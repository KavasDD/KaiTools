# Allegro 小开 SKILL 工具箱

在 Allegro 中按 **Alt+K** 打开“小开 SKILL 工具箱”，也可以点击顶部“小开工具箱 → 打开 SKILL 工具箱（Alt+K）”或输入命令 `xk_skill`。

v1.6.87：按当前保留的功能连续编号，同步集合窗口、主工具箱说明和适配窗口标题。菜单栏改为包含可执行子项的标准弹出菜单，修复点击无响应。命令和检查算法保持不变。下方旧版本记录使用当时的编号。

| 分类 | 当前编号与功能 |
| --- | --- |
| 查看类 | A1 元件列表与定位；A2 现有 DRC 浏览与定位；A3 快速切换格点；A4 快速切换层显示；A5 mm／mil 单位换算；A6 焊盘与孔径高亮；A7 修改库路径；A8 生成元件高度文字；A9 一键设置光绘与层叠颜色 |
| 丝印与文字整理 | B1 文字调整与居中；B2 丝印导出与导入 |
| 过孔与走线修改 | C1 过孔修改网络 |
| 检查类（Check） | D1 悬空线／过孔／孤岛检查与处理；D2 未扇出 SMD 引脚检查；D3 焊盘与走线间距检查；D4 SMD 与通孔引脚间距检查；D5 缺少锡膏开窗检查；D6 缺少阻焊开窗检查；D7 缺失丝印位号检查；D8 丝印重叠检查（增强版）；D9 丝印位号交叉检查 |

原 C1～C4 已撤下，仅在 `originals` 保留原件；新版 C1 是原版 `cvia` 过孔改网工具。

v1.6.84：B3 完成显示层切换与高亮后，将可见板图居中并缩放到窗口内，再打开报告。仅调整视图，不修改文字大小、位置或封装。

v1.6.83 修复 B3 检查完成后自动打开报告（含零项结果），报告文件保留为 `no_refdes.log`。

v1.6.82 暂时搁置 B7、B8，其余按反馈更新 B 组工具，保留编号，双击名称运行：

- **丝印与文字整理**：B1 文字调整与居中、B9 丝印导出与导入。
- **检查类（Check）**：B3 缺失丝印位号检查、B5 丝印重叠检查（增强版）、B6 丝印位号交叉检查。B2 未接入，B4 已从集合和安装清单移除。B3 直接显示并高亮缺位号的元件，补充显示封装轮廓层。

B7、B8 已从工具箱及默认加载清单撤下，原件和适配代码保留在 `originals`、`deferred`，后续再处理。跨命令双击恢复尚不可靠，旧命令仅提示已搁置。详情见 [待处理记录](deferred/README.md)。

B9：先在板图中框选元件或丝印元素，再打开窗口点击导出，选择路径后立即导出选中范围；未选中不导出。支持文字、直线、圆、圆弧，保持原版文件格式。原版导入会移除全板 FIXED／封装 FIXED_PRIVATE，并替换文件所列层的全部旧丝印，局部导出文件不能恢复其它元件的丝印；窗口明确提示并在导入前确认。取消选择或确认不会解除固定。测试板 19,247 条记录完整回导后逐条一致。原命令 `silkin`／`silkout` 保留，集合入口为 `xk_silk_io`。

B1 使用原有简体中文界面，默认层仍为 Assembly；颜色行与分组留出间距，右上角 × 关闭并完成原版清理。B5 使用增强版算法，界面汉化并隔离内部函数和变量，避免与其他工具的 `cnt`、`layer`、`form` 等变量冲突；B6 仅将 Windows 不支持的 `rm` 清理语句替换为文件 API。原始文件保留在 `originals`，构建校验 `b-tools-hashes.json`；加密 B9 安装副本逐字节不变。详见 [本轮验证](../../out/allegro-review/b-feedback-81/验证.md)。

v1.6.73 的AI命令辅助使用模型工具循环：模型根据完整要求、当前板图与真实执行结果选择后续指令，同一窗口显示每步调用和结果。当前已接入器件定位与打开现有工具；具体布线、布局和工具内参数设置仍需手动完成。板图切换、原生失败或取消停止后续操作，失败不再作为成功结果交给模型。API设置继续共用主工具箱左下角入口。

v1.6.56 为集合窗口增加 **赤焰走线 / 曜黑弧光** 两款黑红皮肤，右上角下拉框即时切换并保存。集合窗口改由现有辅助程序显示，工具命令通过只接受已列出命令的 IPC 分发交回 Allegro；分类、序号、双击执行、Ctrl+F 与 Alt+K 保留。A1、A2 辅助窗口使用同套黑红颜色，其他原生 SKILL 工具窗口维持原界面。升级后重启 Allegro。设置保存在 `%LOCALAPPDATA%\XiaokaiToolbox\skins.ini.allegro`，可从主工具箱的「外观 / 皮肤」统一选择。直接运行辅助程序并传入 `--preview` 可预览集合外观，此时不会执行板图命令。

v1.6.55 修复 A3 格点窗口初始化、右上角关闭时空字段被传给 `atof` 的错误，仅实际格点按钮进入原转换算法。双击和快捷键监听改用独立消息线程，IPC 写入通过队列处理，避免 DRC 列表加载或 Allegro 忙碌导致 Windows 移除监听。IPC 支持拆分和合并的消息，每项请求独立捕获异常，后续工具仍可执行。升级后重启 Allegro 加载新辅助程序。

分类按“查看类 → 丝印与文字整理 → 过孔与走线修改 → 铜皮、布局与板图辅助 → 生产输出与转换 → 检查类（Check）”排列。默认折叠，点击分类展开子项，双击工具名立即运行；选中工具后也可点击“执行”。

已安装入口：

- 查看类按序号列出：**A1 元件列表与定位、A2 现有 DRC 浏览与定位、A3 快速切换格点、A4 快速切换层显示、A5 mm／mil 单位换算、A6 焊盘与孔径高亮、A7 修改库路径、A8 生成元件高度文字、A9 一键设置光绘与层叠颜色**。
- 过孔与走线修改：**过孔修改网络**，运行原版 `x_change_via_net.il` 的 `cvia`：在板图中点选或框选过孔，右键 **Done**，再从原生网络列表选择目标网络。固定过孔跳过并记录日志。
- 检查类（Check）：**悬空线／过孔／孤岛检查与处理**，同一窗口三页结果支持定位、刷新和删除，不提供修改网络。底部仅“刷新、删除”，通过右上角 × 关闭。

检查来自 `quick_danglings.il`，原件逐字节保留在 `originals/quick_danglings.il`。`build-danglings.py` 校验原件 SHA-256 后生成 `skill/xiaokaiDanglings.il`，独立函数名避免重名。扫描、定位和删除沿用原算法；适配器修正原孤岛删除分支两处拼错的表单变量 `nv_DanglingForm1`，共享删除按钮通过显式动作参数调用对应原分支。检查入口为 `xk_dangling_check`。移除原来的 `axlUIWDisableQuit` 调用，启用系统关闭按钮。执行工具后主工具箱保留显示。其他分类暂为空，后续按选择加入。

过孔改网独立使用 `x_change_via_net.il`。原文件逐字节保留在 `originals/x_change_via_net.il`，SHA-256 为 `00b329799be936189254ad212fab4288b92790abac7efb76972095dbf3751641`。安装副本仅删除空选择判断 `when( all == nil then` 中多余的 `then`，避免未选过孔时出现 `unbound variable - then`；其余内容与原件一致。主入口为 `cvia`，旧别名 `xk_via_change_net`、`xk_dangling_vias` 兼容调用同一个原函数。

A1～A8 在 v1.6.52 加入；v1.6.54 按用户反馈适配以下行为。原件保留在 `originals`，构建时检查 SHA-256，安装副本和新增适配器承载改动。

- A1：Ctrl+F 打开；筛选框默认空白，按位号片段实时匹配，例如 `24` 匹配 C24、C244。移除刷新按钮，单击结果才定位、高亮，并显示元件所在面的 silk、pin、via、etch。实时输入使用随附辅助程序的窗口，数据库读取和定位由 Allegro 内 SKILL 执行。
- A2：按电气间距、连接与走线、孔与焊盘、封装与装配、阻焊与钢网、丝印与机械、禁布与边界、其他归类，支持类别、层和具体类型交叉筛选，单击记录定位。默认显示全部，选择具体类型后可勾选“暂不关注此类型”；勾选“显示暂不关注的类型”可恢复显示并取消标记。偏好保存在安装目录的 `xiaokai_drc_unfocused.dat`，关闭、重开和刷新后保留。只浏览已有 DRC，不运行新检查。
- A4：固定十个可改名的配置 P1～P10，每行独立保存、读取，保存不关闭窗口。中文界面统一行距；最后一行层开关与其他行等距。沿用原层列表和显示切换算法。配置保存于 `HOME/pcbenv/xiaokai_view_profiles.dat`，不执行配置数据。`ssq` 打开完整版，`sq` 打开迷你版。
- A6：只保留 `highlight_padstack.il` 列表版，可拖动边框缩放，列表随窗口变化。
- A7：打开 PSMPATH、PADPATH、DEVPATH 编辑窗口，可填写目录或点击添加目录；先校验三项输入，再通过文件 API 所需的单字符串格式写入用户 env，立即生效。支持带空格、尾部反斜杠的路径；未闭合的引号会提示补齐，避免写入损坏的配置。
- A8：独立读取元件 PCB 封装高度属性，无需原理图工具。写入 HEIGHT_TEXT_TOP／BOTTOM 层，重复运行删除并重建这两层文字；显示对应层后查看结果。

工具箱通过右上角 × 关闭，运行工具后保留显示。

选择 A9 后，对当前板文件依次执行：

1. 启用原版 `film_reorder.il` 使用的 `film_nosort` 设置，关闭字母排序。
2. 调用原版 `Auto_artwork.il` 的 `Autoart()`，删除旧 Film 并按原逻辑重建。
3. 调用原版 `Quick_ColorS.il` 的 `Quick_ColorSet()`，应用原配色。

生成后的 View 顺序为铜层、DRILL、PASTEMASK、SOLDERMASK、SILKSCREEN、ADT、ADB、ALL。无需额外打开手动排序窗口。原始 `film_reorder` 命令仍可用于手动调整。

三个工具脚本与 `D:\selfsoftware\pcbenv` 中原文件逐字节一致，只新增了工具箱界面和组合入口。光绘功能设置 Film，不直接输出 Gerber；执行后保存 BRD 才会持久保存板图修改。

## 安装

小开工具箱 v1.6.49 起，安装版默认安装已完成的 SKILL；v1.6.51 将“过孔与走线修改”类的改网入口恢复为原版 `cvia` 交互流程，形成上述三项功能。无需单独运行下方脚本。主工具箱“Allegro 工具”页下方显示已安装功能，单击查看说明和安装位置，布局与 Capture 插件区一致。重启 Allegro 后按 Alt+K 使用。绿色版不会自动安装 SKILL。

本机已安装到 `C:\orcad\Cadence\SPB_Data\pcbenv`。重启 Allegro 后生效。

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\selfsoftware\toolbox\allegro\install.ps1
```

安装器把三个光绘相关原脚本、`x_change_via_net.il`、`xiaokaiDanglings.il`、`xiaokaiAllegroMenu.il` 和 `xiaokaiAllegroHotkey.exe` 放入 `HOME\pcbenv`，并合并 `allegro.ilinit` 中的小开启动块。保留已有启动内容和编码，不复制整套原始 env。备份位于 `HOME\pcbenv\xiaokai-allegro-backup`。

Allegro 17.4 的 Alt+字母菜单入口只会选中菜单，因此 Alt+K、Ctrl+F 和工具名双击由随 Allegro 启动的辅助进程接收，通过 IPC 通知 Allegro。快捷键只在所属 Allegro 主窗口或小开工具箱处于前台时响应；辅助进程随所属 Allegro 退出。升级时保留旧进程使用的辅助程序映像，重启后加载新版本。

指定其他 HOME 使用 `-HomeDirectory`。移除自动加载使用 `-Uninstall`，随后重启 Allegro。

## 构建与验证

界面编辑源为 `src/xiaokaiAllegroMenu.il`、`src/xiaokaiViewTools.il`（UTF-8）。构建生成使用 GBK 八进制转义的 ASCII SKILL，并编译 Windows x64 辅助程序：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File D:\selfsoftware\toolbox\allegro\build.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File D:\selfsoftware\toolbox\allegro\test\installer.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File D:\selfsoftware\toolbox\allegro\test\gestures.ps1
```

Allegro 17.4 S035 已在六层板副本上验证启动加载、Alt+K 直接打开窗口、组合工具执行、16 个 Film、配色与 View 顺序。分类树另已验证默认折叠、点击展开、子项说明及执行按钮、查看类首位与检查类末位。界面和结果见 `../../out/allegro-review/category-test`。原始板文件不参与测试写入。

此前改写过原脚本的 1.0.0 版本已停用，归档在 `archive/revised-1.0.0`；其测试结果不代表当前原版。
