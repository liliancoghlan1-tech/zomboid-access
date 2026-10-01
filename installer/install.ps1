# Zomboid Access installer. Run Install.bat (it runs this).
# 1. Checks Project Zomboid is closed and has been started at least once.
# 2. Copies the mod into %USERPROFILE%\Zomboid\mods\ZomboidAccess (replacing an older copy).
# 3. Turns the mod on in mods\default.txt, keeping any other mods you have on.
# 4. Opens the NVDA add-on, so NVDA asks you to install it.
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
    Say "Start Project Zomboid once, wait for the main menu, quit, then run Install again."
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

$addon = Join-Path $here "files\Zomboid Access.nvda-addon"
Say "Now NVDA will ask whether to install the Zomboid Access add-on. Choose Yes, then restart NVDA when it asks."
if (-not $env:ZA_TEST_NO_ADDON) { Start-Process -FilePath $addon }
Say "Done. Start Project Zomboid: the main menu should speak."
