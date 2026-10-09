# Zomboid Access installer. Run Install.bat (it runs this).
# 1. Checks Project Zomboid is closed and has been started at least once.
# 2. Copies the mod into %USERPROFILE%\Zomboid\mods\ZomboidAccess (replacing an older copy).
# 3. Turns the mod on in mods\default.txt, keeping any other mods you have on.
# 4. Copies the speech bridge to %LOCALAPPDATA%\ZomboidAccess and sets Steam's launch option for Project Zomboid,
#    so Steam starts the bridge, the bridge starts the game, and it speaks through whatever screen reader is running.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$zomboid = Join-Path $env:USERPROFILE "Zomboid"
$mods = Join-Path $zomboid "mods"

function Say($text) { Write-Host $text }

if (Get-Process -Name "ProjectZomboid64" -ErrorAction SilentlyContinue) {
    Say "Project Zomboid is running. Quit the game, then run Install again."
    exit 1
}
# Build 42 empties the mod list on its very first start, so the game must have been started once before.
if (-not (Test-Path (Join-Path $mods "reset-mods-42_00.txt"))) {
    Say "Start Project Zomboid once, wait about a minute, close it with Alt F4, then run Install again. The first time, it stops on a Terms of Service screen that is silent until the mod is installed: closing it there is fine."
    Say "(The game clears its mod list the first time it starts, so installing before that would be undone.)"
    exit 1
}

$src = Join-Path $here "files\mods\ZomboidAccess"
$dst = Join-Path $mods "ZomboidAccess"
if (Test-Path $dst) { Remove-Item -Recurse -Force $dst }
Copy-Item -Recurse $src $dst
Say "Copied the mod to $dst."

# Turn it on: add "mod = ZomboidAccess," inside the mods block of default.txt.
$list = Join-Path $mods "default.txt"
if (Test-Path $list) {
    $lines = Get-Content -LiteralPath $list -Encoding UTF8
    if ($lines -match '^\s*mod\s*=\s*\\?ZomboidAccess\s*,') {
        Say "The mod was already on."
    } else {
        $out = New-Object System.Collections.Generic.List[string]
        $inMods = $false; $added = $false
        foreach ($l in $lines) {
            $out.Add($l)
            if ($l -match '^\s*mods\s*$') { $inMods = $true }
            elseif ($inMods -and -not $added -and $l -match '^\s*\{\s*$') { $out.Add("    mod = ZomboidAccess,"); $added = $true }
        }
        if (-not $added) {
            $out.Add(""); $out.Add("mods"); $out.Add("{"); $out.Add("    mod = ZomboidAccess,"); $out.Add("}")
        }
        Copy-Item -LiteralPath $list -Destination ($list + ".before-zomboid-access") -Force
        [System.IO.File]::WriteAllLines($list, $out, (New-Object System.Text.UTF8Encoding($false)))
        Say "Turned the mod on (your old list is saved as default.txt.before-zomboid-access)."
    }
} else {
    $text = "VERSION = 1,`n`nmods`n{`n    mod = ZomboidAccess,`n}`n`nmaps`n{`n}`n"
    [System.IO.File]::WriteAllText($list, $text, (New-Object System.Text.UTF8Encoding($false)))
    Say "Turned the mod on."
}

# The speech bridge: it reads what the mod writes and speaks it through the screen reader (Prism).
. (Join-Path $here "steam.ps1")
$bridgeDir = Join-Path $env:LOCALAPPDATA "ZomboidAccess"
$bridge = Join-Path $bridgeDir "ZomboidAccessBridge.exe"
Get-Process -Name "ZomboidAccessBridge" -ErrorAction SilentlyContinue | Stop-Process -Force
New-Item -ItemType Directory -Force $bridgeDir | Out-Null
Copy-Item -LiteralPath (Join-Path $here "files\ZomboidAccessBridge.exe") -Destination $bridge -Force
Say "Copied the speech bridge to $bridge."

$option = Get-ZABridgeOption $bridge
$manual = "In Steam, open Project Zomboid's Properties, and in Launch Options type: $option"
$configs = Get-ZASteamConfigs
# Reading (a change that changes nothing) is safe while Steam runs: only writing has to wait for it to close.
$alreadySet = @($configs | Where-Object { (Update-ZALaunchOptions $_ { param($old) $old }).Value -like ('"' + $bridge + '"*') }).Count -gt 0
if ($configs.Count -eq 0) {
    Say "Couldn't find Steam's settings. $manual"
} elseif ($alreadySet) {
    Say "Steam already starts the speech bridge with Project Zomboid."
} elseif (-not $env:ZA_TEST_STEAM_DIR -and (Get-Process -Name "steam" -ErrorAction SilentlyContinue)) {
    Say "Steam is running, so its launch options can't be changed now. Exit Steam (Steam menu, Exit), then run Install again."
    Say "Or do it yourself: $manual"
} else {
    foreach ($cfg in $configs) {
        # Keep the player's own options (like -debug) after ours. Options that already wrap the game in another
        # program (%command%) can't be combined automatically.
        $r = Update-ZALaunchOptions $cfg {
            param($old)
            $old = $old -replace '^\s*"[^"]*ZomboidAccessBridge\.exe"\s*%command%\s*', ''
            if ($old -match '%command%') { return $old }
            return ("$option " + $old).Trim()
        }
        if ($r.Result -eq "no-game") { continue }
        if ($r.Value -like "*ZomboidAccessBridge.exe*") {
            Say "Steam starts the speech bridge with Project Zomboid (launch options: $($r.Value))."
        } else {
            Say "Project Zomboid already has launch options that run another program, so they were left alone. $manual"
        }
    }
}

# The NVDA add-on that came before the bridge would say everything a second time.
if (Test-Path (Join-Path $env:APPDATA "nvda\addons\zomboidAccess")) {
    Say "The old Zomboid Access NVDA add-on is still installed. Remove it, or everything is said twice: NVDA menu, Tools, Add-on store, Installed add-ons, Zomboid Access, Remove."
}

if (-not $env:ZA_TEST_NO_BRIDGE) { Start-Process -FilePath $bridge -ArgumentList "--test" -Wait }
Say "Done. You should have just heard your screen reader say which one Zomboid Access speaks through. Start Project Zomboid from Steam: it says Starting Project Zomboid, and then the main menu speaks."
