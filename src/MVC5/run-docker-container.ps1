# Run Script for MvcMusicStore Docker Container
# This script runs the Docker container with proper configuration

param(
    [string]$Tag = "v1",
    [string]$ImageName = "mvcmusicstore",
    [string]$ContainerName = "mvcmusicstore",
    [int]$Port = 8080,
    [switch]$Detached = $true,
    [switch]$Remove
)

$ErrorActionPreference = "Stop"

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "Running MvcMusicStore Container" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

$fullImageName = "${ImageName}:${Tag}"

# Check if image exists
Write-Host "Checking for image: $fullImageName" -ForegroundColor Yellow
$imageExists = docker images -q $fullImageName
if (-not $imageExists) {
    Write-Host "Error: Image $fullImageName not found" -ForegroundColor Red
    Write-Host "Please build the image first using: .\build-docker-image.ps1" -ForegroundColor Yellow
    exit 1
}
Write-Host "? Image found" -ForegroundColor Green
Write-Host ""

# Check if container with same name already exists
$existingContainer = docker ps -a -q -f name=$ContainerName
if ($existingContainer) {
    Write-Host "Container '$ContainerName' already exists" -ForegroundColor Yellow
    
    $isRunning = docker ps -q -f name=$ContainerName
    if ($isRunning) {
        Write-Host "Container is currently running" -ForegroundColor Cyan
        $response = Read-Host "Do you want to stop and remove it? (y/n)"
        if ($response -eq 'y') {
            Write-Host "Stopping container..." -ForegroundColor Yellow
            docker stop $ContainerName | Out-Null
            Write-Host "Removing container..." -ForegroundColor Yellow
            docker rm $ContainerName | Out-Null
            Write-Host "? Container removed" -ForegroundColor Green
        } else {
            Write-Host "Exiting. Container is still running." -ForegroundColor Yellow
            Write-Host "Access it at: http://localhost:$Port" -ForegroundColor Cyan
            exit 0
        }
    } else {
        Write-Host "Container exists but is not running" -ForegroundColor Cyan
        $response = Read-Host "Do you want to remove it and create a new one? (y/n)"
        if ($response -eq 'y') {
            Write-Host "Removing container..." -ForegroundColor Yellow
            docker rm $ContainerName | Out-Null
            Write-Host "? Container removed" -ForegroundColor Green
        } else {
            Write-Host "Starting existing container..." -ForegroundColor Yellow
            docker start $ContainerName | Out-Null
            Write-Host "? Container started" -ForegroundColor Green
            Write-Host ""
            Write-Host "Access the application at: http://localhost:$Port" -ForegroundColor Cyan
            exit 0
        }
    }
    Write-Host ""
}

# Build run command
$runArgs = @("run")

if ($Detached) {
    $runArgs += "-d"
}

if ($Remove) {
    $runArgs += "--rm"
}

$runArgs += @("-p", "${Port}:80", "--name", $ContainerName, $fullImageName)

Write-Host "Running container..." -ForegroundColor Yellow
Write-Host "Command: docker $($runArgs -join ' ')" -ForegroundColor Gray
Write-Host ""

try {
    $containerId = & docker $runArgs
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "==================================" -ForegroundColor Green
        Write-Host "Container Started Successfully! ?" -ForegroundColor Green
        Write-Host "==================================" -ForegroundColor Green
        Write-Host ""
        Write-Host "Container ID: $containerId" -ForegroundColor Gray
        Write-Host "Container Name: $ContainerName" -ForegroundColor Cyan
        Write-Host "Port Mapping: ${Port}:80" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Access the application at: http://localhost:$Port" -ForegroundColor Green
        Write-Host ""
        Write-Host "Useful commands:" -ForegroundColor Yellow
        Write-Host "  View logs:       docker logs $ContainerName" -ForegroundColor White
        Write-Host "  Follow logs:     docker logs -f $ContainerName" -ForegroundColor White
        Write-Host "  Stop container:  docker stop $ContainerName" -ForegroundColor White
        Write-Host "  Start container: docker start $ContainerName" -ForegroundColor White
        Write-Host "  Remove container: docker rm $ContainerName" -ForegroundColor White
        Write-Host ""
        
        # Wait a moment and check if container is still running
        Start-Sleep -Seconds 2
        $stillRunning = docker ps -q -f name=$ContainerName
        if ($stillRunning) {
            Write-Host "? Container is running" -ForegroundColor Green
        } else {
            Write-Host "? Container may have stopped. Check logs:" -ForegroundColor Yellow
            Write-Host "  docker logs $ContainerName" -ForegroundColor White
        }
        Write-Host ""
    } else {
        Write-Host "Failed to start container!" -ForegroundColor Red
        exit 1
    }
} catch {
    Write-Host ""
    Write-Host "Failed to start container!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    exit 1
}
