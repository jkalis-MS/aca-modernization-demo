#requires -Version 7.4
<#
.SYNOPSIS
Introduces or restores the isolated demo's Azure SQL firewall regression.
.DESCRIPTION
Removes only server firewall rules whose start and end addresses are 0.0.0.0.
Saves a recovery snapshot beside the local Azure configuration before changing
anything. Public network access and all other firewall rules are left alone.
Does not restart revisions, change traffic, or verify a catalog outage.
Normal success output keeps the cause hidden; use -Verbose for operator details.
Repeating -Restore without a snapshot is a no-op only if the allowance is enabled.
.EXAMPLE
.\scripts\Introduce-Misterious-Regression.ps1
.EXAMPLE
.\scripts\Introduce-Misterious-Regression.ps1 -Restore
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\azure.local.json'),
    [switch]$Restore
)

$ErrorActionPreference = 'Stop'
$PSNativeCommandUseErrorActionPreference = $true
Set-StrictMode -Version Latest

$config = & (Join-Path $PSScriptRoot 'Get-AzureLocalConfig.ps1') -ConfigPath $ConfigPath -RequiredSettings @(
    'deployment.resourceGroupName', 'resources.sqlServerName'
)
$snapshotPath = Join-Path (Split-Path (Resolve-Path -LiteralPath $ConfigPath).Path -Parent) 'sql-firewall-regression.local.json'
if (!$Restore -and (Test-Path -LiteralPath $snapshotPath)) {
    throw "A recovery snapshot already exists at '$snapshotPath'. Use -Restore before introducing another fault; the original baseline will not be overwritten."
}

$server = az sql server show --subscription $config.deployment.subscriptionId --resource-group $config.deployment.resourceGroupName --name $config.resources.sqlServerName --query '{id:id,publicNetworkAccess:publicNetworkAccess}' --output json --only-show-errors | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($server.id)) {
    throw 'Azure CLI did not return the SQL server identity.'
}
if ($server.publicNetworkAccess -ne 'Enabled') {
    throw 'SQL public network access must already be Enabled. No firewall rules changed.'
}
$azure = @(
    '--subscription', $config.deployment.subscriptionId,
    '--resource-group', $config.deployment.resourceGroupName,
    '--server', $config.resources.sqlServerName,
    '--only-show-errors'
)
$rules = @(az sql server firewall-rule list @azure --output json | ConvertFrom-Json)

if ($Restore) {
    if (!(Test-Path -LiteralPath $snapshotPath -PathType Leaf)) {
        if ($rules | Where-Object {
            $_.startIpAddress -eq '0.0.0.0' -and $_.endIpAddress -eq '0.0.0.0'
        }) {
            Write-Verbose 'Azure-services allowance is already enabled. No recovery snapshot exists; no changes were made.'
            Write-Host 'Nothing to restore. Misterious regression is already reset.'
            return
        }
        throw "No recovery snapshot exists at '$snapshotPath', and the regression setting is not reset. Use the same checkout and -ConfigPath that introduced it; recovery requires the original baseline. No firewall rules changed."
    }
    $snapshot = Get-Content -LiteralPath $snapshotPath -Raw | ConvertFrom-Json
    if ($snapshot.schemaVersion -ne 1 -or $snapshot.serverId -ne $server.id -or
        $snapshot.publicNetworkAccess -ne 'Enabled') {
        throw 'Recovery snapshot does not match this SQL server and its original public-access setting. No firewall rules changed.'
    }
    $azureRules = @($snapshot.firewallRules | Where-Object {
        $_.startIpAddress -eq '0.0.0.0' -and $_.endIpAddress -eq '0.0.0.0'
    })
    if ($azureRules.Count -eq 0) {
        throw 'Recovery snapshot contains no Azure-services allowance. No firewall rules changed.'
    }
    foreach ($rule in $azureRules) {
        if ([string]::IsNullOrWhiteSpace($rule.name)) {
            throw 'Recovery snapshot contains an unnamed firewall rule. No firewall rules changed.'
        }
        $existing = @($rules | Where-Object name -EQ $rule.name)
        if ($existing.Count -gt 0 -and
            ($existing[0].startIpAddress -ne $rule.startIpAddress -or $existing[0].endIpAddress -ne $rule.endIpAddress)) {
            throw "Firewall rule '$($rule.name)' has different addresses. Refusing to overwrite an external change; recovery snapshot retained."
        }
    }
    if (!$PSCmdlet.ShouldProcess($server.id, 'Restore the saved Azure-services firewall allowance')) { return }
    foreach ($rule in $azureRules) {
        if (!($rules | Where-Object name -EQ $rule.name)) {
            az sql server firewall-rule create @azure --name $rule.name --start-ip-address $rule.startIpAddress --end-ip-address $rule.endIpAddress --output none
        }
    }
    $restored = @(az sql server firewall-rule list @azure --output json | ConvertFrom-Json)
    foreach ($rule in $azureRules) {
        if (!($restored | Where-Object {
            $_.name -eq $rule.name -and $_.startIpAddress -eq $rule.startIpAddress -and $_.endIpAddress -eq $rule.endIpAddress
        })) {
            throw "Firewall restoration could not be verified for '$($rule.name)'. Recovery snapshot retained."
        }
    }
    Remove-Item -LiteralPath $snapshotPath
    Write-Verbose 'Saved Azure-services firewall allowance restored. Recovery snapshot cleared for the next rehearsal.'
    Write-Verbose 'Allow time for propagation, then check catalog recovery; no revision was restarted.'
    Write-Host 'Misterious regression removed.'
    return
}

$azureRules = @($rules | Where-Object {
    $_.startIpAddress -eq '0.0.0.0' -and $_.endIpAddress -eq '0.0.0.0'
})
if ($azureRules.Count -eq 0) {
    throw 'The Azure-services firewall allowance is already disabled. No firewall rules changed or recovery snapshot created.'
}
if (!$PSCmdlet.ShouldProcess($server.id, 'Save the firewall baseline and disable the Azure-services allowance for all databases on this SQL server')) { return }

$snapshot = [ordered]@{
    schemaVersion = 1
    capturedAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    serverId = $server.id
    publicNetworkAccess = $server.publicNetworkAccess
    firewallRules = @($rules | Select-Object name, startIpAddress, endIpAddress)
}
$null = New-Item -ItemType File -Path $snapshotPath -Value ($snapshot | ConvertTo-Json -Depth 6)
Write-Verbose "Recovery snapshot saved: $snapshotPath"
Write-Verbose 'This fault affects every database and consumer using the Azure-services allowance on this SQL server.'
foreach ($rule in $azureRules) {
    az sql server firewall-rule delete @azure --name $rule.name --output none
}
$remaining = @(az sql server firewall-rule list @azure --output json | ConvertFrom-Json)
if ($remaining | Where-Object {
    $_.startIpAddress -eq '0.0.0.0' -and $_.endIpAddress -eq '0.0.0.0'
}) {
    throw 'The Azure-services allowance is still present. Recovery snapshot retained; inspect the firewall before continuing.'
}
Write-Verbose 'Azure-services firewall allowance disabled. Public network access and other firewall rules were not changed.'
Write-Verbose 'Existing SQL connections may keep working for several minutes. Other server/database firewall rules can also permit access; no revision was restarted.'
$restoreCommand = '.\scripts\Introduce-Misterious-Regression.ps1 -Restore'
if ($PSBoundParameters.ContainsKey('ConfigPath')) {
    $restoreCommand += " -ConfigPath '$($ConfigPath.Replace("'", "''"))'"
}
Write-Verbose "Restore in CONTROL: $restoreCommand"
Write-Host @'
M   M IIIII  SSS  TTTTT EEEEE RRRR  IIIII  OOO  U   U  SSS
MM MM   I   S       T   E     R   R   I   O   O U   U S
M M M   I    SSS    T   EEEE  RRRR    I   O   O U   U  SSS
M   M   I       S   T   E     R R     I   O   O U   U     S
M   M IIIII  SSS    T   EEEEE R  RR IIIII  OOO   UUU   SSS

RRRR  EEEEE  GGG  RRRR  EEEEE  SSS   SSS  IIIII  OOO  N   N
R   R E     G     R   R E     S     S       I   O   O NN  N
RRRR  EEEE  G GGG RRRR  EEEE   SSS   SSS    I   O   O N N N
R R   E     G   G R R   E         S     S   I   O   O N  NN
R  RR EEEEE  GGG  R  RR EEEEE  SSS   SSS  IIIII  OOO  N   N

IIIII N   N TTTTT RRRR   OOO  DDDD  U   U  CCC  EEEEE DDDD
  I   NN  N   T   R   R O   O D   D U   U C     E     D   D
  I   N N N   T   RRRR  O   O D   D U   U C     EEEE  D   D
  I   N  NN   T   R R   O   O D   D U   U C     E     D   D
IIIII N   N   T   R  RR  OOO  DDDD   UUU   CCC  EEEEE DDDD

       .-""""-.
      /  o  o  \      Misterious regression introduced.
     |    __    |     Greetings from the Intern :)
      \  \__/  /
       '------'
'@ -ForegroundColor Cyan
