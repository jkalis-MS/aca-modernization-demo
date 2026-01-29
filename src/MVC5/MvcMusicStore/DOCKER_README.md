# MvcMusicStore - Docker Containerization Guide

## Overview
This guide explains how to build and run the MvcMusicStore application in a Docker container.

## Prerequisites
- **Docker Desktop for Windows** with Windows containers enabled
- Windows 10/11 or Windows Server 2016 or later

## Important Notes

### Windows Containers Required
This application uses **.NET Framework 4.0** and **ASP.NET MVC 3**, which require Windows containers. The Dockerfile uses:
- Base image: `mcr.microsoft.com/dotnet/framework/sdk:4.8` for building
- Runtime image: `mcr.microsoft.com/dotnet/framework/aspnet:4.8` for running

### Switch Docker to Windows Containers
Before building, ensure Docker Desktop is using Windows containers:
1. Right-click the Docker Desktop icon in the system tray
2. If you see "Switch to Windows containers...", click it
3. Wait for Docker to restart

## Building the Docker Image

Navigate to the MvcMusicStore directory and build the image:

```powershell
cd MvcMusicStore
docker build -t mvcmusicstore:v1 .
```

### Build Process
The Dockerfile uses a **multi-stage build**:
1. **Build Stage**: Uses the SDK image to restore NuGet packages and compile the application
2. **Runtime Stage**: Uses the lighter ASP.NET runtime image with only the published application files

This approach reduces the final image size by excluding build tools and intermediate files.

## Running the Container

Run the container with port mapping:

```powershell
docker run -d -p 8080:80 --name mvcmusicstore mvcmusicstore:v1
```

Access the application at: `http://localhost:8080`

## Configuration Recommendations

### Database Connection
The application currently uses **SQL Server Compact Edition** with a local database file:
```xml
<add name="MusicStoreEntities"
     connectionString="Data Source=|DataDirectory|MvcMusicStore.sdf"
     providerName="System.Data.SqlServerCe.4.0"/>
```

### For Production Deployment:
Consider migrating to a cloud-hosted database:
- **Azure SQL Database**
- **SQL Server in a separate container**

Update the connection string to use environment variables:
```xml
<add name="MusicStoreEntities"
     connectionString="Server=#{DB_SERVER}#;Database=#{DB_NAME}#;User Id=#{DB_USER}#;Password=#{DB_PASSWORD}#;"
     providerName="System.Data.SqlClient"/>
```

Replace these at runtime using:
- Docker environment variables (-e flag)
- Docker secrets
- Azure Key Vault (for Azure deployments)

## Dockerfile Structure

```dockerfile
# Build stage - compile the application
FROM mcr.microsoft.com/dotnet/framework/sdk:4.8 AS build
# ... restore packages and build ...

# Runtime stage - run the application
FROM mcr.microsoft.com/dotnet/framework/aspnet:4.8 AS runtime
# ... copy published files ...
```

## Files Created

1. **MvcMusicStore/Dockerfile** - Multi-stage build configuration
2. **MvcMusicStore/.dockerignore** - Excludes unnecessary files from build context

## Container Management Commands

```powershell
# List running containers
docker ps

# Stop the container
docker stop mvcmusicstore

# Start the container
docker start mvcmusicstore

# View logs
docker logs mvcmusicstore

# Remove the container
docker rm mvcmusicstore

# Remove the image
docker rmi mvcmusicstore:v1
```

## Troubleshooting

### Docker daemon not running
**Error**: `The system cannot find the file specified`
**Solution**: Start Docker Desktop

### Wrong container type
**Error**: Image OS mismatch
**Solution**: Switch Docker Desktop to Windows containers

### Build fails with NuGet restore errors
**Solution**: Ensure the packages.config file is present and properly formatted

## Next Steps

To deploy this application to Azure:
1. Push the image to **Azure Container Registry**
2. Deploy to **Azure Container Instances** or **Azure App Service** (Windows container support)
3. Configure connection strings using Azure Key Vault
4. Set up Application Insights for monitoring

## Security Considerations

- **Never hardcode credentials** in the Dockerfile or code
- Use **environment variables** or **secrets management** for sensitive data
- Keep base images updated to receive security patches
- Consider using Azure Managed Identity for Azure resources

## Additional Resources

- [Docker Documentation](https://docs.docker.com/)
- [Windows Containers Documentation](https://docs.microsoft.com/en-us/virtualization/windowscontainers/)
- [Azure Container Registry](https://azure.microsoft.com/services/container-registry/)
