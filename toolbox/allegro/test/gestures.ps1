$ErrorActionPreference = 'Stop'
$testOutput = Join-Path ([IO.Path]::GetTempPath()) ('xk-allegro-gestures-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $testOutput | Out-Null
$testExe = Join-Path $testOutput 'GestureChecks.exe'
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
& $compiler /nologo /target:exe /platform:x64 /codepage:65001 /main:GestureChecks /reference:System.Windows.Forms.dll /reference:System.Drawing.dll /reference:System.Web.Extensions.dll "/out:$testExe" (Join-Path $PSScriptRoot 'GestureChecks.cs') (Join-Path $PSScriptRoot '..\src\AllegroHotkey.cs') (Join-Path $PSScriptRoot '../../WindowSkins.cs')
if ($LASTEXITCODE) { throw 'Gesture checks build failed.' }
& $testExe
if ($LASTEXITCODE) { throw 'Gesture checks failed.' }
