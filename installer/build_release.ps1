# Builds a release: dist\Zomboid-Access-<version>.zip, the file to attach to the GitHub release
# (Zomboid Access Setup finds the newest release on GitHub and downloads its .zip).
#   Zomboid-Access\ZomboidAccessSetup.exe    install, update, reinstall, uninstall
#   Zomboid-Access\README.txt, LICENSE
#   Zomboid-Access\files\mods\ZomboidAccess   the mod
#   Zomboid-Access\files\ZomboidAccessBridge  the speech bridge
# The version comes from mod\ZomboidAccess\42\mod.info; tag the release v<version>.
# Needs Python 3.10 or later for the bridge (see bridge\build.ps1).
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$version = (Get-Content (Join-Path $root "mod\ZomboidAccess\42\mod.info") | Where-Object { $_ -like "modversion=*" }) -replace "modversion=", ""

& (Join-Path $root "bridge\build.ps1")
& (Join-Path $here "setup\build.ps1")

$dist = Join-Path $root "dist"
$stage = Join-Path $dist "Zomboid-Access"
if (Test-Path $stage) { Remove-Item -Recurse -Force $stage }
New-Item -ItemType Directory -Force (Join-Path $stage "files\mods") | Out-Null
Copy-Item (Join-Path $here "files\ZomboidAccessSetup.exe") $stage
Copy-Item (Join-Path $root "README.md") (Join-Path $stage "README.txt")
Copy-Item (Join-Path $root "LICENSE") $stage
Copy-Item -Recurse (Join-Path $root "mod\ZomboidAccess") (Join-Path $stage "files\mods\ZomboidAccess")
Copy-Item -Recurse (Join-Path $here "files\ZomboidAccessBridge") (Join-Path $stage "files\ZomboidAccessBridge")
# never ship what a test run of the bridge left next to it
Get-ChildItem (Join-Path $stage "files\ZomboidAccessBridge") -Include "voices.json", "bridge.log" -Recurse | Remove-Item -Force

$zip = Join-Path $dist "Zomboid-Access-$version.zip"
if (Test-Path $zip) { Remove-Item -Force $zip }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($stage, $zip, [System.IO.Compression.CompressionLevel]::Optimal, $true)
Write-Host "Built $zip"
