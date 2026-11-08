using System;
using Microsoft.AspNetCore.Builder;
using Microsoft.AspNetCore.Identity;
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

// Store and accounts are shared within this process and reset on restart.
builder.Services.AddSingleton<InMemoryDataStore>();
builder.Services.AddSingleton<InMemoryIdentityData>();

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
.AddUserStore<InMemoryUserStore>()
.AddRoleStore<InMemoryRoleStore>()
.AddDefaultTokenProviders();

builder.Services.Configure<SecurityStampValidatorOptions>(options =>
    options.ValidationInterval = TimeSpan.Zero);

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

// Initialize the process-local catalog and optional administrator on startup.
using (var scope = app.Services.CreateScope())
{
    var services = scope.ServiceProvider;
    var logger = services.GetRequiredService<ILogger<Program>>();

    DbSeeder.Seed(services.GetRequiredService<InMemoryDataStore>(), app.Environment.WebRootPath);
    await InMemoryIdentitySeeder.SeedAsync(services, builder.Configuration);
    logger.LogInformation("In-memory store initialized. Changes and accounts are lost on restart.");
}

app.Run();