# SPDX-License-Identifier: GPL-3.0-only
param([switch]$Test, [string]$Root = (Split-Path -Parent $PSCommandPath))
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($Root)
$outDir = Join-Path $root 'dist'
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc)) { $csc = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe' }
$source = Join-Path $root 'StartupOptimizer.cs'
$refs = @('/r:System.dll','/r:System.Core.dll','/r:System.Drawing.dll','/r:System.Windows.Forms.dll','/r:System.Xml.dll','/r:System.Xml.Linq.dll')
$outputExe = Join-Path $outDir 'OrCAD启动优化工具.exe'
& $csc /nologo /target:winexe /optimize+ /codepage:65001 "/out:$outputExe" @refs $source
if ($LASTEXITCODE -ne 0) { throw 'Compilation failed' }
if ($Test) {
    $testDir = Join-Path $root 'test-output'
    New-Item -ItemType Directory -Force -Path $testDir | Out-Null
    $testExe = Join-Path $testDir 'StartupOptimizerTests.exe'
    & $csc /nologo /target:exe /codepage:65001 /main:OrCadStartup.Tests "/out:$testExe" @refs $source (Join-Path $root 'Tests.cs')
    if ($LASTEXITCODE -ne 0) { throw 'Test compilation failed' }
    & $testExe (Join-Path $testDir 'ui.png')
    if ($LASTEXITCODE -ne 0) { throw 'Tests failed' }
}
Copy-Item -LiteralPath (Join-Path $root 'README.md') -Destination (Join-Path $outDir '使用说明.md') -Force
Write-Host "Built: $outputExe"
