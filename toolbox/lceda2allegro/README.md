# 立创 PCB 封装一键转 Allegro

与「Orcad内直接放置立创元件」配套的独立工具。输入立创商品编号后，读取立创 EDA 标准版元件的 PCB 封装数据，调用本机 Allegro 生成原生 `.dra`、`.psm` 和 `.pad` 文件。

## 使用

1. 在小开工具箱的 **库与转换** 页打开 **立创 PCB 封装一键转 Allegro**，或直接运行 `toolbox/out/立创封装转Allegro.exe`。
2. 输入编号，例如 `C25804` 或 `C2040`，选择输出目录。按需勾选 **同时生成 AD 封装**、**同时生成 PADS 封装**，再点击 **一键转换**。两个选项彼此独立，每次打开窗口默认均不勾选；可以只选其一或两个都选。可使用「粘贴编号」，也可勾选完成后在 Allegro 中打开封装。
3. 将生成的封装子目录同时加入 Allegro 的 **psmpath** 和 **padpath**。保留同一目录内的 `.dra`、`.psm`、全部 `.pad` 和配套 `.ssm` 文件。
4. 已经用 OrCAD 插件放置的元件，其 `PCB Footprint` 名称与这里生成的名称一致：沿用立创封装名，仅将小数点替换为 `d`。例如 `LQFN-56_L7.0-W7.0-P0.4-EP` 对应 `LQFN-56_L7d0-W7d0-P0d4-EP`。

勾选 AD 后，封装目录中的 `AD/封装名.PcbLib` 可用 Altium Designer 打开。勾选 PADS 后，在 PADS Layout 的 File → Library 中选择目标库并通过 Import 导入 `PADS/封装名.d`（PCB Decals）。附加格式直接生成，不要求安装 AD 或 PADS；主转换仍需本机 Allegro 和可用许可证。

每个封装输出到独立子目录。已有同名输出会提示更换目录，不会覆盖原封装。窗口记住输出目录和 Allegro 程序位置；取消转换会停止本工具启动的 Allegro 进程。

需要本机 Allegro PCB Editor 和可用许可证，已在 **17.4 S035** 实机验证。无需 Python、额外 .NET SDK 或 Visual Studio。首次下载需要联网，后续可使用有效缓存。

## 输出

- `AD/*.PcbLib`：勾选时生成的二进制 AD 封装库。
- `PADS/*.d`：勾选时生成的 PADS V9 ASCII 封装库。
- `.dra`：可编辑封装图。
- `.psm`：可在 PCB 中放置的封装。
- `.pad`：所有电气焊盘和机械孔的焊盘叠层。
- `source.json`：本次转换使用的立创数据。
- `manifest.json`：元件编号、原始封装名、已选择的输出格式、各格式封装名、引脚坐标、尺寸、旋转和转换提示。
- `使用说明.txt`：封装名和库路径设置说明。
- `rebuild.il` / `rebuild.scr`：用于诊断、在空白封装环境中复现的 SKILL；重复在已生成的图上加载会产生重复对象。
- Allegro 日志：用于核查原生创建和编译过程。

缓存和界面设置位于 `%LOCALAPPDATA%/XiaokaiToolbox/`。每次转换在独立临时目录调用 Allegro，独立 pcbenv 避免执行用户的自动加载脚本。失败、取消或许可证超时会显示诊断目录，不会把不完整结果发布为成功输出。

## 几何规则与范围

- 保留立创封装原点，将源单位换算为毫米：1 源单位 = 10 mil = 0.254 mm；转换 Y 轴及旋转方向。
- 支持矩形、正方形、圆形、长圆形贴片/通孔焊盘，顶面/底面、镀铜通孔及非镀铜机械孔。
- 保留引脚编号、孔径、阻焊/钢网扩展和独立阻焊/钢网区域。源数据中将钢网缩为零的设置不会被替换成整块焊盘开窗。
- 支持丝印线、矩形、圆、多边形实心区域与 SVG 的 M/L/H/V/A/C/Q/Z 路径；曲线离散为细分直线，圆弧最大弦高误差为 0.005 mm。
- 生成原生位号文字。源任意文字、STEP 模型和 3D 外观挖空不导入，转换提示及 manifest 会记录。
- 暂不支持槽孔、任意多边形焊盘、重复引脚编号、非圆椭圆铜焊盘以及电气区域挖空；遇到这些数据会中止，并显示具体原因。
- 超出上述范围的图形或图层会明确报错，不会静默丢掉电气图形。首次使用应结合器件规格书核对封装尺寸与装配方向。

PADS 的封装名上限为 40 个字符，过长名称会保留前缀并附加稳定哈希，实际名称记录在日志与 manifest 中；PADS 引脚名上限为 7 个字符，超过时明确报错。PADS 层号遵循默认配置：21/28 顶/底阻焊，23/22 顶/底钢网，26/29 顶/底丝印，27/30 顶/底装配。自定义 PADS 层配置需在导入后核对。

## 构建与检查

```powershell
powershell -File toolbox/lceda2allegro/build.ps1 -Test
powershell -File toolbox/build.ps1 -Test
powershell -File toolbox/dist/build-setup.ps1
```

若环境禁止直接运行 `.ps1`，可在 PowerShell 中加载该构建文件为 ScriptBlock，并显式传入 `-Root` 和 `-OutputDirectory`。不需要修改系统执行策略。

转换器使用 Windows .NET Framework 自带的 csc 编译，将 `native.il` 嵌入单个 EXE。工具箱清单、主构建、安装包载荷、可选安装组件和绿色版均包含该工具。

自动检查覆盖坐标单位、原点、Y 轴、旋转、钻孔半径转直径、机械孔、阻焊扩展、API 包装格式、重复引脚与不支持类型拦截、相对路径和圆弧。

命令行用于复现和实际 Allegro 集成测试：

```text
立创封装转Allegro.exe --self-test
立创封装转Allegro.exe --download C25804 cache-directory
立创封装转Allegro.exe --convert source.json C25804 output-directory [path-to-allegro.exe] [--ad] [--pads]
```

实际集成样本和回读结果见工作区 `out/lceda2allegro-validation/` 与 `out/lceda2allegro-readback/`。

新增格式实现及验证说明见 [FORMATS.md](FORMATS.md)。


## 当前版本补充

支持简单 POLYGON 异形焊盘，按源轮廓生成铜皮与阻焊 SSM 并保留旋转；支持原生槽孔。源数据重复引脚编号会分配唯一编号并输出 pin-map.csv，用户必须在原理图/网表中补充对应引脚并连接原编号同一网络。槽孔及异形焊盘暂不支持附加 AD/PADS 输出，选择时会明确提示并停止。自交/退化多边形、异形铜皮与槽孔组合仍不支持。以上更新取代早期版本中“全部异形、槽孔和重复编号均拒绝”的限制描述。
