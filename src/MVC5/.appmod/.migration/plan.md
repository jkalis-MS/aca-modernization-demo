# Migration Plan: Plaintext Credentials to Azure Key Vault with Managed Identity

## Project Information
- **Project Name**: MvcMusicStore
- **Framework**: ASP.NET Core (.NET 10)
- **Project Type**: Razor Pages
- **Current Authentication**: Plaintext credentials in configuration files
- **Target Authentication**: Azure Key Vault with Managed Identity

## Migration Overview

This migration will replace plaintext credentials stored in configuration files with secure Azure Key Vault secret management using Managed Identity for authentication. The application currently stores sensitive information including:

1. Database connection strings in appsettings.json
2. Application Insights connection strings with hardcoded instrumentation keys

## Required NuGet Packages

### Core Packages (Latest Versions)
- `Azure.Security.KeyVault.Secrets` version `4.8.0` - Azure Key Vault Secret management
- `Azure.Identity` version `1.14.0` - Managed Identity and DefaultAzureCredential support
- `Azure.Extensions.AspNetCore.Configuration.Secrets` version `1.3.2` - ASP.NET Core Key Vault configuration integration

## Current State Analysis

### Identified Plaintext Credentials

#### 1. appsettings.json
```json
{
  "ConnectionStrings": {
    "MusicStoreEntities": "Server=(localdb)\\mssqllocaldb;Database=MvcMusicStore;Trusted_Connection=True;MultipleActiveResultSets=true",
    "DefaultConnection": "Server=(localdb)\\mssqllocaldb;Database=MvcMusicStore-Identity;Trusted_Connection=True;MultipleActiveResultSets=true"
  },
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=00000000-0000-0000-0000-000000000000;IngestionEndpoint=https://YOUR_REGION.in.applicationinsights.azure.com/"
  }
}
```

#### 2. appsettings.Development.json
```json
{
  "ApplicationInsights": {
    "ConnectionString": "InstrumentationKey=af624c81-017c-47e3-b367-d962754edc34;IngestionEndpoint=https://westus-0.in.applicationinsights.azure.com/;LiveEndpoint=https://westus.livediagnostics.monitor.azure.com/;ApplicationId=b5a4a132-d712-4518-a500-26ef11092291"
  }
}
```

## Migration Tasks

### Phase 1: Setup and Configuration
1. Install Required NuGet Packages (Azure.Security.KeyVault.Secrets, Azure.Identity, Azure.Extensions.AspNetCore.Configuration.Secrets)
2. Update Configuration Files (add KeyVaultName, prepare for Key Vault integration)

### Phase 2: Create Key Vault Service Infrastructure
3. Create Services/IKeyVaultService.cs interface
4. Create Services/KeyVaultService.cs implementation
5. Create Configuration/KeyVaultConfigurationHelper.cs

### Phase 3: Integrate Azure Key Vault Configuration
6. Update Program.cs to add Key Vault configuration provider
7. Register KeyVaultService in DI container
8. Update appsettings.json structure with KeyVaultName

### Phase 4: Update Application Code
9. Verify DbContext uses configuration-based connection strings
10. Verify Application Insights uses configuration-based connection string
11. Remove hardcoded credentials from all configuration files

### Phase 5: Testing and Validation
12. Build verification
13. Create unit tests for KeyVaultService
14. Test local development with DefaultAzureCredential

### Phase 6: Documentation
15. Update README with Azure Key Vault setup instructions
16. Document required Azure permissions
17. Document local development setup

## Secret Naming Convention in Azure Key Vault

Azure Key Vault secret names can only contain alphanumeric characters and dashes. Configuration keys with colons should be replaced with double dashes (--):

1. **ConnectionStrings--MusicStoreEntities** - Main database connection string
2. **ConnectionStrings--DefaultConnection** - Identity database connection string
3. **ApplicationInsights--ConnectionString** - Application Insights connection string

## Configuration After Migration

### appsettings.json (Updated)
```json
{
  "KeyVaultName": "your-keyvault-name",
  "ConnectionStrings": {
    "MusicStoreEntities": "will-be-loaded-from-keyvault",
    "DefaultConnection": "will-be-loaded-from-keyvault"
  },
  "ApplicationInsights": {
    "ConnectionString": "will-be-loaded-from-keyvault"
  }
}
```

## Azure Requirements

### Azure Key Vault Setup
1. Create Azure Key Vault resource
2. Add secrets with appropriate names (using double-dash notation)
3. Configure RBAC permissions

### Managed Identity Setup
1. Enable System-assigned Managed Identity on Azure App Service/Container App
2. Grant "Key Vault Secrets User" role to the Managed Identity
3. Ensure firewall rules allow access

### Local Development
1. Use Azure CLI (`az login`) or Visual Studio authentication
2. Ensure developer account has "Key Vault Secrets User" role
3. Set KeyVaultName in user secrets or environment variable

## Success Criteria

1. ? No plaintext credentials in appsettings.json or appsettings.Development.json
2. ? Application successfully retrieves secrets from Azure Key Vault
3. ? Database connections work with Key Vault-sourced connection strings
4. ? Application Insights configured with Key Vault-sourced connection string
5. ? Managed Identity authentication working in Azure
6. ? Local development works with DefaultAzureCredential
7. ? All tests passing
8. ? Build succeeds without errors
9. ? Documentation updated

## Rollback Plan

If migration fails:
1. Revert code changes from git
2. Restore original configuration files
3. Remove added NuGet packages
4. Rebuild and test application

## Notes

- This migration focuses exclusively on removing plaintext credentials
- No new business logic or features will be added
- Existing functionality must be preserved
- Configuration structure may change but application behavior must remain the same
- All changes must compile successfully
