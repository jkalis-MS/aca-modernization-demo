using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using Azure;
using Azure.Identity;
using Azure.Security.KeyVault.Secrets;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging;

namespace MvcMusicStore.Services
{
    /// <summary>
    /// Service for managing Azure Key Vault secrets using Managed Identity.
    /// </summary>
    public class KeyVaultService : IKeyVaultService
    {
        private readonly SecretClient _secretClient;
        private readonly ILogger<KeyVaultService> _logger;

        public KeyVaultService(IConfiguration configuration, ILogger<KeyVaultService> logger)
        {
            _logger = logger;

            var keyVaultName = configuration["KeyVaultName"];
            if (string.IsNullOrEmpty(keyVaultName))
            {
                throw new InvalidOperationException("KeyVaultName configuration is missing. Please set KeyVaultName in appsettings.json or environment variables.");
            }

            var keyVaultUri = new Uri($"https://{keyVaultName}.vault.azure.net/");

            // DefaultAzureCredential supports multiple authentication methods:
            // - Managed Identity (in Azure)
            // - Azure CLI (local development)
            // - Visual Studio (local development)
            // - Environment variables
            _secretClient = new SecretClient(keyVaultUri, new DefaultAzureCredential());

            _logger.LogInformation("KeyVaultService initialized for vault: {KeyVaultName}", keyVaultName);
        }

        public async Task<string> GetSecretAsync(string secretName)
        {
            try
            {
                _logger.LogInformation("Retrieving secret: {SecretName}", secretName);
                KeyVaultSecret secret = await _secretClient.GetSecretAsync(secretName);
                return secret.Value;
            }
            catch (RequestFailedException ex) when (ex.Status == 404)
            {
                _logger.LogWarning("Secret not found: {SecretName}", secretName);
                throw new KeyNotFoundException($"Secret '{secretName}' was not found in Azure Key Vault.", ex);
            }
            catch (RequestFailedException ex) when (ex.Status == 401)
            {
                _logger.LogError(ex, "Authentication failed when retrieving secret: {SecretName}", secretName);
                throw new UnauthorizedAccessException("Failed to authenticate with Azure Key Vault. Ensure Managed Identity is properly configured.", ex);
            }
            catch (RequestFailedException ex) when (ex.Status == 403)
            {
                _logger.LogError(ex, "Access denied when retrieving secret: {SecretName}", secretName);
                throw new UnauthorizedAccessException($"Access denied. Ensure the Managed Identity has 'Key Vault Secrets User' role for secret '{secretName}'.", ex);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error retrieving secret: {SecretName}", secretName);
                throw;
            }
        }

        public async Task SetSecretAsync(string secretName, string secretValue)
        {
            try
            {
                _logger.LogInformation("Setting secret: {SecretName}", secretName);
                await _secretClient.SetSecretAsync(secretName, secretValue);
                _logger.LogInformation("Secret set successfully: {SecretName}", secretName);
            }
            catch (RequestFailedException ex) when (ex.Status == 403)
            {
                _logger.LogError(ex, "Access denied when setting secret: {SecretName}", secretName);
                throw new UnauthorizedAccessException("Access denied. Ensure the Managed Identity has 'Key Vault Secrets Officer' role to set secrets.", ex);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error setting secret: {SecretName}", secretName);
                throw;
            }
        }

        public async Task DeleteSecretAsync(string secretName)
        {
            try
            {
                _logger.LogInformation("Deleting secret: {SecretName}", secretName);
                DeleteSecretOperation operation = await _secretClient.StartDeleteSecretAsync(secretName);
                await operation.WaitForCompletionAsync();
                _logger.LogInformation("Secret deleted successfully: {SecretName}", secretName);
            }
            catch (RequestFailedException ex) when (ex.Status == 404)
            {
                _logger.LogWarning("Secret not found for deletion: {SecretName}", secretName);
                throw new KeyNotFoundException($"Secret '{secretName}' was not found in Azure Key Vault.", ex);
            }
            catch (RequestFailedException ex) when (ex.Status == 403)
            {
                _logger.LogError(ex, "Access denied when deleting secret: {SecretName}", secretName);
                throw new UnauthorizedAccessException("Access denied. Ensure the Managed Identity has 'Key Vault Secrets Officer' role to delete secrets.", ex);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error deleting secret: {SecretName}", secretName);
                throw;
            }
        }

        public async Task<IEnumerable<string>> ListSecretsAsync()
        {
            try
            {
                _logger.LogInformation("Listing all secrets");
                var secretNames = new List<string>();
                await foreach (SecretProperties secretProperties in _secretClient.GetPropertiesOfSecretsAsync())
                {
                    secretNames.Add(secretProperties.Name);
                }
                _logger.LogInformation("Found {Count} secrets", secretNames.Count);
                return secretNames;
            }
            catch (RequestFailedException ex) when (ex.Status == 403)
            {
                _logger.LogError(ex, "Access denied when listing secrets");
                throw new UnauthorizedAccessException("Access denied. Ensure the Managed Identity has 'Key Vault Secrets User' role to list secrets.", ex);
            }
            catch (Exception ex)
            {
                _logger.LogError(ex, "Error listing secrets");
                throw;
            }
        }
    }
}
