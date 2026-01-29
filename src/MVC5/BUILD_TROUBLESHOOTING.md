# ?? Build Troubleshooting Guide

This guide addresses common issues when building the MvcMusicStore Docker image.

## ? Issue Fixed: NuGet Restore Error

### Error Message
```
Cannot determine the packages folder to restore NuGet packages. 
Please specify either -PackagesDirectory or -SolutionDirectory.
The command 'powershell -Command $ErrorActionPreference = 'Stop'; nuget restore' returned a non-zero code: 1
```

### What Happened
The NuGet restore command in the Dockerfile didn't specify where to restore packages. NuGet needs either:
- A solution file (.sln), or
- A packages directory location

### The Fix
? **Already fixed!** The Dockerfile now includes the correct command:

```dockerfile
RUN nuget restore MvcMusicStore.csproj -PackagesDirectory .\packages
```

### Verify the Fix
Check your `MvcMusicStore/Dockerfile` contains this line (around line 9):
```dockerfile
RUN nuget restore MvcMusicStore.csproj -PackagesDirectory .\packages
```

### Try Building Again
```powershell
.\build-docker-image.ps1
```

The build should now progress past the NuGet restore step!

---

## Common Build Issues & Solutions

### 1. Platform Manifest Error

**Error:**
```
no match for platform in manifest: not found
```

**Cause:** Docker is in Linux containers mode.

**Solution:** See `QUICK_FIX_WINDOWS_CONTAINERS.md`

### 2. NuGet Package Download Failures

**Error:**
```
Unable to load the service index for source https://api.nuget.org/v3/index.json
```

**Solutions:**
1. **Check internet connection**
2. **Check firewall/proxy settings**
3. **Try again** (sometimes NuGet servers are temporarily slow)
4. **Clean build:**
   ```powershell
   .\build-docker-image.ps1 -NoBuildCache
   ```

### 3. MSBuild Errors

**Error:**
```
error MSB4019: The imported project "..." was not found
```

**Solutions:**
1. Ensure all files are copied correctly (check .dockerignore)
2. Verify packages were restored successfully
3. Check that the project file exists and is valid

### 4. Missing Files During Build

**Error:**
```
COPY failed: file not found in build context
```

**Solutions:**
1. Check the file exists in the MvcMusicStore folder
2. Review `.dockerignore` - make sure needed files aren't excluded
3. Ensure you're running the build from the correct directory

### 5. Build Stage Failures

**Error:**
```
COPY --from=build failed
```

**Cause:** The build stage didn't produce output in the expected location.

**Solutions:**
1. Check MSBuild completed successfully
2. Verify the publish path: `C:\app\out\_PublishedWebsites\MvcMusicStore`
3. Look at build logs for MSBuild errors

### 6. Out of Disk Space

**Error:**
```
no space left on device
```

**Solutions:**
1. **Clean old containers:**
   ```powershell
   docker container prune
   ```

2. **Clean old images:**
   ```powershell
   docker image prune -a
   ```

3. **Clean build cache:**
   ```powershell
   docker builder prune
   ```

### 7. Network Timeout During Base Image Pull

**Error:**
```
failed to pull image: context deadline exceeded
```

**Solutions:**
1. Check internet connection
2. Check Docker Desktop is running properly
3. Try again (large Windows images can take time)
4. Increase Docker timeout in Settings ? Docker Engine

---

## Build Process Explained

Understanding what happens during the build helps troubleshoot issues:

### Stage 1: Build Stage
```dockerfile
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8 AS build
```
1. **Pull SDK image** (first time: ~5-10 minutes, ~10GB)
2. **Copy project files** (.csproj, packages.config)
3. **Restore NuGet packages** (downloads dependencies)
4. **Copy all source code**
5. **Run MSBuild** (compile and publish)

### Stage 2: Runtime Stage
```dockerfile
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8 AS runtime
```
1. **Pull ASP.NET runtime image** (first time: ~3-5 minutes, ~5GB)
2. **Copy published files** from build stage
3. **Configure IIS** (done by base image)

---

## Debugging Tips

### View Detailed Build Output
```powershell
cd MvcMusicStore
docker build -t mvcmusicstore:v1 --progress=plain .
```

### Check Available Disk Space
```powershell
docker system df
```

### Check Docker Resources
Open Docker Desktop ? Settings ? Resources ? Advanced
- **Memory:** Ensure at least 4GB allocated
- **Disk:** Ensure at least 20GB available

### Test NuGet Locally
```powershell
cd MvcMusicStore
nuget restore MvcMusicStore.csproj -PackagesDirectory .\packages
```

### Test MSBuild Locally
```powershell
cd MvcMusicStore
msbuild MvcMusicStore.csproj /p:Configuration=Release
```

---

## Expected Build Time

### First Build
- **Downloading base images:** 10-15 minutes
- **NuGet restore:** 1-2 minutes
- **MSBuild compilation:** 2-3 minutes
- **Total:** ~15-20 minutes

### Subsequent Builds
- **Using cached layers:** 30 seconds - 2 minutes
- **After code changes:** 2-4 minutes

---

## Verification Checklist

Before building, verify:
- [ ] Docker Desktop is running
- [ ] Docker is in Windows containers mode
- [ ] At least 20GB free disk space
- [ ] Internet connection is working
- [ ] MvcMusicStore/Dockerfile exists
- [ ] MvcMusicStore/MvcMusicStore.csproj exists
- [ ] MvcMusicStore/packages.config exists

---

## Still Having Issues?

### Collect Diagnostic Information

1. **Check Docker info:**
   ```powershell
   docker info
   ```

2. **Check Docker version:**
   ```powershell
   docker version
   ```

3. **Try verbose build:**
   ```powershell
   docker build -t mvcmusicstore:v1 --progress=plain --no-cache .
   ```

4. **Check Docker logs:**
   - Open Docker Desktop
   - Click the bug icon (Troubleshoot)
   - View logs

### Get Help

1. Review error messages carefully
2. Check this troubleshooting guide
3. See `QUICK_FIX_WINDOWS_CONTAINERS.md`
4. See `GETTING_STARTED.md`
5. Run `.\verify-docker-environment.ps1`

---

## Success Indicators

You'll know the build succeeded when you see:

```
Successfully built [image-id]
Successfully tagged mvcmusicstore:v1

Build Successful! ?
```

Then you can run:
```powershell
.\run-docker-container.ps1
```

---

**Most Common Issues:**
1. ? Docker in Linux mode ? Fixed by switching to Windows containers
2. ? NuGet restore error ? Fixed in Dockerfile
3. Network timeouts ? Check internet connection
4. Disk space ? Clean old images/containers
