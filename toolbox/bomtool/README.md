# OrCAD BOM Workbench 1.3.10

在 Capture CIS 17.4 内直接读取原理图，或读取原生 TXT/CSV BOM，完成分类、过滤、归一化和位号合并，所有结果写入一个 `BOM.xlsx`。当前流程不再对比人工 BOM，不加载学习规则。

## 打开与更新

在 Capture 的 Command Window 执行：

```tcl
source {C:/path/to/XKGJX/autoload/bomtoolMenu.tcl}
bomtool::dialog
```

控制台显示 `bomtool: 1.3.10 loaded`。旧窗口会自动刷新，仅保留两个操作：

1. **自动生成并整理BOM**：按指定七列读取当前原理图并生成工作簿。
2. **导入已有TXT/CSV（可选）**：选择已有原生 BOM 并生成工作簿。

安装小开工具箱发行版后，在原理图中按 **Alt+K**，展开“BOM整理工具”并双击“01 自动生成并整理 BOM”。插件会直接读取当前原理图，提示选择结果目录，然后自动生成并整理为 Excel；不再先打开工作台。也可在 Capture 命令窗口执行 `bomtool::dialog` 查看原有工作台。将 `autoload/bomtoolMenu.tcl` 复制到个人 `capAutoLoad` 目录即可随 Capture 启动加载。交付为单个 Tcl 文件，无需 Python、Excel 自动化、外部压缩程序或第三方 Tcl 包。

界面每次运行创建一个带时间戳的新目录，目录内仅输出一个 `BOM.xlsx`。表头冻结并启用筛选，封装 `0402` 按文本保存，数量按数字保存。原始文本即使以 `=` 开头也不会变成 Excel 公式。超过 Excel 单元格长度限制时会报错，不截断位号。

## 一个工作簿中的内容

| 工作表 | 内容 |
|---|---|
| 合并BOM | 序号、位号、数量、类别、规格参数、封装、备注 |
| 过滤清单 | NC、TP、MARK、螺丝孔，以及重复位号、缺字段等隔离原因 |
| 告警 | 两类封装告警、无法解析的值或后缀、缺失位号等 |
| 归一化明细 | 每个位号的类别、原始及归一化值/封装、分组键、过滤原因 |
| 原始BOM | 原始位号、值、封装、Option、DNP、MATERIAL、描述等输入字段 |
| 汇总 | 输入行数、位号数量、合并组数、过滤数、告警数、版本，以及分类前缀、特殊分类、封装归一、值解析、合并、规格补齐、过滤、告警、多单元器件和批量分类询问的详细规则 |

源行号是输入文本的物理记录起始行号，Capture 原生页眉可能使其大于数据序号。原理图直接导出时按数据记录顺序编号。

## 合并与过滤

先拆分每行位号，再按以下前缀分类；长前缀优先，避免 PCIE 被识别成 PC 电容、CHOKE 被识别成 C 电容：

| 前缀 | 类别 |
|---|---|
| C、PC | cap |
| AC + C0402/C0603 等电容封装 | cap |
| AR + R0402/R0603 等电阻封装 | res |
| AR + C封装 | 不按封装单独推断；符合连续批量候选条件时由导出前弹窗确认 |
| R、PR | res |
| L、PL、FB、CH、CHK、CHOKE | ind |
| D | diode |
| Q、PQ、QN | mos |
| U、PU、AU | ic |
| J、JGPIO、PCI、PCIE、SATA、USB、CPU、CPU_FAN | conn |
| RTCBAT | batt（电池座） |
| X/Y 位号且 Value 含 MHz | xtal（晶振） |
| 其余 | other |

明确用途优先：COM、CPU/CPU_FAN及明确连接器描述识别为连接器，LED识别为二极管，PFB识别为磁珠；Value 含 NTC 时按 NTC 热敏电阻解析并保留 B 值；RTCBAT 识别为电池座；其余按原有前缀兜底。

自动整理时，如果发现默认归为“其他”的位号存在同前缀、连续编号且至少 8 个，会在导出前弹窗让你逐组选择分类。选择结果仅用于本次导出，并影响分类、归一化和合并；取消则停止本次导出。工作簿“汇总”表列出默认分类、特殊规则、封装归一、值解析、合并规格、过滤及告警处理的详细说明，便于对照原理图命名规范。

```text
group_key = device_category:norm_footprint:norm_value
```

- `100nF / 100nf / 0.1uF` 归一为相同容量；`4K7 / 4.7kΩ / 4700` 归一为相同阻值。
- 电容键以 pF、电阻以 Ohm、电感以 nH 为基准；0Ω 的归一化值为 `0`。显示值使用 nF/uF、kOhm 等单位。
- 常见完整封装名 `0402/C0402/R0402/L0402/FB0402` 在归一化分组和“合并BOM”封装列中统一显示为 `0402`，类别始终保留在键中；这是有意的尺寸归一，原始写法可在“原始BOM”表查看。“汇总”表会列明此规则，供使用者对照本地命名习惯。复杂封装不猜测等效关系。
- **电容暂不区分 X5R、X7R、Y5V、C0G/NP0 等材质**，不要求小于 1 nF 使用 C0G，不选择或升级材质，不产生材质优劣告警。材质原文保存在原始 BOM 和原始值中。未识别的非标准后缀仍保留，避免误删功率、电流或型号等信息。
- 同组耐压取已知最大值，百分比容差取已知最小值；F=1%、J=5% 等自动识别。缺失的规格可以补入同组已有规格。
- “规格参数”是合并后的规格要求；没有原记录同时满足耐压和精度时，备注提示“需选择满足合并规格的器件”，不会虚构采购料号。
- 0Ω电阻使用 C 前缀封装可在电阻组内合并，并输出 `WARN-0OHM-FOOTPRINT` 位号告警。
- 非0Ω电阻使用 C 前缀封装，或电容使用 R 前缀封装，输出 `WARN-CATEGORY-FOOTPRINT`，合并行备注标为“需检查原理图库”。
- 不同类别绝不合并。缺值、缺封装和文本 BOM 中的重复位号被隔离，不静默去重。

NC 识别包括单独的 `NC`、`NC/...`、`.../NC`、独立 DNP/DNI/NS 标记、`Option=ns`、`DNP=YES/1` 及中文不焊标记。`NCV123`、`2X5_NC10` 等型号/缺针说明不会被当成整件不焊。电感值中的电流额定值及数字/M规格组合（如 `0.47uH_5A`、`1.0uH_7.5m_11A/17A`、`220nH/36A/80A_0.82m`）保留在分组键中，但不再误报为无法识别的后缀。

螺丝孔识别 BOSS/HOLE/MH 位号及 HOLE/NPHOLE 值或封装；测试点识别 TP/TESTPOINT、ICTPAD、PAD_TEST；Mark 点识别 MARK/FID/FIDUCIAL。多个过滤原因可同时保留。SP 短接焊盘不在这四类中，未标 NC 时保留。

数据库读取沿层级 occurrence 获取实际位号，读取有效及 variant 属性；相同位号的多单元器件仅在属性一致时去重，冲突则停止。数据库只读。1.0.1 的迭代器末尾 `AT_END` 修复已保留。

## 输入与命令行

支持 Capture `.BOM.txt`、TSV、CSV；不直接读取 XLSX。输入默认 UTF-8，可选 `cp936`（GBK）、`unicode`（UTF-16LE）。支持带表头或前三列为位号、值、封装的无表头数据；识别独立 MATERIAL、Voltage、Tolerance、DNP，以及原生 Dsecription 拼写。位号支持逗号、分号、空格和 `R1-R5` 范围。

```tcl
bomtool::moduleA {D:/path/native.BOM.txt} {D:/path/output}
bomtool::moduleA {D:/path/native.BOM.txt} {D:/path/output} cp936
bomtool::exportCapture {D:/path/output}
```

命令行固定输出目录中的 `BOM.xlsx` 会被更新；界面创建新目录。写入失败时保留原工作簿。

## 样例与验证

1.2.0历史样例为 `sample/current/BOM.xlsx`，仅由原生 TXT 生成：2348 个位号中，2060 个进入 269 组合并结果，288 个被过滤；16 个 0Ω使用 C 前缀封装的位号已告警。

`sample/module_a`、`sample/module_b`、`sample/input` 及旧核对说明是此前版本的历史结果，不参与当前执行。旧对比源码保留为历史参考，不再打包进交付脚本，重新加载时也会移除旧会话的对比及规则加载入口。

开发辅助 Python 只用于构建和验证，不在 Capture 运行链路中：

```powershell
python bomtool/build.py
& 'C:/OrCAD/Cadence/SPB_17.4/tcltk/bin/tclsh.exe' bomtool/tests.tcl
& 'C:/OrCAD/Cadence/SPB_17.4/tcltk/bin/tclsh.exe' bomtool/capture_tests.tcl
python bomtool/workbook_tests.py
python bomtool/run_sample.py
```

工作簿以纯 Tcl 写入标准 OOXML 和 ZIP；验证独立检查 ZIP CRC、XML、六张工作表、中文/特殊字符、前导零、公式安全及真实样例位号守恒。Capture 数据库适配器使用模拟契约测试，真实设计导出仍需在 Capture 会话验收。

## 1.2.0 更新：自动七列导出、精简中文结果

主操作改为 **自动生成并整理BOM**，一次完成读取原理图、按七列生成原生表、归一化及 Excel 输出；无需先在 Capture 的 BOM 对话框手动设置或导出。已有 TXT/CSV 导入仅作为可选入口。

软件内置以下表头与 Line Item Definition（`\t` 表示制表符），同时写入结果的“汇总”表供核对：

```text
Reference\tValue\tPCB Footprint\tDsecription\tOption\tEMPTY\tMATERIAL
{Reference}\t{Value}\t{PCB Footprint}\t{Dsecription}\t{Option}\t{EMPTY}\t{MATERIAL}
```

按这些字段读取数据库并生成工作簿中的“原始BOM”表，不修改 Capture 全局 BOM 对话框配置。`Dsecription` 优先读取用户指定的同名属性；该属性为空时兼容读取 `Description`。`EMPTY` 是实际读取并保留的属性列，不强制清空。DNP、独立耐压/精度属性仍用于处理判断。

“合并BOM”仅保留 **序号、位号、数量、类别、规格参数、封装、备注** 七列。分组键、原始数值、源行号等技术信息集中在“归一化明细”中。除用户指定的原生七列表头、器件原值及告警编号外，结果表头、类别、过滤原因、备注及窗口提示采用中文。

告警表包含“位号、问题类型、具体原因、本次处理、建议处理、源行号、原始值、原始封装、告警编号”。例如0Ω电阻使用C封装时，明确说明允许在电阻组内合并、不会并入电容，并建议核对焊盘和规范库命名；无法解析的后缀则说明原文被保留，避免误删功率、电流等规格。


## 1.3.0 更新：按用途解释器件值

已加入最新确认的规则，主流程及七列原生BOM格式保持不变：

- COM 优先归为连接器，LED 优先归为二极管；识别 CONN、CON_DIP、HDR、HEADER 等明确连接器描述，避免按 C 前缀误作电容。PFB 与 FB 都识别为磁珠前缀，LV 或 FB封装也能确认磁珠用途。
- CH/CHK/CHOKE 共模电感的型号是合法Value，完整保留型号，不强制解析成感值。不同型号仍分组。
- NC 前缀或后缀只表示不焊。解析其余值：`NC/2.2uF/16V` 得到2.2µF、16V，仍进入不焊接清单，原始值保留。
- 磁珠 `120ohm/100MHz,2.5A` 显示阻抗、测试频率及最大电流；A/mA、Hz/kHz/MHz换算统一。已识别为磁珠时，裸数字 `30` 表示30Ω。不补猜未填写的频率、电流，不丢掉这些条件去合并。
- LED 的 G/GREEN、R/RED 分别显示绿色、红色；不同颜色不合并。
- 电感 `/L444018` 识别为封装简码，不报未知后缀；在尚未确认等效关系前保留简码参与分组，不自动猜测PCB封装尺寸。
- `NTC_100K` 表示100kΩ NTC热敏电阻，归在电阻类别内，但通过归一化值中的NTC类型标识与普通电阻隔离。
- 电阻 `4.7K-04` 的 `-04` 代表0402：PCB封装为0402/R0402时可与普通4.7kΩ同组；若PCB封装为0603等其他封装，保留原记录并输出“值中的封装简码与PCB封装不符”告警。

分组键仍为 `器件类别:归一化封装:归一化值`。归一化值中保留磁珠、共模电感、NTC、LED等用途标识及必要规格，避免同大类内误合并。没有确认的非标准值不会盲目删除其后缀。

最新样例：`sample/v1.3.0/BOM.xlsx`。2348 个输入位号中，2060 个进入262组，288个过滤，告警从143条减少到39条。保留16条0Ω电阻使用C封装告警。`sample/current` 是旧版本历史结果。


## 1.3.1 更新：明确不焊接依据

“过滤清单”新增“不焊接依据”列，按实际触发字段记录：Value 中的独立 NC/DNP 等标记、Option=ns 等装配选项、DNP属性、中文不焊标记，或Capture/CIS中匹配设计不装配标记的属性及其值。同一记录有多个触发条件时全部列出。CIS状态派生的DNP=YES不会被写成用户原有DNP属性。

已有样例中，PR24、R430、C593、U6来自Option=ns，R6340来自Value=NC/0R。Value没有NC并不代表器件需要装配，仍须检查Option等字段。本工具展示原理图/BOM中的标记依据，不推断设计人员决定不焊的电路原因。

最新工作簿为 `sample/v1.3.1/BOM.xlsx`。结果数量保持262组、288个过滤位号、39条告警。

## 小开工具箱统一入口

小开工具箱安装版会自动部署当前 BOM 脚本以及其他自研 Capture 插件。按 **Alt+K**
打开统一编号窗口后双击 BOM 分组中的“自动生成并整理 BOM”，直接读取当前原理图并输出工作簿。插件不再单独显示 Accessories 菜单，也不再从工具箱右键单独卸载；卸载小开工具箱时可选择保留或删除全部自研 Capture 插件。


## 1.3.2 更新：Accessories点击入口

菜单入口先加载Tk 8.6，再创建界面，避免新启动的Capture尚未初始化Tk时窗口无法打开。使用与lceda2orcad一致的全局回调 `bomtoolMenuOpen`，接受Capture传入的附加参数；已有窗口被隐藏时执行恢复和置前，创建失败时销毁半成品窗口以便重试。

加载、菜单注册和点击日志使用 `bomtool:` 前缀。点击应出现 `open callback begin`，成功出现 `open OK`，失败出现 `open FAILED` 和堆栈；已有Tk时也会弹出错误提示。`netlocator: add ... menu OK` 仅表示其他插件在刷新菜单。

本机已安装1.3.2脚本。正在运行的Capture需重启或重新source脚本，然后执行 `bomtoolMenuOpen`。工具箱安装版和绿色包同步升级为1.6.3。

新增 `menu_tests.tcl`：用Capture自带Tcl 8.6.5从未加载Tk的状态测试菜单点击、附加回调参数、隐藏窗口恢复、异常清理及重试。该测试不替代真实Capture会话的最终点击确认。

## 1.3.3 更新：多分部器件属性差异

修复 `Capture: conflicting package sections for U5` 导致整份BOM中止的问题。同位号按一个物理器件计数；分部空字段用其他分部的非空值补齐。描述、EMPTY、材质差异保留首个非空值，并在告警页记录所有不同值及原始BOM行号。

Value、PCB Footprint、Option、Voltage、Tolerance、Part Number 的非空值冲突，或各分部焊接状态不同，标记 `WARN-PACKAGE-CONFLICT`。冲突位号暂不计入合并BOM，放入过滤清单待核对，其他器件继续处理。该隔离原因不表示不焊接。完成提示会明确显示待核对位号数；原始BOM页保留所有分部记录，便于核对后重新导出。没有冲突的差异记录为 `WARN-PACKAGE-METADATA`。

通过37项Capture适配模拟断言、125项核心断言和XLSX/真实样例回归。未取得对方U5原理图，具体冲突字段须通过新版告警确认。工具箱安装版和绿色包更新为1.6.5；另提供独立 `bomtool-setup-v1.3.3.exe` 供对方直接更新插件，安装后重启Capture。
