// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

class NetlocatorSetup : Form
{
    readonly bool uninstall;

    public NetlocatorSetup(bool remove)
    {
        uninstall = remove;
        Text = "netlocator";
        ClientSize = new System.Drawing.Size(420, 120);
        StartPosition = FormStartPosition.CenterScreen;
        FormBorderStyle = FormBorderStyle.FixedDialog;
        MaximizeBox = false; MinimizeBox = false;
        var msg = new Label { Dock = DockStyle.Fill, TextAlign = System.Drawing.ContentAlignment.MiddleCenter,
            Text = uninstall ? "正在查找并卸载 netlocator..." : "正在自动查找 OrCAD Capture 并安装 netlocator..." };
        Controls.Add(msg);
        Shown += delegate { if (uninstall) Uninstall(msg); else Install(msg); };
    }

    static string FindSpbData()
    {
        var roots = new List<string>();
        foreach (string v in new[] { "HOME", "CDS_INST_DIR", "SPB_17_4", "SPB_16_6", "CDSROOT", "CDS_ROOT" })
        {
            string p = Environment.GetEnvironmentVariable(v);
            if (!String.IsNullOrEmpty(p)) roots.Add(p);
        }
        foreach (string p in new[] {
            "C:\\orcad\\Cadence\\SPB_Data", "D:\\orcad\\Cadence\\SPB_Data",
            "E:\\orcad\\Cadence\\SPB_Data", "C:\\Cadence\\SPB_Data",
            "D:\\Cadence\\SPB_Data", "E:\\Cadence\\SPB_Data"
        }) roots.Add(p);
        foreach (string drive in new[] { "C:\\", "D:\\", "E:\\", "F:\\" }) roots.Add(drive);
        foreach (string root in roots)
        {
            string hit = Search(root, 4);
            if (hit != null) return hit;
        }
        return null;
    }

    static List<string> FindTargets(bool remove)
    {
        var targets = new List<string>();
        string detected = FindSpbData();
        if (!String.IsNullOrEmpty(detected)) targets.Add(detected);

        string profile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);
        string userTarget = Path.Combine(profile, "cdssetup", "OrCAD_Capture", "tclscripts", "capAutoLoad");
        string script = Path.Combine(userTarget, "netlocatorMenu.tcl");
        if ((remove && File.Exists(script)) || Directory.Exists(Path.Combine(profile, "cdssetup")))
            targets.Add(userTarget);

        var unique = new List<string>();
        foreach (string target in targets)
        {
            string full = Path.GetFullPath(target);
            if (!unique.Exists(delegate(string item) {
                return String.Equals(item, full, StringComparison.OrdinalIgnoreCase);
            })) unique.Add(full);
        }
        return unique;
    }

    static string Search(string root, int depth)
    {
        if (depth < 0 || String.IsNullOrEmpty(root)) return null;
        // Support both layouts used by 16.6/17.x:
        //   <Cadence>\SPB_Data\...
        //   <Cadence>\SPB_16.6\SPB_Data\...
        string own = Path.Combine(root, "cdssetup", "OrCAD_Capture", "tclscripts", "capAutoLoad");
        if (Directory.Exists(Path.Combine(root, "cdssetup")) &&
            root.EndsWith("SPB_Data", StringComparison.OrdinalIgnoreCase))
            return own;

        string direct = Path.Combine(root, "SPB_Data", "cdssetup", "OrCAD_Capture", "tclscripts", "capAutoLoad");
        if (Directory.Exists(Path.Combine(root, "SPB_Data", "cdssetup"))) return direct;

        string cap = Path.Combine(root, "tools", "bin", "Capture.exe");
        string cap2 = Path.Combine(root, "tools", "capture", "Capture.exe");
        if (File.Exists(cap) || File.Exists(cap2))
        {
            DirectoryInfo parentInfo = Directory.GetParent(root);
            if (parentInfo != null)
            {
                string parent = parentInfo.FullName;
                string candidate = Path.Combine(parent, "SPB_Data", "cdssetup", "OrCAD_Capture", "tclscripts", "capAutoLoad");
                if (Directory.Exists(Path.Combine(parent, "SPB_Data", "cdssetup"))) return candidate;
            }
        }
        string[] directories;
        try { directories = Directory.GetDirectories(root); }
        catch (UnauthorizedAccessException) { return null; }
        catch (IOException) { return null; }
        foreach (string directory in directories)
        {
            string hit = Search(directory, depth - 1);
            if (hit != null) return hit;
        }
        return null;
    }

    void Install(Label msg)
    {
        List<string> targets = FindTargets(false);
        if (targets.Count == 0)
        {
            msg.Text = "未找到 OrCAD Capture 的 SPB_Data。\n请确认已安装 OrCAD 16.6/17.x 后重试。";
            return;
        }
        try
        {
            byte[] script = ReadPayload();
            int copied = 0;
            foreach (string target in targets)
            {
                if (String.IsNullOrEmpty(target)) continue;
                Directory.CreateDirectory(target);
                File.WriteAllBytes(Path.Combine(target, "netlocatorMenu.tcl"), script);
                copied++;
            }
            msg.Text = "netlocator 已安装到 " + copied + " 个 Capture autoload 目录。\n请重启 OrCAD Capture。";
        }
        catch (Exception ex) { msg.Text = "安装失败:\n" + ex.Message; }
    }

    static byte[] ReadPayload()
    {
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("netlocatorMenu.tcl"))
        {
            if (stream == null) throw new InvalidOperationException("安装器缺少 netlocatorMenu.tcl。");
            using (var memory = new MemoryStream())
            {
                stream.CopyTo(memory);
                return memory.ToArray();
            }
        }
    }

    void Uninstall(Label msg)
    {
        try
        {
            List<string> targets = FindTargets(true);
            int removed = 0;
            foreach (string target in targets)
            {
                string script = Path.Combine(target, "netlocatorMenu.tcl");
                if (!File.Exists(script)) continue;
                File.Delete(script);
                removed++;
            }
            msg.Text = removed == 0
                ? "未找到 netlocator 插件，无需卸载。"
                : "netlocator 已从 " + removed + " 个 Capture autoload 目录移除。\n请重启 OrCAD Capture。";
        }
        catch (Exception ex) { msg.Text = "卸载失败:\n" + ex.Message; }
    }

    [STAThread]
    static void Main(string[] args)
    {
        bool remove = false;
        foreach (string arg in args)
        {
            if (arg.Equals("/uninstall", StringComparison.OrdinalIgnoreCase)) remove = true;
            else
            {
                MessageBox.Show("未知参数：" + arg, "netlocator", MessageBoxButtons.OK, MessageBoxIcon.Error);
                return;
            }
        }
        Application.EnableVisualStyles();
        Application.Run(new NetlocatorSetup(remove));
    }
}
