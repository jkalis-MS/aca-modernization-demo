# .NET 10 Upgrade Plan

## Execution Steps

Execute steps below sequentially one by one in the order they are listed.

1. Validate that a .NET 10 SDK required for this upgrade is installed on the machine and if not, help to get it installed.
2. Ensure that the SDK version specified in global.json files is compatible with the .NET 10 upgrade.
3. Upgrade MvcMusicStore\MvcMusicStore.csproj to .NET 10
4. Update frontend security vulnerabilities (bootstrap, jQuery, jQuery.Validation)
5. Add Azure Monitor OpenTelemetry and Profiler
6. Prepare for Azure Container Apps deployment

## Settings

This section contains settings and data used by execution steps.

### Excluded projects

No projects are excluded from this upgrade.

### Aggregate NuGet packages modifications across all projects

NuGet packages used across all selected projects or their dependencies that need version update in projects that reference them.

| Package Name                              | Current Version | New Version | Description                                                    |
|:------------------------------------------|:---------------:|:-----------:|:---------------------------------------------------------------|
| Antlr                                     | 3.4.1.9004      |             | Replace with Antlr4 4.6.6                                      |
| Antlr4                                    |                 | 4.6.6       | Replacement for Antlr                                          |
| bootstrap                                 | 3.0.0           | 5.3.8       | Security vulnerability - manual update after modernization     |
| EntityFramework                           | 6.0.0           |             | Replace with Microsoft.EntityFrameworkCore                     |
| jQuery                                    | 1.10.2          | 3.7.1       | Security vulnerability - manual update after modernization     |
| jQuery.Validation                         | 1.11.1          | 1.21.0      | Security vulnerability - manual update after modernization     |
| Microsoft.AspNet.Identity.Core            | 1.0.0           |             | Replace with ASP.NET Core Identity                             |
| Microsoft.AspNet.Identity.EntityFramework | 1.0.0           |             | Replace with ASP.NET Core Identity with EF Core                |
| Microsoft.AspNet.Identity.Owin            | 1.0.0           |             | Replace with ASP.NET Core Identity (security vulnerability)    |
| Microsoft.AspNet.Mvc                      | 5.0.0           |             | Functionality included with ASP.NET Core framework             |
| Microsoft.AspNet.Razor                    | 3.0.0           |             | Functionality included with ASP.NET Core framework             |
| Microsoft.AspNet.Web.Optimization         | 1.1.1           |             | Not supported - remove bundling, use direct script/style tags  |
| Microsoft.AspNet.WebPages                 | 3.0.0           |             | Functionality included with ASP.NET Core framework             |
| Microsoft.EntityFrameworkCore             |                 | 9.0.0       | Replacement for EntityFramework 6                              |
| Microsoft.EntityFrameworkCore.SqlServer   |                 | 9.0.0       | SQL Server provider for EF Core                                |
| Microsoft.Owin                            | 2.0.0           |             | Replace with ASP.NET Core middleware (security vulnerability)  |
| Microsoft.Owin.Host.SystemWeb             | 2.0.0           |             | Replace with ASP.NET Core hosting                              |
| Microsoft.Owin.Security                   | 2.0.0           |             | Replace with ASP.NET Core authentication                       |
| Microsoft.Owin.Security.Cookies           | 2.0.0           |             | Replace with ASP.NET Core cookies (security vulnerability)     |
| Microsoft.Owin.Security.Facebook          | 2.0.0           |             | Replace with ASP.NET Core Facebook authentication              |
| Microsoft.Owin.Security.Google            | 2.0.0           |             | Replace with ASP.NET Core Google authentication                |
| Microsoft.Owin.Security.MicrosoftAccount  | 2.0.0           |             | Replace with ASP.NET Core Microsoft authentication             |
| Microsoft.Owin.Security.OAuth             | 2.0.0           |             | Replace with ASP.NET Core OAuth                                |
| Microsoft.Owin.Security.Twitter           | 2.0.0           |             | Replace with ASP.NET Core Twitter authentication               |
| Microsoft.Web.Infrastructure              | 1.0.0.0         |             | Functionality included with ASP.NET Core framework             |
| Newtonsoft.Json                           | 5.0.6           | 13.0.4      | Security vulnerability - will be updated during modernization  |
| Owin                                      | 1.0             |             | Replace with ASP.NET Core                                      |

### Project upgrade details

This section contains details about each project upgrade and modifications that need to be done in the project.

#### MvcMusicStore\MvcMusicStore.csproj modifications

Project properties changes:
  - Convert project from .NET Framework 4.8 legacy format to SDK-style project
  - Target framework should be changed from `net48` to `net10.0`

NuGet packages changes:
  - Remove deprecated OWIN packages (replaced by ASP.NET Core middleware)
  - Remove ASP.NET Identity packages (replaced by ASP.NET Core Identity)
  - Remove EntityFramework 6.0.0 and add Microsoft.EntityFrameworkCore 9.0.0
  - Remove Microsoft.AspNet.Web.Optimization (bundling/minification)
  - Update Newtonsoft.Json from 5.0.6 to 13.0.4
  - Replace Antlr 3.4.1.9004 with Antlr4 4.6.6
  - Remove Microsoft.AspNet.Mvc, Razor, WebPages (included in ASP.NET Core)
  - Frontend packages (bootstrap, jQuery, jQuery.Validation) will be updated in separate step

Feature upgrades:
  - **System.Web.Optimization**: Remove bundling and minification, replace @Scripts.Render and @Styles.Render with direct script/style tags
  - **RouteCollection**: Convert route registration from Global.asax to Program.cs using MapControllerRoute
  - **GlobalFilterCollection**: Convert global filters to middleware in Program.cs
  - **Global.asax.cs**: Migrate application initialization to Program.cs and Startup.cs patterns
  - **ASP.NET Identity**: Migrate from Microsoft.AspNet.Identity to ASP.NET Core Identity with EF Core
  - **OWIN Authentication**: Replace OWIN middleware with ASP.NET Core authentication middleware
  - **Entity Framework**: Migrate from EF 6 to EF Core 9, update DbContext and database initialization

Other changes:
  - Create Program.cs for ASP.NET Core application entry point
  - Update Web.config settings to appsettings.json
  - Update connection strings for EF Core
  - Update Razor views syntax for ASP.NET Core MVC
  - Remove Global.asax and Global.asax.cs
  - Update namespace imports and using statements
  - Add Azure Monitor OpenTelemetry packages and configuration
  - Add OpenTelemetry Profiler integration
  - Create Dockerfile for containerization
  - Document Azure Container Apps deployment steps
