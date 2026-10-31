#requires -Version 7.0
[CmdletBinding()]
param(
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\azure.local.json'),
    [string[]]$RequiredSettings = @()
)

$ErrorActionPreference = 'Stop'
if (!(Test-Path -LiteralPath $ConfigPath -PathType Leaf)) {
    throw 'Local Azure configuration is missing. Copy config\azure.example.json to config\azure.local.json and supply your own subscription and settings.'
}
try {
    $config = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
}
catch {
    throw 'Local Azure configuration is not valid JSON. Correct the local file before continuing.'
}
if ($null -eq $config -or !$config.psobject.Properties['schemaVersion'] -or $config.schemaVersion -ne 1) {
    throw 'Local Azure configuration requires schemaVersion 1.'
}
foreach ($path in (@('deployment.subscriptionId') + $RequiredSettings | Select-Object -Unique)) {
    $value = $config
    foreach ($segment in $path.Split('.')) {
        if ($null -eq $value -or !$value.psobject.Properties[$segment]) {
            throw "Local Azure configuration requires '$path'. Supply your own value."
        }
        $value = $value.$segment
    }
    if ($null -eq $value -or [string]::IsNullOrWhiteSpace([string]$value)) {
        throw "Local Azure configuration requires '$path'. Supply your own value."
    }
}
$subscription = [Guid]::Empty
if (![Guid]::TryParse([string]$config.deployment.subscriptionId, [ref]$subscription) -or $subscription -eq [Guid]::Empty) {
    throw 'Local Azure configuration requires a nonempty subscription GUID. The Azure CLI default subscription is never used.'
}
$config
