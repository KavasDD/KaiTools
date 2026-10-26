# SPDX-License-Identifier: GPL-3.0-only
# 把 gerber2dxf.py 打成 toolbox\gerber2dxf.exe。
#
#     powershell -NoProfile -File toolbox\make-gerber2dxf.ps1
#
# 依赖:PyInstaller + gerbonara + ezdxf。打包机器上先装:
#     python -m pip install pyinstaller gerbonara ezdxf
#
# 这个工具的窗口图标是源码里内嵌的 base64,不依赖外部文件;--icon 只管 exe
# 的文件图标(资源管理器/任务栏兜底)。
param(
    [string]$Root = (Split-Path -Parent $PSCommandPath),
    [switch]$Clean
)
$ErrorActionPreference = 'Stop'

$src = Join-Path $Root 'src\gerber2dxf.py'
$ico = Join-Path $Root 'gerber2dxf.ico'
$exe = Join-Path $Root 'gerber2dxf.exe'
$work = Join-Path $env:TEMP 'gerber2dxf-build'

if (-not (Test-Path $src)) { throw "missing $src" }
if (-not (Test-Path $ico)) { throw "missing $ico - run toolbox\make-icons.ps1 first" }

& python -c "import PyInstaller" 2>$null
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller not installed - run: python -m pip install pyinstaller' }

& python -m py_compile $src
if ($LASTEXITCODE -ne 0) { throw 'gerber2dxf.py does not compile' }

if ($Clean -and (Test-Path $work)) { Remove-Item $work -Recurse -Force }

# gerbonara 的 aperture_macros 有一批子模块是按名字动态取的(源码里
# PRIMITIVE_CLASSES[5] 这种),collect-submodules 把这一包收全,兜住动态取用。
# 千万别对整个 gerbonara 用 collect-all —— 那会把 gerbonara.cad.* 和 .cli 也拽
# 进来,而它们 import torch/tensorflow/scipy,exe 直接从 45MB 涨到 250MB。这个
# 工具只用到 GerberFile / graphic_objects / apertures / aperture_macros.primitive,
# 全是模块顶部的静态 import,PyInstaller 正常分析就能找到。重的那堆显式排掉。
$pyArgs = @(
    '-m', 'PyInstaller',
    '--onefile', '--windowed', '--noconfirm',
    '--name', 'gerber2dxf',
    '--icon', $ico,
    '--collect-submodules', 'gerbonara.aperture_macros',
    '--exclude-module', 'torch',
    '--exclude-module', 'torchvision',
    '--exclude-module', 'tensorflow',
    '--exclude-module', 'scipy',
    '--exclude-module', 'numba',
    '--exclude-module', 'llvmlite',
    '--exclude-module', 'sympy',
    '--exclude-module', 'matplotlib',
    '--exclude-module', 'gerbonara.cad',
    '--exclude-module', 'gerbonara.cli',
    '--exclude-module', 'tkinter.test',
    '--exclude-module', 'pydoc_data',
    '--exclude-module', 'lib2to3',
    '--distpath', $Root,
    '--workpath', (Join-Path $work 'build'),
    '--specpath', $work,
    $src
)

Write-Host "building $exe ..."
& python @pyArgs
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed with exit code $LASTEXITCODE" }
if (-not (Test-Path $exe)) { throw "PyInstaller reported success but $exe is missing" }

Remove-Item (Join-Path $work 'build') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $work 'gerber2dxf.spec') -Force -ErrorAction SilentlyContinue

$size = (Get-Item $exe).Length
Write-Host ''
Write-Host "built $exe"
Write-Host ("  size : {0:N0} bytes ({1:N1} MB)" -f $size, ($size / 1MB))
Write-Host ''
Write-Host 'next:  powershell -File toolbox\build.ps1'