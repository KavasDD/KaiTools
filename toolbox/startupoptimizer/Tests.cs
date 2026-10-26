// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.IO;
using System.Linq;
using System.Windows.Forms;

namespace OrCadStartup
{
    static class Tests
    {
        static int checks;
        static void Check(bool ok, string message) { if (!ok) throw new Exception(message); checks++; }
        static void Fails(Action action, string message)
        { bool failed = false; try { action(); } catch (IOException) { failed = true; } Check(failed, message); }
        [STAThread] static int Main(string[] args)
        {
            string sandbox = Path.Combine(Path.GetTempPath(), "orcad-startup-tests-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(sandbox);
            try
            {
                string root = Path.Combine(sandbox, "capAutoLoad"); Directory.CreateDirectory(root);
                string a = "capAutoDemoBrowser.tcl", b = "caplearningresources.tcl";
                byte[] content = { 0xEF, 0xBB, 0xBF, 0, 13, 10, 255, 90 };
                File.WriteAllBytes(Path.Combine(root, a), content); File.WriteAllText(Path.Combine(root, b), "puts learning");
                File.WriteAllText(Path.Combine(root, "capCustomDRCInit.tcl"), "protected");
                File.WriteAllText(Path.Combine(root, "bomtoolMenu.tcl"), "user plugin");
                var e = new Engine(root, () => false);
                Check(Catalog.Features.Last().Files.Length == 27, "modeling catalog size");
                Check(e.Disable(new[] { a, b, a }) == 2, "disable deduplicates");
                Check(!File.Exists(Path.Combine(root, a)) && e.Pending().Length == 2, "disabled persisted");
                Check(e.Active().Length == 2, "only protected and custom remain");
                Check(!e.Backup.StartsWith(root + Path.DirectorySeparatorChar), "backup outside autoload");
                Check(e.Disable(new[] { a, b }) == 0, "repeated disable no-op");
                Check(new Engine(root, () => false).Restore() == 2, "restore across instances");
                Check(File.ReadAllBytes(Path.Combine(root, a)).SequenceEqual(content), "byte-exact restore");
                Check(e.Pending().Length == 0 && e.Restore() == 0, "restore idempotent");
                Fails(() => e.Disable(new[] { "capCustomDRCInit.tcl" }), "core rejected");
                Fails(() => e.Disable(new[] { "..\\capAutoDemoBrowser.tcl" }), "traversal rejected");
                Fails(() => new Engine(root, () => true).Disable(new[] { a }), "running Capture rejected");
                Check(File.Exists(Path.Combine(root, a)), "running guard preserves source");

                e.Disable(new[] { a, b });
                File.WriteAllText(Path.Combine(root, b), "updated by vendor");
                Fails(() => e.Restore(), "updated original rejected");
                Check(!File.Exists(Path.Combine(root, a)), "restore preflight prevents partial restore on conflict");
                Check(File.ReadAllText(Path.Combine(root, b)) == "updated by vendor", "vendor update preserved");
                File.Delete(Path.Combine(root, b)); e.Restore();

                e.Disable(new[] { a });
                string backup = Directory.GetFiles(e.Backup, a + ".*.bak").Single();
                File.WriteAllText(backup, "corrupt");
                Fails(() => e.Restore(), "corrupt backup rejected");
                Check(!File.Exists(Path.Combine(root, a)), "corrupt data never restored");
                File.WriteAllBytes(backup, content); e.Restore();

                int calls = 0;
                var interrupted = new Engine(root, () => ++calls >= 3);
                Fails(() => interrupted.Disable(new[] { a, b }), "interrupt after first deletion");
                Check(File.Exists(Path.Combine(root, a)) && File.Exists(Path.Combine(root, b)), "batch rolled back");
                Check(e.Pending().Length == 0, "rollback clears new records");
                Check(File.ReadAllBytes(Path.Combine(root, a)).SequenceEqual(content), "rollback byte-exact");

                e.Disable(new[] { a, b }); calls = 0;
                Fails(() => new Engine(root, () => ++calls >= 3).Restore(), "interrupted restore");
                Check(e.Pending().Length == 1, "partial restore journals remaining item");
                Check(e.Restore() == 1, "partial restore resumes");

                // Simulate a crash after manifest save but before source removal.
                e.Disable(new[] { a }); File.WriteAllBytes(Path.Combine(root, a), content);
                Check(e.Restore() == 0 && e.Pending().Length == 0, "prepared operation reconciles");
                File.WriteAllText(Path.Combine(root, a), "new version");
                Check(e.Disable(new[] { a }) == 1 && e.Restore() == 1, "new version after restore gets fresh backup");
                Check(File.ReadAllText(Path.Combine(root, a)) == "new version", "fresh version restored");
                Check(File.ReadAllText(Path.Combine(root, "capCustomDRCInit.tcl")) == "protected", "DRC untouched");
                Check(File.ReadAllText(Path.Combine(root, "bomtoolMenu.tcl")) == "user plugin", "custom untouched");

                string manifest = Path.Combine(e.Backup, "manifest.xml");
                string originalManifest = File.ReadAllText(manifest);
                File.WriteAllText(manifest, "<!DOCTYPE backup [<!ENTITY x SYSTEM 'file:///C:/Windows/win.ini'>]><backup>&x;</backup>");
                bool xmlBlocked = false; try { e.Pending(); } catch (System.Xml.XmlException) { xmlBlocked = true; }
                Check(xmlBlocked, "external entities prohibited"); File.WriteAllText(manifest, originalManifest);
                using (var held = new FileStream(Path.Combine(e.Backup, "operation.lock"), FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                    Fails(() => e.Disable(new[] { a }), "concurrent writer rejected");

                Application.EnableVisualStyles();
                using (var form = new MainForm())
                {
                    form.CreateControl(); Check(form.Controls.Count > 0, "GUI constructs");
                    if (args.Length == 1)
                    {
                        form.Opacity = 0; form.ShowInTaskbar = false; form.Show(); Application.DoEvents();
                        using (var bitmap = new System.Drawing.Bitmap(form.Width, form.Height))
                        { form.DrawToBitmap(bitmap, new System.Drawing.Rectangle(0, 0, form.Width, form.Height)); bitmap.Save(args[0]); }
                        form.Close();
                    }
                }
                Console.WriteLine("PASS: " + checks + " checks; isolated fixtures only. Live OrCAD was not modified.");
                return 0;
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
            finally
            {
                // Only this test's freshly-created absolute directory can be removed.
                string full = Path.GetFullPath(sandbox);
                string temp = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
                if (full.StartsWith(temp, StringComparison.OrdinalIgnoreCase) && Path.GetFileName(full).StartsWith("orcad-startup-tests-"))
                    Directory.Delete(full, true);
            }
        }
    }
}
