# Azure Key Vault Configuration Guide

This application uses Azure Key Vault with Managed Identity to securely store and retrieve sensitive configuration values such as connection strings and API keys.

## Required Azure Key Vault Secrets

The following secrets must be created in your Azure Key Vault. Note that Azure Key Vault secret names can only contain alphanumeric characters and dashes, so configuration keys with colons (`:`) are replaced with double dashes (`--`).

### Secret Names and Values

| Secret Name | Configuration Key | Description | Example Value |
|------------|-------------------|-------------|---------------|
| `ConnectionStrings--MusicStoreEntities` | `ConnectionStrings:MusicStoreEntities` | Main database connection string | `Server=tcp:yourserver.database.windows.net,1433;Initial Catalog=MvcMusicStore;Authentication=Active Directory Default;` |
| `ConnectionStrings--DefaultConnection` | `ConnectionStrings:DefaultConnection` | Identity database connection string | `Server=tcp:yourserver.database.windows.net,1433;Initial Catalog=MvcMusicStore-Identity;Authentication=Active Directory Default;` |
| `ApplicationInsights--ConnectionString` | `ApplicationInsights:ConnectionString` | Application Insights connection string | `InstrumentationKey=<your-key>;IngestionEndpoint=https://westus-0.in.applicationinsights.azure.com/` |

## Azure Setup Instructions

### 1. Create Azure Key Vault

```bash
# Set variables
RESOURCE_GROUP="rg-musicstore"
LOCATION="eastus"
KEY_VAULT_NAME="kv-musicstore-unique"  # Must be globally unique

# Create Key Vault
az keyvault create \
  --name $KEY_VAULT_NAME \
  --resource-group $RESOURCE_GROUP \
  --location $LOCATION
```

### 2. Add Secrets to Key Vault

```bash
# Add database connection string
az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name "ConnectionStrings--MusicStoreEntities" \
  --value "Server=tcp:yourserver.database.windows.net,1433;Initial Catalog=MvcMusicStore;Authentication=Active Directory Default;"

# Add identity database connection string
az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name "ConnectionStrings--DefaultConnection" \
  --value "Server=tcp:yourserver.database.windows.net,1433;Initial Catalog=MvcMusicStore-Identity;Authentication=Active Directory Default;"

# Add Application Insights connection string
az keyvault secret set \
  --vault-name $KEY_VAULT_NAME \
  --name "ApplicationInsights--ConnectionString" \
  --value "InstrumentationKey=YOUR_KEY;IngestionEndpoint=https://westus-0.in.applicationinsights.azure.com/"
```

### 3. Configure Managed Identity for Azure App Service / Container App

```bash
# Enable system-assigned managed identity
APP_NAME="musicstore-app"

# For App Service
az webapp identity assign \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP

# For Container App
az containerapp identity assign \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --system-assigned

# Get the principal ID
PRINCIPAL_ID=$(az webapp identity show \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --query principalId -o tsv)
```

### 4. Grant Key Vault Access to Managed Identity

```bash
# Assign "Key Vault Secrets User" role
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee $PRINCIPAL_ID \
  --scope /subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME
```

### 5. Configure Application Settings

Set the `KeyVaultName` configuration in your Azure App Service or Container App:

```bash
# For App Service
az webapp config appsettings set \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --settings KeyVaultName=$KEY_VAULT_NAME

# For Container App
az containerapp update \
  --name $APP_NAME \
  --resource-group $RESOURCE_GROUP \
  --set-env-vars KeyVaultName=$KEY_VAULT_NAME
```

## Local Development Setup

For local development, you need to authenticate with Azure and have appropriate permissions to access Key Vault.

### Prerequisites

1. **Azure CLI** installed and logged in
2. **Key Vault Secrets User** role assigned to your Azure AD account

### Authentication Methods

The application uses `DefaultAzureCredential` which tries multiple authentication methods in order:

1. **Environment Variables** (for CI/CD)
2. **Managed Identity** (in Azure)
3. **Azure CLI** (local development)
4. **Visual Studio** (local development)

### Local Development Configuration

#### Option 1: Using Azure CLI (Recommended)

```bash
# Login to Azure
az login

# Set your subscription
az set account --subscription <subscription-id>

# Grant yourself Key Vault access (if not already granted)
az role assignment create \
  --role "Key Vault Secrets User" \
  --assignee <your-email@domain.com> \
  --scope /subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME
```

#### Option 2: Using User Secrets (for testing without Key Vault)

For local development without Azure Key Vault access, you can use user secrets:

```bash
# Navigate to the project directory
cd MvcMusicStore

# Initialize user secrets
dotnet user-secrets init

# Add connection strings
dotnet user-secrets set "ConnectionStrings:MusicStoreEntities" "Server=(localdb)\\mssqllocaldb;Database=MvcMusicStore;Trusted_Connection=True;MultipleActiveResultSets=true"
dotnet user-secrets set "ConnectionStrings:DefaultConnection" "Server=(localdb)\\mssqllocaldb;Database=MvcMusicStore-Identity;Trusted_Connection=True;MultipleActiveResultSets=true"
dotnet user-secrets set "ApplicationInsights:ConnectionString" "InstrumentationKey=local-dev-key"
```

#### Option 3: Using Local appsettings (not recommended for production secrets)

You can create a `appsettings.Local.json` file (add to `.gitignore`!) with your local secrets:

```json
{
  "ConnectionStrings": {
    "MusicStoreEntities": "Server=(localdb)\\mssqllocaldb;Database=MvcMusicStore;Trusted_Connection=True;MultipleActiveResultSets=true",
    "DefaultConnection": "Server=(localdb)\\mssqllocaldb;Database=MvcMusicStore-Identity;Trusted_Connection=True;MultipleActiveResultSets=true"
  },
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=local-dev-key"
  }
}
```

### Setting KeyVaultName for Local Development

#### Option A: Environment Variable

```bash
# Windows (PowerShell)
$env:KeyVaultName="your-keyvault-name"

# Windows (CMD)
set KeyVaultName=your-keyvault-name

# Linux/macOS
export KeyVaultName=your-keyvault-name
```

#### Option B: User Secrets

```bash
dotnet user-secrets set "KeyVaultName" "your-keyvault-name"
```

#### Option C: appsettings.Local.json

```json
{
  "KeyVaultName": "your-keyvault-name"
}
```

## Database Connection String Format for Azure SQL with Managed Identity

When using Azure SQL Database with Managed Identity, use the following connection string format:

```
Server=tcp:yourserver.database.windows.net,1433;Initial Catalog=YourDatabase;Authentication=Active Directory Default;Encrypt=True;TrustServerCertificate=False;
```

**Important**: Do NOT include `User ID` or `Password` in the connection string when using Managed Identity. The `Authentication=Active Directory Default` parameter enables Managed Identity authentication.

### Grant Database Access to Managed Identity

After enabling Managed Identity, you must grant database access:

```sql
-- Connect to your database as an admin and run:
CREATE USER [your-app-name] FROM EXTERNAL PROVIDER;
ALTER ROLE db_datareader ADD MEMBER [your-app-name];
ALTER ROLE db_datawriter ADD MEMBER [your-app-name];
ALTER ROLE db_ddladmin ADD MEMBER [your-app-name];  -- Only if needed for migrations
```

## Troubleshooting

### Issue: "KeyVaultName configuration is missing"

**Solution**: Ensure `KeyVaultName` is set in one of the following:
- `appsettings.json`
- Environment variable
- User secrets
- Azure App Configuration

### Issue: "Authentication failed when retrieving secret"

**Possible causes**:
1. Not logged in to Azure CLI: Run `az login`
2. Managed Identity not configured in Azure
3. Insufficient permissions

**Solution**: Verify you have "Key Vault Secrets User" role assigned

### Issue: "Access denied when retrieving secret"

**Solution**: Verify the Managed Identity or your Azure AD account has the "Key Vault Secrets User" role:

```bash
az role assignment list \
  --scope /subscriptions/<subscription-id>/resourceGroups/$RESOURCE_GROUP/providers/Microsoft.KeyVault/vaults/$KEY_VAULT_NAME
```

### Issue: "Secret not found"

**Solution**: Verify the secret exists in Key Vault and the name matches exactly (including the double-dash notation):

```bash
az keyvault secret list --vault-name $KEY_VAULT_NAME
```

## Security Best Practices

1. ? **Use Managed Identity** - Never store credentials in code or configuration files
2. ? **Principle of Least Privilege** - Grant only necessary permissions (Key Vault Secrets User for reading)
3. ? **Rotate Secrets Regularly** - Update secrets in Key Vault without code changes
4. ? **Enable Soft Delete** - Protect against accidental deletion
5. ? **Enable Audit Logging** - Monitor secret access
6. ? **Use Private Endpoints** - Restrict Key Vault access to your VNet
7. ? **Separate Key Vaults** - Use different Key Vaults for dev, staging, and production

## Additional Resources

- [Azure Key Vault Documentation](https://docs.microsoft.com/azure/key-vault/)
- [Managed Identity Documentation](https://docs.microsoft.com/azure/active-directory/managed-identities-azure-resources/)
- [DefaultAzureCredential Documentation](https://docs.microsoft.com/dotnet/api/azure.identity.defaultazurecredential)
- [Azure SQL Managed Identity Authentication](https://docs.microsoft.com/azure/azure-sql/database/authentication-aad-configure)
