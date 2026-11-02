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
                && split.SplitterDistance <= split.ClientSize.Width
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
                    foreach (Size size in new[] { new Size(1024, 620), new Size(960, 600), new Size(1400, 800) })
                    {
                        // A hosted desktop can be smaller than a requested test
                        // window. Windows clamps its restore bounds to that desktop.
                        Size border = new Size(form.Width - form.ClientSize.Width,
                            form.Height - form.ClientSize.Height);
                        Rectangle area = Screen.FromControl(form).WorkingArea;
                        Size client = new Size(Math.Min(size.Width, area.Width - border.Width),
                            Math.Min(size.Height, area.Height - border.Height));
                        form.Location = area.Location;
                        form.ClientSize = client;
                        Application.DoEvents();
                        Size expectedSize = form.ClientSize;
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
                                Check(form.ClientSize == expectedSize, "Restore preserves window size: expected "
                                    + expectedSize + ", actual " + form.ClientSize);
                                CheckDistance(split);
                            }
                        }
                    }

                    categories.SelectedItem = "Allegro 工具";
                    Application.DoEvents();
                    Check(Field<Label>(form, "mMineHeading").Text.Contains("Allegro SKILL"), "Allegro SKILL heading");
                    var grid = Field<IconGrid>(form, "mMineGrid");
                    foreach (ListViewItem item in grid.Items)
                    {
                        var plugin = item.Tag as CapturePluginStatus.PluginInfo;
                        if (plugin == null) continue;
                        Check(plugin.Host == "Allegro", "Allegro excludes Capture plugins");
                        item.Selected = true;
                        Application.DoEvents();
                        Check(Field<TextBox>(form, "mHelp").Text.Contains("安装位置：")
                            && Field<TextBox>(form, "mHelp").Text.Contains("Allegro 板图"), "SKILL selection shows path and usage");
                        using (var selectedShot = new Bitmap(form.Width, form.Height))
                        {
                            form.DrawToBitmap(selectedShot, new Rectangle(Point.Empty, selectedShot.Size));
                            selectedShot.Save(Path.Combine(Paths.Toolbox, "allegro-skill-description.png"));
                        }
                        item.Selected = false;
                    }
                    using (var shot = new Bitmap(form.Width, form.Height))
                    {
                        form.DrawToBitmap(shot, new Rectangle(Point.Empty, shot.Size));
                        shot.Save(Path.Combine(Paths.Toolbox, "allegro-skills.png"));
                    }
                    categories.SelectedItem = "OrCAD 工具";
                    Application.DoEvents();
                    split.Dock = DockStyle.None;
                    // Height zero gives the reported upper bound: 0 - 74 - 6 = -80.
                    foreach (int width in new[] { 0, 50, 100, 169, 170, 300 })
                    {
                        split.Width = width;
                        ResizeContent(form);
                        Check(true, "Transient width " + width + " does not throw");
                    }
                    split.Dock = DockStyle.Fill;
                    form.PerformLayout();
                    Application.DoEvents();
                    CheckDistance(split);

                    int draggedDistance = split.Panel1MinSize + 20;
                    typeof(MainForm).GetField("mUserDragged",
                        BindingFlags.Instance | BindingFlags.NonPublic).SetValue(form, true);
                    split.SplitterDistance = draggedDistance;
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
