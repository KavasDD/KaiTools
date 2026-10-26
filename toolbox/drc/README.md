# Capture DRC

小开工具箱 v1.6.42 的 Capture 内部 Tcl 插件“DRC中文增强版”。交付文件为 `autoload/drctoolMenu.tcl`，不需要 Python、不读取 DSN 文件结构、不依赖外部解析库。本版自动保存当前设计，用一次原生 Batch DRC 同时检查指定的 11 项，忽略引脚电气类型冲突，保留无驱动源；随后调用进程内原生 PST 引擎输出 PCB 网表并汇总错误。完成或失败后删除 DRC markers，不创建或打开临时设计。

## 使用

通过工具箱安装或更新 Capture 插件，重启 Capture，打开设计，按 `Alt+K`，双击 `DRC中文增强版` 即开始检查，无需再次点击。插件集合自动最小化，结果窗口前置。未保存的修改也直接参与 DRC。也可在 Capture Command Window 中执行：

```tcl
source {C:/path/to/XKGJX/autoload/drctoolMenu.tcl}
drctoolMenuRun
# 无交互检查，.drc 自动写到 DSN 旁；HTML/CSV 需调用 writeReports：
::xiaokai::drc::run {D:/reports} $::xiaokai::drc::powerWhitelist
```

窗口只显示有问题的项，不展示通过的规则。按共性原因和受影响网络/器件归纳，双击分组展开；双击展开后的器件文字或位置列，直接打开对应图纸并定位，无需再按按钮。单击显示中文原因和建议，英文和 ORCAP 编号收在“原生详细信息”。分层实例分别定位；一个组内有多个位置时不会随意跳到第一个位置。搜索支持位号、网络、路径和问题描述。

子项直接写明器件引脚或网络，例如“U12 的 3 脚未连接”“网络 RESET 没有驱动源”。可确定单个引脚时，双击选中原生引脚对象，并按旋转和放置后的连接端坐标居中放大；只有原生坐标时放大到该处并尝试高亮附近导线。没有可用图纸、实例、对象或坐标的行显示“无定位信息”。DRC 与网表消息只在图纸、分层实例和位置能够一致匹配时关联展示，保留两份原文；不根据同名网络合并不同位置。

窗口每 1.5 秒读取原生页面事务版本及文件状态，定位和导出前也会核对。正常编辑、重新打开设计、源文件保存或移动后显示“设计已修改，结果待更新”，保留旧结果供阅读，重新检查后恢复定位和导出。切换项目只提示切回，不会使旧结果永久失效。第三方 Tcl 直接调用底层 setter 且不更新 Capture 事务状态的修改不保证被检测，此类脚本修改后应重新检查。

没有问题时只显示“检查完成，未发现问题”。网表只显示 ERROR/FATAL，共性错误归纳；失败不会丢弃 DRC 结果，无法输出或缺少完整输出也显示为问题。提供图纸和实例位置的网表错误支持定位，无位置的错误只显示详细信息。每次检查直接将原生 `<设计名>.drc` 保存到 DSN 所在目录；结果显示后点击“导出报告”，才生成 `drc.html`、`drc.csv`，并复制 `netlist/` 网表及日志。导出不再额外复制 `.drc`。HTML 只统计非零问题；CSV 保留 UTF-8 BOM、标准双引号和多行字段。

固定字段：`rule_id, rule_name, hierarchy_path, sheet_name, refdes, net_name, pin_info, message`。`message` 保留原生错误编号、描述和坐标；不适用或原生报告未标识的对象字段留空。根路径为 `/`；复用实例分别使用 `/halfadd_A`、`/halfadd_B` 等路径。

网表错误使用 `rule_id=netlist_error` 标识操作结果，不是新增 DRC 规则。原生网表引擎可能返回封装相关错误，这些错误也会显示。网表保存在本次报告目录的 `netlist/`，不覆盖工程原有网表、不创建或更新 PCB 板。使用设计配置的 Allegro 配置文件、合并属性字符串与 Part Type Length；未设置时使用安装目录的 `allegro.cfg` 及原生默认参数。当前已验证 Capture CIS 17.4；原生接口缺失时会显示网表未能输出，不会误报通过。

## 规则与原生行为

一次启用指定的 11 个原生 Batch DRC 选项，只调用一次原生检查。设置 Entire Design、Occurrences，保留设计当前 ERC Matrix，因此驱动源与冲突判定、隐式电源连接、No Connect 标记、总线与分层端口均由 Capture 处理。检查结束后只遍历一次 occurrence、pin、schematic net、flat net 对象补全报告字段。利用原生报告分节和消息编号归类诊断，不再逐规则重复检查。

原生“无驱动源与引脚类型冲突”为同一个选项，因此仍启用它，结果中过滤 `ORCAP-1829` 及原生 pin type conflict 消息；`ORCAP-1608` 等无驱动源提示继续保留。原始 `.drc` 保留原生内容。

配置由 Tcl 回调直接提供，跳过原生配置对话框；检查期间暂时启用 Capture 的 `SuppressMsgBoxInTcl`，结束后恢复。检查前通过原生 `DboSession MarkAllLibForSave/SaveDesign` 保存当前设计，免去 ORCAP-1450 保存确认。ORCAP-1805 询问是否查看错误/警告日志时，使用 Capture 原生 `TclScript` 对话框重放默认回答 YES；检查完成后中文结果窗口前置。重放只匹配该日志问题，不自动确认其他未知提示。只调用一次原生检查，不会逐规则弹出 11 个窗口；原生可取消进度仍由 Capture 显示。

| rule_id | 原生检查选项 |
|---|---|
| single_node_nets | Check single node nets |
| drive_source_pin_conflict | Check no driving source and Pin type conflicts |
| duplicate_net_name | Check duplicate net names |
| hier_port_conn | Check hierarchical port connections |
| unconnected_bus | Check unconnected bus nets |
| unconnected_pin | Check unconnected pins |
| power_pin_visibility | Check power pin visibility |
| convert_view_sync | Check normal convert view sync |
| pin_group_assign | Check incorrect Pin Group assignment |
| missing_pin_num | Check missing pin numbers |
| name_prop_consistency | Check name prop consistency |

不会启用 PCB footprint 属性/路径、电源地短路、高速属性语法、零引脚器件规则，也不会添加其他独立判定。名称检查遵循对应原生选项：跨页或跨层合法相连的同名网络不被额外当作重名错误；name prop 使用原生层次 block 名称属性一致性选项。

直接在当前设计调用 Capture 原生 Batch DRC。检查期间可能生成 markers，结束后通过原生 `DboPage DeleteERC` 删除所有图纸的 DRC markers；按 schematic 定义遍历，复用实例共用图纸不重复删除。中途失败也执行清理并恢复检查配置；清理失败会明确显示错误，不报告检查成功。No Connect 符号不是 ERC 对象，不在删除范围。

原先已有的 DRC markers 也会被清除，这是本版直接检查后清理 markers 的行为。运行检查即包含保存：检查前保存，清除 markers 后再次保存，网表输出引起的缓存更新也在完成后保存。只保存本次检查的设计；不手动清除修改标志，保存失败会停止并显示原因。中文列表保留本次诊断，双击定位不依赖 markers。Capture 打开已保存的页面时可能再次设置已修改标志；结果有效性按实际页面事务版本核对，避免仅导航就要求重新检查。

原生自动应答使用一个临时单行 Tcl 控制文件，调用结束后删除；检查逻辑仍在 Capture 进程内，不启动外部应答程序，不创建 DSN/OPJ 副本，不增加 `.drc` 文件。

每次检查只生成一份 Capture 原生 `<设计名>.drc` 文件，不拆分或拼接 11 份报告，直接与 DSN 放在同一个目录。下次检查覆盖同名 `.drc`；目录无法写入时会显示失败，不改存其他位置。API 返回的 `report_path` 为该文件完整路径。网表和排错日志仍放在本次工作目录；不生成 DSN/OPJ 副本。设计变化后旧结果保留供查看，重新检查后恢复定位和导出。外部 DSN 引用和其他 Capture 版本仍需验证。

遇到尚未识别的原生诊断格式时，保留原生内容并显示“原生检查发现问题”，其规则元数据留空；不会遗漏该问题、伪报通过或额外执行规则。

## 电源单点白名单

默认无豁免。在 Capture Command Window 中设置列表，每项为属性选择器字典，支持不区分大小写的 Tcl glob：

```tcl
set ::xiaokai::drc::powerWhitelist [list \
    [dict create net_name VCC refdes U1* pin_number 14] \
    [dict create hierarchy_path /power_block net_name VDD*]]
```

支持 `hierarchy_path, sheet_name, refdes, net_name, pin_name, pin_number`。同一项的条件必须全部匹配。只对 `single_node_nets` 生效，且通过原生 flat net 确认全网只有一个不同的物理引脚、其 pinType 为 Power 后才豁免；不能根据网络名猜测电源。原始报告保留被豁免诊断，HTML 显示豁免数量。

## 开发与验证

`core.tcl` 为规则配置、原生报告读取和报告渲染；`presentation.tcl` 为中文解释和归纳；`capture.tcl` 为 Capture 当前设计检查、标记清理及定位适配；`ui.tcl` 为 Tk 窗口。修改后执行 `python toolbox/drc/build.py` 生成单文件插件；载荷用 UTF-8/base64 包装，以兼容 Capture 系统源文件编码为 GBK 的环境。

```powershell
& 'C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe' toolbox/drc/tests.tcl
& 'C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe' toolbox/drc/lifecycle-tests.tcl
& 'C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe' toolbox/drc/ui-tests.tcl
& 'C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe' toolbox/drc/netlist-tests.tcl
& 'C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe' toolbox/drc/usability-tests.tcl
& 'C:/orcad/Cadence/SPB_17.4/tcltk/bin/tclsh.exe' toolbox/drc/save-tests.tcl
```

单元测试覆盖单次批量配置严格启用 11 项、禁用其他规则、原生分节及消息分类、矩阵序列化、实例隔离、电源白名单、报告转义和消息框选项恢复；生命周期测试断言保存顺序、保存失败不进入检查、仅调用一次原生检查、仅一个报告路径，以及根图纸和子图纸标记删除、正常及失败路径清理、恢复设置、不创建副本。保存测试核对原生写入失败、仍有未保存修改、会话缺失及资源释放。真实 Tk 测试覆盖分组、定位回调、搜索和空结果。未对全部 11 类缺陷逐类构造实机样例，其他 Capture 版本仍需实际验证；缺少原生配置入口时会明确失败。实机验证详见 [验证记录](VALIDATION.md)。
