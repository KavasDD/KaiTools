# SPDX-License-Identifier: GPL-3.0-only
# 编译小开工具箱。
#
#     powershell -File toolbox\build.ps1
#     powershell -File toolbox\build.ps1 -Test    # 编译后跑一遍自检
#
# 用 .NET Framework 自带的 csc.exe,机器上不需要装 SDK、不需要 VS。
# 产物是 toolbox\out\XiaokaiToolbox.exe 加同目录的 tools.ini。
param(
    [string]$Root = (Split-Path -Parent $PSCommandPath),
    [switch]$Test
)
$ErrorActionPreference = 'Stop'
if (-not $env:XIAOKAI_BUILD_PYTHON) { $env:XIAOKAI_BUILD_PYTHON = (Get-Command python -ErrorAction Stop).Source }

$src  = Join-Path $Root 'Toolbox.cs'
$ini  = Join-Path $Root 'tools.ini'
$out  = Join-Path $Root 'out'
$exe  = Join-Path $out 'XiaokaiToolbox.exe'

# 旧版本曾把三个大型转换器复制到 out\。清理它们，避免瘦身后的构建目录
# 仍然被旧文件撑大；用户需要时通过工具箱的 ZIP 加载入口安装。
foreach ($large in 'dwg2dxf.exe', 'step2dxf.exe', 'gerber2dxf.exe') {
    Remove-Item (Join-Path $out $large) -Force -ErrorAction SilentlyContinue
}
foreach ($obsolete in 'lceda2orcad-setup.exe', 'bomtool-setup.exe', 'netlocator-setup.exe',
                      'netlocatorMenu.tcl') {
    Remove-Item (Join-Path $out $obsolete) -Force -ErrorAction SilentlyContinue
}

foreach ($f in @($src, $ini)) {
    if (-not (Test-Path $f)) { throw "missing $f" }
}
if (-not (Test-Path $out)) { New-Item -ItemType Directory $out | Out-Null }

# csc.exe 随 .NET Framework 4 一起装在 Windows 里,Win10 上一定有。
$csc = 'C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) {
    $csc = 'C:\Windows\Microsoft.NET\Framework\v4.0.30319\csc.exe'
}
if (-not (Test-Path $csc)) { throw 'csc.exe not found - .NET Framework 4.x missing' }

# /target:winexe 而不是 exe:否则双击会先弹一个黑色控制台窗口。
$refs = @(
    '/r:System.dll'
    '/r:System.Web.Extensions.dll'
    '/r:System.Drawing.dll'
    '/r:System.Windows.Forms.dll'
    '/r:System.IO.Compression.dll'
    '/r:System.IO.Compression.FileSystem.dll'
)
$skinSource = Join-Path $Root 'WindowSkins.cs'
& $env:XIAOKAI_BUILD_PYTHON (Join-Path $Root 'drc/build.py')
if ($LASTEXITCODE) { throw 'AI bridge build failed' }
$skinResources = @()
foreach ($skinId in @('toolbox-b','orcad-a','allegro-a')) {
    $skinFile = Join-Path $Root "design/window-backgrounds-v1/$skinId.png"
    if (-not (Test-Path -LiteralPath $skinFile)) { throw "Missing skin artwork: $skinId" }
    $skinResources += "/resource:$skinFile,skin.$skinId.png"
}
$args = @(
    '/nologo'
    '/target:winexe'
    '/optimize+'
    '/codepage:65001'
    '/warnaserror-'
    "/out:$exe"
) + $refs + $skinResources + @("/resource:$(Join-Path $Root 'drc/test-output/xiaokaiAiBridge.exe'),xiaokai.ai.bridge", $src, $skinSource, (Join-Path $Root 'allegro/AllegroSkillFiles.cs'))

# 图标可以没有 —— 缺了只是变成默认的空白 exe 图标,不该让整个构建失败。
# 生成方式见 make-icon.ps1。
$ico = Join-Path $Root 'toolbox.ico'
if (Test-Path $ico) {
    $args = @("/win32icon:$ico") + $args
} else {
    Write-Host "note: toolbox.ico missing - run make-icon.ps1 to generate it"
}

Write-Host "compiling with $(Split-Path -Leaf $csc) ..."
& $csc @args
if ($LASTEXITCODE -ne 0) { throw "csc failed with exit code $LASTEXITCODE" }

# tools.ini 必须跟 exe 同目录 —— 程序按 exe 所在目录去找它。
# 用 UTF-8 无 BOM 写:清单里全是中文,C# 那边按 UTF-8 读。
$iniTxt = [System.IO.File]::ReadAllText($ini)
[System.IO.File]::WriteAllText(
    (Join-Path $out 'tools.ini'), $iniTxt,
    (New-Object System.Text.UTF8Encoding($false)))

# 工具图标也得跟到 out\ —— 清单里是 %TOOLBOX%\*.ico,而 %TOOLBOX%
# 就是 exe 所在目录。以前只有 dist\build.ps1 拷,于是从 out\ 直接跑(README
# 里写的开发跑法)那两个格子退回字母占位图,看着像图标做坏了,实际是没拷过来。
# 缺了只警告不失败:图标是外观问题,不像缺 exe 那样让功能不可用。
foreach ($ico in 'specgen.ico', 'jlc3d.ico', 'dwg2dxf.ico', 'step2dxf.ico', 'gerber2dxf.ico') {
    $p = Join-Path $Root $ico
    if (Test-Path $p) { Copy-Item $p (Join-Path $out $ico) -Force }
    else { Write-Warning "$ico not found - that tile will show a placeholder (run make-icons.ps1)" }
}

# 嘉立创 3D 模型下载器。绿色版单 exe,清单里用 %TOOLBOX% 指过来,和上面那个
# 安装包一样只是拷过去。缺了只警告:它由 make-jlc3d.ps1 打包,需要 PyInstaller,
# 不该因为这台机器没装 PyInstaller 就整个构建失败。
$jlc = Join-Path $Root 'JLC3D-Downloader.exe'
if (Test-Path $jlc) {
    Copy-Item $jlc (Join-Path $out 'JLC3D-Downloader.exe') -Force
    Write-Host "  bundled : JLC3D-Downloader.exe"
} else {
    Write-Warning "JLC3D-Downloader.exe not found - run toolbox\make-jlc3d.ps1 (that entry will show as unavailable)"
}

# 元器件规格描述生成器。自包含单 exe,清单里用 %TOOLBOX% 指过来,和上面一样只是
# 拷过去。它在 selfsoftware2\ 项目里另有构建脚本(tools\build_exe.py),不在本
# 目录打包,所以单列一段;缺了只警告不失败。config.json 由它写在自己所在目录
# (即 %TOOLBOX%),不落临时目录。
$specgen = Join-Path $Root 'selfsoftware2\dist\元器件规格描述生成器.exe'
if (Test-Path $specgen) {
    Copy-Item $specgen (Join-Path $out '元器件规格描述生成器.exe') -Force
    Write-Host "  bundled : 元器件规格描述生成器.exe"
} else {
    Write-Warning "元器件规格描述生成器.exe not found - build it in selfsoftware2 (python tools\build_exe.py); that entry will show as unavailable"
}

# Offline marking lookup; its TSV catalog is embedded in the executable.
& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $Root 'markinglookup/build.ps1')))) -Root (Join-Path $Root 'markinglookup') -OutputDirectory $out -Test:$Test

# Standalone startup manager, included in the auxiliary tools category.
$startupSrc = Join-Path $Root 'startupoptimizer\StartupOptimizer.cs'
$startupArgs = @('/nologo','/target:winexe','/optimize+','/codepage:65001',
    "/win32icon:$(Join-Path $Root 'startupoptimizer.ico')",
    "/out:$(Join-Path $out 'OrCAD启动优化工具.exe')",
    '/r:System.Core.dll','/r:System.Xml.dll','/r:System.Xml.Linq.dll') + $refs + @($startupSrc)
& $csc @startupArgs
if ($LASTEXITCODE -ne 0) { throw 'Startup optimizer compile failed' }
Write-Host '  bundled : OrCAD启动优化工具.exe'

$size = (Get-Item $exe).Length
Write-Host ""
Write-Host "built $exe"
Write-Host ("  size    : {0:N0} bytes" -f $size)

# 数一下清单里有多少工具和分类,构建完直接看出清单是否被正确读到。
$sections = (Select-String -Path $ini -Pattern '^\[' -AllMatches).Count - 1
$cats = ((Select-String -Path $ini -Pattern '^order\s*=' | Select-Object -First 1).Line -split '=', 2)[1]
Write-Host ("  tools   : {0}" -f $sections)
Write-Host ("  groups  : {0}" -f ($cats -split '\|').Count)

# -Test:把 SelfTest.cs 和同一份 Toolbox.cs 一起编成控制台程序。
# 用 /main: 指定入口,所以 GUI 源码里不用为测试留任何钩子。
if ($Test) {
    $tsrc = Join-Path $Root 'SelfTest.cs'
    if (-not (Test-Path $tsrc)) { throw "missing $tsrc" }
    $texe = Join-Path $out 'SelfTest.exe'
    $targs = @(
        '/nologo'
        '/target:exe'
        '/codepage:65001'
        '/warnaserror-'
        '/main:CadenceToolbox.SelfTest'
        "/out:$texe"
    ) + $refs + $skinResources + @($src, $skinSource, $tsrc, (Join-Path $Root 'allegro/AllegroSkillFiles.cs'))
    Write-Host ""
    Write-Host "running self-test ..."
    & $csc @targs
    if ($LASTEXITCODE -ne 0) { throw "self-test build failed with exit code $LASTEXITCODE" }
    & $texe
    $rc = $LASTEXITCODE
    # 自检只是构建期的检查,产物目录里不留它 —— 免得跟着 exe 一起被分发。
    Remove-Item $texe -Force -ErrorAction SilentlyContinue
    $layoutExe = Join-Path $out 'LayoutTest.exe'
    $layoutArgs = @('/nologo', '/target:exe', '/codepage:65001',
        '/main:CadenceToolbox.LayoutTest', "/out:$layoutExe") + $refs + $skinResources + @(
        $src, $skinSource, (Join-Path $Root 'LayoutTest.cs'), (Join-Path $Root 'allegro/AllegroSkillFiles.cs'))
    & $csc @layoutArgs
    if ($LASTEXITCODE -ne 0) { throw 'layout test build failed' }
    & $layoutExe
    $layoutResult = $LASTEXITCODE
    Remove-Item -LiteralPath $layoutExe -Force -ErrorAction SilentlyContinue
    if ($layoutResult -ne 0) { throw "layout test failed with exit code $layoutResult" }
    if ($rc -ne 0) { throw "self-test failed with exit code $rc" }
    $skinTestExe = Join-Path $out 'SkinChecks.exe'
    $skinTestArgs = @('/nologo','/target:exe','/codepage:65001',
        '/main:CadenceToolbox.SkinChecks', "/out:$skinTestExe") + $refs + $skinResources + @(
        $src, $skinSource, (Join-Path $Root 'SkinChecks.cs'),
        (Join-Path $Root 'allegro/AllegroSkillFiles.cs'), (Join-Path $Root 'allegro/src/AllegroHotkey.cs'))
    & $csc @skinTestArgs
    if ($LASTEXITCODE -ne 0) { throw 'Appearance check compile failed' }
    & $skinTestExe
    if ($LASTEXITCODE -ne 0) { throw 'Appearance checks failed' }
    Remove-Item -LiteralPath $skinTestExe -Force -ErrorAction SilentlyContinue
}

Write-Host ""
Write-Host "run it:  $exe"
