# Zomboid Access uninstaller. Run Uninstall.bat (it runs this).
# Removes the mod folder and its line in mods\default.txt, the speech bridge, and the bridge from Steam's launch
# options for Project Zomboid.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
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

. (Join-Path $here "steam.ps1")
$configs = Get-ZASteamConfigs
if ($configs.Count -gt 0 -and -not $env:ZA_TEST_STEAM_DIR -and (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
    Write-Host "Steam is running, so the speech bridge is still in Project Zomboid's launch options. Exit Steam and run Uninstall again, or remove it yourself: Project Zomboid, Properties, Launch Options."
} else {
    foreach ($cfg in $configs) {
        $r = Update-ZALaunchOptions $cfg {
            param($old)
            # Take out only our part: '"...ZomboidAccessBridge.exe" %command%' and anything after it stays.
            ($old -replace '^\s*"[^"]*ZomboidAccessBridge\.exe"\s*%command%\s*', '').Trim()
        }
        if ($r.Result -eq "changed") { Write-Host "Took the speech bridge out of Steam's launch options." }
    }
}
Get-Process -Name "ZomboidAccessBridge" -ErrorAction SilentlyContinue | Stop-Process -Force
$bridgeDir = Join-Path $env:LOCALAPPDATA "ZomboidAccess"
if (Test-Path $bridgeDir) { Remove-Item -Recurse -Force $bridgeDir; Write-Host "Removed the speech bridge." }
