// SPDX-License-Identifier: GPL-3.0-only
// ==========================================================================
//  小开工具箱 - 单文件 WinForms 启动器
// ==========================================================================
//
//  用 csc.exe 编译成单个 exe,不需要装任何东西:
//      powershell -File build.ps1
//
//  工具清单在 tools.ini 里,加工具不用改这个文件。
//
//  为什么是 C# 而不是 TCL:要从 allegro.exe / Capture.exe 里直接抽真实图标,
//  System.Drawing 一行就够;Tk 得先把图标导成 PNG 放磁盘上。而且编译出来是
//  单个 exe,不依赖 SPB 的 wish.exe —— 工具箱本身要能在 SPB 装歪了的机器上
//  启动起来告诉用户"没找到 SPB",用 SPB 的解释器写就自相矛盾了。
//
// ==========================================================================

using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using Microsoft.Win32;

// 版本号写进 exe 的资源里,不只是界面上那行字。安装脚本靠读它来判断机器上
// 装的是哪一版("replacing version X with Y"),不写这个属性的话 csc 会填
// 0.0.0.0,那句话就永远是错的。两处必须一致,自检里有一条在盯这个
// (MainForm.Version 对 AssemblyVersion)。
[assembly: System.Reflection.AssemblyFileVersion("1.6.47.0")]
[assembly: System.Reflection.AssemblyVersion("1.6.47.0")]
[assembly: System.Reflection.AssemblyTitle("小开工具箱")]

namespace CadenceToolbox
{
    // 一个工具条目。字段和 tools.ini 里的键一一对应。
    class Tool
    {
        public string Name;
        public string Category;
        public string Exe;
        public string Args = "";
        public string Desc = "";

        // 详细说明,单击图标后显示在底部。ini 是一行一个键,所以换行在里面写成
        // 字面的 \n,读进来再还原 —— 不这么做就得发明一种多行续行语法,
        // 而清单是给人手写的,多一种语法就多一种写错的方式。
        public string Help = "";
        public string IconFrom;      // 空 = 从 Exe 自己抽
        public bool Exists;          // 解析完就定下来,界面据此灰显
        public string Missing;       // Exists 为 false 时的原因

        // Cadence 自带的还是自研的。每个分类页面按这个上下分区:上半 Cadence
        // 原厂工具,下半自研工具。分开是因为这两类东西的性质不一样 —— 原厂的
        // 装在 SPB 里跟着 Cadence 走,自研的是我们自己发的、要能单独卸。
        public bool Mine;

        // 自研工具的卸载命令,右键菜单用。空 = 绿色版,没什么可卸的。
        public string Uninstall = "";
        public string UninstallExe = "";
        public string UninstallArgs = "";
        public string UninstallEnv = "";
        public string UninstallProbe = "";

        public bool HasUninstaller
        {
            get { return !string.IsNullOrEmpty(UninstallExe) || !string.IsNullOrEmpty(Uninstall); }
        }

        public bool CanUninstall
        {
            get
            {
                return HasUninstaller && IsUninstallTargetPresent(UninstallProbe);
            }
        }

        public static bool IsUninstallTargetPresent(string probe)
        {
            if (string.IsNullOrWhiteSpace(probe)) return true;
            foreach (string path in probe.Split('|'))
            {
                string expanded = Paths.Expand(path.Trim());
                if (!string.IsNullOrEmpty(expanded) && File.Exists(expanded)) return true;
            }
            return false;
        }

        // 来自 tools.local.ini,也就是用户自己用"添加其他软件"加的。
        // 只有这种才给"从工具箱移除" —— 随包那份是升级时要被覆盖的,
        // 从界面上删掉它下次装新版又会回来,那个按钮等于骗人。
        public bool Local;

        // 非空表示这个工具来自用户安装的 ZIP 工具包。用于移除时清理包目录。
        public string PackageRoot = "";
        public string PackageId = "";

        public string IconSource
        {
            get { return string.IsNullOrEmpty(IconFrom) ? Exe : IconFrom; }
        }
    }

    static class ToolProcessManager
    {
        sealed class TrackedProcess
        {
            public Process Process;
            public string Name;
        }

        static readonly object sLock = new object();
        static readonly List<TrackedProcess> sProcesses = new List<TrackedProcess>();

        public static Process Start(ProcessStartInfo startInfo, string name)
        {
            Process process = Process.Start(startInfo);
            if (process == null)
                throw new InvalidOperationException("Windows 没有启动 " + name + "。");

            lock (sLock)
            {
                sProcesses.Add(new TrackedProcess { Process = process, Name = name });
            }
            return process;
        }

        public static bool IsRunning(int processId)
        {
            try
            {
                using (Process process = Process.GetProcessById(processId))
                    return !process.HasExited;
            }
            catch (ArgumentException)
            {
                return false;
            }
        }

        public static string CloseAll(int graceMilliseconds)
        {
            List<TrackedProcess> processes;
            lock (sLock)
            {
                processes = new List<TrackedProcess>(sProcesses);
                sProcesses.Clear();
            }

            var errors = new StringBuilder();
            var active = new List<TrackedProcess>();
            foreach (TrackedProcess tracked in processes)
            {
                try
                {
                    if (tracked.Process.HasExited) continue;
                    tracked.Process.CloseMainWindow();
                    active.Add(tracked);
                }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception ex)
                {
                    AppendError(errors, tracked.Name, ex.Message);
                    active.Add(tracked);
                }
            }

            DateTime deadline = DateTime.UtcNow.AddMilliseconds(Math.Max(0, graceMilliseconds));
            while (DateTime.UtcNow < deadline)
            {
                bool anyRunning = false;
                foreach (TrackedProcess tracked in active)
                {
                    try { if (!tracked.Process.HasExited) { anyRunning = true; break; } }
                    catch (InvalidOperationException) { }
                    catch (System.ComponentModel.Win32Exception ex)
                    {
                        AppendError(errors, tracked.Name, ex.Message);
                        anyRunning = true;
                        break;
                    }
                }
                if (!anyRunning) break;
                int remaining = (int)Math.Max(1, (deadline - DateTime.UtcNow).TotalMilliseconds);
                Thread.Sleep(Math.Min(100, remaining));
            }

            foreach (TrackedProcess tracked in active)
            {
                try
                {
                    if (!tracked.Process.HasExited)
                    {
                        string error = KillProcessTree(tracked.Process);
                        if (!string.IsNullOrEmpty(error))
                            AppendError(errors, tracked.Name, error);
                    }
                }
                catch (InvalidOperationException) { }
                catch (System.ComponentModel.Win32Exception ex)
                {
                    AppendError(errors, tracked.Name, ex.Message);
                }
            }

            foreach (TrackedProcess tracked in processes)
                tracked.Process.Dispose();
            return errors.ToString();
        }

        static string KillProcessTree(Process process)
        {
            string taskkill = Path.Combine(Environment.SystemDirectory, "taskkill.exe");
            string treeError = "";
            try
            {
                var startInfo = new ProcessStartInfo(taskkill, "/PID " + process.Id + " /T /F")
                {
                    UseShellExecute = false,
                    CreateNoWindow = true
                };
                using (Process killer = Process.Start(startInfo))
                {
                    if (killer == null) throw new InvalidOperationException("无法启动 taskkill.exe。");
                    if (!killer.WaitForExit(5000))
                    {
                        killer.Kill();
                        treeError = "taskkill.exe 等待超时。";
                    }
                    else if (killer.ExitCode != 0 && !process.HasExited)
                        treeError = "taskkill.exe 未能结束进程。";
                }
            }
            catch (Exception ex)
            {
                treeError = ex.Message;
            }

            try
            {
                if (!process.HasExited)
                {
                    process.Kill();
                    if (!process.WaitForExit(3000))
                        return "强制结束请求已发送，但主进程仍在运行。";
                }
            }
            catch (Exception ex)
            {
                return "结束进程树失败：" + treeError + "；结束主进程失败：" + ex.Message;
            }
            return treeError;
        }

        static void AppendError(StringBuilder errors, string name, string message)
        {
            if (errors.Length > 0) errors.AppendLine();
            errors.Append(name).Append(": ").Append(message);
        }
    }

    static class Paths
    {
        public static string Spb;        // C:\orcad\Cadence\SPB_17.4
        public static string CadRoot;    // C:\orcad\Cadence
        public static string Toolbox;    // 工具箱 exe 所在目录
        public static string SpbFoundBy = "没找到";

        // 手动指定的目录存这儿。放注册表而不是 tools.local.ini:那个文件是
        // 工具清单,塞设置进去要给它另加一套段名规则。卸载时这个键会被删掉。
        const string SettingsKey = @"Software\XiaokaiToolbox";
        const string SpbValue = "SpbDir";

        // 探测 Cadence 安装位置。写死路径是不行的:这台机器就装在 C:\orcad\
        // 而不是默认的 C:\Cadence\,而安装程序允许装到任何地方。
        //
        // 顺序按可信度排:环境变量是用户/安装程序明确设的,注册表是安装程序写的,
        // 猜路径只是最后兜底。
        public static void Detect()
        {
            Toolbox = Path.GetDirectoryName(Application.ExecutablePath);
            Spb = null; CadRoot = null; SpbFoundBy = "没找到";

            // 手动指定的排最前面 —— 用户是因为自动探测判错了才去设它的,
            // 让任何自动结果盖过它都等于那个按钮没用。
            string man = LoadManual();
            // 手动选择过的根目录优先级最高。16.6 的安装结构与 17.x 不完全
            // 一样，不能只靠固定 exe 标记判断，否则重启后会退回自动探测。
            if (ManualRootIsUsable(man)) { Accept(man, "手动指定"); return; }

            foreach (string v in new[] { "CDS_INST_DIR", "SPB_17_4", "SPB_17_2",
                                         "SPB_16_6", "CDSROOT", "CDS_ROOT" })
            {
                string p = Environment.GetEnvironmentVariable(v);
                if (Ok(p)) { Accept(p, "环境变量 " + v); return; }
            }

            // 许可证文件反推。CDS_LIC_FILE 指向 ...\Cadence\LicenseManager\license.dat
            // (这台机器上就是),往上两级正好是 Cadence 根,下面就是 SPB_*。
            // 比盲扫盘可信得多:它是机器上真有 Cadence 许可的直接证据,而且和
            // 装在哪个盘、目录叫什么名字都无关。
            //
            // 文件名不能写死 cds.lic —— 这台机器上叫 license.dat。所以只用
            // 环境变量给的那个路径,不去猜文件名。
            foreach (string v in new[] { "CDS_LIC_FILE", "CDSLMD_LICENSE_FILE", "LM_LICENSE_FILE" })
            {
                string lic = Environment.GetEnvironmentVariable(v);
                string hit = FromLicense(lic);
                if (hit != null) { Accept(hit, "许可证 " + v); return; }
            }

            // 注册表。版本号不能写死:同一套键在 17.2 / 16.6 / 22.1 上叫别的名字,
            // 写死 17.4 就等于只认一个版本。所以枚举产品键下面的所有子键。
            //
            // 注意这台开发机上 Cadence Design Systems 底下只有 License Manager,
            // 产品键根本不存在 —— 别把"注册表读到了"当成理所当然的事。
            foreach (string bas in new[]
            {
                @"SOFTWARE\Cadence Design Systems",
                @"SOFTWARE\Wow6432Node\Cadence Design Systems",
            })
            {
                foreach (RegistryKey root in new[] { Registry.LocalMachine, Registry.CurrentUser })
                {
                    string hit = ScanReg(root, bas);
                    if (hit != null) { Accept(hit, "注册表"); return; }
                }
            }

            // 兜底:扫盘。盘符不写死 C/D/E —— 装在 F: 的机器上那样就找不到。
            // Program Files (x86) 是必须有的:16.x 是 32 位安装,默认就落在那儿。
            var mids = new[]
            {
                @"\Cadence", @"\orcad\Cadence", @"\OrCAD",
                @"\Program Files\Cadence", @"\Program Files (x86)\Cadence",
                @"\Program Files\OrCAD", @"\Program Files (x86)\OrCAD",
            };
            foreach (DriveInfo di in SafeDrives())
            {
                foreach (string mid in mids)
                {
                    string bas = di.Name.TrimEnd('\\') + mid;
                    if (!Directory.Exists(bas)) continue;
                    // 先看这一层自己是不是(OrCAD 16.6 直接装成 ...\OrCAD\OrCAD_16.6,
                    // 中间没有 SPB_ 那一级),再看下面的子目录。
                    if (Ok(bas)) { Accept(bas, "扫描 " + bas); return; }
                    string best = BestUnder(bas);
                    if (best != null) { Accept(best, "扫描 " + bas); return; }
                }
                string deep = FindProductOnDrive(di.RootDirectory.FullName, 4);
                if (deep != null) { Accept(deep, "扫描 " + di.RootDirectory.FullName); return; }
            }
        }

        static string FindProductOnDrive(string root, int depth)
        {
            if (depth < 0 || string.IsNullOrEmpty(root)) return null;
            try
            {
                foreach (string d in Directory.GetDirectories(root))
                {
                    string n = Path.GetFileName(d.TrimEnd('\\'));
                    if ((n.StartsWith("SPB_", StringComparison.OrdinalIgnoreCase) ||
                         n.StartsWith("OrCAD_", StringComparison.OrdinalIgnoreCase)) &&
                        (Ok(d) || LooksLikeCadenceRoot(d))) return d;
                    string hit = FindProductOnDrive(d, depth - 1);
                    if (hit != null) return hit;
                }
            }
            catch { }
            return null;
        }

        // 从许可证文件路径反推安装根:...\Cadence\LicenseManager\license.dat
        // 往上两级 = ...\Cadence,下面找产品目录。
        public static string FromLicense(string lic)
        {
            if (string.IsNullOrEmpty(lic)) return null;
            // CDS_LIC_FILE 也可以写成 5280@hostname 那种许可证服务器,那不是路径。
            // 不挡住的话 Path.GetDirectoryName 会抛,或者拿到个莫名其妙的结果。
            if (lic.IndexOf('@') >= 0) return null;
            // 可以是分号分隔的多个。
            foreach (string one in lic.Split(';'))
            {
                string p = one.Trim().Trim('"');
                if (p.Length == 0) continue;
                try
                {
                    // 给的可能是文件也可能是目录。
                    string dir = File.Exists(p) ? Path.GetDirectoryName(p) : p;
                    if (!Directory.Exists(dir)) continue;
                    // LicenseManager 自己不是安装根(里面没有 tools\bin),
                    // 所以要看它的父目录下面有什么。
                    string root = Path.GetDirectoryName(dir.TrimEnd('\\'));
                    if (string.IsNullOrEmpty(root)) continue;
                    if (Ok(root)) return root;
                    string best = BestUnder(root);
                    if (best != null) return best;
                }
                catch { }
            }
            return null;
        }

        // 一个目录下面所有合格的产品目录里,挑版本号最高的那个。
        //
        // 不能直接用 GetDirectories 的第一个:它是按字母序回来的,同时装了
        // SPB_16.6 和 SPB_17.4 的机器上会选中 16.6 —— 用户装了新版,工具箱却
        // 一直指着旧版,而界面上完全看不出选错了。
        public static string BestUnder(string bas)
        {
            var hits = new List<string>();
            try
            {
                foreach (string d in Directory.GetDirectories(bas))
                    if (Ok(d)) hits.Add(d);
            }
            catch { return null; }
            if (hits.Count == 0) return null;
            hits.Sort(delegate (string a, string b) { return CmpVer(b, a); });   // 降序
            return hits[0];
        }

        // 比目录名尾部的版本号。SPB_17.4 > SPB_16.6,OrCAD_16.6 > OrCAD_16.3。
        // 按段拆开比数值,不是比字符串 —— 字符串比法下 "17.10" < "17.4"。
        static int CmpVer(string a, string b)
        {
            int[] va = VerOf(a), vb = VerOf(b);
            for (int i = 0; i < Math.Max(va.Length, vb.Length); i++)
            {
                int x = i < va.Length ? va[i] : 0;
                int y = i < vb.Length ? vb[i] : 0;
                if (x != y) return x < y ? -1 : 1;
            }
            // 版本号一样(或都没有)就按名字排,至少让结果稳定、可复现。
            return string.Compare(Path.GetFileName(a), Path.GetFileName(b),
                StringComparison.OrdinalIgnoreCase);
        }

        static int[] VerOf(string dir)
        {
            string n = Path.GetFileName(dir.TrimEnd('\\'));
            // 取末尾那串数字和点,比如 SPB_17.4 -> 17.4
            int i = n.Length;
            while (i > 0 && (char.IsDigit(n[i - 1]) || n[i - 1] == '.')) i--;
            string tail = n.Substring(i).Trim('.');
            if (tail.Length == 0) return new int[0];
            string[] parts = tail.Split('.');
            var r = new List<int>();
            foreach (string s in parts)
            {
                int v;
                if (int.TryParse(s, out v)) r.Add(v);
            }
            return r.ToArray();
        }

        // 枚举 Cadence Design Systems 下面每个产品的每个版本,找 InstallDir 之类。
        static string ScanReg(RegistryKey root, string bas)
        {
            try
            {
                using (RegistryKey b = root.OpenSubKey(bas))
                {
                    if (b == null) return null;
                    foreach (string prod in b.GetSubKeyNames())
                    {
                        using (RegistryKey pk = b.OpenSubKey(prod))
                        {
                            if (pk == null) continue;
                            string hit = RegValues(pk);
                            if (hit != null) return hit;
                            foreach (string ver in pk.GetSubKeyNames())
                                using (RegistryKey vk = pk.OpenSubKey(ver))
                                    if (vk != null)
                                    {
                                        hit = RegValues(vk);
                                        if (hit != null) return hit;
                                    }
                        }
                    }
                }
            }
            catch { }
            return null;
        }

        static string RegValues(RegistryKey k)
        {
            foreach (string vn in new[] { "InstallDir", "SPB_ROOT", "Path", "ROOT", "InstallPath" })
            {
                try
                {
                    string p = k.GetValue(vn) as string;
                    if (string.IsNullOrEmpty(p)) continue;
                    if (Ok(p)) return p;
                    // 有些版本写的是 ...\tools\bin 或 ...\tools,不是安装根。
                    string up = ClimbToRoot(p);
                    if (up != null) return up;
                }
                catch { }
            }
            return null;
        }

        // 网络盘和空的光驱会让 Directory.Exists 卡上好几秒,所以只要固定盘。
        static List<DriveInfo> SafeDrives()
        {
            var r = new List<DriveInfo>();
            try
            {
                foreach (DriveInfo d in DriveInfo.GetDrives())
                    try { if (d.DriveType == DriveType.Fixed && d.IsReady) r.Add(d); }
                    catch { }
            }
            catch { }
            return r;
        }

        // 从任意一个路径往上爬,找到那个是 SPB 根的祖先目录。
        // "选一个 exe,其他自动找出来"就靠这个:用户指了 Capture.exe,
        // 从 ...\SPB_17.4\tools\bin\Capture.exe 往上三级就到根了。
        public static string ClimbToRoot(string any)
        {
            if (string.IsNullOrEmpty(any)) return null;
            string d;
            try
            {
                d = File.Exists(any) ? Path.GetDirectoryName(Path.GetFullPath(any))
                                     : Path.GetFullPath(any).TrimEnd('\\');
            }
            catch { return null; }

            // 上限 8 级:够从 tools\bin\ 爬到根,又不会一路爬到盘符去
            // 把 C:\ 认成安装目录。
            for (int i = 0; i < 8 && !string.IsNullOrEmpty(d); i++)
            {
                if (Ok(d)) return d;
                if (LooksLikeCadenceRoot(d)) return d;
                try { d = Path.GetDirectoryName(d); } catch { return null; }
            }
            return null;
        }

        // 手动指定。传 null 表示清掉、回到自动探测。
        // 返回 null = 成功,否则是给用户看的失败原因。
        public static string SetManual(string dir)
        {
            if (dir != null)
            {
                string root = ClimbToRoot(dir);
                if (root == null)
                    return "这里面找不到 Cadence 的程序。\n\n" + dir
                        + "\n\n请指到 Cadence 安装目录里任意一个程序(比如 Capture.exe),"
                        + "或者那个装了 tools\\bin 的目录本身。";
                dir = root;
            }
            try
            {
                if (dir == null)
                {
                    // 清设置时把整个键删掉,不是只删值。CreateSubKey 建过壳,
                    // 只 DeleteValue 会留一个空键在注册表里 —— 功能上没影响,
                    // 但那就是残留,卸载后也还在。
                    using (RegistryKey k = Registry.CurrentUser.OpenSubKey(SettingsKey, true))
                    {
                        if (k == null) return null;          // 本来就没有
                        k.DeleteValue(SpbValue, false);
                        // 只在确实空了的时候删键 —— 以后往这儿加别的设置时,
                        // 清一个路径不该把旁边的设置一起带走。
                        if (k.GetValueNames().Length == 0 && k.GetSubKeyNames().Length == 0)
                        {
                            k.Close();
                            Registry.CurrentUser.DeleteSubKey(SettingsKey, false);
                        }
                    }
                    return null;
                }
                using (RegistryKey k = Registry.CurrentUser.CreateSubKey(SettingsKey))
                {
                    if (k == null) return "打不开注册表 HKCU\\" + SettingsKey;
                    k.SetValue(SpbValue, dir, RegistryValueKind.String);
                }
            }
            catch (Exception ex) { return "存不进注册表。\n\n" + ex.Message; }
            return null;
        }

        public static string LoadManual()
        {
            try
            {
                using (RegistryKey k = Registry.CurrentUser.OpenSubKey(SettingsKey))
                    return k == null ? null : k.GetValue(SpbValue) as string;
            }
            catch { return null; }
        }

        // 存着但已经失效的手动路径(软件被挪走/卸掉了)。要拿来提示用户,
        // 不然界面只说"没探测到",而设置里明明存着一个路径,对不上。
        public static string StaleManual()
        {
            string m = LoadManual();
            return (!string.IsNullOrEmpty(m) && !Ok(m)) ? m : null;
        }

        // 认定一个目录是安装根的判据:下面这些里**任意一个**在就算。
        //
        // 以前只认 tools\bin\allegro.exe,那是个错的判据:只装 Capture、没装
        // Allegro/PCB Editor 的机器上这个文件不存在,于是整套 Cadence 工具全被
        // 判成"未安装" —— 而 Capture 明明能从开始菜单点开。用户看到的就是
        // "没有探测到 Cadence 安装目录,所有 Cadence 工具都不可用"。
        //
        // 所以判据必须覆盖到"只装了其中一个产品"的情况。switchversion.exe 放最后:
        // 它几乎总在,但不代表任何一个具体产品装了。
        static readonly string[] Markers =
        {
            @"tools\bin\capture.exe",
            @"tools\bin\allegro.exe",
            @"tools\capture\capture.exe",
            @"tools\pspice\pspice.exe",
            @"tools\bin\switchversion.exe",
        };

        static bool LooksLikeCadenceRoot(string p)
        {
            // Directory names and empty tools/bin trees also survive uninstall.
            // Require a real product marker for manual and fallback detection.
            return Ok(p);
        }

        static bool ManualRootIsUsable(string p)
        {
            return Ok(p) || LooksLikeCadenceRoot(p);
        }

        // 只看目录存在是不够的,卸载残留的空壳目录会骗过检查。
        static bool Ok(string p)
        {
            if (string.IsNullOrEmpty(p)) return false;
            foreach (string m in Markers)
            {
                try { if (File.Exists(Path.Combine(p, m))) return true; }
                catch { }   // 路径里有非法字符时 Combine 会抛,当作不匹配
            }
            return false;
        }

        static void Accept(string p, string how)
        {
            Spb = p.TrimEnd('\\');
            CadRoot = Path.GetDirectoryName(Spb);
            SpbFoundBy = how;
        }

        public static string Expand(string s)
        {
            if (string.IsNullOrEmpty(s)) return s;
            s = s.Replace("%SPB%", Spb ?? "");
            s = s.Replace("%CADROOT%", CadRoot ?? "");
            s = s.Replace("%TOOLBOX%", Toolbox ?? "");
            return Environment.ExpandEnvironmentVariables(s);
        }
    }

    static class Manifest
    {
        public static List<Tool> Tools = new List<Tool>();
        public static List<string> Categories = new List<string>();
        public static string Error;

        // 清空已解析的状态。界面只加载一次,用不到这个;自检要连着加载好几份
        // 不同的清单,不清干净就会互相累加。
        public static void Reset()
        {
            Tools.Clear();
            Categories.Clear();
            sSeen.Clear();
            Error = null;
        }

        // 同名覆盖要跨文件生效,所以 seen 不能是 Parse 的局部变量 ——
        // tools.local.ini 里重写一个已有工具(改参数、换路径)靠的就是这个。
        static Dictionary<string, Tool> sSeen = new Dictionary<string, Tool>();

        // 读两个文件:tools.ini 是随包发的,升级时会被覆盖;tools.local.ini
        // 是自己加的,装新版永远不动它。分开放是为了让"加工具"和"能升级"
        // 这两件事不互相踩 —— 合在一个文件里,升级要么冲掉你加的东西,
        // 要么新版带的工具永远进不来。
        // 最近一次 Load 用的随包清单路径。"添加其他软件"要据此算出
        // tools.local.ini 的位置,而那个位置只有 Load 知道。
        static string sIni = "";

        public static string LocalPath
        {
            get
            {
                if (sIni.Length == 0) return "";
                return Path.Combine(Path.GetDirectoryName(sIni), "tools.local.ini");
            }
        }

        // 重新读一遍两个清单。"添加其他软件"写完文件后调它,免得让用户重启。
        //
        // 必须先 Reset:Load 只往 Tools 里累加,不清。少了这一句,加一个工具
        // 之后每个工具都会变成两份 —— 而 sSeen 的同名覆盖会让它们指向同一个
        // 对象,所以界面上是两个一模一样的图标,看不出是哪里多出来的。
        public static void Reload()
        {
            if (sIni.Length == 0) return;
            string ini = sIni;
            Reset();
            Load(ini);
        }

        public static void Load(string path)
        {
            if (!File.Exists(path))
            {
                Error = "找不到清单文件 tools.ini\n应该和工具箱 exe 放在同一个目录:\n" + path;
                return;
            }
            string order = Parse(path, false);
            if (Error != null) return;

            sIni = path;
            string local = LocalPath;
            if (File.Exists(local))
            {
                string lo = Parse(local, true);
                // 本地清单写了 order 就以它为准,没写就沿用随包那份。
                // 只想加一两个工具的话不用写 order:新分类会自动补在末尾。
                if (!string.IsNullOrEmpty(lo)) order = lo;
                if (Error != null) return;
            }

            Resolve();
            BuildCategories(order);
        }

        // 解析一个清单文件,把工具累加进 Tools,返回它声明的 order(没有则为 null)。
        // local:这份是不是 tools.local.ini —— 决定条目能不能被"移除"。
        static string Parse(string path, bool local)
        {
            // UTF-8 读取。清单里全是中文说明,按系统 ANSI 读会变乱码。
            string[] lines;
            try { lines = File.ReadAllLines(path, Encoding.UTF8); }
            catch (Exception e)
            {
                Error = "读取 " + Path.GetFileName(path) + " 失败:" + e.Message;
                return null;
            }

            string order = null;
            Tool cur = null;

            foreach (string raw in lines)
            {
                string line = raw.Trim();
                if (line.Length == 0 || line[0] == ';' || line[0] == '#') continue;

                if (line[0] == '[' && line.EndsWith("]"))
                {
                    string name = line.Substring(1, line.Length - 2).Trim();
                    if (name.Equals("toolbox", StringComparison.OrdinalIgnoreCase))
                    {
                        cur = null;              // 这段是设置,不是工具
                        continue;
                    }
                    if (!local && IsDeferredTool(name) &&
                        !File.Exists(Paths.Expand("%TOOLBOX%\\" + DeferredExe(name))))
                    {
                        cur = null;
                        continue;
                    }
                    cur = new Tool { Name = name, Local = local };
                    // 同名工具后面的覆盖前面的,而不是出现两个一样的图标。
                    if (sSeen.ContainsKey(name)) Tools.Remove(sSeen[name]);
                    sSeen[name] = cur;
                    Tools.Add(cur);
                    continue;
                }

                int eq = line.IndexOf('=');
                if (eq < 0) continue;
                string key = line.Substring(0, eq).Trim().ToLowerInvariant();
                string val = line.Substring(eq + 1).Trim();

                if (cur == null)
                {
                    if (key == "order") order = val;
                    continue;
                }
                switch (key)
                {
                    case "category": cur.Category = val; break;
                    case "exe":      cur.Exe = val;      break;
                    case "args":     cur.Args = val;     break;
                    case "desc":     cur.Desc = val;     break;
                    case "help":     cur.Help = Unescape(val); break;
                    case "icon":     cur.IconFrom = val; break;
                    // mine = 1/true/yes 都算自研。写法不统一是迟早的事,
                    // 与其让人猜哪个才认,不如三个都认。
                    case "mine":
                        cur.Mine = (val == "1" || val.ToLowerInvariant() == "true"
                            || val.ToLowerInvariant() == "yes");
                        break;
                    case "uninstall": cur.Uninstall = val; break;
                    case "uninstall_exe": cur.UninstallExe = val; break;
                    case "uninstall_args": cur.UninstallArgs = val; break;
                    case "uninstall_env": cur.UninstallEnv = val; break;
                    case "uninstall_probe": cur.UninstallProbe = val; break;
                    case "package": cur.PackageId = val; break;
                    case "package_root": cur.PackageRoot = val; break;
                }
            }

            return order;
        }

        static bool IsDeferredTool(string name)
        {
            return name == "DWG 转 DXF" || name == "STEP 转 DXF" || name == "Gerber 转 DXF";
        }

        static string DeferredExe(string name)
        {
            return name == "DWG 转 DXF" ? "dwg2dxf.exe" :
                   (name == "STEP 转 DXF" ? "step2dxf.exe" : "gerber2dxf.exe");
        }

        // 把占位符展开成真实路径,并确定每个工具在不在。
        static void Resolve()
        {
            foreach (Tool t in Tools)
            {
                t.Exe = Paths.Expand(t.Exe);
                t.IconFrom = Paths.Expand(t.IconFrom);
                t.PackageRoot = Paths.Expand(t.PackageRoot);

                if (string.IsNullOrEmpty(t.Exe))
                {
                    t.Exists = false;
                    t.Missing = "清单里没写 exe 路径";
                }
                else if (!File.Exists(t.Exe))
                {
                    t.Exists = false;
                    // 分清两种缺失:整个 Cadence 没找到,还是单个工具没装。
                    // 前者要去修安装/环境变量,后者是这个组件没选装 —— 修法不同。
                    // 没探到时给出下一步怎么办,不然用户只知道"不可用"、不知道能修。
                    // 手动路径存着却失效了要单独说 —— 否则界面说没探到、设置里
                    // 明明有个路径,两边对不上,像是设置没生效。
                    string stale = Paths.StaleManual();
                    t.Missing = Paths.Spb == null
                        ? (stale != null
                            ? "手动指定的目录现在找不到 Cadence 了:" + stale
                              + " —— 用左下角「指定 Cadence 目录」重新指一下"
                            : "没有探测到 Cadence 安装目录。装了但没认出来的话,"
                              + "点左下角「指定 Cadence 目录」,挑一个 exe 就行")
                        : "这个组件没有安装:" + t.Exe;
                }
                else
                {
                    t.Exists = true;
                }
            }
        }

        // 分类顺序以 order 为准;order 里没提到但工具用到的分类补在后面,
        // 免得写清单时漏填 order 就让整组工具凭空消失。
        static void BuildCategories(string order)
        {
            if (!string.IsNullOrEmpty(order))
                foreach (string c in order.Split('|'))
                {
                    string n = c.Trim();
                    if (n.Length > 0 && !Categories.Contains(n)) Categories.Add(n);
                }

            foreach (Tool t in Tools)
                if (!string.IsNullOrEmpty(t.Category) && !Categories.Contains(t.Category))
                    Categories.Add(t.Category);
        }

        public static List<Tool> InCategory(string cat)
        {
            var r = new List<Tool>();
            foreach (Tool t in Tools) if (t.Category == cat) r.Add(t);
            return r;
        }

        // 把 help 里字面的 \n 还原成换行,\\ 还原成一个反斜杠。
        //
        // 一遍扫完而不是连着两次 Replace:先换 \\ 再换 \n 的话,写在说明里的
        // Windows 路径 "C:\\新库" 会先变成 "C:\新库",不出问题;但反过来先换
        // \n,"...\\newlib" 里的 \n 就被当成换行,路径断成两行。一遍扫过去
        // 每个转义只处理一次,没有这个先后问题。
        public static string Unescape(string s)
        {
            if (s.IndexOf('\\') < 0) return s;      // 绝大多数条目没有转义
            var sb = new System.Text.StringBuilder(s.Length);
            for (int i = 0; i < s.Length; i++)
            {
                if (s[i] != '\\' || i + 1 >= s.Length) { sb.Append(s[i]); continue; }
                char nx = s[i + 1];
                if (nx == 'n') { sb.Append('\n'); i++; }
                else if (nx == '\\') { sb.Append('\\'); i++; }
                // 不认识的转义原样留着 —— 说明里写 "C:\Cadence" 时那个 \C
                // 应该还是 \C,不该被吞掉。
                else sb.Append(s[i]);
            }
            return sb.ToString();
        }
    }

    // 图标缓存。同一个 exe 可能被多个条目引用(比如 Capture 和 Capture Viewer),
    // 抽一次就够 —— 每次重画都去读磁盘会让切分类明显卡顿。
    static class Icons
    {
        static Dictionary<string, Image> sCache = new Dictionary<string, Image>();

        public static Image For(Tool t)
        {
            string key = t.IconSource ?? "";
            return ForPath(key, t.Name);
        }

        public static Image ForPath(string path, string displayName)
        {
            string key = path ?? "";
            Image img;
            if (sCache.TryGetValue(key, out img)) return img;

            img = null;
            try
            {
                if (File.Exists(key))
                    using (Icon ico = Icon.ExtractAssociatedIcon(key))
                        if (ico != null) img = new Bitmap(ico.ToBitmap(), 32, 32);
            }
            catch { }

            if (img == null) img = Placeholder(displayName);
            sCache[key] = img;
            return img;
        }

        // 抽不到图标时画一个带首字母的方块,而不是留空白 ——
        // 空白会让人以为界面画坏了。
        static Image Placeholder(string name)
        {
            var bmp = new Bitmap(32, 32);
            using (Graphics g = Graphics.FromImage(bmp))
            {
                g.SmoothingMode = System.Drawing.Drawing2D.SmoothingMode.AntiAlias;
                using (var b = new SolidBrush(Color.FromArgb(120, 130, 145)))
                    g.FillRectangle(b, 2, 2, 28, 28);
                string s = string.IsNullOrEmpty(name) ? "?" : name.Substring(0, 1).ToUpperInvariant();
                using (var f = new Font("Segoe UI", 14, FontStyle.Bold))
                using (var b = new SolidBrush(Color.White))
                {
                    SizeF sz = g.MeasureString(s, f);
                    g.DrawString(s, f, b, (32 - sz.Width) / 2, (32 - sz.Height) / 2);
                }
            }
            return bmp;
        }
    }

    sealed class RecentDocument
    {
        public string Path;
        public DateTime LastOpened;
    }

    static class RecentDocuments
    {
        const uint SHARD_PATHW = 0x00000003;

        [System.Runtime.InteropServices.DllImport("shell32.dll",
            CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        static extern void SHAddToRecentDocs(uint flags, string path);

        public static string QuoteArgument(string value)
        {
            return "\"" + value.Replace("\"", "\\\"") + "\"";
        }

        public static bool HasExtension(string path, string extension)
        {
            return string.Equals(Path.GetExtension(path), extension,
                StringComparison.OrdinalIgnoreCase);
        }

        public static List<RecentDocument> Read(string extension, int limit)
        {
            if (extension != ".dsn" && extension != ".brd")
                throw new ArgumentException("Only DSN and BRD files are supported.", "extension");
            if (limit < 1) throw new ArgumentOutOfRangeException("limit");

            string recent = Environment.GetFolderPath(Environment.SpecialFolder.Recent);
            var results = new List<RecentDocument>();
            if (string.IsNullOrEmpty(recent) || !Directory.Exists(recent)) return results;

            Type shellType = Type.GetTypeFromProgID("WScript.Shell");
            if (shellType == null)
                throw new InvalidOperationException("Windows Script Host is unavailable; cannot read recent file shortcuts.");
            object shell = Activator.CreateInstance(shellType);
            try
            {
                string[] links = Directory.GetFiles(recent, "*.lnk");
                Array.Sort(links, delegate(string a, string b)
                {
                    return File.GetLastWriteTimeUtc(b).CompareTo(File.GetLastWriteTimeUtc(a));
                });

                var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
                foreach (string link in links)
                {
                    object shortcut = null;
                    try
                    {
                        shortcut = shellType.InvokeMember("CreateShortcut",
                            System.Reflection.BindingFlags.InvokeMethod, null, shell,
                            new object[] { link });
                        string target = Convert.ToString(shellType.InvokeMember("TargetPath",
                            System.Reflection.BindingFlags.GetProperty, null, shortcut, null));
                        if (!HasExtension(target, extension) || !File.Exists(target) || !seen.Add(target))
                            continue;
                        results.Add(new RecentDocument {
                            Path = target,
                            LastOpened = File.GetLastWriteTimeUtc(link)
                        });
                        if (results.Count >= limit) break;
                    }
                    catch (System.Runtime.InteropServices.COMException)
                    {
                        // Skip an invalid or inaccessible shortcut; valid recent entries remain usable.
                    }
                    finally
                    {
                        if (shortcut != null && System.Runtime.InteropServices.Marshal.IsComObject(shortcut))
                            System.Runtime.InteropServices.Marshal.ReleaseComObject(shortcut);
                    }
                }
            }
            finally
            {
                if (System.Runtime.InteropServices.Marshal.IsComObject(shell))
                    System.Runtime.InteropServices.Marshal.ReleaseComObject(shell);
            }
            return results;
        }

        public static void RecordOpened(string path)
        {
            SHAddToRecentDocs(SHARD_PATHW, Path.GetFullPath(path));
        }
    }

    class InstalledPackageTool
    {
        public string Name;
        public string Category;
        public string Exe;
        public string Icon;
        public string Desc;
        public string Help;
        public string Args;
    }

    static class PackageInstaller
    {
        static readonly string[] KnownExecutables = { "dwg2dxf.exe", "step2dxf.exe", "gerber2dxf.exe" };

        public static string Root
        {
            get { return Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "XiaokaiToolbox", "packages"); }
        }

        public static List<InstalledPackageTool> Install(string zipPath, out string packageId, out string packageRoot)
        {
            packageId = Path.GetFileNameWithoutExtension(zipPath) + "-" + Guid.NewGuid().ToString("N").Substring(0, 8);
            packageRoot = Path.Combine(Root, packageId);
            Directory.CreateDirectory(packageRoot);

            try
            {
                using (ZipArchive za = ZipFile.OpenRead(zipPath))
                {
                    foreach (ZipArchiveEntry e in za.Entries)
                    {
                        string rel = e.FullName.Replace('/', Path.DirectorySeparatorChar).Replace('\\', Path.DirectorySeparatorChar);
                        string dest = Path.GetFullPath(Path.Combine(packageRoot, rel));
                        if (!dest.StartsWith(Path.GetFullPath(packageRoot).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
                            throw new InvalidDataException("工具包包含非法路径: " + e.FullName);
                        if (e.FullName.EndsWith("/")) { Directory.CreateDirectory(dest); continue; }
                        Directory.CreateDirectory(Path.GetDirectoryName(dest));
                        using (Stream input = e.Open()) using (FileStream output = File.Create(dest)) input.CopyTo(output);
                    }
                }

                List<InstalledPackageTool> tools = ReadManifest(packageRoot);
                if (tools.Count == 0) tools = DetectKnown(packageRoot);
                if (tools.Count == 0) throw new InvalidDataException("工具包里没有可识别的工具。请放入 tools.ini/package.ini，或包含 DWG/STEP/Gerber 转 DXF exe。");
                foreach (InstalledPackageTool t in tools)
                {
                    t.Exe = FullUnder(packageRoot, t.Exe);
                    t.Icon = string.IsNullOrEmpty(t.Icon) ? Path.ChangeExtension(t.Exe, ".ico") : FullUnder(packageRoot, t.Icon);
                    if (!File.Exists(t.Exe)) throw new InvalidDataException("找不到工具程序: " + t.Exe);
                }
                return tools;
            }
            catch
            {
                try { if (Directory.Exists(packageRoot)) Directory.Delete(packageRoot, true); } catch { }
                throw;
            }
        }

        static string FullUnder(string root, string rel)
        {
            string p = Path.GetFullPath(Path.Combine(root, rel.Replace('/', Path.DirectorySeparatorChar)));
            string basePath = Path.GetFullPath(root).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!p.StartsWith(basePath, StringComparison.OrdinalIgnoreCase)) throw new InvalidDataException("清单包含非法路径: " + rel);
            return p;
        }

        static List<InstalledPackageTool> ReadManifest(string root)
        {
            string path = File.Exists(Path.Combine(root, "tools.ini")) ? Path.Combine(root, "tools.ini") : Path.Combine(root, "package.ini");
            var result = new List<InstalledPackageTool>();
            if (!File.Exists(path)) return result;
            InstalledPackageTool cur = null;
            foreach (string raw in File.ReadAllLines(path, Encoding.UTF8))
            {
                string line = raw.Trim();
                if (line.Length == 0 || line[0] == ';' || line[0] == '#') continue;
                if (line.StartsWith("[") && line.EndsWith("]"))
                {
                    string section = line.Substring(1, line.Length - 2).Trim();
                    cur = section.Equals("package", StringComparison.OrdinalIgnoreCase) ? null : new InstalledPackageTool { Name = section };
                    if (cur != null) result.Add(cur);
                    continue;
                }
                int eq = line.IndexOf('='); if (eq < 0 || cur == null) continue;
                string key = line.Substring(0, eq).Trim().ToLowerInvariant();
                string val = line.Substring(eq + 1).Trim();
                if (key == "name") cur.Name = val;
                else if (key == "category") cur.Category = val;
                else if (key == "exe") cur.Exe = val;
                else if (key == "icon") cur.Icon = val;
                else if (key == "desc") cur.Desc = val;
                else if (key == "help") cur.Help = val;
                else if (key == "args") cur.Args = val;
            }
            result.RemoveAll(delegate(InstalledPackageTool t) { return string.IsNullOrEmpty(t.Exe); });
            return result;
        }

        static List<InstalledPackageTool> DetectKnown(string root)
        {
            var result = new List<InstalledPackageTool>();
            foreach (string name in KnownExecutables)
                foreach (string p in Directory.GetFiles(root, name, SearchOption.AllDirectories))
                {
                    string stem = Path.GetFileNameWithoutExtension(p);
                    result.Add(new InstalledPackageTool {
                        Name = stem == "dwg2dxf" ? "DWG 转 DXF" : (stem == "step2dxf" ? "STEP 转 DXF" : "Gerber 转 DXF"),
                        Category = "其他辅助工具", Exe = p.Substring(root.Length + 1),
                        Icon = Path.ChangeExtension(p.Substring(root.Length + 1), ".ico"), Desc = "来自工具包的绿色版工具"
                    });
                    break;
                }
            return result;
        }

        public static string AppendToLocal(string packageId, string packageRoot, List<InstalledPackageTool> tools)
        {
            string path = Manifest.LocalPath;
            var sb = new StringBuilder();
            if (!File.Exists(path)) sb.Append("; 小开工具箱本地清单\r\n");
            foreach (InstalledPackageTool t in tools)
            {
                string category = string.IsNullOrEmpty(t.Category) ? "其他辅助工具" : t.Category;
                if (category == "Other Tools") category = "其他辅助工具";
                sb.Append("\r\n[").Append(t.Name).Append("]\r\n")
                  .Append("category = ").Append(category).Append("\r\n")
                  .Append("exe = ").Append(t.Exe).Append("\r\n")
                  .Append("icon = ").Append(t.Icon).Append("\r\n")
                  .Append("desc = ").Append(string.IsNullOrEmpty(t.Desc) ? "来自工具包" : t.Desc).Append("\r\n")
                  .Append("help = ").Append((t.Help ?? "").Replace("\r", "").Replace("\n", "\\n")).Append("\r\n")
                  .Append("args = ").Append(t.Args ?? "").Append("\r\n")
                  .Append("mine = 1\r\npackage = ").Append(packageId).Append("\r\npackage_root = ").Append(packageRoot).Append("\r\n");
            }
            File.AppendAllText(path, sb.ToString(), new UTF8Encoding(true));
            return path;
        }
    }

    static class Theme
    {
        public static readonly Color SideBg     = Color.FromArgb(0x1B, 0x5E, 0x8C);
        public static readonly Color SideSel    = Color.FromArgb(0x14, 0x47, 0x6B);
        public static readonly Color SideHot    = Color.FromArgb(0x22, 0x6E, 0xA1);
        public static readonly Color SideText   = Color.FromArgb(0xE8, 0xF2, 0xF8);
        public static readonly Color HeadBg     = Color.FromArgb(0x15, 0x50, 0x7A);
        public static readonly Color GridBg     = Color.FromArgb(0x2E, 0x8B, 0xB8);
        public static readonly Color HintBg     = Color.FromArgb(0x3E, 0x9E, 0xCB);
        public static readonly Color FootBg     = Color.FromArgb(0x14, 0x47, 0x6B);
        // 底部说明区。比网格深一档 —— 它是"读"的地方,不是"点"的地方,
        // 颜色一样的话会让人以为下面还有图标只是没加载出来。
        public static readonly Color HelpBg     = Color.FromArgb(0x19, 0x55, 0x80);
    }

    // 只为了一件事存在:把图标间距调宽。LargeIcon 视图的默认格子宽度容不下
    // "PCB Environment Editor" 这种名字,标签会被截成 "PCB Environm...",
    // 而按名字认工具正是这个界面的全部用处。WinForms 没有对应属性,只能发
    // LVM_SETICONSPACING。
    //
    // 放在 OnHandleCreated 里而不是构造完设一次:换 LargeImageList 会重建
    // 句柄,间距会跟着被重置回默认值。
    class IconGrid : ListView
    {
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern IntPtr SendMessage(IntPtr hWnd, int msg, IntPtr wp, IntPtr lp);

        const int LVM_SETICONSPACING = 0x1000 + 53;
        const int LVM_SETEXTENDEDLISTVIEWSTYLE = 0x1000 + 54;
        const int LVS_EX_DOUBLEBUFFER = 0x00010000;

        public Size Spacing = new Size(128, 92);

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            // ListView 是原生 Win32 控件，WinForms 的普通双缓冲对它不生效。
            // 打开文件对话框时主窗体会失去/恢复焦点，原生控件会重画选中项；
            // LVS_EX_DOUBLEBUFFER 避免图标在这次重画中短暂消失。
            SendMessage(Handle, LVM_SETEXTENDEDLISTVIEWSTYLE,
                (IntPtr)LVS_EX_DOUBLEBUFFER, (IntPtr)LVS_EX_DOUBLEBUFFER);
            SendMessage(Handle, LVM_SETICONSPACING, IntPtr.Zero,
                (IntPtr)((Spacing.Height << 16) | (Spacing.Width & 0xFFFF)));
        }

        // 第一行不顶格,靠外面套一层带上边距的 Panel 实现,见 WrapPadded。
        //
        // 试过 LVM_SETITEMPOSITION 把项整体下移,不行:LargeIcon 视图开着
        // AutoArrange,设完位置马上被重排回去。关掉 AutoArrange 又会失去
        // 窗口变宽时自动重新折行的能力 —— 那正是这个界面每天都在用的。
    }

    static class CapturePluginStatus
    {
        public sealed class PluginInfo
        {
            public readonly string Name;
            public readonly string File;
            public readonly string Description;

            public PluginInfo(string name, string file, string description)
            {
                Name = name;
                File = file;
                Description = description;
            }
        }

        static readonly PluginInfo[] sPlugins = {
            new PluginInfo("立创 EDA 转 OrCAD", "lceda2orcadMenu.tcl",
                "剪贴板添加器件；按编号添加器件；列出缓存器件；清除生成的 OLB（保留器件缓存）。"),
            new PluginInfo("BOM 整理工具", "bomtoolMenu.tcl",
                "读取当前原理图，自动生成并整理 BOM Excel 工作簿。"),
            new PluginInfo("Netlocator", "netlocatorMenu.tcl",
                "跨页定位并高亮网络（Alt+F2）；选择当前页整网（Alt+F3）；显示选中网络名称。"),
            new PluginInfo("DRC中文增强版", "drctoolMenu.tcl",
                "双击检查当前设计及 PCB 网表，忽略引脚电气类型冲突；中文归纳问题、双击定位，报告按需导出。"),
            new PluginInfo("文字前后缀", "textaffixMenu.tcl",
                "设置添加文字和前后位置，单击或框选即可处理；已有相同前缀／后缀时可去掉，默认连续处理，Esc 停止并关闭。")
        };

        static string AutoLoadPath(string root)
        {
            return Path.Combine(root, "cdssetup", "OrCAD_Capture",
                                "tclscripts", "capAutoLoad");
        }

        static void AddDirectory(HashSet<string> paths, string path)
        {
            if (string.IsNullOrWhiteSpace(path)) return;
            path = Environment.ExpandEnvironmentVariables(path.Trim().Trim('"'));
            string name = Path.GetFileName(path.TrimEnd(Path.DirectorySeparatorChar,
                                                        Path.AltDirectorySeparatorChar));
            if (name.Equals("capAutoLoad", StringComparison.OrdinalIgnoreCase))
                paths.Add(Path.GetFullPath(path));
            else if (name.Equals("OrCAD_Capture", StringComparison.OrdinalIgnoreCase))
                paths.Add(Path.GetFullPath(Path.Combine(path, "tclscripts", "capAutoLoad")));
            else
            {
                paths.Add(Path.GetFullPath(AutoLoadPath(path)));
                paths.Add(Path.GetFullPath(AutoLoadPath(Path.Combine(path, "SPB_Data"))));
                paths.Add(Path.GetFullPath(Path.Combine(path, "tools", "capture", "tclscripts", "capAutoLoad")));
                if (name.Equals("SPB_Data", StringComparison.OrdinalIgnoreCase))
                    paths.Add(Path.GetFullPath(AutoLoadPath(Path.GetDirectoryName(path) ?? "")));
                if (name.StartsWith("SPB_", StringComparison.OrdinalIgnoreCase))
                    paths.Add(Path.GetFullPath(AutoLoadPath(Path.Combine(
                        Path.GetDirectoryName(path) ?? "", "SPB_Data"))));
            }
        }

        static List<string> FindAutoLoadPaths()
        {
            var paths = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            using (RegistryKey key = Registry.CurrentUser.OpenSubKey(@"Software\XiaokaiToolbox"))
                if (key != null) AddDirectory(paths, key.GetValue("CaptureAutoLoad") as string);
            foreach (string name in new[] {
                "XIAOKAI_CAPTURE_AUTOLOAD", "HOME", "USERPROFILE", "CDS_INST_DIR", "SPB_17_4",
                "SPB_17_2", "SPB_16_6", "CDSROOT"
            })
            {
                try { AddDirectory(paths, Environment.GetEnvironmentVariable(name)); }
                catch (ArgumentException) { }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
                catch (NotSupportedException) { }
            }

            if (!string.IsNullOrEmpty(Paths.CadRoot))
                AddDirectory(paths, Paths.CadRoot);
            if (!string.IsNullOrEmpty(Paths.Spb))
                AddDirectory(paths, Paths.Spb);

            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                if (!drive.IsReady || drive.DriveType != DriveType.Fixed) continue;
                string root = drive.RootDirectory.FullName;
                foreach (string relative in new[] {
                    "Cadence\\SPB_Data", "orcad\\Cadence\\SPB_Data",
                    "Program Files\\Cadence\\SPB_Data",
                    "Program Files (x86)\\Cadence\\SPB_Data"
                })
                {
                    try { AddDirectory(paths, Path.Combine(root, relative)); }
                    catch (ArgumentException) { }
                    catch (IOException) { }
                    catch (UnauthorizedAccessException) { }
                    catch (NotSupportedException) { }
                }
            }
            return new List<string>(paths);
        }

        public static List<PluginInfo> InstalledPluginsIn(string autoLoadPath)
        {
            var installed = new List<PluginInfo>();
            foreach (PluginInfo plugin in sPlugins)
                if (File.Exists(Path.Combine(autoLoadPath, plugin.File)))
                    installed.Add(plugin);
            return installed;
        }

        public static List<PluginInfo> InstalledPlugins()
        {
            var installed = new List<PluginInfo>();
            var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            foreach (string path in FindAutoLoadPaths())
                foreach (PluginInfo plugin in InstalledPluginsIn(path))
                    if (seen.Add(plugin.File)) installed.Add(plugin);
            return installed;
        }
    }

    class MainForm : Form
    {
        ListBox mCats;
        // 上半 Cadence 原厂,下半自研。两个 ListView 而不是一个带分组的:
        // LargeIcon 视图的分组头在 XP 之后的视觉样式下会强行套系统配色,
        // 在这套深蓝背景上是一条白杠,改不掉。
        IconGrid mGrid;
        IconGrid mMineGrid;
        IconGrid mDsnGrid;
        IconGrid mBrdGrid;
        SplitContainer mSplit;   // 上下分区,中间那条能拖
        Label mHint;
        TextBox mHelp;           // 底部详细说明
        Label mFoot;
        Label mPick;             // 侧栏"指定 Cadence 目录"
        Control mDsnSection;
        Control mBrdSection;
        Label mMineHeading;
        // public 是为了让自检能对着上面的 AssemblyFileVersion 比一遍。
        public const string Version = "1.6.47";

        public MainForm()
        {
            Text = "小开工具箱";
            ClientSize = new Size(1024, 598);
            MinimumSize = new Size(820, 480);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Theme.GridBg;
            // 去掉系统边框。白色的标题栏压在这套深蓝配色上面很突出,而窗口本身
            // 已经有自己的标题条(侧栏顶部那块),再来一条是重复的。
            //
            // 代价是边框自带的东西全都没了:拖动、最小化、关闭、贴边最大化。
            // 拖动在 MakeDragHandle 里补,按钮在 BuildWinButtons 里补,
            // 最大化保留系统行为(双击标题栏 / Win+Up 仍然有效)。
            FormBorderStyle = FormBorderStyle.None;
            Font = new Font("Microsoft YaHei UI", 9f);
            try { Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath); } catch { }

            // 顺序要紧,而且是反直觉的:WinForms 的停靠按 Z 序**倒序**处理,
            // 集合里索引最高的先占地方。所以内容区必须先加(索引低、最后停靠,
            // 吃掉剩下的空间),侧栏后加(先停靠,拿到完整的左侧一条)。
            //
            // 反过来写的话侧栏会直接压在图标网格上面 —— 界面看着像画坏了,
            // 但编译和自检全都过,只有截图能看出来。
            BuildContent();
            BuildSidebar();
            Resize += delegate { SizeContent(); };
            Activated += delegate { ShowCategory(); };
            FormClosing += OnMainFormClosing;

            if (Manifest.Error != null)
            {
                MessageBox.Show(Manifest.Error, "小开工具箱",
                    MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }

            if (mCats.Items.Count > 0) mCats.SelectedIndex = 0;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern bool ReleaseCapture();
        [System.Runtime.InteropServices.DllImport("user32.dll")]
        static extern IntPtr SendMessage(IntPtr hWnd, int msg, int wp, int lp);

        const int WM_NCLBUTTONDOWN = 0xA1;
        const int HTCAPTION = 0x2;

        // 让一个控件变成"标题栏"。做法是把鼠标按下伪装成在系统标题栏上按下,
        // 后面的拖动就交给 Windows 自己走 —— 比在 MouseMove 里自己算偏移好:
        // 贴边吸附、多显示器、拖到屏幕外的限制全都是免费的。
        void MakeDragHandle(Control c)
        {
            c.MouseDown += delegate (object s, MouseEventArgs e)
            {
                if (e.Button != MouseButtons.Left) return;
                ReleaseCapture();
                SendMessage(Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
            };
            // 双击标题栏最大化/还原,和系统标题栏一致。
            c.MouseDoubleClick += delegate (object s, MouseEventArgs e)
            {
                if (e.Button != MouseButtons.Left) return;
                WindowState = WindowState == FormWindowState.Maximized
                    ? FormWindowState.Normal : FormWindowState.Maximized;
            };
        }

        void BuildSidebar()
        {
            var side = new Panel
            {
                Dock = DockStyle.Left,
                Width = 200,
                BackColor = Theme.SideBg
            };

            var title = new Label
            {
                Dock = DockStyle.Top,
                Height = 56,
                Text = "  小开工具箱",
                ForeColor = Color.White,
                BackColor = Theme.HeadBg,
                Font = new Font("Microsoft YaHei UI", 13f, FontStyle.Regular),
                TextAlign = ContentAlignment.MiddleLeft
            };

            // 自绘的 ListBox 而不是一堆 Button:条目数量由清单决定,
            // 而 ListBox 自带键盘上下选择和滚动。
            mCats = new ListBox
            {
                Dock = DockStyle.Fill,
                BackColor = Theme.SideBg,
                ForeColor = Theme.SideText,
                BorderStyle = BorderStyle.None,
                DrawMode = DrawMode.OwnerDrawFixed,
                ItemHeight = 40,
                IntegralHeight = false
            };
            mCats.DrawItem += OnDrawCat;
            mCats.SelectedIndexChanged += delegate { ShowCategory(); };
            foreach (string c in Manifest.Categories) mCats.Items.Add(c);

            mFoot = new Label
            {
                Dock = DockStyle.Bottom,
                Height = 30,
                Text = "  Version : " + Version,
                ForeColor = Color.FromArgb(0xBF, 0xDA, 0xEA),
                BackColor = Theme.FootBg,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Microsoft YaHei UI", 8.5f)
            };

            // 放在侧栏底部而不是图标区里:图标区分了上下两块,按钮放哪一块都
            // 像是"只给这块加",而且下半块在没有自研工具的分类里是折起来的,
            // 按钮会跟着消失。
            var add = new Label
            {
                Dock = DockStyle.Bottom,
                Height = 34,
                Text = "  + 添加其他软件",
                ForeColor = Color.FromArgb(0xD8, 0xEC, 0xF7),
                BackColor = Theme.SideSel,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Microsoft YaHei UI", 9f),
                Cursor = Cursors.Hand
            };
            add.Click += OnAddTool;
            add.MouseEnter += delegate { add.BackColor = Theme.SideHot; };
            add.MouseLeave += delegate { add.BackColor = Theme.SideSel; };

            // 指路的入口一直摆在这儿,不是只在探测失败时才出现:探测**成功但找错了**
            // 也要能改(装了两个版本、想指到另一个),那种情况下界面上没有任何异常。
            var pick = new Label
            {
                Dock = DockStyle.Bottom,
                Height = 34,
                // ⚙ (U+2699) 而不是 ⌕ (U+2315):后者是 TELEPHONE RECORDER,
                // 本来就长得像个 ρ,不是放大镜 —— 界面上看着像字体缺字。
                Text = "  ⚙ 指定 Cadence 目录",
                ForeColor = Color.FromArgb(0xD8, 0xEC, 0xF7),
                BackColor = Theme.SideSel,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Microsoft YaHei UI", 9f),
                Cursor = Cursors.Hand
            };
            pick.Click += OnPickSpb;
            pick.MouseEnter += delegate { pick.BackColor = Theme.SideHot; };
            pick.MouseLeave += delegate { pick.BackColor = Theme.SideSel; };
            mPick = pick;
            UpdatePickLabel();

            MakeDragHandle(title);

            // 停靠是按索引倒着处理的(见 BuildContent),所以这里越靠后写的越贴边。
            // mFoot 写在 add 后面 = 版本号在最底下,按钮在它上面。反过来的话
            // 按钮贴着窗口下沿,版本号浮在中间,像是排版塌了。
            side.Controls.Add(mCats);
            side.Controls.Add(pick);
            side.Controls.Add(add);
            side.Controls.Add(mFoot);
            side.Controls.Add(title);
            Controls.Add(side);
        }

        void OnDrawCat(object sender, DrawItemEventArgs e)
        {
            if (e.Index < 0) return;
            bool sel = (e.State & DrawItemState.Selected) == DrawItemState.Selected;
            Color bg = sel ? Theme.SideSel : Theme.SideBg;
            using (var b = new SolidBrush(bg)) e.Graphics.FillRectangle(b, e.Bounds);

            // 选中项左侧一条亮边,比只换背景色更容易看出选了哪个。
            if (sel)
                using (var b = new SolidBrush(Color.FromArgb(0x7F, 0xD4, 0xF5)))
                    e.Graphics.FillRectangle(b, e.Bounds.X, e.Bounds.Y, 4, e.Bounds.Height);

            string txt = (string)mCats.Items[e.Index];
            var rect = new Rectangle(e.Bounds.X + 22, e.Bounds.Y, e.Bounds.Width - 26, e.Bounds.Height);
            TextRenderer.DrawText(e.Graphics, txt, e.Font, rect, Theme.SideText,
                TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
        }

        void BuildContent()
        {
            mHint = new Label
            {
                Dock = DockStyle.Top,
                Height = 34,
                Text = "  提示: 单击选择工具可查看工具说明,双击可启动工具。",
                ForeColor = Color.White,
                BackColor = Theme.HintBg,
                TextAlign = ContentAlignment.MiddleLeft,
                Padding = new Padding(8, 0, 0, 0)
            };
            MakeDragHandle(mHint);

            // 边框没了,关闭和最小化得自己来。放在提示栏右端 —— 那里本来就是空的,
            // 而且和用户对"窗口右上角"的肌肉记忆一致。
            mHint.Controls.Add(MakeWinButton("×", 46, delegate { Close(); }));
            mHint.Controls.Add(MakeWinButton("—", 92,
                delegate { WindowState = FormWindowState.Minimized; }));

            mGrid = MakeGrid();
            mMineGrid = MakeGrid();
            mDsnGrid = MakeRecentGrid();
            mBrdGrid = MakeRecentGrid();

            // 自研工具的右键卸载。挂在自研网格上,原厂网格没有 —— 原厂工具跟着
            // SPB 装,卸载得走 Cadence 自己的安装器,这里给个入口只会误导人。
            var menu = new ContextMenuStrip();
            var miUninst = new ToolStripMenuItem("卸载(&U)");
            miUninst.Click += OnUninstall;
            menu.Items.Add(miUninst);
            // 移除:只从清单里删掉,不动磁盘。跟卸载分成两项而不是一项 ——
            // 这两件事的后果差得远,合成一个"删除"迟早有人误点。
            var miRemove = new ToolStripMenuItem("从工具箱移除(&R)");
            miRemove.Click += OnRemoveTool;
            menu.Items.Add(miRemove);
            // 每次弹出时重算可用性:绿色版没有卸载命令,菜单项该是灰的而不是
            // 点了没反应。
            menu.Opening += delegate (object s, System.ComponentModel.CancelEventArgs e)
            {
                Tool t = SelectedIn(mMineGrid);
                miUninst.Enabled = (t != null && t.CanUninstall);
                miRemove.Enabled = (t != null && t.Local);
                if (t == null) e.Cancel = true;   // 空白处右键不弹
            };
            mMineGrid.ContextMenuStrip = menu;

            // 上下两块用 SplitContainer 而不是固定高度 + Splitter:加了几个自研
            // 工具之后两块该多高,只有用的人知道 —— 中间那条能拖。
            //
            // 没用老的 Splitter 控件:它靠 Add 顺序推断自己该改谁的大小,而这里
            // 的停靠顺序本来就是反的(见 BuildContent 里的注释),两套反直觉的
            // 顺序叠在一起没人能维护。SplitContainer 的 Panel1/Panel2 是明确的。
            mSplit = new SplitContainer
            {
                Dock = DockStyle.Fill,
                Orientation = Orientation.Horizontal,
                BackColor = Theme.HeadBg,     // 就是中间那条分隔线的颜色
                SplitterWidth = 6,
                Panel1MinSize = 90,
                Panel2MinSize = 74
            };
            mSplit.Panel1.BackColor = Theme.GridBg;
            mSplit.Panel2.BackColor = Theme.GridBg;
            // SplitterMoving 只在鼠标真的拖的时候发;SplitterMoved 连我们自己设
            // SplitterDistance 也会发,用它的话第一次切分类就把标记点亮了,
            // "用户拖过就不再自动调"整个失效。
            mSplit.SplitterMoving += delegate { mUserDragged = true; };

            mDsnSection = MakeRecentSection("  常用 DSN 文件", mDsnGrid);
            mBrdSection = MakeRecentSection("  常用 BRD 文件", mBrdGrid);
            mDsnSection.Visible = false;
            mBrdSection.Visible = false;

            mSplit.Panel1.Controls.Add(WrapPadded(mGrid));
            mSplit.Panel1.Controls.Add(mDsnSection);
            mSplit.Panel1.Controls.Add(mBrdSection);
            mSplit.Panel1.Controls.Add(MakeZoneLabel("  Cadence 原厂工具"));
            mSplit.Panel2.Controls.Add(WrapPadded(mMineGrid));
            mMineHeading = MakeZoneLabel("  自研工具  (右键可卸载 / 移除)");
            mSplit.Panel2.Controls.Add(mMineHeading);

            // 底部详细说明。单击图标时填,顶部那条仍旧只放一句话的简介。
            //
            // 用只读 TextBox 而不是 Label:说明可能有十几行,Label 装不下就直接
            // 截掉,而 TextBox 自带滚动条,还能选中复制 —— 里面有路径和菜单名,
            // 复制走比照着敲省事。
            mHelp = new TextBox
            {
                Dock = DockStyle.Bottom,
                Height = 132,
                Multiline = true,
                ReadOnly = true,
                WordWrap = true,
                ScrollBars = ScrollBars.Vertical,
                BorderStyle = BorderStyle.None,
                BackColor = Theme.HelpBg,
                ForeColor = Color.FromArgb(0xE8, 0xF4, 0xFA),
                Font = new Font("Microsoft YaHei UI", 9f),
                TabStop = false,
                Text = HelpPlaceholder
            };

            // 提示栏要关在内容面板里,不能直接加到窗体上:直接加的话它会横穿
            // 整个窗口宽度,把侧栏标题挤到下面去。
            var content = new Panel { Dock = DockStyle.Fill, BackColor = Theme.GridBg };
            content.Controls.Add(mSplit);   // 先加 = 最后停靠 = 吃掉剩余空间
            content.Controls.Add(mHelp);    // 底部一条
            content.Controls.Add(mHint);    // 最先停靠 = 拿到顶部一条
            Controls.Add(content);
            // 父窗口 Resize 时停靠布局可能还没结束,以分区的实际尺寸再调整一次。
            mSplit.SizeChanged += delegate { SizeContent(); };
        }

        int FillCapturePlugins()
        {
            List<CapturePluginStatus.PluginInfo> installed =
                CapturePluginStatus.InstalledPlugins();
            string capture = Paths.Expand(@"%SPB%\tools\bin\Capture.exe");
            foreach (CapturePluginStatus.PluginInfo plugin in installed)
            {
                string key = "capture-plugin:" + plugin.File;
                string iconPath = File.Exists(capture) ? capture
                    : Path.Combine(Paths.Toolbox, plugin.File);
                mMineGrid.LargeImageList.Images.Add(key, Icons.ForPath(iconPath, plugin.Name));
                mMineGrid.Items.Add(new ListViewItem(plugin.Name, key)
                {
                    Tag = plugin,
                    ToolTipText = plugin.Description
                });
            }
            if (installed.Count == 0)
                mMineGrid.Items.Add(new ListViewItem("未检测到已安装插件")
                {
                    ForeColor = Theme.SideText
                });
            return Math.Max(1, installed.Count);
        }

        void ShowPluginInfo(CapturePluginStatus.PluginInfo plugin)
        {
            mHint.Text = "  " + plugin.Name + " - " + plugin.Description;
            mHelp.Text = plugin.Name + "\r\n\r\n" + plugin.Description
                + "\r\n\r\n在 Capture 原理图中按 Alt+K 打开插件功能集合。"
                + "\r\n\r\n插件由小开工具箱安装到 OrCAD Capture 的 capAutoLoad 目录。";
            mHelp.SelectionStart = 0;
            mHelp.SelectionLength = 0;
            mHelp.ScrollToCaret();
        }

        const string HelpPlaceholder =
            "  单击上面的图标,这里显示这个工具是干什么的、怎么用。双击图标启动。";

        // 第一行不顶格:套一层同色 Panel,用它的 Padding 把网格整体推下来。
        // 背景色必须和网格一致,否则上面会出现一条深色的横带。
        Panel WrapPadded(Control inner)
        {
            var p = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = Theme.GridBg,
                Padding = new Padding(6, 12, 0, 0)
            };
            p.Controls.Add(inner);
            return p;
        }

        // 两个网格除了内容以外完全一样,共用一份构造。
        IconGrid MakeGrid()
        {
            var g = new IconGrid
            {
                Dock = DockStyle.Fill,
                View = View.LargeIcon,
                BackColor = Theme.GridBg,
                ForeColor = Color.White,
                BorderStyle = BorderStyle.None,
                MultiSelect = false,
                LabelWrap = true,
                // 失去焦点就不画选中框。原来是 false(一直画),结果点完一个图标
                // 再点别处,那个图标的名字底下会留一块灰蓝色 —— 系统画的"非活动
                // 选中"色,压在这套配色上很脏,而且看着像还选着、其实回车已经
                // 打不到它了。
                HideSelection = true
            };
            g.LargeImageList = new ImageList
            {
                ImageSize = new Size(32, 32),
                ColorDepth = ColorDepth.Depth32Bit
            };
            g.ItemSelectionChanged += OnPick;
            g.MouseDoubleClick += OnLaunch;
            // 回车等同双击:键盘选到了就该能直接启动。
            g.KeyDown += delegate (object s, KeyEventArgs e)
            {
                if (e.KeyCode == Keys.Enter) LaunchSelected();
            };
            return g;
        }

        IconGrid MakeRecentGrid()
        {
            var g = new IconGrid
            {
                Dock = DockStyle.Fill,
                View = View.SmallIcon,
                BackColor = Theme.GridBg,
                ForeColor = Color.White,
                BorderStyle = BorderStyle.None,
                MultiSelect = false,
                LabelWrap = false,
                HideSelection = true,
                ShowItemToolTips = true
            };
            g.SmallImageList = new ImageList
            {
                ImageSize = new Size(16, 16),
                ColorDepth = ColorDepth.Depth32Bit
            };
            g.ItemSelectionChanged += OnPickRecent;
            g.MouseDoubleClick += OnLaunchRecent;
            g.KeyDown += delegate(object s, KeyEventArgs e)
            {
                if (e.KeyCode == Keys.Enter) LaunchRecentSelected(s as IconGrid);
            };
            return g;
        }

        Control MakeRecentSection(string title, IconGrid grid)
        {
            var section = new Panel { Dock = DockStyle.Bottom, Height = 100, BackColor = Theme.GridBg };
            var heading = new Label
            {
                Dock = DockStyle.Top,
                Height = 24,
                Text = title,
                ForeColor = Color.FromArgb(0xD8, 0xEC, 0xF7),
                BackColor = Theme.HeadBg,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Microsoft YaHei UI", 8.5f)
            };
            var body = new Panel
            {
                Dock = DockStyle.Fill,
                BackColor = Theme.GridBg,
                Padding = new Padding(6, 4, 6, 4)
            };
            body.Controls.Add(grid);
            section.Controls.Add(body);
            section.Controls.Add(heading);
            return section;
        }

        void RefreshRecentFiles()
        {
            if (mCats != null && (string)mCats.SelectedItem == "OrCAD 工具") FillRecentGrid(mDsnGrid, ".dsn");
            if (mCats != null && (string)mCats.SelectedItem == "Allegro 工具") FillRecentGrid(mBrdGrid, ".brd");
        }

        void FillRecentGrid(IconGrid grid, string extension)
        {
            grid.BeginUpdate();
            grid.Items.Clear();
            grid.SmallImageList.Images.Clear();
            try
            {
                List<RecentDocument> documents = RecentDocuments.Read(extension, 8);
                int index = 0;
                foreach (RecentDocument document in documents)
                {
                    string key = extension + index++;
                    grid.SmallImageList.Images.Add(key, Icons.ForPath(document.Path,
                        Path.GetFileNameWithoutExtension(document.Path)));
                    var item = new ListViewItem(Path.GetFileNameWithoutExtension(document.Path), key)
                    {
                        Tag = document,
                        ToolTipText = document.Path + "\r\n最近打开：" + document.LastOpened.ToLocalTime()
                    };
                    grid.Items.Add(item);
                }
                if (documents.Count == 0)
                {
                    grid.Items.Add(new ListViewItem("暂无最近打开的文件"));
                }
            }
            catch (Exception ex)
            {
                grid.Items.Add(new ListViewItem("读取最近文件失败"));
                mHint.Text = "  无法读取 " + extension + " 最近文件：" + ex.Message;
            }
            finally
            {
                grid.EndUpdate();
            }
        }

        Label MakeZoneLabel(string text)
        {
            return new Label
            {
                Dock = DockStyle.Top,
                Height = 26,
                Text = text,
                ForeColor = Color.FromArgb(0xD8, 0xEC, 0xF7),
                BackColor = Theme.HeadBg,
                TextAlign = ContentAlignment.MiddleLeft,
                Font = new Font("Microsoft YaHei UI", 9f)
            };
        }

        // rightOffset 是距提示栏右边缘的距离,靠 Anchor 顶右保持住 —— 提示栏
        // 是 Dock.Top,窗口一变宽它就变宽,写死 Left 的话按钮会留在原地。
        Label MakeWinButton(string glyph, int rightOffset, EventHandler onClick)
        {
            var b = new Label
            {
                Text = glyph,
                Width = 40,
                Height = 34,
                Left = mHint.Width - rightOffset,
                Top = 0,
                Anchor = AnchorStyles.Top | AnchorStyles.Right,
                ForeColor = Color.White,
                BackColor = Theme.HintBg,
                TextAlign = ContentAlignment.MiddleCenter,
                Font = new Font("Microsoft YaHei UI", 11f),
                Cursor = Cursors.Hand
            };
            b.Click += onClick;
            // 悬停变色。没有边框和阴影的情况下,这是"这里能点"的唯一提示。
            b.MouseEnter += delegate { b.BackColor = Theme.SideHot; };
            b.MouseLeave += delegate { b.BackColor = Theme.HintBg; };
            return b;
        }

        void ShowCategory()
        {
            string cat = mCats.SelectedItem as string;
            if (cat == null) return;

            var all = Manifest.InCategory(cat);
            int cad  = Fill(mGrid, all, false);
            int mine = Fill(mMineGrid, all, true);
            bool orcad = cat == "OrCAD 工具";
            bool allegro = cat == "Allegro 工具";
            mDsnSection.Visible = orcad;
            mBrdSection.Visible = allegro;
            mMineHeading.Text = orcad
                ? (mine == 0 ? "  Capture 插件" : "  自研工具 / Capture 插件  (右键可卸载 / 移除)")
                : "  自研工具  (右键可卸载 / 移除)";
            if (orcad) mine += FillCapturePlugins();
            RefreshRecentFiles();

            // 空的那半整块折起来,不留一条空标题占地方。
            // 「许可证工具」全是原厂的,下半折起来;「其他辅助工具」全是自研的,
            // 上半折起来。两边都有才显示中间那条可拖的分隔线。
            mSplit.Panel2Collapsed = (mine == 0);
            mSplit.Panel1Collapsed = (cad == 0 && !orcad && !allegro);

            SizeContent();
            ShowHintDefault();
        }

        void SizeContent()
        {
            if (mHelp == null || mSplit == null || WindowState == FormWindowState.Minimized) return;
            // 窗口变矮时先收短说明区,给原厂工具、常用文件和插件各留出空间。
            mHelp.Height = Math.Max(60, Math.Min(132, ClientSize.Height - 414));
            // 用户拖动过分隔线后继续保留他的比例。
            if (!mSplit.Panel1Collapsed && !mSplit.Panel2Collapsed && !mUserDragged)
            {
                // 最小化或停靠布局的中间状态可能没有足够高度容纳两块。
                // 此时保留分隔条位置,等尺寸恢复后由 SizeChanged 重新计算。
                int minimum = mSplit.Panel1MinSize;
                int maximum = mSplit.ClientSize.Height - mSplit.Panel2MinSize - mSplit.SplitterWidth;
                if (maximum < minimum) return;
                int rows = (mMineGrid.Items.Count + 5) / 6;
                int want = 26 + 12 + rows * 92 + 8;
                int distance = mSplit.ClientSize.Height - want - mSplit.SplitterWidth;
                mSplit.SplitterDistance = Math.Max(minimum, Math.Min(distance, maximum));
            }
        }

        // 用户是不是自己拖过分隔线。拖过之后就不再自动设高度。
        bool mUserDragged;

        // 按 Mine 过滤后填一个网格,返回填进去的个数。
        int Fill(IconGrid g, System.Collections.Generic.List<Tool> all, bool mine)
        {
            g.BeginUpdate();
            g.Items.Clear();
            g.LargeImageList.Images.Clear();

            int n = 0;
            foreach (Tool t in all)
            {
                if (t.Mine != mine) continue;
                string key = t.Name;
                g.LargeImageList.Images.Add(key, Icons.For(t));
                var it = new ListViewItem(t.Name, key) { Tag = t };
                if (!t.Exists)
                {
                    // 灰显但不隐藏:一个装了一半的 Cadence 应该看得出缺了什么,
                    // 而不是让人以为工具箱漏做了这个工具。
                    it.ForeColor = Color.FromArgb(0x9F, 0xBF, 0xD2);
                    it.Text = t.Name + "(未安装)";
                }
                g.Items.Add(it);
                n++;
            }
            g.EndUpdate();
            return n;
        }

        void ShowHintDefault()
        {
            mHint.Text = "  提示: 单击选择工具可查看工具说明,双击可启动工具。";
            if (mHelp != null) mHelp.Text = HelpPlaceholder;
        }

        void OnPick(object sender, ListViewItemSelectionChangedEventArgs e)
        {
            if (!e.IsSelected) { ShowHintDefault(); return; }
            Tool t = e.Item.Tag as Tool;
            CapturePluginStatus.PluginInfo plugin = e.Item.Tag as CapturePluginStatus.PluginInfo;
            if (t == null && plugin == null) return;

            // 两个网格各有各的选中态,不互斥。在另一个里点一下之后,这边原来
            // 选中的那项还亮着 —— 看着像同时选中了两个工具,而回车只启动一个。
            IconGrid other = (sender == mGrid) ? mMineGrid : mGrid;
            if (other.SelectedItems.Count > 0) other.SelectedItems.Clear();
            mLast = sender as IconGrid;
            if (mDsnGrid.SelectedItems.Count > 0) mDsnGrid.SelectedItems.Clear();
            if (mBrdGrid.SelectedItems.Count > 0) mBrdGrid.SelectedItems.Clear();
            if (plugin != null)
            {
                ShowPluginInfo(plugin);
                return;
            }

            mHint.Text = t.Exists
                ? "  " + t.Name + " - " + t.Desc
                : "  " + t.Name + " - 不可用:" + t.Missing;
            ShowHelp(t);
        }

        void OnPickRecent(object sender, ListViewItemSelectionChangedEventArgs e)
        {
            if (!e.IsSelected) return;
            RecentDocument document = e.Item.Tag as RecentDocument;
            if (document == null) return;

            if (mGrid.SelectedItems.Count > 0) mGrid.SelectedItems.Clear();
            if (mMineGrid.SelectedItems.Count > 0) mMineGrid.SelectedItems.Clear();
            IconGrid other = sender == mDsnGrid ? mBrdGrid : mDsnGrid;
            if (other.SelectedItems.Count > 0) other.SelectedItems.Clear();

            string extension = Path.GetExtension(document.Path).ToUpperInvariant();
            mHint.Text = "  " + Path.GetFileName(document.Path) + " - 双击使用 Cadence 打开";
            mHelp.Text = "常用 " + extension + " 文件\r\n\r\n"
                + document.Path + "\r\n\r\n最近打开："
                + document.LastOpened.ToLocalTime();
            mHelp.SelectionStart = 0;
            mHelp.SelectionLength = 0;
            mHelp.ScrollToCaret();
        }

        void OnLaunchRecent(object sender, MouseEventArgs e)
        {
            var grid = sender as IconGrid;
            if (grid != null && grid.GetItemAt(e.X, e.Y) != null)
                LaunchRecentSelected(grid);
        }

        void LaunchRecentSelected(IconGrid grid)
        {
            if (grid == null || grid.SelectedItems.Count == 0) return;
            RecentDocument document = grid.SelectedItems[0].Tag as RecentDocument;
            if (document == null) return;

            try
            {
                if (!File.Exists(document.Path))
                    throw new FileNotFoundException("最近文件已不存在。", document.Path);
                string extension = Path.GetExtension(document.Path);
                string executable = extension.Equals(".dsn", StringComparison.OrdinalIgnoreCase)
                    ? Paths.Expand(@"%SPB%\tools\bin\Capture.exe")
                    : Paths.Expand(@"%SPB%\tools\bin\allegro.exe");
                if (!File.Exists(executable))
                    throw new FileNotFoundException("未找到对应的 Cadence 原厂程序。请先指定 Cadence 目录。", executable);

                RecentDocuments.RecordOpened(document.Path);
                var psi = new ProcessStartInfo(executable)
                {
                    Arguments = RecentDocuments.QuoteArgument(document.Path),
                    WorkingDirectory = Path.GetDirectoryName(executable),
                    UseShellExecute = true
                };
                ToolProcessManager.Start(psi, Path.GetFileName(document.Path));
                mHint.Text = "  已使用 " + (extension.Equals(".dsn", StringComparison.OrdinalIgnoreCase)
                    ? "Capture" : "Allegro") + " 打开 " + document.Path;
                RefreshRecentFiles();
            }
            catch (Exception ex)
            {
                MessageBox.Show("打开常用文件失败。\n\n" + ex.Message,
                    "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        // 底部详细说明。没写 help 的工具退回显示 desc —— 留白的话看着像
        // 说明没加载出来。
        void ShowHelp(Tool t)
        {
            string body = t.Help.Length > 0 ? t.Help : t.Desc;
            var sb = new System.Text.StringBuilder();
            sb.Append(t.Name).Append("\r\n\r\n");
            // TextBox 只认 \r\n,单个 \n 会显示成一个方框。ini 里解出来的是 \n。
            sb.Append(body.Replace("\r\n", "\n").Replace("\n", "\r\n"));
            if (!t.Exists) sb.Append("\r\n\r\n当前不可用:").Append(t.Missing);
            sb.Append("\r\n\r\n路径:").Append(t.Exe);
            mHelp.Text = sb.ToString();
            mHelp.SelectionStart = 0;      // 否则换工具后还停在上一条的滚动位置
            mHelp.SelectionLength = 0;
            mHelp.ScrollToCaret();
        }

        // 最后一次选中发生在哪个网格。回车启动要靠它才知道该看谁的选中项。
        IconGrid mLast;

        void OnLaunch(object sender, MouseEventArgs e)
        {
            var g = sender as IconGrid;
            if (g != null && g.GetItemAt(e.X, e.Y) != null) LaunchSelected();
        }

        Tool SelectedIn(IconGrid g)
        {
            if (g == null || g.SelectedItems.Count == 0) return null;
            return g.SelectedItems[0].Tag as Tool;
        }

        void LaunchSelected()
        {
            Tool t = SelectedIn(mLast);
            if (t == null) return;

            if (!t.Exists)
            {
                MessageBox.Show(t.Name + " 无法启动。\n\n" + t.Missing,
                    "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            try
            {
                var psi = new ProcessStartInfo(t.Exe)
                {
                    // Cadence 的工具会按相对路径找自己的配置和 DLL,
                    // 工作目录留在工具箱这边有些工具会起不来。
                    WorkingDirectory = Path.GetDirectoryName(t.Exe),
                    UseShellExecute = true
                };
                if (!string.IsNullOrEmpty(t.Args)) psi.Arguments = t.Args;
                ToolProcessManager.Start(psi, t.Name);

                mHint.Text = "  已启动 " + t.Name + ",大型工具首次启动可能要等十几秒。";
            }
            catch (Exception ex)
            {
                // exe 存在但起不来:权限、License、缺运行库都可能。
                // 把原始消息原样显示,不要包装成"未知错误"。
                MessageBox.Show("启动 " + t.Name + " 失败。\n\n" + ex.Message
                    + "\n\n路径:" + t.Exe,
                    "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        // 右键卸载。卸载是不可逆的,所以先确认一次,并且把要执行的命令原样
        // 显示出来 —— 用户至少能看出它到底要动哪个目录。
        void OnUninstall(object sender, EventArgs e)
        {
            Tool t = SelectedIn(mMineGrid);
            if (t == null) return;

            if (!t.HasUninstaller)
            {
                MessageBox.Show(t.Name + " 是绿色版,没有卸载程序。\n\n"
                    + "直接删掉这个目录就行:\n"
                    + Path.GetDirectoryName(t.Exe),
                    "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }
            if (!t.CanUninstall)
            {
                MessageBox.Show(t.Name + " 当前未安装，无需卸载。",
                    "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Information);
                return;
            }

            string command = !string.IsNullOrEmpty(t.UninstallExe)
                ? Paths.Expand(t.UninstallExe) + " " + Paths.Expand(t.UninstallArgs)
                : t.Uninstall;
            var r = MessageBox.Show("确定要卸载 " + t.Name + " 吗?\n\n"
                + "将执行:\n" + command,
                "小开工具箱", MessageBoxButtons.YesNo, MessageBoxIcon.Warning,
                MessageBoxDefaultButton.Button2);   // 默认停在"否"
            if (r != DialogResult.Yes) return;

            try
            {
                ProcessStartInfo psi;
                if (!string.IsNullOrEmpty(t.UninstallExe))
                {
                    string exe = Paths.Expand(t.UninstallExe);
                    psi = new ProcessStartInfo(exe)
                    {
                        Arguments = Paths.Expand(t.UninstallArgs),
                        WorkingDirectory = Path.GetDirectoryName(exe),
                        UseShellExecute = false,
                        CreateNoWindow = false,
                        WindowStyle = ProcessWindowStyle.Normal
                    };
                    foreach (string entry in t.UninstallEnv.Split(';'))
                    {
                        int equals = entry.IndexOf('=');
                        if (equals <= 0) continue;
                        psi.EnvironmentVariables[entry.Substring(0, equals).Trim()] =
                            entry.Substring(equals + 1).Trim();
                    }
                }
                else
                {
                    psi = new ProcessStartInfo("cmd.exe", "/d /s /c \"" + t.Uninstall + "\"")
                    {
                        UseShellExecute = false,
                        CreateNoWindow = false,
                        WindowStyle = ProcessWindowStyle.Normal
                    };
                }
                ToolProcessManager.Start(psi, t.Name + " 卸载程序");
                mHint.Text = "  已启动 " + t.Name + " 卸载程序；请查看结果并重启 Capture。";
            }
            catch (Exception ex)
            {
                MessageBox.Show("卸载 " + t.Name + " 失败。\n\n" + ex.Message,
                    "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        void OnMainFormClosing(object sender, FormClosingEventArgs e)
        {
            string errors = ToolProcessManager.CloseAll(8000);
            if (!string.IsNullOrEmpty(errors))
            {
                MessageBox.Show("关闭已启动的工具时遇到问题，部分进程可能仍在运行：\n\n" + errors,
                    "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            }
        }

        // "+ 添加其他软件"。选个 exe、给个名字、挑个分类,追加到 tools.local.ini。
        //
        // 写 local 而不是 tools.ini:装新版会覆盖随包那份,用户加的东西不能跟着
        // 被冲掉。两个文件的分工见 Manifest 顶上的注释。
        // 侧栏文字跟着状态走:已经手动指过就标出来,免得用户忘了自己设过,
        // 之后 Cadence 换了目录还在纳闷为什么一直指着旧的。
        void UpdatePickLabel()
        {
            if (mPick == null) return;
            mPick.Text = Paths.LoadManual() == null
                ? "  ⚙ 指定 Cadence 目录"
                : "  ⚙ Cadence 目录(已手动指定)";
        }

        // "指定 Cadence 目录"。让用户挑**一个** exe,从它往上爬找到安装根,
        // 剩下几十个工具全按 %SPB% 自己算出来 —— 用户不需要知道哪个在哪。
        void OnPickSpb(object sender, EventArgs e)
        {
            if (Paths.LoadManual() != null)
            {
                // 已经设过了,先问是改还是清。三个按钮:是=重新选,否=清掉回自动,
                // 取消=什么都不动。
                DialogResult r = MessageBox.Show(
                    "现在指的是:\n" + Paths.LoadManual()
                    + "\n\n重新选一个?\n\n"
                    + "「是」重新选     「否」清掉、回到自动探测     「取消」不动",
                    "指定 Cadence 目录",
                    MessageBoxButtons.YesNoCancel, MessageBoxIcon.Question);
                if (r == DialogResult.Cancel) return;
                if (r == DialogResult.No) { ApplySpb(null, "已清掉手动设置,回到自动探测。"); return; }
            }

            using (var d = new OpenFileDialog())
            {
                d.Title = "在 Cadence 安装目录里选任意一个程序(比如 Capture.exe)";
                d.Filter = "程序 (*.exe)|*.exe|所有文件 (*.*)|*.*";
                // 从当前探到的位置开一层,已经对的时候用户不用从头翻。
                string seed = Paths.Spb;
                if (!string.IsNullOrEmpty(seed))
                {
                    string bin = Path.Combine(seed, @"tools\bin");
                    d.InitialDirectory = Directory.Exists(bin) ? bin : seed;
                }
                if (d.ShowDialog(this) != DialogResult.OK) return;

                string bad = Paths.SetManual(d.FileName);
                if (bad != null)
                {
                    MessageBox.Show(bad, "指定 Cadence 目录",
                        MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                ApplySpb(d.FileName, null);
            }
        }

        // 重新探测 + 重算所有路径 + 刷界面。改完设置必须走这条路:
        // Tool.Exe 是在 Manifest 里就地展开的,不重读清单的话它们还是老路径。
        void ApplySpb(string picked, string note)
        {
            Paths.Detect();
            Manifest.Reload();
            RefreshAll(mCats.SelectedItem as string);
            UpdatePickLabel();

            if (note != null) { mHint.Text = "  " + note; return; }
            mHint.Text = Paths.Spb == null
                ? "  还是没找到。选的是:" + picked
                : "  Cadence 目录:" + Paths.Spb + "(" + Paths.SpbFoundBy + ")";
        }

        void OnAddTool(object sender, EventArgs e)
        {
            using (var dlg = new AddToolForm(mCats.SelectedItem as string))
            {
                if (dlg.ShowDialog(this) != DialogResult.OK) return;

                try { AppendLocal(dlg.ToolName, dlg.ToolExe, dlg.ToolCat); }
                catch (Exception ex)
                {
                    MessageBox.Show("写入 tools.local.ini 失败。\n\n" + ex.Message
                        + "\n\n路径:" + Manifest.LocalPath,
                        "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }

                Manifest.Reload();
                RefreshAll(dlg.ToolCat);
                mHint.Text = "  已添加 " + dlg.ToolName + ",在「" + dlg.ToolCat + "」里。";
            }
        }

        // 追加一段。用 Append 而不是读-改-写:用户可能手工编辑过这个文件
        // (注释、order、自己排的顺序),整体重写会把那些都抹平。
        static void AppendLocal(string name, string exe, string cat)
        {
            string path = Manifest.LocalPath;
            var sb = new System.Text.StringBuilder();
            if (!File.Exists(path))
            {
                sb.Append("; 小开工具箱 —— 本地清单\r\n")
                  .Append("; 这个文件是你自己的,升级工具箱不会动它。\r\n")
                  .Append("; 手工改也行,格式和 tools.ini 一样。\r\n");
            }
            sb.Append("\r\n[").Append(name).Append("]\r\n")
              .Append("category = ").Append(cat).Append("\r\n")
              .Append("exe  = ").Append(exe).Append("\r\n")
              .Append("desc = ").Append(Path.GetFileName(exe)).Append("\r\n")
              // mine = 1:放到下半区。用户自己加的归在"自研"这半边,
              // 因为上半区那个标题写的是 Cadence 原厂工具。
              .Append("mine = 1\r\n");

            // 带 BOM 的 UTF-8。没 BOM 的话记事本按 ANSI 打开,用户看到的
            // 中文名是乱码 —— 而这个文件就是给人手改的。
            File.AppendAllText(path, sb.ToString(), new UTF8Encoding(true));
        }

        // 重建侧栏条目并回到指定分类。加完工具可能多出一个新分类,
        // 只刷网格的话侧栏里看不到它。
        void RefreshAll(string cat)
        {
            mCats.BeginUpdate();
            mCats.Items.Clear();
            foreach (string c in Manifest.Categories) mCats.Items.Add(c);
            mCats.EndUpdate();

            int i = mCats.Items.IndexOf(cat);
            if (i < 0) i = 0;
            if (mCats.Items.Count > 0)
            {
                // 分类没变时 SelectedIndex 不会触发 Changed,得自己刷一次。
                if (mCats.SelectedIndex == i) ShowCategory();
                else mCats.SelectedIndex = i;
            }
        }

        // 清单变化但当前分类没有变化时，只补侧栏，避免清空/重建两个
        // ListView 导致当前页面的图标出现短暂闪烁。
        void RefreshSidebar(string addedCategory)
        {
            // 常用工具包都落在已有分类，此时不要调用 BeginUpdate/EndUpdate，
            // 它会让原生子窗口整体失效并连带重画右侧网格。
            if (!string.IsNullOrEmpty(addedCategory) && mCats.Items.IndexOf(addedCategory) < 0)
                mCats.Items.Add(addedCategory);
        }

        // 从工具箱移除(只对用户自己加的)。删的是清单里的一段,不动磁盘上的
        // exe —— 这一点得在确认框里说清楚,"移除"很容易被当成"删软件"。
        void OnRemoveTool(object sender, EventArgs e)
        {
            Tool t = SelectedIn(mMineGrid);
            if (t == null || !t.Local) return;

            if (!string.IsNullOrEmpty(t.PackageId))
            {
                var pr = MessageBox.Show("移除工具包“" + t.PackageId + "”吗?\n\n将从工具箱移除其中所有工具，并删除已解压的文件。",
                    "小开工具箱", MessageBoxButtons.YesNo, MessageBoxIcon.Warning,
                    MessageBoxDefaultButton.Button2);
                if (pr != DialogResult.Yes) return;
                try
                {
                    RemoveLocalPackage(t.PackageId);
                    if (!string.IsNullOrEmpty(t.PackageRoot) && Directory.Exists(t.PackageRoot))
                        Directory.Delete(t.PackageRoot, true);
                    string cat0 = mCats.SelectedItem as string;
                    Manifest.Reload();
                    RefreshAll(cat0);
                    mHint.Text = "  已移除工具包 " + t.PackageId + "。";
                }
                catch (Exception ex)
                {
                    MessageBox.Show("移除工具包失败。\n\n" + ex.Message,
                        "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                }
                return;
            }

            var r = MessageBox.Show("把 " + t.Name + " 从工具箱里移除?\n\n"
                + "只是不再显示这个图标,软件本身不会被删:\n" + t.Exe,
                "小开工具箱", MessageBoxButtons.YesNo, MessageBoxIcon.Question,
                MessageBoxDefaultButton.Button2);
            if (r != DialogResult.Yes) return;

            try { RemoveLocal(t.Name); }
            catch (Exception ex)
            {
                MessageBox.Show("改写 tools.local.ini 失败。\n\n" + ex.Message,
                    "小开工具箱", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                return;
            }

            string cat = mCats.SelectedItem as string;
            Manifest.Reload();
            RefreshAll(cat);
            mHint.Text = "  已移除 " + t.Name + "。";
        }

        // 删掉 [name] 那一段:从它的段头开始,一直到下一个段头之前。
        // 段内的注释跟着一起走 —— 它们是在说这个工具,留着就成了孤儿。
        static void RemoveLocal(string name)
        {
            string path = Manifest.LocalPath;
            if (!File.Exists(path)) return;

            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            var keep = new List<string>();
            bool drop = false;
            foreach (string raw in lines)
            {
                string s = raw.Trim();
                if (s.StartsWith("[") && s.EndsWith("]"))
                    drop = s.Substring(1, s.Length - 2).Trim() == name;
                if (!drop) keep.Add(raw);
            }
            File.WriteAllLines(path, keep.ToArray(), new UTF8Encoding(true));
        }

        static void RemoveLocalPackage(string packageId)
        {
            string path = Manifest.LocalPath;
            if (!File.Exists(path)) return;
            string[] lines = File.ReadAllLines(path, Encoding.UTF8);
            var keep = new List<string>();
            var block = new List<string>();
            foreach (string raw in lines)
            {
                string s = raw.Trim();
                if (s.StartsWith("[") && s.EndsWith("]"))
                {
                    if (block.Count > 0 && !BlockHasPackage(block, packageId)) keep.AddRange(block);
                    block.Clear();
                }
                block.Add(raw);
            }
            if (block.Count > 0 && !BlockHasPackage(block, packageId)) keep.AddRange(block);
            File.WriteAllLines(path, keep.ToArray(), new UTF8Encoding(true));
        }

        static bool BlockHasPackage(List<string> block, string packageId)
        {
            string wanted = "package";
            foreach (string raw in block)
            {
                int eq = raw.IndexOf('=');
                if (eq < 0) continue;
                if (raw.Substring(0, eq).Trim().ToLowerInvariant() == wanted &&
                    raw.Substring(eq + 1).Trim() == packageId) return true;
            }
            return false;
        }
    }

    // 添加工具的对话框。手写而不是拿 InputBox 凑:要选文件、要挑分类,
    // 分三次弹框问三个问题的体验比一个小窗差得多。
    class AddToolForm : Form
    {
        TextBox mName;
        TextBox mExe;
        ComboBox mCat;

        public string ToolName { get { return mName.Text.Trim(); } }
        public string ToolExe  { get { return mExe.Text.Trim(); } }
        public string ToolCat  { get { return mCat.Text.Trim(); } }

        public AddToolForm(string preset)
        {
            Text = "添加其他软件";
            FormBorderStyle = FormBorderStyle.FixedDialog;
            StartPosition = FormStartPosition.CenterParent;
            MaximizeBox = false;
            MinimizeBox = false;
            ClientSize = new Size(468, 186);
            BackColor = Theme.GridBg;
            ForeColor = Color.FromArgb(0xE8, 0xF4, 0xFA);
            Font = new Font("Microsoft YaHei UI", 9f);

            Controls.Add(MakeLabel("程序", 18));
            mExe = MakeBox(64, 18, 306);
            Controls.Add(mExe);

            var browse = new Button
            {
                Text = "浏览…", Bounds = new Rectangle(378, 16, 72, 25),
                FlatStyle = FlatStyle.Flat, BackColor = Theme.SideSel,
                ForeColor = Color.FromArgb(0xE8, 0xF4, 0xFA), UseVisualStyleBackColor = false
            };
            browse.Click += OnBrowse;
            Controls.Add(browse);

            Controls.Add(MakeLabel("名称", 56));
            mName = MakeBox(64, 56, 386);
            Controls.Add(mName);

            Controls.Add(MakeLabel("分类", 94));
            mCat = new ComboBox
            {
                Bounds = new Rectangle(64, 92, 386, 24),
                // DropDown 而不是 DropDownList:除了现有分类,也让人能敲一个新的。
                DropDownStyle = ComboBoxStyle.DropDown,
                FlatStyle = FlatStyle.Flat,
                BackColor = Theme.HeadBg, ForeColor = Color.FromArgb(0xE8, 0xF4, 0xFA)
            };
            foreach (string c in Manifest.Categories) mCat.Items.Add(c);
            // 默认落在当前正看着的分类上 —— 大多数人是"看到这一页缺个东西"
            // 才去点添加的。它要是空的就退到其他辅助工具。
            if (!string.IsNullOrEmpty(preset)) mCat.Text = preset;
            else if (mCat.Items.Count > 0) mCat.SelectedIndex = 0;
            Controls.Add(mCat);

            var ok = new Button
            {
                Text = "添加", Bounds = new Rectangle(288, 140, 76, 28),
                DialogResult = DialogResult.OK, FlatStyle = FlatStyle.Flat,
                BackColor = Theme.SideSel, ForeColor = Color.FromArgb(0xE8, 0xF4, 0xFA),
                UseVisualStyleBackColor = false
            };
            ok.Click += OnOk;
            var cancel = new Button
            {
                Text = "取消", Bounds = new Rectangle(374, 140, 76, 28),
                DialogResult = DialogResult.Cancel, FlatStyle = FlatStyle.Flat,
                BackColor = Theme.HeadBg, ForeColor = Color.FromArgb(0xE8, 0xF4, 0xFA),
                UseVisualStyleBackColor = false
            };
            Controls.Add(ok);
            Controls.Add(cancel);
            AcceptButton = ok;
            CancelButton = cancel;
        }

        Label MakeLabel(string txt, int y)
        {
            return new Label
            {
                Text = txt, Bounds = new Rectangle(14, y + 3, 46, 20),
                ForeColor = Color.FromArgb(0xA8, 0xC8, 0xDC)
            };
        }

        TextBox MakeBox(int x, int y, int w)
        {
            return new TextBox
            {
                Bounds = new Rectangle(x, y, w, 24), BorderStyle = BorderStyle.FixedSingle,
                BackColor = Theme.HeadBg, ForeColor = Color.FromArgb(0xE8, 0xF4, 0xFA)
            };
        }

        void OnBrowse(object sender, EventArgs e)
        {
            using (var d = new OpenFileDialog())
            {
                d.Title = "选择要添加的程序";
                d.Filter = "程序 (*.exe;*.bat;*.cmd;*.lnk)|*.exe;*.bat;*.cmd;*.lnk"
                    + "|所有文件 (*.*)|*.*";
                if (d.ShowDialog(this) != DialogResult.OK) return;
                mExe.Text = d.FileName;
                // 名字空着就用文件名填上。已经填了的不动 —— 那是用户敲的。
                if (mName.Text.Trim().Length == 0)
                    mName.Text = Path.GetFileNameWithoutExtension(d.FileName);
            }
        }

        void OnOk(object sender, EventArgs e)
        {
            string bad = FindProblem();
            if (bad == null) return;
            MessageBox.Show(bad, "添加其他软件",
                MessageBoxButtons.OK, MessageBoxIcon.Information);
            DialogResult = DialogResult.None;   // 拦住,别把窗关了
        }

        // 返回出错原因,没问题返回 null。
        // 没叫 Validate:Form 继承来的 ContainerControl.Validate() 是别的意思,
        // 同名会把它藏掉,以后谁调 this.Validate() 都会拿到错的东西。
        string FindProblem()
        {
            if (ToolExe.Length == 0) return "先选一个程序。";
            if (!File.Exists(ToolExe)) return "这个文件不存在:\n" + ToolExe;
            if (ToolName.Length == 0) return "给它起个名字。";
            // 名字是清单里的段头,方括号会让那一行解析不出来。
            if (ToolName.IndexOfAny(new[] { '[', ']', '=' }) >= 0)
                return "名称里不能有 [ ] = 这三个符号。";
            if (ToolCat.Length == 0) return "选一个分类,或者自己敲一个新的。";
            if (Manifest.Tools.Exists(delegate (Tool t) { return t.Name == ToolName; }))
                return "已经有一个叫「" + ToolName + "」的工具了,换个名字。";
            return null;
        }
    }

    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);

            Paths.Detect();
            Manifest.Load(Path.Combine(Paths.Toolbox, "tools.ini"));

            Application.Run(new MainForm());
        }
    }
}
