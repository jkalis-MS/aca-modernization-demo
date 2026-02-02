# Azure Container Apps Deployment Guide

This guide walks through deploying the MVC Music Store application to Azure Container Apps.

## Prerequisites

- [Azure CLI](https://docs.microsoft.com/cli/azure/install-azure-cli) installed
- [Docker](https://docs.docker.com/get-docker/) installed (for local testing)
- Azure subscription
- Resource group created in Azure

## Architecture Overview

Azure Container Apps provides:
- Fully managed container hosting
- Auto-scaling (scale to zero)
- Built-in load balancing
- HTTPS termination
- Managed identity support
- Integration with Azure services

## Step 1: Build and Test Docker Image Locally

```bash
# Navigate to the solution directory
cd src/MVC5

# Build the Docker image
docker build -t mvcmusicstore:latest -f MvcMusicStore/Dockerfile .

# Test locally
docker run -p 8080:8080 mvcmusicstore:latest

# Open browser to http://localhost:8080
```

## Step 2: Create Azure Resources

```bash
# Login to Azure
az login

# Set variables
RESOURCE_GROUP="rg-musicstore"
LOCATION="eastus"
ENVIRONMENT="env-musicstore"
APP_NAME="musicstore-app"
ACR_NAME="acrmusicstore"  # Must be globally unique

# Create resource group
az group create \
  --name $RESOURCE_GROUP \
  --location $LOCATION

# Create Azure Container Registry
az acr create \
  --resource-group $RESOURCE_GROUP \
  --name $ACR_NAME \
  --sku Basic \
  --admin-enabled true

# Create Container Apps environment
az containerapp env create \
  --name $ENVIRONMENT \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

## Step 3: Push Image to Azure Container Registry

```bash
# Login to ACR
az acr login --name $ACR_NAME

# Tag image
docker tag mvcmusicstore:latest $ACR_NAME.azurecr.io/mvcmusicstore:latest

# Push image
docker push $ACR_NAME.azurecr.io/mvcmusicstore:latest

# Or build and push in one step
az acr build \
  --registry $ACR_NAME \
  --image mvcmusicstore:latest \
  --file MvcMusicStore/Dockerfile \
  .
```

## Step 4: Create Azure SQL Database

```bash
SQL_SERVER="sql-musicstore"
SQL_DB="musicstore"
SQL_ADMIN="sqladmin"
SQL_PASSWORD="YourStr0ngP@ssword"  # Change this!

# Create SQL Server
az sql server create \
  --name $SQL_SERVER \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --admin-user $SQL_ADMIN \
  --admin-password $SQL_PASSWORD

# Create database
az sql db create \
  --name $SQL_DB \
  --server $SQL_SERVER \
  --resource-group $RESOURCE_GROUP \
  --service-objective S0

# Allow Azure services to access
az sql server firewall-rule create \
  --resource-group $RESOURCE_GROUP \
  --server $SQL_SERVER \
  --name AllowAzureServices \
  --start-ip-address 0.0.0.0 \
  --end-ip-address 0.0.0.0

# Get connection string
CONNECTION_STRING="Server=tcp:$SQL_SERVER.database.windows.net,1433;Initial Catalog=$SQL_DB;Persist Security Info=False;User ID=$SQL_ADMIN;Password=$SQL_PASSWORD;MultipleActiveResultSets=True;Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"
```

## Step 5: Create Application Insights

```bash
APP_INSIGHTS="appi-musicstore"

# Create Application Insights
az monitor app-insights component create \
  --app $APP_INSIGHTS \
  --location $LOCATION \
  --resource-group $RESOURCE_GROUP \
  --application-type web

# Get connection string
APPINSIGHTS_CONNECTION_STRING=$(az monitor app-insights component show \
  --app $APP_INSIGHTS \
  --resource-group $RESOURCE_GROUP \
  --query connectionString -o tsv)
```

## Step 6: Deploy Container App

```bash
# Get ACR credentials
ACR_USERNAME=$(az acr credential show \
  --name $ACR_NAME \
  --query username -o tsv)

ACR_PASSWORD=$(az acr credential show \
  --name $ACR_NAME \
  --query passwords[0].value -o tsv)

# Create container app
az containerapp create \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --environment $ENVIRONMENT \
  --image $ACR_NAME.azurecr.io/mvcmusicstore:latest \
  --registry-server $ACR_NAME.azurecr.io \
  --registry-username $ACR_USERNAME \
  --registry-password $ACR_PASSWORD \
  --target-port 8080 \
  --ingress external \
  --cpu 0.5 \
  --memory 1Gi \
  --min-replicas 1 \
  --max-replicas 5 \
  --secrets \
    "connection-string=$CONNECTION_STRING" \
    "appinsights-connection=$APPINSIGHTS_CONNECTION_STRING" \
  --env-vars \
    "ASPNETCORE_ENVIRONMENT=Production" \
    "ConnectionStrings__MusicStoreEntities=secretref:connection-string" \
    "ConnectionStrings__DefaultConnection=secretref:connection-string" \
    "ApplicationInsights__ConnectionString=secretref:appinsights-connection"

# Get the application URL
az containerapp show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query properties.configuration.ingress.fqdn -o tsv
```

## Step 7: Run Database Migrations

You have several options to run EF Core migrations:

### Option A: Using Azure CLI (Recommended)
```bash
# Execute migrations in container
az containerapp exec \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --command "dotnet ef database update"
```

### Option B: Using Local dotnet-ef tool
```bash
# Install EF Core tools if not already installed
dotnet tool install --global dotnet-ef

# Run from your development machine
dotnet ef database update \
  --connection "$CONNECTION_STRING" \
  --project MvcMusicStore/MvcMusicStore.csproj
```

### Option C: Add to Dockerfile (Startup Migration)
Add this to your `Program.cs`:
```csharp
// Auto-migrate database on startup (use with caution in production)
using (var scope = app.Services.CreateScope())
{
    var db = scope.ServiceProvider.GetRequiredService<MusicStoreEntities>();
    db.Database.Migrate();
}
```

## Step 8: Configure Auto-Scaling Rules

```bash
# Scale based on HTTP requests
az containerapp update \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --scale-rule-name http-scaling \
  --scale-rule-type http \
  --scale-rule-http-concurrency 100

# Scale based on CPU
az containerapp update \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --scale-rule-name cpu-scaling \
  --scale-rule-type cpu \
  --scale-rule-metadata "type=Utilization" "value=70"
```

## Step 9: Set Up Custom Domain (Optional)

```bash
# Add custom domain
az containerapp hostname add \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --hostname www.yourdomain.com

# Bind certificate
az containerapp hostname bind \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --hostname www.yourdomain.com \
  --environment $ENVIRONMENT \
  --validation-method CNAME
```

## Step 10: Enable Continuous Deployment (CI/CD)

### Using GitHub Actions

Create `.github/workflows/deploy.yml`:

```yaml
name: Deploy to Azure Container Apps

on:
  push:
    branches: [ main ]

env:
  ACR_NAME: acrmusicstore
  RESOURCE_GROUP: rg-musicstore
  APP_NAME: musicstore-app

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3
    
    - name: Login to Azure
      uses: azure/login@v1
      with:
        creds: ${{ secrets.AZURE_CREDENTIALS }}
    
    - name: Build and push to ACR
      run: |
        az acr build \
          --registry ${{ env.ACR_NAME }} \
          --image mvcmusicstore:${{ github.sha }} \
          --file src/MVC5/MvcMusicStore/Dockerfile \
          src/MVC5
    
    - name: Update Container App
      run: |
        az containerapp update \
          --name ${{ env.APP_NAME }} \
          --resource-group ${{ env.RESOURCE_GROUP }} \
          --image ${{ env.ACR_NAME }}.azurecr.io/mvcmusicstore:${{ github.sha }}
```

## Monitoring and Troubleshooting

### View Logs
```bash
# Stream logs
az containerapp logs show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --follow

# View recent logs
az containerapp logs show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --tail 100
```

### View Metrics
```bash
# Check replica count
az containerapp revision list \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query "[].properties.replicas"
```

### Application Insights
View detailed telemetry in Azure Portal:
1. Navigate to Application Insights resource
2. Check Live Metrics for real-time monitoring
3. Review Performance and Failures sections

## Security Best Practices

1. **Use Managed Identity** instead of connection strings when possible
2. **Enable HTTPS only** in production
3. **Store secrets in Azure Key Vault**
4. **Use Azure Container Registry with private endpoints**
5. **Enable Azure Defender** for container security scanning
6. **Implement Azure Front Door** or Application Gateway for WAF protection

## Cost Optimization

- Enable scale-to-zero for dev/test environments
- Use Azure Reservations for production workloads
- Monitor and optimize database DTU usage
- Use consumption-based pricing for variable workloads

## References

- [Azure Container Apps Documentation](https://docs.microsoft.com/azure/container-apps/)
- [Azure Container Registry](https://docs.microsoft.com/azure/container-registry/)
- [Azure SQL Database](https://docs.microsoft.com/azure/azure-sql/)
- [Application Insights](https://docs.microsoft.com/azure/azure-monitor/app/app-insights-overview)
