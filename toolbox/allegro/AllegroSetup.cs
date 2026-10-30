using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;

namespace XiaokaiSetup
{
    static class AllegroSkills
    {
        public static IEnumerable<string> Names
        {
            get
            {
                yield return "allegro.install.ps1";
                foreach (string file in XiaokaiAllegro.SkillFiles.Names) yield return "allegro." + file;
            }
        }

        public static long TotalBytes()
        {
            long total = 0;
            foreach (string name in Names) total += Payload.Size(name);
            return total;
        }

        // Use the same byte-preserving, backup/rollback installer as standalone deployment.
        static string RunTarget(string home, bool uninstall)
        {
            string stage = Path.Combine(Path.GetTempPath(), "xk-allegro-stage-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(Path.Combine(stage, "skill"));
            try
            {
                string script = Path.Combine(stage, "install.ps1");
                Payload.Extract("allegro.install.ps1", script, null);
                if (!uninstall)
                    foreach (string name in XiaokaiAllegro.SkillFiles.Names)
                        Payload.Extract("allegro." + name, Path.Combine(stage, "skill", name), null);
                var start = new ProcessStartInfo(Path.Combine(Environment.GetFolderPath(
                    Environment.SpecialFolder.System), @"WindowsPowerShell\v1.0\powershell.exe"));
                start.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File \"" + script
                    + "\" -HomeDirectory \"" + home + "\"" + (uninstall ? " -Uninstall" : "");
                start.UseShellExecute = false;
                start.CreateNoWindow = true;
                start.RedirectStandardOutput = true;
                start.RedirectStandardError = true;
                using (Process process = Process.Start(start))
                {
                    string output = process.StandardOutput.ReadToEnd();
                    string error = process.StandardError.ReadToEnd();
                    process.WaitForExit();
                    if (process.ExitCode != 0) throw new IOException("Allegro SKILL 安装失败：" + output + error);
                    return output;
                }
            }
            finally
            {
                // The absolute target is the fresh directory created above, under TEMP.
                if (Path.GetDirectoryName(stage).Equals(Path.GetTempPath().TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)
                    && Path.GetFileName(stage).StartsWith("xk-allegro-stage-", StringComparison.Ordinal))
                    Directory.Delete(stage, true);
            }
        }

        public static bool Apply(IReport report, bool uninstall)
        {
            try
            {
                List<string> homes = XiaokaiAllegro.SkillFiles.FindHomes(null);
                if (homes.Count == 0)
                {
                    report.Note("未找到 Allegro 用户目录，跳过 SKILL 安装；安装 Allegro 后重新运行本安装包即可。");
                    return true;
                }
                foreach (string home in homes)
                {
                    if (uninstall && !File.Exists(Path.Combine(home, "pcbenv", "allegro.ilinit"))) continue;
                    report.Step((uninstall ? "移除" : "安装") + " Allegro SKILL：" + home);
                    report.Note(RunTarget(home, uninstall).Trim());
                }
                report.Note(uninstall ? "已移除 Allegro 自动加载入口，脚本及备份保留。请重启 Allegro。"
                    : "Allegro SKILL 已默认安装；重启 Allegro 后按 Alt+K 使用。");
                return true;
            }
            catch (Exception ex) { report.Fail(ex.Message); return false; }
        }

        public static string TestLifecycle()
        {
            string home = Path.Combine(Path.GetTempPath(), "xk-allegro-lifecycle-" + Guid.NewGuid().ToString("N"));
            string pcb = Path.Combine(home, "pcbenv");
            Directory.CreateDirectory(pcb);
            byte[] original = Encoding.GetEncoding(936).GetBytes("; 原有中文配置\r\nprintln(\"user init\")\r\n");
            string init = Path.Combine(pcb, "allegro.ilinit");
            try
            {
                File.WriteAllBytes(init, original);
                File.WriteAllText(Path.Combine(pcb, "Quick_ColorS.il"), "; existing user script");
                RunTarget(home, false);
                foreach (string file in XiaokaiAllegro.SkillFiles.Names)
                    if (!File.Exists(Path.Combine(pcb, file))) return "missing installed " + file;
                if (!XiaokaiAllegro.SkillFiles.Enabled(pcb, XiaokaiAllegro.SkillFiles.Names)) return "startup missing";
                string first = Convert.ToBase64String(File.ReadAllBytes(init));
                RunTarget(home, false);
                if (first != Convert.ToBase64String(File.ReadAllBytes(init))) return "upgrade duplicates or changes startup";
                if (Directory.GetFiles(Path.Combine(pcb, "xiaokai-allegro-backup"), "Quick_ColorS.il", SearchOption.AllDirectories).Length < 1)
                    return "original script not backed up";
                RunTarget(home, true);
                if (Convert.ToBase64String(original) != Convert.ToBase64String(File.ReadAllBytes(init)))
                    return "uninstall changed original bytes";
                if (!File.Exists(Path.Combine(pcb, "Quick_ColorS.il"))) return "uninstall deleted script";
                return null;
            }
            catch (Exception ex) { return ex.ToString(); }
            finally
            {
                if (Path.GetDirectoryName(home).Equals(Path.GetTempPath().TrimEnd('\\'), StringComparison.OrdinalIgnoreCase)
                    && Path.GetFileName(home).StartsWith("xk-allegro-lifecycle-", StringComparison.Ordinal))
                    Directory.Delete(home, true);
            }
        }
    }
}
