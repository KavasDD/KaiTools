// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Windows.Forms;
using System.Xml;
using System.Xml.Linq;

namespace OrCadStartup
{
    public sealed class Feature
    {
        public string Name, Impact;
        public string[] Files;
        public bool Mild;
        public Feature(string name, string impact, bool mild, params string[] files)
        { Name = name; Impact = impact; Mild = mild; Files = files; }
    }

    public static class Catalog
    {
        public static readonly Feature[] Features = {
            new Feature("示例设计浏览器", "移除 File 菜单中的 Demo Designs 入口。", true, "capAutoDemoBrowser.tcl"),
            new Feature("学习资源", "移除 Help 菜单中的 Learning PSpice 入口。", true, "caplearningresources.tcl"),
            new Feature("云元件库入口", "移除 Arrow / Ultra Librarian 集成菜单；使用这些库时请保留。", false, "capCloudMenu.tcl"),
            new Feature("OrCAD 欢迎页", "停用自动欢迎页及其打开入口；仍可通过 File 打开工程。", false, "capOrCADStartPage.tcl"),
            new Feature("PSpice 建模助手", "停用 27 个模型创建/编辑助手入口。已有模型的专用编辑功能也可能受影响；使用 PSpice 时建议保留。", false,
                "capAutoPSpiceModelAppAND.tcl", "capAutoPSpiceModelAppOR.tcl",
                "capAutoPSpiceModelAppPwlBJT.tcl", "capAutoPSpiceModelAppPwlBUF.tcl",
                "capAutoPSpiceModelAppPwlConstant.tcl", "capAutoPSpiceModelAppPwlCounter.tcl",
                "capAutoPSpiceModelAppPwlDigitalSources.tcl", "capAutoPSpiceModelAppPwlDiode.tcl",
                "capAutoPSpiceModelAppPwlIGBT.tcl", "capAutoPSpiceModelAppPwlJFET.tcl",
                "capAutoPSpiceModelAppPwlMOSFET.tcl", "capAutoPSpiceModelAppPwlPassives.tcl",
                "capAutoPSpiceModelAppPwlRegister.tcl", "capAutoPSpiceModelAppPwlTFF.tcl",
                "capAutoPSpiceModelAppPwlXOR.tcl", "capAutoPSpiceModelAppPwlZener.tcl",
                "capPSpiceModelAppA.tcl", "capPSpiceModelAppCapacitor.tcl",
                "capPSpiceModelAppInductor.tcl", "cappspicemodelappled.tcl",
                "capPSpiceModelAppPowerDiode.tcl", "capPSpiceModelAppPowerMosfet.tcl",
                "capPSpiceModelAppSwitch.tcl", "capPSpiceModelAppTransformer.tcl",
                "capPSpiceModelAppTVS.tcl", "capPSpiceModelAppVCO.tcl", "capPSpiceModelAppZener.tcl")
        };
        public static bool Allowed(string name)
        { return Features.Any(f => f.Files.Contains(name, StringComparer.OrdinalIgnoreCase)); }
    }

    // Manifest is committed before removing any startup file. Each backup is
    // immutable, hashed, and outside capAutoLoad. Interrupted work is restorable.
    public sealed class Engine
    {
        public readonly string Root, Backup;
        readonly Func<bool> running;
        string Manifest { get { return Path.Combine(Backup, "manifest.xml"); } }
        public Engine(string path) : this(path, CaptureRunning) { }
        internal Engine(string path, Func<bool> runningCheck)
        {
            Root = Normalize(path);
            Backup = Path.Combine(Path.GetDirectoryName(Root), "xiaokai-startup-backup");
            running = runningCheck;
            CheckDirectories();
        }
        public static bool CaptureRunning()
        {
            var processes = Process.GetProcessesByName("Capture");
            try { return processes.Length > 0; }
            finally { foreach (var p in processes) p.Dispose(); }
        }
        public static string Normalize(string path)
        {
            string p = Path.GetFullPath(Environment.ExpandEnvironmentVariables(path.Trim().Trim('"'))).TrimEnd('\\', '/');
            if (!Path.GetFileName(p).Equals("capAutoLoad", StringComparison.OrdinalIgnoreCase))
                p = Path.Combine(p, "tools", "capture", "tclscripts", "capAutoLoad");
            if (!Directory.Exists(p)) throw new IOException("未找到 capAutoLoad，请选择 SPB 安装目录或 capAutoLoad 目录。");
            return p;
        }
        static void NoLinks(string path)
        {
            for (string p = path; !String.IsNullOrEmpty(p); p = Path.GetDirectoryName(p))
                if ((Directory.Exists(p) || File.Exists(p)) && (File.GetAttributes(p) & FileAttributes.ReparsePoint) != 0)
                    throw new IOException("不支持符号链接或目录联接：" + p);
        }
        void CheckDirectories() { NoLinks(Root); NoLinks(Backup); }
        static void PlainFile(string path)
        {
            NoLinks(path);
            if (File.Exists(path) && (File.GetAttributes(path) & FileAttributes.ReadOnly) != 0)
                throw new IOException("文件为只读：" + path);
        }
        public static string Hash(string path)
        { using (var s = File.OpenRead(path)) using (var h = SHA256.Create()) return BitConverter.ToString(h.ComputeHash(s)).Replace("-", ""); }
        Dictionary<string, string> Load()
        {
            var entries = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
            if (!File.Exists(Manifest)) return entries;
            PlainFile(Manifest);
            var settings = new XmlReaderSettings { DtdProcessing = DtdProcessing.Prohibit, XmlResolver = null };
            XDocument doc;
            using (var reader = XmlReader.Create(Manifest, settings)) doc = XDocument.Load(reader);
            if (doc.Root == null || doc.Root.Name != "backup" || !String.Equals((string)doc.Root.Attribute("root"), Root, StringComparison.OrdinalIgnoreCase))
                throw new IOException("备份目录与当前安装路径不匹配。");
            foreach (var e in doc.Root.Elements("file"))
            {
                string name = (string)e.Attribute("name"), hash = (string)e.Attribute("sha256");
                if (name == null || !Catalog.Allowed(name) || name != Path.GetFileName(name) ||
                    hash == null || hash.Length != 64 || !hash.All(Uri.IsHexDigit) || entries.ContainsKey(name))
                    throw new IOException("备份清单不合法，已停止操作。");
                entries.Add(name, hash);
            }
            return entries;
        }
        void Save(Dictionary<string, string> entries)
        {
            var doc = new XDocument(new XElement("backup", new XAttribute("root", Root),
                entries.OrderBy(e => e.Key).Select(e => new XElement("file", new XAttribute("name", e.Key), new XAttribute("sha256", e.Value)))));
            string temp = Path.Combine(Backup, Guid.NewGuid().ToString("N") + ".tmp");
            using (var stream = new FileStream(temp, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { doc.Save(stream); stream.Flush(true); }
            if (File.Exists(Manifest)) File.Replace(temp, Manifest, null);
            else File.Move(temp, Manifest);
        }
        string Original(string name) { return Path.Combine(Root, name); }
        string CopyPath(string name, string hash) { return Path.Combine(Backup, name + "." + hash + ".bak"); }
        void VerifyBackup(string name, string hash)
        {
            string p = CopyPath(name, hash);
            PlainFile(p);
            if (!File.Exists(p) || Hash(p) != hash) throw new IOException("备份缺失或校验失败：" + name);
        }
        FileStream Begin()
        {
            CheckDirectories();
            if (running()) throw new IOException("请先保存工程并关闭所有 OrCAD Capture 窗口，再应用或恢复。");
            Directory.CreateDirectory(Backup);
            string lockPath = Path.Combine(Backup, "operation.lock");
            PlainFile(lockPath);
            return new FileStream(lockPath, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
        }
        public string[] Pending() { return Load().Keys.ToArray(); }
        public string[] Active() { return Directory.GetFiles(Root, "*.tcl").Select(Path.GetFileName).OrderBy(s => s).ToArray(); }
        public int Disable(IEnumerable<string> files)
        {
            var names = files.Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
            if (names.Any(n => !Catalog.Allowed(n))) throw new IOException("只能停用已识别的可选功能。");
            using (Begin())
            {
                var entries = Load();
                var before = new Dictionary<string, string>(entries, StringComparer.OrdinalIgnoreCase);
                var remove = new List<string>();
                foreach (string name in names)
                {
                    string p = Original(name);
                    PlainFile(p);
                    if (entries.ContainsKey(name))
                    {
                        VerifyBackup(name, entries[name]);
                        if (File.Exists(p) && Hash(p) != entries[name])
                            throw new IOException("原脚本已更新，与备份冲突，请先处理：" + name);
                    }
                    if (!File.Exists(p)) continue;
                    string hash = Hash(p), copy = CopyPath(name, hash);
                    PlainFile(copy);
                    if (!File.Exists(copy))
                    {
                        using (var source = File.OpenRead(p))
                        using (var dest = new FileStream(copy, FileMode.CreateNew, FileAccess.Write, FileShare.None))
                        { source.CopyTo(dest); dest.Flush(true); }
                    }
                    VerifyBackup(name, hash);
                    entries[name] = hash;
                    remove.Add(name);
                }
                Save(entries);
                try
                {
                    foreach (string name in remove)
                    {
                        if (running()) throw new IOException("检测到 Capture 已启动，操作中止。");
                        if (Hash(Original(name)) != entries[name]) throw new IOException("操作期间脚本已改变：" + name);
                        File.Delete(Original(name));
                    }
                }
                catch (Exception failure)
                {
                    try
                    {
                        foreach (string name in remove)
                            if (!File.Exists(Original(name))) File.Copy(CopyPath(name, entries[name]), Original(name), false);
                        Save(before);
                    }
                    catch (Exception rollback)
                    { throw new IOException("停用失败，自动回滚未完成。请使用恢复按钮。\n" + failure.Message + "\n" + rollback.Message); }
                    throw;
                }
                return remove.Count;
            }
        }
        public int Restore()
        {
            using (Begin())
            {
                var entries = Load();
                foreach (var e in entries)
                {
                    VerifyBackup(e.Key, e.Value);
                    PlainFile(Original(e.Key));
                    if (File.Exists(Original(e.Key)) && Hash(Original(e.Key)) != e.Value)
                        throw new IOException("当前脚本已更新，恢复不会覆盖它：" + e.Key + "\n请保留当前文件与备份，再人工比较。");
                }
                int count = 0;
                foreach (var e in entries.ToArray())
                {
                    if (running()) throw new IOException("检测到 Capture 已启动，恢复暂停；关闭后可继续恢复。");
                    string p = Original(e.Key);
                    if (!File.Exists(p))
                    {
                        // Stage outside capAutoLoad so a crash cannot leave a partial startup script.
                        string stage = Path.Combine(Backup, Guid.NewGuid().ToString("N") + ".restore");
                        File.Copy(CopyPath(e.Key, e.Value), stage, false);
                        if (Hash(stage) != e.Value) throw new IOException("恢复副本校验失败：" + e.Key);
                        File.Move(stage, p);
                        count++;
                    }
                    entries.Remove(e.Key);
                    Save(entries);
                }
                return count;
            }
        }
    }

    public sealed class MainForm : Form
    {
        readonly TextBox path = new TextBox();
        readonly ListView features = new ListView();
        readonly TextBox detail = new TextBox();
        readonly Label status = new Label();
        Engine engine;
        public MainForm()
        {
            Text = "OrCAD 启动优化工具"; Font = new Font("Microsoft YaHei UI", 9F);
            Size = new Size(1040, 710); MinimumSize = new Size(880, 620);
            StartPosition = FormStartPosition.CenterScreen;
            var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(18), ColumnCount = 1, RowCount = 7 };
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 45));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 52));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 48));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 46));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
            Controls.Add(layout);
            layout.Controls.Add(new Label { Text = "减少不常用的启动功能 · 勾选表示准备停用 · 应用后下次启动生效", Dock = DockStyle.Fill, AutoSize = false }, 0, 0);
            var paths = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 3 };
            paths.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            paths.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 95));
            paths.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 95));
            path.Dock = DockStyle.Fill; paths.Controls.Add(path);
            paths.Controls.Add(Button("选择目录", delegate {
                using (var d = new FolderBrowserDialog { Description = "选择 SPB 安装目录或 capAutoLoad 目录" })
                    if (d.ShowDialog(this) == DialogResult.OK) { path.Text = d.SelectedPath; Scan(); }
            }));
            paths.Controls.Add(Button("重新扫描", delegate { Scan(); })); layout.Controls.Add(paths, 0, 1);
            path.TextChanged += delegate { engine = null; status.Text = "目录已改变，请重新扫描。"; };
            var presets = new FlowLayoutPanel { Dock = DockStyle.Fill };
            presets.Controls.Add(Button("保守方案", delegate { Preset(1); }));
            presets.Controls.Add(Button("不用建模助手", delegate { Preset(2); }));
            presets.Controls.Add(Button("清空勾选", delegate { Preset(0); }));
            presets.Controls.Add(new Label { Text = "云元件库和欢迎页按需手动勾选", AutoSize = true, Padding = new Padding(10, 9, 0, 0) });
            layout.Controls.Add(presets, 0, 2);
            features.Dock = DockStyle.Fill; features.View = View.Details; features.CheckBoxes = true;
            features.FullRowSelect = true; features.HideSelection = false; features.MultiSelect = false;
            features.Columns.Add("准备停用的功能", 200); features.Columns.Add("当前状态", 150); features.Columns.Add("停用影响", 590);
            features.SelectedIndexChanged += delegate {
                if (features.SelectedItems.Count > 0) ShowFeature((Feature)features.SelectedItems[0].Tag);
            };
            layout.Controls.Add(features, 0, 3);
            detail.Dock = DockStyle.Fill; detail.Multiline = true; detail.ReadOnly = true;
            detail.ScrollBars = ScrollBars.Vertical; detail.BackColor = Color.White;
            layout.Controls.Add(detail, 0, 4);
            var actions = new FlowLayoutPanel { Dock = DockStyle.Fill };
            actions.Controls.Add(Button("备份并停用所选", delegate { Apply(); }));
            actions.Controls.Add(Button("恢复本工具停用项", delegate { Restore(); }));
            actions.Controls.Add(Button("查看全部启动脚本", delegate { Inventory(); }));
            actions.Controls.Add(Button("导出扫描报告", delegate { Export(); }));
            layout.Controls.Add(actions, 0, 5); status.Dock = DockStyle.Fill; layout.Controls.Add(status, 0, 6);
            Shown += delegate { path.Text = Detect(); if (path.Text.Length > 0) Scan(); else status.Text = "请选择 OrCAD 安装目录。"; };
        }
        static Button Button(string text, EventHandler action)
        { var b = new Button { Text = text, AutoSize = true, Height = 32, Padding = new Padding(6, 0, 6, 0) }; b.Click += action; return b; }
        static string Detect()
        {
            var candidates = new List<string>();
            foreach (string key in new[] { "CDS_INST_DIR", "CDSROOT" })
                if (!String.IsNullOrEmpty(Environment.GetEnvironmentVariable(key))) candidates.Add(Environment.GetEnvironmentVariable(key));
            candidates.Add(@"C:\orcad\Cadence\SPB_17.4");
            foreach (string baseDir in new[] { @"C:\Cadence", @"C:\orcad\Cadence", @"D:\Cadence" })
                if (Directory.Exists(baseDir)) candidates.AddRange(Directory.GetDirectories(baseDir, "SPB*").OrderByDescending(s => s));
            foreach (string candidate in candidates) { try { return Engine.Normalize(candidate); } catch { } }
            return "";
        }
        void Error(Exception e)
        {
            string text = e is UnauthorizedAccessException ? "没有写入权限。请关闭工具，右键以管理员身份运行，再重新扫描和选择。\n" + e.Message : e.Message;
            MessageBox.Show(this, text, "操作未完成", MessageBoxButtons.OK, MessageBoxIcon.Warning);
        }
        bool Ready() { if (engine != null) return true; MessageBox.Show(this, "请先重新扫描目录。"); return false; }
        void Scan()
        {
            engine = null; features.Items.Clear(); detail.Clear();
            try
            {
                var scanned = new Engine(path.Text); var pending = scanned.Pending(); var active = scanned.Active();
                engine = scanned;
                foreach (var f in Catalog.Features)
                {
                    int enabled = f.Files.Count(n => active.Contains(n, StringComparer.OrdinalIgnoreCase));
                    int disabled = f.Files.Count(n => pending.Contains(n, StringComparer.OrdinalIgnoreCase) && !active.Contains(n, StringComparer.OrdinalIgnoreCase));
                    var item = new ListViewItem(f.Name) { Tag = f };
                    item.SubItems.Add(enabled + " 启用 / " + disabled + " 停用"); item.SubItems.Add(f.Impact);
                    features.Items.Add(item);
                }
                Preset(1); Inventory();
                status.Text = String.Format("扫描到 {0} 个启动 Tcl；{1} 项恢复记录。{2}", active.Length, pending.Length,
                    Engine.CaptureRunning() ? "Capture 正在运行，关闭后才可应用。" : "可以应用。建议先记录一次原始启动耗时。");
            }
            catch (Exception e) { engine = null; status.Text = "扫描失败。"; Error(e); }
        }
        void Preset(int mode)
        {
            foreach (ListViewItem item in features.Items)
            { var f = (Feature)item.Tag; item.Checked = mode != 0 && (f.Mild || (mode == 2 && f.Name == "PSpice 建模助手")); }
        }
        void ShowFeature(Feature f)
        { detail.Text = f.Name + "\r\n" + f.Impact + "\r\n\r\n涉及脚本：\r\n" + String.Join("\r\n", f.Files); }
        string Report()
        {
            var active = engine.Active(); var pending = engine.Pending();
            return "OrCAD 启动项扫描 " + DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + "\r\n目录：" + engine.Root +
                "\r\n备份：" + engine.Backup + "\r\n\r\n加载项数量不等于启动耗时，原日志没有各脚本耗时数据。\r\n" +
                "只管理列出的可选功能；DRC、保存、PCB 联动、仿真核心及未知/自定义脚本保持启用。\r\n" +
                "备份移出 capAutoLoad；恢复前会校验 SHA-256，遇到更新后的同名脚本不会覆盖。\r\n\r\n" +
                "当前启动脚本（" + active.Length + "）：\r\n" + String.Join("\r\n", active) +
                "\r\n\r\n本工具恢复记录（" + pending.Length + "）：\r\n" + String.Join("\r\n", pending);
        }
        void Inventory() { if (!Ready()) return; try { detail.Text = Report(); } catch (Exception e) { Error(e); } }
        void Export()
        {
            if (!Ready()) return;
            using (var d = new SaveFileDialog { Filter = "文本报告|*.txt", FileName = "OrCAD启动项扫描.txt" })
                if (d.ShowDialog(this) == DialogResult.OK)
                    try { File.WriteAllText(d.FileName, Report(), new UTF8Encoding(true)); } catch (Exception e) { Error(e); }
        }
        void Apply()
        {
            if (!Ready()) return;
            var selected = features.CheckedItems.Cast<ListViewItem>().Select(i => (Feature)i.Tag).ToArray();
            if (selected.Length == 0) { MessageBox.Show(this, "请先勾选要停用的功能。"); return; }
            string summary = String.Join("\r\n\r\n", selected.Select(f => f.Name + "：" + f.Impact));
            if (MessageBox.Show(this, "将备份并停用以下功能，下次启动生效：\r\n\r\n" + summary, "确认停用", MessageBoxButtons.OKCancel, MessageBoxIcon.Information) != DialogResult.OK) return;
            try { int n = engine.Disable(selected.SelectMany(f => f.Files)); Scan(); MessageBox.Show(this, "已备份并停用 " + n + " 个脚本。\r\n下次启动 Capture 生效，可随时使用恢复按钮。"); }
            catch (Exception e) { Error(e); Scan(); }
        }
        void Restore()
        {
            if (!Ready()) return;
            try { int n = engine.Restore(); Scan(); MessageBox.Show(this, "已恢复 " + n + " 个脚本，下次启动 Capture 生效。"); }
            catch (Exception e) { Error(e); Scan(); }
        }
    }
    static class Program
    {
        [STAThread] static void Main()
        {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            Application.Run(new MainForm());
        }
    }
}
