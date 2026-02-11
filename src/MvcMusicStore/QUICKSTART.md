# MVC Music Store - Quick Start Guide

## Running Locally with Docker

### Prerequisites
- Docker Desktop installed
- .NET 10 SDK installed (for development)

### Option 1: Docker Compose (with SQL Server)

```bash
# Start all services
docker-compose up -d

# View logs
docker-compose logs -f

# Access the application
# Open browser to: http://localhost:8080

# Stop services
docker-compose down

# Stop and remove volumes
docker-compose down -v
```

### Option 2: Docker only (requires external database)

```bash
# Build image
docker build -t mvcmusicstore -f MvcMusicStore/Dockerfile .

# Run container
docker run -p 8080:8080 \
  -e ConnectionStrings__MusicStoreEntities="Your connection string" \
  -e ConnectionStrings__DefaultConnection="Your connection string" \
  mvcmusicstore
```

## Running Locally without Docker

### Prerequisites
- .NET 10 SDK installed
- SQL Server or LocalDB installed

### Steps

```bash
# Restore packages
dotnet restore MvcMusicStore/MvcMusicStore.csproj

# Update database connection strings in appsettings.json

# Run database migrations
dotnet ef database update --project MvcMusicStore

# Run the application
dotnet run --project MvcMusicStore

# Access at: https://localhost:5001 or http://localhost:5000
```

## Database Setup

### Create Database and Run Migrations

```bash
# Install EF Core tools (if not installed)
dotnet tool install --global dotnet-ef

# Create migration (if needed)
dotnet ef migrations add InitialCreate --project MvcMusicStore

# Update database
dotnet ef database update --project MvcMusicStore
```

## Configuration

### Required Settings in appsettings.json or Environment Variables

```json
{
  "ConnectionStrings": {
    "MusicStoreEntities": "Server=...;Database=MvcMusicStore;...",
    "DefaultConnection": "Server=...;Database=MvcMusicStore-Identity;..."
  },
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=...;..." // Optional for Azure
  }
}
```

### Using Environment Variables

```bash
export ConnectionStrings__MusicStoreEntities="Server=..."
export ConnectionStrings__DefaultConnection="Server=..."
export ApplicationInsights__ConnectionString="InstrumentationKey=..."
```

## Troubleshooting

### Container won't start
- Check Docker logs: `docker logs <container-id>`
- Verify connection strings are correct
- Ensure SQL Server is running and accessible

### Database connection errors
- Verify connection string format
- Check SQL Server firewall rules
- For containers: use service name instead of localhost

### Application Insights not working
- Verify connection string is set
- Check Azure Portal for incoming telemetry
- Review logs for initialization errors

## Development Tips

### Watch for changes (hot reload)
```bash
dotnet watch run --project MvcMusicStore
```

### View container logs
```bash
docker logs -f <container-name>
```

### Access container shell
```bash
docker exec -it <container-name> /bin/bash
```

## Next Steps

1. Review [AZURE_DEPLOYMENT.md](AZURE_DEPLOYMENT.md) for Azure deployment
2. Check [AZURE_MONITOR_SETUP.md](AZURE_MONITOR_SETUP.md) for monitoring setup
3. Configure CI/CD pipeline for automated deployments

## Project Structure

```
MvcMusicStore/
??? Controllers/         # MVC Controllers
??? Models/             # Data models and DbContext
??? Views/              # Razor views
??? wwwroot/            # Static files (CSS, JS, images)
??? Program.cs          # Application entry point
??? appsettings.json    # Configuration
??? Dockerfile          # Container definition
??? docker-compose.yml  # Local development setup
```

## Support

For issues or questions:
- Check Application Insights for errors
- Review container logs
- Consult Azure Container Apps documentation
