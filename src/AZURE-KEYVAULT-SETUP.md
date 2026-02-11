# Azure Key Vault Setup Guide

This document explains how to configure and use Azure Key Vault to secure your application credentials using Managed Identity.

## Overview

The MVC Music Store application has been migrated to use Azure Key Vault for secure credential storage instead of plaintext credentials in configuration files. This follows Azure security best practices by:

- **Eliminating plaintext secrets** from configuration files
- **Using Managed Identity** for authentication (no credentials needed)
- **Centralizing secret management** in Azure Key Vault
- **Supporting local development** through Azure CLI or Visual Studio authentication

## Prerequisites

### For Azure Deployment
- Azure subscription
- Azure Key Vault resource
- App Service or Azure compute resource with System-Assigned Managed Identity enabled

### For Local Development
Choose one of these options:
- **Azure CLI**: Install and run `az login`
- **Visual Studio**: Sign in with your Azure account
- **Visual Studio Code**: Install Azure Account extension and sign in

## Azure Setup Steps

### 1. Create Azure Key Vault

```bash
# Set variables
RESOURCE_GROUP="your-resource-group"
KEY_VAULT_NAME="your-keyvault-name"  # Must be globally unique
LOCATION="eastus"

# Create Key Vault
az keyvault create \
  --name $KEY_VAULT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION \
  --enable-rbac-authorization true
```

### 2. Store Secrets in Key Vault

Store your connection strings and other secrets in Key Vault:

```bash
# Store SQL connection strings
az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name "ConnectionStrings--MusicStoreEntities" \
  --value "Server=your-server.database.windows.net;Database=MvcMusicStore;Authentication=Active Directory Default;"

az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name "ConnectionStrings--DefaultConnection" \
  --value "Server=your-server.database.windows.net;Database=MvcMusicStore-Identity;Authentication=Active Directory Default;"

# Store Application Insights connection string
az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name "ApplicationInsights--ConnectionString" \
  --value "InstrumentationKey=your-key;IngestionEndpoint=https://your-region.in.applicationinsights.azure.com/"
```

**Note**: Use `--` (double hyphen) to represent `:` (colon) in hierarchical configuration keys.

### 3. Enable System-Assigned Managed Identity on App Service

```bash
APP_SERVICE_NAME="your-app-service-name"

# Enable system-assigned managed identity
az webapp identity assign \
  --name $APP_SERVICE_NAME \
  --resource-group $RESOURCE_GROUP
```

### 4. Grant Key Vault Access to Managed Identity

```bash
# Get the managed identity principal ID
PRINCIPAL_ID=$(az webapp identity show \
  --name $APP_SERVICE_NAME \
  --resource-group $RESOURCE_GROUP \
  --query principalId \
  --output tsv)

# Grant "Key Vault Secrets User" role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $PRINCIPAL_ID \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"
```

## Application Configuration

### 1. Update appsettings.json

Set the Key Vault name in your configuration:

```json
{
  "KeyVaultName": "your-keyvault-name",
  "ConnectionStrings": {
    "MusicStoreEntities": "Server=(localdb)\\mssqllocaldb;Database=MvcMusicStore;Trusted_Connection=True;MultipleActiveResultSets=true",
    "DefaultConnection": "Server=(localdb)\\mssqllocaldb;Database=MvcMusicStore-Identity;Trusted_Connection=True;MultipleActiveResultSets=true"
  },
  "ApplicationInsights": {
    "ConnectionString": "..."
  }
}
```

**Important**: 
- When `KeyVaultName` is configured, secrets from Key Vault override local configuration
- Local connection strings are fallback values for development
- Leave `KeyVaultName` empty for local development without Azure Key Vault

### 2. Environment-Specific Configuration

**Production (Azure App Service):**
- Set `KeyVaultName` application setting in App Service configuration
- App Service will automatically use its Managed Identity to access Key Vault

**Local Development:**
- Leave `KeyVaultName` empty in `appsettings.Development.json`
- OR set it and authenticate with Azure CLI: `az login`
- Application will use local connection strings as fallback

## How It Works

### Code Implementation (Program.cs)

```csharp
// Configure Azure Key Vault integration with Managed Identity
var keyVaultName = builder.Configuration["KeyVaultName"];
if (!string.IsNullOrEmpty(keyVaultName))
{
    var keyVaultUri = new Uri($"https://{keyVaultName}.vault.azure.net/");
    
    // DefaultAzureCredential authentication chain:
    // 1. Managed Identity (in Azure)
    // 2. Azure CLI (local: az login)
    // 3. Visual Studio (local: signed-in account)
    builder.Configuration.AddAzureKeyVault(
        keyVaultUri,
        new DefaultAzureCredential());
}
```

### DefaultAzureCredential Authentication Chain

The `DefaultAzureCredential` tries authentication methods in this order:

1. **Environment Variables** - Checks for AZURE_CLIENT_ID, AZURE_TENANT_ID, AZURE_CLIENT_SECRET
2. **Managed Identity** - Used automatically in Azure (App Service, Functions, VMs)
3. **Azure CLI** - Uses `az login` credentials for local development
4. **Visual Studio** - Uses Visual Studio signed-in account
5. **Visual Studio Code** - Uses VSCode Azure Account extension

## Testing

### Local Testing (Without Key Vault)

1. Leave `KeyVaultName` empty in `appsettings.Development.json`
2. Application will use local connection strings from configuration files
3. Run the application: `dotnet run`

### Local Testing (With Key Vault)

1. Sign in to Azure CLI: `az login`
2. Set `KeyVaultName` in `appsettings.Development.json`
3. Ensure you have "Key Vault Secrets User" role on the Key Vault
4. Run the application: `dotnet run`

### Azure Testing

1. Deploy application to Azure App Service
2. Set `KeyVaultName` application setting
3. Ensure Managed Identity is enabled and has Key Vault access
4. Application will automatically authenticate using Managed Identity

## Troubleshooting

### Error: "403 Forbidden" when accessing Key Vault

**Cause**: Managed Identity or local user doesn't have permissions.

**Solution**:
```bash
# Check role assignments
az role assignment list \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"

# Grant access if missing
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee YOUR_PRINCIPAL_ID \
  --scope "/subscriptions/YOUR_SUBSCRIPTION_ID/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME"
```

### Error: "401 Unauthorized" or "CredentialUnavailableException"

**Cause**: No valid authentication method found.

**Solution for local development**:
- Run `az login` to authenticate Azure CLI
- OR sign in to Visual Studio with your Azure account
- Verify: `az account show`

### Secrets Not Loading from Key Vault

**Cause**: Key Vault name not configured or secret names don't match.

**Solution**:
1. Verify `KeyVaultName` is set correctly
2. Check secret names use `--` instead of `:` for hierarchy
   - Correct: `ConnectionStrings--MusicStoreEntities`
   - Incorrect: `ConnectionStrings:MusicStoreEntities`

### Error: "Key Vault name not found"

**Cause**: Key Vault doesn't exist or name is incorrect.

**Solution**:
```bash
# List available Key Vaults
az keyvault list --query "[].name"

# Verify specific Key Vault
az keyvault show --name $KEY_VAULT_NAME
```

## Security Best Practices

? **DO:**
- Use Managed Identity for authentication in Azure
- Store all secrets in Key Vault (connection strings, API keys, certificates)
- Use RBAC for Key Vault access control
- Regularly rotate secrets
- Use separate Key Vaults for different environments (dev, staging, production)

? **DON'T:**
- Commit secrets to source control
- Use access keys or client secrets for Key Vault authentication
- Share Key Vault across unrelated applications
- Give more permissions than needed (principle of least privilege)

## Migration Checklist

- [x] Install Azure.Security.KeyVault.Secrets NuGet package
- [x] Install Azure.Identity NuGet package  
- [x] Install Azure.Extensions.AspNetCore.Configuration.Secrets NuGet package
- [x] Add Key Vault configuration code to Program.cs
- [x] Update appsettings.json with KeyVaultName setting
- [ ] Create Azure Key Vault resource
- [ ] Store secrets in Key Vault
- [ ] Enable Managed Identity on Azure compute resource
- [ ] Grant Key Vault access to Managed Identity
- [ ] Deploy and test application
- [ ] Remove plaintext secrets from configuration files (after confirming Key Vault works)

## Additional Resources

- [Azure Key Vault Documentation](https://learn.microsoft.com/en-us/azure/key-vault/)
- [DefaultAzureCredential Documentation](https://learn.microsoft.com/en-us/dotnet/api/azure.identity.defaultazurecredential)
- [Managed Identity Overview](https://learn.microsoft.com/en-us/entra/identity/managed-identities-azure-resources/overview)
- [Azure SDK for .NET](https://learn.microsoft.com/en-us/dotnet/azure/sdk/azure-sdk-for-dotnet)
