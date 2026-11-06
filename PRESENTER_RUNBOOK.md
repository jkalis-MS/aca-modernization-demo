# Music Store: ACA operations presenter runbook

Use the existing web application to show HTTP scaling, traffic rollback, and
recovery after one application process crashes. Allow about 16 minutes.

**Rehearsal requirement:** verify scale-out, candidate exposure, and rollback in
one uninterrupted traffic run in your own environment. The console-based crash
procedure must also pass rehearsal before it is used live.

**Deployment prerequisite for the unified traffic command:** rebuild and stage
both healthy and candidate images from code supporting the combined `demo`
operation when setting up another deployment. Older images support only separate
operations; changing PowerShell does not update those images. Update your ignored
local revision references after staging both images.
After a rollout, reload CONTROL's `$Config`, `$Healthy`, and `$Candidate` variables.
WATCH automatically discovers new active revisions without restarting.

## Terminals and prerequisites

Open **three PowerShell 7.4+ terminals** in the repository root. Keep their names
visible in terminal tabs or window titles:

| Terminal | Name | Colors | Purpose |
|---|---|---|---|
| 1 | CONTROL | White on dark charcoal (`#202020`) | Azure inspection, traffic changes, and one targeted console session |
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
exit-code checks. Crash-target safety checks remain in Scenario 3.

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
URL, subscription, resource group, app name, healthy/candidate revisions, baked
candidate version, and versioned Key Vault token reference. Never show the token.

### Terminal 1 — CONTROL: initialize

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
$ErrorActionPreference = 'Stop'; $PSNativeCommandUseErrorActionPreference = $true
Set-Location -LiteralPath '<repository-root>'
$Host.UI.RawUI.WindowTitle = '1 - CONTROL'; $Host.UI.RawUI.BackgroundColor = 'Black'; $Host.UI.RawUI.ForegroundColor = 'White'; Write-Host "`e]11;#202020`a`e[48;2;32;32;32m`e[2J`e[H" -NoNewline
function global:prompt { 'CONTROL> ' }
$Config = .\scripts\Get-AzureLocalConfig.ps1 -RequiredSettings deployment.tenantId,deployment.resourceGroupName,resources.containerAppName,resources.applicationUrl,demo.healthyRevision,demo.candidateRevision
$Healthy = $Config.demo.healthyRevision
$Candidate = $Config.demo.candidateRevision
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
az containerapp revision show @Azure --revision $Healthy --query properties.template.scale -o json
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
az containerapp ingress traffic set @Azure --revision-weight "$Healthy=100" "$Candidate=0" --output none
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
Authentication/setup failures and the high-error-rate safety stop still stop
traffic.

Cancellation of in-flight requests when you stop traffic is expected and is not
counted as an error. Any unexpected failure still fails the run; read the
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
$CandidateHost = az containerapp revision show @Azure --revision $Candidate --query properties.fqdn -o tsv
(Invoke-WebRequest "https://$CandidateHost/health/ready" -TimeoutSec 15).StatusCode
(Invoke-WebRequest "https://$CandidateHost/Store/Browse?genre=Rock" -TimeoutSec 15).StatusCode
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
az containerapp ingress traffic set @Azure --revision-weight "$Healthy=90" "$Candidate=10" --output none
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
az containerapp ingress traffic set @Azure --revision-weight "$Healthy=100" "$Candidate=0" --output none
az containerapp show @Azure --query properties.configuration.ingress.traffic -o table
```

Leave the same TRAFFIC process running. After routing propagation, in-flight
requests drain, and old failures age out of the 10-second window, expect
**LAST 10s** to show successful responses and zero errors. The
traffic status returns to green. Historical error totals do not reset or decrease;
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

## Scenario 3 — Crash one application process (about 5 minutes)

**Warning:** deliberately disruptive. Rehearse exact console behavior first.
No live builds, revision restart, redeployment, traffic changes, or public crash
endpoint are part of this fault.

Require healthy 100% traffic, candidate 0%, and at least two ready replicas of
the healthy revision. Recheck traffic before continuing.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp show @Azure --query properties.configuration.ingress.traffic -o table
```

**Run in TERMINAL 2: TRAFFIC - PowerShell.**

```powershell
.\scripts\Invoke-DemoTraffic.ps1 -Scenario Recovery
```

Select one exact ready container. Record its ID/restart count before opening
the console. Do not let the CLI select the latest revision or a random replica.

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
$Replicas = @(az containerapp replica list @Azure --revision $Healthy -o json | ConvertFrom-Json)
$Ready = @($Replicas | Where-Object { $_.properties.containers | Where-Object { $_.name -eq 'web' -and $_.ready } })
if ($Ready.Count -lt 2) { throw 'Need at least two ready replicas. Do not crash.' }
$Victim = $Ready[0].name
Write-Host "Selected replica: $Victim"
$Ready[0].properties.containers | Select-Object name, containerId, restartCount
az containerapp exec @Azure --revision $Healthy --replica $Victim --container web --command /bin/bash
```

**TERMINAL 1 is now a Linux container shell, not PowerShell.**
Verify PID 1 and capture its process start token. The check refuses unexpected
processes and signal configurations.

**Run in TERMINAL 1: CONTROL - Bash INSIDE the selected container.**

```bash
# TERMINAL 1: CONTROL | INSIDE THE SELECTED CONTAINER | Bash, not PowerShell
cmd=$(tr '\000' ' ' < /proc/1/cmdline)
if [ "$cmd" != 'dotnet MvcMusicStore.dll ' ]; then
    echo "Unexpected PID 1; refusing."
    exit 1
fi
mask=$(awk '/^SigCgt:/ {print $2}' /proc/1/status)
if [ -z "$mask" ] || (( (16#$mask & 32) == 0 )); then
    echo "No SIGABRT handler; refusing."
    exit 1
fi
start=$(awk '{print $22}' /proc/1/stat)
printf 'Target: %s\nProcess start token: %s\n' "$cmd" "$start"
```

Confirm you are in the selected container. Send the fault **once**:

**Run in TERMINAL 1: CONTROL - Bash INSIDE the selected container.**

```bash
# TERMINAL 1: CONTROL | INSIDE THE SELECTED CONTAINER | Bash | ONE SHOT
if [ -z "$start" ] || [ "$start" != "$(awk '{print $22}' /proc/1/stat)" ]; then
    echo "Process identity changed; refusing."
    exit 1
fi
kill -ABRT 1
```

The console should disconnect. **Never retry after a disconnect or ambiguous
result.** Observe evidence instead. SIGABRT is an ungraceful fault; PID 1 has
special Linux signal rules, so an in-container `kill -9 1` is not substituted.
If the command fails or the process remains alive, stop the fault demonstration.

**Point to TRAFFIC:** the survivor continues responding; failures/timeouts remain
visible. A new process identity should eventually serve requests.

**Point to WATCH:** restart count or container replacement evidence, readiness,
and return to service. The replica name may remain unchanged. The traffic
identity table is cumulative, so old processes remain listed.

**Explain:** runtime process-exit detection causes recovery. Readiness controls
return to traffic; this is not a liveness-triggered hung-process demonstration.
In-flight requests may fail. This does not prove zero downtime or zone/region
resilience. No application retries are configured by the generator.

After the console closes, CONTROL is back in PowerShell:

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp replica list @Azure --revision $Healthy --query '[].{replica:name,containers:properties.containers[].{name:name,ready:ready,restarts:restartCount,containerId:containerId}}' -o json
```

Require at least two ready replicas and successful responses from a new process.
Use a 180-second rehearsal recovery budget; if recovery is not established, stop
the demo and show a labeled recording. Do not crash another container.

## Finish and repeat

Stop requests with **Ctrl+C in TERMINAL 2: TRAFFIC** if still running.
Stop observation with **Ctrl+C in TERMINAL 3: WATCH**.

**Run in TERMINAL 2: TRAFFIC - PowerShell.**

```powershell
Remove-Item Env:\MUSICSTORE_DEMO_TOKEN -ErrorAction SilentlyContinue
```

**Run in TERMINAL 1: CONTROL - PowerShell.**

```powershell
az containerapp ingress traffic set @Azure --revision-weight "$Healthy=100" "$Candidate=0" --output none
az containerapp revision list @Azure --query '[].{revision:name,health:properties.healthState,traffic:properties.trafficWeight,replicas:properties.replicas}' -o table
```

Before repeating, require healthy 100%, candidate 0%, stable healthy containers,
no remaining generators, and eventual return to the two-replica baseline. Reload
the token in TRAFFIC. Do not restart a revision to reset the recovery demo.

Warm replicas still cost money. Ending the prepared demo environment is a
separate, deliberate deployment/reset operation, not part of this live runbook.
Keep recordings of scaling, rollback, and recovery available before presenting.
