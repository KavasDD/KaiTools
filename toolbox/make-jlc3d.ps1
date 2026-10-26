# SPDX-License-Identifier: GPL-3.0-only
# 把 JLC3DDownload.py 打成 toolbox\JLC3D-Downloader.exe。
#
#     powershell -NoProfile -File toolbox\make-jlc3d.ps1
#
# 产物直接落在 toolbox\ 里,和 .ico 放一起 —— build.ps1 从这儿往 out\ 拷,
# dist\build.ps1 从 out\ 装进安装包,和 lceda2orcad-setup.exe 一个走法。
#
# 要先有 PyInstaller:  python -m pip install pyinstaller
# 源码只用标准库,所以除了 PyInstaller 本身没有别的依赖要装。
param(
    [string]$Root = (Split-Path -Parent $PSCommandPath),
    [switch]$Clean,
    [string]$Python = 'python'
)
$ErrorActionPreference = 'Stop'

$src = Join-Path $Root 'src\JLC3DDownload.py'
$ico = Join-Path $Root 'jlc3d.ico'
$exe = Join-Path $Root 'JLC3D-Downloader.exe'
$work = Join-Path $env:TEMP 'jlc3d-build'

if (-not (Test-Path $src)) { throw "missing $src" }
# 图标缺了不只是难看:程序里 iconbitmap 也指着它,而 tools.ini 拿它当格子图标。
# 直接停下,而不是打出一个没图标的 exe。
if (-not (Test-Path $ico)) { throw "missing $ico - run toolbox\make-icons.ps1 first" }

& $Python -c "import PyInstaller" 2>$null
if ($LASTEXITCODE -ne 0) { throw 'PyInstaller not installed - run: python -m pip install pyinstaller' }

# 源码先过一遍编译。语法错在这一步报出来,比等 PyInstaller 打完包、
# 双击了什么都不弹要好查得多 —— windowed 模式下 traceback 没地方显示。
& $Python -m py_compile $src
if ($LASTEXITCODE -ne 0) { throw 'JLC3DDownload.py does not compile' }

if ($Clean -and (Test-Path $work)) { Remove-Item $work -Recurse -Force }

# --onefile:单个 exe,拷到哪都能跑,和工具箱"绿色版"的说法一致。代价是
#   每次启动要先解压到 %TEMP%,冷启动大约两三秒。
# --windowed:不带控制台。少了这个,双击会先弹一个黑窗口。
# --add-data:把 .ico 也塞进去,程序里 app_icon() 从 sys._MEIPASS 找它。
#   分隔符在 Windows 上是分号,写成冒号会被当成路径的一部分。
$pyArgs = @(
    '-m', 'PyInstaller',
    '--onefile', '--windowed', '--noconfirm',
    '--name', 'JLC3D-Downloader',
    '--icon', $ico,
    '--add-data', ($ico + ';.'),
    '--distpath', $Root,
    '--workpath', (Join-Path $work 'build'),
    '--specpath', $work,
    # 标准库里几个明确用不到的大件。tkinter 要留着,但它默认会把 tcl/tk 的
    # test 套件也带进来,排掉能小一截。
    '--exclude-module', 'tkinter.test',
    '--exclude-module', 'test',
    '--exclude-module', 'unittest',
    '--exclude-module', 'pydoc_data',
    '--exclude-module', 'lib2to3',
    $src
)

Write-Host "building $exe ..."
& $Python @pyArgs
if ($LASTEXITCODE -ne 0) { throw "PyInstaller failed with exit code $LASTEXITCODE" }
if (-not (Test-Path $exe)) { throw "PyInstaller reported success but $exe is missing" }

# PyInstaller 会在 --distpath 边上留一堆中间产物,清掉 —— toolbox\ 是源码目录,
# 不该躺着 build\ 和 .spec。
Remove-Item (Join-Path $work 'build') -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path $work 'JLC3D-Downloader.spec') -Force -ErrorAction SilentlyContinue

$size = (Get-Item $exe).Length
Write-Host ''
Write-Host "built $exe"
Write-Host ("  size : {0:N0} bytes ({1:N1} MB)" -f $size, ($size / 1MB))
Write-Host ''
Write-Host 'next:  powershell -File toolbox\build.ps1'
