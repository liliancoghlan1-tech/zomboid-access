# Builds ZomboidAccessSetup.exe into installer\files with the C# compiler that comes with Windows
# (.NET Framework 4.x, on every Windows 10 and 11): nothing to install to build it or to run it.
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$out = Join-Path (Split-Path -Parent $here) "files"
$fw = Join-Path $env:WINDIR "Microsoft.NET\Framework64\v4.0.30319"
$csc = Join-Path $fw "csc.exe"
if (-not (Test-Path $csc)) { throw "No C# compiler at $csc (.NET Framework 4 is part of Windows 10 and 11)." }
New-Item -ItemType Directory -Force $out | Out-Null
# The setup's version is the mod's (mod.info): an older setup hands an update over to a newer one by comparing them.
$info = Join-Path (Split-Path -Parent (Split-Path -Parent $here)) "mod\ZomboidAccess\42\mod.info"
$modversion = ((Get-Content $info | Where-Object { $_ -like "modversion=*" }) -replace "modversion=", "").Trim()
$numbers = @([regex]::Matches($modversion, "\d+") | ForEach-Object { $_.Value } | Select-Object -First 4)
while ($numbers.Count -lt 4) { $numbers += "0" }
$version = Join-Path ([System.IO.Path]::GetTempPath()) "ZomboidAccessSetup-version.cs"
Set-Content -Encoding ascii $version "[assembly: System.Reflection.AssemblyVersion(""$($numbers -join '.')"")]"
& $csc /nologo /target:winexe /optimize+ /platform:anycpu "/out:$out\ZomboidAccessSetup.exe" `
    /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll `
    "/r:$fw\System.Web.Extensions.dll" "/r:$fw\System.IO.Compression.dll" "/r:$fw\System.IO.Compression.FileSystem.dll" `
    (Join-Path $here "ZomboidAccessSetup.cs") $version
$built = $LASTEXITCODE
Remove-Item -Force $version
if ($built -ne 0) { throw "The setup didn't compile." }
Write-Host "Built $out\ZomboidAccessSetup.exe, version $($numbers -join '.')"
