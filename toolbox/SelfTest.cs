// SPDX-License-Identifier: GPL-3.0-only
// 控制台自检。和 Toolbox.cs 一起编译,用 /main:CadenceToolbox.SelfTest
// 指定入口,这样不用改主程序就能验证非 GUI 的逻辑。
//
//     powershell -File toolbox\build.ps1 -Test
//
// 手工编的话:
//
//     csc /target:exe /main:CadenceToolbox.SelfTest Toolbox.cs SelfTest.cs
//
// 验的是真正会出错的地方:SPB 探测对不对、清单读没读到、
// 每个工具的 exe 是否真的存在。GUI 画得对不对得靠眼睛看。
using System;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace CadenceToolbox
{
    static class SelfTest
    {
        static int sPass, sFail;

        static void Check(string name, bool ok, string detail)
        {
            if (ok) { sPass++; Console.WriteLine("  ok   " + name); }
            else { sFail++; Console.WriteLine("  FAIL " + name + "  <- " + detail); }
        }

        static void Main()
        {
            Console.OutputEncoding = System.Text.Encoding.UTF8;

            Paths.Detect();
            Console.WriteLine("SPB detect");
            Console.WriteLine("  spb     : " + (Paths.Spb ?? "(not found)"));
            Console.WriteLine("  cadroot : " + (Paths.CadRoot ?? "(n/a)"));
            Console.WriteLine("  foundBy : " + Paths.SpbFoundBy);
            Console.WriteLine("  toolbox : " + Paths.Toolbox);
            Console.WriteLine();

            if (Paths.Spb != null)
            {
                Check("SPB found", Paths.Spb != null, "detection returned null");
                // 判据不能是"allegro.exe 在" —— 只装 Capture 的机器上它不在,而那
                // 恰好是探测失败的那种机器。这里只要求判据文件里有一个在,具体哪个
                // 不管;真正的反例在 Detection() 里用假目录树造。
                Check("a marker exe under SPB",
                    Paths.Spb != null && Paths.ClimbToRoot(Paths.Spb) != null,
                    "no marker matched under " + (Paths.Spb ?? "(null)"));
                Check("CADROOT is SPB parent",
                    Paths.CadRoot != null && Directory.Exists(Paths.CadRoot), "not a directory");

                // 占位符展开
                Console.WriteLine("\nplaceholder expansion");
                string ex = Paths.Expand(@"%SPB%\tools\bin\Capture.exe");
                Console.WriteLine("  %SPB%\\tools\\bin\\Capture.exe -> " + ex);
                Check("%SPB% expands", ex.IndexOf('%') < 0, "still contains %");
                Check("expanded path exists", File.Exists(ex), ex);
                Check("%CADROOT% expands",
                    Paths.Expand("%CADROOT%").IndexOf('%') < 0, "still contains %");
            }
            else Console.WriteLine("  SKIP installed Cadence checks: no SPB installation detected");
            Check("%TOOLBOX% expands",
                Paths.Expand("%TOOLBOX%").IndexOf('%') < 0, "still contains %");

            // 清单
            string ini = Path.Combine(Paths.Toolbox, "tools.ini");
            Manifest.Load(ini);
            Console.WriteLine("\nmanifest " + ini);
            Check("no load error", Manifest.Error == null, Manifest.Error ?? "");
            Check("tools parsed", Manifest.Tools.Count > 0, "zero tools");
            Check("categories parsed", Manifest.Categories.Count > 0, "zero categories");
            Console.WriteLine("  tools      : " + Manifest.Tools.Count);
            Console.WriteLine("  categories : " + Manifest.Categories.Count);

            // [toolbox] 那段不能被当成工具
            bool leaked = false;
            foreach (Tool t in Manifest.Tools)
                if (t.Name.Equals("toolbox", StringComparison.OrdinalIgnoreCase)) leaked = true;
            Check("[toolbox] not a tool", !leaked, "settings section became a tool entry");

            // 每个工具都得有分类,否则它不会出现在任何分类页里 —— 静默消失
            foreach (Tool t in Manifest.Tools)
                if (string.IsNullOrEmpty(t.Category))
                    Check("has category: " + t.Name, false, "category missing");

            // 分类里的工具数加起来应该等于总数,否则有工具的分类名拼错了
            int sum = 0;
            foreach (string c in Manifest.Categories) sum += Manifest.InCategory(c).Count;
            Check("every tool reachable from a category", sum == Manifest.Tools.Count,
                "sum=" + sum + " total=" + Manifest.Tools.Count);

            TestCapturePluginStatus();
            TestAllegroSkillStatus();

            // 逐个工具报告
            Console.WriteLine("\nper-tool resolution");
            int have = 0, miss = 0;
            foreach (string c in Manifest.Categories)
            {
                Console.WriteLine("  [" + c + "]");
                foreach (Tool t in Manifest.InCategory(c))
                {
                    if (t.Exists) { have++; Console.WriteLine("    ok      " + t.Name); }
                    else { miss++; Console.WriteLine("    MISSING " + t.Name + "  " + t.Missing); }

                    // 说明是给用户看的,空的说明等于没提示
                    if (string.IsNullOrEmpty(t.Desc))
                        Check("has desc: " + t.Name, false, "desc empty");
                }
            }
            Console.WriteLine("\n  present: " + have + "   missing: " + miss);

            // 图标:抽不到也必须给出占位图,不能返回 null 让界面崩
            Console.WriteLine("\nicons");
            int nullIcon = 0;
            foreach (Tool t in Manifest.Tools)
                if (Icons.For(t) == null) nullIcon++;
            Check("no null icons", nullIcon == 0, nullIcon + " tools returned null");
            bool wrongIconSize = false;
            foreach (Tool t in Manifest.Tools)
                if (Icons.For(t).Width != 32 || Icons.For(t).Height != 32)
                    wrongIconSize = true;
            Check("original 32px icon display size preserved", !wrongIconSize,
                "tool icon bitmap size changed");
            Check("recent DSN extension filter",
                RecentDocuments.HasExtension(@"C:\design\board.dsn", ".dsn"),
                "DSN file was not accepted");
            Check("recent file extension filter is case-insensitive",
                RecentDocuments.HasExtension(@"C:\design\board.BRD", ".brd"),
                "uppercase BRD extension was not accepted");
            Check("recent DSN filter rejects BRD",
                !RecentDocuments.HasExtension(@"C:\design\board.brd", ".dsn"),
                "BRD was accepted as DSN");
            Check("document launch arguments preserve spaces",
                RecentDocuments.QuoteArgument(@"C:\design files\board.dsn") ==
                    "\"C:\\design files\\board.dsn\"",
                "quoted path mismatch");
            try
            {
                var recentDsn = RecentDocuments.Read(".dsn", 5);
                var recentBrd = RecentDocuments.Read(".brd", 5);
                bool validRecentFiles = recentDsn.Count <= 5 && recentBrd.Count <= 5;
                foreach (RecentDocument document in recentDsn)
                    validRecentFiles = validRecentFiles
                        && RecentDocuments.HasExtension(document.Path, ".dsn")
                        && File.Exists(document.Path);
                foreach (RecentDocument document in recentBrd)
                    validRecentFiles = validRecentFiles
                        && RecentDocuments.HasExtension(document.Path, ".brd")
                        && File.Exists(document.Path);
                Check("recent DSN/BRD records resolve to existing files", validRecentFiles,
                    "recent list contained an invalid document");
                Console.WriteLine("  recent DSN : " + recentDsn.Count
                    + "    recent BRD : " + recentBrd.Count);
            }
            catch (Exception recentException)
            {
                Check("recent DSN/BRD records resolve to existing files", false, recentException.Message);
            }

            SplitZones();
            LocalManifest();
            Detection();

            // 界面上显示的版本号和编进 exe 资源的必须一致 —— 安装脚本读的是
            // 资源里那个,不一致的话装完报的版本号是错的。
            Console.WriteLine("\nversion");
            string shown = MainForm.Version;
            string stamped = System.Reflection.Assembly.GetExecutingAssembly()
                .GetName().Version.ToString();
            Console.WriteLine("  kVersion        : " + shown);
            Console.WriteLine("  AssemblyVersion : " + stamped);
            // 资源里是四段(1.0.0.0),kVersion 是三段,所以比前缀。
            Check("versions agree", stamped.StartsWith(shown + "."),
                shown + " vs " + stamped);

            Console.WriteLine("\nlaunched tool cleanup");
            var childStart = new ProcessStartInfo(
                Path.Combine(Environment.SystemDirectory, "cmd.exe"),
                "/d /c ping 127.0.0.1 -n 30 >nul")
            {
                UseShellExecute = false,
                CreateNoWindow = true
            };
            Process child = ToolProcessManager.Start(childStart, "self-test child");
            int childId = child.Id;
            string closeErrors = ToolProcessManager.CloseAll(100);
            Check("toolbox exit closes tracked process tree",
                !ToolProcessManager.IsRunning(childId) && string.IsNullOrEmpty(closeErrors),
                string.IsNullOrEmpty(closeErrors) ? "process still running" : closeErrors);

            Console.WriteLine("\n" + sPass + " passed, " + sFail + " failed");
            Environment.Exit(sFail == 0 ? 0 : 1);
        }

        // 探测判据和"选一个 exe 反推安装根"。
        //
        // 用假目录树造反例,不靠这台机器的真实安装 —— 这台机器装了 Allegro,
        // 拿它测永远测不出"只装 Capture 就认不出来"这个 bug,那正是用户报的问题。
        static void Detection()
        {
            Console.WriteLine("\n安装目录探测");

            string tmp = Path.Combine(Path.GetTempPath(),
                "xkt-detect-" + Guid.NewGuid().ToString("N").Substring(0, 8));
            try
            {
                // 只装了 Capture:没有 allegro.exe。旧判据在这儿会判成"没装"。
                string cap = Path.Combine(tmp, "CaptureOnly");
                Directory.CreateDirectory(Path.Combine(cap, @"tools\bin"));
                File.WriteAllText(Path.Combine(cap, @"tools\bin\capture.exe"), "x");
                Check("只装 Capture 也认得出", Paths.ClimbToRoot(cap) == cap,
                    "got " + (Paths.ClimbToRoot(cap) ?? "(null)"));

                // 从 exe 反推:用户指的是 exe,不是目录。
                Check("从 exe 往上找到根",
                    Paths.ClimbToRoot(Path.Combine(cap, @"tools\bin\capture.exe")) == cap,
                    "climb from exe failed");

                // 只装了 Allegro:原来那条路不能因为放宽判据而坏掉。
                string alg = Path.Combine(tmp, "AllegroOnly");
                Directory.CreateDirectory(Path.Combine(alg, @"tools\bin"));
                File.WriteAllText(Path.Combine(alg, @"tools\bin\allegro.exe"), "x");
                Check("只装 Allegro 仍然认得出", Paths.ClimbToRoot(alg) == alg, "regressed");

                // 空壳目录:卸载残留会骗过"目录存在"这种判据。
                string shell = Path.Combine(tmp, "Empty");
                Directory.CreateDirectory(Path.Combine(shell, @"tools\bin"));
                Check("空壳目录不算", Paths.ClimbToRoot(shell) == null, "accepted an empty tree");

                // 往上爬不能爬穿:随便一个临时目录不该把 C:\ 认成安装根。
                Check("不会一路爬到盘符",
                    Paths.ClimbToRoot(Path.Combine(tmp, "nope", "deeper")) == null,
                    "climbed too far");

                // 装了两个版本时挑新的。GetDirectories 是字母序,不排的话
                // SPB_16.6 会赢过 SPB_17.4 —— 装了新版却一直指着旧版,界面上
                // 看不出选错了。顺带一个 17.10 vs 17.4:按字符串比会反。
                string multi = Path.Combine(tmp, "Multi");
                foreach (string v in new[] { "SPB_16.6", "SPB_17.4", "SPB_17.10" })
                {
                    string bin = Path.Combine(multi, v, @"tools\bin");
                    Directory.CreateDirectory(bin);
                    File.WriteAllText(Path.Combine(bin, "capture.exe"), "x");
                }
                Check("多版本挑最新",
                    Paths.BestUnder(multi) == Path.Combine(multi, "SPB_17.10"),
                    "picked " + (Paths.BestUnder(multi) ?? "(null)"));

                // 许可证反推:CDS_LIC_FILE 指向 ...\Cadence\LicenseManager\xxx,
                // 往上两级是根。文件名不能写死 cds.lic —— 这台机器上叫 license.dat。
                string lroot = Path.Combine(tmp, "LicTree");
                string lm = Path.Combine(lroot, "LicenseManager");
                Directory.CreateDirectory(lm);
                File.WriteAllText(Path.Combine(lm, "license.dat"), "SERVER localhost ANY 5280");
                string lbin = Path.Combine(lroot, "SPB_17.4", @"tools\bin");
                Directory.CreateDirectory(lbin);
                File.WriteAllText(Path.Combine(lbin, "capture.exe"), "x");
                Check("从许可证路径反推",
                    Paths.FromLicense(Path.Combine(lm, "license.dat"))
                        == Path.Combine(lroot, "SPB_17.4"),
                    "got " + (Paths.FromLicense(Path.Combine(lm, "license.dat")) ?? "(null)"));
                // port@host 是许可证服务器,不是路径。不挡住会在 GetDirectoryName 上抛。
                Check("许可证服务器不当路径", Paths.FromLicense("5280@localhost") == null,
                    "treated port@host as a path");
                Check("空的许可证变量不炸", Paths.FromLicense(null) == null, "threw or matched");

                // 这个键是真写注册表的,所以先记下原来的值,最后一定要还回去 ——
                // 不然跑完自检这台机器的工具箱就被钉在假路径上了。
                string keep = Paths.LoadManual();
                try
                {
                    // 手动指定:存之前先验,验不过不写。
                    string err = Paths.SetManual(shell);
                    Check("手动指到没有 Cadence 的地方会被拒", err != null, "accepted a bad dir");
                    // 断言是"没被改动",不是"读出来是 null" —— 用户本来就设过一个
                    // 好路径时,选错一次不该把它冲掉。写成比 null 的话,只有在
                    // 机器上碰巧没设过的时候才过,反而把这条正确行为测反了。
                    Check("被拒时不动原来的设置", Paths.LoadManual() == keep,
                        "was " + (keep ?? "(null)") + ", now " + (Paths.LoadManual() ?? "(null)"));

                    Check("手动指定存得进去", Paths.SetManual(cap) == null, "SetManual failed");
                    Check("存的是根不是 exe", Paths.LoadManual() == cap,
                        "stored " + (Paths.LoadManual() ?? "(null)"));

                    // 手动的必须盖过自动探测,否则那个按钮点了没反应。
                    Paths.Detect();
                    Check("手动指定优先于自动探测", Paths.Spb == cap,
                        "detect gave " + (Paths.Spb ?? "(null)") + ", foundBy=" + Paths.SpbFoundBy);
                    Check("来源标成手动", Paths.SpbFoundBy == "手动指定", Paths.SpbFoundBy);

                    // 指着的目录没了要能报出来,不然界面说"没探到"、设置里却有路径。
                    Directory.Delete(Path.Combine(cap, @"tools\bin"), true);
                    Check("失效的手动路径能查出来", Paths.StaleManual() == cap,
                        "stale=" + (Paths.StaleManual() ?? "(null)"));
                }
                finally
                {
                    Paths.SetManual(null);
                    // 还原绕过 SetManual:它要校验路径,而用户原来存的那个可能此刻
                    // 正好失效(Cadence 挪走了)。走 SetManual 会被拒,于是自检把
                    // 用户的设置悄悄弄丢了 —— 自检不该有副作用。
                    if (keep != null)
                        using (var rk = Microsoft.Win32.Registry.CurrentUser
                            .CreateSubKey(@"Software\XiaokaiToolbox"))
                            if (rk != null) rk.SetValue("SpbDir", keep);
                }
                Check("清得掉", keep != null || Paths.LoadManual() == null, "still set");
                // 清完不留空键。只删值会留一个空壳,卸载后也还在。
                if (keep == null)
                    using (var rk = Microsoft.Win32.Registry.CurrentUser
                        .OpenSubKey(@"Software\XiaokaiToolbox"))
                        Check("清完不留空键", rk == null,
                            "empty key left behind with " +
                            (rk == null ? 0 : rk.GetValueNames().Length) + " values");

                // 清掉之后自动探测要回来。
                Paths.Detect();
                Check("清掉后回到自动探测",
                    Paths.SpbFoundBy != "手动指定" || keep != null, Paths.SpbFoundBy);
            }
            finally
            {
                try { Directory.Delete(tmp, true); } catch { }
            }
        }

        // 上下分区靠 Tool.Mine 决定,右键菜单的可用性靠 Tool.HasUninstaller。
        // 这两个都是从 ini 里解析出来的,解析错了界面上看不出问题 —— 自研工具会
        // 安安静静地混在原厂工具里,右键菜单则是灰的。
        static void SplitZones()
        {
            Console.WriteLine("\n上下分区");

            int mine = 0, cad = 0;
            foreach (Tool t in Manifest.Tools) { if (t.Mine) mine++; else cad++; }
            Console.WriteLine("  自研: " + mine + "   原厂: " + cad);
            Check("两边都有工具", mine > 0 && cad > 0, "mine=" + mine + " cadence=" + cad);

            // 原厂工具绝不该带卸载命令:它们跟着 SPB 装,卸载得走 Cadence 的
            // 安装器。这里漏标 mine 的话,右键卸载会出现在错的地方。
            int badUninst = 0;
            foreach (Tool t in Manifest.Tools)
                if (!t.Mine && t.HasUninstaller) badUninst++;
            Check("原厂工具不带卸载命令", badUninst == 0, badUninst + " 个带了");

            bool hasPluginTile = false;
            foreach (Tool t in Manifest.Tools)
                if (t.Name.StartsWith("lceda2orcad", StringComparison.OrdinalIgnoreCase)
                    || t.Name.StartsWith("BOM整理工具", StringComparison.OrdinalIgnoreCase)
                    || t.Name.StartsWith("netlocator", StringComparison.OrdinalIgnoreCase))
                    hasPluginTile = true;
            Check("Capture插件不再提供独立安装或卸载入口",
                !hasPluginTile, "tools.ini 仍包含独立插件条目");

            Tool lookup = Find("常见丝印反查 v1.0");
            Check("丝印反查可从其他辅助工具启动", lookup != null && lookup.Mine
                && lookup.Category == "其他辅助工具" && lookup.Exists && !lookup.HasUninstaller,
                lookup == null ? "没找到" : lookup.Exe);

            Tool gen = Find("元器件规格描述生成器 v1.0");
            Check("元器件规格描述生成器在清单里", gen != null, "没找到");
            Check("元器件规格描述生成器标为自研", gen != null && gen.Mine,
                gen == null ? "没找到" : "Mine=" + gen.Mine);
            // 绿色版,没有卸载程序 —— 右键菜单该是灰的而不是点了跑个不存在的命令。
            Check("元器件规格描述生成器无卸载命令",
                gen != null && !gen.HasUninstaller,
                gen == null ? "没找到" : "HasUninstaller=" + gen.HasUninstaller);
            // 它跟原理图/PCB 无关,不该混在 OrCAD 页里。
            Check("元器件规格描述生成器归到其他辅助工具",
                gen != null && gen.Category == "其他辅助工具",
                gen == null ? "没找到" : gen.Category);

            // 单击图标要在底部显示详细说明。help 缺了会退回 desc,那是一行字,
            // 界面上不报错 —— 只是"使用说明"变成了一句话。
            Check("元器件规格描述生成器有简洁说明", gen != null && gen.Help.Length > 0 && gen.Help.Length <= 180,
                gen == null ? "没找到" : "len=" + gen.Help.Length);

            Tool jlc = Find("嘉立创 3D 模型下载器 v2.0");
            Check("嘉立创 3D 模型下载器在清单里", jlc != null, "没找到");
            Check("嘉立创 3D 模型下载器标为自研", jlc != null && jlc.Mine,
                jlc == null ? "没找到" : "Mine=" + jlc.Mine);
            // 绿色版单 exe,没有安装器 —— 右键卸载该是灰的,不是跑一条不存在的命令。
            Check("嘉立创 3D 模型下载器无卸载命令",
                jlc != null && !jlc.HasUninstaller,
                jlc == null ? "没找到" : "HasUninstaller=" + jlc.HasUninstaller);
            // 它抓的是元件库资产(3D 模型),和 Library Explorer 那些是一类事,
            // 所以归"库与转换"而不是"其他辅助工具"。
            Check("嘉立创 3D 模型下载器归到库与转换",
                jlc != null && jlc.Category == "库与转换",
                jlc == null ? "没找到" : jlc.Category);
            Check("嘉立创 3D 模型下载器有简洁说明",
                jlc != null && jlc.Help.Length > 0 && jlc.Help.Length <= 180,
                jlc == null ? "没找到" : "len=" + jlc.Help.Length);
            // 它的图标必须自己指。exe 里嵌了图标,但 exe 还没打出来时
            // (这台机器没装 PyInstaller)格子得有东西显示。
            Check("嘉立创 3D 模型下载器指定了图标",
                jlc != null && !string.IsNullOrEmpty(jlc.IconFrom),
                jlc == null ? "没找到" : "icon 空着");

            // 已经没有"自研工具"这个分类了,分区取代了它。留着的话同一个工具
            // 会在两个地方出现。
            bool stale = false;
            foreach (string c in Manifest.Categories) if (c == "自研工具") stale = true;
            Check("没有遗留的自研工具分类", !stale, "还在分类列表里");
        }

        // tools.local.ini:自己加的工具放这里,装新版不会被覆盖。
        // 在临时目录里跑 —— 直接在产物目录写一个 tools.local.ini,万一测试中途
        // 挂掉就会留在那儿,悄悄改掉真正运行时看到的工具列表。
        static void LocalManifest()
        {
            Console.WriteLine("\ntools.local.ini");
            string dir = Path.Combine(Path.GetTempPath(), "tbx-selftest-" + Guid.NewGuid().ToString("N"));
            try
            {
                Directory.CreateDirectory(dir);
                var utf8 = new UTF8Encoding(false);
                File.WriteAllText(Path.Combine(dir, "tools.ini"),
                    "[toolbox]\norder = 甲 | 乙\n\n" +
                    "[原有工具]\ncategory = 甲\nexe = %SPB%\\tools\\bin\\Capture.exe\ndesc = 随包发的。\n" +
                    "[会被改掉的]\ncategory = 甲\nexe = %SPB%\\tools\\bin\\Capture.exe\ndesc = 原说明。\n", utf8);

                // 只加东西,不写 order:新分类应该自动补在末尾。
                File.WriteAllText(Path.Combine(dir, "tools.local.ini"),
                    "[自己加的]\ncategory = 丙\nexe = %SPB%\\tools\\bin\\allegro.exe\ndesc = 本地追加。\n" +
                    "[会被改掉的]\ncategory = 甲\nexe = %SPB%\\tools\\bin\\allegro.exe\ndesc = 改后说明。\n", utf8);

                Manifest.Reset();
                Manifest.Load(Path.Combine(dir, "tools.ini"));
                Check("local ini loads", Manifest.Error == null, Manifest.Error ?? "");
                Check("local tool added", Find("自己加的") != null, "not in the list");
                Check("new category appended", Manifest.Categories.Contains("丙"),
                    "categories: " + string.Join(",", Manifest.Categories.ToArray()));
                Check("declared order kept first",
                    Manifest.Categories.Count == 3 && Manifest.Categories[0] == "甲"
                        && Manifest.Categories[2] == "丙",
                    string.Join(",", Manifest.Categories.ToArray()));

                Tool over = Find("会被改掉的");
                Check("local entry overrides shipped one",
                    over != null && over.Desc == "改后说明。",
                    over == null ? "missing" : "desc=" + over.Desc);
                // 覆盖必须是替换而不是新增,否则界面上会出现两个同名图标。
                int dup = 0;
                foreach (Tool t in Manifest.Tools) if (t.Name == "会被改掉的") dup++;
                Check("override replaces, not duplicates", dup == 1, "found " + dup);
                Check("shipped tool survives", Find("原有工具") != null, "lost from the list");

                // 没有 tools.local.ini 时不能报错 —— 绝大多数机器上就是没有。
                File.Delete(Path.Combine(dir, "tools.local.ini"));
                Manifest.Reset();
                Manifest.Load(Path.Combine(dir, "tools.ini"));
                Check("absent local ini is not an error", Manifest.Error == null, Manifest.Error ?? "");
                Check("without local ini only shipped tools", Manifest.Tools.Count == 2,
                    "count=" + Manifest.Tools.Count);

                // Local 标记决定右键有没有"从工具箱移除"。随包那份不能带这个
                // 标记 —— 移掉了装新版又会回来,按钮等于骗人。
                File.WriteAllText(Path.Combine(dir, "tools.local.ini"),
                    "[自己加的]\ncategory = 丙\nexe = %SPB%\\tools\\bin\\allegro.exe\n" +
                    "help = 第一行\\n第二行\\\\尾巴 C:\\Cadence\n", utf8);
                Manifest.Reset();
                Manifest.Load(Path.Combine(dir, "tools.ini"));
                Tool loc = Find("自己加的");
                Check("本地条目标为 Local", loc != null && loc.Local,
                    loc == null ? "没找到" : "Local=" + loc.Local);
                Check("随包条目不标 Local",
                    Find("原有工具") != null && !Find("原有工具").Local, "被标成本地了");
                // \n 变真换行,\\ 变一个反斜杠,不认识的 \C 原样留着 ——
                // 说明里写 Windows 路径是常事,吞掉反斜杠会让路径变成错的。
                Check("Unescape 处理三种情况",
                    loc != null && loc.Help == "第一行\n第二行\\尾巴 C:\\Cadence",
                    loc == null ? "没找到" : "'" + loc.Help + "'");

                // Reload 忘了 Reset 的话每个工具会变成两份。
                int before = Manifest.Tools.Count;
                Manifest.Reload();
                Check("Reload 不重复累加", Manifest.Tools.Count == before,
                    before + " -> " + Manifest.Tools.Count);
            }
            catch (Exception e)
            {
                Check("local ini test ran", false, e.Message);
            }
            finally
            {
                try { Directory.Delete(dir, true); } catch { }
            }
        }

        static Tool Find(string name)
        {
            foreach (Tool t in Manifest.Tools) if (t.Name == name) return t;
            return null;
        }

        static void TestAllegroSkillStatus()
        {
            string dir = Path.Combine(Path.GetTempPath(), "xkt-skill-status-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            try
            {
                foreach (string name in XiaokaiAllegro.SkillFiles.Names)
                    File.WriteAllText(Path.Combine(dir, name), "");
                Check("SKILL files without startup are not installed", AllegroSkillStatus.InstalledPluginsIn(dir).Count == 0, "");
                var init = new System.Text.StringBuilder("; BEGIN XIAOKAI ALLEGRO SELECTED TOOLS\n");
                foreach (string name in XiaokaiAllegro.SkillFiles.Names)
                    if (name.EndsWith(".il")) init.Append("load(\"C:/test/").Append(name)
                        .Append(name == "x_silk_in_out.il" ? "\" \"deargds\")\n" : "\")\n");
                init.Append("; END XIAOKAI ALLEGRO SELECTED TOOLS\n");
                File.WriteAllText(Path.Combine(dir, "allegro.ilinit"), init.ToString());
                var plugins = AllegroSkillStatus.InstalledPluginsIn(dir);
                Check("Allegro SKILL includes A1-A9 and selected B tools", plugins.Count == 21
                    && plugins[0].File == "Find_Component.il" && plugins[7].File == "show_height.il"
                    && plugins[8].File == "Auto_artwork.il" && plugins[9].File == "x_change_via_net.il"
                    && plugins[10].File == "xiaokaiDanglings.il", "");
                Check("SKILL descriptions include usage and installed path", plugins.Count == 21
                    && plugins[0].Host == "Allegro" && plugins[0].Usage.Contains("Alt+K")
                    && plugins[0].Directory == dir && plugins[9].Usage.Contains("cvia"), "");
                Check("View tools retain A1-A8 numbering", plugins.GetRange(0, 8).TrueForAll(
                    delegate(CapturePluginStatus.PluginInfo p) { return p.Name.StartsWith("A") && p.Usage.Contains("Alt+K"); }), "");
                Check("A6 uses list implementation", plugins[5].File == "highlight_padstack.il", "");
                Check("Renumbered text tools retain enhanced overlap check and omit retired scripts", plugins.Exists(
                    delegate(CapturePluginStatus.PluginInfo p) { return p.File == "gxl_wdzcheck_text_overlap.il"; })
                    && !plugins.Exists(delegate(CapturePluginStatus.PluginInfo p) { return p.File == "check_dir.il" || p.File == "text_rotate.il" || p.File == "quick_textset.il"; }), "");
                Check("B2 silk import/export startup supports password", plugins.Exists(
                    delegate(CapturePluginStatus.PluginInfo p) { return p.File == "x_silk_in_out.il" && p.Usage.Contains("xk_silk_io"); }), "");
                Check("Check description excludes net editing", plugins.Count == 21
                    && !plugins[10].Usage.Contains("cvia"), "");
                File.Delete(Path.Combine(dir, "Quick_ColorS.il"));
                plugins = AllegroSkillStatus.InstalledPluginsIn(dir);
                Check("Incomplete combined tool is not listed", plugins.Count == 20
                    && !plugins.Exists(delegate(CapturePluginStatus.PluginInfo p) { return p.File == "Auto_artwork.il"; }), "");
                File.Delete(Path.Combine(dir, "xiaokaiDanglings.il"));
                plugins = AllegroSkillStatus.InstalledPluginsIn(dir);
                Check("Via net editor does not depend on Check", plugins.Count == 19
                    && plugins[8].File == "x_change_via_net.il", "");
                File.Delete(Path.Combine(dir, "xiaokaiAllegroMenu.il"));
                Check("Missing SKILL toolbox entry is not installed", AllegroSkillStatus.InstalledPluginsIn(dir).Count == 0, "");
            }
            finally { Directory.Delete(dir, true); }
        }

        static void TestCapturePluginStatus()
        {
            Console.WriteLine("\nCapture 插件状态检测");
            string dir = Path.Combine(Path.GetTempPath(),
                "xkt-plugin-status-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(dir);
            try
            {
                File.WriteAllText(Path.Combine(dir, "lceda2orcadMenu.tcl"), "");
                File.WriteAllText(Path.Combine(dir, "bomtoolMenu.tcl"), "");
                File.WriteAllText(Path.Combine(dir, "netlocatorMenu.tcl"), "");
                var installed = CapturePluginStatus.InstalledPluginsIn(dir);
                Check("显示已安装的 Capture 插件",
                    installed.Count == 3
                        && installed[0].Name == "Orcad内直接放置立创元件"
                        && installed[1].Name == "BOM输出增强版"
                        && installed[2].Name == "Signal一键全网络高亮"
                        && installed[0].Description.Length > 0
                        && installed[1].Description.Length > 0
                        && installed[2].Description.Length > 0,
                    string.Join(", ", installed.ConvertAll(delegate(
                        CapturePluginStatus.PluginInfo plugin) { return plugin.Name; }).ToArray()));
            }
            finally
            {
                try { Directory.Delete(dir, true); } catch { }
            }
        }
    }
}
