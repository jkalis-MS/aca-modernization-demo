# ?? QUICK FIX - "no match for platform in manifest" Error

## What Happened?

You got this error:
```
ERROR: failed to resolve source metadata for mcr.microsoft.com/dotnet/framework/aspnet:4.8: 
no match for platform in manifest: not found
```

## What Does It Mean?

**Docker is in Linux containers mode**, but your application needs **Windows containers**.

.NET Framework 4.0/4.8 applications can ONLY run on Windows. The Docker base images for .NET Framework only have Windows container versions, not Linux versions.

## The Fix (Takes 2 Minutes)

### Step 1: Switch Docker to Windows Containers

1. **Find the Docker Desktop icon** in your system tray (bottom-right corner of screen, near the clock)
   
2. **Right-click the Docker icon** (it looks like a whale)

3. **Look at the menu:**
   - If you see **"Switch to Windows containers..."** ? Click this option!
   - If you see **"Switch to Linux containers..."** ? You're already OK (shouldn't happen)

4. **Wait for Docker to restart**
   - You'll see a notification saying Docker is restarting
   - This takes 1-2 minutes
   - The Docker icon might change colors

5. **Wait for the green icon**
   - When Docker Desktop shows a steady green icon, it's ready

### Step 2: Verify the Switch

Open PowerShell and run:

```powershell
docker info --format '{{.OSType}}'
```

**Expected output:** `windows`

If you see `linux`, the switch didn't complete. Try right-clicking Docker again.

### Step 3: Run the Verification Script

```powershell
.\verify-docker-environment.ps1
```

You should see:
```
? Docker is using Windows containers
```

### Step 4: Try Building Again

```powershell
.\build-docker-image.ps1
```

This time it should work! ??

## Why Does This Happen?

- Docker Desktop defaults to **Linux containers** because most containers are Linux-based
- **Windows containers** are only needed for Windows-specific applications like .NET Framework
- .NET Framework 4.0/4.8 are Windows-only technologies (older .NET)
- .NET Core and .NET 5+ can run on Linux, but not .NET Framework

## Visual Guide

### Finding Docker Desktop

```
System Tray (bottom-right):
??????????????????????????????????
?  [Time] [Volume] [Network] [??]?  ? Docker icon (whale)
??????????????????????????????????
```

### Right-Click Menu

```
????????????????????????????????????????
? Docker Desktop                       ?
????????????????????????????????????????
? Dashboard                            ?
? Settings                             ?
? Check for updates                    ?
? Troubleshoot                         ?
? Switch to Windows containers...   ? Click this!
? About Docker Desktop                 ?
? Quit Docker Desktop                  ?
????????????????????????????????????????
```

## Still Having Issues?

### Issue: Don't see "Switch to Windows containers"

**Possible causes:**
1. You're already in Windows mode (check with `docker info --format '{{.OSType}}'`)
2. Docker Desktop hasn't fully started yet (wait 30 seconds and try again)
3. Your Docker Desktop version is too old (update Docker Desktop)

### Issue: Switch fails or times out

**Solutions:**
1. Close Docker Desktop completely: Right-click ? Quit Docker Desktop
2. Wait 10 seconds
3. Start Docker Desktop from the Start menu
4. Wait for it to fully start
5. Try switching again

### Issue: Still getting the error after switching

**Verification steps:**
```powershell
# 1. Check OS type
docker info --format '{{.OSType}}'
# Should show: windows

# 2. Check Docker version
docker version
# Should show "OS/Arch: windows/amd64" in Server section

# 3. Try pulling a Windows image manually
docker pull mcr.microsoft.com/windows/nanoserver:ltsc2022
# Should succeed if Windows containers are working
```

## Quick Reference

| Command | Expected Result |
|---------|----------------|
| `docker info --format '{{.OSType}}'` | Should return `windows` |
| `.\verify-docker-environment.ps1` | Should show ? for Windows containers |
| `.\build-docker-image.ps1` | Should start downloading Windows base images |

## Next Steps After Switching

1. ? Switch to Windows containers (you're doing this now)
2. ? Run `.\verify-docker-environment.ps1`
3. ? Run `.\build-docker-image.ps1`
4. ? Run `.\run-docker-container.ps1`
5. ? Open http://localhost:8080

## More Help

- Full guide: `GETTING_STARTED.md`
- Detailed docs: `MvcMusicStore/DOCKER_README.md`
- Run verification: `.\verify-docker-environment.ps1`

---

**TL;DR:** Right-click Docker icon ? Click "Switch to Windows containers..." ? Wait ? Try again ?
