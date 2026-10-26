# SPDX-License-Identifier: GPL-3.0-only
param([string]$SpbRoot = 'C:\orcad\Cadence\SPB_17.4')
$ErrorActionPreference = 'Stop'
# A dedicated test process prevents modifying any already-open user design.
if (Get-Process Capture -ErrorAction SilentlyContinue) {
    throw 'Close Capture before running this development smoke test.'
}
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$captureExe = Join-Path $SpbRoot 'tools\bin\Capture.exe'
$sample = Join-Path $SpbRoot 'tools\capture\samples\PCB-Layout\FullAdder\FULLADD.DSN'
if (!(Test-Path $captureExe) -or !(Test-Path $sample)) { throw 'Capture/sample not found' }
$scratch = Join-Path $env:TEMP ('xiaokai-drc-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item -LiteralPath $sample -Destination (Join-Path $scratch 'validation.dsn')
[IO.File]::WriteAllText((Join-Path $scratch 'validation.opj'), @'
(ExpressProject ""
  (ProjectVersion "19981106")
  (ProjectType "PCB")
  (Folder "Design Resources"
    (Folder "Library")
    (File ".\validation.dsn" (Type "Schematic Design"))
    (RUN_Online_Rules "FALSE"))
  (Folder "Outputs")
  (Folder "Referenced Projects"))
'@, [Text.Encoding]::ASCII)
$launcher = Join-Path $scratch 'launch.tcl'
# Capture's command-line Tcl reader needs a one-line source command.
[IO.File]::WriteAllText($launcher,
    'source -encoding utf-8 [file join $::env(XIAOKAI_DRC_TEST_REPO) toolbox drc smoke_native.tcl]',
    [Text.Encoding]::ASCII)
$oldRepo = $env:XIAOKAI_DRC_TEST_REPO
$oldScratch = $env:XIAOKAI_DRC_TEST_SCRATCH
try {
    $env:XIAOKAI_DRC_TEST_REPO = $repo
    $env:XIAOKAI_DRC_TEST_SCRATCH = $scratch
    $process = Start-Process -FilePath $captureExe -ArgumentList ('"' + $launcher + '"') -WindowStyle Hidden -PassThru
} finally {
    $env:XIAOKAI_DRC_TEST_REPO = $oldRepo
    $env:XIAOKAI_DRC_TEST_SCRATCH = $oldScratch
}
Write-Output "Capture test process: $($process.Id)"
Write-Output "Log and reports: $scratch"
Write-Output 'Wait for PASS/FAIL in smoke.log. Only the disposable validation.dsn test fixture is modified in memory.'
