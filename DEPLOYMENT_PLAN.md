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

## Parallel deployment to another region

Deploy a new resource group and a complete new regional stack; do not change the
location of the existing resources. Resource names derive from the resource
group and environment, so a new group produces new app, SQL server, registry,
identity, and vault names. Read those names from Bicep outputs rather than
substituting a region in existing names or URLs.

Keep each deployment's configuration and any outstanding firewall recovery
snapshot together under ignored `config\deployments\<profile>\`. Start the new
profile from `config\azure.example.json`, not from a populated old profile that
would retain stale demo revisions or secret references. Explicitly pass its
`-ConfigPath` while provisioning and verifying; leave the active root
`config\azure.local.json` unchanged until the new stack is ready.

Use fresh seeded databases unless data migration is explicitly required. Import
the verified healthy and candidate images by digest into the new registry,
bootstrap the new managed identity's database users, and create a token in the
new vault. Recreate both demo revisions, probes, scale rules, SQL connection
rotation, and healthy-only traffic. A normal deployment-script invocation alone
does not recreate the multiple-revision operational demo.

Verify resource locations, Consumption assignment, catalog/readiness, both demo
image identities, and candidate behavior before switching the active local
configuration. Keep the old stack intact. Restart the three presenter terminals
and reload the new token: already-running scripts and cached `$Config`, `$Azure`,
`$V1`, and `$V2` variables do not follow a configuration-file change.
Rehearse Cascade's SRE Agent access against the new app separately.

### Move only Container Apps to another region

When supporting services must stay in their original region, deploy
`src\infra\container-app.bicep` directly at resource-group scope in **incremental**
mode. This is the same module used by `main.bicep`; probes, identity selection,
secrets, SQL connection rotation, and scale settings stay consistent.

Supply new app/environment names and their target `location`, plus the existing
identity, registry, vault, SQL server/databases, Log Analytics, and Application
Insights names. Those dependencies must be in the deployment's resource group.
The module declares them as existing references: it does not move, recreate,
grant new permissions to, or reset them. Preview must create only the new app
and environment. Do not deploy the full subscription template to perform this
ACA-only relocation.
`Deploy-MusicStore.ps1` refuses a split-region profile targeting the same resource
group, even with `-ResetDemoConfiguration`, rather than accidentally redeploying
the original regional app. A new full-stack deployment needs a separate profile
or an explicitly different resource group.

Keep `deployment.location` as the supporting-services region and record the
ACA region in `deployment.containerAppLocation`. After verification, update only
the app/environment/URL and demo revision references in the active configuration;
the SQL server name, database data, image registry, identity, and secret reference
remain unchanged. Existing images can be pulled across regions without imports.
Keep the old app as a fallback until explicitly retired.
When retiring it, delete only the explicitly selected old Container App. Keep
the shared SQL, registry, vault, identity, monitoring, and resource group.
Deleting the old environment is a separate decision. An archived local profile
is a historical record after retirement, not a working fallback target.

**Shared-dependency warning:** the old and new apps use the same databases,
monitoring, and token. Scenario 3's SQL firewall change affects both apps;
regional app separation does not isolate a shared SQL outage. Do not reseed or
replace these existing databases when staging the new app. Cross-region SQL
calls can also change latency, so rehearse the scaling and incident timing again.
