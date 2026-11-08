using System.Collections.Generic;
using Microsoft.AspNetCore.Identity;
using MvcMusicStore.Models;

namespace MvcMusicStore.Data;

public sealed class InMemoryIdentityData
{
    internal object Sync { get; } = new();
    internal Dictionary<string, ApplicationUser> Users { get; } = new();
    internal Dictionary<string, IdentityRole> Roles { get; } = new();

    internal static IdentityRole CopyRole(IdentityRole role) => new()
    {
        Id = role.Id,
        Name = role.Name,
        NormalizedName = role.NormalizedName,
        ConcurrencyStamp = role.ConcurrencyStamp
    };
}
