# Zomboid Access: the Steam launch option that starts the speech bridge with the game.
# Steam keeps it in userdata\<account>\config\localconfig.vdf, at
# UserLocalConfigStore > Software > Valve > Steam > apps > 108600 > LaunchOptions.
# Steam rewrites that file when it exits, so it must be closed while we change it.

$ZA_AppId = "108600"

function Get-ZASteamDir {
    if ($env:ZA_TEST_STEAM_DIR) { return $env:ZA_TEST_STEAM_DIR }
    try { return (Get-ItemProperty -Path "HKCU:\Software\Valve\Steam" -ErrorAction Stop).SteamPath } catch { return $null }
}

function Get-ZASteamConfigs {
    $steam = Get-ZASteamDir
    if (-not $steam -or -not (Test-Path (Join-Path $steam "userdata"))) { return @() }
    return @(Get-ChildItem (Join-Path $steam "userdata") -Directory |
        ForEach-Object { Join-Path $_.FullName "config\localconfig.vdf" } |
        Where-Object { Test-Path -LiteralPath $_ })
}

# The block that is the direct child $key of the block whose contents run from $from to $to.
# Returns @(index of "{", index of "}") or $null.
function Find-ZAVdfChild([string]$text, [int]$from, [int]$to, [string]$key) {
    $depth = 0; $i = $from; $last = $null
    while ($i -lt $to) {
        $c = $text[$i]
        if ($c -eq '"') {
            $j = $i + 1
            while ($j -lt $to -and $text[$j] -ne '"') { if ($text[$j] -eq '\') { $j++ }; $j++ }
            if ($depth -eq 0) { $last = $text.Substring($i + 1, $j - $i - 1) }
            $i = $j + 1; continue
        }
        if ($c -eq '{') {
            if ($depth -eq 0 -and $last -eq $key) {
                $d = 0
                for ($k = $i; $k -lt $to; $k++) {
                    if ($text[$k] -eq '"') { $k++; while ($text[$k] -ne '"') { if ($text[$k] -eq '\') { $k++ }; $k++ } }
                    elseif ($text[$k] -eq '{') { $d++ }
                    elseif ($text[$k] -eq '}') { $d--; if ($d -eq 0) { return @($i, $k) } }
                }
                return $null
            }
            $depth++; $last = $null
        } elseif ($c -eq '}') { $depth--; $last = $null }
        $i++
    }
    return $null
}

function Find-ZAAppBlock([string]$text) {
    $range = @(-1, $text.Length)
    foreach ($key in @("UserLocalConfigStore", "Software", "Valve", "Steam", "apps", $ZA_AppId)) {
        $range = Find-ZAVdfChild $text ($range[0] + 1) $range[1] $key
        if (-not $range) { return $null }
    }
    return $range
}

function ConvertTo-ZAVdf([string]$s) { return $s.Replace('\', '\\').Replace('"', '\"') }
function ConvertFrom-ZAVdf([string]$s) { return [regex]::Replace($s, '\\(.)', '$1') }

# Calls $change with the current launch options (text, "" if none) and writes back what it returns.
# Returns @{ Result = "changed", "same" or "no-game" (that Steam account has never started Project Zomboid);
# Value = the launch options now }.
function Update-ZALaunchOptions([string]$path, [scriptblock]$change) {
    $text = [IO.File]::ReadAllText($path)
    $block = Find-ZAAppBlock $text
    if (-not $block) { return @{ Result = "no-game"; Value = "" } }
    $open = $block[0]; $close = $block[1]
    $inner = $text.Substring($open, $close - $open)
    $m = [regex]::Match($inner, '"LaunchOptions"(\s*)"((?:[^"\\]|\\.)*)"')
    $old = if ($m.Success) { ConvertFrom-ZAVdf $m.Groups[2].Value } else { "" }
    $new = & $change $old
    if ($new -eq $old) { return @{ Result = "same"; Value = $old } }
    $value = '"' + (ConvertTo-ZAVdf $new) + '"'
    if ($m.Success) {
        $start = $open + $m.Groups[2].Index - 1
        $text = $text.Substring(0, $start) + $value + $text.Substring($start + $m.Groups[2].Length + 2)
    } else {
        $lineStart = $text.LastIndexOf("`n", $open) + 1
        $indent = ([regex]::Match($text.Substring($lineStart, $open - $lineStart), '^\t*')).Value + "`t"
        $text = $text.Substring(0, $open + 1) + "`n" + $indent + '"LaunchOptions"' + "`t`t" + $value + $text.Substring($open + 1)
    }
    Copy-Item -LiteralPath $path -Destination ($path + ".before-zomboid-access") -Force
    [IO.File]::WriteAllText($path, $text, (New-Object System.Text.UTF8Encoding($false)))
    return @{ Result = "changed"; Value = $new }
}

function Get-ZABridgeOption([string]$exe) { return '"' + $exe + '" %command%' }
