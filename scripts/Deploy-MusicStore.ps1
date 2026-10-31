#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$SubscriptionId,
    [string]$ResourceGroupName,
    [string]$Location,
    [string]$EnvironmentName,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\azure.local.json'),
    [string]$DeploymentClientIp,
    [ValidatePattern('^[a-zA-Z0-9_][a-zA-Z0-9_.-]{0,127}$')]
    [string]$ImageTag = "deploy-$([DateTime]::UtcNow.ToString('yyyyMMddHHmmss'))",
    [switch]$PreviewOnly,
    [switch]$SkipImageBuild,
    [switch]$ResetDemoConfiguration
)

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$template = Join-Path $root 'src\infra\subscription.bicep'
$appDirectory = Join-Path $root 'src\MvcMusicStore'
$required = @()
foreach ($name in 'ResourceGroupName', 'Location', 'EnvironmentName') {
    if (!$PSBoundParameters.ContainsKey($name)) {
        $required += "deployment.$($name.Substring(0, 1).ToLowerInvariant())$($name.Substring(1))"
    }
}
$config = & (Join-Path $PSScriptRoot 'Get-AzureLocalConfig.ps1') -ConfigPath $ConfigPath -RequiredSettings $required
foreach ($name in 'SubscriptionId', 'ResourceGroupName', 'Location', 'EnvironmentName') {
    if (!$PSBoundParameters.ContainsKey($name)) {
        $key = $name.Substring(0, 1).ToLowerInvariant() + $name.Substring(1)
        Set-Variable -Name $name -Value $config.deployment.$key
    }
}
if ($SubscriptionId -notmatch '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') {
    throw 'Supply a valid subscription GUID.'
}
if ([string]::IsNullOrWhiteSpace($ResourceGroupName) -or [string]::IsNullOrWhiteSpace($Location) -or
    [string]::IsNullOrWhiteSpace($EnvironmentName)) { throw 'Deployment target settings must not be empty.' }

function Invoke-Azure {
    param([string[]]$Arguments)
    $output = & az @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Azure CLI failed: az $($Arguments -join ' ')"
    }
    return $output
}

$account = Invoke-Azure @(
    'account', 'show', '--subscription', $SubscriptionId, '--output', 'json'
) | ConvertFrom-Json
if ($account.state -ne 'Enabled') {
    throw 'The requested subscription is not enabled.'
}
$existingApps = @()
$groupExists = Invoke-Azure @(
    'group', 'exists', '--subscription', $SubscriptionId, '--name', $ResourceGroupName
)
if ($groupExists -eq 'true') {
    $existingApps = @(Invoke-Azure @(
        'containerapp', 'list', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName,
        '--query', '[].{name:name,mode:properties.configuration.activeRevisionsMode}',
        '--output', 'json'
    ) | ConvertFrom-Json)
}
if (($existingApps | Where-Object { $_.mode -eq 'Multiple' }) -and !$ResetDemoConfiguration) {
    throw 'Multiple-revision demo configuration exists. Use native az commands to stage changes; this script restores Single mode/one replica. Supply -ResetDemoConfiguration only to intentionally end the demo.'
}
$operator = Invoke-Azure @('ad', 'signed-in-user', 'show', '--output', 'json') | ConvertFrom-Json

if (!$DeploymentClientIp) {
    $DeploymentClientIp = (Invoke-RestMethod 'https://api.ipify.org').Trim()
}
$address = [System.Net.IPAddress]::Parse($DeploymentClientIp)
if ($address.AddressFamily -ne [System.Net.Sockets.AddressFamily]::InterNetwork) {
    throw 'DeploymentClientIp must be a public IPv4 address.'
}

$parameters = @(
    "resourceGroupName=$ResourceGroupName"
    "location=$Location"
    "environmentName=$EnvironmentName"
    "sqlAdministratorObjectId=$($operator.id)"
    "sqlAdministratorLogin=$($operator.userPrincipalName)"
    "sqlDeploymentClientIp=$DeploymentClientIp"
)
$deployment = @(
    '--subscription', $SubscriptionId,
    '--location', $Location,
    '--template-file', $template,
    '--parameters'
) + $parameters

Invoke-Azure @('bicep', 'build', '--file', $template, '--stdout') | Out-Null
Write-Host 'Validating and previewing infrastructure (public SQL access from Azure and the deployment client).'
Invoke-Azure (@('deployment', 'sub', 'validate') + $deployment + @('--output', 'none')) | Out-Host
Invoke-Azure (@('deployment', 'sub', 'what-if') + $deployment + @('--result-format', 'ResourceIdOnly')) | Out-Host
if ($PreviewOnly) {
    return
}

Write-Host 'Provisioning infrastructure through Bicep.'
$resources = Invoke-Azure (@('deployment', 'sub', 'create', '--name', "$EnvironmentName-foundation") +
    $deployment + @('--query', 'properties.outputs.resources.value', '--output', 'json')) | ConvertFrom-Json

$imageName = "musicstore:$ImageTag"
if ($SkipImageBuild) {
    Invoke-Azure @(
        'acr', 'repository', 'show', '--subscription', $SubscriptionId,
        '--name', $resources.registryName, '--image', $imageName, '--output', 'none'
    ) | Out-Host
}
else {
    Write-Host "Building and publishing $imageName using ACR Tasks."
    Invoke-Azure @(
        'acr', 'build', '--subscription', $SubscriptionId,
        '--registry', $resources.registryName, '--image', $imageName,
        '--file', (Join-Path $appDirectory 'Dockerfile'), '--platform', 'linux/amd64', $appDirectory
    ) | Out-Host
}

# SQL data-plane grants cannot be declared as ARM resources. Use the operator's
# Entra token; creating the user from its SID avoids directory lookup permissions.
Write-Host 'Bootstrapping database-scoped access for the application managed identity.'
$sqlToken = Invoke-Azure @(
    'account', 'get-access-token', '--subscription', $SubscriptionId,
    '--resource', 'https://database.windows.net/', '--query', 'accessToken', '--output', 'tsv'
)
# Azure SQL stores the application/client ID in the SID for service principals,
# including managed identities; RBAC uses the different principal/object ID.
$sid = '0x' + [Convert]::ToHexString(([Guid]$resources.identityClientId).ToByteArray())
$userName = $resources.identityName.Replace(']', ']]')
$userLiteral = $resources.identityName.Replace("'", "''")
$grantSql = @"
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$userLiteral' AND sid <> $sid)
    THROW 50000, 'Existing database user has a different SID; review its identity before granting access.', 1;
IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'$userLiteral')
    CREATE USER [$userName] WITH SID = $sid, TYPE = E;
IF IS_ROLEMEMBER(N'db_datareader', N'$userLiteral') <> 1
    ALTER ROLE db_datareader ADD MEMBER [$userName];
IF IS_ROLEMEMBER(N'db_datawriter', N'$userLiteral') <> 1
    ALTER ROLE db_datawriter ADD MEMBER [$userName];
IF IS_ROLEMEMBER(N'db_ddladmin', N'$userLiteral') <> 1
    ALTER ROLE db_ddladmin ADD MEMBER [$userName];
"@

foreach ($database in $resources.databaseNames) {
    $connection = [System.Data.SqlClient.SqlConnection]::new(
        "Server=tcp:$($resources.sqlServerEndpoint),1433;Database=$database;Encrypt=True;TrustServerCertificate=False;Connect Timeout=60;"
    )
    $connection.AccessToken = $sqlToken
    try {
        $connection.Open()
        $command = $connection.CreateCommand()
        try {
            $command.CommandText = $grantSql
            $command.CommandTimeout = 120
            $null = $command.ExecuteNonQuery()
        }
        finally {
            $command.Dispose()
        }
    }
    finally {
        $connection.Dispose()
    }
}
$sqlToken = $null

$digest = Invoke-Azure @(
    'acr', 'repository', 'show', '--subscription', $SubscriptionId,
    '--name', $resources.registryName, '--image', $imageName,
    '--query', 'digest', '--output', 'tsv'
)
if ($digest -notmatch '^sha256:[0-9a-f]{64}$') {
    throw 'The registry did not return a valid image digest.'
}
$image = "$($resources.registryEndpoint)/musicstore@$digest"
$appDeployment = $deployment + @('deployApplication=true', "containerImage=$image")
Write-Host "Validating and previewing application image $image."
Invoke-Azure (@('deployment', 'sub', 'validate') + $appDeployment + @('--output', 'none')) | Out-Host
Invoke-Azure (@('deployment', 'sub', 'what-if') + $appDeployment + @('--result-format', 'ResourceIdOnly')) | Out-Host
Write-Host 'Deploying application through Bicep.'
$result = Invoke-Azure (@('deployment', 'sub', 'create', '--name', "$EnvironmentName-application") +
    $appDeployment + @('--query', 'properties.outputs.resources.value', '--output', 'json')) | ConvertFrom-Json

Write-Host 'Waiting for the deployed revision to become healthy and receive all traffic.'
$rolledOut = $false
for ($attempt = 1; $attempt -le 60; $attempt++) {
    $state = Invoke-Azure @(
        'containerapp', 'show', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName, '--name', $result.appName,
        '--output', 'json'
    ) | ConvertFrom-Json
    $revisions = @(Invoke-Azure @(
        'containerapp', 'revision', 'list', '--subscription', $SubscriptionId,
        '--resource-group', $ResourceGroupName, '--name', $result.appName,
        '--output', 'json'
    ) | ConvertFrom-Json)
    $latest = $revisions | Where-Object { $_.name -eq $state.properties.latestRevisionName }
    $otherTraffic = @($revisions | Where-Object {
        $_.name -ne $state.properties.latestRevisionName -and $_.properties.trafficWeight -gt 0
    })
    if ($latest -and
        $state.properties.latestRevisionName -eq $state.properties.latestReadyRevisionName -and
        $latest.properties.healthState -eq 'Healthy' -and
        $latest.properties.trafficWeight -eq 100 -and
        $otherTraffic.Count -eq 0 -and
        $latest.properties.template.containers[0].image -eq $image) {
        $rolledOut = $true
        break
    }
    Start-Sleep -Seconds 10
}
if (!$rolledOut) {
    throw 'The new image did not complete rollout. A previous healthy revision is not proof that the deployment succeeded.'
}

Write-Host "Checking readiness at $($result.applicationUrl)/health/ready"
$ready = $false
for ($attempt = 1; $attempt -le 30; $attempt++) {
    try {
        $response = Invoke-WebRequest "$($result.applicationUrl)/health/ready" -TimeoutSec 20
        if ($response.StatusCode -eq 200 -and $response.Content.Trim() -eq 'Healthy') {
            $ready = $true
            break
        }
        Write-Warning "Readiness attempt $attempt returned unexpected content."
    }
    catch {
        Write-Warning "Readiness attempt $attempt failed: $($_.Exception.Message)"
    }
    Start-Sleep -Seconds 10
}
if (!$ready) {
    throw 'The application did not become database-ready. Inspect Container Apps logs before accepting the deployment.'
}
$config.deployment.subscriptionId = $SubscriptionId
$config.deployment.resourceGroupName = $ResourceGroupName
$config.deployment.location = $Location
$config.deployment.environmentName = $EnvironmentName
foreach ($name in 'registryName', 'registryEndpoint', 'sqlServerName', 'sqlServerEndpoint',
    'databaseNames', 'identityName', 'identityPrincipalId', 'identityClientId', 'applicationUrl', 'logWorkspaceId',
    'keyVaultName', 'logWorkspaceName', 'applicationInsightsName') {
    $config.resources | Add-Member -NotePropertyName $name -NotePropertyValue $result.$name -Force
}
$config.resources.containerAppName = $result.appName
$config.resources.containerAppEnvironmentName = $result.environmentName
$config | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ConfigPath -Encoding utf8
Write-Host 'Deployment settings saved to the local configuration file.'
$result | ConvertTo-Json -Depth 5
