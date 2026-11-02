# SPDX-License-Identifier: GPL-3.0-only
param([string]$Root=$PSScriptRoot,[string]$OutputDirectory=(Join-Path (Split-Path -Parent $PSScriptRoot) 'out'),[switch]$Test)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
$csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework64/v4.0.30319/csc.exe'
if (!(Test-Path $csc)) { $csc=Join-Path $env:WINDIR 'Microsoft.NET/Framework/v4.0.30319/csc.exe' }
$exe=Join-Path $OutputDirectory '立创封装转Allegro.exe'
& $csc /nologo /target:winexe /optimize+ /codepage:65001 /r:System.dll /r:System.Core.dll /r:System.Drawing.dll /r:System.Windows.Forms.dll /r:System.Web.Extensions.dll "/win32icon:$(Join-Path (Split-Path -Parent $Root) 'lceda2orcad.ico')" "/resource:$(Join-Path $Root 'native.il'),native.il" "/out:$exe" (Join-Path $Root 'LcedaAllegro.cs') (Join-Path $Root 'SelfTest.cs') (Join-Path $Root 'ExtraFormats.cs')
if ($LASTEXITCODE) { throw '立创封装转换器编译失败' }
if ($Test) {
 $check=Start-Process -FilePath $exe -ArgumentList '--self-test' -Wait -PassThru -WindowStyle Hidden -RedirectStandardOutput (Join-Path $OutputDirectory 'lceda2allegro-test.log') -RedirectStandardError (Join-Path $OutputDirectory 'lceda2allegro-test-error.log')
 Get-Content (Join-Path $OutputDirectory 'lceda2allegro-test.log')
 if ($check.ExitCode) { Get-Content (Join-Path $OutputDirectory 'lceda2allegro-test-error.log'); throw '转换器自检失败' }
}
Write-Host "Built: $exe"
