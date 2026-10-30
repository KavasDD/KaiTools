param([string]$SpbRoot = 'C:\orcad\Cadence\SPB_17.4')
$ErrorActionPreference = 'Stop'
if (Get-Process Capture -ErrorAction SilentlyContinue) {throw 'Close Capture before running the separate development test.'}
$repo = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$scratch = Join-Path (Join-Path $repo 'out') ('review-native-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
Copy-Item (Join-Path $SpbRoot 'tools\capture\samples\PCB-Layout\FullAdder\FULLADD.DSN') (Join-Path $scratch 'review.dsn')
[IO.File]::WriteAllText((Join-Path $scratch 'review.opj'), '(ExpressProject "" (ProjectVersion "19981106") (ProjectType "PCB") (Folder "Design Resources" (Folder "Library") (File ".\review.dsn" (Type "Schematic Design")) (RUN_Online_Rules "FALSE")) (Folder "Outputs") (Folder "Referenced Projects"))', [Text.Encoding]::ASCII)
$launcher = Join-Path $scratch 'launch.tcl'
[IO.File]::WriteAllText($launcher, 'source -encoding utf-8 [file join $::env(XIAOKAI_REVIEW_TEST_REPO) toolbox drc review-live.tcl]' + "`n", [Text.Encoding]::ASCII)
$previousDir = $env:XIAOKAI_REVIEW_TEST_DIR; $previousRepo = $env:XIAOKAI_REVIEW_TEST_REPO
try {
    $env:XIAOKAI_REVIEW_TEST_DIR = $scratch; $env:XIAOKAI_REVIEW_TEST_REPO = $repo
    $process = Start-Process (Join-Path $SpbRoot 'tools\bin\Capture.exe') -ArgumentList ('-product="OrCAD Capture CIS" "' + ($launcher -replace '\\','/') + '"') -WorkingDirectory $scratch -WindowStyle Hidden -PassThru
} finally {$env:XIAOKAI_REVIEW_TEST_DIR = $previousDir; $env:XIAOKAI_REVIEW_TEST_REPO = $previousRepo}
[pscustomobject]@{ProcessId=$process.Id;Directory=$scratch;Log=(Join-Path $scratch 'review-live.log')}
