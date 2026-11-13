param(
	[ValidateNotNullOrEmpty()]
	[string]$Registry = 'azacrtnu2n32syw266',
	[string]$Repo = '',
	[ValidateNotNullOrEmpty()]
	[string]$ImageName = 'modernized-cached',
	[ValidateNotNullOrEmpty()]
	[string]$Tag = 'latest',
	[ValidateNotNullOrEmpty()]
	[string]$Context = $PSScriptRoot,
	[ValidateNotNullOrEmpty()]
	[string]$Subscription = '30501c6c-81f6-41ac-a388-d29cf43a020d',
	[switch]$NoWait
)

$ErrorActionPreference = 'Stop'

function Assert-AzCli {
	if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
		throw "Azure CLI 'az' not found. Install Azure CLI before running this script."
	}
}

Assert-AzCli

if (-not (Test-Path -LiteralPath $Context -PathType Container)) {
	throw "Build context directory not found: $Context"
}
$buildContext = (Resolve-Path -LiteralPath $Context).ProviderPath
$dockerfile = Join-Path $buildContext 'Dockerfile'
if (-not (Test-Path -LiteralPath $dockerfile -PathType Leaf)) {
	throw "Dockerfile not found: $dockerfile"
}

Write-Host 'Checking Azure CLI login and subscription access...'
& az account show --subscription $Subscription --output none 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
	throw "Azure CLI is not logged in or subscription '$Subscription' is unavailable. Run 'az login' and verify subscription access."
}

$repository = if ([string]::IsNullOrWhiteSpace($Repo)) { $ImageName } else { "$($Repo.Trim('/'))/$ImageName" }
$image = "$($repository):$Tag"

Write-Host "Building and pushing image $Registry.azurecr.io/$image from $buildContext"
$azArguments = @(
	'acr', 'build',
	'--subscription', $Subscription,
	'--registry', $Registry,
	'--image', $image,
	'--file', $dockerfile,
	'--platform', 'linux/amd64'
)
if ($NoWait) { $azArguments += '--no-wait' }
$azArguments += $buildContext

& az @azArguments
$buildExitCode = $LASTEXITCODE
if ($buildExitCode -ne 0) {
	Write-Error "az acr build failed with exit code $buildExitCode" -ErrorAction Continue
	exit $buildExitCode
}

if ($NoWait) {
	Write-Host "Build submitted: $Registry.azurecr.io/$image. Completion has not been verified."
} else {
	Write-Host "Build and push completed: $Registry.azurecr.io/$image"
}

# Examples:
# .\build-image.ps1
# .\build-image.ps1 -Tag v1 -NoWait
# .\build-image.ps1 -Registry myRegistry -Repo myRepo -ImageName myApp -Tag v1
