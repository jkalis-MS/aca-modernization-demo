using System;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;
using MvcMusicStore.Models;
using MvcMusicStore.Data;
using MvcMusicStore.Services;
using Azure.Monitor.OpenTelemetry.AspNetCore;
using Azure.Monitor.OpenTelemetry.Profiler;
using Azure.Identity;
using Azure.Extensions.AspNetCore.Configuration.Secrets;

var builder = WebApplication.CreateBuilder(args);

// Configure Azure Key Vault integration with Managed Identity
var keyVaultName = builder.Configuration["KeyVaultName"];
if (!string.IsNullOrEmpty(keyVaultName))
{
    var keyVaultUri = new Uri($"https://{keyVaultName}.vault.azure.net/");
    
    // Use DefaultAzureCredential which supports:
    // - Managed Identity (in Azure)
    // - Azure CLI (local development)
    // - Visual Studio (local development)
    builder.Configuration.AddAzureKeyVault(
        keyVaultUri,
        new DefaultAzureCredential());
}

// Configure OpenTelemetry with Azure Monitor
var connectionString = builder.Configuration["ApplicationInsights:ConnectionString"];
if (!string.IsNullOrEmpty(connectionString))
{
    builder.Services.AddOpenTelemetry()
        .UseAzureMonitor(options =>
        {
            options.ConnectionString = connectionString;
        })
        .AddAzureMonitorProfiler();  // Add Azure Monitor Profiler
}

// Add services to the container.
builder.Services.AddControllersWithViews();

// Register Key Vault Service
builder.Services.AddSingleton<IKeyVaultService, KeyVaultService>();

// Configure Entity Framework Core with SQL Server
builder.Services.AddDbContext<MusicStoreEntities>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("MusicStoreEntities")));

// Configure ASP.NET Core Identity
builder.Services.AddDbContext<ApplicationDbContext>(options =>
    options.UseSqlServer(builder.Configuration.GetConnectionString("DefaultConnection")));

builder.Services.AddIdentity<ApplicationUser, IdentityRole>(options =>
{
    // Password settings
    options.Password.RequireDigit = true;
    options.Password.RequiredLength = 6;
    options.Password.RequireNonAlphanumeric = false;
    options.Password.RequireUppercase = true;
    options.Password.RequireLowercase = false;
    
    // Lockout settings
    options.Lockout.DefaultLockoutTimeSpan = TimeSpan.FromMinutes(30);
    options.Lockout.MaxFailedAccessAttempts = 10;
    
    // User settings
    options.User.RequireUniqueEmail = true;
})
.AddEntityFrameworkStores<ApplicationDbContext>()
.AddDefaultTokenProviders();

// Configure application cookie
builder.Services.ConfigureApplicationCookie(options =>
{
    options.Cookie.HttpOnly = true;
    options.ExpireTimeSpan = TimeSpan.FromMinutes(30);
    options.LoginPath = "/Account/Login";
    options.LogoutPath = "/Account/LogOff";
    options.AccessDeniedPath = "/Account/Login";
    options.SlidingExpiration = true;
});

// Configure session
builder.Services.AddDistributedMemoryCache();
builder.Services.AddSession(options =>
{
    options.IdleTimeout = TimeSpan.FromMinutes(30);
    options.Cookie.HttpOnly = true;
    options.Cookie.IsEssential = true;
});

var app = builder.Build();

if (!app.Environment.IsDevelopment())
{
    app.UseExceptionHandler("/Home/Error"); // Global error handler
    app.UseStatusCodePagesWithReExecute("/Home/StatusErrorCode", "?code={0}");
    app.UseHsts();
}

app.UseHttpsRedirection();
app.UseStaticFiles();

app.UseRouting();
app.UseSession();
app.UseAuthentication();
app.UseAuthorization();

app.MapControllerRoute(
    name: "default",
    pattern: "{controller=Home}/{action=Index}/{id?}");

// Auto-migrate and seed database on startup
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();
    
    try
    {
        logger.LogInformation("Starting database initialization...");
        
        var context = services.GetRequiredService<MusicStoreEntities>();
        var identityContext = services.GetRequiredService<ApplicationDbContext>();
        
        // Check if database recreation is enabled (useful during development)
        var recreateDatabase = builder.Configuration.GetValue<bool>("Database:RecreateOnStartup", false);
        
        if (recreateDatabase)
        {
            logger.LogWarning("?? Database recreation is ENABLED. This will delete all existing data!");
            
            // Recreate main database
            await DbSeeder.RecreateAndSeedAsync(context, logger, app.Environment.WebRootPath);
            
            // Recreate Identity database
            logger.LogInformation("Recreating Identity database...");
            await identityContext.Database.EnsureDeletedAsync();
            await identityContext.Database.MigrateAsync();
            logger.LogInformation("Identity database recreated.");
        }
        else
        {
            // Normal migration and seeding
            logger.LogInformation("Running EF Core migrations for MusicStoreEntities...");
            await context.Database.MigrateAsync();
            
            logger.LogInformation("Running EF Core migrations for Identity database...");
            await identityContext.Database.MigrateAsync();
            
            logger.LogInformation("Database migrations completed successfully.");
            
            // Normal seeding (only if empty)
            logger.LogInformation("Seeding database if needed...");
            await DbSeeder.SeedAsync(context, app.Environment.WebRootPath);
            logger.LogInformation("Database seeding completed.");
        }
        
        logger.LogInformation("? Database initialization complete!");
    }
    catch (Exception ex)
    {
        logger.LogError(ex, "An error occurred while initializing the database.");
        // Don't throw - allow app to start even if migration fails
        // This allows the app to serve requests and show meaningful errors
    }
}

app.Run();