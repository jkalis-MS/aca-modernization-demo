# Music Store: ACA operations presenter runbook

Use the existing web application to show HTTP scaling, traffic rollback, and
diagnosis of a mysterious regression with **Debug with SRE Agent** in Cascade.
Allow about 20–25 minutes, with extra time for incident propagation if needed.

**Rehearsal requirement:** verify scale-out, candidate exposure, and rollback in
one uninterrupted traffic run in your own environment. Also rehearse regression
introduction, the Cascade SRE Agent workflow, and recovery before presenting.

**Deployment prerequisite for the unified traffic command:** rebuild and stage
both healthy and candidate images from code supporting the combined `demo`
operation when setting up another deployment. Older images support only separate
operations; changing PowerShell does not update those images. Update your ignored
local revision references after staging both images.
After a rollout, reload CONTROL's `$Config`, `$V1`, and `$V2` variables.
WATCH automatically discovers new active revisions without restarting.

After changing deployments or regions, restart all three terminals and repeat
initialization, including loading the new demo token. Existing processes and
cached CONTROL variables still target the previous app. App, SQL server, vault,
URL, and revision names come from local configuration, not from the region name.
If old and new apps share the SQL server, Scenario 3 affects both apps even when
their Container Apps environments are in different regions.

## Terminals and prerequisites

Open **three PowerShell 7.4+ terminals** in the repository root. Keep their names
visible in terminal tabs or window titles:

| Terminal | Name | Colors | Purpose |
|---|---|---|---|
| 1 | CONTROL | White on dark charcoal (`#202020`) | Azure inspection, traffic changes, and regression control |
| 2 | TRAFFIC | White on near-black navy (`#0B1220`) | Synthetic HTTP requests; holds the demo token in memory |
| 3 | WATCH | **Bright white on black** | **Primary audience view:** read-only replica status |

Initialization sets each window title and its console colors, then clears the
screen. CONTROL uses dark charcoal, TRAFFIC uses near-black navy, and WATCH uses black so
their roles remain visually distinct. Keep WATCH largest and most prominent, with a
font size readable from the back row. Do not rely on color alone: READY/STARTING
labels and replica counts carry the meaning. Check contrast on the actual
projector during rehearsal. Hosts may override console colors;
if yours does, select the matching color scheme in its terminal settings.
CONTROL and TRAFFIC use explicit RGB backgrounds rather than PowerShell's
palette-based `DarkGray`/`DarkBlue`, which can appear much brighter depending on
the terminal theme. Their escape sequences require a terminal supporting
true-color and OSC 11.

Initialization also shortens each PowerShell prompt to `CONTROL>`, `TRAFFIC>`,
or `WATCH>`. This changes only the current terminal session, not the working
directory or your saved PowerShell profile.

Every PowerShell command below occupies one physical line, with no continuation
backticks. Paste one line at a time; use Up Arrow to repeat that complete command.
Long lines may wrap visually in the terminal, but remain a single history entry.
Terminal labels are outside the command blocks.

Initialization enables native-command error handling for the current session.
Failed Azure CLI commands report errors and stop execution without inline
exit-code checks. The regression script saves a private recovery baseline before
changing the environment.

Before presenting, copy this template to `config\PRESENTER_RUNBOOK.local.md` and
replace all three `<repository-root>` placeholders in that ignored local copy
with your checkout's absolute path. Its commands will then be ready to paste into
fresh terminals without prompts. Keep machine-specific paths out of this shared
template. Azure settings come only from the ignored local configuration.

Use an isolated demo environment with no real users. The app has local sessions
and data-protection keys: demonstrate **anonymous catalog browsing only**, not
cart/login continuity.

Before the talk, build and stage both images and configure the local file.
Do not build, provision infrastructure, grant permissions, or run the deployment
script onstage. The ignored `config\azure.local.json` must contain the application
URL, subscription, resource group, app name, SQL server name, healthy/candidate
revisions, baked candidate version, and versioned Key Vault token reference.
Never show the token. Complete Scenario 3's presenter-only preflight below
before screen sharing.

### Terminal 1 — CONTROL: initialize

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
$ErrorActionPreference = 'Stop'; $PSNativeCommandUseErrorActionPreference = $true
Set-Location -LiteralPath '<repository-root>'
$Host.UI.RawUI.WindowTitle = '1 - CONTROL'; $Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'White'; Write-Host "`e]11;#202020`a`e[48;2;32;32;32m`e[2J`e[H" -NoNewline
function global:prompt { 'CONTROL> ' }
$Config = .\scripts\Get-AzureLocalConfig.ps1 -RequiredSettings deployment.tenantId,deployment.resourceGroupName,resources.containerAppName,resources.applicationUrl,resources.sqlServerName,demo.healthyRevision,demo.candidateRevision
$V1 = $Config.demo.healthyRevision
$V2 = $Config.demo.candidateRevision
$Azure = @('--subscription', $Config.deployment.subscriptionId, '--resource-group', $Config.deployment.resourceGroupName, '--name', $Config.resources.containerAppName)
```

Sign in before the presentation. Skip this if the correct Azure login is already
available. Authentication and permissions must be established offstage.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az login --tenant $Config.deployment.tenantId --output none
```

Inspect the starting state. Require Multiple mode, HTTPS ingress, healthy
revision at 100%, candidate at 0%, healthy min/max 2/4, candidate min/max 1/1,
and HTTP concurrency target 5. Both revisions should be healthy.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp show @Azure --query '{mode:properties.configuration.activeRevisionsMode,traffic:properties.configuration.ingress.traffic}' -o json
az containerapp revision list @Azure --query '[].{revision:name,healthy:properties.healthState,traffic:properties.trafficWeight,min:properties.template.scale.minReplicas,max:properties.template.scale.maxReplicas}' -o table
az containerapp revision show @Azure --revision $V1 --query properties.template.scale -o json
```

If staging is incomplete or values differ, stop and correct them offstage.
Do not improvise a deployment during the demo.

### Terminal 2 — TRAFFIC: initialize

This terminal has its own variables. Load the token here, not in CONTROL or WATCH.

**Run in TERMINAL 2: TRAFFIC - PowerShell.**

```powershell
$ErrorActionPreference = 'Stop'; $PSNativeCommandUseErrorActionPreference = $true
Set-Location -LiteralPath '<repository-root>'
$Host.UI.RawUI.WindowTitle = '2 - TRAFFIC'; $Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'White'; Write-Host "`e]11;#0B1220`a`e[48;2;11;18;32m`e[2J`e[H" -NoNewline
function global:prompt { 'TRAFFIC> ' }
$Config = .\scripts\Get-AzureLocalConfig.ps1 -RequiredSettings resources.applicationUrl,resources.keyVaultName,demo.tokenSecretName,demo.tokenSecretVersion,demo.candidateVersion
$env:MUSICSTORE_DEMO_TOKEN = az keyvault secret show --subscription $Config.deployment.subscriptionId --vault-name $Config.resources.keyVaultName --name $Config.demo.tokenSecretName --version $Config.demo.tokenSecretVersion --query value --output tsv
```

### Terminal 3 — WATCH: start observation

**Run in TERMINAL 3: WATCH - PowerShell.**

```powershell
$ErrorActionPreference = 'Stop'; $PSNativeCommandUseErrorActionPreference = $true
Set-Location -LiteralPath '<repository-root>'
$Host.UI.RawUI.WindowTitle = '3 - WATCH'; $Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'White'; Clear-Host
function global:prompt { 'WATCH> ' }
.\scripts\Watch-Demo.ps1
```

Keep WATCH running across the scenarios. It automatically discovers all active
revisions, including the 0%-traffic candidate, and groups their replicas by
revision. New revisions and replicas appear without restarting. The top totals
include every displayed revision; use each revision's group for scenario-specific
evidence. It has no overall time limit. Press **Ctrl+C in TERMINAL 3: WATCH** to
stop it. Azure CLI query failures/timeouts still stop observation.

## Scenario 1 — HTTP scaling (about 4 minutes, then revisit scale-in)

**Say:** "The app starts with two warm replicas. We will increase concurrent web
requests and let ACA add capacity, up to our configured limit of four."

Pin public traffic to the healthy revision. This also resets a previous canary.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp ingress traffic set @Azure --revision-weight "$V1=100" "$V2=0" --output none
```

**Run in TERMINAL 2: TRAFFIC - PowerShell.**

```powershell
.\scripts\Invoke-DemoTraffic.ps1
```

**Point to TRAFFIC:** approximately 32 in-flight requests; responses/second,
successes, errors, and requests attributed to additional instances.

The normal scaling display omits latency, diagnostic counters, and explanatory footer
notes. Diagnostic counters appear if an unexpected failure occurs; `-Verbose`
includes latency, counters, and notes for troubleshooting. Each replica/process
row has a count column for every observed HTTP status, initially `HTTP 200`.
`HTTP 503` appears naturally when the candidate starts returning errors, along
with the recent-response window. Rows with HTTP error statuses are red.
Instance request counts are cumulative responders,
not current readiness; latency percentiles use the latest 2,048 completions.

**Point to WATCH:** the healthy revision starts with two ready replicas;
additional replicas may appear and become ready, up to four. The candidate has
its own group with one warm replica even at 0% traffic, so the top total can grow
from three to five. A listed but unready replica is not serving-capacity
evidence. The request display confirms which instances actually responded.

**Explain:** the protected operation adds 500 ms of cancellable asynchronous
delay before normal catalog SQL/MVC processing. This makes concurrent demand
visible without CPU stress. It is not a production performance benchmark.

The generator keeps 32 requests in flight until you press **Ctrl+C in TERMINAL 2:
TRAFFIC**. There is no duration or total-request limit. Leave this exact process
running into Scenario 2; no scenario argument, switch, or restart is needed.
The continuous run stays up through timeouts, HTTP errors, and a complete outage
so it can show recovery without restarting. Authentication/setup failures still
stop traffic. Optional duration/request-bounded verification runs retain their
high-error-rate safety stop and strict failure result.

Cancellation of in-flight requests when you stop traffic is expected and is not
counted as an error. Unexpected failures remain visible; read the
`FAILURE` outcome/status on TRAFFIC. Use `-OutputPath` with a new filename when
starting traffic offstage if per-request evidence is needed.
Do not describe a run with unexpected failures as error-free.

Keep WATCH and TRAFFIC running. Continued load can keep the extra replicas warm.
Show scale-in after stopping traffic at the end of Scenario 2, not while the
same scaling load continues. Do not lower replica settings to manufacture scale-in.

**Rehearsal gate:** added ready replicas must serve successful responses within
the measured budget. If not, stop the load and use a clearly labeled recording.
Do not repeatedly escalate concurrency. No exact scaling time is guaranteed.

## Scenario 2 — Candidate exposure and traffic rollback (about 6 minutes)

**Say:** "Both versions were built and staged before this talk. The candidate is
running, but receives no public traffic."

Verify ordinary browsing and readiness through the candidate's direct URL.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
$V2Host = az containerapp revision show @Azure --revision $V2 --query properties.fqdn -o tsv
(Invoke-WebRequest "https://$V2Host/health/ready" -TimeoutSec 15).StatusCode
(Invoke-WebRequest "https://$V2Host/Store/Browse?genre=Rock" -TimeoutSec 15).StatusCode
```

Both must return 200. This is intentionally a regression that passes readiness:
only the authenticated combined demo (or standalone release-check) operation
fails in the candidate.
Ordinary browsing is unchanged and no database data is corrupted.

Keep the TRAFFIC process from Scenario 1 running unchanged. Every request already
combines the scaling delay and candidate-regression behavior. CONTROL only changes
routing weights; do not enter another command in TRAFFIC.

Confirm successful responses and zero errors before exposing the candidate.
If starting this scenario independently, restore healthy 100% and candidate 0%
with the CONTROL reset command in Scenario 1, then start the same default traffic
command shown there.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp ingress traffic set @Azure --revision-weight "$V1=90" "$V2=10" --output none
```

**Point to TRAFFIC:** both version identities, healthy successes, and candidate
503 errors appearing in the candidate row's **HTTP 503** column in the
already-running process. **LAST 10s** shows recent
responses, while totals and the identity table retain the whole run's history.
The sample will not necessarily be exactly 90/10. Connection
behavior and sample size affect the observed distribution.

**Say:** "We identified the regression by version. Now we manually return traffic
to the healthy revision." Roll back even if the sampler reports an error.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp ingress traffic set @Azure --revision-weight "$V1=100" "$V2=0" --output none
az containerapp show @Azure --query properties.configuration.ingress.traffic -o table
```

Leave the same TRAFFIC process running. After routing propagation, in-flight
requests drain, and old failures age out of the 10-second window, expect
**LAST 10s** to show successful responses and zero errors. The
recent error count returns to its normal color. Historical error totals do not reset or decrease;
the candidate remains in the cumulative identity table, but its HTTP 503 count
stops growing. A window with no responses
is not rollback evidence. If new candidate errors persist, stop and inspect; do
not claim a successful rollback.

Press **Ctrl+C in TERMINAL 2: TRAFFIC** after showing the healthy responses.

**Explain:** this is manual traffic rollback, not automatic rollback. It does not
undo database changes, shared secrets/configuration, or external side effects.
The overlapping versions use compatible schemas.

**Revisit WATCH:** after stopping TRAFFIC, observe the healthy revision's natural
scale-in toward two replicas, plus the candidate's one warm replica. It can take
several minutes. If scale-in is delayed, describe the delay
and use the rehearsal recording.

## Scenario 3 — Misterious regression and Debug with SRE Agent (about 8–10 minutes)

**Say:** "The catalog is working. An intern is about to introduce a mysterious
regression. Instead of guessing, let's investigate with SRE Agent."

This is a deliberately disruptive availability incident, not a process-crash
demonstration. Keep the cause hidden until the agent has investigated. Do not
project the script source, recovery snapshot, presenter-only notes, or `-Verbose`
output. No build, redeployment, revision restart, or canary exposure is needed.

### Establish the working baseline

Require healthy 100% traffic, candidate 0%, working catalog browsing, and healthy
database readiness. Resolve any leftover incident offstage before starting.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp show @Azure --query properties.configuration.ingress.traffic -o table
(Invoke-WebRequest "$($Config.resources.applicationUrl.TrimEnd('/'))/health/ready" -TimeoutSec 30).StatusCode
(Invoke-WebRequest "$($Config.resources.applicationUrl.TrimEnd('/'))/Store/Browse?genre=Rock" -TimeoutSec 30).StatusCode
```

Both HTTP checks must return 200. Browse the catalog in the browser as well.

If TRAFFIC was stopped to show scale-in after Scenario 2, start the same default
command again. If it is already running, leave it alone; do not start a second
generator. Keep this process and WATCH running through the incident and recovery.
No scenario argument or incident-specific switch is required.

**Run in TERMINAL 2: TRAFFIC - PowerShell, only if not already running.**

```powershell
.\scripts\Invoke-DemoTraffic.ps1
```

### Introduce the regression

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
.\scripts\Introduce-Misterious-Regression.ps1
```

The large ASCII banner says **"Misterious regression introduced. Greetings from
the Intern :)"** without revealing the cause. Run the command once, without
`-Restore` or `-Verbose`. Allow time for the failure to appear; do not repeat the
fault or restart the revision to speed it up.

**Point to TRAFFIC:** successes give way to HTTP errors or timeouts. The continuous
run stays up even if every request fails. **LAST 10s** shows recent outcomes;
cumulative failures are retained. Missing response identities do not mean there
are zero containers.

**Point to WATCH:** readiness, activation, and restart behavior may change.
A revision's **Healthy** label alone does not prove the catalog is available.
Describe the actual state rather than claiming the containers are running
normally. Show an ordinary catalog request failing or timing out in the browser.

### Diagnose in Cascade

Open the demonstrated Container App in the **Cascade portal** and select
**Debug with SRE Agent**. Confirm that the investigation targets the correct app.
Present only the customer symptom, not the injected change or a suggested cause.

**Enter in CASCADE: SRE Agent conversation - not a terminal.**

```text
The catalog was working, but now requests fail or time out. Investigate this Container App, identify the root cause, and show the supporting evidence. Diagnose only; do not make changes yet.
```

Let the agent investigate. Ask it to connect the customer impact to concrete
logs and configuration evidence, distinguish symptoms from the root cause, and
propose the smallest corrective change. Do not feed it the script contents or
the known error number. If it cannot establish a supported diagnosis, say so;
do not present an unsupported guess as a successful investigation.

If diagnosis stalls beyond the rehearsed budget, restore the captured settings
using the command below and switch to a labeled recording. Do not leave the
incident active while waiting indefinitely for the agent.

**Say, after the evidence is established:** "Now we understand the cause.
Let's restore the known-good configuration and confirm customer recovery."

### Restore and show recovery

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
.\scripts\Introduce-Misterious-Regression.ps1 -Restore
```

This restores the captured settings, not a guessed fix. If the agent has already
restored the original settings with your explicit approval, use the same command
to reconcile the saved recovery state. Without a saved incident, an already-reset
environment produces a neutral no-op message; an unsafe missing-baseline case
still stops with an error.

Leave the same TRAFFIC process and WATCH running. Allow propagation and
in-flight failures to settle. Require **LAST 10s** to show successful responses
and zero errors, not an empty window. Historical totals and red rows can remain;
they are evidence of the incident, not proof it is still ongoing.

Once responses resume, confirm ordinary catalog browsing and database readiness.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
(Invoke-WebRequest "$($Config.resources.applicationUrl.TrimEnd('/'))/health/ready" -TimeoutSec 30).StatusCode
(Invoke-WebRequest "$($Config.resources.applicationUrl.TrimEnd('/'))/Store/Browse?genre=Rock" -TimeoutSec 30).StatusCode
az containerapp revision list @Azure --query '[].{revision:name,health:properties.healthState,traffic:properties.trafficWeight,replicas:properties.replicas}' -o table
```

Both HTTP checks must return 200. Require ready healthy-revision replicas in
WATCH, healthy 100% traffic, and candidate 0%. Recovery is not established by a
status label alone.

**Explain:** SRE Agent helped diagnose an external dependency failure using
evidence. Adding replicas or rolling traffic back cannot repair shared dependency
access. Remediation was reviewed and controlled, then verified with customer
requests; this is not automatic self-healing.

If recovery exceeds the rehearsed budget, stop synthetic traffic, use a clearly
labeled recording, and continue recovery offstage. Do not introduce the fault
again or weaken health checks to manufacture a successful result.

### Presenter-only preflight and technical notes — do not project

Before the talk, verify the app uses the public Azure SQL endpoint, public
network access is enabled, and no other server-level or database-level rule
allows the app's outbound addresses. Both databases and all revisions share
this SQL server; ensure there are no other consumers.

The regression script saves the baseline in the ignored
`config\sql-firewall-regression.local.json`, then removes only the
`0.0.0.0`–`0.0.0.0` Azure-services firewall allowance. Use the same checkout and
configuration for introduction and restoration. Before connecting to SQL, the
script automatically creates or updates `Admin Access` for the workstation's
detected public IPv4 address. It preserves `DeploymentClient` and all other
rules. `Admin Access` remains after restoration; a network change updates
its single allowed address on the next introduction or restoration. No config
edit or redeployment is needed. Verify firewall write permissions and rehearse
this at the venue; propagation can take up to five minutes. If SQL access
initially fails, wait and rerun the same command.
An existing `PresenterLaptop` rule is not renamed or deleted automatically.
After restoring any incident and verifying `Admin Access` works, remove the old
rule if it is no longer needed.
Do not delete the snapshot,
change other firewall rules, disable public network access, or deploy Bicep
during the incident; Bicep would recreate the allowance.

The script refreshes firewall caches in both configured databases after
introduction and restoration using the signed-in operator's Entra SQL token.
Rehearse workstation SQL access and administrator or `KILL DATABASE CONNECTION`
permission offstage; do not grant this permission to the app. Introduction
checks access/permissions before removing Azure-services rules. Restoration repairs the
firewall first and retains the snapshot if cache refresh fails. SQL sessions
are not killed, and app pooling/retry settings are unchanged.

Both revisions must already use `Pooling=True;Load Balance Timeout=30;` for both
databases, consistently across every scenario. Connections older than 30 seconds
are retired when returned to the pool, not interrupted mid-query. SQL firewall
cache refresh reduces propagation delay, but this is not a 30-second outage
guarantee.

Privately establish a genuine SQL firewall rejection in console logs, commonly
error **40615**, before attributing the incident to that cause. Application
readiness depends on both databases, and SQL initialization happens before the
web server starts. Replicas may become unready, activating, or restarting;
ingress may time out or return 503 without demo identity headers. These are not
the candidate's intentional, identified 503 responses.

Verify the Cascade entry point, agent permissions, log access, recovery command,
and measured propagation/recovery timing offstage. Console/system logs are
important if the application cannot complete startup. The initial agent request
is diagnosis-only; approve any proposed remediation explicitly.

## Finish and repeat

Restore the incident settings before ending the demo, including after an aborted
Scenario 3. The restore command is safe to repeat when already reset.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
.\scripts\Introduce-Misterious-Regression.ps1 -Restore
```

Before stopping either terminal, confirm catalog/readiness HTTP 200 and recent
successful traffic with zero recent errors, as in Scenario 3. Restoring settings
alone does not establish application recovery.

Stop requests with **Ctrl+C in TERMINAL 2: TRAFFIC** if still running.
Stop observation with **Ctrl+C in TERMINAL 3: WATCH**.

**Run in TERMINAL 2: TRAFFIC - PowerShell.**

```powershell
Remove-Item Env:\MUSICSTORE_DEMO_TOKEN -ErrorAction SilentlyContinue
```

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp ingress traffic set @Azure --revision-weight "$V1=100" "$V2=0" --output none
az containerapp revision list @Azure --query '[].{revision:name,health:properties.healthState,traffic:properties.trafficWeight,replicas:properties.replicas}' -o table
```

Before repeating, require healthy 100%, candidate 0%, stable healthy containers,
restored incident settings, successful catalog/readiness checks, no remaining
generators, and eventual return to the two-replica baseline. Reload the token in
TRAFFIC. Do not restart a revision merely to reset the incident.

Warm replicas still cost money. Ending the prepared demo environment is a
separate, deliberate deployment/reset operation, not part of this live runbook.
Keep recordings of scaling, rollback, and SRE diagnosis/recovery available before
presenting.
