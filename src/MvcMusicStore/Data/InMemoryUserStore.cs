using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.AspNetCore.Identity;
using MvcMusicStore.Models;

namespace MvcMusicStore.Data;

public sealed class InMemoryUserStore : IUserPasswordStore<ApplicationUser>, IUserEmailStore<ApplicationUser>,
    IUserSecurityStampStore<ApplicationUser>, IUserLockoutStore<ApplicationUser>, IUserRoleStore<ApplicationUser>
{
    private readonly InMemoryIdentityData _data;
    private readonly IdentityErrorDescriber _errors;

    public InMemoryUserStore(InMemoryIdentityData data, IdentityErrorDescriber errors)
    {
        _data = data;
        _errors = errors;
    }

    public Task<IdentityResult> CreateAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            var error = FindDuplicate(user);
            if (error != null)
            {
                return Task.FromResult(IdentityResult.Failed(error));
            }
            if (_data.Users.ContainsKey(user.Id))
            {
                return Task.FromResult(IdentityResult.Failed(_errors.ConcurrencyFailure()));
            }
            user.ConcurrencyStamp = Guid.NewGuid().ToString();
            _data.Users.Add(user.Id, user.Copy());
            return Task.FromResult(IdentityResult.Success);
        }
    }

    public Task<IdentityResult> UpdateAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            if (!_data.Users.TryGetValue(user.Id, out var current) || current.ConcurrencyStamp != user.ConcurrencyStamp)
            {
                return Task.FromResult(IdentityResult.Failed(_errors.ConcurrencyFailure()));
            }
            var error = FindDuplicate(user);
            if (error != null)
            {
                return Task.FromResult(IdentityResult.Failed(error));
            }
            user.ConcurrencyStamp = Guid.NewGuid().ToString();
            _data.Users[user.Id] = user.Copy();
            return Task.FromResult(IdentityResult.Success);
        }
    }

    public Task<IdentityResult> DeleteAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            if (!_data.Users.TryGetValue(user.Id, out var current) || current.ConcurrencyStamp != user.ConcurrencyStamp)
            {
                return Task.FromResult(IdentityResult.Failed(_errors.ConcurrencyFailure()));
            }
            _data.Users.Remove(user.Id);
            return Task.FromResult(IdentityResult.Success);
        }
    }

    public Task<ApplicationUser> FindByIdAsync(string userId, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            return Task.FromResult(_data.Users.GetValueOrDefault(userId)?.Copy());
        }
    }

    public Task<ApplicationUser> FindByNameAsync(string normalizedUserName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            return Task.FromResult(_data.Users.Values.SingleOrDefault(u => u.NormalizedUserName == normalizedUserName)?.Copy());
        }
    }

    public Task<ApplicationUser> FindByEmailAsync(string normalizedEmail, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            return Task.FromResult(_data.Users.Values.SingleOrDefault(u => u.NormalizedEmail == normalizedEmail)?.Copy());
        }
    }

    public Task AddToRoleAsync(ApplicationUser user, string normalizedRoleName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            var role = _data.Roles.Values.SingleOrDefault(r => r.NormalizedName == normalizedRoleName)
                ?? throw new InvalidOperationException("Role does not exist.");
            user.RoleIds.Add(role.Id);
        }
        return Task.CompletedTask;
    }

    public Task RemoveFromRoleAsync(ApplicationUser user, string normalizedRoleName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            var role = _data.Roles.Values.SingleOrDefault(r => r.NormalizedName == normalizedRoleName);
            if (role != null)
            {
                user.RoleIds.Remove(role.Id);
            }
        }
        return Task.CompletedTask;
    }

    public Task<IList<string>> GetRolesAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            return Task.FromResult<IList<string>>(_data.Roles.Values.Where(r => user.RoleIds.Contains(r.Id)).Select(r => r.Name).ToList());
        }
    }

    public Task<bool> IsInRoleAsync(ApplicationUser user, string normalizedRoleName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            return Task.FromResult(_data.Roles.Values.Any(r => r.NormalizedName == normalizedRoleName && user.RoleIds.Contains(r.Id)));
        }
    }

    public Task<IList<ApplicationUser>> GetUsersInRoleAsync(string normalizedRoleName, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_data.Sync)
        {
            var role = _data.Roles.Values.SingleOrDefault(r => r.NormalizedName == normalizedRoleName);
            return Task.FromResult<IList<ApplicationUser>>(_data.Users.Values
                .Where(u => role != null && u.RoleIds.Contains(role.Id)).Select(u => u.Copy()).ToList());
        }
    }

    private IdentityError FindDuplicate(ApplicationUser user)
    {
        if (_data.Users.Values.Any(u => u.Id != user.Id && u.NormalizedUserName == user.NormalizedUserName))
        {
            return _errors.DuplicateUserName(user.UserName);
        }
        if (user.NormalizedEmail != null && _data.Users.Values.Any(u => u.Id != user.Id && u.NormalizedEmail == user.NormalizedEmail))
        {
            return _errors.DuplicateEmail(user.Email);
        }
        return null;
    }

    private static Task<T> Value<T>(T value, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(value);
    }

    private static Task Set(Action action, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        action();
        return Task.CompletedTask;
    }

    public Task<string> GetUserIdAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.Id, cancellationToken);
    public Task<string> GetUserNameAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.UserName, cancellationToken);
    public Task SetUserNameAsync(ApplicationUser user, string userName, CancellationToken cancellationToken) => Set(() => user.UserName = userName, cancellationToken);
    public Task<string> GetNormalizedUserNameAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.NormalizedUserName, cancellationToken);
    public Task SetNormalizedUserNameAsync(ApplicationUser user, string normalizedName, CancellationToken cancellationToken) => Set(() => user.NormalizedUserName = normalizedName, cancellationToken);
    public Task SetPasswordHashAsync(ApplicationUser user, string passwordHash, CancellationToken cancellationToken) => Set(() => user.PasswordHash = passwordHash, cancellationToken);
    public Task<string> GetPasswordHashAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.PasswordHash, cancellationToken);
    public Task<bool> HasPasswordAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.PasswordHash != null, cancellationToken);
    public Task SetEmailAsync(ApplicationUser user, string email, CancellationToken cancellationToken) => Set(() => user.Email = email, cancellationToken);
    public Task<string> GetEmailAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.Email, cancellationToken);
    public Task<bool> GetEmailConfirmedAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.EmailConfirmed, cancellationToken);
    public Task SetEmailConfirmedAsync(ApplicationUser user, bool confirmed, CancellationToken cancellationToken) => Set(() => user.EmailConfirmed = confirmed, cancellationToken);
    public Task<string> GetNormalizedEmailAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.NormalizedEmail, cancellationToken);
    public Task SetNormalizedEmailAsync(ApplicationUser user, string normalizedEmail, CancellationToken cancellationToken) => Set(() => user.NormalizedEmail = normalizedEmail, cancellationToken);
    public Task SetSecurityStampAsync(ApplicationUser user, string stamp, CancellationToken cancellationToken) => Set(() => user.SecurityStamp = stamp, cancellationToken);
    public Task<string> GetSecurityStampAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.SecurityStamp, cancellationToken);
    public Task<DateTimeOffset?> GetLockoutEndDateAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.LockoutEnd, cancellationToken);
    public Task SetLockoutEndDateAsync(ApplicationUser user, DateTimeOffset? lockoutEnd, CancellationToken cancellationToken) => Set(() => user.LockoutEnd = lockoutEnd, cancellationToken);
    public Task<int> IncrementAccessFailedCountAsync(ApplicationUser user, CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        return Task.FromResult(++user.AccessFailedCount);
    }
    public Task ResetAccessFailedCountAsync(ApplicationUser user, CancellationToken cancellationToken) => Set(() => user.AccessFailedCount = 0, cancellationToken);
    public Task<int> GetAccessFailedCountAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.AccessFailedCount, cancellationToken);
    public Task<bool> GetLockoutEnabledAsync(ApplicationUser user, CancellationToken cancellationToken) => Value(user.LockoutEnabled, cancellationToken);
    public Task SetLockoutEnabledAsync(ApplicationUser user, bool enabled, CancellationToken cancellationToken) => Set(() => user.LockoutEnabled = enabled, cancellationToken);
    public void Dispose() { }
}
