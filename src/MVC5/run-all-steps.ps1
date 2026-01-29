# Step-by-Step Commands to Containerize MvcMusicStore
# Copy and paste these commands one at a time

# ============================================
# STEP 1: Switch Docker to Windows Containers
# ============================================
# You MUST do this manually:
# 1. Right-click Docker Desktop icon (system tray)
# 2. Click "Switch to Windows containers..."
# 3. Wait for Docker to restart

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "STEP 1: Switch to Windows Containers" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "ACTION REQUIRED:" -ForegroundColor Yellow
Write-Host "1. Right-click Docker Desktop icon in system tray" -ForegroundColor White
Write-Host "2. Click 'Switch to Windows containers...'" -ForegroundColor White
Write-Host "3. Wait for Docker to restart" -ForegroundColor White
Write-Host ""
Write-Host "Press Enter AFTER you have switched to Windows containers..." -ForegroundColor Green
$null = Read-Host

# ============================================
# STEP 2: Verify Docker is in Windows Mode
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "STEP 2: Verifying Docker Mode" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$osType = docker info --format '{{.OSType}}' 2>&1
Write-Host "Current Docker mode: $osType" -ForegroundColor $(if ($osType -eq "windows") { "Green" } else { "Red" })

if ($osType -ne "windows") {
    Write-Host ""
    Write-Host "ERROR: Docker is still in Linux mode!" -ForegroundColor Red
    Write-Host "Please switch to Windows containers and run this script again." -ForegroundColor Yellow
    exit 1
}

Write-Host "? Docker is correctly configured!" -ForegroundColor Green
Write-Host ""
Write-Host "Press Enter to continue to environment verification..." -ForegroundColor Cyan
$null = Read-Host

# ============================================
# STEP 3: Run Environment Verification
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "STEP 3: Running Environment Verification" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

.\verify-docker-environment.ps1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Environment verification failed. Please fix the issues above." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Press Enter to continue to building the image..." -ForegroundColor Cyan
$null = Read-Host

# ============================================
# STEP 4: Build Docker Image
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "STEP 4: Building Docker Image" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "This may take 5-10 minutes on first build..." -ForegroundColor Yellow
Write-Host ""

.\build-docker-image.ps1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Build failed. Check the error messages above." -ForegroundColor Red
    exit 1
}

Write-Host ""
Write-Host "Press Enter to continue to running the container..." -ForegroundColor Cyan
$null = Read-Host

# ============================================
# STEP 5: Run Docker Container
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "STEP 5: Running Docker Container" -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

.\run-docker-container.ps1

if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "Failed to start container. Check the error messages above." -ForegroundColor Red
    exit 1
}

# ============================================
# STEP 6: Success!
# ============================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "SUCCESS! Your Application is Containerized!" -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
Write-Host "? Your containerized application is now running!" -ForegroundColor Green
Write-Host ""
Write-Host "Access your application at:" -ForegroundColor Cyan
Write-Host "  http://localhost:8080" -ForegroundColor White -BackgroundColor DarkBlue
Write-Host ""
Write-Host "Useful commands:" -ForegroundColor Yellow
Write-Host "  View logs:       docker logs mvcmusicstore" -ForegroundColor White
Write-Host "  Stop container:  docker stop mvcmusicstore" -ForegroundColor White
Write-Host "  Start container: docker start mvcmusicstore" -ForegroundColor White
Write-Host ""
Write-Host "Open your web browser and navigate to http://localhost:8080" -ForegroundColor Cyan
Write-Host ""
