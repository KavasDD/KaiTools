# SPDX-License-Identifier: GPL-3.0-only
param([string]$Root = $PSScriptRoot, [string]$OutputDirectory = '', [switch]$Test)
$ErrorActionPreference = 'Stop'
if (-not $OutputDirectory) { $OutputDirectory = Join-Path (Split-Path -Parent $Root) 'out' }
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
$source = Join-Path $Root 'MarkingLookup.cs'
$data = Join-Path $Root 'markings.tsv'
$exe = Join-Path $OutputDirectory '常见丝印反查.exe'
$compileArgs = @('/nologo', '/optimize+', '/codepage:65001', '/r:System.dll', '/r:System.Drawing.dll',
    '/r:System.Windows.Forms.dll', "/resource:$data,markings.tsv")
$icon = Join-Path (Split-Path -Parent $Root) 'markinglookup.ico'
if (Test-Path -LiteralPath $icon) { $compileArgs += "/win32icon:$icon" }
& $csc @compileArgs '/target:winexe' "/out:$exe" $source
if ($LASTEXITCODE -ne 0) { throw 'Marking lookup compile failed' }
Write-Host "  bundled : $exe (embedded offline catalog)"
if ($Test) {
    $testExe = Join-Path $OutputDirectory 'MarkingLookupTests.exe'
    & $csc @compileArgs '/target:exe' '/main:XiaokaiMarking.LookupTests' "/out:$testExe" $source (Join-Path $Root 'LookupTests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Marking lookup test compile failed' }
    try {
        & $testExe (Join-Path $OutputDirectory 'markinglookup-preview.png')
        if ($LASTEXITCODE -ne 0) { throw 'Marking lookup tests failed' }
    } finally { Remove-Item -LiteralPath $testExe -Force -ErrorAction SilentlyContinue }
}
