using System.Collections.Generic;
using System.Threading.Tasks;

namespace MvcMusicStore.Services
{
    /// <summary>
    /// Interface for Azure Key Vault secret management operations.
    /// </summary>
    public interface IKeyVaultService
    {
        /// <summary>
        /// Retrieves a secret value from Azure Key Vault asynchronously.
        /// </summary>
        /// <param name="secretName">The name of the secret to retrieve.</param>
        /// <returns>The secret value as a string.</returns>
        Task<string> GetSecretAsync(string secretName);

        /// <summary>
        /// Sets or updates a secret in Azure Key Vault asynchronously.
        /// </summary>
        /// <param name="secretName">The name of the secret.</param>
        /// <param name="secretValue">The value to store.</param>
        /// <returns>A task representing the asynchronous operation.</returns>
        Task SetSecretAsync(string secretName, string secretValue);

        /// <summary>
        /// Deletes a secret from Azure Key Vault asynchronously.
        /// </summary>
        /// <param name="secretName">The name of the secret to delete.</param>
        /// <returns>A task representing the asynchronous operation.</returns>
        Task DeleteSecretAsync(string secretName);

        /// <summary>
        /// Lists all secret names in the Azure Key Vault asynchronously.
        /// </summary>
        /// <returns>A collection of secret names.</returns>
        Task<IEnumerable<string>> ListSecretsAsync();
    }
}
