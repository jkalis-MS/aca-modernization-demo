# Music Store deployment plan

Deploy the modernized Music Store into a new, self-contained resource group in
an operator-selected region, using Bicep, Azure Container Apps Consumption, and
Azure SQL Database.

This is a reusable deployment plan, not a record of an operator's deployment.
Copy `config\azure.example.json` to ignored `config\azure.local.json` and populate
the deployment settings and resource references locally. Keep secret values out
of JSON; store only token secret references.

## 1. Target architecture

| Component | Proposed configuration |
|---|---|
| Subscription | Operator-selected subscription from local configuration |
| Resource group | New, operator-selected resource group from local configuration |
| Region | Operator-selected region with required service availability and quota |
| Container Apps environment | New workload-profiles environment with an explicit Consumption profile; no Dedicated profiles |
| Container app | Music Store's .NET 10 Linux image, explicitly assigned to Consumption |
| Compute | Initially 0.5 vCPU / 1 GiB, one replica |
| Ingress | Public HTTPS endpoint, forwarding to container port 8080 |
| Container registry | New Azure Container Registry, Basic tier; admin credentials disabled |
| Database | One Azure SQL logical server with two databases: `MvcMusicStore` and `MvcMusicStore-Identity`, matching the existing app |
| SQL tier | Initially Basic, 5 DTU per database, suitable for this demonstration |
| Authentication | Managed identity for registry pulls, SQL connections, and Key Vault access; no SQL passwords |
| Supporting services | Key Vault, Log Analytics, and Application Insights |

Every deployed resource will belong to the same resource group, including
identities and any deployment-bootstrap resources. Regional resources will use
the configured location.

One replica avoids introducing multi-replica session problems: the application
currently stores session state in memory. Consumption does not require scaling to
zero. Registry, SQL, monitoring, and an always-running app still incur charges.

## 2. Prepare the Bicep deployment

Reuse and update `src\infra\main.bicep`, rather than create a separate
infrastructure implementation.

- Add a subscription-scoped Bicep entry point that creates the new resource group
  and invokes the resource-group-scoped infrastructure module.
- Parameterize resource names, region, image reference, database SKU, and replica
  settings.
- Explicitly configure the environment's Consumption workload profile and the
  app's `workloadProfileName`.
- Replace the current hello-world placeholder with the actual application image.
- Keep resource creation and configuration in Bicep. Use CLI/AZD only to
  orchestrate validation, image builds, and deployment.
- Output the application URL, resource group, registry, and database endpoints.

## 3. Resolve deployment-readiness gaps

Before provisioning:

- Build the application and container, and run a local container check if Docker
  is available.
- Make managed-identity selection consistent between SQL and Key Vault.
- Configure SQL Entra administration and bootstrap the application's database
  users and permissions. Grant the permissions needed for the existing startup
  migrations without making the running app the SQL server administrator.
- Grant registry-pull and Key Vault access at the appropriate resource scopes.
- Explicitly set Production configuration and
  `Database__RecreateOnStartup=false`.
- Configure startup/readiness checks so an HTTP listener alone does not hide
  database initialization failure.
- Check HTTPS forwarding and authentication-cookie behavior behind Container
  Apps ingress.

Networking assumption for this demo: public application ingress and public
SQL/Key Vault endpoints protected by authentication and firewall controls. The
existing SQL template allows Azure services broadly; flag that explicitly in the
deployment preview rather than describe it as private networking.

## 4. Validate before deployment

- Check subscription policies, required provider registrations, deployment
  permissions, and selected-region service availability/Consumption quota.
- Compile and lint the Bicep.
- Run deployment validation and what-if.
- Confirm the preview creates only the intended new resource group and its
  resources, with no changes to existing applications or environments.

Subscription access alone does not establish deployment permissions or capacity.
Complete these checks for each target before provisioning.

## 5. Deploy in stages

1. Provision the resource group and supporting infrastructure through Bicep.
2. Build and push the app image to the new registry using an immutable image tag.
3. Bootstrap SQL access, then deploy the app image and configuration through
   Bicep.
4. Allow the app to apply its existing EF Core migrations and seed the new
   database.

## 6. Verify the finished deployment

Verify the HTTPS endpoint, album browsing, registration/login, shopping cart,
checkout, database migrations, and telemetry. Confirm all resources are in the
requested resource group and region, and that the app is using Consumption.

## Private deployment outputs

Keep application URLs, portal links, resource identifiers, image digests, revision
names, secret references, and deployment/verification execution records in local
configuration or private operator notes. Private deployment outputs are not
committed to this repository.
Deployment automatically saves returned resource identifiers to ignored local
configuration without credentials. After the first operator deployment, outputs
are captured locally; update demo revision/version references locally when staging.

The shared `scripts\Get-AzureLocalConfig.ps1` helper returns the parsed object,
defaults `-ConfigPath` to root `config\azure.local.json`, and accepts
`-RequiredSettings` as dotted-path strings. It always validates schema version 1
and the subscription GUID, makes no Azure calls, and has no account-default
fallback. Deployment and observation scripts load configuration automatically;
explicit arguments override settings but always require a valid configured
subscription. `Watch-Demo.ps1` resource overrides are `-ResourceGroup` and
`-AppName`. Traffic and smoke-test scripts load the configured application URL
and require a configured subscription unless `-ApplicationUrl` is supplied;
an explicit URL allows local/mock tests without configuration.
Native `az` commands must always pass that subscription explicitly.

See [README.md](README.md#deploy-this-checkout) for deployment commands,
redeployment options, synthetic smoke-test data, networking/cost/session
tradeoffs, and pre-existing build warnings.
