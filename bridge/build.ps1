# Builds ZomboidAccessBridge.exe (one file, no console window) into installer\files.
# Needs Python 3.10 or later. Run from anywhere: powershell -ExecutionPolicy Bypass -File bridge\build.ps1
$ErrorActionPreference = "Stop"
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$venv = Join-Path $here ".venv"
$work = Join-Path $here "build"
$out = Join-Path (Split-Path -Parent $here) "installer\files"

if (-not (Test-Path $venv)) { py -3 -m venv $venv }
& "$venv\Scripts\python.exe" -m pip install -q -r (Join-Path $here "requirements.txt")
# prismatoid finds its native module in prism\_native at run time, which PyInstaller doesn't follow:
# put the module and prism.dll straight into the bundled prism package.
$native = Join-Path $venv "Lib\site-packages\prism\_native"
& "$venv\Scripts\pyinstaller.exe" --noconfirm --onefile --noconsole --name ZomboidAccessBridge `
    --collect-all prism --hidden-import _cffi_backend `
    --add-binary "$native\_prism_cffi.pyd;prism" --add-binary "$native\prism.dll;prism" --distpath $out --workpath $work --specpath $work `
    (Join-Path $here "zomboid_access_bridge.py")
Write-Host "Built $out\ZomboidAccessBridge.exe"
