#requires -Version 7.2
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$helper = Join-Path $PSScriptRoot 'Get-AzureLocalConfig.ps1'
$work = Join-Path $PSScriptRoot ".azure-config-test-$([Guid]::NewGuid().ToString('N'))"
$checks = 0

function Assert-Refused {
    param([scriptblock]$Action, [string]$Pattern)
    try { & $Action | Out-Null }
    catch {
        if ($_.Exception.Message -notmatch $Pattern) { throw }
        $script:checks++
        return
    }
    throw "Configuration should have been refused: $Pattern"
}

New-Item -ItemType Directory -Path $work | Out-Null
try {
    $missing = Join-Path $work 'missing.json'
    Assert-Refused { & $helper -ConfigPath $missing } 'configuration is missing'
    foreach ($script in 'Deploy-MusicStore.ps1', 'Watch-Demo.ps1', 'Invoke-DemoTraffic.ps1', 'Test-MusicStore.ps1') {
        $arguments = @{ ConfigPath = $missing }
        if ($script -eq 'Invoke-DemoTraffic.ps1') { $arguments.Scenario = 'Scale' }
        Assert-Refused { & (Join-Path $PSScriptRoot $script) @arguments } 'configuration is missing'
    }
    $path = Join-Path $work 'azure.local.json'
    Copy-Item (Join-Path $root 'config\azure.example.json') $path
    Assert-Refused { & $helper -ConfigPath $path } 'deployment.subscriptionId'
    $fixture = Get-Content $path -Raw | ConvertFrom-Json
    $fixture.deployment.subscriptionId = 'not-a-subscription'
    $fixture | ConvertTo-Json -Depth 10 | Set-Content $path
    Assert-Refused { & $helper -ConfigPath $path } 'subscription GUID'
    $fixture.deployment.subscriptionId = '00000000-0000-0000-0000-000000000000'
    $fixture | ConvertTo-Json -Depth 10 | Set-Content $path
    Assert-Refused { & $helper -ConfigPath $path } 'subscription GUID'
    $fixture.deployment.subscriptionId = '11111111-1111-4111-8111-111111111111'
    $fixture | ConvertTo-Json -Depth 10 | Set-Content $path
    Assert-Refused { & $helper -ConfigPath $path -RequiredSettings resources.applicationUrl } 'resources.applicationUrl'
    Assert-Refused { & $helper -ConfigPath $path -RequiredSettings missing.setting } 'missing.setting'
    $fixture.resources.applicationUrl = 'https://example.invalid'
    $fixture | ConvertTo-Json -Depth 10 | Set-Content $path
    $loaded = & $helper -ConfigPath $path -RequiredSettings resources.applicationUrl
    if ($loaded.resources.applicationUrl -ne 'https://example.invalid') { throw 'Required local value was not loaded.' }
    $checks++
    '{}' | Set-Content $path
    Assert-Refused { & $helper -ConfigPath $path } 'schemaVersion'
    '{invalid' | Set-Content $path
    Assert-Refused { & $helper -ConfigPath $path } 'not valid JSON'
    Write-Host "PASS: $checks local-configuration checks; no Azure requests or CLI fallback."
}
finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
