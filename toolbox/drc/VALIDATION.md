# 中文问题助手验证记录（2026-10-22）

环境：Windows、Capture CIS 17.4、Capture 自带 Tcl 8.6。

## v1.6.42 当前交付：自动保存和默认查看日志

- 运行检查前通过 Capture 原生会话 `MarkAllLibForSave` + `SaveDesign` 保存当前设计，检查返回状态和保存后修改标志；失败则停止，不进入 DRC。原生 `SaveDesign` 单独使用时不能保证完整清除已编辑页面的修改状态，实机验证后采用官方脚本同样使用的两步调用。
- 清除 markers 后再保存，网表引擎更新缓存后也保存，避免下一个步骤再次询问 ORCAP-1450。只写本次检查设计，不确认或保存其他项目。
- ORCAP-1805 默认回答 YES，采用 Capture 自带 `TclScript` 运行单行 `Menu ... | MessageBox "YES" "One or more errors or warnings were encountered."`。普通 Tcl `source/eval` 不会解释该管道重放指令，实机已验证必须使用 Capture 脚本读取器。临时控制文件在成功或失败后删除，没有外部应答程序或设计副本；每次仍只有一份原生 `.drc`。
- `test-output/prompts-safe/run.log` PASS：原生 GUI 新放置器件使设计 DIRTY=1，自动完成保存、DRC、网表及保存，DIRTY=0，无人工确认。发现 1 条悬空引脚和 1 条原生网表错误；干净样例检查问题数 0，预期的日志问询未出现时也正常结束。定位实选 `DboPortInstScalar` 后状态保持 current。
- 保存后打开页面可使 Capture 的 IsModified 从 0 变 1，而页面事务版本未变化；结果有效性不再单独使用该标志，避免导航被误判为改图。实际修改仍通过页面事务计数和最后事务号检测。
- 复测旧夹具时曾解引用保存前的部件对象，Capture 退出；夹具已改用原生 GUI 放置命令，并避免保存后复用底层对象。最终独立测试会话完成干净/有错两条路径，Capture 保持运行；插件定位使用对象 ID 重新选中。
- 六套测试全部通过：`tests.tcl`、`lifecycle-tests.tcl`、`netlist-tests.tcl`、`ui-tests.tcl`、`usability-tests.tcl`、新增 `save-tests.tcl`。覆盖保存顺序、保存失败不进入检查、单份报告、原生管道参数、临时控制文件清理，以及既有规则/定位/导出行为。
- v1.6.42 安装包和绿色版已构建，安装包 `/selftest` 返回 0，21 项全部通过。

## v1.6.41：定位、中文说明和结果有效性

- 引脚元数据补充原生 ID 和 `GetOffsetHotSpot` 连接端坐标；实机选择结果为 `DboPortInstScalar`，定位后结果状态保持 current。坐标采用放置、旋转后的绝对值，未使用相对 `GetHotSpot`。导线坐标定位使用原生折线点，实机实际选中 `DboWireScalar`。
- 子项显示具体器件引脚、网络的中文摘要。无图纸、实例、对象或坐标的行显示“无定位信息”；真实 Tk 鼠标双击回归继续通过，不增加定位按钮。
- DRC 和网表仅在可证明相同的图纸、实例、坐标或对象位置关联；两份原文和错误编号均保留。测试覆盖不同实例、不同坐标、重叠但不同位号、仅 DRC 及未知位置不误合并；仍严格保持 11 项规则。
- 检查完成后记录设计和页面原生事务版本、文件时间及大小；窗口每 1.5 秒以及定位/导出前核验。实机正常 `SetProperty` 编辑后页面事务从 1/0 变为 2/1，状态 stale，界面显示“设计已修改，结果待更新”。定位和缩放不使结果失效；切换项目可恢复，修改失效状态只在重新检查后清除。
- 实机完整 DRC + 网表日志 `test-output/usability-final/run.log` PASS：4 条单点网络、2 条无驱动源、2 条悬空引脚，网表错误 0；两个具体引脚及导线实际高亮成功，未保存修改被检测。只有 DSN 同目录一份 `test.drc`。使用独立测试夹具，未修改用户工程。Capture 这轮仍显示过原生 ORCAP-1805 提示查看日志，因此不宣称所有原生提示窗都已消除。
- `tests.tcl`、`lifecycle-tests.tcl`、`netlist-tests.tcl`、`ui-tests.tcl`、`usability-tests.tcl` 全部通过。新增覆盖具体引脚缩放、同位置两来源原文保留、位置隔离、无定位文字、旧结果阻止定位/导出、重新检查恢复、文件修改/移动和设计重新打开。
- v1.6.41 安装包和绿色版已构建，安装包 `/selftest` 返回 0，21 项通过，含最新单文件插件加载和安装/升级/卸载恢复。
- 限制：第三方 Tcl 绕过 Capture 正常事务的底层 setter 修改不保证触发版本变化；此类修改应重新检查。未逐类构造所有规则的实机缺陷，其他 Capture 版本和外部 DSN 引用仍需验证。

## v1.6.40：直接双击跳转与设计同目录报告

- 修复双击回调中的 `$tree identify row $y`：Tk 要求横纵坐标，旧调用实测报 `expected integer but got "row"`，导致事件中断。改为 `$tree identify row $x $y`，双击绑定阻止后续类绑定重复切换；分组自行展开/收起，叶子行在鼠标事件结束后按点击时的具体记录定位。
- 移除“定位选中问题”按钮。Tk 测试实际生成鼠标按下/释放事件验证文字列及位置列双击、精确定位点击行、分组展开和无位置错误处理；不再只直接调用定位函数测试。
- Capture 实机事件验证 PASS：双击 4 个位置行分别选中 U1B、U4A、U2A、U3A，对应 `/halfadd_A`、`/halfadd_B` 实例路径正确。日志 `test-output/double-click-live/run.log`。
- 原生报告直接保存为 DSN 同目录 `<设计名>.drc`，不再放进临时 `native/`。后续检查覆盖同名文件，导出 HTML/CSV 时不复制第二份 `.drc`。API 返回 `report_path`；配置仍完整恢复。
- 生命周期测试使用含空格的设计路径，验证一份同目录报告、临时工作目录不生成 `.drc` 或 `native/`，同时覆盖成功/失败清理。其他规则、网表错误汇总、分层复用和导出回归通过。
- v1.6.40 安装包及绿色版已重新构建，安装包 `/selftest` 退出码 0，21 项全部通过。

## v1.6.39：DRC中文增强版与网表错误

- 名称统一为“DRC中文增强版”，插件集合改成可直接双击的一项；双击自动开始，集合最小化，结果窗口置顶。真实 Tk 自动化验证一次启动只调用一次检查，集合为 iconic，结果窗口 normal、topmost。
- Capture 实机完整入口验证 `test-output/enhanced-live/launcher.log` PASS：从集合执行入口后自动完成 DRC 和网表，原生 DRC 调用计数 1、一份 `.drc`、4 条网表错误，集合 iconic，窗口标题“DRC中文增强版”、topmost=1。
- 仅忽略原生 `ORCAP-1829` / pin type conflict 消息，保留 `ORCAP-1608` 无驱动源。原生 DRC 仍为一次调用、一份原生报告；不增加独立 DRC 规则。
- DRC 后使用 Capture 内部 `orPstSwp64.dll` 的 `orExecutePst` 和当前 `DboSession` 输出 PCB 网表。实机正常样例得到 `pstchip.dat`、`pstxprt.dat`、`pstxnet.dat`，返回码 0。只写本次结果目录，不调用板更新或外部网表程序。
- 实机配置缺失封装属性，原生返回 4 条 `ORCAP-36002` 与 1 条 `ORCAP-36018` 汇总；提取 4 条具体错误，按同一原因归为 1 组，省略重复汇总。根据 occurrence 位号匹配到两个复用实例，4 条逐一定位均实际选中器件，不把其他实例额外计入。原生日志的 `#1 ERROR(...)` 编号前缀已覆盖解析。
- 结果中的 `netlist_error` 是网表操作错误标识；未新增 DRC 判定。没有位置的错误禁用定位，网表失败仍保留已完成的 DRC 结果。HTML/CSV 包含网表错误，导出时同时复制原生网表及日志。
- `tests.tcl`、`lifecycle-tests.tcl`、`netlist-tests.tcl`、`ui-tests.tcl` 通过。包括网表返回失败、原生抛错、输出缺文件、抑制弹窗选项恢复、具体错误归纳、保留无驱动源、启动与窗口状态。
- v1.6.39 安装包和绿色版已构建；安装包自检退出码 0，21 项全部通过，包括最新插件载荷和安装/升级/卸载恢复。
- 实机日志 `test-output/enhanced-live/run.log` 最终 PASS；正常样例 DRC + 网表约 4 秒。此轮窗口采样观察到原生可取消 DRC 进度窗；没有逐规则的 11 个配置窗口。不能将 v1.6.38 的“未发现新弹窗”样例结论视为所有调用均不显示原生进度。其他 Capture 版本尚未实测。

## v1.6.38：一次原生 Batch DRC

- 直接检查当前设计，一次配置同时启用指定的 11 项规则，只调用一次 `Menu "PCB::Design Rules Check"`，只生成一个原生 `.drc`；不创建临时 DSN/OPJ，不拼接 11 份报告。
- 缺陷样例包含根图纸及两个复用 HALFADD 实例。实机共检出 10 条诊断：4 条单点网络、2 条无驱动源、4 条悬空引脚。原生调用计数为 1，总耗时 4666 ms；窗口监测仅发现已有 Capture 主窗口，未发现新增检查弹窗。此耗时仅代表该样例。
- 根图纸、`/halfadd_A`、`/halfadd_B` 三个位置均实际选中对应器件；两个复用实例分别验证。检查结束后 DRC markers 为零，完整原生 DRC 配置和 `SuppressMsgBoxInTcl` 均恢复。
- 实机独立验证原生 marker 删除 API：根图纸和子图纸共 4 个预置标记全部删除。本版按用户要求删除包括原有标记在内的所有 DRC markers。Capture 自身可能按工具设置保存设计，插件不额外调用保存，也不清除修改标记。
- `tests.tcl`、`lifecycle-tests.tcl`、`ui-tests.tcl` 均通过。覆盖严格 11 项配置及其他规则禁用、矩阵保留、综合报告分类、未识别诊断保留、单次调用和单文件、失败时清理及配置恢复、清理时先释放迭代器、中文分组/搜索/定位回调与 HTML/CSV。
- 最终 v1.6.38 安装包和绿色版已重新构建；安装包 `/selftest` 退出码 0，21 项全部通过，包含最新 DRC 插件载荷及安装/升级/卸载恢复。
- 实机日志：`test-output/single-batch-final/run.log`；窗口监测：`test-output/single-batch-final/windows.log`。剩余缺陷类型未逐类构造实机样例，其他 Capture 版本及外部 DSN 引用尚未验证。

以下为历史验证记录；临时设计副本、11 次检查、保留原标记等旧行为均已取消，不代表当前实现。

## v1.6.36 弹窗修复

原因：v1.6.35 为检查副本仅复制 DSN，直接 `Open inspection.dsn` 会在默认 Capture 配置下触发“Select Project Type”。现在同时生成带 `ProjectType PCB` 和相对 DSN 引用的最小临时 OPJ，直接打开 OPJ；不再要求选择项目类型。

`tests.tcl` 新增回归：全新副本目录自动包含 PCB 项目，DSN 字节保持一致，Capture 打开目标确认为 OPJ。规则和 Tk 界面测试通过；v1.6.36 安装包自检 21 项通过。实机采用全新临时目录和单独启动的 Capture，已完成无错误样例的 11 项检查，未出现项目类型弹窗。

## v1.6.35 基础功能记录

- 官方 PCB-Layout/FullAdder 已保存样例：通过临时 DSN 副本完成 11 项原生检查，零诊断；检查后返回源项目。识别 `/`、`/halfadd_A`、`/halfadd_B`，两个子实例引用相同 HALFADD 定义。
- 缺陷样例：只在测试样例中移动根图纸一个器件，并预先创建 2 个原生 warning markers 作为保留验证。助手在另一临时副本完成 11 项检查，检出 2 条 `ORCAP-1600` 单点网络、2 条 `ORCAP-1831` 悬空引脚。HTML/CSV 对应 4 条记录，block 名、位号、引脚和网络信息与原始报告一致。
- 缺陷样例检查前后，源 DSN 的 CRC32 均为 `2676738103`，原有 marker IDs 均为 `{2546 2548}`；未保存或改写源文件，未清理原有标记。悬空引脚定位实际选中根图纸器件。
- 复用实例实机定位：`OPage` 分别打开 `/halfadd_A`、`/halfadd_B`，通过 `GetInstanceOccurrence` 确认当前路径，分别选中同一符号定义在相应实例中的对象。两次定位后设计 `IsModified` 均为 0。
- 修复原生诊断激活其他窗口后项目选中失败的问题：先用 `ui::PMActivate` 激活完整 OPJ 路径，再选择 DSN；选中后核对设计完整路径，不把错误项目送去检查。
- 运行前后 `capGetDRCConfigData` 解析结果完全一致，包括 ERC Matrix；临时配置回调已恢复。
- `tests.tcl` 通过：严格 11 项、禁用其他 Run* 规则、矩阵保留、复用实例路径、flat/local 网络匹配、多单元电源物理引脚去重、白名单边界、失败时回调恢复、HTML 转义和 CSV 多行字段；新增中文原因、同网络归纳、实例隔离、搜索、精确去重、拒绝检查未保存设计、激活正确项目和拒绝错误项目测试。
- `ui-tests.tcl` 使用真实 Tk 窗口通过：共性分组、父子行、选中说明、子项定位回调、原生详细信息、搜索和空结果。多位置组不任意定位第一个对象。
- 独立 Python 标准 JSON/CSV 读取通过：矩阵为嵌套数组对象，CSV 的引号、多行和 UTF-8 BOM 正常。
- 发布单文件插件加载测试通过，GBK 系统源文件编码下仍输出正确中文 HTML。
- 最终 v1.6.35 安装包自检 21 项通过，包括最新 DRC 嵌入载荷、Capture 插件安装/升级/卸载恢复。安装包和绿色版已重新构建。此前工具箱布局回归 108 项通过。
- 工具箱完整自检为 66 通过、3 失败。失败项均位于原有 Cadence 目录探测：空壳 `tools/bin` 被接受、错误手动目录未被拒绝、拒绝后保留原设置断言失败。本次未修改目录探测逻辑。

最新实机日志：`test-output/assistant-probe/defect-final.log`、`hierarchy-locate2.log`，报告：`test-output/assistant-probe/final-report/`。未逐一构造剩余 9 类缺陷，也未验证外部 DSN 引用或其他 Capture 版本。电源单点白名单目前通过对象模型单元测试验证，未构造专门的实机电源单点样例。以上记录只说明已验证的样例，不代表所有类型缺陷均已覆盖。

开发者可在关闭 Capture 后执行 `smoke.ps1`，将官方样例复制到独立测试目录后启动 Capture。测试脚本移动样例器件、创建并删除测试标记，验证单次批量检查、单报告、成功/失败清理、根图纸和复用实例定位。该测试夹具的副本不属于插件运行流程。脚本会拒绝在已有 Capture 进程时启动，避免命令行被转发到现有会话。当前最新实机证据以上方 v1.6.38 日志为准。
