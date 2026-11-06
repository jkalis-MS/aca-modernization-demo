#requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$trafficScript = Join-Path $PSScriptRoot 'Invoke-DemoTraffic.ps1'
$watchScript = Join-Path $PSScriptRoot 'Watch-Demo.ps1'
$work = Join-Path $PSScriptRoot ".demo-utilities-test-$([Guid]::NewGuid().ToString('N'))"
$originalToken = $env:MUSICSTORE_DEMO_TOKEN
$originalPath = $env:PATH
$originalMockMode = $env:DEMO_AZ_TEST_MODE
$originalMockLog = $env:DEMO_AZ_TEST_LOG
$server = $null

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw "Assertion failed: $Message" }
}

function Assert-Fails {
    param([scriptblock]$Action, [string]$Pattern)
    $message = $null
    try { $null = & $Action } catch { $message = $_.Exception.Message }
    Assert-True ($null -ne $message -and $message -match $Pattern) "Expected failure matching '$Pattern'; got '$message'."
}

if (!('DemoUtilitiesTests.Server' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;
using System.Threading.Tasks;

namespace DemoUtilitiesTests
{
    public sealed class Request
    {
        public DateTime Timestamp { get; set; }
        public string Line { get; set; }
        public Dictionary<string, string> Headers { get; set; }
    }

    public sealed class Server : IDisposable
    {
        private readonly TcpListener listener = new TcpListener(IPAddress.Loopback, 0);
        private readonly CancellationTokenSource stop = new CancellationTokenSource();
        private readonly ConcurrentBag<Task> clients = new ConcurrentBag<Task>();
        private Task loop;
        private int active, maxActive;
        public readonly ConcurrentQueue<Request> Requests = new ConcurrentQueue<Request>();
        public string Mode { get; set; } = "success";
        public int DelayMs { get; set; } = 100;
        public int SetupFailureAfter { get; set; }
        public int Port { get; private set; }
        public int MaxActive { get { return maxActive; } }

        public Server()
        {
            listener.Start();
            Port = ((IPEndPoint)listener.LocalEndpoint).Port;
            loop = AcceptAsync();
        }

        private async Task AcceptAsync()
        {
            try
            {
                while (!stop.IsCancellationRequested)
                {
                    var client = await listener.AcceptTcpClientAsync().ConfigureAwait(false);
                    clients.Add(ServeAsync(client));
                }
            }
            catch (SocketException) when (stop.IsCancellationRequested) { }
            catch (ObjectDisposedException) when (stop.IsCancellationRequested) { }
        }

        private async Task ServeAsync(TcpClient client)
        {
            using (client)
            {
                int current = Interlocked.Increment(ref active);
                int previous;
                do { previous = maxActive; if (previous >= current) break; }
                while (Interlocked.CompareExchange(ref maxActive, current, previous) != previous);
                try
                {
                    var stream = client.GetStream();
                    using (var reader = new StreamReader(stream, Encoding.ASCII, false, 1024, true))
                    {
                        string line = await reader.ReadLineAsync().ConfigureAwait(false);
                        if (line == null) return;
                        var headers = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
                        string header;
                        while (!String.IsNullOrEmpty(header = await reader.ReadLineAsync().ConfigureAwait(false)))
                        {
                            int colon = header.IndexOf(':');
                            if (colon > 0) headers[header.Substring(0, colon)] = header.Substring(colon + 1).Trim();
                        }
                        Requests.Enqueue(new Request { Line = line, Headers = headers, Timestamp = DateTime.UtcNow });
                        string mode = Mode;
                        if (SetupFailureAfter > 0 && Requests.Count >= SetupFailureAfter) mode = "missing";
                        await Task.Delay(DelayMs, stop.Token).ConfigureAwait(false);
                        if (mode == "disconnect") return;
                        int status = mode == "candidate" || mode == "stable503" || mode == "gateway503" ||
                            ((mode == "mixed" || mode == "split") && Requests.Count % 2 == 0) ? 503
                            : mode == "gateway500" ? 500 : mode == "gateway429" ? 429
                            : mode == "gateway408" ? 408 : mode == "unauthorized" ? 401
                            : mode == "forbidden" ? 403 : mode == "redirect" ? 302 : 200;
                        var response = new StringBuilder("HTTP/1.1 " + status + " Test\r\nConnection: close\r\nContent-Length: 2\r\n");
                        if (mode == "redirect") response.Append("Location: http://127.0.0.1:" + Port + "/must-not-follow\r\n");
                        if (mode != "missing" && !mode.StartsWith("gateway", StringComparison.Ordinal))
                        {
                            response.Append("X-Demo-Version: " + (mode == "candidate" ||
                                (mode == "split" && status == 503) ? "candidate" : "stable") + "\r\n");
                            response.Append("X-Demo-Revision: revision-test\r\nX-Demo-Replica: replica-test\r\n");
                            response.Append("X-Demo-Process: process-test\r\nX-Demo-Request-Id: " + Guid.NewGuid().ToString("N") + "\r\n");
                            response.Append("X-Demo-Active-Requests: " + current + "\r\n");
                            response.Append("Set-Cookie: test-cookie=must-not-send\r\n");
                        }
                        response.Append("\r\nOK");
                        byte[] bytes = Encoding.ASCII.GetBytes(response.ToString());
                        await stream.WriteAsync(bytes, 0, bytes.Length, stop.Token).ConfigureAwait(false);
                    }
                }
                catch (IOException) { } // The traffic client intentionally cancels in timeout tests.
                catch (OperationCanceledException) when (stop.IsCancellationRequested) { }
                finally { Interlocked.Decrement(ref active); }
            }
        }

        public void Dispose()
        {
            stop.Cancel();
            listener.Stop();
            loop.GetAwaiter().GetResult();
            Task.WhenAll(clients.ToArray()).GetAwaiter().GetResult();
            stop.Dispose();
        }
    }
}
'@
}

try {
    $null = New-Item -ItemType Directory -Path $work
    $env:MUSICSTORE_DEMO_TOKEN = 'only-a-local-test-token'
    $server = [DemoUtilitiesTests.Server]::new()
    $url = "http://127.0.0.1:$($server.Port)"
    $trafficConfigPath = Join-Path $work 'traffic.local.json'
    @{
        schemaVersion = 1
        deployment = @{subscriptionId='11111111-1111-4111-8111-111111111111'}
        resources = @{applicationUrl=$url}
        demo = @{candidateVersion='candidate'}
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $trafficConfigPath
    $results = Join-Path $work 'scale.jsonl'
    if (!('MusicStoreDemoTraffic.Engine' -as [type])) {
        Add-Type -TypeDefinition 'namespace MusicStoreDemoTraffic { public sealed class Engine {} public sealed class Snapshot {} }'
    }
    $displayOutput = @(& $trafficScript -ApplicationUrl $url -Scenario Scale -RunId local-test `
        -Concurrency 4 -DurationSeconds 10 -MaxRequests 12 -OutputPath $results -PassThru -NoClear 6>&1)
    $summary = $displayOutput | Where-Object { $_.GetType().Name -eq 'Snapshot' }
    Assert-True ($summary.GetType().Namespace -like 'MusicStoreDemoTraffic_*') 'Traffic isolates the current engine from stale types already loaded in the terminal.'
    $engineType = $summary.GetType().Assembly.GetType("$($summary.GetType().Namespace).Engine")
    $screen = ($displayOutput | Where-Object { $_ -is [System.Management.Automation.InformationRecord] }) -join "`n"
    Assert-True ($screen -match 'MUSIC STORE \| SCALE \| FINISHED') 'Traffic has a compact final screen.'
    Assert-True ($screen -match 'RESPONDING REPLICAS 1' -and $screen -match 'SUCCESS 12') 'Traffic displays response identity counts and successes.'
    Assert-True ($screen -notmatch 'LATENCY|p50|p95') 'Default scaling display omits latency.'
    Assert-True ($summary.P50Ms -gt 0 -and $summary.P95Ms -ge $summary.P50Ms) 'Scaling still measures latency in the structured summary.'
    Assert-True ($screen -notmatch 'Bounds:|version=|process=') 'Default traffic display omits verbose details.'
    Assert-True ($screen -notmatch 'Unexpected|Candidate 503s|Timeouts|Cancelled|Counts cumulative|Requests cancelled|Instances above') 'Successful scaling display omits diagnostic counters and explanatory footer notes.'
    Assert-True ($summary.Success -eq 12 -and $summary.InFlight -eq 0) 'All bounded requests finish.'
    Assert-True ($screen -match 'HTTP 200' -and $summary.Identities[0].StatusCounts[200] -eq 12) 'Each replica/process row counts its successful HTTP responses.'
    Assert-True ($server.MaxActive -ge 2 -and $server.MaxActive -le 4) 'Requests execute concurrently within the connection bound.'
    $records = @(Get-Content $results | ConvertFrom-Json)
    Assert-True ($records.Count -eq 12 -and $records[0].Replica -eq 'replica-test') 'JSONL includes request identity.'
    Assert-True ((Get-Content $results -Raw) -notmatch 'only-a-local-test-token|X-Demo-Token') 'JSONL never includes the token.'
    foreach ($request in $server.Requests.ToArray()) {
        Assert-True ($request.Line -eq 'GET /Store/Browse?genre=Rock HTTP/1.1') 'Only the fixed browse endpoint and HTTP/1.1 are used.'
        Assert-True ($request.Headers['X-Demo-Operation'] -eq 'scale') 'Scale operation header.'
        Assert-True ($request.Headers['X-Demo-Token'] -eq $env:MUSICSTORE_DEMO_TOKEN) 'Token supplied via environment.'
        Assert-True ($request.Headers['X-Demo-Run-Id'] -eq 'local-test') 'Run ID header.'
        Assert-True (!$request.Headers.ContainsKey('Cookie')) 'No cookies are replayed.'
    }
    $verboseScreen = (& $trafficScript -ApplicationUrl $url -Scenario Scale -Concurrency 1 `
        -DurationSeconds 5 -MaxRequests 1 -Verbose -NoClear 4>&1 6>&1 | Out-String)
    Assert-True ($verboseScreen -match 'Unexpected 0 \| Timeouts 0 \| Cancelled 0' -and
        $verboseScreen -match 'Counts cumulative' -and $verboseScreen -match 'Requests cancelled' -and
        $verboseScreen -match 'Instances above') 'Verbose preserves diagnostic counters and explanatory footer notes.'
    Assert-True ($verboseScreen -notmatch 'Candidate 503s') 'Scaling does not display release-only counters even in verbose mode.'
    Assert-True ($verboseScreen -match 'LATENCY p50 \d+ms / p95 \d+ms') 'Verbose scaling displays latency.'
    $before = $server.Requests.Count
    $demoOutput = @(& $trafficScript -ConfigPath $trafficConfigPath -DurationSeconds 5 -MaxRequests 12 -PassThru -NoClear 6>&1)
    $demoSummary = $demoOutput | Where-Object { $_.GetType().Name -eq 'Snapshot' }
    $demoScreen = $demoOutput -join "`n"
    Assert-True ($demoScreen -match 'MUSIC STORE \| LIVE TRAFFIC \| FINISHED' -and
        $demoScreen -match 'Concurrency 32') 'No Scenario argument starts the unified 32-concurrency presenter workload.'
    Assert-True ($demoSummary.Success -eq 12 -and $demoScreen -notmatch 'LATENCY|Candidate 503s|LAST 10s') 'Healthy unified traffic keeps the scaling display clean.'
    $demoRequests = @($server.Requests.ToArray() | Select-Object -Skip $before)
    Assert-True (@($demoRequests | Where-Object { $_.Headers['X-Demo-Operation'] -ne 'demo' }).Count -eq 0) 'Unified traffic always sends the same combined operation.'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale -OutputPath $results } 'already exists'
    Assert-Fails { & $trafficScript -ApplicationUrl 'http://example.com' -Scenario Scale } 'HTTPS origin'
    Assert-Fails { & $trafficScript -ApplicationUrl "$url/unexpected" -Scenario Scale } 'HTTPS origin'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale -Concurrency 65 } 'validat'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale -DurationSeconds 181 } 'validat'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale -MaxRequests 15001 } 'validat'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale -TimeoutSeconds 16 } 'validat'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale -RunId 'bad/run' } 'validat'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale -RunId "bad`n" } 'validat'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale -RunId 'UPPERCASE' } 'validat'
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Release -CandidateVersion candidate -RequestsPerSecond 11 } 'at most 10'
    $env:MUSICSTORE_DEMO_TOKEN = ''
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale } 'MUSICSTORE_DEMO_TOKEN'
    $env:MUSICSTORE_DEMO_TOKEN = "secret`r`nheader"
    Assert-Fails { & $trafficScript -ApplicationUrl $url -Scenario Scale } 'MUSICSTORE_DEMO_TOKEN'
    $env:MUSICSTORE_DEMO_TOKEN = 'only-a-local-test-token'

    $server.Mode = 'candidate'
    $before = $server.Requests.Count
    $releaseOutput = @(& $trafficScript -ConfigPath $trafficConfigPath -Scenario Release -Concurrency 4 -DurationSeconds 10 -MaxRequests 55 -PassThru 6>&1)
    $summary = $releaseOutput | Where-Object { $_.GetType().Name -eq 'Snapshot' }
    Assert-True (($releaseOutput -join "`n") -match 'HTTP 503' -and
        ($releaseOutput -join "`n") -match '(?m)^\s+candidate\s+replica-test\s+\S+\s+55\s+55\s*$') 'The candidate row displays all 55 responses under HTTP 503.'
    Assert-True ($summary.Identities[0].StatusCounts[503] -eq 55) 'Candidate HTTP status totals are retained in the structured snapshot.'
    Assert-True (($releaseOutput -join "`n") -notmatch 'Candidate 503s') 'The status table replaces separate candidate-specific labels.'
    Assert-True (($releaseOutput -join "`n") -notmatch 'Expected regression:') 'Traffic omits the regression explanation label.'
    Assert-True (($releaseOutput -join "`n") -match 'LATENCY p50') 'Release latency remains visible by default.'
    Assert-True ($summary.ExpectedCandidate503 -eq 55 -and $summary.Errors -eq 55 -and $summary.UnexpectedErrors -eq 0) 'Expected candidate 503s remain visible as errors without triggering the >=50-request safety stop.'
    $release = @($server.Requests.ToArray() | Select-Object -Skip $before)
    for ($i = 1; $i -lt $release.Count; $i++) {
        Assert-True (($release[$i].Timestamp - $release[$i - 1].Timestamp).TotalMilliseconds -ge 85) 'Release rate is bounded at 10/s without catch-up bursts.'
    }
    Assert-True ($release[0].Headers['X-Demo-Operation'] -eq 'release-check') 'Release operation header.'

    $server.Mode = 'success'
    $releaseEngine = $engineType::new(
        $url, $env:MUSICSTORE_DEMO_TOKEN, 'rollback-test', 'Demo', 'candidate',
        32, 0, 0, 5, 50, $null)
    try {
        $releaseTask = $releaseEngine.RunAsync()
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while ($releaseEngine.GetSnapshot().Success -eq 0 -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        Assert-True ($releaseEngine.GetSnapshot().RecentSuccess -gt 0 -and
            $releaseEngine.GetSnapshot().RecentErrors -eq 0) 'One combined scaling/release run begins with a healthy baseline.'
        $server.Mode = 'candidate'
        $deadline = [DateTime]::UtcNow.AddSeconds(5)
        while ($releaseEngine.GetSnapshot().ExpectedCandidate503 -eq 0 -and [DateTime]::UtcNow -lt $deadline) {
            Start-Sleep -Milliseconds 50
        }
        $exposed = $releaseEngine.GetSnapshot()
        Assert-True ($exposed.RecentCandidate503 -gt 0 -and $exposed.RecentErrors -gt 0 -and
            !$releaseTask.IsCompleted) 'Candidate exposure produces recent errors without restarting or stopping traffic.'
        $server.Mode = 'success'
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            Start-Sleep -Milliseconds 100
            $rolledBack = $releaseEngine.GetSnapshot()
        } while (($rolledBack.RecentErrors -gt 0 -or $rolledBack.RecentSuccess -eq 0) -and
            [DateTime]::UtcNow -lt $deadline)
        Assert-True ($rolledBack.RecentErrors -eq 0 -and $rolledBack.RecentCandidate503 -eq 0 -and
            $rolledBack.RecentSuccess -gt 0 -and !$releaseTask.IsCompleted) 'Rollback clears recent errors while the same process continues serving successful responses.'
        Assert-True ($rolledBack.ExpectedCandidate503 -ge $exposed.ExpectedCandidate503 -and
            $rolledBack.Errors -gt 0 -and $rolledBack.Identities.Count -eq 2) 'Rollback preserves historical errors and both version identities.'
        $healthyIdentity = $rolledBack.Identities | Where-Object Version -eq 'stable'
        $candidateIdentity = $rolledBack.Identities | Where-Object Version -eq 'candidate'
        Assert-True ($healthyIdentity.StatusCounts[200] -gt 0 -and $candidateIdentity.StatusCounts[503] -gt 0) 'Mixed-version traffic attributes HTTP 200 and 503 counts to the correct rows.'
        Assert-True ($rolledBack.UnexpectedErrors -eq 0) 'Expected candidate errors never trigger the unexpected-error safety stop.'
    }
    finally {
        $releaseEngine.Cancel()
        $null = $releaseTask.GetAwaiter().GetResult()
        $releaseEngine.Dispose()
    }

    $server.Mode = 'split'
    $splitOutput = @(& $trafficScript -ApplicationUrl $url -CandidateVersion candidate -Concurrency 1 `
        -DurationSeconds 5 -MaxRequests 12 -NoClear -PassThru 6>&1)
    $splitScreen = $splitOutput -join "`n"
    Assert-True ($splitScreen -match 'HTTP 200\s+HTTP 503' -and
        $splitScreen -match '(?m)^\s+stable\s+replica-test\s+\S+\s+6\s+6\s+0\s*$' -and
        $splitScreen -match '(?m)^\s+candidate\s+replica-test\s+\S+\s+6\s+0\s+6\s*$') 'The display aligns HTTP 200/503 columns and shows zero for statuses absent from each row.'
    $server.Mode = 'mixed'
    $statusEngine = $engineType::new(
        $url, $env:MUSICSTORE_DEMO_TOKEN, 'status-counts-test', 'Demo', 'stable',
        1, 5, 12, 5, 10, $null)
    try {
        $statusTask = $statusEngine.RunAsync()
        $statusSummary = $statusTask.GetAwaiter().GetResult()
        $identity = $statusSummary.Identities[0]
        Assert-True ($statusSummary.Identities.Count -eq 1 -and $identity.Count -eq 12 -and
            $identity.StatusCounts[200] -eq 6 -and $identity.StatusCounts[503] -eq 6) 'Different HTTP statuses aggregate into columns on the same replica/process row.'
        $identity.StatusCounts[200] = 999
        Assert-True ($statusEngine.GetSnapshot().Identities[0].StatusCounts[200] -eq 6) 'Snapshot status dictionaries are independent copies of engine state.'
    }
    finally { $statusEngine.Dispose() }

    $server.Mode = 'stable503'
    $server.DelayMs = 0
    $safetyPath = Join-Path $work 'safety.jsonl'
    $failureScreen = [Collections.Generic.List[string]]::new()
    Assert-Fails {
        & $trafficScript -ApplicationUrl $url -Scenario Scale -Concurrency 4 -DurationSeconds 10 -MaxRequests 100 -OutputPath $safetyPath 6>&1 |
            ForEach-Object { $failureScreen.Add([string]$_) }
    } 'Safety stop'
    Assert-True (($failureScreen -join "`n") -match 'Unexpected [1-9]' -and
        ($failureScreen -join "`n") -match 'FAILURE .*HttpError \| HTTP 503') 'Unexpected scaling failures show diagnostic counters and the failure category/status.'
    $safety = @(Get-Content $safetyPath | ConvertFrom-Json)
    Assert-True ($safety.Count -ge 50 -and $safety.Count -lt 100) 'Safety stop occurs after the sample threshold and before the request limit.'
    Assert-True ($safety[0].StatusCode -eq 503 -and $safety[0].Replica -eq 'replica-test') '503 identity retained.'
    Assert-Fails {
        & $trafficScript -ApplicationUrl $url -Scenario Release -CandidateVersion candidate -DurationSeconds 5 -MaxRequests 2
    } 'unexpected errors: 2x HttpError \| HTTP 503'

    $server.Mode = 'gateway503'
    $gatewayScreen = [Collections.Generic.List[string]]::new()
    $gatewayPath = Join-Path $work 'gateway.jsonl'
    Assert-Fails {
        & $trafficScript -ApplicationUrl $url -CandidateVersion candidate -Concurrency 1 -MaxRequests 2 -OutputPath $gatewayPath -NoClear 6>&1 |
            ForEach-Object { $gatewayScreen.Add([string]$_) }
    } 'unexpected errors: 2x HttpError \| HTTP 503'
    $gatewayRecords = @(Get-Content $gatewayPath | ConvertFrom-Json)
    Assert-True (@($gatewayRecords | Where-Object { $_.Outcome -ne 'HttpError' -or $_.Replica }).Count -eq 0) 'Unidentified ingress 503s are HTTP errors, not setup failures or invented replica responses.'
    Assert-True (($gatewayScreen -join "`n") -match 'LAST 10s \| SUCCESS 0 \| ERRORS 2') 'The recent-response window appears for outages without requiring previous candidate exposure.'

    foreach ($mode in 'missing', 'unauthorized', 'forbidden') {
        $server.Mode = $mode
        $before = $server.Requests.Count
        Assert-Fails {
            & $trafficScript -ApplicationUrl $url -Scenario Recovery -Concurrency 1
        } 'Setup failure'
        Assert-True (($server.Requests.Count - $before) -eq 1) 'Setup failure stops immediately.'
    }

    $server.Mode = 'redirect'
    $before = $server.Requests.Count
    Assert-Fails {
        & $trafficScript -ApplicationUrl $url -Scenario Recovery -Concurrency 1 -DurationSeconds 5 -MaxRequests 1
    } 'unexpected errors'
    Assert-True (($server.Requests.Count - $before) -eq 1) 'Redirect is not followed and no request is retried.'

    $server.Mode = 'disconnect'
    $before = $server.Requests.Count
    $transportPath = Join-Path $work 'transport.jsonl'
    Assert-Fails {
        & $trafficScript -ApplicationUrl $url -Scenario Recovery -Concurrency 1 -DurationSeconds 5 -MaxRequests 1 -OutputPath $transportPath
    } 'unexpected errors'
    $transport = Get-Content $transportPath | ConvertFrom-Json
    Assert-True ($transport.Outcome -eq 'TransportError') 'Transport errors are explicit.'
    Assert-True (![string]::IsNullOrWhiteSpace($transport.ErrorKind)) 'Transport errors retain the exception type without raw exception messages.'
    Assert-True (($server.Requests.Count - $before) -eq 1) 'A disconnected request is not retried.'

    $server.Mode = 'success'
    $server.DelayMs = 1400
    $timeoutPath = Join-Path $work 'timeout.jsonl'
    Assert-Fails {
        & $trafficScript -ApplicationUrl $url -Scenario Recovery -Concurrency 1 -DurationSeconds 5 -MaxRequests 1 -TimeoutSeconds 1 -OutputPath $timeoutPath
    } 'unexpected errors'
    $timedOut = Get-Content $timeoutPath | ConvertFrom-Json
    Assert-True ($timedOut.Outcome -eq 'Timeout') 'Request timeout is distinguished from run cancellation.'
    $cancelPath = Join-Path $work 'cancel.jsonl'
    Assert-Fails {
        & $trafficScript -ApplicationUrl $url -Scenario Recovery -Concurrency 1 -DurationSeconds 1 -MaxRequests 1 -TimeoutSeconds 5 -OutputPath $cancelPath
    } 'No complete'
    $cancelled = Get-Content $cancelPath | ConvertFrom-Json
    Assert-True ($cancelled.Outcome -eq 'Cancelled') 'Duration cancellation is recorded and drained.'
    $server.DelayMs = 0
    $server.Mode = 'success'
    $before = $server.Requests.Count
    $summary = & $trafficScript -ConfigPath $trafficConfigPath -Scenario Recovery -DurationSeconds 5 -MaxRequests 5 -PassThru
    $recovery = @($server.Requests.ToArray() | Select-Object -Skip $before)
    Assert-True ($summary.Success -eq 5 -and $recovery[0].Headers['X-Demo-Operation'] -eq 'observe') 'Recovery sends only the observe operation.'

    foreach ($scenario in 'Demo', 'Scale', 'Release', 'Recovery') {
        $server.SetupFailureAfter = $server.Requests.Count + 20
        $continuousOutput = [Collections.Generic.List[string]]::new()
        Assert-Fails {
            & $trafficScript -ConfigPath $trafficConfigPath -Scenario $scenario -NoClear 6>&1 |
                ForEach-Object { $continuousOutput.Add([string]$_) }
        } 'Setup failure'
        Assert-True (($continuousOutput -join "`n") -match 'Until Ctrl\+C \| No request cap') "$scenario defaults to continuous traffic without total-request or duration caps."
    }
    $server.SetupFailureAfter = 0
    $continuousEngine = $engineType::new(
        $url, $env:MUSICSTORE_DEMO_TOKEN, 'continuous-test', 'Scale', 'candidate',
        4, 0, 0, 5, 0, $null)
    try {
        $continuousTask = $continuousEngine.RunAsync()
        Start-Sleep -Milliseconds 500
        $firstCount = $continuousEngine.GetSnapshot().Completed
        Start-Sleep -Milliseconds 500
        Assert-True (!$continuousTask.IsCompleted -and $continuousEngine.GetSnapshot().Completed -gt $firstCount) 'Continuous traffic keeps sending requests until cancelled.'
        $continuousEngine.Cancel()
        Assert-True ($continuousTask.Wait(5000)) 'Manual cancellation promptly drains owned requests.'
        $continuousSummary = $continuousTask.GetAwaiter().GetResult()
        Assert-True ($continuousSummary.Success -gt 0 -and $continuousSummary.InFlight -eq 0 -and $continuousSummary.UnexpectedErrors -eq 0) 'Manual cancellation leaves no in-flight requests or unexpected failures.'
    }
    finally {
        $continuousEngine.Cancel()
        $null = $continuousTask.GetAwaiter().GetResult()
        $continuousEngine.Dispose()
    }

    $server.Mode = 'gateway503'
    $outageOutput = @(& {
        $cancelDeadline = [DateTime]::UtcNow.AddSeconds(10)
        function Start-Sleep {
            param([int]$Milliseconds)
            if ([DateTime]::UtcNow -gt $cancelDeadline) { throw 'Continuous outage script did not reach the cancellation threshold.' }
            if ($engine.GetSnapshot().UnexpectedErrors -ge 64) { $engine.Cancel() }
            Microsoft.PowerShell.Utility\Start-Sleep -Milliseconds $Milliseconds
        }
        & $trafficScript -ApplicationUrl $url -CandidateVersion candidate -Concurrency 4 -PassThru -NoClear 6>&1
    })
    $outageSummary = $outageOutput | Where-Object { $_.GetType().Name -eq 'Snapshot' }
    Assert-True ($outageSummary.Success -eq 0 -and $outageSummary.UnexpectedErrors -ge 64 -and
        $outageSummary.InFlight -eq 0 -and !$outageSummary.StopReason) 'Cancelling the actual default script during a total outage returns its failure evidence without throwing.'
    Assert-True (($outageOutput -join "`n") -match 'LIVE TRAFFIC \| FINISHED') 'The default script finishes normally after cancellation even when no authenticated request succeeded.'

    foreach ($mode in 'stable503', 'gateway503', 'gateway500', 'gateway429', 'gateway408', 'disconnect', 'timeout') {
        $server.Mode = if ($mode -eq 'timeout') { 'success' } else { $mode }
        $server.DelayMs = if ($mode -eq 'timeout') { 1400 } else { 0 }
        $outageEngine = $engineType::new(
            $url, $env:MUSICSTORE_DEMO_TOKEN, "outage-$mode", 'Demo', 'candidate',
            32, 0, 0, 1, 100, $null)
        try {
            $outageTask = $outageEngine.RunAsync()
            $deadline = [DateTime]::UtcNow.AddSeconds(10)
            do {
                Start-Sleep -Milliseconds 50
                $outage = $outageEngine.GetSnapshot()
            } while ($outage.UnexpectedErrors -lt 64 -and !$outageTask.IsCompleted -and [DateTime]::UtcNow -lt $deadline)
            Assert-True ($outage.UnexpectedErrors -ge 64 -and $outage.Success -eq 0 -and
                !$outageTask.IsCompleted -and !$outage.StopReason) "Continuous traffic survives 100% $mode failures beyond the old safety threshold."
            Assert-True ($outage.ExpectedCandidate503 -eq 0 -and $outage.RecentErrors -gt 0) "$mode failures remain real errors, not expected candidate responses."
            if ($mode.StartsWith('gateway') -or $mode -in 'disconnect', 'timeout') {
                Assert-True ($outage.Identities.Count -eq 0) "$mode failures do not invent a responding replica."
            }
            if ($mode -eq 'timeout') {
                Assert-True ($outage.Timeouts -ge 64 -and $outage.Cancellations -eq 0) 'Timeouts remain distinct from manual cancellation during a total outage.'
            }
            $server.Mode = 'success'
            $server.DelayMs = 0
            $deadline = [DateTime]::UtcNow.AddSeconds(5)
            do {
                Start-Sleep -Milliseconds 50
                $recovered = $outageEngine.GetSnapshot()
            } while ($recovered.Success -eq 0 -and !$outageTask.IsCompleted -and [DateTime]::UtcNow -lt $deadline)
            Assert-True ($recovered.Success -gt 0 -and $recovered.UnexpectedErrors -ge $outage.UnexpectedErrors -and
                !$outageTask.IsCompleted -and !$recovered.StopReason) "The same $mode traffic process observes recovery without erasing failures."
            if ($mode -eq 'gateway503') {
                $deadline = [DateTime]::UtcNow.AddSeconds(15)
                do {
                    Start-Sleep -Milliseconds 100
                    $recovered = $outageEngine.GetSnapshot()
                } while (($recovered.RecentErrors -gt 0 -or $recovered.RecentSuccess -eq 0) -and [DateTime]::UtcNow -lt $deadline)
                Assert-True ($recovered.RecentErrors -eq 0 -and $recovered.RecentSuccess -gt 0 -and
                    $recovered.UnexpectedErrors -ge 64 -and !$outageTask.IsCompleted) 'Recovery clears the recent outage window while retaining cumulative failures.'
            }
            $outageEngine.Cancel()
            Assert-True ($outageTask.Wait(5000)) "Manual cancellation drains $mode traffic promptly."
            $outageSummary = $outageTask.GetAwaiter().GetResult()
            Assert-True ($outageSummary.InFlight -eq 0 -and !$outageSummary.StopReason) "$mode traffic ends cleanly only when cancelled, with its error evidence intact."
        }
        finally {
            $outageEngine.Cancel()
            $null = $outageTask.GetAwaiter().GetResult()
            $outageEngine.Dispose()
        }
    }
    $server.Dispose()
    $server = $null

    # A PATH-local fake executable ensures Watch never reaches Azure, even on failure/timeout.
    $mock = Join-Path $work 'az-mock.ps1'
    @'
[IO.File]::WriteAllText("$env:DEMO_AZ_TEST_LOG.pid", [string]$PID)
$args | ConvertTo-Json -Compress | Add-Content $env:DEMO_AZ_TEST_LOG
if ($env:DEMO_AZ_TEST_MODE -eq 'failure') { [Console]::Error.WriteLine('mock authorization failure'); exit 7 }
if ($env:DEMO_AZ_TEST_MODE -eq 'failure-after-first' -and @(Get-Content $env:DEMO_AZ_TEST_LOG).Count -gt 1) {
    [Console]::Error.WriteLine('mock failure after continuous refresh'); exit 7
}
if ($env:DEMO_AZ_TEST_MODE -eq 'slow') { Start-Sleep -Seconds 10 }
if ($env:DEMO_AZ_TEST_MODE -eq 'empty') { '[]'; exit 0 }
if ($env:DEMO_AZ_TEST_MODE -eq 'revisions') {
    $stepPath = "$env:DEMO_AZ_TEST_LOG.step"
    if ($args[1] -eq 'revision') {
        $step = if (Test-Path $stepPath) { [int](Get-Content $stepPath) + 1 } else { 1 }
        Set-Content $stepPath $step
        switch ($step) {
            1 { '[{"name":"ca-test--v1","health":"Healthy","traffic":100}]' }
            2 { '[{"name":"ca-test--v1","health":"Healthy","traffic":100},{"name":"ca-test--v2","health":"Activating","traffic":0}]' }
            3 { '[{"name":"ca-test--v1","health":"Healthy","traffic":90},{"name":"ca-test--v2","health":"Healthy","traffic":10}]' }
            4 { '[{"name":"ca-test--v2","health":"Healthy","traffic":100}]' }
            default { [Console]::Error.WriteLine('mock completed revision lifecycle'); exit 9 }
        }
        exit 0
    }
    $step = [int](Get-Content $stepPath)
    $revision = $args[[Array]::IndexOf($args, '--revision') + 1]
    if ($revision -eq 'ca-test--v1') {
        switch ($step) {
            1 { '[{"name":"replica-a","containers":[{"ready":true,"restartCount":0,"containerId":"a1"}]}]' }
            2 { '[{"name":"replica-a","containers":[{"ready":true,"restartCount":0,"containerId":"a1"}]},{"name":"replica-b","containers":[{"ready":false,"restartCount":0,"containerId":"b1"}]}]' }
            default { '[{"name":"replica-a","containers":[{"ready":true,"restartCount":1,"containerId":"a2"}]},{"name":"replica-b","containers":[{"ready":true,"restartCount":0,"containerId":"b1"}]}]' }
        }
    }
    elseif ($revision -eq 'ca-test--v2') {
        switch ($step) {
            2 { '[]' }
            3 { '[{"name":"replica-a","containers":[{"ready":true,"restartCount":0,"containerId":"c1"}]}]' }
            default { '[{"name":"replica-a","containers":[{"ready":true,"restartCount":0,"containerId":"c1"}]},{"name":"replica-b","containers":[{"ready":true,"restartCount":0,"containerId":"d1"}]}]' }
        }
    }
    else { [Console]::Error.WriteLine('unexpected revision target'); exit 8 }
    exit 0
}
if ($env:DEMO_AZ_TEST_MODE -eq 'slow-tail' -and @(Get-Content $env:DEMO_AZ_TEST_LOG).Count -gt 1) {
    Start-Sleep -Seconds 10
}
if ($env:DEMO_AZ_TEST_MODE -eq 'changes') {
    $step = @(Get-Content $env:DEMO_AZ_TEST_LOG).Count
    switch ($step) {
        1 { '[{"name":"replica-a","containers":[{"ready":true,"restartCount":0,"containerId":"a1"}]}]' }
        2 { '[{"name":"replica-a","containers":[{"ready":true,"restartCount":0,"containerId":"a1"}]},{"name":"replica-b","containers":[{"ready":false,"restartCount":0,"containerId":"b1"}]}]' }
        3 { '[{"name":"replica-a","containers":[{"ready":true,"restartCount":1,"containerId":"a2"}]},{"name":"replica-b","containers":[{"ready":true,"restartCount":0,"containerId":"b1"}]}]' }
        4 { '[{"name":"replica-b","containers":[{"ready":true,"restartCount":0,"containerId":"b1"}]}]' }
        default { [Console]::Error.WriteLine('mock completed replica lifecycle'); exit 9 }
    }
    exit 0
}
'[{"name":"replica-test","containers":[{"name":"web","ready":true,"restartCount":2,"containerId":"container-test"}]}]'
'@ | Set-Content $mock
    $pwsh = (Get-Process -Id $PID).Path
    if ($IsWindows) {
        "@echo off`r`n`"$pwsh`" -NoLogo -NoProfile -File `"$mock`" %*`r`n" | Set-Content (Join-Path $work 'az.cmd')
    }
    else {
        "#!/bin/sh`nexec '$pwsh' -NoLogo -NoProfile -File '$mock' `"`$@`"`n" | Set-Content (Join-Path $work 'az')
        & chmod +x (Join-Path $work 'az')
        if ($LASTEXITCODE -ne 0) { throw 'Cannot mark local az test shim executable.' }
    }
    $env:PATH = $work + [IO.Path]::PathSeparator + $originalPath
    $env:DEMO_AZ_TEST_LOG = Join-Path $work 'az-arguments.jsonl'
    $testConfigPath = Join-Path $work 'azure.local.json'
    @{
        schemaVersion = 1
        deployment = @{subscriptionId='11111111-1111-4111-8111-111111111111';resourceGroupName='rg-test'}
        resources = @{containerAppName='ca-test'}
    } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $testConfigPath
    $watchSettings = @{ ConfigPath = $testConfigPath }
    $env:DEMO_AZ_TEST_MODE = 'success'
    $watchOutput = (& $watchScript @watchSettings -Revision revision-test -DurationSeconds 10 -CommandTimeoutSeconds 10 6>&1 | Out-String)
    Assert-True ($watchOutput -match 'REPLICAS 1\s+\|\s+READY 1/1\s+\|\s+RESTARTS 2') 'Watch summarizes replica readiness and restarts.'
    Assert-True ($watchOutput -match 'R01\s+replica-test\s+READY\s+2') 'Watch shows a compact replica row.'
    Assert-True ($watchOutput -notmatch "az 'containerapp'|container-test") 'Default display hides CLI noise and full container IDs.'
    $verboseOutput = (& $watchScript @watchSettings -Revision revision-test -DurationSeconds 10 -Verbose -NoClear 4>&1 6>&1 | Out-String)
    Assert-True ($verboseOutput -match "az 'containerapp' 'replica' 'list'.*--subscription.*--revision") 'Verbose preserves the exact read-only query.'
    Assert-True ($verboseOutput -match 'containerID=container-test') 'Verbose preserves full container identity.'
    $cliArgs = @(Get-Content $env:DEMO_AZ_TEST_LOG | Select-Object -First 1 | ConvertFrom-Json)
    Assert-True (($cliArgs -join ' ') -match '--subscription 11111111-1111-4111-8111-111111111111 --resource-group rg-test --name ca-test --revision revision-test') 'Local test configuration is passed explicitly to Azure CLI.'
    Assert-True (($cliArgs -join ' ') -match "properties.containers\[\?name=='web'\]") 'Query selects only the web container.'
    $env:DEMO_AZ_TEST_MODE = 'empty'
    $emptyOutput = (& $watchScript @watchSettings -Revision revision-test -DurationSeconds 5 6>&1 | Out-String)
    Assert-True ($emptyOutput -match 'No replicas returned') 'Empty revision replica sets are visible.'
    Assert-True ($emptyOutput -match 'REPLICAS 0\s+\|\s+READY 0/0') 'Empty sets have zero totals.'
    $emptyRevisions = (& $watchScript @watchSettings -DurationSeconds 10 -NoClear 6>&1 | Out-String)
    Assert-True ($emptyRevisions -match 'REVISIONS 0 \| REPLICAS 0' -and
        $emptyRevisions -match 'No active revisions returned') 'An app without active revisions is explicitly shown without inventing replica readiness.'
    Remove-Item -LiteralPath $env:DEMO_AZ_TEST_LOG
    $env:DEMO_AZ_TEST_MODE = 'changes'
    $changesLines = [Collections.Generic.List[string]]::new()
    Assert-Fails {
        & $watchScript @watchSettings -Revision revision-test -DurationSeconds 180 -NoClear 6>&1 |
            ForEach-Object { $changesLines.Add([string]$_) }
    } 'exit 9'
    $changesOutput = $changesLines -join "`n"
    Assert-True ($changesOutput -match 'R02 added \(STARTING\)') 'Scale-out is highlighted with a stable label.'
    Assert-True ($changesOutput -match 'R02 STARTING -> READY') 'Readiness changes are highlighted.'
    Assert-True ($changesOutput -match 'R01 container restarted/replaced') 'Same-name container recovery is highlighted.'
    Assert-True ($changesOutput -match 'R01 removed') 'Scale-in is highlighted.'
    Remove-Item -LiteralPath $env:DEMO_AZ_TEST_LOG
    $env:DEMO_AZ_TEST_MODE = 'revisions'
    $revisionLines = [Collections.Generic.List[string]]::new()
    Assert-Fails {
        & $watchScript @watchSettings -DurationSeconds 180 -NoClear 6>&1 |
            ForEach-Object { $revisionLines.Add([string]$_) }
    } 'exit 9'
    $revisionOutput = $revisionLines -join "`n"
    Assert-True ($revisionOutput -match 'Revision v2 added' -and
        $revisionOutput -match 'Revision: v2 \| Traffic 0% \| Activating \| READY 0/0' -and
        $revisionOutput -match 'No replicas returned') 'New zero-traffic revisions appear before replicas exist.'
    Assert-True ($revisionOutput -match 'Revision: v1 \| Traffic 90%' -and
        $revisionOutput -match 'Revision: v2 \| Traffic 10%') 'Routing weight changes are discovered in the running observer.'
    Assert-True ($revisionOutput -match 'REVISIONS 2 \| REPLICAS 3\s+\|\s+READY 3/3\s+\|\s+RESTARTS 1') 'Totals include all revision groups.'
    Assert-True ($revisionOutput -match 'R01\s+replica-a\s+READY' -and
        $revisionOutput -match 'R03\s+replica-a\s+READY' -and
        $revisionOutput -match 'R03 added \(READY\) in v2') 'Replica labels are revision-scoped even when instance names collide.'
    Assert-True ($revisionOutput -match 'Revision v1 no longer active' -and
        $revisionOutput -match 'R04 added \(READY\) in v2') 'Revision removal and later replica additions appear without restarting Watch.'
    $discoveryCalls = @(Get-Content $env:DEMO_AZ_TEST_LOG | ForEach-Object { ,@(ConvertFrom-Json $_) })
    Assert-True (@($discoveryCalls | Where-Object { $_[1] -eq 'revision' }).Count -eq 5) 'Watch rediscovers revisions on every snapshot.'
    Assert-True (@($discoveryCalls | Where-Object { $_[1] -notin 'revision', 'replica' -or $_[2] -ne 'list' }).Count -eq 0) 'Multi-revision discovery uses only read-only list commands.'
    Remove-Item -LiteralPath $env:DEMO_AZ_TEST_LOG
    $env:DEMO_AZ_TEST_MODE = 'slow-tail'
    $tailOutput = (& $watchScript @watchSettings -Revision revision-test -DurationSeconds 9 -CommandTimeoutSeconds 5 -NoClear 6>&1 | Out-String)
    Assert-True ($tailOutput -match 'REPLICAS 1') 'Normal duration expiry during a final refresh is not a query failure.'
    $env:DEMO_AZ_TEST_MODE = 'failure'
    Assert-Fails { & $watchScript @watchSettings -Revision revision-test -DurationSeconds 5 } 'exit 7'
    Remove-Item -LiteralPath $env:DEMO_AZ_TEST_LOG
    $env:DEMO_AZ_TEST_MODE = 'failure-after-first'
    $watchAst = [Management.Automation.Language.Parser]::ParseFile($watchScript, [ref]$null, [ref]$null)
    $durationParameter = $watchAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'DurationSeconds' }
    Assert-True ($null -eq $durationParameter.DefaultValue) 'Watch has no default duration limit.'
    Assert-Fails { & $watchScript @watchSettings -Revision revision-test -CommandTimeoutSeconds 30 } 'exit 7'
    Assert-True (@(Get-Content $env:DEMO_AZ_TEST_LOG).Count -eq 2) 'Continuous Watch refreshes without a duration argument and still surfaces CLI failures.'
    $env:DEMO_AZ_TEST_MODE = 'slow'
    Assert-Fails { & $watchScript @watchSettings -Revision revision-test -DurationSeconds 6 -CommandTimeoutSeconds 3 } 'timed out'
    $mockPid = [int](Get-Content "$env:DEMO_AZ_TEST_LOG.pid")
    Assert-True ($null -eq (Get-Process -Id $mockPid -ErrorAction SilentlyContinue)) 'A timed-out owned CLI invocation leaves no child process running.'
    Assert-Fails { & $watchScript -Revision revision-test -DurationSeconds 1801 } 'validat'
    Assert-Fails { & $watchScript -Revision revision-test -IntervalSeconds 4 } 'validat'
    Write-Host 'PASS: local traffic bounds/concurrency/rate/identity/error handling and read-only Watch CLI tests.'
}
finally {
    if ($server) { $server.Dispose() }
    $env:MUSICSTORE_DEMO_TOKEN = $originalToken
    $env:PATH = $originalPath
    $env:DEMO_AZ_TEST_MODE = $originalMockMode
    $env:DEMO_AZ_TEST_LOG = $originalMockLog
    if (Test-Path $work) { Remove-Item -LiteralPath $work -Recurse -Force }
}
