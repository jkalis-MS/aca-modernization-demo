using System;
using System.Linq;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MvcMusicStore.Models;

namespace MvcMusicStore.Data;

public static class InMemoryIdentitySeeder
{
    public static async Task SeedAsync(IServiceProvider services, IConfiguration configuration)
    {
        var userName = configuration["InMemoryStore:AdminUserName"];
        var password = configuration["InMemoryStore:AdminPassword"];
        if (string.IsNullOrWhiteSpace(userName) && string.IsNullOrEmpty(password))
        {
            return;
        }
        if (string.IsNullOrWhiteSpace(userName) || string.IsNullOrEmpty(password))
        {
            throw new InvalidOperationException("Configure both InMemoryStore:AdminUserName and InMemoryStore:AdminPassword to seed an administrator.");
        }

        var roles = services.GetRequiredService<RoleManager<IdentityRole>>();
        if (!await roles.RoleExistsAsync("Administrator"))
        {
            EnsureSuccess(await roles.CreateAsync(new IdentityRole("Administrator")));
        }
        var users = services.GetRequiredService<UserManager<ApplicationUser>>();
        var user = await users.FindByNameAsync(userName);
        if (user == null)
        {
            user = new ApplicationUser { UserName = userName, Email = userName };
            EnsureSuccess(await users.CreateAsync(user, password));
        }
        if (!await users.IsInRoleAsync(user, "Administrator"))
        {
            EnsureSuccess(await users.AddToRoleAsync(user, "Administrator"));
        }
    }

    private static void EnsureSuccess(IdentityResult result)
    {
        if (!result.Succeeded)
        {
            throw new InvalidOperationException("Administrator initialization failed: " + string.Join(", ", result.Errors.Select(e => e.Code)));
        }
    }
}
