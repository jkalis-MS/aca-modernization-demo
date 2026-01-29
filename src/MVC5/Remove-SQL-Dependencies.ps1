# PowerShell script to remove all SQL and EntityFramework dependencies
# This script should be run after closing Visual Studio

Write-Host "Removing SQL and EntityFramework dependencies..." -ForegroundColor Green

# Path to the project file
$projectFile = "MvcMusicStore\MvcMusicStore.csproj"
$packagesFile = "MvcMusicStore\packages.config"

# Check if project file exists
if (!(Test-Path $projectFile)) {
    Write-Host "Error: Project file not found at $projectFile" -ForegroundColor Red
    exit 1
}

Write-Host "Reading project file..." -ForegroundColor Yellow

# Load the project XML
[xml]$proj = Get-Content $projectFile

# Define namespaces
$ns = New-Object System.Xml.XmlNamespaceManager($proj.NameTable)
$ns.AddNamespace("ms", "http://schemas.microsoft.com/developer/msbuild/2003")

# Find and remove EntityFramework reference
$efReference = $proj.SelectSingleNode("//ms:Reference[contains(@Include, 'EntityFramework')]", $ns)
if ($efReference) {
    Write-Host "Removing EntityFramework reference..." -ForegroundColor Yellow
    $efReference.ParentNode.RemoveChild($efReference) | Out-Null
}

# Find and remove System.Data.Entity reference
$dataEntityReference = $proj.SelectSingleNode("//ms:Reference[@Include='System.Data.Entity']", $ns)
if ($dataEntityReference) {
    Write-Host "Removing System.Data.Entity reference..." -ForegroundColor Yellow
    $dataEntityReference.ParentNode.RemoveChild($dataEntityReference) | Out-Null
}

# Find and remove System.Web.Entity reference
$webEntityReference = $proj.SelectSingleNode("//ms:Reference[@Include='System.Web.Entity']", $ns)
if ($webEntityReference) {
    Write-Host "Removing System.Web.Entity reference..." -ForegroundColor Yellow
    $webEntityReference.ParentNode.RemoveChild($webEntityReference) | Out-Null
}

# Save the updated project file
$proj.Save((Resolve-Path $projectFile))
Write-Host "Project file updated successfully!" -ForegroundColor Green

# Update packages.config if it exists
if (Test-Path $packagesFile) {
    Write-Host "Reading packages.config..." -ForegroundColor Yellow
    [xml]$packages = Get-Content $packagesFile
    
    $efPackage = $packages.SelectSingleNode("//package[@id='EntityFramework']")
    if ($efPackage) {
        Write-Host "Removing EntityFramework from packages.config..." -ForegroundColor Yellow
        $efPackage.ParentNode.RemoveChild($efPackage) | Out-Null
        $packages.Save((Resolve-Path $packagesFile))
        Write-Host "packages.config updated successfully!" -ForegroundColor Green
    } else {
        Write-Host "EntityFramework package not found in packages.config" -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "SQL dependencies removed successfully!" -ForegroundColor Green
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "1. Delete the 'packages\EntityFramework*' folder if it exists" -ForegroundColor White
Write-Host "2. Open the solution in Visual Studio" -ForegroundColor White
Write-Host "3. Clean and rebuild the solution" -ForegroundColor White
Write-Host ""
