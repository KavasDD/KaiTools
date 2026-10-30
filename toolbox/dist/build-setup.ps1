# SPDX-License-Identifier: GPL-3.0-only
# 打小开工具箱的安装包 + 绿色版。
#
# 产出(都在 dist\ 下):
#     XiaokaiToolbox-setup-v<版本>.exe  单页安装包,载荷全嵌在里面
#     小开工具箱-绿色版-v<版本>.zip      解开就能用,不装不写注册表
#
# 用法:  powershell -NoProfile -File build-setup.ps1
#         (不要加 -ExecutionPolicy Bypass,这台机器上不允许)
#
# 关于编译:
#   * csc 是 .NET Framework 4.0 那个,只有 v3.5/v4.0 的引用程序集,所以 Setup.cs
#     只用 System / System.Drawing / System.Windows.Forms,不碰 ZipFile。
#   * Setup.cs 是 UTF-8 无 BOM 且带中文,必须给 /codepage:65001,不给的话 csc 按
#     系统 ANSI 读,中文字符串全变乱码 —— 而且它不报错,是无声的。
#   * 同一份源码编两遍:先 /define:UNINSTALLER 出 uninstall.exe(不带载荷),再把
#     它当成载荷之一嵌进安装包。

param([string]$BuildDirectory = $PSScriptRoot)
$ErrorActionPreference = 'Stop'
$here = [IO.Path]::GetFullPath($BuildDirectory)
$root = Split-Path -Parent $here          # toolbox\
$out  = Join-Path $root 'out'

function Say($m)  { Write-Host "  $m" }
function Ok($m)   { Write-Host "  [ok] $m" -ForegroundColor Green }
function Warn($m) { Write-Host "  [!!] $m" -ForegroundColor Yellow }
function Die($m)  { Write-Host "  [xx] $m" -ForegroundColor Red; exit 1 }

$csc = "$env:WINDIR\Microsoft.NET\Framework64\v4.0.30319\csc.exe"
if (-not (Test-Path $csc)) { $csc = "$env:WINDIR\Microsoft.NET\Framework\v4.0.30319\csc.exe" }
if (-not (Test-Path $csc)) { Die "找不到 csc.exe" }

# ---- 1. 版本号必须和主程序一致 ----
# 发出去的包版本对不上,远端机器上就没法判断跑的是哪一版(ship-requires-version-bump)。
Write-Host "`n[1/6] 核对版本号"
$setupVer = ([regex]::Match((Get-Content (Join-Path $here 'Setup.cs') -Raw),
             'Version\s*=\s*"([\d.]+)"')).Groups[1].Value
$appVer   = ([regex]::Match((Get-Content (Join-Path $root 'Toolbox.cs') -Raw),
             'public const string Version\s*=\s*"([\d.]+)"')).Groups[1].Value
if (-not $setupVer) { Die "Setup.cs 里读不到版本号" }
if (-not $appVer)   { Die "Toolbox.cs 里读不到版本号" }
if ($setupVer -ne $appVer) { Die "版本号不一致:Setup.cs=$setupVer,Toolbox.cs=$appVer" }
Ok "v$setupVer"
$installerName = "XiaokaiToolbox-setup-v$setupVer.exe"
$portableName = "XiaokaiToolbox-portable-v$setupVer.zip"

# ---- 2. 主程序重新编一遍,免得拿到旧的 ----
Write-Host "`n[2/6] 编译主程序"
& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'build.ps1')))) -Root $root
if ($LASTEXITCODE -ne 0) { Die "主程序编译失败" }
$appExe = Join-Path $out 'XiaokaiToolbox.exe'
if (-not (Test-Path $appExe)) { Die "没找到 $appExe" }
Ok ("XiaokaiToolbox.exe  {0:N0} 字节" -f (Get-Item $appExe).Length)
& ([scriptblock]::Create([IO.File]::ReadAllText((Join-Path $root 'allegro/build.ps1')))) -Root (Join-Path $root 'allegro')
if ($LASTEXITCODE -ne 0) { Die "Allegro 辅助程序编译失败" }

# ---- 3. 凑载荷 ----
# 资源名一律 ASCII:/resource: 的名字带中文的话,csc 按 ANSI 解析命令行,名字进去
# 就变形了,运行时 GetManifestResourceStream 按 UTF-16 的中文名找,永远找不到。
# 真实文件名(可含中文)写在 Setup.cs 的 Plan 里。
Write-Host "`n[3/6] 收集载荷"
$specgen = Join-Path $root 'selfsoftware2\dist\元器件规格描述生成器.exe'
$autoload = Join-Path (Split-Path -Parent $root) 'autoload'
$repoRoot = Split-Path -Parent $root
$legalDir = Join-Path $out 'legal'
New-Item -ItemType Directory -Force -Path $legalDir | Out-Null
foreach ($name in @('LICENSE', 'COPYRIGHT', 'THIRD_PARTY_NOTICES.md', 'BUILD_ENVIRONMENT.json')) {
    $source = Join-Path $repoRoot $name
    if (-not (Test-Path -LiteralPath $source)) { Die "Missing release notice: $source" }
    Copy-Item -LiteralPath $source -Destination (Join-Path $legalDir $name) -Force
}
$sourceNotice = @'
小开工具箱按 GPL-3.0-only 发布，完整条款见 LICENSE。
本次发布同时提供完整对应源码（包括生成和安装脚本）：
https://github.com/KavasDD/KaiTools/releases/tag/vVERSION
下载 XKGJX-source-vVERSION.zip；也可从同名 Git 标签取得源码：
https://github.com/KavasDD/KaiTools/tree/vVERSION
项目没有任何担保。分发修改版时须保留声明、标明修改并按 GPL 提供对应源码。
第三方作者与依赖许可见 THIRD_PARTY_NOTICES.md 和 LICENSES/。
'@
[IO.File]::WriteAllText((Join-Path $legalDir 'SOURCE_CODE.txt'), $sourceNotice.Replace('VERSION', $setupVer), (New-Object Text.UTF8Encoding($true)))
$licenseFiles = @(Get-ChildItem -LiteralPath (Join-Path $repoRoot 'LICENSES') -File -Recurse)
if (-not $licenseFiles.Count) { Die 'Run scripts/collect-licenses.py before packaging.' }
foreach ($file in $licenseFiles) {
    $relative = $file.FullName.Substring($repoRoot.Length + 1)
    $target = Join-Path $legalDir $relative
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
}
$payload = [ordered]@{
    'app.exe'                     = $appExe
    'tools.ini'                   = Join-Path $out  'tools.ini'
    'logo.ico'                    = Join-Path $root 'toolbox.ico'
    'lceda2orcadMenu.tcl'          = Join-Path $autoload 'lceda2orcadMenu.tcl'
    'bomtoolMenu.tcl'              = Join-Path $autoload 'bomtoolMenu.tcl'
    'netlocatorMenu.tcl'           = Join-Path $autoload 'netlocatorMenu.tcl'
    'drctoolMenu.tcl'              = Join-Path $autoload 'drctoolMenu.tcl'
    'textaffixMenu.tcl'            = Join-Path $autoload 'textaffixMenu.tcl'
    'xiaokaiSchematicPlugins.tcl'  = Join-Path $autoload 'xiaokaiSchematicPlugins.tcl'
    'specgen.exe'                  = $specgen
    'specgen.ico'                  = Join-Path $root 'specgen.ico'
    'jlc3d.exe'                    = Join-Path $out  'JLC3D-Downloader.exe'
    'jlc3d.ico'                    = Join-Path $root 'jlc3d.ico'
    'markinglookup.exe'            = Join-Path $out '常见丝印反查.exe'
    'startupoptimizer.exe'         = Join-Path $out 'OrCAD启动优化工具.exe'
}
$payload['allegro.install.ps1'] = Join-Path $root 'allegro/install.ps1'
foreach ($name in @('film_reorder.il', 'Auto_artwork.il', 'Quick_ColorS.il', 'x_change_via_net.il',
                    'Find_Component.il', 'Find_DRC.il', 'quick_grids.il', 'quick_display.il',
                    'conv.il', 'highlight_padstack.il', 'show_library.il', 'show_height.il',
                    'fTextTuneTools.il', 'check_no_refdes.il', 'gxl_wdzcheck_text_overlap.il', 'jkcheck_refdes_cross.il', 'x_silk_in_out.il', 'xiaokaiTextTools.il',
                    'lgs_hilight_no_fanout.il', 'lgs_check_solder_to_line_V1_0.il', 'quick_chSmd2ThrP.il', 'find_pin_no_past.il', 'find_pin_no_solder.il',
            'xiaokaiDanglings.il', 'xiaokaiAllegroMenu.il', 'xiaokaiAllegroHotkey.exe', 'xiaokaiAiBridge.exe')) {
    $payload["allegro.$name"] = Join-Path $root "allegro/skill/$name"
}
$legalResourceFiles = @{}
foreach ($file in @(Get-ChildItem -LiteralPath $legalDir -File -Recurse | Sort-Object FullName)) {
    $relative = $file.FullName.Substring($legalDir.Length + 1).Replace('\', '/')
    $resource = 'legal.' + $relative
    $payload.Add($resource, $file.FullName)
    $legalResourceFiles.Add($resource, $relative)
}
# app.exe / tools.ini / logo.ico 缺了就没法继续,其余缺了只是少个组件 —— 界面上
# 那一条会显示成灰的"这个安装包里没带这个组件",而不是装完才发现文件不在。
$must = @(
    'app.exe', 'tools.ini', 'logo.ico', 'lceda2orcadMenu.tcl',
    'bomtoolMenu.tcl', 'netlocatorMenu.tcl', 'drctoolMenu.tcl', 'textaffixMenu.tcl', 'xiaokaiSchematicPlugins.tcl',
    'startupoptimizer.exe', 'markinglookup.exe'
)
$must += @($payload.Keys | Where-Object { $_ -like 'allegro.*' })
$must += @($legalResourceFiles.Keys)
$must += @('specgen.exe', 'jlc3d.exe')
$res = @(); $total = 0
foreach ($k in $payload.Keys) {
    $p = $payload[$k]
    if (Test-Path $p) {
        $sz = (Get-Item $p).Length
        $total += $sz
        $res += "/resource:$p,$k"
        Say ("{0,-24} {1,12:N0}" -f $k, $sz)
    } elseif ($must -contains $k) {
        Die "缺少必需文件:$p"
    } else {
        Warn "没有 $p,这个组件不进包"
    }
}
Ok ("载荷合计 {0:N1} MB" -f ($total / 1MB))

# ---- 4. 先编卸载程序(不带载荷) ----
Write-Host "`n[4/6] 编译卸载程序"
$src = @((Join-Path $here 'Setup.cs'), (Join-Path $root 'allegro/AllegroSkillFiles.cs'), (Join-Path $root 'allegro/AllegroSetup.cs'))
$ico   = Join-Path $root 'toolbox.ico'
$unin  = Join-Path $out  'uninstall.exe'
$refs  = @('/r:System.dll','/r:System.Drawing.dll','/r:System.Windows.Forms.dll')
$base  = @('/nologo','/target:winexe','/optimize+','/warnaserror-','/codepage:65001')
if (Test-Path $ico) { $base += "/win32icon:$ico" }

# 卸载程序也要 logo.ico,不然它的界面上没有图标。
& $csc @base @refs '/define:UNINSTALLER' "/resource:$ico,logo.ico" "/resource:$(Join-Path $root 'allegro/install.ps1'),allegro.install.ps1" "/out:$unin" @src
if ($LASTEXITCODE -ne 0) { Die "卸载程序编译失败" }
Ok ("uninstall.exe  {0:N0} 字节" -f (Get-Item $unin).Length)

# ---- 5. 编安装包,把卸载程序一起嵌进去 ----
Write-Host "`n[5/6] 编译安装包"
$res += "/resource:$unin,uninstall.exe"
$exe = Join-Path $here $installerName
if (Test-Path $exe) { Remove-Item -LiteralPath $exe -Force }
& $csc @base @refs @res "/out:$exe" @src
if ($LASTEXITCODE -ne 0) { Die "安装包编译失败" }
if (-not (Test-Path $exe)) { Die "编完了但文件不在?" }
Ok ("$installerName  {0:N1} MB" -f ((Get-Item $exe).Length / 1MB))

# 回读产物里的版本号,确认真的进去了 —— 光看源码不算。
$fv = (Get-Item $exe).VersionInfo.FileVersion
if ($fv -notlike "$setupVer*") { Die "产物版本号是 $fv,跟 $setupVer 不符" }
Ok "产物版本号 $fv"

# ---- 6. 绿色版 ----
# 压缩在这儿做而不是在 exe 里做:csc 没有 4.5+ 的引用程序集,ZipFile 编不过。
# Compress-Archive 是 PowerShell 5.1 自带的,不需要额外装东西。
Write-Host "`n[6/6] 打绿色版"
$green = Join-Path $here '小开工具箱-绿色版'
if ([IO.Path]::GetFullPath($green) -ne [IO.Path]::Combine([IO.Path]::GetFullPath($here), '小开工具箱-绿色版')) { Die 'Unsafe staging path' }
$zip = Join-Path $here $portableName
if (Test-Path $green) { Remove-Item -LiteralPath $green -Recurse -Force }
if (Test-Path $zip)   { Remove-Item -LiteralPath $zip -Force }
New-Item -ItemType Directory -Path $green | Out-Null

# 绿色版里文件用真实名字(可含中文),跟安装出来的目录长得一样。
$greenFiles = @{
    'app.exe'               = 'XiaokaiToolbox.exe'
    'tools.ini'             = 'tools.ini'
    'specgen.exe'           = '元器件规格描述生成器.exe'
    'specgen.ico'           = 'specgen.ico'
    'jlc3d.exe'             = 'JLC3D-Downloader.exe'
    'jlc3d.ico'             = 'jlc3d.ico'
    'markinglookup.exe'    = '常见丝印反查.exe'
    'startupoptimizer.exe' = 'OrCAD启动优化工具.exe'
}
foreach ($k in $greenFiles.Keys) {
    if (-not $payload.Contains($k)) { continue }
    $s = $payload[$k]
    if (Test-Path $s) { Copy-Item -LiteralPath $s -Destination (Join-Path $green $greenFiles[$k]) }
}

foreach ($resource in $legalResourceFiles.Keys) {
    $target = Join-Path $green $legalResourceFiles[$resource]
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    Copy-Item -LiteralPath $payload[$resource] -Destination $target -Force
}
$readme = @"
小开工具箱 v$setupVer 绿色版
================================

解压到任意目录,双击 XiaokaiToolbox.exe 就能用。不写注册表,不建快捷方式,
删掉这个目录就等于卸载干净了。

目录里有什么
    XiaokaiToolbox.exe          主程序
    tools.ini                   工具清单(升级会覆盖,不要在这里加自己的东西)
    元器件规格描述生成器.exe      按型号生成规范的元器件规格描述
    JLC3D-Downloader.exe        按编号批量下载封装的 3D 模型
    OrCAD启动优化工具.exe       按需停用启动功能，备份与恢复
    常见丝印反查.exe             离线丝印反查，支持分类、封装筛选与复制

想自己加别的软件快捷方式
    在主程序里点"添加其他软件"就行,它会写到 tools.local.ini。这个文件升级时
    不会被覆盖,tools.ini 会。

常用 DSN / BRD 文件
    常用文件使用 16×16 小图标：DSN 仅在 OrCAD 工具页显示，BRD 仅在 Allegro 工具页显示。
    双击 DSN 使用 Capture 打开,双击 BRD 使用 Allegro 打开；Cadence 未加入
    Windows 最近项目的文件不会显示。

固定外观
    工具箱固定使用当前深蓝背景，OrCAD 为蓝白，Allegro 为黑红。
    不再提供皮肤选择，也不再读取原有皮肤设置。安装升级后重启 Capture / Allegro。
    A1、A2 辅助窗口使用黑红配色；其余原生 SKILL 工具窗口沿用原界面。

OrCAD 原理图插件
    AI 配置统一在主工具箱左下角「API KEY」；获取模型后下拉选择并保存。
    OrCAD / Allegro 中按 Alt+K，点击「AI 命令辅助」描述完整要求。模型会选择并组合
    已接入指令，执行每步后重新读取工程和原生结果，决定继续或结束，无需固定话术。
    OrCAD支持独立导线创建、改名、移动、输入连接符、图纸点选、红色Text和定位；
    Allegro支持定位和打开已有工具，工具内具体操作仍需手动完成。调用过程、结果和
    失败原因显示在同一对话中；原生失败、工程切换或取消停止后续步骤。
    Capture 插件位于 OrCAD 工具页右侧，按功能分类，单击分类展开或收起。
    安装版会自动安装 Orcad内直接放置立创元件、BOM输出增强版、Signal一键全网络高亮、DRC中文增强版、任意位置批量前/后添加文字及统一入口脚本。
    首次安装前如有同名脚本会备份；升级仅替换工具箱管理的脚本。Capture 正在运行时
    也会尝试更新，完成后请重启 Capture。原理图中按 Alt+K 打开分类功能集合。
    安装版默认安装 Allegro SKILL：一键设置光绘与层叠颜色、过孔修改网络、悬空线／过孔／孤岛检查与处理。
    Allegro 板图中按 Alt+K 使用；主工具箱的 Allegro 工具页右侧显示可展开的 SKILL 分类和说明。
    绿色版不会自动更改 Capture / Allegro；请使用安装版安装插件。
    卸载安装版时默认保留插件，也可取消“保留 OrCAD 原理图插件”并删除，已备份的
    原文件会恢复。卸载后请重启 Capture。

退出工具箱会先请求正常关闭由工具箱启动的程序,等待 8 秒后强制结束仍运行的进程树。
安装器默认勾选“强制结束已安装目录中的工具进程及其子进程”；请先保存工程和其他
未保存内容。手动启动的程序不受工具箱退出清理影响。

OrCAD 启动优化工具
    在“其他辅助工具”中双击打开，选择方案并查看停用影响。
    保存工程并关闭 Capture 后应用，下次启动生效；支持恢复本工具停用项。

netlocator 插件
    安装版统一提供 Alt+F2 跨页定位网络、Alt+F3 选择当前页整网。
    定位结果窗口始终置顶,双击跳转后仍保持可见。

要开机自启、要在开始菜单里、要能从控制面板卸载,用安装版:
    $installerName
"@
# UTF-8 带 BOM:记事本打开中文才不乱码(它对无 BOM 的 UTF-8 猜得不准)。
$readme | Out-File -FilePath (Join-Path $green '使用说明.txt') -Encoding utf8

for ($archiveAttempt = 1; $archiveAttempt -le 3; $archiveAttempt++) {
    try {
        Compress-Archive -Path "$green\*" -DestinationPath $zip -CompressionLevel Optimal -Force -ErrorAction Stop
        break
    } catch {
        if ($archiveAttempt -eq 3) { throw }
        Start-Sleep -Seconds 2
    }
}
try { Remove-Item -LiteralPath $green -Recurse -Force -ErrorAction Stop }
catch { Warn "压缩包已生成，临时目录被占用，可稍后清理：$green" }
Ok ("$portableName  {0:N1} MB" -f ((Get-Item $zip).Length / 1MB))

Write-Host "`n两个产物都在 $here`n" -ForegroundColor Cyan
Get-Item -LiteralPath $exe, $zip | ForEach-Object { Say ("{0,-34} {1,10:N1} MB" -f $_.Name, ($_.Length/1MB)) }
