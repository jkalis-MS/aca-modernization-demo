#requires -Version 7.0
[CmdletBinding()]
param(
    [uri]$ApplicationUrl,
    [string]$ConfigPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'config\azure.local.json')
)

$ErrorActionPreference = 'Stop'
if (!$PSBoundParameters.ContainsKey('ApplicationUrl')) {
    $config = & (Join-Path $PSScriptRoot 'Get-AzureLocalConfig.ps1') -ConfigPath $ConfigPath -RequiredSettings 'resources.applicationUrl'
    $ApplicationUrl = [uri]$config.resources.applicationUrl
}
if (!$ApplicationUrl -or $ApplicationUrl.Scheme -ne 'https') {
    throw 'Use the HTTPS application URL.'
}
$base = $ApplicationUrl.AbsoluteUri.TrimEnd('/')
$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
$checks = [System.Collections.Generic.List[string]]::new()

function Get-Page {
    param([string]$Path)
    Invoke-WebRequest "$base$Path" -WebSession $session -TimeoutSec 60
}

function Get-AntiforgeryToken {
    param([string]$Html)
    $inputTag = [regex]::Match($Html, '<input[^>]*name="__RequestVerificationToken"[^>]*>').Value
    $token = [regex]::Match($inputTag, 'value="([^"]+)"').Groups[1].Value
    if (!$token) {
        throw 'The form did not contain an antiforgery token.'
    }
    [System.Net.WebUtility]::HtmlDecode($token)
}

function Assert-Content {
    param([object]$Response, [string]$Pattern, [string]$Check)
    if ($Response.StatusCode -ne 200 -or $Response.Content -notmatch $Pattern) {
        throw "$Check failed (HTTP $($Response.StatusCode))."
    }
    $checks.Add($Check)
}

Assert-Content (Get-Page '/health/live') '^Healthy$' 'Liveness'
Assert-Content (Get-Page '/health/ready') '^Healthy$' 'Database readiness'
Assert-Content (Get-Page '/') 'Music Store' 'Home page'
Assert-Content (Get-Page '/Store') 'Rock' 'SQL-backed genre catalog'
$browse = Get-Page '/Store/Browse?genre=Rock'
Assert-Content $browse '/Store/Details/' 'SQL-backed album browsing'
$albumId = [regex]::Match($browse.Content, '/Store/Details/(\d+)').Groups[1].Value
Assert-Content (Get-Page "/Store/Details/$albumId") 'Add to cart' 'Album details'

# This creates a synthetic account and order in the demo, not real customer data.
$user = "smoke-$([Guid]::NewGuid().ToString('N'))@example.com"
$password = "Demo$([Guid]::NewGuid().ToString('N'))!1"
$register = Get-Page '/Account/Register'
$registered = Invoke-WebRequest "$base/Account/Register" -WebSession $session -Method Post -Body @{
    UserName = $user
    Password = $password
    ConfirmPassword = $password
    __RequestVerificationToken = Get-AntiforgeryToken $register.Content
} -TimeoutSec 60
Assert-Content $registered ([regex]::Escape($user)) 'Account registration'

$logout = Invoke-WebRequest "$base/Account/LogOff" -WebSession $session -Method Post -Body @{
    __RequestVerificationToken = Get-AntiforgeryToken $registered.Content
} -TimeoutSec 60
Assert-Content $logout '/Account/Login' 'Sign out'
$login = Get-Page '/Account/Login'
$loggedIn = Invoke-WebRequest "$base/Account/Login" -WebSession $session -Method Post -Body @{
    UserName = $user
    Password = $password
    RememberMe = 'false'
    __RequestVerificationToken = Get-AntiforgeryToken $login.Content
} -TimeoutSec 60
Assert-Content $loggedIn ([regex]::Escape($user)) 'Sign in'

Assert-Content (Get-Page "/ShoppingCart/AddToCart/$albumId") 'item-count-' 'Add to cart'
$checkout = Get-Page '/Checkout/AddressAndPayment'
$order = Invoke-WebRequest "$base/Checkout/AddressAndPayment" -WebSession $session -Method Post -Body @{
    FirstName = 'Demo'
    LastName = 'Validation'
    Address = '123 Demo Street'
    City = 'Seattle'
    State = 'WA'
    PostalCode = '98101'
    Country = 'USA'
    Phone = '202-555-0100'
    Email = $user
    PromoCode = 'FREE'
    __RequestVerificationToken = Get-AntiforgeryToken $checkout.Content
} -TimeoutSec 60
Assert-Content $order 'Thanks for your order! Your order number is: \d+' 'Checkout and order persistence'

$null = Invoke-WebRequest "$base/Account/LogOff" -WebSession $session -Method Post -Body @{
    __RequestVerificationToken = Get-AntiforgeryToken $order.Content
} -TimeoutSec 60
$password = $null
[pscustomobject]@{
    ApplicationUrl = $base
    Passed = $checks.Count
    Checks = $checks.ToArray()
} | ConvertTo-Json -Depth 3
