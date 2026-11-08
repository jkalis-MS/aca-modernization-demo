using System;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;

namespace MvcMusicStore.Data;

public sealed class InMemoryRoleStore : IRoleStore<IdentityRole>
{
    private readonly InMemoryIdentityData _data;
    private readonly IdentityErrorDescriber _errors;

    public InMemoryRoleStore(InMemoryIdentityData data, IdentityErrorDescriber errors)
    {
        _data = data;
        _errors = errors;
    }

    public Task<IdentityResult> CreateAsync(IdentityRole role, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            if (_data.Roles.Values.Any(r => r.NormalizedName == role.NormalizedName))
            {
                return Task.FromResult(IdentityResult.Failed(_errors.DuplicateRoleName(role.Name)));
            }
            if (_data.Roles.ContainsKey(role.Id))
            {
                return Task.FromResult(IdentityResult.Failed(_errors.ConcurrencyFailure()));
            }
            role.ConcurrencyStamp = Guid.NewGuid().ToString();
            _data.Roles.Add(role.Id, InMemoryIdentityData.CopyRole(role));
            return Task.FromResult(IdentityResult.Success);
        }
    }

    public Task<IdentityResult> UpdateAsync(IdentityRole role, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            if (!_data.Roles.TryGetValue(role.Id, out var current) || current.ConcurrencyStamp != role.ConcurrencyStamp)
            {
                return Task.FromResult(IdentityResult.Failed(_errors.ConcurrencyFailure()));
            }
            if (_data.Roles.Values.Any(r => r.Id != role.Id && r.NormalizedName == role.NormalizedName))
            {
                return Task.FromResult(IdentityResult.Failed(_errors.DuplicateRoleName(role.Name)));
            }
            role.ConcurrencyStamp = Guid.NewGuid().ToString();
            _data.Roles[role.Id] = InMemoryIdentityData.CopyRole(role);
            return Task.FromResult(IdentityResult.Success);
        }
    }

    public Task<IdentityResult> DeleteAsync(IdentityRole role, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            if (!_data.Roles.TryGetValue(role.Id, out var current) || current.ConcurrencyStamp != role.ConcurrencyStamp)
            {
                return Task.FromResult(IdentityResult.Failed(_errors.ConcurrencyFailure()));
            }
            _data.Roles.Remove(role.Id);
            foreach (var user in _data.Users.Values.Where(u => u.RoleIds.Contains(role.Id)))
            {
                user.RoleIds.Remove(role.Id);
                user.ConcurrencyStamp = Guid.NewGuid().ToString();
                user.SecurityStamp = Guid.NewGuid().ToString();
            }
            return Task.FromResult(IdentityResult.Success);
        }
    }

    public Task<IdentityRole> FindByIdAsync(string roleId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            return Task.FromResult(_data.Roles.TryGetValue(roleId, out var role) ? InMemoryIdentityData.CopyRole(role) : null);
        }
    }

    public Task<IdentityRole> FindByNameAsync(string normalizedRoleName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            var role = _data.Roles.Values.SingleOrDefault(r => r.NormalizedName == normalizedRoleName);
            return Task.FromResult(role == null ? null : InMemoryIdentityData.CopyRole(role));
        }
    }

    public Task<string> GetRoleIdAsync(IdentityRole role, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(role.Id);
    }

    public Task<string> GetRoleNameAsync(IdentityRole role, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(role.Name);
    }

    public Task SetRoleNameAsync(IdentityRole role, string roleName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        role.Name = roleName;
        return Task.CompletedTask;
    }

    public Task<string> GetNormalizedRoleNameAsync(IdentityRole role, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(role.NormalizedName);
    }

    public Task SetNormalizedRoleNameAsync(IdentityRole role, string normalizedName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        role.NormalizedName = normalizedName;
        return Task.CompletedTask;
    }

    public void Dispose() { }
}
