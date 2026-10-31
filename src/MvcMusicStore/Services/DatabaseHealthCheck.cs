using System;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Diagnostics.HealthChecks;
using MvcMusicStore.Models;

namespace MvcMusicStore.Services;

public sealed class DatabaseHealthCheck(IServiceScopeFactory scopeFactory) : IHealthCheck
{
    public async Task<HealthCheckResult> CheckHealthAsync(
        HealthCheckContext context,
        CancellationToken cancellationToken = default)
    {
        using var scope = scopeFactory.CreateScope();
        try
        {
            var store = scope.ServiceProvider.GetRequiredService<MusicStoreEntities>();
            var identity = scope.ServiceProvider.GetRequiredService<ApplicationDbContext>();
            if (!await store.Albums.AnyAsync(cancellationToken))
            {
                return HealthCheckResult.Unhealthy("The music catalog has not been seeded.");
            }

            // Query a migrated table, not just the server, to verify schema readiness.
            await identity.Users.AnyAsync(cancellationToken);
            return HealthCheckResult.Healthy();
        }
        catch (Exception exception)
        {
            return HealthCheckResult.Unhealthy("Database readiness check failed.", exception);
        }
    }
}
