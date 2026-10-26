# SPDX-License-Identifier: GPL-3.0-only
param([string]$Python = 'python', [string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($Root)
$pythonExe = (Get-Command $Python -ErrorAction Stop).Source
Push-Location $root
try {
    & $pythonExe -c 'import PyInstaller, tkinter'
    if ($LASTEXITCODE -ne 0) { throw 'Install requirements-build.txt with a CPython that includes tkinter.' }
    & $pythonExe scripts/build-plugins.py
    if ($LASTEXITCODE -ne 0) { throw 'Plugin build failed' }
    & $pythonExe toolbox/selfsoftware2/tools/build_exe.py
    if ($LASTEXITCODE -ne 0) { throw 'Specification generator build failed' }
    & ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'toolbox/make-jlc3d.ps1')))) -Python $pythonExe -Root (Join-Path $root 'toolbox')
    & $pythonExe scripts/collect-licenses.py
    if ($LASTEXITCODE -ne 0) { throw 'License collection failed' }
    & ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'toolbox/dist/build-setup.ps1')))) -BuildDirectory (Join-Path $root 'toolbox/dist')
    if ($LASTEXITCODE -ne 0) { throw 'Installer build failed' }
} finally { Pop-Location }
