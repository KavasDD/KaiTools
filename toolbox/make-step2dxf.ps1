# SPDX-License-Identifier: GPL-3.0-only
# 把 step2dxf_converter.py 打成 toolbox\step2dxf.exe。
#
#     powershell -NoProfile -File toolbox\make-step2dxf.ps1
#
# 依赖最重的一个:cadquery + OCP(OpenCASCADE 的 Python 绑定)。打包机器上先装:
#     python -m pip install pyinstaller cadquery ezdxf Pillow
#
# 提醒:这个 exe 会很大(OCP 那个编译库单独就一百多 MB),onefile 冷启动
# 也慢些 —— 这是 cadquery 本身的体量,不是打包方式的问题。
param(
    [string]$Root = (Split-Path -Parent $PSCommandPath),
    [switch]$Clean
)
$ErrorActionPreference = 'Stop'

$src = Join-Path $Root 'src\step2dxf_converter.py'
$ico = Join-Path $Root 'step2dxf.ico'
$exe = Join-Path $Root 'step2dxf.exe'
$work = Join-Path $env:TEMP 'step2dxf-build'

if (-not (Test-Path $src)) { throw "missing $src" }
if (-not (Test-Path $ico)) { throw "missing $ico - run toolbox\make-icons.ps1 first" }

& python -c "import PyInstaller" 2>$null
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller not installed - run: python -m pip install pyinstaller' }

& python -m py_compile $src
if ($LASTEXITCODE -ne 0) { throw 'step2dxf_converter.py does not compile' }

if ($Clean -and (Test-Path $work)) { Remove-Item $work -Recurse -Force }

# 关键在 collect-all:源码里是 `from OCP.gp import ...` 这种在函数体里现导入的
# 写法,PyInstaller 的静态扫描抓不到,不 collect 的话打出来的 exe 一点转换就报
# ModuleNotFoundError。OCP 还带一堆 OpenCASCADE 的数据文件,--collect-all 会把
# binaries+datas 一起收走。
#
# vtk 千万别 collect-all:cadquery 只在 occ_impl/shapes.py 硬 import 了
# vtkCommonDataModel 一个类型,这个工具压根不做 3D 渲染(只用 importStep + OCP
# 的 HLR 投影)。对 vtkmodules 用 collect-all 会把整个 VTK 渲染/OpenGL 栈拽进来,
# exe 直接冲到 380MB。交给 PyInstaller 自带的 vtk 钩子按引用只收用到的那部分,
# 能砍掉一大半。cadquery 也不用 collect-all —— 它是纯 py 包,正常分析就能跟到,
# collect-all 只会顺带把它 examples/测试数据也带上。
$pyArgs = @(
    '-m', 'PyInstaller',
    '--onefile', '--windowed', '--noconfirm',
    '--name', 'step2dxf',
    '--icon', $ico,
    '--collect-all', 'OCP',
    '--collect-submodules', 'cadquery',
    '--exclude-module', 'torch',
    '--exclude-module', 'torchvision',
    '--exclude-module', 'tensorflow',
    '--exclude-module', 'scipy',
    '--exclude-module', 'numba',
    '--exclude-module', 'llvmlite',
    '--exclude-module', 'sympy',
    '--exclude-module', 'matplotlib',
    '--exclude-module', 'pandas',
    '--exclude-module', 'tkinter.test',
    '--exclude-module', 'pydoc_data',
    '--exclude-module', 'lib2to3',
    '--distpath', $Root,
    '--workpath', (Join-Path $work 'build'),
    '--specpath', $work,
    $src
)

Write-Host "building $exe ... (cadquery/OCP is large, this takes a while)"
& python @pyArgs
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed with exit code $LASTEXITCODE" }
if (-not (Test-Path $exe)) { throw "PyInstaller reported success but $exe is missing" }

Remove-Item (Join-Path $work 'build') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $work 'step2dxf.spec') -Force -ErrorAction SilentlyContinue

$size = (Get-Item $exe).Length
Write-Host ''
Write-Host "built $exe"
Write-Host ("  size : {0:N0} bytes ({1:N1} MB)" -f $size, ($size / 1MB))
Write-Host ''
Write-Host 'next:  powershell -File toolbox\build.ps1'