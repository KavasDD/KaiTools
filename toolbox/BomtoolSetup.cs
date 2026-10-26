// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.Collections.Generic;
using System.IO;
using System.Reflection;
using System.Security.Cryptography;
using System.Windows.Forms;

// Embedded payload: a toolbox component cannot lose its companion Tcl file.
class BomtoolSetup
{
    const string Script = "bomtoolMenu.tcl";
    static string Target(string root)
    {
        return Path.Combine(root, "cdssetup", "OrCAD_Capture", "tclscripts", "capAutoLoad");
    }
    static List<string> FindTargets()
    {
        var roots = new List<string>();
        foreach (string key in new[] { "BOMTOOL_SPB", "HOME", "CDS_SITE" })
        {
            string p = Environment.GetEnvironmentVariable(key);
            if (!String.IsNullOrEmpty(p)) roots.Add(p);
        }
        roots.Add(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile));
        roots.AddRange(new[] {
            "C:\\orcad\\Cadence\\SPB_Data", "D:\\orcad\\Cadence\\SPB_Data",
            "E:\\orcad\\Cadence\\SPB_Data", "C:\\Cadence\\SPB_Data",
            "D:\\Cadence\\SPB_Data", "E:\\Cadence\\SPB_Data"
        });
        foreach (string key in new[] { "CDS_INST_DIR", "SPB_17_4", "CDSROOT", "CDS_ROOT" })
        {
            string p = Environment.GetEnvironmentVariable(key);
            if (String.IsNullOrEmpty(p)) continue;
            roots.Add(Path.Combine(p, "SPB_Data"));
            DirectoryInfo parent = Directory.GetParent(p);
            if (parent != null) roots.Add(Path.Combine(parent.FullName, "SPB_Data"));
        }
        foreach (string drive in new[] { "C:\\", "D:\\", "E:\\", "F:\\" })
        {
            roots.Add(Path.Combine(drive, "OrCAD", "Cadence", "SPB_Data"));
            roots.Add(Path.Combine(drive, "Cadence", "SPB_Data"));
        }
        var targets = new List<string>();
        foreach (string root in roots)
        {
            if (!Directory.Exists(Path.Combine(root, "cdssetup", "OrCAD_Capture"))) continue;
            string path = Path.GetFullPath(Target(root));
            if (!targets.Exists(delegate(string t) { return String.Equals(t, path, StringComparison.OrdinalIgnoreCase); })) targets.Add(path);
        }
        return targets;
    }
    static byte[] Payload()
    {
        using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream(Script))
        {
            if (stream == null) throw new InvalidOperationException("安装包缺少BOM脚本。");
            using (var ms = new MemoryStream()) { stream.CopyTo(ms); return ms.ToArray(); }
        }
    }
    static string Hash(byte[] data)
    {
        using (var hash = SHA256.Create()) { return BitConverter.ToString(hash.ComputeHash(data)).Replace("-", ""); }
    }
    static string Apply(string target, byte[] payload, bool uninstall)
    {
        target = Path.GetFullPath(target);
        string dest = Path.Combine(target, Script);
        if (uninstall)
        {
            if (File.Exists(dest)) File.Move(dest, dest + ".removed-" + DateTime.Now.ToString("yyyyMMddHHmmssfff"));
            return target;
        }
        Directory.CreateDirectory(target);
        string expected = Hash(payload);
        if (File.Exists(dest) && Hash(File.ReadAllBytes(dest)) == expected) return target;
        string backup = dest + ".bak-" + DateTime.Now.ToString("yyyyMMddHHmmssfff");
        string staged = dest + "." + Guid.NewGuid().ToString("N") + ".tmp";
        bool hadOld = File.Exists(dest);
        try
        {
            File.WriteAllBytes(staged, payload);
            if (Hash(File.ReadAllBytes(staged)) != expected) throw new IOException("脚本校验失败。");
            if (hadOld) File.Replace(staged, dest, backup);
            else File.Move(staged, dest);
            if (Hash(File.ReadAllBytes(dest)) != expected)
            {
                if (hadOld && File.Exists(backup)) File.Copy(backup, dest, true);
                else File.Delete(dest);
                throw new IOException("安装后校验失败，已回退。");
            }
        }
        finally { if (File.Exists(staged)) File.Delete(staged); }
        return target;
    }
    [STAThread]
    static int Main(string[] args)
    {
        bool quiet = false, uninstall = false; string explicitTarget = null;
        try
        {
            foreach (string arg in args)
            {
                if (arg.Equals("/quiet", StringComparison.OrdinalIgnoreCase)) quiet = true;
                else if (arg.Equals("/uninstall", StringComparison.OrdinalIgnoreCase)) uninstall = true;
                else if (arg.StartsWith("/target=", StringComparison.OrdinalIgnoreCase)) explicitTarget = arg.Substring(8);
                else throw new ArgumentException("未知参数：" + arg);
            }
            var targets = explicitTarget == null ? FindTargets() : new List<string> { explicitTarget };
            if (targets.Count == 0 && !quiet)
            {
                using (var picker = new FolderBrowserDialog())
                {
                    picker.Description = "未自动找到Capture配置目录，请选择SPB_Data目录";
                    if (picker.ShowDialog() != DialogResult.OK) return 1;
                    if (!Directory.Exists(Path.Combine(picker.SelectedPath, "cdssetup", "OrCAD_Capture"))) throw new IOException("请选择含cdssetup/OrCAD_Capture的SPB_Data目录。");
                    targets.Add(Target(picker.SelectedPath));
                }
            }
            if (targets.Count == 0) throw new IOException("未找到Capture配置目录，可用 /target= 指定capAutoLoad目录。");
            byte[] payload = Payload();
            var results = new List<string>(); var failures = new List<string>();
            foreach (string target in targets)
            {
                try { results.Add(Apply(target, payload, uninstall)); }
                catch (Exception ex) { failures.Add(target + "：" + ex.Message); }
            }
            string message = (uninstall ? "已移除自动加载入口（脚本已备份）。" : "BOM整理工具安装完成。") +
                "\r\n" + String.Join("\r\n", results.ToArray()) +
                "\r\n\r\n请重启Capture。菜单：Accessories → BOM整理工具 → 打开BOM整理工具。";
            if (failures.Count > 0) message += "\r\n未完成的目录：\r\n" + String.Join("\r\n", failures.ToArray());
            File.WriteAllText(Path.Combine(Path.GetTempPath(), "bomtool-install.log"), message);
            if (!quiet) MessageBox.Show(message, "BOM整理工具", MessageBoxButtons.OK, failures.Count > 0 ? MessageBoxIcon.Warning : MessageBoxIcon.Information);
            return failures.Count > 0 ? 1 : 0;
        }
        catch (Exception ex)
        {
            if (!quiet) MessageBox.Show(ex.Message, "BOM安装失败", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
