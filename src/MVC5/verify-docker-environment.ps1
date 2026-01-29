# Docker Environment Verification Script for MvcMusicStore
# This script checks if Docker is properly configured to build the application

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Docker Environment Check" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# Check if Docker is installed
Write-Host "1. Checking Docker installation..." -ForegroundColor Yellow
try {
    $dockerVersion = docker --version
    Write-Host "   ? Docker is installed: $dockerVersion" -ForegroundColor Green
} catch {
    Write-Host "   ? Docker is not installed or not in PATH" -ForegroundColor Red
    Write-Host "   Please install Docker Desktop for Windows" -ForegroundColor Red
    exit 1
}

# Check if Docker daemon is running
Write-Host ""
Write-Host "2. Checking Docker daemon status..." -ForegroundColor Yellow
try {
    $dockerInfo = docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ? Docker daemon is running" -ForegroundColor Green
    } else {
        Write-Host "   ? Docker daemon is not running" -ForegroundColor Red
        Write-Host "   Please start Docker Desktop" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host "   ? Cannot connect to Docker daemon" -ForegroundColor Red
    Write-Host "   Please start Docker Desktop" -ForegroundColor Red
    exit 1
}

# Check if Windows containers are enabled
Write-Host ""
Write-Host "3. Checking container mode..." -ForegroundColor Yellow
$osType = docker info --format '{{.OSType}}' 2>&1
if ($osType -eq "windows") {
    Write-Host "   ? Docker is using Windows containers" -ForegroundColor Green
} else {
    Write-Host "   ? Docker is using Linux containers" -ForegroundColor Red
    Write-Host "   This application requires Windows containers" -ForegroundColor Red
    Write-Host "   To switch:" -ForegroundColor Yellow
    Write-Host "   - Right-click Docker Desktop icon in system tray" -ForegroundColor Yellow
    Write-Host "   - Select 'Switch to Windows containers...'" -ForegroundColor Yellow
    Write-Host "   - Wait for Docker to restart" -ForegroundColor Yellow
    exit 1
}

# Check if required base images are available or can be pulled
Write-Host ""
Write-Host "4. Checking base images..." -ForegroundColor Yellow
$buildImage = "mcr.microsoft.com/dotnet/framework/sdk:4.8"
$runtimeImage = "mcr.microsoft.com/dotnet/framework/aspnet:4.8"

Write-Host "   Checking build image: $buildImage" -ForegroundColor Gray
$buildImageExists = docker images -q $buildImage
if ($buildImageExists) {
    Write-Host "   ? Build image is available locally" -ForegroundColor Green
} else {
    Write-Host "   ? Build image not found locally (will be pulled during build)" -ForegroundColor Cyan
}

Write-Host "   Checking runtime image: $runtimeImage" -ForegroundColor Gray
$runtimeImageExists = docker images -q $runtimeImage
if ($runtimeImageExists) {
    Write-Host "   ? Runtime image is available locally" -ForegroundColor Green
} else {
    Write-Host "   ? Runtime image not found locally (will be pulled during build)" -ForegroundColor Cyan
}

# Check if Dockerfile exists
Write-Host ""
Write-Host "5. Checking project files..." -ForegroundColor Yellow
if (Test-Path "MvcMusicStore\Dockerfile") {
    Write-Host "   ? Dockerfile found" -ForegroundColor Green
} else {
    Write-Host "   ? Dockerfile not found in MvcMusicStore directory" -ForegroundColor Red
    exit 1
}

if (Test-Path "MvcMusicStore\.dockerignore") {
    Write-Host "   ? .dockerignore found" -ForegroundColor Green
} else {
    Write-Host "   ? .dockerignore not found (optional but recommended)" -ForegroundColor Cyan
}

if (Test-Path "MvcMusicStore\MvcMusicStore.csproj") {
    Write-Host "   ? Project file found" -ForegroundColor Green
} else {
    Write-Host "   ? Project file not found" -ForegroundColor Red
    exit 1
}

# Summary
Write-Host ""
Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Environment Check Complete!" -ForegroundColor Green
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Your environment is ready to build the Docker image." -ForegroundColor Green
Write-Host ""
Write-Host "To build the image, run:" -ForegroundColor Yellow
Write-Host "  cd MvcMusicStore" -ForegroundColor White
Write-Host "  docker build -t mvcmusicstore:v1 ." -ForegroundColor White
Write-Host ""
Write-Host "To run the container after building:" -ForegroundColor Yellow
Write-Host "  docker run -d -p 8080:80 --name mvcmusicstore mvcmusicstore:v1" -ForegroundColor White
Write-Host ""
Write-Host "Access the application at: http://localhost:8080" -ForegroundColor Cyan
Write-Host ""
