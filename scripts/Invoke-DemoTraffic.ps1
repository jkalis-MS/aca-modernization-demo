#requires -Version 7.2
[CmdletBinding()]
param(
    [uri]$ApplicationUrl,
    [ValidateSet('Demo', 'Scale', 'Release', 'Recovery')][string]$Scenario = 'Demo',
    [ValidatePattern('\A[a-z0-9][a-z0-9-]{0,62}\z', Options = 'None')]
    [string]$RunId = "demo-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))-$([Guid]::NewGuid().ToString('N').Substring(0, 8))",
    [ValidateRange(1, 64)][int]$Concurrency,
    [ValidateRange(1, 180)][int]$DurationSeconds,
    [ValidateRange(1, 15000)][int]$MaxRequests,
    [ValidateRange(0, 1000)][double]$RequestsPerSecond,
    [ValidateRange(1, 15)][int]$TimeoutSeconds = 15,
    [ValidateNotNullOrEmpty()][string]$CandidateVersion,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\azure.local.json'),
    [string]$OutputPath,
    [switch]$NoClear,
    [switch]$PassThru
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$boundedRun = $DurationSeconds -gt 0 -or $MaxRequests -gt 0
$required = @()
if (!$PSBoundParameters.ContainsKey('ApplicationUrl')) { $required += 'resources.applicationUrl' }
$releaseChecks = $Scenario -in 'Demo', 'Release'
if ($releaseChecks -and !$PSBoundParameters.ContainsKey('CandidateVersion')) {
    $required += 'demo.candidateVersion'
}
if ($required.Count) {
    $config = & (Join-Path $PSScriptRoot 'Get-AzureLocalConfig.ps1') -ConfigPath $ConfigPath -RequiredSettings $required
    if (!$PSBoundParameters.ContainsKey('ApplicationUrl')) { $ApplicationUrl = [uri]$config.resources.applicationUrl }
    if ($releaseChecks -and !$PSBoundParameters.ContainsKey('CandidateVersion')) {
        $CandidateVersion = $config.demo.candidateVersion
    }
}
if (!$CandidateVersion) { $CandidateVersion = 'not-applicable' }

if (!$ApplicationUrl -or !$ApplicationUrl.IsAbsoluteUri -or
    ($ApplicationUrl.Scheme -ne 'https' -and !($ApplicationUrl.Scheme -eq 'http' -and $ApplicationUrl.IsLoopback)) -or
    $ApplicationUrl.UserInfo -or $ApplicationUrl.Query -or $ApplicationUrl.Fragment -or
    $ApplicationUrl.AbsolutePath -ne '/') {
    throw 'ApplicationUrl must be an absolute HTTPS origin without credentials, path, query, or fragment. HTTP is allowed only for loopback tests.'
}
$token = [Environment]::GetEnvironmentVariable('MUSICSTORE_DEMO_TOKEN')
if ([string]::IsNullOrWhiteSpace($token) -or $token.Length -gt 4096 -or $token -match '[^\x21-\x7e]') {
    throw 'Set MUSICSTORE_DEMO_TOKEN to a nonempty printable ASCII token without whitespace before running traffic.'
}
$defaults = @{
    Demo = @{ Concurrency = 32; RequestsPerSecond = 0 }
    Scale = @{ Concurrency = 32; RequestsPerSecond = 0 }
    Release = @{ Concurrency = 4; RequestsPerSecond = 10 }
    Recovery = @{ Concurrency = 8; RequestsPerSecond = 20 }
}
foreach ($name in 'Concurrency', 'RequestsPerSecond') {
    if (!$PSBoundParameters.ContainsKey($name)) {
        Set-Variable -Name $name -Value $defaults[$Scenario][$name]
    }
}
if ($Scenario -eq 'Release' -and ($RequestsPerSecond -le 0 -or $RequestsPerSecond -gt 10)) {
    throw 'Release requires a nonzero rate of at most 10 requests/second.'
}
if ([double]::IsNaN($RequestsPerSecond) -or [double]::IsInfinity($RequestsPerSecond)) {
    throw 'RequestsPerSecond must be finite.'
}
if ($CandidateVersion.Length -gt 256 -or $CandidateVersion -match '[\r\n]') {
    throw 'CandidateVersion must be a single-line version of at most 256 characters.'
}

$engineSource = @'
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Net.Sockets;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace MusicStoreDemoTraffic
{
    public sealed class Result
    {
        public string Type { get; set; } = "request";
        public DateTime Timestamp { get; set; }
        public string RunId { get; set; }
        public string Scenario { get; set; }
        public int StatusCode { get; set; }
        public string Outcome { get; set; }
        public string ErrorKind { get; set; }
        public double DurationMs { get; set; }
        public string Version { get; set; }
        public string Revision { get; set; }
        public string Replica { get; set; }
        public string Process { get; set; }
        public string RequestId { get; set; }
        public int? ActiveRequests { get; set; }
    }

    public sealed class IdentityCount
    {
        public string Version { get; set; }
        public string Revision { get; set; }
        public string Replica { get; set; }
        public string Process { get; set; }
        public int Count { get; set; }
        public Dictionary<int, int> StatusCounts { get; set; } = new Dictionary<int, int>();
    }

    public sealed class Snapshot
    {
        public int Started { get; set; }
        public int Completed { get; set; }
        public int InFlight { get; set; }
        public int Success { get; set; }
        public int Errors { get; set; }
        public int UnexpectedErrors { get; set; }
        public int ExpectedCandidate503 { get; set; }
        public int Timeouts { get; set; }
        public int Cancellations { get; set; }
        public int RecentCompleted { get; set; }
        public int RecentSuccess { get; set; }
        public int RecentErrors { get; set; }
        public int RecentCandidate503 { get; set; }
        public Dictionary<string, int> FailureCounts { get; set; }
        public double P50Ms { get; set; }
        public double P95Ms { get; set; }
        public IdentityCount[] Identities { get; set; }
        public int OtherIdentityCount { get; set; }
        public string StopReason { get; set; }
        public double ElapsedSeconds { get; set; }
    }

    public sealed class Engine : IDisposable
    {
        private sealed class Attempt { public int Connections; }
        private static readonly HttpRequestOptionsKey<Attempt> AttemptKey = new HttpRequestOptionsKey<Attempt>("DemoAttempt");
        private readonly object gate = new object();
        private readonly HttpClient client;
        private readonly CancellationTokenSource stop = new CancellationTokenSource();
        private readonly Stopwatch clock = new Stopwatch();
        private readonly List<double> latencies = new List<double>(2048);
        private readonly Queue<(double Time, string Outcome)> recent = new Queue<(double, string)>();
        private readonly Dictionary<string, IdentityCount> identities = new Dictionary<string, IdentityCount>();
        private readonly Dictionary<string, int> failureCounts = new Dictionary<string, int>();
        private readonly Uri endpoint;
        private readonly string token, runId, scenario, operation, candidateVersion;
        private readonly bool releaseChecks, boundedRun;
        private readonly int concurrency, duration, maxRequests, timeout;
        private readonly double rate;
        private readonly TextWriter writer;
        private int started, completed, success, unexpectedErrors, expected503, timeouts, cancellations, otherIdentities;
        private string stopReason;

        public Engine(string url, string token, string runId, string scenario, string candidateVersion,
                      int concurrency, int duration, int maxRequests, int timeout, double rate, TextWriter writer)
        {
            endpoint = new Uri(new Uri(url), "/Store/Browse?genre=Rock");
            this.token = token;
            this.runId = runId;
            this.scenario = scenario;
            this.candidateVersion = candidateVersion;
            this.concurrency = concurrency;
            this.duration = duration;
            this.maxRequests = maxRequests;
            this.timeout = timeout;
            this.rate = rate;
            this.writer = writer;
            boundedRun = duration > 0 || maxRequests > 0;
            releaseChecks = scenario == "Demo" || scenario == "Release";
            operation = scenario == "Demo" ? "demo" : scenario == "Scale" ? "scale"
                : scenario == "Release" ? "release-check" : "observe";
            var handler = new SocketsHttpHandler {
                AllowAutoRedirect = false,
                UseCookies = false,
                UseProxy = false,
                MaxConnectionsPerServer = concurrency,
                ConnectTimeout = TimeSpan.FromSeconds(timeout),
                MaxResponseHeadersLength = 16
            };
            // HttpClient otherwise silently replays GETs when a connection ends before response headers.
            // One connection per request plus this per-message guard prevents those hidden retries,
            // without changing global runtime settings or exceeding the fixed connection pool bound.
            handler.ConnectCallback = async (context, cancellation) => {
                Attempt attempt;
                if (!context.InitialRequestMessage.Options.TryGetValue(AttemptKey, out attempt) ||
                    Interlocked.Increment(ref attempt.Connections) != 1)
                    throw new HttpRequestException("Automatic transport replay suppressed.");
                var socket = new Socket(SocketType.Stream, ProtocolType.Tcp) { NoDelay = true };
                try
                {
                    await socket.ConnectAsync(context.DnsEndPoint, cancellation).ConfigureAwait(false);
                    return new NetworkStream(socket, ownsSocket: true);
                }
                catch { socket.Dispose(); throw; }
            };
            client = new HttpClient(handler) { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
        }

        private static string Header(HttpResponseMessage response, string name)
        {
            IEnumerable<string> values;
            if (!response.Headers.TryGetValues(name, out values)) return null;
            var all = values.ToArray();
            if (all.Length != 1 || String.IsNullOrWhiteSpace(all[0]) || all[0].Length > 256) return null;
            return all[0];
        }

        private async Task<Result> SendAsync()
        {
            var timer = Stopwatch.StartNew();
            var result = new Result { Timestamp = DateTime.UtcNow, RunId = runId, Scenario = scenario };
            using (var deadline = CancellationTokenSource.CreateLinkedTokenSource(stop.Token))
            using (var request = new HttpRequestMessage(HttpMethod.Get, endpoint))
            {
                deadline.CancelAfter(TimeSpan.FromSeconds(timeout));
                request.Version = HttpVersion.Version11;
                request.VersionPolicy = HttpVersionPolicy.RequestVersionExact;
                request.Headers.ConnectionClose = true;
                request.Options.Set(AttemptKey, new Attempt());
                request.Headers.Add("X-Demo-Token", token);
                request.Headers.Add("X-Demo-Run-Id", runId);
                request.Headers.Add("X-Demo-Operation", operation);
                try
                {
                    using (var response = await client.SendAsync(request, HttpCompletionOption.ResponseHeadersRead,
                                                               deadline.Token).ConfigureAwait(false))
                    {
                        result.StatusCode = (int)response.StatusCode;
                        result.Version = Header(response, "X-Demo-Version");
                        result.Revision = Header(response, "X-Demo-Revision");
                        result.Replica = Header(response, "X-Demo-Replica");
                        result.Process = Header(response, "X-Demo-Process");
                        result.RequestId = Header(response, "X-Demo-Request-Id");
                        int active;
                        if (Int32.TryParse(Header(response, "X-Demo-Active-Requests"), out active) && active >= 0)
                            result.ActiveRequests = active;
                        bool hasIdentity = result.Version != null && result.Revision != null && result.Replica != null &&
                            result.Process != null && result.RequestId != null && result.ActiveRequests != null;
                        if (result.StatusCode == 401 || result.StatusCode == 403)
                            result.Outcome = "SetupError";
                        else if (!hasIdentity)
                            result.Outcome = result.StatusCode == 408 || result.StatusCode == 429 ||
                                (result.StatusCode >= 500 && result.StatusCode <= 599) ? "HttpError" : "SetupError";
                        else if (response.IsSuccessStatusCode)
                            result.Outcome = "Success";
                        else if (releaseChecks && result.StatusCode == 503 &&
                                 String.Equals(result.Version, candidateVersion, StringComparison.Ordinal))
                            result.Outcome = "ExpectedCandidate503";
                        else
                            result.Outcome = "HttpError";
                        // Drain only a bounded body to measure the complete HTTP operation.
                        // Headers (including 503 identity) survive body errors and cancellation.
                        if (result.Outcome != "SetupError")
                        using (var body = await response.Content.ReadAsStreamAsync(deadline.Token).ConfigureAwait(false))
                        {
                            var buffer = new byte[8192];
                            int total = 0, read;
                            while (total <= 1048576 &&
                                   (read = await body.ReadAsync(buffer, 0, buffer.Length, deadline.Token).ConfigureAwait(false)) > 0)
                                total += read;
                        }
                    }
                }
                catch (OperationCanceledException)
                {
                    if (result.Outcome != "SetupError")
                        result.Outcome = stop.IsCancellationRequested ? "Cancelled" : "Timeout";
                }
                catch (HttpRequestException error)
                {
                    result.ErrorKind = error.GetBaseException().GetType().Name;
                    if (result.Outcome != "SetupError")
                        result.Outcome = stop.IsCancellationRequested ? "Cancelled"
                            : deadline.IsCancellationRequested ? "Timeout" : "TransportError";
                }
                catch (IOException error)
                {
                    result.ErrorKind = error.GetBaseException().GetType().Name;
                    if (result.Outcome != "SetupError")
                        result.Outcome = stop.IsCancellationRequested ? "Cancelled"
                            : deadline.IsCancellationRequested ? "Timeout" : "TransportError";
                }
            }
            result.DurationMs = Math.Round(timer.Elapsed.TotalMilliseconds, 2);
            return result;
        }

        private void Record(Result result)
        {
            lock (gate)
            {
                completed++;
                if (releaseChecks && result.Outcome != "Cancelled")
                    recent.Enqueue((clock.Elapsed.TotalSeconds, result.Outcome));
                TrimRecent();
                if (latencies.Count < 2048) latencies.Add(result.DurationMs);
                else latencies[(completed - 1) % 2048] = result.DurationMs;
                switch (result.Outcome)
                {
                    case "Success": success++; break;
                    case "ExpectedCandidate503": expected503++; break;
                    case "Cancelled": cancellations++; break;
                    default:
                        unexpectedErrors++;
                        string failure = result.Outcome + " | HTTP " +
                            (result.StatusCode == 0 ? "no response" : result.StatusCode.ToString()) +
                            (result.ErrorKind == null ? "" : " | " + result.ErrorKind);
                        int failureCount;
                        failureCounts.TryGetValue(failure, out failureCount);
                        failureCounts[failure] = failureCount + 1;
                        break;
                }
                if (result.Outcome == "Timeout") timeouts++;
                if (result.Version != null && result.Revision != null && result.Replica != null && result.Process != null)
                {
                    string key = String.Join("\u001f", result.Version, result.Revision, result.Replica, result.Process);
                    IdentityCount count;
                    if (!identities.TryGetValue(key, out count))
                    {
                        if (identities.Count < 256)
                        {
                            count = new IdentityCount { Version = result.Version, Revision = result.Revision,
                                Replica = result.Replica, Process = result.Process };
                            identities.Add(key, count);
                        }
                        else otherIdentities++;
                    }
                    if (count != null)
                    {
                        count.Count++;
                        int statusCount;
                        count.StatusCounts.TryGetValue(result.StatusCode, out statusCount);
                        count.StatusCounts[result.StatusCode] = statusCount + 1;
                    }
                }
                if (result.Outcome == "SetupError")
                    stopReason = "Setup failure: authentication rejected or required demo identity headers missing/invalid.";
                else if (boundedRun && stopReason == null && completed >= 50 && (double)unexpectedErrors / completed > 0.02)
                    stopReason = "Safety stop: unexpected HTTP/transport errors exceeded 2% after at least 50 completed requests.";
                if (stopReason != null) stop.Cancel();
            }
            if (writer != null) writer.WriteLine(JsonSerializer.Serialize(result));
        }

        public async Task<Snapshot> RunAsync()
        {
            clock.Start();
            if (duration > 0) stop.CancelAfter(TimeSpan.FromSeconds(duration));
            var pending = new List<Task<Result>>(concurrency);
            double nextStart = 0;
            try
            {
                while (true)
                {
                    foreach (var task in pending.Where(t => t.IsCompleted).ToArray())
                    {
                        pending.Remove(task);
                        Record(await task.ConfigureAwait(false));
                    }
                    while (!stop.IsCancellationRequested && (duration == 0 || clock.Elapsed.TotalSeconds < duration) &&
                           (maxRequests == 0 || started < maxRequests) &&
                           pending.Count < concurrency && clock.Elapsed.TotalSeconds >= nextStart)
                    {
                        lock (gate) started++;
                        pending.Add(SendAsync());
                        if (rate > 0) nextStart = clock.Elapsed.TotalSeconds + 1.0 / rate;
                    }
                    if (pending.Count == 0 && (stop.IsCancellationRequested || (maxRequests > 0 && started >= maxRequests))) break;
                    double waitMs = rate > 0 && pending.Count < concurrency
                        ? Math.Max(1, Math.Min(25, (nextStart - clock.Elapsed.TotalSeconds) * 1000)) : 25;
                    var wake = Task.Delay((int)waitMs);
                    if (pending.Count > 0)
                        await Task.WhenAny(pending.Cast<Task>().Append(wake)).ConfigureAwait(false);
                    else
                        await wake.ConfigureAwait(false);
                }
            }
            finally
            {
                stop.Cancel();
                // Cancellation is also awaited on writer/runtime errors: no owned HTTP task is abandoned.
                await Task.WhenAll(pending).ConfigureAwait(false);
                clock.Stop();
            }
            return GetSnapshot();
        }

        private void TrimRecent()
        {
            double cutoff = clock.Elapsed.TotalSeconds - 10;
            while (recent.Count > 0 && recent.Peek().Time <= cutoff) recent.Dequeue();
        }

        public Snapshot GetSnapshot()
        {
            lock (gate)
            {
                TrimRecent();
                var samples = latencies.OrderBy(x => x).ToArray();
                return new Snapshot {
                    Started = started, Completed = completed, InFlight = started - completed, Success = success,
                    Errors = unexpectedErrors + expected503, UnexpectedErrors = unexpectedErrors,
                    ExpectedCandidate503 = expected503, Timeouts = timeouts, Cancellations = cancellations,
                    RecentCompleted = recent.Count, RecentSuccess = recent.Count(x => x.Outcome == "Success"),
                    RecentErrors = recent.Count(x => x.Outcome != "Success"),
                    RecentCandidate503 = recent.Count(x => x.Outcome == "ExpectedCandidate503"),
                    FailureCounts = new Dictionary<string, int>(failureCounts),
                    P50Ms = samples.Length == 0 ? 0 : samples[(int)Math.Ceiling(samples.Length * 0.50) - 1],
                    P95Ms = samples.Length == 0 ? 0 : samples[(int)Math.Ceiling(samples.Length * 0.95) - 1],
                    Identities = identities.Values.Select(x => new IdentityCount { Version = x.Version,
                        Revision = x.Revision, Replica = x.Replica, Process = x.Process, Count = x.Count,
                        StatusCounts = new Dictionary<int, int>(x.StatusCounts) }).ToArray(),
                    OtherIdentityCount = otherIdentities, StopReason = stopReason, ElapsedSeconds = clock.Elapsed.TotalSeconds
                };
            }
        }

        public void Cancel() { stop.Cancel(); }
        public void Dispose() { stop.Cancel(); client.Dispose(); stop.Dispose(); }
    }
}
'@
# PowerShell cannot replace loaded types; isolate each engine source version.
$engineHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($engineSource)))
$engineNamespace = "MusicStoreDemoTraffic_$engineHash"
$engineType = "$engineNamespace.Engine" -as [type]
if (!$engineType) {
    $engineSource = $engineSource.Replace('namespace MusicStoreDemoTraffic', "namespace $engineNamespace")
    $engineType = Add-Type -TypeDefinition $engineSource -PassThru | Where-Object Name -EQ 'Engine'
}

$refreshScreen = !$NoClear -and $VerbosePreference -ne 'Continue' -and
    ![Console]::IsOutputRedirected -and $Host.Name -eq 'ConsoleHost'

function Show-TrafficStatus {
    param($Snapshot, [switch]$Finished)
    if ($refreshScreen) { Clear-Host }
    $state = if ($Snapshot.StopReason) { 'STOPPED' } elseif ($Finished) { 'FINISHED' } else { 'RUNNING' }
    $color = if ($Snapshot.UnexpectedErrors -or $Snapshot.StopReason) { 'Red' } elseif (
        ($releaseChecks -and (!$Snapshot.RecentCompleted -or $Snapshot.RecentErrors)) -or
        (!$releaseChecks -and $Snapshot.Errors)) { 'Yellow' } else { 'Green' }
    $rate = if ($Snapshot.ElapsedSeconds -gt 0) { $Snapshot.Completed / $Snapshot.ElapsedSeconds } else { 0 }
    $replicaCount = @($Snapshot.Identities | Select-Object -ExpandProperty Replica -Unique).Count
    Write-Host ''
    $trafficLabel = if ($Scenario -eq 'Demo') { 'LIVE TRAFFIC' } else { $Scenario.ToUpperInvariant() }
    Write-Host "  MUSIC STORE | $trafficLabel | $state" -ForegroundColor Cyan
    $durationLabel = if ($DurationSeconds) { "/${DurationSeconds}s" } else { 's | Until Ctrl+C' }
    $requestLabel = if ($MaxRequests) { '{0:N0} requests' -f $MaxRequests } else { 'No request cap' }
    Write-Host ('  Elapsed {0:N0}{1} | {2} | Concurrency {3}' -f
        $Snapshot.ElapsedSeconds, $durationLabel, $requestLabel, $Concurrency)
    Write-Host ''
    Write-Host ('  IN FLIGHT {0}   |   RESPONDING REPLICAS {1}   |   AVG {2:N1}/s' -f
        $Snapshot.InFlight, $replicaCount, $rate) -ForegroundColor $color
    $latencyLabel = if ($Scenario -notin 'Demo', 'Scale' -or $VerbosePreference -eq 'Continue') {
        '   |   LATENCY p50 {0:N0}ms / p95 {1:N0}ms' -f $Snapshot.P50Ms, $Snapshot.P95Ms
    } else { '' }
    $totalLabel = if ($releaseChecks) { 'TOTAL ' } else { '' }
    Write-Host (('  {0}SUCCESS {1:N0}   |   ERRORS {2:N0}' -f
        $totalLabel, $Snapshot.Success, $Snapshot.Errors) + $latencyLabel) -ForegroundColor $color
    $showReleaseStatus = $Scenario -eq 'Release' -or ($Scenario -eq 'Demo' -and $Snapshot.Errors -gt 0)
    if ($showReleaseStatus) {
        Write-Host ('  LAST 10s | SUCCESS {0:N0} | ERRORS {1:N0}' -f
            $Snapshot.RecentSuccess, $Snapshot.RecentErrors) -ForegroundColor $color
        if (!$Snapshot.RecentCompleted) { Write-Host '  No completed responses in the last 10s.' -ForegroundColor Yellow }
    }
    if ($Snapshot.UnexpectedErrors -or $Snapshot.Timeouts -or $VerbosePreference -eq 'Continue') {
        Write-Host ('  Unexpected {0} | Timeouts {1} | Cancelled {2}' -f
            $Snapshot.UnexpectedErrors, $Snapshot.Timeouts, $Snapshot.Cancellations)
    }
    foreach ($failure in ($Snapshot.FailureCounts.GetEnumerator() | Sort-Object Key)) {
        Write-Host "  FAILURE $($failure.Value): $($failure.Key)" -ForegroundColor Red
    }
    Write-Host ''
    $identities = @($Snapshot.Identities | Sort-Object Count -Descending)
    $statusCodes = @($identities | ForEach-Object { $_.StatusCounts.Keys } | Sort-Object -Unique)
    $tableHeader = '  {0,-20} {1,-22} {2,-8} {3,8}' -f 'VERSION', 'INSTANCE', 'PROCESS', 'REQUESTS'
    foreach ($status in $statusCodes) { $tableHeader += ' {0,8}' -f "HTTP $status" }
    Write-Host $tableHeader
    foreach ($identity in ($identities | Select-Object -First 8)) {
        $instance = if ($identity.Replica.StartsWith("$($identity.Revision)-")) {
            $identity.Replica.Substring($identity.Revision.Length + 1)
        } else { $identity.Replica }
        $shortVersion = if ($identity.Version.Length -gt 20) { $identity.Version.Substring(0, 17) + '...' } else { $identity.Version }
        $shortInstance = if ($instance.Length -gt 22) { '...' + $instance.Substring($instance.Length - 19) } else { $instance }
        $shortProcess = $identity.Process.Substring(0, [Math]::Min(8, $identity.Process.Length))
        $tableRow = '  {0,-20} {1,-22} {2,-8} {3,8:N0}' -f $shortVersion, $shortInstance, $shortProcess, $identity.Count
        foreach ($status in $statusCodes) {
            $statusCount = if ($identity.StatusCounts.ContainsKey([int]$status)) { $identity.StatusCounts[[int]$status] } else { 0 }
            $tableRow += ' {0,8:N0}' -f $statusCount
        }
        $rowColor = if (@($identity.StatusCounts.Keys | Where-Object { $_ -ge 400 }).Count) { 'Red' } elseif (
            @($identity.StatusCounts.Keys | Where-Object { $_ -ge 300 }).Count) { 'Yellow' } else { 'Green' }
        Write-Host $tableRow -ForegroundColor $rowColor
    }
    if (!$identities.Count) { Write-Host '  Waiting for authenticated responses...' -ForegroundColor DarkGray }
    if ($identities.Count -gt 8) { Write-Host "  + $($identities.Count - 8) more process identities (see -Verbose / JSONL)" }
    if ($Snapshot.OtherIdentityCount) { Write-Host "  Additional requests beyond 256 identity limit: $($Snapshot.OtherIdentityCount)" -ForegroundColor Yellow }
    Write-Host ''
    Write-Verbose 'Counts cumulative; latency uses last 2048 completions.'
    Write-Verbose 'Requests cancelled when stopping are not counted as errors.'
    Write-Verbose 'Instances above have responded; this is not current replica readiness.'
    if ($Snapshot.StopReason) { Write-Host "  $($Snapshot.StopReason)" -ForegroundColor Red }
    Write-Host "  Updated $(Get-Date -Format HH:mm:ss) | Ctrl+C to stop" -ForegroundColor DarkGray
    foreach ($identity in $Snapshot.Identities) {
        Write-Verbose ("version={0} revision={1} replica={2} process={3} requests={4}" -f
            $identity.Version, $identity.Revision, $identity.Replica, $identity.Process, $identity.Count)
    }
}

$writer = $null
$engine = $null
$task = $null
try {
    if ($OutputPath) {
        $fullOutputPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutputPath)
        $stream = [IO.File]::Open($fullOutputPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::Read)
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
        $writer.AutoFlush = $true
    }
    $engine = $engineType::new($ApplicationUrl.AbsoluteUri, $token, $RunId, $Scenario,
        $CandidateVersion, $Concurrency, $DurationSeconds, $MaxRequests, $TimeoutSeconds, $RequestsPerSecond, $writer)
    $token = $null
    Write-Verbose "GET $($ApplicationUrl.GetLeftPart([UriPartial]::Authority))/Store/Browse?genre=Rock scenario=$Scenario run=$RunId"
    Write-Verbose "Bounds: concurrency=$Concurrency duration=${DurationSeconds}s requests=$MaxRequests rate=$RequestsPerSecond/s timeout=${TimeoutSeconds}s; no retries, redirects, cookies, proxy, or Azure mutations."
    Write-Verbose 'HTTP/1.1 connections close after each request; a connection-attempt guard prevents hidden transport retries.'
    Write-Host "Starting $Scenario traffic (Ctrl+C to stop; no Azure resource changes)..."
    $task = $engine.RunAsync()
    Show-TrafficStatus $engine.GetSnapshot()
    $nextStatus = [DateTime]::UtcNow.AddSeconds(5)
    while (!$task.IsCompleted) {
        Start-Sleep -Milliseconds 100
        if ([DateTime]::UtcNow -ge $nextStatus) {
            Show-TrafficStatus $engine.GetSnapshot()
            $nextStatus = [DateTime]::UtcNow.AddSeconds(5)
        }
    }
    $summary = $task.GetAwaiter().GetResult()
    Show-TrafficStatus $summary -Finished
    if ($summary.StopReason) { throw $summary.StopReason }
    if ($boundedRun -and $summary.UnexpectedErrors -gt 0) {
        $failures = ($summary.FailureCounts.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Value)x $($_.Key)" }) -join '; '
        $details = if ($OutputPath) { "Request details: $fullOutputPath" } else { 'Use -OutputPath with a new JSONL filename on the next run to retain per-request evidence.' }
        throw "Traffic completed with $($summary.UnexpectedErrors) unexpected errors: $failures. $details"
    }
    if ($boundedRun -and ($summary.Success + $summary.ExpectedCandidate503 -eq 0)) { throw 'No complete, authenticated demo response was received within the run bounds.' }
    if ($PassThru) { $summary }
}
finally {
    $token = $null
    try {
        if ($engine) {
            $engine.Cancel()
            try {
                if ($task -and !$task.IsCompleted) { $null = $task.GetAwaiter().GetResult() }
            }
            finally { $engine.Dispose() }
        }
    }
    finally { if ($writer) { $writer.Dispose() } }
}
