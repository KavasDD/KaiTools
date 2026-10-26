// SPDX-License-Identifier: GPL-3.0-only
// Real WinForms regression checks for transient sizes and minimize/restore.
using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

namespace CadenceToolbox
{
    static class LayoutTest
    {
        static int sChecks;

        static T Field<T>(MainForm form, string name)
        {
            return (T)typeof(MainForm).GetField(name,
                BindingFlags.Instance | BindingFlags.NonPublic).GetValue(form);
        }

        static void Check(bool condition, string name)
        {
            if (!condition) throw new Exception(name);
            sChecks++;
        }

        static void ResizeContent(MainForm form)
        {
            typeof(MainForm).GetMethod("SizeContent",
                BindingFlags.Instance | BindingFlags.NonPublic).Invoke(form, null);
        }

        static void CheckDistance(SplitContainer split)
        {
            if (split.Panel1Collapsed || split.Panel2Collapsed) return;
            Check(split.SplitterDistance >= split.Panel1MinSize
                && split.SplitterDistance <= split.ClientSize.Height
                    - split.Panel2MinSize - split.SplitterWidth,
                "Splitter remains within both panel limits");
        }

        [STAThread]
        static int Main()
        {
            try
            {
                Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Paths.Detect();
                Manifest.Load(Path.Combine(Paths.Toolbox, "tools.ini"));
                using (var form = new MainForm())
                {
                    form.ShowInTaskbar = false;
                    form.Opacity = 0;
                    form.Show();
                    Application.DoEvents();
                    var categories = Field<ListBox>(form, "mCats");
                    var split = Field<SplitContainer>(form, "mSplit");
                    foreach (Size size in new[] { new Size(1024, 598), new Size(820, 480), new Size(1400, 800) })
                    {
                        form.ClientSize = size;
                        for (int round = 0; round < 3; round++)
                        {
                            for (int i = 0; i < categories.Items.Count; i++)
                            {
                                categories.SelectedIndex = i;
                                Application.DoEvents();
                                CheckDistance(split);
                                form.WindowState = FormWindowState.Minimized;
                                Application.DoEvents();
                                ResizeContent(form);
                                form.WindowState = FormWindowState.Normal;
                                Application.DoEvents();
                                Check(form.ClientSize == size, "Restore preserves window size");
                                CheckDistance(split);
                            }
                        }
                    }

                    categories.SelectedItem = "OrCAD 工具";
                    Application.DoEvents();
                    split.Dock = DockStyle.None;
                    // Height zero gives the reported upper bound: 0 - 74 - 6 = -80.
                    foreach (int height in new[] { 0, 50, 100, 169, 170, 300 })
                    {
                        split.Height = height;
                        ResizeContent(form);
                        Check(true, "Transient height " + height + " does not throw");
                    }
                    split.Dock = DockStyle.Fill;
                    form.PerformLayout();
                    Application.DoEvents();
                    CheckDistance(split);

                    int draggedDistance = split.Panel1MinSize + 20;
                    split.SplitterDistance = draggedDistance;
                    typeof(MainForm).GetField("mUserDragged",
                        BindingFlags.Instance | BindingFlags.NonPublic).SetValue(form, true);
                    ResizeContent(form);
                    Check(split.SplitterDistance == draggedDistance, "Manual divider position is preserved");
                    form.WindowState = FormWindowState.Minimized;
                    Application.DoEvents();
                    form.WindowState = FormWindowState.Normal;
                    Application.DoEvents();
                    Check(split.SplitterDistance == draggedDistance, "Restore preserves manual divider position");
                    form.Close();
                }
                Console.WriteLine(sChecks + " layout regression checks passed.");
                return 0;
            }
            catch (Exception ex)
            {
                Console.WriteLine(ex);
                return 1;
            }
        }
    }
}
