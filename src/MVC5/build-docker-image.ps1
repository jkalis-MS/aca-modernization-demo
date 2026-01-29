# Build Script for MvcMusicStore Docker Image
# This script builds the Docker image with proper error handling

param(
    [string]$Tag = "v1",
    [string]$ImageName = "mvcmusicstore",
    [switch]$NoBuildCache
)

$ErrorActionPreference = "Stop"

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Building MvcMusicStore Docker Image" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is in Windows containers mode
Write-Host "Checking Docker container mode..." -ForegroundColor Yellow
try {
    $osType = docker info --format '{{.OSType}}' 2>&1
    if ($osType -ne "windows") {
        Write-Host ""
        Write-Host "=====================================" -ForegroundColor Red
        Write-Host "ERROR: Docker is in Linux mode!" -ForegroundColor Red
        Write-Host "=====================================" -ForegroundColor Red
        Write-Host ""
        Write-Host "This application requires Windows containers." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "To switch to Windows containers:" -ForegroundColor Cyan
        Write-Host "  1. Right-click the Docker Desktop icon in the system tray" -ForegroundColor White
        Write-Host "  2. Click 'Switch to Windows containers...'" -ForegroundColor White
        Write-Host "  3. Wait for Docker to restart (1-2 minutes)" -ForegroundColor White
        Write-Host "  4. Run this script again" -ForegroundColor White
        Write-Host ""
        Write-Host "Or run the verification script first:" -ForegroundColor Cyan
        Write-Host "  .\verify-docker-environment.ps1" -ForegroundColor White
        Write-Host ""
        exit 1
    }
    Write-Host "? Docker is in Windows containers mode" -ForegroundColor Green
} catch {
    Write-Host "? Could not verify Docker mode" -ForegroundColor Yellow
}
Write-Host ""

# Navigate to the project directory
$scriptPath = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectPath = Join-Path $scriptPath "MvcMusicStore"

if (-not (Test-Path $projectPath)) {
    Write-Host "Error: MvcMusicStore directory not found at $projectPath" -ForegroundColor Red
    exit 1
}

Set-Location $projectPath
Write-Host "Building from: $projectPath" -ForegroundColor Gray
Write-Host ""

# Build the Docker image
$fullImageName = "${ImageName}:${Tag}"
Write-Host "Image name: $fullImageName" -ForegroundColor Yellow
Write-Host ""

$buildArgs = @("build", "-t", $fullImageName)

if ($NoBuildCache) {
    Write-Host "Building without cache..." -ForegroundColor Yellow
    $buildArgs += "--no-cache"
}

$buildArgs += "."

Write-Host "Running: docker $($buildArgs -join ' ')" -ForegroundColor Gray
Write-Host ""
Write-Host "This may take several minutes on first build (downloading base images)..." -ForegroundColor Cyan
Write-Host ""

try {
    & docker $buildArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "==================================" -ForegroundColor Green
        Write-Host "Build Successful! ?" -ForegroundColor Green
        Write-Host "==================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Image: $fullImageName" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "To run the container:" -ForegroundColor Yellow
        Write-Host "  docker run -d -p 8080:80 --name mvcmusicstore $fullImageName" -ForegroundColor White
        Write-Host ""
        Write-Host "To view running containers:" -ForegroundColor Yellow
        Write-Host "  docker ps" -ForegroundColor White
        Write-Host ""
        Write-Host "To view logs:" -ForegroundColor Yellow
        Write-Host "  docker logs mvcmusicstore" -ForegroundColor White
        Write-Host ""
        Write-Host "Access the application at: http://localhost:8080" -ForegroundColor Cyan
        Write-Host ""
    } else {
        Write-Host ""
        Write-Host "Build Failed!" -ForegroundColor Red
        Write-Host "Check the error messages above for details." -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "Build Failed with exception!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
