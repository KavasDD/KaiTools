# 发布维护

1. 同步更新 `toolbox/Toolbox.cs`、`toolbox/dist/Setup.cs` 中的版本号，以及 `CHANGELOG.md`。
2. 安装固定构建依赖，运行 `scripts/build-release.ps1` 和相关测试。
3. 检查第三方声明与 `LICENSES/` 是否覆盖发行内容，确认没有个人配置、缓存、工程文件和凭据。
4. 提交源码，执行 `scripts/package-release.ps1`，检查对应源码 ZIP 与 SHA256SUMS。
5. 创建与该提交对应的 `v版本` 标签，推送并创建 GitHub Release。上传安装 EXE、绿色 ZIP、对应源码 ZIP 和 SHA256SUMS.txt。
6. 对照 Release 下载并校验文件，确认源码链接公开可访问。修改发布内容时需更新校验值与源码对应关系。

推送标签并打包后，可运行 `python scripts/publish-release.py v版本`。该入口通过 UTF-8 JSON 文件提交中文标题和说明，先创建草稿、上传四个附件，随后发布并回读核对。不要将含中文的脚本或正文通过 Windows PowerShell 默认编码的管道传给外部程序；这会把中文永久转成问号。

本项目采用 GPL-3.0-only。分发二进制时应同时提供完整对应源码（包含生成/安装脚本），并在同一下载位置清晰提供同等访问方式。不要仅发布 EXE，也不要把过时源码冒充当前版本源码。GPL 不禁止商用、收费或重新分发；接受本项目代码的修改版须保留相应 GPL 义务。
