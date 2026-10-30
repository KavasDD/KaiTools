# 第三方声明

本文件随源码、安装版和绿色版一起分发。根目录 GPL 声明仅授予维护者有权授予的权利，第三方权利和原作者署名予以保留。

## 获得单独许可的工具源码

项目维护者于 2026-10-26 确认，以下第三方代码已获原作者允许修改并按 GPL-3.0 分发源码。本记录依据维护者的授权确认，不表示上游仓库已经采用 GPL，也不替代原作者的授权凭据；维护者应保留单独授权记录。

| 路径 | 原作者 / 来源 | 本仓库分发依据 |
| --- | --- | --- |
| `toolbox/src/JLC3DDownload.py` | Jupiter；[Jupiter1028/JLC3DDownload](https://github.com/Jupiter1028/JLC3DDownload)，原地址 `zhutongxueya/JLC3DDownload` 已重定向 | 原作者单独允许 GPL-3.0 分发；原始作者署名保留 |
| `toolbox/src/step2dxf_converter.py` | zhanshuting，源码保留 `design by zhanshuting` | 原作者单独允许 GPL-3.0 分发 |
| `toolbox/src/gerber2dxf.py` | zhanshuting，源码保留 `design by zhanshuting` | 原作者单独允许 GPL-3.0 分发 |
| `toolbox/src/dwg2dxf_gui.py` | 维护者提供的第三方转换器代码 | 维护者确认已获 GPL-3.0 分发授权；已有署名保留 |

## 主发行包的运行时与构建工具

启动器和 Capture 插件本身使用 Windows / Cadence 已安装的运行时；不再分发这些软件。配套的两个 Python 可执行程序从公开源码重新构建，不复制旧的未知构建产物。

| 组件 | 用途 | 许可证 / 声明 |
| --- | --- | --- |
| CPython | 两个配套 Python 程序的运行时 | Python Software Foundation License，见 `LICENSES/Python.txt` |
| Tcl/Tk | 3D 下载器的 tkinter 界面 | Tcl/Tk 许可，见 `LICENSES/Tcl.txt`、`LICENSES/Tk.txt` |
| PyInstaller | 将 Python 程序打包为 EXE | GPL-2.0-or-later，附 bootloader 分发例外；见 `LICENSES/PyInstaller.txt`。该例外允许按应用自己的许可证分发打包产物 |
| Microsoft Visual C++ Runtime | CPython Windows 运行时依赖 | Microsoft 运行库单独条款，见 `LICENSES/VC-Runtime.txt` |

`requirements-build.txt` 固定打包工具版本。构建环境中其他开发工具及依赖的许可证记录在 `LICENSES/build-dependencies/`，并不意味着这些开发工具全被嵌入最终程序。精确构建环境随发行记录保存。

## 可选转换器依赖

以下依赖由用户自行安装，主发行包未包含其二进制。发布自行构建的转换器时，还需遵守实际安装版本及其传递依赖的许可证，并随包提供所需声明和源码。

| 依赖 | 主要许可证 | 用途 |
| --- | --- | --- |
| ezdxf | MIT | DXF 读写 |
| Pillow | HPND / Pillow 许可 | 图像处理 |
| ezdwg | 以实际安装版本元数据与上游条款为准 | DWG 读取 |
| gerbonara | Apache-2.0 | Gerber 解析 |
| CadQuery | Apache-2.0 | STEP 模型处理 |
| OCP / Open CASCADE | LGPL-2.1，附 Open CASCADE 例外，及各自上游条款 | 几何内核 |

本次发行不包含可选转换器的预编译 EXE，避免将未核验的本地二进制直接发布。

## 外部数据与商业软件

- Cadence、OrCAD、Allegro 等名称和商标属于各自权利人，本项目与其不存在官方隶属关系。
- 立创 / 嘉立创在线接口与下载内容受其各自条款约束；下载的器件数据、3D 模型和用户工程不是本项目 GPL 授权的对象。
- 开发机上的参考仓库 `OpenOrCadParser` 没有作为依赖或源码复制到本仓库；用户工程、旧安装包、缓存和原始规格表也未纳入。

## Allegro SKILL 与 PDF 解析

`toolbox/allegro/originals/` 保留用户提供的 SKILL 原始文件与校验值，安装副本和适配器在 `skill/`、`src/`；原作者署名与注释保留。加密脚本保持原字节。本项目 GPL 声明不替代这些第三方脚本本身的权利声明。

PDF 解析使用 PdfPig 0.1.9（Apache-2.0）和 Microsoft .NET 兼容库。固定版本、来源与 SHA-256 见 `toolbox/drc/vendor/README.md`、`runtime-sha256.json`；完整许可与上游声明见同目录 `THIRD-PARTY-NOTICES.txt`，随源码和运行包提供，且嵌入辅助程序。用户下载的规格书不会随本项目发布。
