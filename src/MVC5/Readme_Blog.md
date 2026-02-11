# From "Maybe Next Quarter" to Done Before Lunch: Modernizing a Legacy .NET App with GitHub App Modernization

---

A year ago, I wanted to modernize Jon Galloway's [MVC Music Store](https://github.com/jongalloway/MvcMusicStore) — a classic ASP.NET MVC 5 app running on .NET Framework 4.8 with Entity Framework 4.1. The goal was straightforward: move to modern .NET, enable managed identity, and deploy to Azure Container Apps. No more plaintext connection strings. No more passwords in config files.

I hit a wall immediately.

Entity Framework on .NET Framework doesn't support `Azure.Identity` or `DefaultAzureCredential`. You can't just add a NuGet package and call it done — you need EF Core, which means you need modern .NET. That means rewriting the data layer, the identity system, the startup pipeline, the views. The engineering team estimated **one week** of dedicated developer work. As a PM without deep .NET migration experience, I couldn't do it quickly myself. The project went on the backlog.

At that time, **GitHub App Modernization** existed but only offered **assessment** — it could tell you *what* needed to change, but couldn't make the changes for you.

Fast-forward one year. The full modernization agent shipped. I sat down with the same app and the same goal. **A few hours later, it was running on Azure Container Apps with managed identity, Key Vault integration, and zero plaintext credentials.**

Here's how it went.

---

## Phase 1: Assessment

GitHub App Modernization starts by analyzing your codebase and producing a detailed assessment:

- **Framework gap analysis** — .NET Framework 4.0 → .NET 10, identifying every breaking change
- **Dependency inventory** — Entity Framework 4.1 (not EF Core), MVC 3 references, System.Web dependencies
- **Security findings** — plaintext SQL connection strings in `Web.config`, no managed identity support
- **API surface changes** — `Global.asax` → `Program.cs` minimal hosting, `System.Web.Mvc` → `Microsoft.AspNetCore.Mvc`

The assessment is not a generic checklist. It reads your code — your controllers, your `DbContext`, your views — and maps a concrete migration path. For this app, the key finding was clear: EF 4.1 on .NET Framework cannot support `DefaultAzureCredential`. The *entire* data layer needs to move to EF Core on modern .NET to unlock passwordless authentication.

## Phase 2: Code & Dependency Modernization

This is where last year's experience ended and this year's began. The agent performed the actual migration:

**Project structure:**
- `.csproj` converted from legacy XML format to SDK-style targeting `net10.0`
- `Global.asax` replaced with `Program.cs` using minimal hosting
- `packages.config` → NuGet `PackageReference` entries

**Data layer (the hard part):**
- Entity Framework 4.1 → EF Core with `Microsoft.EntityFrameworkCore.SqlServer`
- `DbContext` rewritten with `OnModelCreating` fluent configuration
- `System.Data.Entity` → `Microsoft.EntityFrameworkCore` namespace throughout
- EF Core migrations generated from scratch
- Database seeding moved to a proper `DbSeeder` pattern with `MigrateAsync()`

**Identity:**
- ASP.NET Membership → ASP.NET Core Identity with `ApplicationUser`, `ApplicationDbContext`
- Cookie authentication configured through `ConfigureApplicationCookie`

**Security (the whole point):**
- `Azure.Identity` + `DefaultAzureCredential` integrated in `Program.cs`
- Azure Key Vault configuration provider added via `Azure.Extensions.AspNetCore.Configuration.Secrets`
- Connection strings use `Authentication=Active Directory Default` — no passwords anywhere
- Application Insights wired through OpenTelemetry

**Views:**
- Razor views updated from MVC 3 helpers to ASP.NET Core Tag Helpers and conventions
- `_Layout.cshtml` and all partials migrated

The code changes touched every layer of the application. This is not a find-and-replace — it's a structural rewrite that maintains functional equivalence.

## Phase 3: Local Testing

After modernization, the app builds, runs locally, and connects to a local SQL Server (or SQL in a container). EF Core migrations apply cleanly, the seed data loads, and you can browse albums, add to cart, and check out. The identity system works. The Key Vault integration gracefully skips when `KeyVaultName` isn't configured — meaning local dev and Azure use the same `Program.cs` with zero code branches.

## Phase 4: `azd up` and Deployment to Azure

The agent also generates the deployment infrastructure:

- **`azure.yaml`** — AZD service definition pointing to the `Dockerfile`, targeting Azure Container Apps
- **`Dockerfile`** — Multi-stage build using `mcr.microsoft.com/dotnet/sdk:10.0` and `aspnet:10.0`
- **`infra/main.bicep`** — Full IaC including:
  - Azure Container Apps with system + user-assigned managed identity
  - Azure SQL Server with **Azure AD-only authentication** (no SQL auth)
  - Azure Key Vault with RBAC, Secrets Officer role for the managed identity
  - Container Registry with ACR Pull role assignment
  - Application Insights + Log Analytics
  - All connection strings injected as Container App secrets — using `Active Directory Default`, not passwords

One command:

```bash
azd up
```

Provisions everything, builds the container, pushes to ACR, deploys to Container Apps. The app starts, runs `MigrateAsync()` on first boot, seeds the database, and serves traffic. Managed identity handles all auth to SQL and Key Vault. No credentials stored anywhere.

---

## What Changed in a Year

| | Early 2024 | Mid 2025 |
|---|---|---|
| **Assessment** | ✅ Available | ✅ Available |
| **Automated code modernization** | ❌ Not yet | ✅ Full migration agent |
| **Target framework** | .NET 8 | .NET 10 |
| **EF Core managed identity support** | Available but manual migration required | Agent handles the full EF → EF Core rewrite |
| **Infrastructure generation** | ❌ Manual | ✅ Bicep + AZD generated |
| **Time to complete** | ~1 week (senior developer) | ~Few hours (PM, no deep .NET experience) |

The technology didn't just improve incrementally. The gap between "assessment" and "done" collapsed. A year ago, knowing *what* to do and *being able to do it* were very different things. Now they're the same step.

---

## Who This Is For

If you have a .NET Framework app sitting on a backlog because "the migration is too expensive" — revisit that assumption. The cost changed. GitHub App Modernization doesn't just tell you what's wrong. It rewrites your data layer, generates your infrastructure, and gets you to `azd up`. The hardest part of this modernization — EF to EF Core with managed identity — is exactly the part the agent handles end to end.

MVC Music Store went from .NET Framework 4.0 with Entity Framework 4.1 and plaintext SQL credentials to .NET 10 on Azure Container Apps with managed identity, Key Vault, and zero secrets in code. In an afternoon.

That backlog item might be a lunch break now.

---

*The [MVC Music Store modernization repository](https://github.com/jkalis-MS/aca-modernization-demo) is public. The `appmod/dotnet-migration-plaintext-credentials-to-azure-key-vault-with-managed-identity` branch contains the fully modernized application with all infrastructure code.*
