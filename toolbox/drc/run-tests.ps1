param([string]$TestRoot = $PSScriptRoot, [string]$Tcl = 'C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe')
$ErrorActionPreference = 'Stop'
foreach ($name in @('tests.tcl','lifecycle-tests.tcl','netlist-tests.tcl','save-tests.tcl',
    'ui-tests.tcl','usability-tests.tcl','review-tests.tcl','review-ui-tests.tcl','placement-tests.tcl','ai-tests.tcl','connections-tests.tcl')) {
    # Explicit UTF-8 source avoids Capture Tcl's Windows system encoding.
    $path = (Join-Path $TestRoot $name) -replace '\\','/'
    $launch = Join-Path $env:TEMP ('xiaokai-test-' + [guid]::NewGuid().ToString('N') + '.tcl')
    $text = "try {source -encoding utf-8 {$path}} on error {msg opts} {puts stderr [dict get `$opts -errorinfo]; exit 1}"
    [IO.File]::WriteAllText($launch, $text, [Text.Encoding]::ASCII)
    try {
        & $Tcl $launch
        if ($LASTEXITCODE -ne 0) {throw "Failed: $name"}
    } finally {Remove-Item -LiteralPath $launch -ErrorAction SilentlyContinue}
}
