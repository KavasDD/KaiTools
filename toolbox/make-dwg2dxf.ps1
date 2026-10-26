# SPDX-License-Identifier: GPL-3.0-only
# 把 dwg2dxf_gui.py 打成 toolbox\dwg2dxf.exe。
#
#     powershell -NoProfile -File toolbox\make-dwg2dxf.ps1
#
# 产物落在 toolbox\ 里,和 .ico 放一起,走法和 make-jlc3d.ps1 一样:build.ps1
# 从这儿往 out\ 拷,dist\build.ps1 再从 out\ 装进安装包。
#
# 依赖:PyInstaller + 这个工具自己的三个库。源码用了第三方库,不是纯标准库,
# 所以打包机器上得先装齐:
#     python -m pip install pyinstaller "ezdwg[dxf]" ezdxf Pillow
param(
    [string]$Root = (Split-Path -Parent $PSCommandPath),
    [switch]$Clean
)
$ErrorActionPreference = 'Stop'

$src = Join-Path $Root 'src\dwg2dxf_gui.py'
$ico = Join-Path $Root 'dwg2dxf.ico'
$exe = Join-Path $Root 'dwg2dxf.exe'
$work = Join-Path $env:TEMP 'dwg2dxf-build'

if (-not (Test-Path $src)) { throw "missing $src" }
# 图标缺了就停 —— tools.ini 拿它当格子图,而 --icon 也要它给 exe 定文件图标。
if (-not (Test-Path $ico)) { throw "missing $ico - run toolbox\make-icons.ps1 first" }

& python -c "import PyInstaller" 2>$null
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller not installed - run: python -m pip install pyinstaller' }

# 先过一遍编译,语法错在这一步就报出来 —— windowed 模式下双击不弹 traceback。
& python -m py_compile $src
if ($LASTEXITCODE -ne 0) { throw 'dwg2dxf_gui.py does not compile' }

if ($Clean -and (Test-Path $work)) { Remove-Item $work -Recurse -Force }

# --onefile/--windowed:和其它自研工具一致,单 exe、无黑窗口。
# 这个工具的窗口图标走的是源码里 __file__ 边上的 kuromi_*.png,没有就退默认 —
# 那是它本来的行为,不改。exe 的文件图标(任务栏兜底)由 --icon 定。
# ezdwg 带一个编译扩展(pyd)+ 数据,PyInstaller 的钩子未必全抓得到,用
# collect-all 兜底,免得打出来的 exe 一转换就报缺 DLL/数据。
$pyArgs = @(
    '-m', 'PyInstaller',
    '--onefile', '--windowed', '--noconfirm',
    '--name', 'dwg2dxf',
    '--icon', $ico,
    '--collect-all', 'ezdwg',
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
Remove-Item (Join-Path $work 'dwg2dxf.spec') -Force -ErrorAction SilentlyContinue

$size = (Get-Item $exe).Length
Write-Host ''
Write-Host "built $exe"
Write-Host ("  size : {0:N0} bytes ({1:N1} MB)" -f $size, ($size / 1MB))
Write-Host ''
Write-Host 'next:  powershell -File toolbox\build.ps1'