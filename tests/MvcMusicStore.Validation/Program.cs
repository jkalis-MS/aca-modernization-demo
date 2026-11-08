using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Identity;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using MvcMusicStore.Controllers;
using MvcMusicStore.Data;
using MvcMusicStore.Models;

var failures = 0;
var checks = 0;

await Check("Catalog seed and detached snapshots", () =>
{
    var store = CreateStore();
    DbSeeder.Seed(store);
    Require(store.GetAlbums().Count == 100, "Seed should be idempotent.");
    Require(store.GetGenres().Count == 10 && store.GetArtists().Count == 55, "Expected seed genres and artists.");
    Require(store.GetGenres().All(g => g.Albums.Count == 10), "Each genre should have ten albums.");
    Require(store.GetAlbums().All(a => a.Artist != null && a.Genre != null && a.OrderDetails != null), "Relationships should be populated.");
    var album = store.GetAlbum(1);
    album.Title = "Changed outside store";
    album.Genre.Name = "Changed outside store";
    album.OrderDetails.Add(new OrderDetail());
    Require(store.GetAlbum(1).Title == "Thunder Road", "Returned albums must be detached.");
    Require(store.GetAlbum(1).Genre.Name == "Rock" && store.GetAlbum(1).OrderDetails.Count == 0, "Related data must be detached.");
    return Task.CompletedTask;
});

await Check("Catalog CRUD and relationships", () =>
{
    var store = CreateStore();
    var input = new Album { Title = "Test Album", GenreId = 1, ArtistId = 1, Price = 3.99m };
    var id = store.AddAlbum(input);
    Require(id == 101, "New albums must get a generated ID.");
    input.Title = "Not persisted";
    Require(store.GetAlbum(id).Title == "Test Album", "Input must be copied.");
    var edited = store.GetAlbum(id);
    edited.GenreId = 2;
    edited.Price = 4.99m;
    Require(store.UpdateAlbum(edited), "Update should succeed.");
    Require(store.GetAlbum(id).Genre.Name == "Jazz", "Genre relationship should update.");
    Require(store.GetGenres().Single(g => g.GenreId == 1).Albums.Count == 10, "Old genre should not retain album.");
    edited.ArtistId = -1;
    Expect<ArgumentException>(() => store.UpdateAlbum(edited));
    store.AddToCart("guest", id);
    Require(store.DeleteAlbum(id), "Delete should succeed.");
    Require(store.GetAlbum(id) == null && store.GetCartItems("guest").Count == 0, "Deletion must not leave dangling carts.");
    Require(!store.DeleteAlbum(id) && !store.UpdateAlbum(edited), "Missing albums should be handled.");
    return Task.CompletedTask;
});

await Check("Concurrent ID allocation and cart increments", () =>
{
    var store = CreateStore();
    Parallel.For(0, 200, _ => store.AddToCart("guest", 1));
    Require(store.GetCartItems("guest").Single().Count == 200, "Concurrent additions must not lose increments.");
    Parallel.For(0, 200, _ => store.RemoveFromCart("guest", store.GetCartItems("guest").FirstOrDefault()?.RecordId ?? -1));
    Require(store.GetCartItems("guest").Count == 0, "Concurrent removals should empty the cart.");
    var ids = new System.Collections.Concurrent.ConcurrentBag<int>();
    Parallel.For(0, 100, _ => ids.Add(store.AddAlbum(new Album { Title = "Concurrent Album", GenreId = 1, ArtistId = 1, Price = 1m })));
    Require(ids.Distinct().Count() == 100, "Concurrent creates must allocate unique IDs.");
    return Task.CompletedTask;
});

await Check("Cart ownership and account migration", () =>
{
    var store = CreateStore();
    store.AddToCart("guest", 1);
    store.AddToCart("guest", 1);
    store.AddToCart("account", 1);
    store.AddToCart("other", 2);
    var otherItem = store.GetCartItems("other").Single();
    Require(store.RemoveFromCart("guest", otherItem.RecordId) == 0, "Another user's item cannot be removed.");
    Require(store.GetCartItems("other").Single().Count == 1, "Other cart must be unchanged.");
    store.MigrateCart("guest", "account");
    store.MigrateCart("account", "account");
    Require(store.GetCartItems("guest").Count == 0, "Anonymous cart should be migrated.");
    Require(store.GetCartItems("account").Single().Count == 3, "Existing account cart should merge quantities.");
    var snapshot = store.GetCartItems("account").Single();
    snapshot.Count = 999;
    Require(store.GetCartItems("account").Single().Count == 3, "Cart snapshots must be detached.");
    return Task.CompletedTask;
});

await Check("Checkout server pricing, order ownership and atomicity", () =>
{
    var store = CreateStore();
    store.AddToCart("account", 1);
    store.AddToCart("account", 1);
    store.AddToCart("other", 2);
    var album = store.GetAlbum(1);
    album.Price = 15m;
    store.UpdateAlbum(album);
    var order = new Order { Username = "account", Total = -100m, OrderId = -1, OrderDate = DateTime.Now };
    var id = store.CreateOrder("account", order);
    Require(id == 1 && order.Total == 30m, "Checkout must use current server prices and generated IDs.");
    Require(store.OwnsOrder(id, "account") && !store.OwnsOrder(id, "other"), "Order ownership must be enforced.");
    Require(store.GetCartItems("account").Count == 0 && store.GetCartItems("other").Count == 1, "Only checked-out cart should be emptied.");
    Require(store.GetAlbum(1).OrderDetails.Single().Quantity == 2, "Order details should populate popularity data.");
    Expect<InvalidOperationException>(() => store.DeleteAlbum(1));
    Expect<InvalidOperationException>(() => store.CreateOrder("account", new Order { Username = "account" }));
    Require(!store.OwnsOrder(2, "account"), "Empty checkout must not create an order.");
    store.AddToCart("account", 2);
    var successes = 0;
    Parallel.For(0, 20, _ =>
    {
        try { store.CreateOrder("account", new Order { Username = "account" }); Interlocked.Increment(ref successes); }
        catch (InvalidOperationException) { }
    });
    Require(successes == 1, "Concurrent checkout must process a cart exactly once.");
    return Task.CompletedTask;
});

await Check("Session cart and missing-item controller responses", () =>
{
    var store = CreateStore();
    var context = new DefaultHttpContext { Session = new TestSession() };
    var cart = ShoppingCart.GetCart(store, context);
    cart.AddToCart(store.GetAlbum(1));
    Require(cart.GetCount() == 1 && cart.GetTotal() == 9.99m, "Session cart should retain quantities and prices.");
    cart.MigrateCart("account");
    context.Session.SetString(ShoppingCart.CartSessionKey, "account");
    Require(ShoppingCart.GetCart(store, context).GetCount() == 1, "Migrated session should see account cart.");
    var controller = new ShoppingCartController(store) { ControllerContext = new Microsoft.AspNetCore.Mvc.ControllerContext { HttpContext = context } };
    Require(controller.AddToCart(-1) is Microsoft.AspNetCore.Mvc.NotFoundResult, "Missing album should return 404.");
    Require(controller.RemoveFromCart(-1) is Microsoft.AspNetCore.Mvc.NotFoundResult, "Missing cart item should return 404.");
    return Task.CompletedTask;
});

await Check("Identity hashing, uniqueness, security stamps, concurrency and roles", async () =>
{
    using var provider = CreateIdentityProvider();
    using var scope = provider.CreateScope();
    var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
    var roles = scope.ServiceProvider.GetRequiredService<RoleManager<IdentityRole>>();
    var user = new ApplicationUser { UserName = "reader@example.com", Email = "reader@example.com" };
    Require((await users.CreateAsync(user, "TestPassword123!")).Succeeded, "Registration should succeed.");
    Require(user.PasswordHash != "TestPassword123!" && user.PasswordHash != null, "Passwords must be hashed.");
    Require(await users.CheckPasswordAsync(user, "TestPassword123!"), "Correct password should work.");
    Require(!await users.CheckPasswordAsync(user, "incorrect"), "Incorrect password should fail.");
    var duplicate = new ApplicationUser { UserName = "READER@example.com", Email = "READER@example.com" };
    Require(!(await users.CreateAsync(duplicate, "TestPassword123!")).Succeeded, "Case-insensitive duplicates must be rejected.");
    var oldStamp = await users.GetSecurityStampAsync(user);
    Require((await users.ChangePasswordAsync(user, "TestPassword123!", "ChangedPassword123!")).Succeeded, "Password change should succeed.");
    Require(oldStamp != await users.GetSecurityStampAsync(user), "Password changes must rotate security stamps.");
    Require(!await users.CheckPasswordAsync(user, "TestPassword123!"), "Old password must stop working.");
    Require((await roles.CreateAsync(new IdentityRole("Administrator"))).Succeeded, "Role creation should succeed.");
    Require((await users.AddToRoleAsync(user, "Administrator")).Succeeded, "Role assignment should succeed.");
    var loaded = await users.FindByNameAsync("READER@EXAMPLE.COM");
    Require(await users.IsInRoleAsync(loaded, "Administrator"), "Roles must persist across detached lookups.");
    var stale = await users.FindByIdAsync(user.Id);
    loaded.EmailConfirmed = true;
    Require((await users.UpdateAsync(loaded)).Succeeded, "First account update should succeed.");
    stale.EmailConfirmed = false;
    Require(!(await users.UpdateAsync(stale)).Succeeded, "Stale account updates must fail concurrency validation.");
    using var secondScope = provider.CreateScope();
    var secondUsers = secondScope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
    Require((await secondUsers.FindByIdAsync(user.Id)).EmailConfirmed, "Identity backing data must be shared across scopes.");
    Require((await users.DeleteAsync(loaded)).Succeeded, "Account deletion should succeed.");
    Require(await secondUsers.FindByIdAsync(user.Id) == null, "Deleted accounts must not remain accessible.");
});

await Check("Optional administrator seeding and fresh-instance reset", async () =>
{
    using var provider = CreateIdentityProvider();
    using var scope = provider.CreateScope();
    var configuration = new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string, string>
    {
        ["InMemoryStore:AdminUserName"] = "admin@example.com",
        ["InMemoryStore:AdminPassword"] = "AdminPassword123!"
    }).Build();
    await InMemoryIdentitySeeder.SeedAsync(scope.ServiceProvider, configuration);
    await InMemoryIdentitySeeder.SeedAsync(scope.ServiceProvider, configuration);
    var users = scope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>();
    var admin = await users.FindByNameAsync("admin@example.com");
    Require(await users.IsInRoleAsync(admin, "Administrator"), "Secret-configured administrator should have the proper role.");
    using var freshProvider = CreateIdentityProvider();
    using var freshScope = freshProvider.CreateScope();
    Require(await freshScope.ServiceProvider.GetRequiredService<UserManager<ApplicationUser>>().FindByIdAsync(admin.Id) == null, "Fresh instance should have no previous accounts.");
    var store = CreateStore();
    store.AddToCart("guest", 1);
    var freshStore = CreateStore();
    Require(freshStore.GetCartItems("guest").Count == 0 && freshStore.GetAlbums().Count == 100, "Fresh instance should reset carts and reseed catalog.");
});

Console.WriteLine($"{checks - failures}/{checks} validation checks passed.");
return failures == 0 ? 0 : 1;

async Task Check(string name, Func<Task> action)
{
    checks++;
    try { await action(); Console.WriteLine($"PASS: {name}"); }
    catch (Exception ex) { failures++; Console.Error.WriteLine($"FAIL: {name}: {ex}"); }
}

static InMemoryDataStore CreateStore()
{
    var store = new InMemoryDataStore();
    DbSeeder.Seed(store);
    return store;
}

static ServiceProvider CreateIdentityProvider()
{
    var services = new ServiceCollection();
    services.AddLogging();
    services.AddDataProtection();
    services.AddSingleton<InMemoryIdentityData>();
    services.AddIdentity<ApplicationUser, IdentityRole>(options => options.User.RequireUniqueEmail = true)
        .AddUserStore<InMemoryUserStore>().AddRoleStore<InMemoryRoleStore>().AddDefaultTokenProviders();
    return services.BuildServiceProvider(new ServiceProviderOptions { ValidateScopes = true });
}

static void Require(bool condition, string message)
{
    if (!condition) throw new InvalidOperationException(message);
}

static void Expect<T>(Action action) where T : Exception
{
    try { action(); }
    catch (T) { return; }
    throw new InvalidOperationException($"Expected {typeof(T).Name}.");
}

sealed class TestSession : ISession
{
    private readonly Dictionary<string, byte[]> _values = new();
    public bool IsAvailable => true;
    public string Id { get; } = Guid.NewGuid().ToString();
    public IEnumerable<string> Keys => _values.Keys;
    public void Clear() => _values.Clear();
    public void Remove(string key) => _values.Remove(key);
    public void Set(string key, byte[] value) => _values[key] = value;
    public bool TryGetValue(string key, out byte[] value) => _values.TryGetValue(key, out value);
    public Task LoadAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
    public Task CommitAsync(CancellationToken cancellationToken = default) => Task.CompletedTask;
}
