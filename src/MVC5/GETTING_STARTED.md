# ?? Getting Started - MvcMusicStore Containerization

?? **ENCOUNTERED BUILD ERROR?** See `QUICK_FIX_WINDOWS_CONTAINERS.md` for the solution!

This guide will help you get your MvcMusicStore application running in a Docker container in just a few steps!

## Prerequisites

Before you begin, ensure you have:

1. **Docker Desktop for Windows** installed
   - Download from: https://www.docker.com/products/docker-desktop/
   - Minimum version: Docker Desktop 4.0 or later

2. **Windows 10/11 or Windows Server 2016+**
   - Required for Windows containers

## Step-by-Step Guide

### Step 1: Start Docker Desktop

1. Launch **Docker Desktop** from the Start menu
2. Wait for Docker to fully start (icon in system tray will be steady green)

### Step 2: Switch to Windows Containers ?? **CRITICAL STEP**

**This step is REQUIRED!** The error you encountered means Docker is in Linux mode.

1. Right-click the **Docker Desktop icon** in the system tray (bottom-right of screen)
2. Look for the menu option:
   - If you see **"Switch to Windows containers..."** ? Click this!
   - If you see **"Switch to Linux containers..."** ? You're already in Windows mode ?
3. Wait for Docker to restart (this may take 1-2 minutes)
4. You'll see a notification when the switch is complete

**Why this matters:**
- Your application uses .NET Framework 4.0 (Windows only)
- The Docker base images (`mcr.microsoft.com/dotnet/framework/*`) only exist for Windows
- Linux containers cannot run .NET Framework applications

**Common error if you skip this:**
```
ERROR: no match for platform in manifest: not found
```

This is the error you just saw! It means Docker tried to pull a Windows image while in Linux mode.

### Step 3: Verify Your Environment

Open **PowerShell** and navigate to your project directory:

```powershell
cd C:\Users\jkalis\Source\Repos\MvcMusicStore2\src\MVC5
```

Run the environment verification script:

```powershell
.\verify-docker-environment.ps1
```

This will check:
- ? Docker installation
- ? Docker daemon is running
- ? Windows containers mode
- ? Required files exist

If all checks pass, you're ready to build! ??

### Step 4: Build the Docker Image

Build your Docker image using the helper script:

```powershell
.\build-docker-image.ps1
```

**What happens during the build:**
1. Downloads base images (first time only - may take 5-10 minutes)
2. Restores NuGet packages
3. Compiles your application
4. Creates optimized container image

**Expected output:**
```
Building MvcMusicStore Docker Image
Image name: mvcmusicstore:v1
...
Build Successful! ?
```

### Step 5: Run the Container

Start your application in a container:

```powershell
.\run-docker-container.ps1
```

**What happens:**
1. Creates a new container from your image
2. Maps port 8080 on your machine to port 80 in the container
3. Starts the application

**Expected output:**
```
Container Started Successfully! ?
Access the application at: http://localhost:8080
```

### Step 6: Access Your Application

Open your web browser and navigate to:

```
http://localhost:8080
```

You should see the MvcMusicStore home page! ??

## Quick Reference Commands

### Using Helper Scripts (Recommended)

```powershell
# Check environment
.\verify-docker-environment.ps1

# Build image
.\build-docker-image.ps1

# Build image without cache (clean build)
.\build-docker-image.ps1 -NoBuildCache

# Run container
.\run-docker-container.ps1

# Run container on different port
.\run-docker-container.ps1 -Port 9090
```

### Using Docker Commands Directly

```powershell
# Build image
cd MvcMusicStore
docker build -t mvcmusicstore:v1 .

# Run container
docker run -d -p 8080:80 --name mvcmusicstore mvcmusicstore:v1

# View running containers
docker ps

# View all containers (including stopped)
docker ps -a

# View container logs
docker logs mvcmusicstore

# Follow logs in real-time
docker logs -f mvcmusicstore

# Stop container
docker stop mvcmusicstore

# Start stopped container
docker start mvcmusicstore

# Remove container
docker rm mvcmusicstore

# Remove container (force, even if running)
docker rm -f mvcmusicstore

# View images
docker images

# Remove image
docker rmi mvcmusicstore:v1
```

## Troubleshooting

### Problem: "no match for platform in manifest: not found" ?? **YOU ARE HERE**

**This is your current error!** This means Docker is in Linux containers mode.

**Solution:**
1. Right-click Docker Desktop icon in system tray
2. Click "Switch to Windows containers..."
3. Wait for Docker to restart (1-2 minutes)
4. Run `.\verify-docker-environment.ps1` to confirm
5. Run `.\build-docker-image.ps1` again

**Quick verification:**
```powershell
docker info --format '{{.OSType}}'
```
Should return: `windows` (not `linux`)

### Problem: "Docker daemon is not running"

**Solution:**
1. Start Docker Desktop from the Start menu
2. Wait for it to fully start (green icon in system tray)
3. Try again

### Problem: "Image OS mismatch" or "no matching manifest"

**Solution:**
1. Right-click Docker Desktop icon
2. Select "Switch to Windows containers..."
3. Wait for restart
4. Try building again

### Problem: Build fails with NuGet errors

**Solution:**
1. Check internet connection
2. Rebuild without cache: `.\build-docker-image.ps1 -NoBuildCache`
3. Ensure packages.config exists in MvcMusicStore folder

### Problem: Container starts but can't access application

**Solution:**
1. Check if container is running: `docker ps`
2. Check container logs: `docker logs mvcmusicstore`
3. Verify port mapping (should show `0.0.0.0:8080->80/tcp`)
4. Try a different port: `.\run-docker-container.ps1 -Port 9090`
5. Check Windows Firewall isn't blocking the port

### Problem: Application works locally but not in container

**Solution:**
1. Check for hardcoded paths (use relative paths)
2. Verify database files are copied (check .dockerignore)
3. Check Web.config connection strings
4. Review container logs for errors

## Next Steps

### For Development

1. **Make code changes** in Visual Studio
2. **Rebuild the image**: `.\build-docker-image.ps1`
3. **Stop old container**: `docker stop mvcmusicstore`
4. **Remove old container**: `docker rm mvcmusicstore`
5. **Run new container**: `.\run-docker-container.ps1`

### For Production Deployment

See the detailed guides:
- **MvcMusicStore/DOCKER_README.md** - Comprehensive Docker guide
- **.azure/CONTAINERIZATION_SUMMARY.md** - Production recommendations

Key steps for Azure deployment:
1. Create Azure Container Registry
2. Push your image to ACR
3. Deploy to Azure App Service or Container Instances
4. Configure Azure SQL Database
5. Set up Application Insights monitoring

## Additional Resources

### Documentation
- **DOCKER_README.md** - Detailed Docker documentation
- **CONTAINERIZATION_SUMMARY.md** - Complete containerization overview
- **containerization-plan.copilot.md** - Original containerization plan

### Helper Scripts
- **verify-docker-environment.ps1** - Check Docker setup
- **build-docker-image.ps1** - Build with options
- **run-docker-container.ps1** - Run with configuration

### Online Resources
- [Docker Documentation](https://docs.docker.com/)
- [Windows Containers](https://docs.microsoft.com/en-us/virtualization/windowscontainers/)
- [Azure Container Services](https://azure.microsoft.com/en-us/products/category/containers/)

## Success Checklist

- [ ] Docker Desktop installed and running
- [ ] Switched to Windows containers mode
- [ ] Environment verification passed
- [ ] Docker image built successfully
- [ ] Container is running
- [ ] Application accessible at http://localhost:8080
- [ ] Read documentation for production deployment

## Need Help?

1. **Check the logs**: `docker logs mvcmusicstore`
2. **Review the troubleshooting section** above
3. **Read the detailed documentation** in MvcMusicStore/DOCKER_README.md
4. **Verify your environment** with verify-docker-environment.ps1

---

**Congratulations!** ?? You've successfully containerized your MvcMusicStore application!
