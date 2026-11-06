#requires -Version 7.0
[CmdletBinding()]
param(
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]{0,127}$')][string]$Revision,
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$SubscriptionId,
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9._-]{0,89}$')][string]$ResourceGroup,
    [ValidatePattern('^[a-zA-Z0-9][a-zA-Z0-9-]{0,63}$')][string]$AppName,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\azure.local.json'),
    [ValidateRange(1, 1800)][int]$DurationSeconds,
    [ValidateRange(5, 1800)][int]$IntervalSeconds = 5,
    [ValidateRange(1, 60)][int]$CommandTimeoutSeconds = 30,
    [switch]$NoClear
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$settings = @{ SubscriptionId = 'deployment.subscriptionId'; ResourceGroup = 'deployment.resourceGroupName';
    AppName = 'resources.containerAppName' }
$required = @($settings.Keys | Where-Object { !$PSBoundParameters.ContainsKey($_) } | ForEach-Object { $settings[$_] })
$config = & (Join-Path $PSScriptRoot 'Get-AzureLocalConfig.ps1') -ConfigPath $ConfigPath -RequiredSettings $required
foreach ($name in $settings.Keys) {
    if (!$PSBoundParameters.ContainsKey($name)) {
        $parts = $settings[$name].Split('.')
        Set-Variable -Name $name -Value $config.($parts[0]).($parts[1])
    }
    if ([string]::IsNullOrWhiteSpace((Get-Variable -Name $name -ValueOnly))) {
        throw "The explicit target setting '$name' must not be empty."
    }
}
if ($PSBoundParameters.ContainsKey('Revision') -and [string]::IsNullOrWhiteSpace($Revision)) {
    throw "The explicit target setting 'Revision' must not be empty."
}
$az = (Get-Command az -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
$query = "[].{name:name,containers:properties.containers[?name=='web'].{name:name,ready:ready,restartCount:restartCount,containerId:containerId}}"
$targetArguments = @('--subscription', $SubscriptionId, '--resource-group', $ResourceGroup, '--name', $AppName)
$revisionArguments = @('containerapp', 'revision', 'list') + $targetArguments +
    @('--query', '[?properties.active==`true`].{name:name,health:properties.healthState,traffic:properties.trafficWeight}',
        '--output', 'json', '--only-show-errors')
$clock = [Diagnostics.Stopwatch]::StartNew()
$labels = @{}
$previous = @{}
$previousRevisions = @{}
$events = [Collections.Generic.Queue[string]]::new()
$firstSnapshot = $true
$refreshScreen = !$NoClear -and $VerbosePreference -ne 'Continue' -and
    ![Console]::IsOutputRedirected -and $Host.Name -eq 'ConsoleHost'

function Invoke-WatchQuery {
    param([string[]]$CliArguments)
    Write-Verbose ('az ' + (($CliArguments | ForEach-Object { "'" + $_.Replace("'", "''") + "'" }) -join ' '))
    $invocation = [powershell]::Create()
    $pending = $null
    try {
        $null = $invocation.AddScript({
            param($Executable, $CliArguments)
            $ErrorActionPreference = 'Stop'
            $output = & $Executable @CliArguments 2>&1
            if ($LASTEXITCODE -ne 0) {
                throw "Azure CLI failed (exit $LASTEXITCODE): $($output -join [Environment]::NewLine)"
            }
            $output
        }).AddArgument($az).AddArgument($CliArguments)
        $pending = $invocation.BeginInvoke()
        $remaining = if ($DurationSeconds) { $DurationSeconds - $clock.Elapsed.TotalSeconds } else { [double]::PositiveInfinity }
        $timeout = [Math]::Min([double]$CommandTimeoutSeconds, [double]$remaining)
        Write-Verbose "CLI started after $($clock.Elapsed.TotalSeconds) seconds; remaining=$remaining; timeout=$timeout."
        if (!$pending.AsyncWaitHandle.WaitOne([TimeSpan]::FromSeconds([Math]::Max(0, $timeout)))) {
            if (!$firstSnapshot -and $timeout -lt $CommandTimeoutSeconds) {
                Write-Verbose 'Observation duration ended during the final refresh.'
                return [pscustomobject]@{ Completed = $false; Items = @() }
            }
            throw "Azure CLI query timed out after $([Math]::Round($timeout, 1)) seconds."
        }
        $json = $invocation.EndInvoke($pending) -join [Environment]::NewLine
        if ($invocation.HadErrors) { throw "Azure CLI query failed: $($invocation.Streams.Error -join '; ')" }
        if ([string]::IsNullOrWhiteSpace($json)) { throw 'Azure CLI returned empty output instead of a JSON array.' }
        return [pscustomobject]@{ Completed = $true; Items = @($json | ConvertFrom-Json -ErrorAction Stop) }
    }
    finally {
        # Stop only this read-only CLI invocation on timeout/Ctrl+C; never target an application process.
        if ($pending -and !$pending.IsCompleted) { $invocation.Stop() }
        $invocation.Dispose()
    }
}

Write-Host 'Connecting to Azure Container Apps (read-only)...'
:observe while (!$DurationSeconds -or $clock.Elapsed.TotalSeconds -lt $DurationSeconds) {
    if ($Revision) {
        $revisions = @([pscustomobject]@{ name = $Revision; health = $null; traffic = $null })
    }
    else {
        $result = Invoke-WatchQuery -CliArguments $revisionArguments
        if (!$result.Completed) { break }
        $revisions = @($result.Items | Sort-Object name)
    }
    $current = @{}
    $currentRevisions = @{}
    $groups = @(
    foreach ($revisionInfo in $revisions) {
        if (!$revisionInfo.name) { throw 'Azure CLI returned a revision without a name.' }
        $revisionName = [string]$revisionInfo.name
        $revisionLabel = if ($revisionName.StartsWith("$AppName--")) { $revisionName.Substring($AppName.Length + 2) } else { $revisionName }
        $currentRevisions[$revisionName] = $revisionLabel
        $arguments = @('containerapp', 'replica', 'list') + $targetArguments +
            @('--revision', $revisionName, '--query', $query, '--output', 'json', '--only-show-errors')
        $result = Invoke-WatchQuery -CliArguments $arguments
        if (!$result.Completed) { break observe }
        if (!$firstSnapshot -and !$previousRevisions.ContainsKey($revisionName)) {
            $events.Enqueue("$(Get-Date -Format HH:mm:ss)  Revision $revisionLabel added")
        }
        $rows = @(
        foreach ($replica in ($result.Items | Sort-Object name)) {
            if (!$replica.name) { throw 'Azure CLI returned a replica without a name.' }
            $web = @($replica.containers)
            $key = "$revisionName|$($replica.name)"
            if (!$labels.ContainsKey($key)) {
                $labels[$key] = 'R{0:00}' -f ($labels.Count + 1)
            }
            if ($web.Count -gt 1) { throw 'More than one web container returned for a replica.' }
            $container = if ($web.Count) { $web[0] } else { $null }
            $state = if (!$container) { 'NO CONTAINER' } elseif ($container.ready) { 'READY' } else { 'STARTING' }
            $restarts = if ($container) { [int]$container.restartCount } else { 0 }
            $containerId = if ($container) { [string]$container.containerId } else { '' }
            $label = $labels[$key]
            $current[$key] = @{ State = $state; Restarts = $restarts; ContainerId = $containerId }
            $change = $null
            if (!$firstSnapshot) {
                if (!$previous.ContainsKey($key)) { $change = "$label added ($state) in $revisionLabel" }
                else {
                    $old = $previous[$key]
                    if ($restarts -gt $old.Restarts -or ($old.ContainerId -and $containerId -and $old.ContainerId -ne $containerId)) {
                        $change = "$label container restarted/replaced ($state)"
                    }
                    elseif ($old.State -ne $state) { $change = "$label $($old.State) -> $state" }
                }
            }
            if ($change) { $events.Enqueue("$(Get-Date -Format HH:mm:ss)  $change") }
            Write-Verbose "revision=$revisionName replica=$($replica.name) ready=$state restarts=$restarts containerID=$containerId"
            $shortName = if ($replica.name.StartsWith("$revisionName-")) { $replica.name.Substring($revisionName.Length + 1) } else { $replica.name }
            [pscustomobject]@{ Label = $label; Instance = $shortName; State = $state; Restarts = $restarts }
        }
        )
        [pscustomobject]@{ Name = $revisionName; Label = $revisionLabel; Health = $revisionInfo.health;
            Traffic = $revisionInfo.traffic; Rows = $rows }
    }
    )
    foreach ($removed in $previous.Keys) {
        if (!$current.ContainsKey($removed)) {
            $events.Enqueue("$(Get-Date -Format HH:mm:ss)  $($labels[$removed]) removed")
        }
    }
    foreach ($removed in $previousRevisions.Keys) {
        if (!$currentRevisions.ContainsKey($removed)) {
            $events.Enqueue("$(Get-Date -Format HH:mm:ss)  Revision $($previousRevisions[$removed]) no longer active")
        }
    }
    while ($events.Count -gt 4) { $null = $events.Dequeue() }
    $allRows = @($groups | ForEach-Object { $_.Rows })
    $readyCount = @($allRows | Where-Object State -eq 'READY').Count
    $restartCount = 0
    foreach ($row in $allRows) { $restartCount += $row.Restarts }
    if ($refreshScreen) { Clear-Host }
    Write-Host ''
    Write-Host '  AZURE CONTAINER APPS | LIVE REPLICAS' -ForegroundColor Cyan
    Write-Host "  App: $AppName"
    Write-Host ''
    Write-Host ("  REVISIONS {0} | REPLICAS {1}   |   READY {2}/{1}   |   RESTARTS {3}" -f $groups.Count, $allRows.Count, $readyCount, $restartCount) `
        -ForegroundColor $(if ($readyCount -eq $allRows.Count -and $allRows.Count -gt 0) { 'Green' } else { 'Yellow' })
    foreach ($group in $groups) {
        Write-Host ''
        $metadata = if ($null -ne $group.Traffic) { " | Traffic $($group.Traffic)% | $($group.Health)" } else { '' }
        $groupReady = @($group.Rows | Where-Object State -eq 'READY').Count
        Write-Host "  Revision: $($group.Label)$metadata | READY $groupReady/$($group.Rows.Count)" -ForegroundColor Cyan
        Write-Host ('  {0,-5} {1,-25} {2,-13} {3,8}' -f 'ID', 'INSTANCE', 'STATE', 'RESTARTS')
        foreach ($row in $group.Rows) {
            Write-Host ('  {0,-5} {1,-25} {2,-13} {3,8}' -f $row.Label, $row.Instance, $row.State, $row.Restarts) `
                -ForegroundColor $(if ($row.State -eq 'READY') { 'Green' } else { 'Yellow' })
        }
        if (!$group.Rows.Count) { Write-Host '  No replicas returned.' -ForegroundColor Yellow }
    }
    if (!$groups.Count) { Write-Host '  No active revisions returned.' -ForegroundColor Yellow }
    Write-Host ''
    Write-Host '  RECENT CHANGES'
    if (!$events.Count) { Write-Host '  No changes since observation started.' -ForegroundColor DarkGray }
    foreach ($event in $events) { Write-Host "  $event" }
    Write-Host ''
    Write-Host "  Updated $(Get-Date -Format HH:mm:ss) | read-only | Ctrl+C to stop" -ForegroundColor DarkGray
    $previous = $current
    $previousRevisions = $currentRevisions
    $firstSnapshot = $false
    $remaining = if ($DurationSeconds) { $DurationSeconds - $clock.Elapsed.TotalSeconds } else { [double]::PositiveInfinity }
    if ($remaining -le $IntervalSeconds) {
        if ($remaining -gt 0) { Start-Sleep -Milliseconds ([int][Math]::Ceiling($remaining * 1000)) }
        break
    }
    Start-Sleep -Seconds $IntervalSeconds
}
