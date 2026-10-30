param([string]$Root = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
if (-not $env:XIAOKAI_BUILD_PYTHON) { $env:XIAOKAI_BUILD_PYTHON = (Get-Command python -ErrorAction Stop).Source }
& $env:XIAOKAI_BUILD_PYTHON (Join-Path $Root 'build-ui.py')
if ($LASTEXITCODE) { throw 'SKILL UI build failed.' }
& $env:XIAOKAI_BUILD_PYTHON (Join-Path $Root 'build-danglings.py')
if ($LASTEXITCODE) { throw 'Danglings adapter build failed.' }
& $env:XIAOKAI_BUILD_PYTHON (Join-Path $Root 'build-c-checks.py')
if ($LASTEXITCODE) { throw 'C checks adapter build failed.' }
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $env:XIAOKAI_BUILD_PYTHON (Join-Path $Root '../drc/build.py')
if ($LASTEXITCODE) { throw 'Shared AI helper build failed.' }
Copy-Item -LiteralPath (Join-Path $Root '../drc/test-output/xiaokaiAiBridge.exe') -Destination (Join-Path $Root 'skill/xiaokaiAiBridge.exe') -Force
$skinResources = @()
foreach ($skinId in @('toolbox-b','orcad-a','allegro-a')) {
    $skinPath = Join-Path $Root "../design/window-backgrounds-v1/$skinId.png"
    $skinResources += "/resource:$skinPath,skin.$skinId.png"
}
& $compiler /nologo /target:winexe /platform:x64 /optimize+ /codepage:65001 /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll @skinResources "/out:$Root\skill\xiaokaiAllegroHotkey.exe" (Join-Path $Root 'src\AllegroHotkey.cs') (Join-Path $Root '../WindowSkins.cs')
if ($LASTEXITCODE) { throw 'Allegro hotkey helper build failed.' }
