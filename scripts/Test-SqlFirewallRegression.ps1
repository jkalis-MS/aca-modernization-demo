#requires -Version 7.4
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$root = Split-Path $PSScriptRoot -Parent
$faultScript = Join-Path $PSScriptRoot 'Introduce-Misterious-Regression.ps1'
$work = Join-Path $root "artifacts\sql-firewall-test-$([Guid]::NewGuid().ToString('N'))"
$configPath = Join-Path $work 'azure.local.json'
$snapshotPath = Join-Path $work 'sql-firewall-regression.local.json'
$subscription = '11111111-1111-4111-8111-111111111111'
$serverId = "/subscriptions/$subscription/resourceGroups/rg-test/providers/Microsoft.Sql/servers/sql-test"
$checks = 0

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (!$Condition) { throw "Assertion failed: $Message" }
    $script:checks++
}

function Assert-Fails {
    param([scriptblock]$Action, [string]$Pattern)
    $message = $null
    try { & $Action | Out-Null } catch { $message = $_.Exception.Message }
    Assert-True ($null -ne $message -and $message -match $Pattern) "Expected '$Pattern'; got '$message'."
}

function Reset-Fixture {
    if (Test-Path -LiteralPath $snapshotPath) { Remove-Item -LiteralPath $snapshotPath }
    $script:mock = @{
        PublicAccess = 'Enabled'
        Rules = [System.Collections.Generic.List[object]]::new()
        Calls = [System.Collections.Generic.List[string]]::new()
        DeleteCount = 0
        CreateCount = 0
        FailDeleteAt = 0
        FailCreateAt = 0
        FailShow = $false
        IgnoreDelete = $false
        IgnoreCreate = $false
        Connections = [System.Collections.Generic.List[object]]::new()
        Flushes = [System.Collections.Generic.List[object]]::new()
        DenyPermission = $false
        FailOpenAt = 0
        FailFlushAt = 0
        FailToken = $false
        ClientIp = '198.51.100.10'
        FailIpLookup = $false
        IpLookups = 0
        PresenterWrites = 0
        FailPresenterWrite = $false
        IgnorePresenterWrite = $false
    }
    foreach ($rule in @(
        @{ name = 'AzureAllowance-A'; startIpAddress = '0.0.0.0'; endIpAddress = '0.0.0.0' },
        @{ name = 'AzureAllowance-B'; startIpAddress = '0.0.0.0'; endIpAddress = '0.0.0.0' },
        @{ name = 'Admin Access'; startIpAddress = '198.51.100.10'; endIpAddress = '198.51.100.10' },
        @{ name = 'NotAnAzureAllowance'; startIpAddress = '0.0.0.0'; endIpAddress = '0.0.0.1' }
    )) {
        $script:mock.Rules.Add([pscustomobject]$rule)
    }
}

function Invoke-RestMethod {
    param([string]$Uri, [int]$TimeoutSec)
    if ($Uri -ne 'https://api.ipify.org' -or $TimeoutSec -ne 15) { throw 'Unexpected IP lookup.' }
    $mock.IpLookups++
    if ($mock.FailIpLookup) { throw 'Mock IP lookup failure' }
    return $mock.ClientIp
}

function New-Object {
    param([string]$TypeName, [string]$ArgumentList)
    if ($TypeName -ne 'System.Data.SqlClient.SqlConnection') { throw 'Unexpected object creation.' }
    $builder = [System.Data.SqlClient.SqlConnectionStringBuilder]::new($ArgumentList)
    if ($builder.DataSource -ne 'tcp:sql-test.database.windows.net,1433' -or
        $builder.InitialCatalog -notin 'Catalog', 'Identity' -or !$builder.Encrypt -or
        $builder.TrustServerCertificate -or $builder.Pooling) {
        throw 'Unexpected SQL connection target or security settings.'
    }
    $connection = [pscustomobject]@{
        Database = $builder.InitialCatalog
        AccessToken = ''
        Disposed = $false
        Ordinal = $mock.Connections.Count + 1
    }
    $connection | Add-Member ScriptMethod Open {
        if ($this.AccessToken -ne 'mock-sql-token') { throw 'Missing operator token.' }
        if (!($mock.Rules | Where-Object { $_.name -eq 'Admin Access' -and $_.startIpAddress -eq $mock.ClientIp -and $_.endIpAddress -eq $mock.ClientIp })) {
            throw 'Presenter access must be established before SQL connections open.'
        }
        if ($this.Ordinal -eq $mock.FailOpenAt) { throw 'Mock SQL open failure' }
    }
    $connection | Add-Member ScriptMethod Dispose { $this.Disposed = $true }
    $connection | Add-Member ScriptMethod CreateCommand {
        $command = [pscustomobject]@{ Database = $this.Database; CommandText = ''; CommandTimeout = 0 }
        $command | Add-Member ScriptMethod ExecuteScalar {
            if ($this.CommandText -ne "SELECT HAS_PERMS_BY_NAME(DB_NAME(), 'DATABASE', 'KILL DATABASE CONNECTION');") {
                throw 'Unexpected permission query.'
            }
            if ($mock.DenyPermission) { return 0 }
            return 1
        }
        $command | Add-Member ScriptMethod ExecuteNonQuery {
            if ($this.CommandText -ne 'DBCC FLUSHAUTHCACHE;' -or $this.CommandTimeout -ne 15) {
                throw 'Unexpected SQL mutation or timeout.'
            }
            if (!(Test-Path -LiteralPath $snapshotPath)) { throw 'Cache refresh requires a recovery baseline.' }
            $mock.Flushes.Add([pscustomobject]@{ Database = $this.Database; AllowancePresent = @($mock.Rules | Where-Object startIpAddress -EQ '0.0.0.0' | Where-Object endIpAddress -EQ '0.0.0.0').Count -gt 0 })
            if ($mock.Flushes.Count -eq $mock.FailFlushAt) { throw 'Mock SQL refresh failure' }
            return -1
        }
        $command | Add-Member ScriptMethod Dispose {}
        return $command
    }
    $mock.Connections.Add($connection)
    return $connection
}

function Get-Option {
    param([object[]]$Arguments, [string]$Name)
    $index = [Array]::IndexOf($Arguments, $Name)
    if ($index -lt 0 -or $index + 1 -ge $Arguments.Count) { throw "Missing mock CLI option: $Name" }
    $Arguments[$index + 1]
}

# This scope-local command intercepts every az invocation; no Azure requests occur.
function az {
    $arguments = @($args)
    $command = $arguments -join ' '
    $mock.Calls.Add($command)
    foreach ($option in $arguments | Where-Object { $_ -like '--*' }) {
        if ($option -notin @('--subscription', '--resource-group', '--name', '--server', '--query',
            '--output', '--only-show-errors', '--start-ip-address', '--end-ip-address', '--resource')) {
            throw "Unsupported mock CLI option: $option"
        }
    }
    if ($command.StartsWith('account get-access-token ')) {
        if ((Get-Option $arguments '--subscription') -ne $subscription -or
            (Get-Option $arguments '--resource') -ne 'https://database.windows.net/') { throw 'Wrong token target.' }
        if ($mock.FailToken) { & pwsh -NoLogo -NoProfile -Command 'exit 17'; return }
        return 'mock-sql-token'
    }
    if ((Get-Option $arguments '--subscription') -ne $subscription -or
        (Get-Option $arguments '--resource-group') -ne 'rg-test') {
        throw 'CLI command did not explicitly target the configured subscription/resource group.'
    }
    if ($command.StartsWith('sql server show ')) {
        if ((Get-Option $arguments '--name') -ne 'sql-test') { throw 'Wrong SQL server.' }
        if ($mock.FailShow) { & pwsh -NoLogo -NoProfile -Command 'exit 17'; return }
        @{ id = $serverId; publicNetworkAccess = $mock.PublicAccess; fullyQualifiedDomainName = 'sql-test.database.windows.net' } | ConvertTo-Json
        return
    }
    if ((Get-Option $arguments '--server') -ne 'sql-test') { throw 'Wrong SQL server.' }
    if ($command.StartsWith('sql server firewall-rule list ')) {
        ConvertTo-Json -InputObject @($mock.Rules)
        return
    }
    $name = Get-Option $arguments '--name'
    if ($command.StartsWith('sql server firewall-rule create ') -and $name -eq 'Admin Access' -and
        (Get-Option $arguments '--start-ip-address') -ne '0.0.0.0') {
        $mock.PresenterWrites++
        if ($mock.FailPresenterWrite) { & pwsh -NoLogo -NoProfile -Command 'exit 17'; return }
        if ((Get-Option $arguments '--start-ip-address') -ne $mock.ClientIp -or
            (Get-Option $arguments '--end-ip-address') -ne $mock.ClientIp) { throw 'Presenter rule must allow only the detected IP.' }
        if (!$mock.IgnorePresenterWrite) {
            $existing = $mock.Rules | Where-Object name -EQ $name
            if ($existing) { $null = $mock.Rules.Remove($existing) }
            $mock.Rules.Add([pscustomobject]@{
                name = $name; startIpAddress = $mock.ClientIp; endIpAddress = $mock.ClientIp
            })
        }
        return
    }
    if (!(Test-Path -LiteralPath $snapshotPath -PathType Leaf)) { throw 'Mutation attempted without a recovery snapshot.' }
    if ($command.StartsWith('sql server firewall-rule delete ')) {
        if ($mock.Connections.Count -ne 2 -or @($mock.Connections | Where-Object Disposed).Count -ne 0) {
            throw 'Both operator connections must be opened and retained before removing firewall access.'
        }
        $mock.DeleteCount++
        if ($mock.DeleteCount -eq $mock.FailDeleteAt) { & pwsh -NoLogo -NoProfile -Command 'exit 17'; return }
        if (!$mock.IgnoreDelete) {
            $rule = $mock.Rules | Where-Object name -EQ $name
            if ($null -eq $rule) { throw 'Delete targeted a nonexistent rule.' }
            $null = $mock.Rules.Remove($rule)
        }
        return
    }
    if ($command.StartsWith('sql server firewall-rule create ')) {
        $mock.CreateCount++
        if ($mock.CreateCount -eq $mock.FailCreateAt) { & pwsh -NoLogo -NoProfile -Command 'exit 17'; return }
        if ($mock.Rules | Where-Object name -EQ $name) { throw 'Create overwrote an existing rule.' }
        if (!$mock.IgnoreCreate) {
            $mock.Rules.Add([pscustomobject]@{
                name = $name
                startIpAddress = Get-Option $arguments '--start-ip-address'
                endIpAddress = Get-Option $arguments '--end-ip-address'
            })
        }
        return
    }
    throw "Unexpected CLI operation: $command"
}

New-Item -ItemType Directory -Path $work -Force | Out-Null
try {
    @{
        schemaVersion = 1
        deployment = @{ subscriptionId = $subscription; resourceGroupName = 'rg-test' }
        resources = @{ sqlServerName = 'sql-test'; databaseNames = @('Catalog', 'Identity') }
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $configPath

    Reset-Fixture
    Assert-Fails { & $faultScript -ConfigPath (Join-Path $work 'missing.json') } 'configuration is missing'
    Assert-True ($mock.Calls.Count -eq 0) 'Missing configuration must not invoke az.'
    $output = @(& $faultScript -ConfigPath $configPath -Restore *>&1)
    Assert-True ($output.Count -eq 1 -and [string]$output[0] -ceq 'Nothing to restore. Misterious regression is already reset.') 'Missing snapshot with an enabled allowance must produce only the neutral no-op message.'
    Assert-True ($mock.Calls.Count -eq 2 -and $mock.DeleteCount -eq 0 -and $mock.CreateCount -eq 0 -and !(Test-Path -LiteralPath $snapshotPath)) 'No-op restore must read the live state without changing rules or writing a snapshot.'

    & $faultScript -ConfigPath $configPath -WhatIf
    Assert-True (!(Test-Path -LiteralPath $snapshotPath)) 'WhatIf must not write a snapshot.'
    Assert-True ($mock.DeleteCount -eq 0 -and $mock.Rules.Count -eq 4) 'WhatIf must not change rules.'
    Assert-True ($mock.Connections.Count -eq 0 -and $mock.Flushes.Count -eq 0) 'WhatIf must not connect to SQL or refresh caches.'
    Assert-True ($mock.IpLookups -eq 0 -and $mock.PresenterWrites -eq 0) 'WhatIf and no-op restore must not look up IPs or prepare access.'

    $output = @(& $faultScript -ConfigPath $configPath *>&1)
    Assert-True ($output.Count -eq 1) 'Default introduction must output only the presenter banner, with no extra stream messages.'
    $banner = [string]$output[0]
    Assert-True ($banner.Contains('Misterious regression introduced.') -and $banner.Contains('Greetings from the Intern :)')) 'The banner must preserve the presenter message.'
    $bannerLines = @($banner -split '\r?\n')
    Assert-True ($bannerLines.Count -ge 20 -and @($bannerLines | Where-Object Length -GT 80).Count -eq 0) 'The large banner must fit an 80-column terminal.'
    Assert-True ($banner -notmatch '[^\x00-\x7F]' -and $banner.Contains('\__/')) 'The banner must use ASCII only and include a smiling face.'
    Assert-True ($banner -notmatch '(?i)firewall|SQL|Azure|snapshot|Restore in CONTROL') 'The presenter banner must not reveal the cause or operator details.'
    $savedJson = Get-Content -LiteralPath $snapshotPath -Raw
    $saved = $savedJson | ConvertFrom-Json
    Assert-True ($saved.schemaVersion -eq 1 -and $saved.serverId -eq $serverId) 'Snapshot must identify the original server.'
    Assert-True ($saved.publicNetworkAccess -eq 'Enabled' -and $saved.firewallRules.Count -eq 4) 'Snapshot must record all original firewall rules and public access.'
    Assert-True ($mock.DeleteCount -eq 2 -and $mock.Rules.Count -eq 2) 'Disable every exact Azure-services allowance, regardless of name.'
    Assert-True ($mock.Flushes.Count -eq 2 -and @($mock.Flushes | Where-Object AllowancePresent).Count -eq 0) 'Refresh both user databases only after allowance removal.'
    Assert-True (@($mock.Connections | Where-Object { !$_.Disposed }).Count -eq 0) 'Dispose all operator connections after introduction.'
    Assert-True (@($mock.Rules | Where-Object name -EQ 'Admin Access').Count -eq 1 -and $mock.PresenterWrites -eq 0) 'Preserve matching operator access without redundant writes.'
    Assert-True (@($mock.Rules | Where-Object name -EQ 'NotAnAzureAllowance').Count -eq 1) 'Require both start and end to equal 0.0.0.0.'
    Assert-Fails { & $faultScript -ConfigPath $configPath } 'already exists'
    Assert-True ((Get-Content -LiteralPath $snapshotPath -Raw) -ceq $savedJson) 'Repeated invocation must not overwrite the baseline.'
    & $faultScript -ConfigPath $configPath -Restore -WhatIf
    Assert-True ($mock.CreateCount -eq 0 -and (Test-Path -LiteralPath $snapshotPath)) 'Restore WhatIf must preserve both Azure state and the snapshot.'
    Assert-True ($mock.Connections.Count -eq 2 -and $mock.Flushes.Count -eq 2) 'Restore WhatIf must not open additional SQL connections or refresh any caches.'
    $output = @(& $faultScript -ConfigPath $configPath -Restore *>&1)
    Assert-True ($output.Count -eq 1 -and [string]$output[0] -ceq 'Misterious regression removed.') 'Default restoration output must not reveal the cause.'
    Assert-True ($mock.CreateCount -eq 2 -and $mock.Rules.Count -eq 4) 'Restore both original rule names and exact addresses.'
    Assert-True (!(Test-Path -LiteralPath $snapshotPath)) 'Clear the snapshot only after verified restoration.'
    Assert-True ($mock.Flushes.Count -eq 4 -and @($mock.Flushes | Select-Object -Last 2 | Where-Object AllowancePresent).Count -eq 2) 'Refresh both databases after restoring the allowance.'
    $output = @(& $faultScript -ConfigPath $configPath -Restore *>&1)
    Assert-True ($output.Count -eq 1 -and [string]$output[0] -ceq 'Nothing to restore. Misterious regression is already reset.') 'A repeated successful restore must be safe and presentation-friendly.'
    Assert-True ($mock.CreateCount -eq 2 -and $mock.DeleteCount -eq 2) 'Repeating restore must not introduce any additional writes.'

    Reset-Fixture
    ($mock.Rules | Where-Object name -EQ 'Admin Access').name = 'PresenterLaptop'
    & $faultScript -ConfigPath $configPath -WhatIf
    Assert-True ($mock.PresenterWrites -eq 0 -and $mock.IpLookups -eq 0) 'WhatIf must not add missing presenter access.'
    & $faultScript -ConfigPath $configPath
    $saved = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    Assert-True ($mock.PresenterWrites -eq 1 -and $mock.DeleteCount -eq 2) 'Create missing presenter access before introducing the incident.'
    Assert-True (@($saved.firewallRules | Where-Object name -EQ 'Admin Access').Count -eq 1) 'Snapshot includes the new rule name, including its space.'
    Assert-True (@($mock.Rules | Where-Object name -EQ 'PresenterLaptop').Count -eq 1) 'Preparing access must preserve the legacy rule.'
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True ($mock.PresenterWrites -eq 1 -and $mock.Rules.Count -eq 5) 'Restore retains presenter access without redundant writes.'

    Reset-Fixture
    $mock.ClientIp = '203.0.113.8'
    & $faultScript -ConfigPath $configPath
    Assert-True ($mock.PresenterWrites -eq 1) 'Update the dedicated presenter rule when the public IP changes.'
    $mock.ClientIp = '203.0.113.9'
    & $faultScript -ConfigPath $configPath -Restore -WhatIf
    Assert-True ($mock.PresenterWrites -eq 1) 'Restore WhatIf must not update presenter access.'
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True ($mock.PresenterWrites -eq 2 -and !(Test-Path $snapshotPath)) 'Restore prepares access from a changed IP before refreshing SQL caches.'

    foreach ($failure in 'FailIpLookup', 'FailPresenterWrite', 'IgnorePresenterWrite') {
        Reset-Fixture
        $mock.ClientIp = '203.0.113.8'
        $mock[$failure] = $true
        Assert-Fails { & $faultScript -ConfigPath $configPath } 'lookup failure|17|could not be verified'
        Assert-True ($mock.DeleteCount -eq 0 -and $mock.Connections.Count -eq 0 -and !(Test-Path $snapshotPath)) 'Access preparation failure must not inject an incident or open SQL.'
    }
    foreach ($invalidIp in '::1', '0.0.0.0', '127.0.0.1', '255.255.255.255', 'not-an-ip', '') {
        Reset-Fixture
        $mock.ClientIp = $invalidIp
        Assert-Fails { & $faultScript -ConfigPath $configPath } 'valid workstation IPv4'
        Assert-True ($mock.PresenterWrites -eq 0 -and $mock.DeleteCount -eq 0) 'Invalid detected IP must not mutate any firewall rule.'
    }

    Reset-Fixture
    $presenter = $mock.Rules | Where-Object name -EQ 'Admin Access'
    $presenter.startIpAddress = '0.0.0.0'
    $presenter.endIpAddress = '0.0.0.0'
    Assert-Fails { & $faultScript -ConfigPath $configPath } 'not a workstation rule'
    Assert-True ($mock.PresenterWrites -eq 0 -and $mock.DeleteCount -eq 0) 'Never overwrite an Azure-services allowance named Admin Access.'

    Reset-Fixture
    $presenter = $mock.Rules | Where-Object name -EQ 'Admin Access'
    $presenter.endIpAddress = '198.51.100.11'
    Assert-Fails { & $faultScript -ConfigPath $configPath } 'not a single-address rule'
    Assert-True ($mock.PresenterWrites -eq 0 -and $mock.DeleteCount -eq 0) 'Never overwrite an existing Admin Access address range.'

    Reset-Fixture
    ($mock.Rules | Where-Object name -EQ 'Admin Access').name = 'PresenterLaptop'
    @{
        schemaVersion = 1; serverId = $serverId; publicNetworkAccess = 'Enabled'
        firewallRules = @($mock.Rules)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $snapshotPath
    $mock.Rules.RemoveRange(0, 2)
    & $faultScript -ConfigPath $configPath -Restore -WhatIf
    Assert-True ($mock.PresenterWrites -eq 0 -and $mock.CreateCount -eq 0) 'Restoring a legacy snapshot with WhatIf must not change rules.'
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True (@($mock.Rules | Where-Object name -EQ 'Admin Access').Count -eq 1 -and
        @($mock.Rules | Where-Object name -EQ 'PresenterLaptop').Count -eq 1 -and
        !(Test-Path -LiteralPath $snapshotPath)) 'Restore an old snapshot and prepare the new rule without deleting the old rule.'

    Reset-Fixture
    ($mock.Rules | Where-Object name -EQ 'Admin Access').name = 'Workstation'
    ($mock.Rules | Where-Object name -EQ 'AzureAllowance-A').name = 'Admin Access'
    @{
        schemaVersion = 1; serverId = $serverId; publicNetworkAccess = 'Enabled'
        firewallRules = @($mock.Rules)
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $snapshotPath
    $mock.Rules.RemoveRange(0, 2)
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } 'not a workstation rule'
    Assert-True ($mock.PresenterWrites -eq 0 -and
        @($mock.Rules | Where-Object { $_.name -eq 'Admin Access' -and $_.startIpAddress -eq '0.0.0.0' -and $_.endIpAddress -eq '0.0.0.0' }).Count -eq 1 -and
        (Test-Path -LiteralPath $snapshotPath)) 'Restore never replaces an Azure-services allowance named Admin Access and retains its snapshot.'

    Reset-Fixture
    & $faultScript -ConfigPath $configPath
    $mock.FailIpLookup = $true
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } 'recovery snapshot retained'
    Assert-True ($mock.Rules.Count -eq 4 -and (Test-Path $snapshotPath)) 'Restore repairs the Azure-services allowance even if presenter access preparation fails.'
    $mock.FailIpLookup = $false
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True (!(Test-Path $snapshotPath)) 'Restore can finish after the IP lookup recovers.'

    Reset-Fixture
    $mock.Rules.RemoveRange(0, 2)
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } 'No recovery snapshot'
    Assert-True ($mock.CreateCount -eq 0 -and $mock.DeleteCount -eq 0 -and !(Test-Path -LiteralPath $snapshotPath)) 'Without a baseline, a disabled allowance must never be guessed or silently treated as restored.'

    Reset-Fixture
    $mock.FailShow = $true
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } '17'
    Assert-True ($mock.CreateCount -eq 0 -and $mock.DeleteCount -eq 0) 'Missing-snapshot restore must surface failed Azure reads, not report a successful no-op.'

    Reset-Fixture
    $output = @(& $faultScript -ConfigPath $configPath -Verbose *>&1)
    Assert-True (($output -join "`n") -match 'Recovery snapshot saved:' -and ($output -join "`n") -match 'Azure-services firewall allowance disabled') 'Verbose output must retain operator diagnostics.'
    & $faultScript -ConfigPath $configPath -Restore

    Reset-Fixture
    $mock.PublicAccess = 'Disabled'
    Assert-Fails { & $faultScript -ConfigPath $configPath } 'must already be Enabled'
    Assert-True ($mock.DeleteCount -eq 0 -and !(Test-Path -LiteralPath $snapshotPath)) 'Disabled public access must fail without mutation.'

    Reset-Fixture
    $mock.Rules.RemoveRange(0, 2)
    Assert-Fails { & $faultScript -ConfigPath $configPath } 'already disabled'
    Assert-True ($mock.DeleteCount -eq 0 -and !(Test-Path -LiteralPath $snapshotPath)) 'Absent allowance must not create a misleading baseline.'

    Reset-Fixture
    $mock.FailShow = $true
    Assert-Fails { & $faultScript -ConfigPath $configPath } '17'
    Assert-True ($mock.DeleteCount -eq 0 -and !(Test-Path -LiteralPath $snapshotPath)) 'Native read failure must stop before any mutation.'

    Reset-Fixture
    $mock.FailDeleteAt = 2
    Assert-Fails { & $faultScript -ConfigPath $configPath } '17'
    Assert-True ($mock.Rules.Count -eq 3 -and (Test-Path -LiteralPath $snapshotPath)) 'Partial native delete failure must preserve the baseline.'
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True ($mock.Rules.Count -eq 4 -and $mock.CreateCount -eq 1) 'Recover partial introduction without overwriting an existing allowance.'

    Reset-Fixture
    $mock.IgnoreDelete = $true
    Assert-Fails { & $faultScript -ConfigPath $configPath } 'allowance is still present'
    Assert-True (Test-Path -LiteralPath $snapshotPath) 'Unverified disable must retain its snapshot.'
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True ($mock.CreateCount -eq 0 -and !(Test-Path -LiteralPath $snapshotPath)) 'An already-restored allowance requires no writes.'

    Reset-Fixture
    & $faultScript -ConfigPath $configPath
    $saved = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    $saved.serverId = "$serverId-other"
    $saved | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $snapshotPath
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } 'does not match'
    Assert-True ($mock.CreateCount -eq 0 -and (Test-Path -LiteralPath $snapshotPath)) 'Never restore a baseline onto another server.'

    Reset-Fixture
    & $faultScript -ConfigPath $configPath
    $mock.Rules.Add([pscustomobject]@{ name = 'AzureAllowance-B'; startIpAddress = '203.0.113.8'; endIpAddress = '203.0.113.8' })
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } 'external change'
    Assert-True ($mock.CreateCount -eq 0 -and (Test-Path -LiteralPath $snapshotPath)) 'Validate all names before any restore writes.'

    Reset-Fixture
    & $faultScript -ConfigPath $configPath
    $mock.FailCreateAt = 2
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } '17'
    Assert-True ($mock.Rules.Count -eq 3 -and (Test-Path -LiteralPath $snapshotPath)) 'Partial native restore failure must retain recovery state.'
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True ($mock.Rules.Count -eq 4 -and $mock.CreateCount -eq 3) 'A restore retry creates only the remaining missing rule.'

    Reset-Fixture
    & $faultScript -ConfigPath $configPath
    $mock.IgnoreCreate = $true
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } 'restoration could not be verified'
    Assert-True (Test-Path -LiteralPath $snapshotPath) 'Unverified restore must retain its snapshot.'

    foreach ($failure in 'DenyPermission', 'FailOpenAt', 'FailToken') {
        Reset-Fixture
        if ($failure -eq 'DenyPermission' -or $failure -eq 'FailToken') { $mock[$failure] = $true } else { $mock[$failure] = 2 }
        Assert-Fails { & $faultScript -ConfigPath $configPath } 'permission|open failure|17'
        Assert-True ($mock.DeleteCount -eq 0 -and !(Test-Path $snapshotPath)) 'Preflight SQL/token failures must stop before removing Azure-services access.'
        Assert-True (@($mock.Connections | Where-Object { !$_.Disposed }).Count -eq 0) 'Dispose connections after failed SQL preflight.'
    }
    Reset-Fixture
    $mock.FailFlushAt = 2
    $output = @()
    Assert-Fails { $output = @(& $faultScript -ConfigPath $configPath *>&1) } 'recovery snapshot retained'
    Assert-True ((Test-Path $snapshotPath) -and $mock.DeleteCount -eq 2) 'A partial injection cache failure keeps the original baseline.'
    Assert-True (($output -join "`n") -notmatch 'Greetings from the Intern') 'Cache failure must not report successful introduction.'
    $mock.FailFlushAt = 0
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True (!(Test-Path $snapshotPath)) 'Restore recovers after a partially failed cache refresh.'

    Reset-Fixture
    & $faultScript -ConfigPath $configPath
    $mock.FailFlushAt = 4
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } 'recovery snapshot retained'
    Assert-True ($mock.Rules.Count -eq 4 -and (Test-Path $snapshotPath)) 'Restore reinstates firewall access even if a subsequent cache refresh fails.'
    $mock.FailFlushAt = 0
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True (!(Test-Path $snapshotPath) -and $mock.CreateCount -eq 2) 'Restore retries cache refresh without recreating already-restored rules.'
    Assert-True (@($mock.Connections | Where-Object { !$_.Disposed }).Count -eq 0) 'Dispose all connections after restore retries.'

    Reset-Fixture
    & $faultScript -ConfigPath $configPath
    $mock.FailToken = $true
    Assert-Fails { & $faultScript -ConfigPath $configPath -Restore } 'recovery snapshot retained'
    Assert-True ($mock.Rules.Count -eq 4 -and (Test-Path $snapshotPath)) 'Even unavailable operator authentication must not block restoring the firewall allowance.'
    $mock.FailToken = $false
    & $faultScript -ConfigPath $configPath -Restore
    Assert-True (!(Test-Path $snapshotPath)) 'Restoration can finish once operator authentication is available.'

    Reset-Fixture
    $fixture = Get-Content $configPath -Raw | ConvertFrom-Json
    $fixture.resources.databaseNames = @()
    $fixture | ConvertTo-Json -Depth 4 | Set-Content $configPath
    Assert-Fails { & $faultScript -ConfigPath $configPath } 'resources.databaseNames'
    Assert-True ($mock.DeleteCount -eq 0 -and !(Test-Path $snapshotPath)) 'Missing database configuration must not leave an injected incident.'

    Write-Host "PASS: $checks SQL firewall regression checks; all Azure calls mocked, no live faults."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
