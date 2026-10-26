# SPDX-License-Identifier: GPL-3.0-only
param([string]$Python = 'python', [string]$Tclsh = '', [string]$Root = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($Root)
$pythonExe = (Get-Command $Python -ErrorAction Stop).Source
Push-Location $root
try {
    & $pythonExe -m compileall -q scripts toolbox/src toolbox/selfsoftware2/app
    if ($LASTEXITCODE -ne 0) { throw 'Python syntax check failed' }
    & $pythonExe scripts/test-specgen.py
    if ($LASTEXITCODE -ne 0) { throw 'Specification generator smoke test failed' }
    $specgen = Join-Path $root 'toolbox/selfsoftware2/dist/元器件规格描述生成器.exe'
    if (Test-Path -LiteralPath $specgen) {
        & $pythonExe scripts/test-specgen.py --executable $specgen
        if ($LASTEXITCODE -ne 0) { throw 'Packaged specification generator smoke test failed' }
    }
    if (-not $Tclsh) {
        $command = Get-Command tclsh -ErrorAction SilentlyContinue
        if ($command) { $Tclsh = $command.Source }
    }
    if (-not $Tclsh) {
        Write-Host 'SKIP Tcl tests: pass -Tclsh pointing to Tcl 8.6 with Tcllib/json.'
        return
    }
    $env:TCLSH = $Tclsh
    $suites = @(
        'toolbox/bomtool/tests.tcl', 'toolbox/bomtool/capture_tests.tcl',
        'toolbox/bomtool/menu_tests.tcl', 'toolbox/drc/tests.tcl',
        'toolbox/drc/netlist-tests.tcl', 'toolbox/drc/lifecycle-tests.tcl',
        'toolbox/drc/save-tests.tcl', 'toolbox/drc/usability-tests.tcl',
        'toolbox/drc/ui-tests.tcl', 'toolbox/textaffix/tests.tcl',
        'toolbox/textaffix/capture-tests.tcl'
    )
    foreach ($suite in $suites) {
        & $Tclsh scripts/run-tcl-test.tcl $suite
        if ($LASTEXITCODE -ne 0) { throw "Tcl test failed: $suite" }
    }
    & $pythonExe toolbox/bomtool/workbook_tests.py
    if ($LASTEXITCODE -ne 0) { throw 'Workbook validation failed' }
} finally { Pop-Location }
