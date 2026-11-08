param(
	[string]$BaseUrl = 'http://127.0.0.1:5087',
	[string]$AdminUserName,
	[string]$AdminPassword
)
$ErrorActionPreference = 'Stop'
Import-Module Microsoft.PowerShell.Utility
$BaseUrl = $BaseUrl.TrimEnd('/')

function Assert-True($Condition, [string]$Message) {
	if (-not $Condition) { throw $Message }
	Write-Host "PASS: $Message"
}

function Get-Page([string]$Path, $Session) {
	Invoke-WebRequest -Uri "$BaseUrl$Path" -WebSession $Session
}

function Submit-Form([string]$Path, [hashtable]$Values, $Session, [string]$TokenPath = $Path) {
	$page = Get-Page $TokenPath $Session
	$token = [regex]::Match($page.Content, 'name="__RequestVerificationToken"[^>]*value="([^"]+)"')
	if (-not $token.Success) { throw "Missing antiforgery token on $TokenPath" }
	$Values['__RequestVerificationToken'] = [System.Net.WebUtility]::HtmlDecode($token.Groups[1].Value)
	Invoke-WebRequest -Uri "$BaseUrl$Path" -Method Post -Body $Values -WebSession $Session
}

$guest = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
foreach ($path in @('/', '/Store', '/Store/Browse?genre=Rock', '/Store/Details/1', '/Images/AlbumArt/album-1.png')) {
	$page = Get-Page $path $guest
	Assert-True ($page.StatusCode -eq 200) "SQL-free page $path responds successfully"
}

$null = Get-Page '/ShoppingCart/AddToCart/1' $guest
$cart = Get-Page '/ShoppingCart' $guest
Assert-True ($cart.Content -match 'Thunder Road') 'Anonymous cart contains the seeded album'

$userName = "smoke-$([guid]::NewGuid().ToString('N'))@example.com"
$password = 'SmokePassword123!'
$registered = Submit-Form '/Account/Register' @{ UserName = $userName; Password = $password; ConfirmPassword = $password } $guest
Assert-True ($registered.Content -match [regex]::Escape($userName)) 'Registration signs in the new in-memory account'
$cart = Get-Page '/ShoppingCart' $guest
Assert-True ($cart.Content -match 'Thunder Road') 'Registration preserves the anonymous cart'

$order = Submit-Form '/Checkout/AddressAndPayment' @{
	FirstName = 'Smoke'; LastName = 'Test'; Address = '123 Test Street'; City = 'Test City'
	State = 'WA'; PostalCode = '98052'; Country = 'USA'; Phone = '555-555-0100'
	Email = $userName; PromoCode = 'FREE'
} $guest
$orderPath = $order.BaseResponse.RequestMessage.RequestUri.AbsolutePath
Assert-True ($orderPath -match '^/Checkout/Complete/\d+$') 'Checkout creates an order without SQL'
$cart = Get-Page '/ShoppingCart' $guest
Assert-True ($cart.Content -notmatch 'Thunder Road') 'Checkout empties the account cart'

$other = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
$otherName = "other-$([guid]::NewGuid().ToString('N'))@example.com"
$null = Submit-Form '/Account/Register' @{ UserName = $otherName; Password = $password; ConfirmPassword = $password } $other
$denied = Get-Page $orderPath $other
Assert-True ($denied.Content -match 'Error') 'Another account cannot view the completed order'

$null = Get-Page '/ShoppingCart/AddToCart/1' $guest
$null = Submit-Form '/Account/LogOff' @{} $guest '/Account/Manage'
$cart = Get-Page '/ShoppingCart' $guest
Assert-True ($cart.Content -notmatch 'Thunder Road') 'Logout isolates the authenticated cart from anonymous sessions'
$loggedIn = Submit-Form '/Account/Login' @{ UserName = $userName.ToUpperInvariant(); Password = $password; RememberMe = 'false' } $guest
Assert-True ($loggedIn.Content -match [regex]::Escape($userName)) 'In-memory account login is case-insensitive'
$cart = Get-Page '/ShoppingCart' $guest
Assert-True ($cart.Content -match 'Thunder Road') 'Login restores the canonical account cart'

if ($AdminUserName -and $AdminPassword) {
	$admin = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
	$null = Submit-Form '/Account/Login' @{ UserName = $AdminUserName; Password = $AdminPassword } $admin
	$managed = Get-Page '/StoreManager' $admin
	Assert-True ($managed.Content -match 'Thunder Road') 'Administrator can access store management'
	$title = "Smoke $([guid]::NewGuid().ToString('N').Substring(0, 8))"
	$created = Submit-Form '/StoreManager/Create' @{
		Title = $title; GenreId = '1'; ArtistId = '1'; Price = '4.99'; AlbumArtUrl = '/Images/AlbumArt/album-1.png'
	} $admin
	Assert-True ($created.Content -match [regex]::Escape($title)) 'Administrator can create an in-memory album'
	$ids = [regex]::Matches($created.Content, '/StoreManager/Edit/(\d+)') | ForEach-Object { [int]$_.Groups[1].Value }
	$id = ($ids | Measure-Object -Maximum).Maximum
	Assert-True ($id -gt 100) 'Created album has a generated ID'
	$edited = Submit-Form "/StoreManager/Edit/$id" @{
		AlbumId = "$id"; Title = "$title Edited"; GenreId = '2'; ArtistId = '1'; Price = '6.99'; AlbumArtUrl = '/Images/AlbumArt/album-1.png'
	} $admin
	Assert-True ($edited.Content -match [regex]::Escape("$title Edited")) 'Administrator can update the in-memory album'
	$deleted = Submit-Form "/StoreManager/Delete/$id" @{} $admin
	Assert-True ($deleted.Content -notmatch [regex]::Escape($title)) 'Administrator can delete the in-memory album'
	$blocked = Submit-Form '/StoreManager/Delete/1' @{} $admin
	Assert-True ($blocked.Content -match 'existing orders cannot be deleted') 'Albums with existing orders retain a visible deletion error'
}

Write-Host 'HTTP smoke checks passed.'
