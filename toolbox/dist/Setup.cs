// SPDX-License-Identifier: GPL-3.0-only
// 小开工具箱 —— 单页安装程序
//
// 一个窗口装完一切:上面 logo,中间路径和可选组件,底部【安装】。点了以后同一个
// 窗口换成进度条 + 安装日志,不弹新窗口、不分页、不下一步。
//
// 为什么不再用 iexpress + install.cmd:
//   * iexpress 的壳是固定的老式向导,改不动界面;
//   * 它会无声吞掉没打包进去的文件和 cmd /c(见 iexpress-silent-failures 笔记);
//   * 命令行开关传不进去,只能靠环境变量。
// 所以载荷直接嵌成 exe 的资源,安装逻辑就写在这里。
//
// 为什么载荷是"一个文件一个资源"而不是塞一个 zip:
//   这台机器的 csc 只有 v3.5 和 v4.0 的引用程序集,ZipFile 在
//   System.IO.Compression.FileSystem.dll(4.5+)里,编不过。而载荷里两个大件本身
//   就是 PyInstaller 打的包,已经压过一遍,再压也就省几个百分点。所以干脆不压,
//   GetManifestResourceStream 直接往外写,零额外引用。
//   绿色版的 zip 是构建期用 PowerShell 压的,跟运行期无关。
//
// 同一份源码编两遍:
//   uninstall.exe —— 不带载荷,只有卸载那条路,约 60 KB,装进安装目录;
//   XiaokaiToolbox-setup.exe —— 带载荷,并把上面那个 uninstall.exe 也嵌进来。
//   这样卸载界面和安装界面长得一样,而且不用把 22 MB 的载荷复制进安装目录。
//
// 编译见 build-setup.ps1。源码是 UTF-8 无 BOM,所以那边必须带 /codepage:65001。

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

[assembly: AssemblyTitle("小开工具箱 安装程序")]
[assembly: AssemblyCompany("小开")]
[assembly: AssemblyProduct("小开工具箱")]
[assembly: AssemblyFileVersion(XiaokaiSetup.Info.Version + ".0")]
[assembly: AssemblyVersion(XiaokaiSetup.Info.Version + ".0")]

namespace XiaokaiSetup
{
    static class Info
    {
        // 跟 Toolbox.cs 里的 Version 保持一致 —— build-setup.ps1 会核对,不一致直接
        // 报错。发版必须动这里(见 ship-requires-version-bump 笔记)。
        public const string Version = "1.6.88";
        public const string AppName  = "小开工具箱";
        public const string AppExe   = "XiaokaiToolbox.exe";
        public const string UninExe  = "uninstall.exe";
        public const string RegKey   = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\XiaokaiToolbox";
        public const string DirName  = "XiaokaiToolbox";
        // 装到 LOCALAPPDATA,不碰 Program Files,所以整个过程不需要管理员。
    }

    // 配色照抄 Toolbox.cs 里的 Theme,装完弹出来的主程序跟安装界面是一套颜色。
    static class Theme
    {
        public static readonly Color Bg      = Color.FromArgb(0xF5, 0xF8, 0xFA);
        public static readonly Color Card    = Color.White;
        public static readonly Color Line    = Color.FromArgb(0xDC, 0xE6, 0xED);
        public static readonly Color Brand   = Color.FromArgb(0x1B, 0x5E, 0x8C);
        public static readonly Color BrandHi = Color.FromArgb(0x22, 0x6E, 0xA1);
        public static readonly Color BrandLo = Color.FromArgb(0x14, 0x47, 0x6B);
        public static readonly Color OnBrand = Color.FromArgb(0xE8, 0xF2, 0xF8);
        public static readonly Color Text    = Color.FromArgb(0x1E, 0x29, 0x32);
        public static readonly Color Dim     = Color.FromArgb(0x6B, 0x7B, 0x8A);
        public static readonly Color Ok      = Color.FromArgb(0x1E, 0x7A, 0x46);
        public static readonly Color Warn    = Color.FromArgb(0xA8, 0x6A, 0x00);
        public static readonly Color Bad     = Color.FromArgb(0xB3, 0x2B, 0x2B);

        public static Font UI(float size, FontStyle st)
        {
            // 微软雅黑不在就退回默认,别让界面因为字体缺失整个崩掉。
            try { return new Font("Microsoft YaHei UI", size, st); }
            catch { return new Font(FontFamily.GenericSansSerif, size, st); }
        }
        public static Font Mono(float size)
        {
            try { return new Font("Consolas", size); }
            catch { return new Font(FontFamily.GenericMonospace, size); }
        }
    }

    // 一个可选组件 = 一个嵌入资源 + 一个落地文件名。
    class Comp
    {
        public string Key;        // 内部标识
        public string Title;      // 复选框上显示的名字
        public string Note;       // 下面那行灰色说明
        public string Res;        // 嵌入资源名(ASCII,中文文件名过不了 /resource:)
        public string File;       // 写到安装目录里的文件名(可含中文)
        public string Icon;       // 附带的图标资源名,没有就是 null
        public string IconFile;
        public bool   Required;   // 必装,复选框禁用且勾上
        public bool   Default;    // 默认勾选
        public CheckBox Box;      // 界面上的复选框,安装时回读勾选状态

        public bool Wanted { get { return Required || (Box != null && Box.Checked); } }
        public bool Present { get { return Payload.Has(Res); } }

        // 体积直接问资源流,不在构建期把数字写进源码。
        //
        // 本来想让 build-setup.ps1 把真实大小填进一段生成代码,但那样加一个组件要
        // 同时改源码和脚本,源文件还每次构建都被改脏。资源自己就知道自己多长,问它
        // 最准 —— 换了载荷也绝不会对不上。
        long mSize = -1;
        public long Size
        {
            get
            {
                if (mSize < 0) mSize = Payload.Size(Res) + Payload.Size(Icon);
                return mSize;
            }
        }
    }

    // 嵌进 exe 的载荷。资源名一律 ASCII,真实文件名(可能是中文)在 Plan 里配。
    static class Payload
    {
        static readonly Assembly Me = Assembly.GetExecutingAssembly();

        public static bool Has(string res)
        {
            if (string.IsNullOrEmpty(res)) return false;
            return Me.GetManifestResourceInfo(res) != null;
        }

        public static long Size(string res)
        {
            if (!Has(res)) return 0;
            using (Stream s = Me.GetManifestResourceStream(res))
                return s == null ? 0 : s.Length;
        }

        public static void Extract(string res, string path, Action<int> progress)
        {
            using (Stream src = Me.GetManifestResourceStream(res))
            {
                if (src == null) throw new FileNotFoundException("载荷里没有 " + res);
                using (FileStream dst = new FileStream(path, FileMode.Create, FileAccess.Write))
                {
                    byte[] buf = new byte[256 * 1024];
                    int n;
                    while ((n = src.Read(buf, 0, buf.Length)) > 0)
                    {
                        dst.Write(buf, 0, n);
                        if (progress != null) progress(n);
                    }
                }
            }
        }
    }

    sealed class CaptureTarget
    {
        public string AutoLoad;
        public string PluginData;
    }

    static class CapturePlugins
    {
        static readonly string[] Resources = {
            "lceda2orcadMenu.tcl", "bomtoolMenu.tcl",
            "netlocatorMenu.tcl", "drctoolMenu.tcl", "textaffixMenu.tcl", "xiaokaiSchematicPlugins.tcl"
        };

        public static IEnumerable<string> Names
        {
            get { foreach (string resource in Resources) yield return resource; }
        }

        public static long TotalBytes()
        {
            long n = 0;
            foreach (string resource in Resources) n += Payload.Size(resource);
            return n;
        }

        static string AutoLoadPath(string root)
        {
            return Path.Combine(root, "cdssetup", "OrCAD_Capture",
                                "tclscripts", "capAutoLoad");
        }

        static void AddTarget(List<CaptureTarget> targets, HashSet<string> seen,
                              string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return;
            try
            {
                path = Path.GetFullPath(Environment.ExpandEnvironmentVariables(path.Trim().Trim('"')));
                string name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar,
                                                             Path.AltDirectorySeparatorChar));
                List<string> candidates = new List<string>();
                if (name.Equals("capAutoLoad", StringComparison.OrdinalIgnoreCase))
                    candidates.Add(path);
                else if (name.Equals("OrCAD_Capture", StringComparison.OrdinalIgnoreCase))
                    candidates.Add(Path.Combine(path, "tclscripts", "capAutoLoad"));
                else
                {
                    candidates.Add(AutoLoadPath(path));
                    candidates.Add(AutoLoadPath(Path.Combine(path, "SPB_Data")));
                    if (name.Equals("SPB_Data", StringComparison.OrdinalIgnoreCase))
                        candidates.Add(AutoLoadPath(Path.GetDirectoryName(path) ?? ""));
                    if (name.StartsWith("SPB_", StringComparison.OrdinalIgnoreCase))
                        candidates.Add(AutoLoadPath(Path.Combine(
                            Path.GetDirectoryName(path) ?? "", "SPB_Data")));
                }
                foreach (string candidate in candidates)
                {
                    if (!Directory.Exists(candidate)) continue;
                    string full = Path.GetFullPath(candidate);
                    if (!seen.Add(full)) continue;
                    string capture = Directory.GetParent(Directory.GetParent(full).FullName).FullName;
                    targets.Add(new CaptureTarget {
                        AutoLoad = full,
                        PluginData = Path.Combine(capture, "xiaokaiToolboxPlugins")
                    });
                }
            }
            catch (ArgumentException) { }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (NotSupportedException) { }
        }

        public static List<CaptureTarget> FindTargets()
        {
            List<CaptureTarget> targets = new List<CaptureTarget>();
            HashSet<string> seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string name in new string[] {
                "HOME", "USERPROFILE", "CDS_INST_DIR", "SPB_17_4", "CDSROOT"
            })
                AddTarget(targets, seen, Environment.GetEnvironmentVariable(name));

            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                if (!drive.IsReady || drive.DriveType != DriveType.Fixed) continue;
                string root = drive.RootDirectory.FullName;
                foreach (string relative in new string[] {
                    "Cadence\\SPB_Data", "orcad\\Cadence\\SPB_Data",
                    "Program Files\\Cadence\\SPB_Data",
                    "Program Files (x86)\\Cadence\\SPB_Data"
                })
                    AddTarget(targets, seen, Path.Combine(root, relative));
            }
            return targets;
        }

        static Dictionary<string, string> ReadManifest(string path)
        {
            Dictionary<string, string> result =
                new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (!File.Exists(path)) return result;
            foreach (string line in File.ReadAllLines(path))
            {
                string[] fields = line.Split('|');
                if (fields.Length == 2 && fields[1].Length == 64)
                    result[fields[0]] = fields[1];
            }
            return result;
        }

        static string HashFile(string path)
        {
            using (System.Security.Cryptography.SHA256 sha =
                   System.Security.Cryptography.SHA256.Create())
            using (FileStream stream = File.OpenRead(path))
            {
                byte[] hash = sha.ComputeHash(stream);
                StringBuilder text = new StringBuilder(hash.Length * 2);
                foreach (byte b in hash) text.Append(b.ToString("x2"));
                return text.ToString();
            }
        }

        static void WriteManifest(string path, Dictionary<string, string> hashes)
        {
            string temp = path + ".tmp";
            List<string> lines = new List<string>();
            foreach (string file in Resources) lines.Add(file + "|" + hashes[file]);
            File.WriteAllLines(temp, lines, new UTF8Encoding(false));
            if (File.Exists(path)) File.Delete(path);
            File.Move(temp, path);
        }

        public static bool Install(IReport report)
        {
            foreach (string resource in Resources)
                if (!Payload.Has(resource))
                {
                    report.Fail("安装包缺少 Capture 插件载荷:" + resource);
                    return false;
                }

            List<CaptureTarget> targets = FindTargets();
            if (targets.Count == 0)
            {
                report.Note("未找到 Capture 用户目录，跳过 Capture 插件；安装 Capture 后可重新运行本安装包。");
                return true;
            }

            return InstallTargets(targets, report);
        }

        static bool InstallTargets(List<CaptureTarget> targets, IReport report)
        {
            foreach (CaptureTarget target in targets)
            {
                string backup = Path.Combine(target.PluginData, "original");
                string modified = Path.Combine(target.PluginData, "modified");
                string manifest = Path.Combine(target.PluginData, "managed.sha256");
                Directory.CreateDirectory(target.PluginData);
                Directory.CreateDirectory(backup);
                Dictionary<string, string> previous = ReadManifest(manifest);
                Dictionary<string, string> current =
                    new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                foreach (string file in Resources)
                {
                    string destination = Path.Combine(target.AutoLoad, file);
                    string original = Path.Combine(backup, file);
                    if (File.Exists(destination))
                    {
                        string existingHash = HashFile(destination);
                        string installedHash;
                        bool wasManaged = previous.TryGetValue(file, out installedHash)
                                       && string.Equals(existingHash, installedHash,
                                                        StringComparison.OrdinalIgnoreCase);
                        if (!wasManaged)
                        {
                            if (!File.Exists(original)) File.Copy(destination, original);
                            else
                            {
                                Directory.CreateDirectory(modified);
                                File.Copy(destination, Path.Combine(modified, file), true);
                            }
                        }
                    }

                    report.Step("安装 Capture 插件 " + file);
                    string temporary = destination + ".xiaokai-" + Guid.NewGuid().ToString("N");
                    try
                    {
                        Payload.Extract(file, temporary, delegate(int n) { report.Bytes(n); });
                        File.Copy(temporary, destination, true);
                        File.Delete(temporary);
                        current[file] = HashFile(destination);
                        report.Ok("已写入 " + destination);
                    }
                    catch
                    {
                        try { if (File.Exists(temporary)) File.Delete(temporary); } catch (IOException) { }
                        throw;
                    }
                }
                WriteManifest(manifest, current);
            }
            report.Note("Capture 插件已安装；如果 Capture 正在运行，请重启后按 Alt+K 打开插件集合。");
            return true;
        }

        static bool LooksLikePlugin(string file, string path)
        {
            string text;
            try { text = File.ReadAllText(path); }
            catch (IOException) { return false; }
            catch (UnauthorizedAccessException) { return false; }
            if (file.Equals("lceda2orcadMenu.tcl", StringComparison.OrdinalIgnoreCase))
                return text.Contains("lceda2orcadVersion");
            if (file.Equals("bomtoolMenu.tcl", StringComparison.OrdinalIgnoreCase))
                return text.Contains("::bomtool::version");
            if (file.Equals("netlocatorMenu.tcl", StringComparison.OrdinalIgnoreCase))
                return text.Contains("::netloc::version");
            if (file.Equals("drctoolMenu.tcl", StringComparison.OrdinalIgnoreCase))
                return text.Contains("::xiaokai::drc");
            if (file.Equals("textaffixMenu.tcl", StringComparison.OrdinalIgnoreCase))
                return text.Contains("::xiaokai::textaffix");
            return text.Contains("xiaokaiSchematicPlugins");
        }

        public static bool Uninstall(IReport report)
        {
            return UninstallTargets(FindTargets(), report);
        }

        static bool UninstallTargets(List<CaptureTarget> targets, IReport report)
        {
            foreach (CaptureTarget target in targets)
            {
                string backup = Path.Combine(target.PluginData, "original");
                string modified = Path.Combine(target.PluginData, "modified");
                string manifest = Path.Combine(target.PluginData, "managed.sha256");
                Dictionary<string, string> managed = ReadManifest(manifest);
                bool preservedModified = false;
                foreach (string file in Resources)
                {
                    string destination = Path.Combine(target.AutoLoad, file);
                    if (!File.Exists(destination)) continue;
                    string expected;
                    bool known = managed.TryGetValue(file, out expected);
                    bool unchanged = known
                        ? string.Equals(HashFile(destination), expected,
                                         StringComparison.OrdinalIgnoreCase)
                        : LooksLikePlugin(file, destination);
                    if (!unchanged)
                    {
                        preservedModified = true;
                        report.Warn("保留了已修改的插件文件:" + destination);
                        continue;
                    }

                    File.Delete(destination);
                    string original = Path.Combine(backup, file);
                    string edited = Path.Combine(modified, file);
                    string restore = File.Exists(edited) ? edited : original;
                    if (File.Exists(restore))
                    {
                        File.Copy(restore, destination);
                        File.Delete(restore);
                        report.Ok("恢复原有文件 " + destination);
                    }
                    else report.Ok("已删除 " + destination);
                }

                if (!preservedModified)
                {
                    if (File.Exists(manifest)) File.Delete(manifest);
                    if (Directory.Exists(backup) && Directory.GetFiles(backup).Length == 0)
                        Directory.Delete(backup);
                    if (Directory.Exists(modified) && Directory.GetFiles(modified).Length == 0)
                        Directory.Delete(modified);
                    if (Directory.Exists(target.PluginData)
                        && Directory.GetFiles(target.PluginData).Length == 0
                        && Directory.GetDirectories(target.PluginData).Length == 0)
                        Directory.Delete(target.PluginData);
                }
            }
            if (targets.Count == 0)
                report.Note("没有找到需要删除 Capture 插件的安装目录。");
            else
                report.Note("删除插件后请重启 Capture。");
            return true;
        }

        sealed class TestReport : IReport
        {
            public string Failure;
            public void Step(string what) { }
            public void Ok(string what) { }
            public void Warn(string what) { }
            public void Fail(string what) { Failure = what; }
            public void Note(string what) { }
            public void Bytes(long n) { }
            public void Phase(string what) { }
        }

        public static string TestLifecycle()
        {
            string root = Path.Combine(Path.GetTempPath(),
                "xk-capture-plugin-test-" + Guid.NewGuid().ToString("N"));
            try
            {
                foreach (string resource in Resources)
                    if (!Payload.Has(resource)) return "missing payload " + resource;

                foreach (bool editBeforeUpgrade in new bool[] { false, true })
                {
                    string capture = Path.Combine(root, editBeforeUpgrade ? "edited" : "original");
                    string autoLoad = Path.Combine(capture, "tclscripts", "capAutoLoad");
                    string pluginData = Path.Combine(capture, "xiaokaiToolboxPlugins");
                    Directory.CreateDirectory(autoLoad);
                    string lceda = Path.Combine(autoLoad, "lceda2orcadMenu.tcl");
                    File.WriteAllText(lceda, "pre-existing plugin");
                    List<CaptureTarget> target = new List<CaptureTarget> {
                        new CaptureTarget { AutoLoad = autoLoad, PluginData = pluginData }
                    };
                    TestReport report = new TestReport();
                    if (!InstallTargets(target, report))
                        return "initial install failed: " + report.Failure;
                    if (File.ReadAllText(Path.Combine(pluginData, "original",
                                                      "lceda2orcadMenu.tcl"))
                        != "pre-existing plugin")
                        return "pre-existing script was not backed up";

                    if (editBeforeUpgrade)
                    {
                        File.WriteAllText(lceda, "user-edited plugin");
                        report = new TestReport();
                        if (!InstallTargets(target, report))
                            return "upgrade failed: " + report.Failure;
                        if (File.ReadAllText(Path.Combine(pluginData, "modified",
                                                          "lceda2orcadMenu.tcl"))
                            != "user-edited plugin")
                            return "user-modified script was not preserved during upgrade";
                    }

                    report = new TestReport();
                    if (!UninstallTargets(target, report))
                        return "uninstall failed: " + report.Failure;
                    string expected = editBeforeUpgrade
                        ? "user-edited plugin" : "pre-existing plugin";
                    if (File.ReadAllText(lceda) != expected)
                        return "uninstall did not restore " + expected;
                    for (int i = 1; i < Resources.Length; i++)
                        if (File.Exists(Path.Combine(autoLoad, Resources[i])))
                            return "uninstall left " + Resources[i];
                }
                return null;
            }
            catch (Exception ex) { return ex.Message; }
            finally
            {
                if (Directory.Exists(root)) Directory.Delete(root, true);
            }
        }
    }
    static class LegalNotices
    {
        public static IEnumerable<string> Names
        {
            get
            {
                foreach (string name in Assembly.GetExecutingAssembly().GetManifestResourceNames())
                    if (name.StartsWith("legal.", StringComparison.Ordinal)) yield return name;
            }
        }
        public static string FileName(string resource)
        {
            return resource.Substring("legal.".Length).Replace('/', Path.DirectorySeparatorChar);
        }

        public static string TestExtraction()
        {
            string dir = Path.Combine(Path.GetTempPath(), "xk-legal-" + Guid.NewGuid().ToString("N"));
            try
            {
                int count = 0;
                foreach (string resource in Names)
                {
                    string path = Path.Combine(dir, FileName(resource));
                    Directory.CreateDirectory(Path.GetDirectoryName(path));
                    Payload.Extract(resource, path, delegate(int n) { });
                    if (new FileInfo(path).Length != Payload.Size(resource)) return "Length mismatch: " + resource;
                    count++;
                }
                return count >= 9 ? null : "Missing runtime license resources";
            }
            catch (Exception ex) { return ex.Message; }
            finally { if (Directory.Exists(dir)) Directory.Delete(dir, true); }
        }
    }
    static class Plan
    {
        // 主程序那几个文件:不作为可选项,勾了任何组件都得有。
        public static readonly Comp[] Core = new Comp[]
        {
            new Comp { Key="app",  Res="app.exe",     File=Info.AppExe,      Required=true },
            new Comp { Key="ini",  Res="tools.ini",   File="tools.ini",      Required=true },
            new Comp { Key="unin", Res="uninstall.exe", File=Info.UninExe,   Required=true },
        };

        public static readonly Comp[] Extras = new Comp[]
        {
            new Comp {
                Key="markinglookup", Title="常见丝印反查",
                Note="离线按丝印、型号和封装反查贴片器件，支持分类筛选及复制条目。",
                Res="markinglookup.exe", File="常见丝印反查.exe", Default=true },
            new Comp {
                Key="startupoptimizer", Title="OrCAD 启动优化工具",
                Note="在其他辅助工具中打开，按需停用启动功能，自动备份并支持恢复。",
                Res="startupoptimizer.exe", File="OrCAD启动优化工具.exe", Default=true },
            new Comp {
                Key="specgen", Title="元器件规格描述生成器",
                Note="按型号生成规范的元器件规格描述,供 BOM 和物料库使用。",
                Res="specgen.exe", File="元器件规格描述生成器.exe",
                Icon="specgen.ico", IconFile="specgen.ico", Default=true },
            new Comp {
                Key="jlc3d", Title="嘉立创 3D 模型下载器",
                Note="按编号批量下载封装的 3D 模型,转成 OrCAD/Allegro 能用的格式。",
                Res="jlc3d.exe", File="JLC3D-Downloader.exe",
                Icon="jlc3d.ico", IconFile="jlc3d.ico", Default=true },
        };

        public static IEnumerable<Comp> All
        {
            get
            {
                foreach (Comp c in Core) yield return c;
                foreach (Comp c in Extras) yield return c;
            }
        }
    }

    static class Locate
    {
        // 装哪儿:装过就沿用上次的位置(升级不换地方),否则 LOCALAPPDATA。
        public static string Suggest()
        {
            string old = Installed();
            if (old != null) return old;
            return Path.Combine(Environment.GetFolderPath(
                Environment.SpecialFolder.LocalApplicationData), Info.DirName);
        }

        public static string Installed()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(Info.RegKey))
                {
                    if (k == null) return null;
                    string p = k.GetValue("InstallLocation") as string;
                    if (!string.IsNullOrEmpty(p)) return p;
                }
            }
            catch { }
            return null;
        }

        public static string InstalledVersion()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(Info.RegKey))
                    return k == null ? null : k.GetValue("DisplayVersion") as string;
            }
            catch { return null; }
        }

        // 路径能不能用。光看 Directory.Exists 不够 —— 目录在但没有写权限的情况是
        // 真会遇到的(比如有人把路径填到别的用户的目录下),所以真去建一个临时文件试。
        public static string Check(string dir)
        {
            if (string.IsNullOrWhiteSpace(dir)) return "安装路径不能为空。";
            if (dir.IndexOfAny(Path.GetInvalidPathChars()) >= 0) return "安装路径里有非法字符。";
            try
            {
                dir = Path.GetFullPath(dir);
                if (!Path.IsPathRooted(dir)) return "请填写完整路径,比如 D:\\Tools\\" + Info.DirName + "。";
                string volumeRoot = Path.GetPathRoot(dir);
                if (dir.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                    .Equals(volumeRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                            StringComparison.OrdinalIgnoreCase))
                    return "不能把磁盘根目录作为安装位置。";
            }
            catch { return "这个路径解析不出来,换一个。"; }

            try
            {
                string probe = dir;
                // 往上找到第一个已经存在的祖先,权限是在那儿判的。
                while (!Directory.Exists(probe))
                {
                    DirectoryInfo up = Directory.GetParent(probe);
                    if (up == null) return "找不到这个盘,确认盘符对不对。";
                    probe = up.FullName;
                }
                string tmp = Path.Combine(probe, "." + Info.DirName + "-probe-" + Guid.NewGuid().ToString("N").Substring(0, 8));
                using (FileStream f = new FileStream(tmp, FileMode.CreateNew, FileAccess.Write)) { }
                File.Delete(tmp);
            }
            catch (UnauthorizedAccessException) { return "这个位置没有写权限,换一个(或者装到用户目录下)。"; }
            catch (Exception ex) { return "这个位置写不进去:" + ex.Message; }
            return null;
        }
    }

    // 自己画的进度条。系统的 ProgressBar 在 Win10 上是绿色的,而且 Visual Styles
    // 一开就不认 BackColor/ForeColor,跟这套蓝色配不上,所以自己画。
    class FlatBar : Control
    {
        double mVal;
        public FlatBar()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                     | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Height = 8;
        }
        // 0..1。安装过程里每写一块就设一次,一秒能有上百次,所以变化太小就不重画。
        public double Value
        {
            get { return mVal; }
            set
            {
                double v = value < 0 ? 0 : (value > 1 ? 1 : value);
                if (Math.Abs(v - mVal) < 0.002 && v < 1) return;
                mVal = v; Invalidate();
            }
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            int r = Height;
            using (SolidBrush b = new SolidBrush(Color.FromArgb(0xE3, 0xEB, 0xF2)))
                Round(g, b, new Rectangle(0, 0, Width, Height), r);
            int w = (int)Math.Round(Width * mVal);
            if (w < 1) return;
            if (w < r) w = r;
            using (LinearGradientBrush b = new LinearGradientBrush(
                       new Rectangle(0, 0, Math.Max(w, 2), Height),
                       Theme.Brand, Theme.BrandHi, LinearGradientMode.Horizontal))
                Round(g, b, new Rectangle(0, 0, w, Height), r);
        }
        static void Round(Graphics g, Brush b, Rectangle rc, int d)
        {
            if (rc.Width <= 0 || rc.Height <= 0) return;
            if (d > rc.Width) d = rc.Width;
            if (d > rc.Height) d = rc.Height;
            using (GraphicsPath p = new GraphicsPath())
            {
                p.AddArc(rc.X, rc.Y, d, d, 180, 90);
                p.AddArc(rc.Right - d, rc.Y, d, d, 270, 90);
                p.AddArc(rc.Right - d, rc.Bottom - d, d, d, 0, 90);
                p.AddArc(rc.X, rc.Bottom - d, d, d, 90, 90);
                p.CloseFigure();
                g.FillPath(b, p);
            }
        }
    }

    // 顶部那条 logo 带。整条可拖动 —— 窗口是无边框的,不给拖的地方就挪不动了。
    class Banner : Control
    {
        readonly Icon mIcon;
        readonly string mSub;
        public Banner(Icon icon, string sub)
        {
            mIcon = icon; mSub = sub;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                     | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Height = 96;
        }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            using (LinearGradientBrush b = new LinearGradientBrush(
                       ClientRectangle, Theme.Brand, Theme.BrandLo, LinearGradientMode.Horizontal))
                g.FillRectangle(b, ClientRectangle);

            int x = 24;
            if (mIcon != null)
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                // 用 Icon 而不是 ToBitmap():48 的尺寸让 GDI 自己从多尺寸 ico 里挑,
                // 缩出来比从 256 硬缩清楚。
                g.DrawIcon(mIcon, new Rectangle(x, (Height - 48) / 2, 48, 48));
                x += 48 + 16;
            }
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            using (Font f1 = Theme.UI(19f, FontStyle.Bold))
            using (Font f2 = Theme.UI(9f, FontStyle.Regular))
            using (SolidBrush w = new SolidBrush(Color.White))
            using (SolidBrush d = new SolidBrush(Color.FromArgb(0xB8, 0xD8, 0xEC)))
            {
                SizeF s1 = g.MeasureString(Info.AppName, f1);
                float top = (Height - (s1.Height + 20)) / 2f;
                g.DrawString(Info.AppName, f1, w, x, top);
                g.DrawString(mSub, f2, d, x + 2, top + s1.Height + 1);
            }
        }
        protected override void OnMouseDown(MouseEventArgs e)
        {
            base.OnMouseDown(e);
            if (e.Button != MouseButtons.Left) return;
            Form f = FindForm();
            if (f != null) Drag.Begin(f);
        }
    }

    static class Drag
    {
        const int WM_NCLBUTTONDOWN = 0xA1, HTCAPTION = 2;
        [DllImport("user32.dll")] static extern bool ReleaseCapture();
        [DllImport("user32.dll")] static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
        // 告诉系统"这一下点的是标题栏",拖动就交给系统去做,不用自己算鼠标偏移,
        // 贴边和多显示器的行为也跟着系统一致。
        public static void Begin(Form f)
        {
            ReleaseCapture();
            SendMessage(f.Handle, WM_NCLBUTTONDOWN, (IntPtr)HTCAPTION, IntPtr.Zero);
        }
    }

    // 扁平按钮。系统 Button 的 FlatStyle.Flat 在鼠标悬停时会自己涂一层灰,盖掉设的
    // 颜色,所以整个自己画。
    class FlatBtn : Control
    {
        bool mHot, mDown;
        public bool Primary = true;
        public FlatBtn(string text, bool primary)
        {
            Text = text; Primary = primary;
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                     | ControlStyles.UserPaint | ControlStyles.ResizeRedraw, true);
            Cursor = Cursors.Hand;
            Size = new Size(120, 38);
        }
        protected override void OnMouseEnter(EventArgs e) { mHot = true;  Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { mHot = false; mDown = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnMouseDown(MouseEventArgs e) { mDown = true;  Invalidate(); base.OnMouseDown(e); }
        protected override void OnMouseUp(MouseEventArgs e)   { mDown = false; Invalidate(); base.OnMouseUp(e); }
        protected override void OnEnabledChanged(EventArgs e)
        {
            Cursor = Enabled ? Cursors.Hand : Cursors.Default;
            Invalidate(); base.OnEnabledChanged(e);
        }
        // 自己画的控件改 Text 不会自动重画 —— 少了这一句,装完按钮上还写着
        // "安装中…",而旁边的 Label 早就变了,看起来像卡住了。
        protected override void OnTextChanged(EventArgs e) { Invalidate(); base.OnTextChanged(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            g.SmoothingMode = SmoothingMode.AntiAlias;
            Rectangle rc = new Rectangle(0, 0, Width - 1, Height - 1);
            Color fill, fore;
            if (!Enabled)      { fill = Color.FromArgb(0xD7, 0xDF, 0xE6); fore = Color.FromArgb(0x93, 0xA1, 0xAD); }
            else if (Primary)  { fill = mDown ? Theme.BrandLo : (mHot ? Theme.BrandHi : Theme.Brand); fore = Color.White; }
            else               { fill = mDown ? Color.FromArgb(0xE2, 0xEA, 0xF1)
                                             : (mHot ? Color.FromArgb(0xEE, 0xF4, 0xF9) : Theme.Card);
                                 fore = Theme.Brand; }
            using (GraphicsPath p = Path(rc, 6))
            using (SolidBrush b = new SolidBrush(fill))
            {
                g.FillPath(b, p);
                if (!Primary && Enabled)
                    using (Pen pen = new Pen(Theme.Line)) g.DrawPath(pen, p);
            }
            g.TextRenderingHint = System.Drawing.Text.TextRenderingHint.ClearTypeGridFit;
            using (Font f = Theme.UI(10.5f, Primary ? FontStyle.Bold : FontStyle.Regular))
            using (SolidBrush b = new SolidBrush(fore))
            using (StringFormat sf = new StringFormat { Alignment = StringAlignment.Center,
                                                       LineAlignment = StringAlignment.Center })
                g.DrawString(Text, f, b, ClientRectangle, sf);
        }
        static GraphicsPath Path(Rectangle rc, int d)
        {
            GraphicsPath p = new GraphicsPath();
            p.AddArc(rc.X, rc.Y, d, d, 180, 90);
            p.AddArc(rc.Right - d, rc.Y, d, d, 270, 90);
            p.AddArc(rc.Right - d, rc.Bottom - d, d, d, 0, 90);
            p.AddArc(rc.X, rc.Bottom - d, d, d, 90, 90);
            p.CloseFigure();
            return p;
        }
    }

    // 安装过程的打印。用 RichTextBox 而不是 TextBox,因为要按行上色(成功绿、警告
    // 橙、失败红);只读但可选中,出问题的人能把日志复制走。
    class LogBox : RichTextBox
    {
        public LogBox()
        {
            ReadOnly = true; BorderStyle = BorderStyle.None;
            BackColor = Color.FromArgb(0xFB, 0xFD, 0xFE);
            Font = Theme.Mono(9f);
            ScrollBars = RichTextBoxScrollBars.Vertical;
            WordWrap = true; TabStop = false; DetectUrls = false;
        }
        public void Put(string line, Color c)
        {
            SelectionStart = TextLength;
            SelectionLength = 0;
            SelectionColor = c;
            AppendText(line + Environment.NewLine);
            // AppendText 已经会滚,但选区留在末尾时偶尔差一行,补一下。
            SelectionStart = TextLength;
            ScrollToCaret();
        }
        protected override void OnGotFocus(EventArgs e)
        {
            // 只读框拿到焦点会显示光标,看着像能编辑。
            base.OnGotFocus(e);
            HideCaret(Handle);
        }
        [DllImport("user32.dll")] static extern bool HideCaret(IntPtr h);
    }

    // 安装/卸载过程往外报告什么。抽成接口是为了让 Worker 不碰任何控件 —— 它跑在
    // 后台线程上,直接摸控件会炸。
    interface IReport
    {
        void Step(string what);            // 开始做一件事
        void Ok(string what);              // 做成了
        void Warn(string what);            // 没做成但不致命
        void Fail(string what);            // 致命
        void Note(string what);            // 顺带说一句
        void Bytes(long n);                // 又写了 n 字节,推进度条
        void Phase(string what);           // 进度条上面那行大字
    }

    // 真正干活的部分。跑在后台线程,只通过 IReport 说话,不认识任何控件。
    class Worker
    {
        readonly IReport R;
        readonly string Dir;
        public bool Desktop = true, StartMenu = true, KeepIni = true;
        public bool KeepPlugins = true;
        public bool ForceCloseTools = true;

        public Worker(IReport r, string dir) { R = r; Dir = dir; }

        internal static string TestKillTree(Process process) { return KillTree(process); }
        internal static bool TestIsTargetProcessPath(string target, string image)
        {
            return IsTargetProcessPath(target, image);
        }

        // 进度条的分母。只算要写的字节,注册表和快捷方式那几步几乎不花时间。
        public long Total()
        {
            long n = 0;
            foreach (Comp c in Plan.All) if (c.Wanted && c.Present) n += c.Size;
            n += CapturePlugins.TotalBytes();
            n += AllegroSkills.TotalBytes();
            return n > 0 ? n : 1;
        }

        public bool Install()
        {
            try
            {
                R.Phase("正在安装");
                if (!CloseRunning()) return false;
                if (!MakeDir()) return false;
                if (!CopyFiles()) return false;
                if (!CapturePlugins.Install(R)) return false;
                if (!AllegroSkills.Apply(R, false)) return false;
                RemoveObsoletePluginInstallers();
                Register();
                MakeShortcuts();
                R.Phase("安装完成");
                R.Note("装到了 " + Dir);
                return true;
            }
            catch (Exception ex)
            {
                R.Fail("安装中断:" + ex.Message);
                return false;
            }
        }

        // 装之前先让旧版退出,否则文件被占住写不进去。
        bool CloseRunning()
        {
            R.Step(ForceCloseTools ? "强制结束安装目录中的工具进程" : "关闭正在运行的旧版本");
            int killed = 0;
            int currentId = Process.GetCurrentProcess().Id;
            string fullDir = Path.GetFullPath(Dir);
            string volumeRoot = Path.GetPathRoot(fullDir);
            if (fullDir.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
                .Equals(volumeRoot.TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar),
                        StringComparison.OrdinalIgnoreCase))
            {
                R.Fail("不能从磁盘根目录安装或清理进程。");
                return false;
            }
            var targetPaths = new Dictionary<string, HashSet<string>>(
                StringComparer.OrdinalIgnoreCase);
            if (ForceCloseTools)
            {
                foreach (string path in Directory.GetFiles(
                    fullDir, "*.exe", SearchOption.TopDirectoryOnly))
                {
                    AddTargetPath(targetPaths, path);
                }
            }
            else
            {
                AddTargetPath(targetPaths, Path.Combine(fullDir, Info.AppExe));
            }

            var targets = new List<Process>();
            var seen = new HashSet<int>();
            bool failed = false;
            foreach (KeyValuePair<string, HashSet<string>> candidate in targetPaths)
            {
                foreach (Process p in Process.GetProcessesByName(candidate.Key))
                {
                    try
                    {
                        if (p.Id == currentId)
                        {
                            p.Dispose();
                            continue;
                        }
                        string image = p.MainModule.FileName;
                        if (image != null
                         && candidate.Value.Contains(Path.GetFullPath(image))
                         && seen.Add(p.Id))
                        {
                            targets.Add(p);
                            continue;
                        }
                    }
                    catch (InvalidOperationException) { }
                    catch (System.ComponentModel.Win32Exception ex)
                    {
                        R.Warn("无法验证同名进程 " + p.Id + " 是否来自安装目录，未对其进行处理：" + ex.Message);
                        failed = true;
                    }
                    p.Dispose();
                }
            }

            foreach (Process p in targets)
            {
                try
                {
                    if (p.HasExited) continue;
                    if (ForceCloseTools)
                    {
                        string error = KillTree(p);
                        if (error != null)
                        {
                            R.Warn("无法结束进程 " + p.Id + "：" + error);
                            failed = true;
                        }
                        else killed++;
                    }
                    else
                    {
                        if (!p.CloseMainWindow() || !p.WaitForExit(12000))
                        {
                            p.Kill();
                            if (!p.WaitForExit(3000))
                            {
                                R.Warn("旧版工具箱进程 " + p.Id + " 仍在运行。");
                                failed = true;
                            }
                            else killed++;
                        }
                        else killed++;
                    }
                }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception ex)
                {
                    R.Warn("无法结束进程 " + p.Id + "：" + ex.Message);
                    failed = true;
                }
                finally { p.Dispose(); }
            }

            if (failed)
                R.Warn("有目标工具进程未能检查或结束；安装已取消，请关闭它们后重试。");
            else
                R.Ok(killed > 0 ? "精准结束了 " + killed + " 个目标工具进程"
                                : "未发现安装目录中的目标工具进程");
            return !failed;
        }

        static void AddTargetPath(Dictionary<string, HashSet<string>> paths, string path)
        {
            string fullPath = Path.GetFullPath(path);
            string name = Path.GetFileNameWithoutExtension(fullPath);
            HashSet<string> matches;
            if (!paths.TryGetValue(name, out matches))
            {
                matches = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                paths.Add(name, matches);
            }
            matches.Add(fullPath);
        }

        static bool IsTargetProcessPath(string target, string image)
        {
            return Path.GetFullPath(target).Equals(Path.GetFullPath(image),
                StringComparison.OrdinalIgnoreCase);
        }

        static string KillTree(Process process)
        {
            string taskkill = Path.Combine(Environment.SystemDirectory, "taskkill.exe");
            string treeError = "";
            var startInfo = new ProcessStartInfo(taskkill, "/PID " + process.Id + " /T /F")
            {
                UseShellExecute = false,
                CreateNoWindow = true
            };
            using (Process killer = Process.Start(startInfo))
            {
                if (killer == null) return "无法启动 taskkill.exe。";
                if (!killer.WaitForExit(10000))
                {
                    killer.Kill();
                    treeError = "taskkill.exe 等待超时。";
                }
                else if (!process.HasExited && killer.ExitCode != 0)
                    treeError = "taskkill.exe 退出码 " + killer.ExitCode + "。";
                if (!process.HasExited && !process.WaitForExit(3000) && treeError.Length == 0)
                    treeError = "主进程仍在运行。";
            }
            if (!process.HasExited)
            {
                process.Kill();
                if (!process.WaitForExit(3000))
                    return "强制结束请求已发送，但主进程仍在运行。";
            }
            if (!string.IsNullOrEmpty(treeError)) return treeError;
            return null;
        }

        bool MakeDir()
        {
            R.Step("创建安装目录");
            try
            {
                Directory.CreateDirectory(Dir);
                R.Ok(Dir);
                return true;
            }
            catch (Exception ex) { R.Fail("建不了目录:" + ex.Message); return false; }
        }

        bool CopyFiles()
        {
            // tools.local.ini 是用户自己加的快捷方式,绝不覆盖也绝不删。tools.ini
            // 是我们的清单,每次都覆盖 —— 新版加了工具就得进去。
            string local = Path.Combine(Dir, "tools.local.ini");
            bool hadLocal = File.Exists(local);

            foreach (Comp c in Plan.All)
            {
                if (!c.Wanted) continue;
                if (!c.Present)
                {
                    // 载荷里没有 = 构建时漏了。核心文件漏了直接失败,可选组件只警告。
                    if (c.Required) { R.Fail("安装包不完整:缺 " + c.File); return false; }
                    R.Warn("安装包里没有 " + c.File + ",跳过");
                    continue;
                }
                R.Step("写入 " + c.File);
                try
                {
                    Payload.Extract(c.Res, Path.Combine(Dir, c.File), delegate(int n) { R.Bytes(n); });
                    if (c.Icon != null && Payload.Has(c.Icon))
                        Payload.Extract(c.Icon, Path.Combine(Dir, c.IconFile), delegate(int n) { R.Bytes(n); });
                    R.Ok(Kb(c.Size));
                }
                catch (Exception ex)
                {
                    if (c.Required) { R.Fail("写不进去:" + ex.Message); return false; }
                    R.Warn(c.File + " 写失败:" + ex.Message);
                }
            }

            try
            {
                foreach (string name in LegalNotices.Names)
                {
                    string path = Path.Combine(Dir, LegalNotices.FileName(name));
                    Directory.CreateDirectory(Path.GetDirectoryName(path));
                    Payload.Extract(name, path, delegate(int n) { R.Bytes(n); });
                }
            }
            catch (Exception ex) { R.Fail("License notice extraction failed: " + ex.Message); return false; }

            if (hadLocal) R.Note("保留了你自己加的 tools.local.ini");

            // 主程序必须真的在,才算装上了。
            string app = Path.Combine(Dir, Info.AppExe);
            if (!File.Exists(app)) { R.Fail("主程序没落地,安装失败"); return false; }
            return true;
        }

        void RemoveObsoletePluginInstallers()
        {
            foreach (string name in new string[] {
                "lceda2orcad-setup.exe", "bomtool-setup.exe", "netlocator-setup.exe"
            })
            {
                string path = Path.Combine(Dir, name);
                if (!File.Exists(path)) continue;
                try { File.Delete(path); R.Note("清理旧版独立插件安装器 " + name); }
                catch (Exception ex) { R.Warn("旧版安装器未能清理 " + name + ":" + ex.Message); }
            }
        }

        static string Kb(long n)
        {
            if (n >= 1024 * 1024) return (n / 1048576.0).ToString("0.0") + " MB";
            if (n >= 1024) return (n / 1024.0).ToString("0") + " KB";
            return n + " B";
        }

        void Register()
        {
            R.Step("注册到控制面板");
            try
            {
                // HKCU 而不是 HKLM:装在用户目录下,不需要管理员,也就不该往
                // 全机器的注册表里写。
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(Info.RegKey))
                {
                    string unin = Path.Combine(Dir, Info.UninExe);
                    k.SetValue("DisplayName", Info.AppName);
                    k.SetValue("DisplayVersion", Info.Version);
                    k.SetValue("Publisher", "小开");
                    k.SetValue("InstallLocation", Dir);
                    k.SetValue("DisplayIcon", Path.Combine(Dir, Info.AppExe));
                    // 路径带空格,所以引号是必须的。
                    k.SetValue("UninstallString", "\"" + unin + "\"");
                    k.SetValue("QuietUninstallString", "\"" + unin + "\" /uninstall /silent");
                    k.SetValue("NoModify", 1, RegistryValueKind.DWord);
                    k.SetValue("NoRepair", 1, RegistryValueKind.DWord);
                    k.SetValue("EstimatedSize", (int)(DirSize() / 1024), RegistryValueKind.DWord);
                    k.SetValue("InstallDate", DateTime.Now.ToString("yyyyMMdd"));
                    // 记下装了哪些组件,卸载和下次升级要照着办。
                    List<string> got = new List<string>();
                    foreach (Comp c in Plan.Extras)
                        if (c.Wanted && c.Present) got.Add(c.Key);
                    k.SetValue("Components", string.Join(",", got.ToArray()));
                }
                R.Ok("控制面板里能看到「" + Info.AppName + "」了");
            }
            catch (Exception ex) { R.Warn("注册失败(不影响使用):" + ex.Message); }
        }

        long DirSize()
        {
            try
            {
                long n = 0;
                foreach (string f in Directory.GetFiles(Dir)) n += new FileInfo(f).Length;
                return n;
            }
            catch { return 0; }
        }

        void MakeShortcuts()
        {
            string app = Path.Combine(Dir, Info.AppExe);
            if (Desktop)
            {
                R.Step("创建桌面快捷方式");
                string lnk = Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.DesktopDirectory), Info.AppName + ".lnk");
                if (Shell.Shortcut(lnk, app, Dir)) R.Ok("桌面"); else R.Warn("桌面快捷方式没建上");
            }
            if (StartMenu)
            {
                R.Step("创建开始菜单快捷方式");
                string dir = Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.Programs), Info.AppName);
                try
                {
                    Directory.CreateDirectory(dir);
                    bool a = Shell.Shortcut(Path.Combine(dir, Info.AppName + ".lnk"), app, Dir);
                    Shell.Shortcut(Path.Combine(dir, "卸载 " + Info.AppName + ".lnk"),
                                   Path.Combine(Dir, Info.UninExe), Dir);
                    if (a) R.Ok("开始菜单 \\ " + Info.AppName); else R.Warn("开始菜单快捷方式没建上");
                }
                catch (Exception ex) { R.Warn("开始菜单没建上:" + ex.Message); }
            }
        }

        public bool Uninstall()
        {
            try
            {
                R.Phase("正在卸载");
                CloseRunning();
                if (!KeepPlugins && !CapturePlugins.Uninstall(R)) return false;
                if (!KeepPlugins && !AllegroSkills.Apply(R, true)) return false;
                if (KeepPlugins) R.Note("按选择保留 Capture 插件和 Allegro SKILL。");
                UnShortcuts();
                UnRegister();
                UnFiles();
                R.Phase("卸载完成");
                return true;
            }
            catch (Exception ex) { R.Fail("卸载中断:" + ex.Message); return false; }
        }

        void UnShortcuts()
        {
            R.Step("删除快捷方式");
            int n = 0;
            try
            {
                string lnk = Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.DesktopDirectory), Info.AppName + ".lnk");
                if (File.Exists(lnk)) { File.Delete(lnk); n++; }
                string dir = Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.Programs), Info.AppName);
                if (Directory.Exists(dir)) { Directory.Delete(dir, true); n++; }
            }
            catch (Exception ex) { R.Warn("有快捷方式没删掉:" + ex.Message); }
            R.Ok("清掉 " + n + " 处");
        }

        void UnRegister()
        {
            R.Step("从控制面板注销");
            try { Registry.CurrentUser.DeleteSubKeyTree(Info.RegKey, false); R.Ok("注销了"); }
            catch (Exception ex) { R.Warn("注册表没清干净:" + ex.Message); }
        }

        // 卸载程序自己就在安装目录里,删不掉自己。所以:能删的先删,剩下自己和
        // (可选的)tools.local.ini 交给一个脱离的 cmd,等我们退出以后再删。
        void UnFiles()
        {
            R.Step("删除文件");
            string me = Path.GetFullPath(Assembly.GetExecutingAssembly().Location);
            string local = Path.Combine(Dir, "tools.local.ini");
            int done = 0; List<string> stuck = new List<string>();
            try
            {
                foreach (string f in Directory.GetFiles(Dir))
                {
                    if (f.Equals(me, StringComparison.OrdinalIgnoreCase)) continue;
                    if (KeepIni && f.Equals(local, StringComparison.OrdinalIgnoreCase)) continue;
                    try { File.SetAttributes(f, FileAttributes.Normal); File.Delete(f); done++; }
                    catch { stuck.Add(Path.GetFileName(f)); }
                }
            }
            catch (Exception ex) { R.Warn("扫目录出错:" + ex.Message); }

            // Remove only license files recorded in this version's embedded manifest.
            // Unknown user files inside LICENSES are preserved.
            foreach (string resource in LegalNotices.Names)
            {
                string relative = LegalNotices.FileName(resource);
                if (!relative.StartsWith("LICENSES" + Path.DirectorySeparatorChar, StringComparison.Ordinal)) continue;
                string file = Path.Combine(Dir, relative);
                try
                {
                    if (File.Exists(file)) { File.Delete(file); done++; }
                    string parent = Path.GetDirectoryName(file);
                    while (parent != Dir && Directory.Exists(parent)
                           && Directory.GetFileSystemEntries(parent).Length == 0)
                    {
                        Directory.Delete(parent);
                        parent = Path.GetDirectoryName(parent);
                    }
                }
                catch { stuck.Add(relative); }
            }
            R.Ok("删掉 " + done + " 个文件");
            if (stuck.Count > 0)
                R.Warn("这几个删不掉(可能还被占用):" + string.Join("、", stuck.ToArray()));
            if (KeepIni && File.Exists(local))
                R.Note("留下了你自己加的快捷方式配置:" + local);

            R.Step("清理安装目录");
            // KeepIni 时只删自己,目录留着(里面还有 tools.local.ini)。
            Shell.SelfDelete(me, KeepIni || stuck.Count > 0 ? null : Dir);
            R.Ok(KeepIni || stuck.Count > 0
                 ? "退出后会删掉卸载程序本身" : "退出后会删掉整个安装目录");
        }
    }

    static class Shell
    {
        // 建快捷方式。用晚绑定的 WScript.Shell,不引 COM 互操作程序集 —— 那个要
        // tlbimp 生成,构建期就得多一步,而 WScript.Shell 每台 Windows 都有。
        public static bool Shortcut(string lnk, string target, string workDir)
        {
            object sh = null;
            try
            {
                Type t = Type.GetTypeFromProgID("WScript.Shell");
                if (t == null) return false;
                sh = Activator.CreateInstance(t);
                object sc = t.InvokeMember("CreateShortcut", BindingFlags.InvokeMethod,
                                           null, sh, new object[] { lnk });
                Type st = sc.GetType();
                Set(st, sc, "TargetPath", target);
                Set(st, sc, "WorkingDirectory", workDir);
                Set(st, sc, "IconLocation", target + ",0");
                Set(st, sc, "Description", Info.AppName);
                st.InvokeMember("Save", BindingFlags.InvokeMethod, null, sc, new object[0]);
                return File.Exists(lnk);
            }
            catch { return false; }
            finally { if (sh != null) try { Marshal.ReleaseComObject(sh); } catch { } }
        }
        static void Set(Type t, object o, string name, object v)
        {
            t.InvokeMember(name, BindingFlags.SetProperty, null, o, new object[] { v });
        }

        // 让一个脱离的 cmd 等我们退出以后再删。
        //
        // ping 是延时手段:timeout 命令在没有交互输入的会话里会直接报错退出,
        // ping 到本机不会。/d "" 关掉 AutoRun,免得用户注册表里挂的东西干扰;
        // 工作目录设到系统盘根,不能设在要删的目录里,否则目录被自己占住删不掉。
        public static void SelfDelete(string exe, string dirToo)
        {
            string cmd = "ping 127.0.0.1 -n 3 >nul & del /f /q \"" + exe + "\"";
            if (dirToo != null) cmd += " & rd /s /q \"" + dirToo + "\"";
            try
            {
                ProcessStartInfo si = new ProcessStartInfo("cmd.exe", "/d /c " + cmd);
                si.UseShellExecute = false; si.CreateNoWindow = true;
                si.WindowStyle = ProcessWindowStyle.Hidden;
                si.WorkingDirectory = Path.GetPathRoot(Environment.SystemDirectory);
                Process.Start(si);
            }
            catch { }
        }

        public static void Open(string path)
        {
            try { Process.Start(new ProcessStartInfo(path) { UseShellExecute = true }); } catch { }
        }
    }

    // 右上角的关闭叉。无边框窗口没有系统标题栏,得自己给一个。
    class CloseBtn : Control
    {
        bool mHot;
        public CloseBtn()
        {
            SetStyle(ControlStyles.AllPaintingInWmPaint | ControlStyles.OptimizedDoubleBuffer
                     | ControlStyles.UserPaint, true);
            Size = new Size(40, 32); Cursor = Cursors.Hand;
        }
        protected override void OnMouseEnter(EventArgs e) { mHot = true;  Invalidate(); base.OnMouseEnter(e); }
        protected override void OnMouseLeave(EventArgs e) { mHot = false; Invalidate(); base.OnMouseLeave(e); }
        protected override void OnPaint(PaintEventArgs e)
        {
            Graphics g = e.Graphics;
            using (SolidBrush b = new SolidBrush(mHot ? Color.FromArgb(0xC0, 0x39, 0x2B) : Theme.BrandLo))
                g.FillRectangle(b, ClientRectangle);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            using (Pen p = new Pen(Color.White, 1.4f))
            {
                int cx = Width / 2, cy = Height / 2, r = 5;
                g.DrawLine(p, cx - r, cy - r, cx + r, cy + r);
                g.DrawLine(p, cx + r, cy - r, cx - r, cy + r);
            }
        }
    }

    class SetupForm : Form, IReport
    {
        readonly bool UnMode;      // true = 卸载界面
        readonly bool Silent;

        Panel mBody;
        Panel mCfg, mRun;          // 配置视图 / 进度视图,同一个窗口里换
        TextBox mPath;
        CheckBox mDesktop, mMenu, mKeepIni, mKeepPlugins, mForceCloseTools;
        FlatBtn mGo, mBrowse;
        FlatBar mBar;
        LogBox mLog;
        Label mPhase, mFoot;

        Worker mWorker;
        long mTotal = 1, mDone;
        bool mBusy, mDone2, mFailed;

        readonly string ForceDir;  // /dir= 给的,null = 用默认
        public bool Hold;          // /hold:静默装完也不关窗

        public SetupForm(bool unMode, bool silent, string dir)
        {
            UnMode = unMode; Silent = silent; ForceDir = dir;
            Build();
            if (!string.IsNullOrEmpty(ForceDir)) mPath.Text = ForceDir;
        }

        void Build()
        {
            Text = Info.AppName + (UnMode ? " 卸载" : " 安装程序");
            FormBorderStyle = FormBorderStyle.None;
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(660, UnMode ? 470 : 560);
            BackColor = Theme.Bg;
            // 留 1px 给上面 OnPaint 画的边框。Dock 的子控件会被这一圈挤进来,
            // 不留的话子控件铺满整个客户区,边框画了也看不见。
            Padding = new Padding(1);
            Font = Theme.UI(9.75f, FontStyle.Regular);
            MaximizeBox = false; MinimizeBox = false; ShowInTaskbar = true;
            Icon = LoadIcon(0);
            KeyPreview = true;
            KeyDown += delegate(object s, KeyEventArgs e)
            {
                // Esc 关窗,但装到一半不许关。
                if (e.KeyCode == Keys.Escape && !mBusy) Close();
            };

            Banner ban = new Banner(LoadIcon(48),
                UnMode ? "卸载" : "OrCAD / Allegro 工具集合 · v" + Info.Version);
            ban.Dock = DockStyle.Top;
            CloseBtn x = new CloseBtn();
            x.Click += delegate { if (!mBusy) Close(); };
            ban.Controls.Add(x);
            ban.Resize += delegate { x.Location = new Point(ban.Width - x.Width, 0); };

            mBody = new Panel { Dock = DockStyle.Fill, Padding = new Padding(24, 18, 24, 8) };
            mCfg = UnMode ? BuildUninstallView() : BuildConfigView();
            mCfg.Dock = DockStyle.Fill;
            mRun = BuildRunView();
            mRun.Dock = DockStyle.Fill;
            mRun.Visible = false;
            mBody.Controls.Add(mRun);
            mBody.Controls.Add(mCfg);

            Controls.Add(mBody);
            Controls.Add(BuildFooter());
            Controls.Add(ban);
        }

        // logo 从嵌进来的 ico 里按尺寸取,不用 ExtractAssociatedIcon —— 那个只给
        // 32x32,拉到 48 是糊的。指定尺寸时 Icon 会挑最接近的那一条。
        //
        // 注意别让 ico 里 48 这一条是 PNG 格式:GDI+ 读不了 ico 里的 PNG 条目
        // (资源管理器能显示,代码里拿到的是空的)。make-icons.ps1 里 ≤64 走 DIB。
        // 给 /selftest 用的入口,免得为了自检把 LoadIcon 放出去。
        internal static Icon TestIcon(int size) { return LoadIcon(size); }
        internal bool TestForceCloseToolsChecked
        {
            get { return mForceCloseTools != null && mForceCloseTools.Checked; }
        }
        internal bool TestKeepPluginsChecked
        {
            get { return mKeepPlugins != null && mKeepPlugins.Checked; }
        }

        static Icon LoadIcon(int size)
        {
            try
            {
                using (Stream s = Assembly.GetExecutingAssembly()
                                          .GetManifestResourceStream("logo.ico"))
                    if (s != null) return size > 0 ? new Icon(s, size, size) : new Icon(s);
            }
            catch { }
            try { return Icon.ExtractAssociatedIcon(Assembly.GetExecutingAssembly().Location); }
            catch { return null; }
        }

        // 一张卡片:白底、细边、圆角靠 Paint 画。放路径行和组件列表用。
        static Panel Card(int pad)
        {
            Panel p = new Panel { BackColor = Theme.Card, Padding = new Padding(pad) };
            p.Paint += delegate(object s, PaintEventArgs e)
            {
                Panel me = (Panel)s;
                using (Pen pen = new Pen(Theme.Line))
                    e.Graphics.DrawRectangle(pen, 0, 0, me.Width - 1, me.Height - 1);
            };
            return p;
        }

        static Label Head(string text)
        {
            return new Label { Text = text, AutoSize = true, ForeColor = Theme.Text,
                               Font = Theme.UI(10.5f, FontStyle.Bold),
                               Margin = new Padding(0, 0, 0, 6) };
        }

        static Control Gap(int h) { return new Panel { Height = h, Dock = DockStyle.Top }; }

        // 窗口不可缩放,所以直接摆绝对坐标 —— 比堆一层层 Dock 容器好读,也不会因为
        // Dock 的插入顺序把上下弄反。
        const int W = 612;

        Panel BuildConfigView()
        {
            // Keep all component choices reachable when the package gains tools.
            const int W = 590;
            Panel v = new Panel { AutoScroll = true };

            Label t1 = Head("安装位置");
            t1.Location = new Point(0, 0);

            Panel c1 = Card(0);
            c1.Bounds = new Rectangle(0, 26, W, 48);
            mPath = new TextBox {
                Text = Locate.Suggest(), BorderStyle = BorderStyle.None,
                Font = Theme.UI(10f, FontStyle.Regular), ForeColor = Theme.Text,
                Bounds = new Rectangle(12, 15, W - 12 - 104 - 12, 20) };
            mBrowse = new FlatBtn("浏览…", false) {
                Bounds = new Rectangle(W - 104, 8, 92, 32) };
            mBrowse.Click += OnBrowse;
            c1.Controls.Add(mPath);
            c1.Controls.Add(mBrowse);

            string old = Locate.InstalledVersion();
            Label hint = new Label {
                AutoSize = true, ForeColor = Theme.Dim, Font = Theme.UI(8.75f, FontStyle.Regular),
                Location = new Point(2, 80),
                Text = old != null
                     ? "检测到已装 v" + old + "，会覆盖安装；默认安装 Capture 插件和 Allegro SKILL"
                     : "无需管理员权限；默认安装 Capture 插件和 Allegro SKILL" };

            Label t2 = Head("可选组件");
            t2.Location = new Point(0, 106);

            Panel c2 = Card(0);
            c2.Bounds = new Rectangle(0, 132, W, 12 + Plan.Extras.Length * 60);
            int y = 10;
            foreach (Comp c in Plan.Extras)
            {
                c.Box = new CheckBox {
                    Text = c.Title + "   " + Mb(c.Size), AutoSize = true,
                    Checked = c.Default && c.Present, Enabled = c.Present,
                    ForeColor = c.Present ? Theme.Text : Theme.Dim,
                    Font = Theme.UI(10f, FontStyle.Regular),
                    Location = new Point(14, y), Cursor = Cursors.Hand };
                c.Box.CheckedChanged += delegate { UpdateGo(); };
                Label note = new Label {
                    Text = c.Present ? c.Note : "这个安装包里没带这个组件",
                    ForeColor = Theme.Dim, Font = Theme.UI(8.75f, FontStyle.Regular),
                    Location = new Point(34, y + 23), Size = new Size(W - 48, 30) };
                c2.Controls.Add(c.Box);
                c2.Controls.Add(note);
                y += 60;
            }

            mForceCloseTools = Tick("仅强制结束安装目录中精准匹配的工具进程及其子进程（可能丢失未保存内容）",
                                    true, 0, c2.Bottom + 12);
            mDesktop = Tick("创建桌面快捷方式", true, 0, c2.Bottom + 42);
            mMenu    = Tick("添加到开始菜单",   true, 200, c2.Bottom + 42);

            v.Controls.AddRange(new Control[] {
                t1, c1, hint, t2, c2, mForceCloseTools, mDesktop, mMenu
            });
            return v;
        }

        static CheckBox Tick(string text, bool on, int x, int y)
        {
            return new CheckBox { Text = text, Checked = on, AutoSize = true,
                                  ForeColor = Theme.Text, Cursor = Cursors.Hand,
                                  Location = new Point(x, y) };
        }

        static string Mb(long n)
        {
            if (n <= 0) return "";
            return n >= 1048576 ? "(" + (n / 1048576.0).ToString("0.0") + " MB)"
                                : "(" + (n / 1024.0).ToString("0") + " KB)";
        }

        Panel BuildUninstallView()
        {
            Panel v = new Panel();
            string dir = Locate.Installed() ?? AppDomain.CurrentDomain.BaseDirectory;

            Label t1 = Head("要卸载 " + Info.AppName + " 吗");
            t1.Location = new Point(0, 4);

            Panel c1 = Card(0);
            c1.Bounds = new Rectangle(0, 34, W, 96);
            Label body = new Label {
                Font = Theme.UI(9.75f, FontStyle.Regular), ForeColor = Theme.Text,
                Bounds = new Rectangle(14, 12, W - 28, 96),
                Text = "会删掉:\n"
                     + "    · " + dir + " 下的程序文件\n"
                     + "    · 桌面和开始菜单的快捷方式,以及控制面板里的条目\n"
                     + "    · 可选择保留或停用 Cadence 插件（Capture / Allegro SKILL）" };
            c1.Controls.Add(body);

            c1.Height = 122;
            mKeepPlugins = Tick("保留 Cadence 插件（Capture / Allegro SKILL，默认）", true, 2, 170);
            mKeepIni = Tick("保留我自己添加的软件快捷方式配置(tools.local.ini)", true, 2, 202);
            Label hint = new Label {
                Text = "取消后恢复 Capture 插件备份并停用 Allegro SKILL；重启 Cadence 后生效。",
                AutoSize = true, ForeColor = Theme.Dim,
                Font = Theme.UI(8.75f, FontStyle.Regular), Location = new Point(22, 226) };

            mPath = new TextBox { Text = dir, Visible = false };  // Worker 从这儿取目录
            v.Controls.AddRange(new Control[] {
                t1, c1, mKeepPlugins, mKeepIni, hint, mPath
            });
            return v;
        }

        Panel BuildRunView()
        {
            Panel v = new Panel();
            mPhase = new Label {
                Text = "准备中", AutoSize = true, ForeColor = Theme.Text,
                Font = Theme.UI(11.5f, FontStyle.Bold), Location = new Point(0, 2) };
            mBar = new FlatBar { Bounds = new Rectangle(0, 32, W, 8) };
            Panel c = Card(1);
            c.Bounds = new Rectangle(0, 54, W, (UnMode ? 470 : 560) - 96 - 54 - 62 - 18);
            mLog = new LogBox { Dock = DockStyle.Fill };
            c.Controls.Add(mLog);
            v.Controls.AddRange(new Control[] { mPhase, mBar, c });
            return v;
        }

        Panel BuildFooter()
        {
            Panel f = new Panel { Dock = DockStyle.Bottom, Height = 62, BackColor = Theme.Bg };
            f.Paint += delegate(object s, PaintEventArgs e)
            {
                using (Pen p = new Pen(Theme.Line))
                    e.Graphics.DrawLine(p, 0, 0, ((Panel)s).Width, 0);
            };
            mFoot = new Label { AutoSize = true, ForeColor = Theme.Dim,
                                Font = Theme.UI(8.75f, FontStyle.Regular),
                                Location = new Point(24, 23), Text = "v" + Info.Version };
            mGo = new FlatBtn(UnMode ? "卸载" : "安装", true) { Size = new Size(132, 40) };
            mGo.Click += OnGo;
            FlatBtn cancel = new FlatBtn("关闭", false) { Size = new Size(88, 40) };
            cancel.Click += delegate { if (!mBusy) Close(); };
            f.Resize += delegate
            {
                mGo.Location = new Point(f.Width - 24 - mGo.Width, 12);
                cancel.Location = new Point(mGo.Left - 10 - cancel.Width, 12);
            };
            f.Controls.AddRange(new Control[] { mFoot, mGo, cancel });
            return f;
        }

        void UpdateGo()
        {
            if (mGo == null) return;
            long n = 0;
            foreach (Comp c in Plan.All) if (c.Wanted && c.Present) n += c.Size;
            mFoot.Text = "v" + Info.Version + "   共 " + Mb(n).Trim('(', ')');
        }

        void OnBrowse(object s, EventArgs e)
        {
            using (FolderBrowserDialog d = new FolderBrowserDialog())
            {
                d.Description = "选择安装位置";
                d.ShowNewFolderButton = true;
                try { d.SelectedPath = mPath.Text; } catch { }
                if (d.ShowDialog(this) != DialogResult.OK) return;
                string p = d.SelectedPath;
                // 选了个已经有别的东西的目录就自动加一层子目录,不然文件会散在人家
                // 目录里,卸载时也不好整个删。选到我们自己的目录则原样用。
                if (!Path.GetFileName(p.TrimEnd(Path.DirectorySeparatorChar))
                          .Equals(Info.DirName, StringComparison.OrdinalIgnoreCase))
                    p = Path.Combine(p, Info.DirName);
                mPath.Text = p;
            }
        }

        void OnGo(object s, EventArgs e)
        {
            if (mDone2) { Finish(); return; }
            if (mBusy) return;
            Start();
        }

        void Start()
        {
            string dir = mPath.Text.Trim();
            if (!UnMode)
            {
                string bad = Locate.Check(dir);
                if (bad != null)
                {
                    MessageBox.Show(this, bad, "安装位置不对", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    mPath.Focus(); mPath.SelectAll();
                    return;
                }
                dir = Path.GetFullPath(dir);
            }

            mBusy = true; mFailed = false; mDone = 0;
            mCfg.Visible = false; mRun.Visible = true;
            mGo.Enabled = false; mGo.Text = UnMode ? "卸载中…" : "安装中…";
            mFoot.Text = "进行中,请不要关窗口";

            mWorker = new Worker(this, dir);
            if (!UnMode)
            {
                mWorker.Desktop = mDesktop.Checked;
                mWorker.StartMenu = mMenu.Checked;
                mWorker.ForceCloseTools = mForceCloseTools.Checked;
            }
            else
            {
                mWorker.KeepIni = mKeepIni.Checked;
                mWorker.KeepPlugins = mKeepPlugins.Checked;
            }
            mTotal = mWorker.Total();

            Thread t = new Thread(delegate()
            {
                bool ok = UnMode ? mWorker.Uninstall() : mWorker.Install();
                try { BeginInvoke((MethodInvoker)delegate { Ended(ok); }); } catch { }
            });
            t.IsBackground = true;
            t.SetApartmentState(ApartmentState.STA);  // WScript.Shell 要 STA
            t.Start();
        }

        void Ended(bool ok)
        {
            mBusy = false; mDone2 = ok; mFailed = !ok;
            mBar.Value = ok ? 1 : mBar.Value;
            mGo.Enabled = true;
            if (ok)
            {
                mGo.Text = UnMode ? "完成" : "启动";
                mFoot.Text = UnMode ? "已卸载" : "装好了,点右边直接打开";
            }
            else
            {
                mGo.Text = "重试"; mDone2 = false;
                mFoot.ForeColor = Theme.Bad;
                mFoot.Text = "没走完,看上面的日志";
            }
            if (Silent && !Hold) Close();
        }

        void Finish()
        {
            if (!UnMode)
            {
                string exe = Path.Combine(mPath.Text.Trim(), Info.AppExe);
                if (File.Exists(exe)) Shell.Open(exe);
            }
            Close();
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            // 装到一半关掉会留下半个目录,拦住。
            if (mBusy)
            {
                e.Cancel = true;
                MessageBox.Show(this, "正在进行中,等它走完再关。", Info.AppName,
                                MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            base.OnFormClosing(e);
        }

        // ---- IReport:后台线程调过来的,所以每个都要 Invoke 回 UI 线程 ----
        void Post(MethodInvoker fn)
        {
            if (IsDisposed) return;
            try { if (InvokeRequired) BeginInvoke(fn); else fn(); } catch { }
        }
        // 步骤前缀用 ASCII 的 >:Consolas 没有 ▸,会掉成一个小点,跟下一行的
        // ✓ 挤在一起分不出层级。✓ ! ✗ 这几个 Consolas 有。
        public void Step(string w) { Post(delegate { mLog.Put("> " + w, Theme.Text); }); }
        public void Ok(string w)   { Post(delegate { mLog.Put("    ✓ " + w, Theme.Ok); }); }
        public void Warn(string w) { Post(delegate { mLog.Put("    ! " + w, Theme.Warn); }); }
        public void Fail(string w) { Post(delegate { mLog.Put("    ✗ " + w, Theme.Bad); }); }
        public void Note(string w) { Post(delegate { mLog.Put("    " + w, Theme.Dim); }); }
        public void Phase(string w){ Post(delegate { mPhase.Text = w; }); }
        public void Bytes(long n)
        {
            // 这个一秒能来上百次。累加在后台线程做,只把算好的比例丢过去,
            // FlatBar 自己会忽略太小的变化。
            mDone += n;
            double v = (double)mDone / mTotal;
            Post(delegate { mBar.Value = v; });
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            UpdateGo();
            // 焦点给【安装】,不要落在路径框上 —— 落在那儿的话路径整条是蓝的选中态,
            // 像是在等人改,而大多数人是直接点安装的。
            if (mGo != null) mGo.Focus();
            if (mPath != null) mPath.SelectionLength = 0;
            if (Silent) Start();       // /silent:界面照样显示,但不用点按钮
        }

        // 无边框窗口在浅色桌面上没有边,画一条细边框把窗口框住。
        protected override void OnPaint(PaintEventArgs e)
        {
            base.OnPaint(e);
            using (Pen p = new Pen(Color.FromArgb(0xC3, 0xD2, 0xDF)))
                e.Graphics.DrawRectangle(p, 0, 0, Width - 1, Height - 1);
        }
    }

    static class Program
    {
        [STAThread]
        static int Main(string[] argv)
        {
            bool un = false, silent = false, hold = false;
            string dir = null;
#if UNINSTALLER
            // 这一份编出来叫 uninstall.exe,注册表里的 UninstallString 不带参数,
            // 所以默认就走卸载。
            un = true;
#endif
            foreach (string a in argv)
            {
                string s = a.TrimStart('-', '/').ToLowerInvariant();
                if (s == "uninstall" || s == "u") un = true;
                else if (s == "silent" || s == "s" || s == "q") silent = true;
                else if (s.StartsWith("dir=")) dir = a.Substring(a.IndexOf('=') + 1).Trim('"');
                else if (s == "selftest") return SelfTest();
                // /silent 装完自己关窗,加上 /hold 就不关 —— 给截图和人工核对用。
                else if (s == "hold") hold = true;
                else if (s == "help" || s == "?" || s == "h")
                {
                    // 控制台程序才有 stdout,这是 winexe,所以用弹窗。
                    MessageBox.Show(
                        Info.AppName + " 安装程序 v" + Info.Version + "\n\n"
                        + "    /uninstall   卸载\n"
                        + "    /silent      不等点按钮,直接开始并在完成后关窗\n"
                        + "    /dir=<路径>  装到指定目录(默认用户目录下)\n"
                        + "    /selftest    自检载荷和界面,结果写到 %TEMP%\n"
                        + "    /help        这段话",
                        Info.AppName, MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 0;
                }
                // 认不出来的开关直接忽略,不当成路径处理 —— 以前踩过这个坑。
            }

            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try
            {
                SetupForm f = new SetupForm(un, silent, dir) { Hold = hold };
                Application.Run(f);
                return 0;
            }
            catch (Exception ex)
            {
                MessageBox.Show("启动失败:" + ex.Message, Info.AppName,
                                MessageBoxButtons.OK, MessageBoxIcon.Error);
                return 1;
            }
        }

        // 不装东西也不弹窗,只检查载荷齐不齐、logo 画不画得出来、界面能不能建起来。
        //
        // 为什么要有这个:界面上的东西没法自动看。截图这条路走不通 —— PrintWindow
        // 对 WinForms 出黑图,UIA 又会抓到别的程序上去(看着通过了,其实测的不是
        // 这个窗口)。所以改成让程序自己报告能不能构造、能不能画。
        // winexe 没有 stdout,结果写文件。
        static int SelfTest()
        {
            StringBuilder sb = new StringBuilder();
            int pass = 0, fail = 0;
            Action<string, bool, string> t = delegate(string name, bool ok, string extra)
            {
                sb.AppendLine((ok ? "  [ok]   " : "  [FAIL] ") + name
                              + (string.IsNullOrEmpty(extra) ? "" : "  -- " + extra));
                if (ok) pass++; else fail++;
            };

            sb.AppendLine("自检 " + Info.AppName + " 安装程序 v" + Info.Version);
            sb.AppendLine();
            sb.AppendLine("嵌进来的资源:");
            foreach (string n in Assembly.GetExecutingAssembly().GetManifestResourceNames())
                sb.AppendLine("    " + n.PadRight(24) + Payload.Size(n).ToString("N0") + " 字节");
            sb.AppendLine();

            foreach (string name in new string[] { "legal.LICENSE", "legal.COPYRIGHT", "legal.THIRD_PARTY_NOTICES.md", "legal.SOURCE_CODE.txt", "legal.BUILD_ENVIRONMENT.json" })
                t("License/source notice " + name, Payload.Has(name), "");
            string legalExtraction = LegalNotices.TestExtraction();
            t("License/source notices extract correctly", legalExtraction == null, legalExtraction);

            foreach (Comp c in Plan.Core)
                t("核心 " + c.File, c.Present, c.Present ? Payload.Size(c.Res).ToString("N0") + " 字节" : "载荷里没有");
            foreach (Comp c in Plan.Extras)
                t("组件 " + c.File, c.Present, c.Present ? Payload.Size(c.Res).ToString("N0") + " 字节" : "载荷里没有");
            foreach (string name in CapturePlugins.Names)
                t("Capture 插件 " + name, Payload.Has(name),
                  Payload.Has(name) ? Payload.Size(name).ToString("N0") + " 字节" : "载荷里没有");
            foreach (string name in AllegroSkills.Names)
                t("Allegro SKILL 载荷 " + name, Payload.Has(name), "");
            string skillLifecycle = AllegroSkills.TestLifecycle();
            t("Allegro SKILL 安装/升级/停用及原配置字节保留", skillLifecycle == null, skillLifecycle ?? "");
            string pluginLifecycle = CapturePlugins.TestLifecycle();
            t("Capture 插件安装/升级/卸载恢复",
              pluginLifecycle == null, pluginLifecycle ?? "");

            // logo:构造出来不算,得真画一遍。ico 里的 PNG 条目能构造、Size 也对,
            // 但 DrawIcon 会抛 "Requested range extends past the end of the array"。
            try
            {
                Icon ic = SetupForm.TestIcon(48);
                bool drew = false;
                if (ic != null)
                    using (Bitmap bmp = new Bitmap(48, 48))
                    {
                        using (Graphics g = Graphics.FromImage(bmp))
                            g.DrawIcon(ic, new Rectangle(0, 0, 48, 48));
                        int opaque = 0;
                        for (int y = 0; y < 48; y += 3)
                            for (int x = 0; x < 48; x += 3)
                                if (bmp.GetPixel(x, y).A > 32) opaque++;
                        drew = opaque > 20;
                        t("logo 画出来不是空的", drew, opaque + "/256 像素");
                    }
                else t("logo 画出来不是空的", false, "拿不到 Icon");
                if (ic != null) ic.Dispose();
            }
            catch (Exception ex) { t("logo 画出来不是空的", false, ex.Message); }

            // 界面构造。摆位置、算大小的代码全在这一步跑,越界或者空引用会当场炸。
            try
            {
                Application.EnableVisualStyles();
                using (SetupForm f = new SetupForm(false, false, null))
                {
                    f.CreateControl();
                    t("安装界面能建起来", true, f.ClientSize.Width + "x" + f.ClientSize.Height);
                    t("每个可选组件都有复选框", CountBoxes() == Plan.Extras.Length,
                      CountBoxes() + "/" + Plan.Extras.Length);
                    t("默认勾选强制结束工具进程", f.TestForceCloseToolsChecked,
                      f.TestForceCloseToolsChecked ? "" : "安装选项未默认勾选");
                }
                using (SetupForm f = new SetupForm(true, false, null))
                {
                    f.CreateControl();
                    t("卸载界面能建起来", true, f.ClientSize.Width + "x" + f.ClientSize.Height);
                    t("卸载默认保留 Capture 插件", f.TestKeepPluginsChecked,
                      f.TestKeepPluginsChecked ? "" : "插件保留选项未默认勾选");
                }
            }
            catch (Exception ex) { t("界面能建起来", false, ex.ToString()); }

            string volumeRoot = Path.GetPathRoot(Environment.SystemDirectory);
            t("拒绝将工具安装到磁盘根目录",
              Locate.Check(volumeRoot) != null,
              "磁盘根目录被安装位置检查接受");

            string targetExe = Path.Combine(Path.GetTempPath(), "xk-tools", "sample.exe");
            string otherExe = Path.Combine(Path.GetTempPath(), "other-tools", "sample.exe");
            t("目标进程路径按完整路径精确匹配",
              Worker.TestIsTargetProcessPath(targetExe, targetExe.ToUpperInvariant())
                  && !Worker.TestIsTargetProcessPath(targetExe, otherExe),
              "同名但位于其他目录的 EXE 不应命中");

            try
            {
                var startInfo = new ProcessStartInfo(
                    Path.Combine(Environment.SystemDirectory, "cmd.exe"),
                    "/d /c ping 127.0.0.1 -n 30 >nul")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using (Process child = Process.Start(startInfo))
                {
                    if (child == null) throw new InvalidOperationException("无法启动自检进程。");
                    int id = child.Id;
                    string error = Worker.TestKillTree(child);
                    bool stopped = !ProcessExists(id);
                    t("强制结束工具进程树", stopped && error == null,
                      error ?? (stopped ? "" : "进程仍在运行"));
                }
            }
            catch (Exception ex) { t("强制结束工具进程树", false, ex.Message); }

            sb.AppendLine();
            sb.AppendLine(fail == 0 ? "  " + pass + " 项全过" : "  " + pass + " 过 / " + fail + " 失败");
            string log = Path.Combine(Path.GetTempPath(), "xiaokai-setup-selftest.txt");
            // UTF-8 带 BOM:记事本打开中文才不乱码。
            File.WriteAllText(log, sb.ToString(), new UTF8Encoding(true));
            return fail == 0 ? 0 : 1;
        }

        static int CountBoxes()
        {
            int n = 0;
            foreach (Comp c in Plan.Extras) if (c.Box != null) n++;
            return n;
        }

        static bool ProcessExists(int id)
        {
            try
            {
                using (Process p = Process.GetProcessById(id)) return !p.HasExited;
            }
            catch (ArgumentException) { return false; }
        }
    }
}
