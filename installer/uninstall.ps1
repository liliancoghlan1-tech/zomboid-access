# Zomboid Access uninstaller. Run Uninstall.bat (it runs this).
# Removes the mod folder and its line in mods\default.txt. The NVDA add-on is removed in NVDA itself:
# NVDA menu, Tools, Add-on store, Installed add-ons, Zomboid Access, Remove.
$ErrorActionPreference = "Stop"
$mods = Join-Path (Join-Path $env:USERPROFILE "Zomboid") "mods"
if (Get-Process -Name "ProjectZomboid64" -ErrorAction SilentlyContinue) {
    Write-Host "Project Zomboid is running. Quit the game, then run Uninstall again."
    exit 1
}
$dst = Join-Path $mods "ZomboidAccess"
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst; Write-Host "Removed the mod folder." }
$list = Join-Path $mods "default.txt"
if (Test-Path $list) {
    $lines = Get-Content -LiteralPath $list -Encoding UTF8 | Where-Object { $_ -notmatch '^\s*mod\s*=\s*\\?ZomboidAccess\s*,' }
    [System.IO.File]::WriteAllLines($list, [string[]]$lines, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "Turned the mod off."
}
Write-Host "To remove the NVDA add-on: NVDA menu, Tools, Add-on store, Installed add-ons, Zomboid Access, Remove."
