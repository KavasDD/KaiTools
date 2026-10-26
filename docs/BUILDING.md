# 构建与测试

在仓库根目录运行命令。PowerShell 脚本以 UTF-8 BOM 保存以兼容 Windows PowerShell 5.1；不要删除 BOM。无需关闭系统的脚本安全设置。

## 环境

- Windows 10 / 11、Windows PowerShell 5.1。
- .NET Framework 4.x 自带 `csc.exe`，无需 Visual Studio。
- 完整发行构建使用 CPython 3.12 Windows 版，需含 tkinter / Tcl / Tk。
- `requirements-build.txt` 固定打包工具与传递依赖版本。
- 普通 Tcl 测试需 Tcl 8.6、tcltest 和 Tcllib 的 json 包；可使用 Capture 自带 `tcltk/bin/tclsh.exe`。运行主程序不要求 Python 或独立 Tcl。

## 最小构建

```powershell
powershell -NoProfile -File toolbox/build.ps1
```

产物是 `toolbox/out/XiaokaiToolbox.exe`、`tools.ini`、图标和启动优化工具。缺少尚未打包的 Python 配套工具只会显示不可用。

## 完整发行构建

```powershell
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install -r requirements-build.txt
powershell -NoProfile -File scripts/build-release.ps1 -Python .\.venv\Scripts\python.exe
```

该脚本重新生成插件，构建规格生成器与 3D 下载器，收集 Python / Tcl / Tk / PyInstaller 许可，然后编译安装版与绿色版。输出在 `toolbox/dist/`；原始 EXE 不进入版本库。

插件源码位置：立创转换在 `dev/`；BOM、DRC、文字前后缀分别在 `toolbox/bomtool`、`toolbox/drc`、`toolbox/textaffix`；Netlocator 与插件集合的源文件就是 `autoload/` 中的 Tcl 文件。文字前后缀的 EscapeWatcher.cs 会被编译并嵌入 Tcl。

规格生成器使用已提交的 `schema.json`，无需原始 Excel 表格。需要改变字段模型时可编辑 JSON；从自有 Excel 重新提取可使用 `toolbox/selfsoftware2/tools/extract_schema.py`，原始表格不随仓库提供。

## 测试

```powershell
powershell -NoProfile -File toolbox/build.ps1 -Test
powershell -NoProfile -File toolbox/startupoptimizer/build.ps1 -Test
powershell -NoProfile -File scripts/test.ps1 -Python .\.venv\Scripts\python.exe -Tclsh 'C:\你的安装目录\tcltk\bin\tclsh.exe'
```

主程序自检会报告开发机上的 Cadence 安装探测；未安装 Cadence 时跳过真实安装探测，仍检查假目录、清单、图标、布局等逻辑。Tcl 测试在独立进程运行，失败立即终止；tcltest 的失败数也会转换为非零退出码。

GitHub runner 没有可靠的交互桌面，CI 使用 `build.ps1 -Test -SkipInteractiveLayout`，明确跳过最小化/恢复测试；本地完整验证仍使用普通 `-Test`。

安装器的 `/selftest` 只运行内建载荷、界面和模拟插件安装生命周期检查，不会在真实 Cadence 目录执行安装：

```powershell
$p = Start-Process -WindowStyle Hidden -Wait -PassThru -FilePath '.\toolbox\dist\XiaokaiToolbox-setup-v1.6.45.exe' -ArgumentList '/selftest'
if ($p.ExitCode -ne 0) { throw '安装器自检失败，查看 %TEMP%\xiaokai-setup-selftest.txt' }
```

Capture 真实集成需在用户自己的测试工程中验证：Alt+K、放置符号、BOM、网络定位、DRC 和文字前后缀/撤销。`smoke*.tcl` 等脚本会操作设计，需先阅读并在专用测试工程中运行，不属于默认 CI。

## 可选 DXF 转换器

建议在独立虚拟环境中安装各自依赖，避免把不必要的库打入主发行包：

| 工具 | Python 依赖 | 构建入口 |
| --- | --- | --- |
| DWG → DXF | PyInstaller、`ezdwg[dxf]`、ezdxf、Pillow | `toolbox/make-dwg2dxf.ps1` |
| STEP → DXF | PyInstaller、cadquery、ezdxf、Pillow | `toolbox/make-step2dxf.ps1` |
| Gerber → DXF | PyInstaller、gerbonara、ezdxf | `toolbox/make-gerber2dxf.ps1` |

这些构建入口保留以供开发使用，本次发行未验证其完整构建，也不提供预编译包。发布前检查实际依赖的许可证、传递依赖和必要源码；本次主发行包的许可证收集脚本不覆盖这些额外依赖。

## 生成对应源码与校验值

源码提交后运行：

```powershell
powershell -NoProfile -File scripts/package-release.ps1
```

脚本要求已提交且工作区干净；使用 `git archive` 导出当前提交的完整对应源码，收集同版本安装版和绿色版，写入 SHA256SUMS.txt。发布时这四个文件应放在同一 Release，源码提供无需登录，并保持可下载。CI 使用 `-AllowGeneratedChanges`，仅允许生成插件和许可证记录变化，并将实际生成内容纳入源码快照。

若本机 PowerShell 的执行策略禁止运行脚本，可在已审阅脚本后，在 PowerShell 中读取并执行脚本内容，无需更改执行策略：

```powershell
$root = (Get-Location).Path
& ([scriptblock]::Create([IO.File]::ReadAllText("$root/scripts/build-release.ps1"))) -Root $root -Python "$root/.venv/Scripts/python.exe"
```

预编译程序可能包含构建时间等信息；这里保证构建步骤和对应源码可用，不声明不同机器上的产物逐字节一致。
