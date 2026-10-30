// SPDX-License-Identifier: GPL-3.0-only
// Behavioral checks and screenshots for the shipped Windows controls.
using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Windows.Forms;
using XiaokaiAppearance;

namespace CadenceToolbox
{
    static class SkinChecks
    {
        static int checks;
        static string output;
        static void Check(bool condition, string name)
        { if (!condition) throw new Exception(name); checks++; }
        static void Shot(Form form, string name)
        {
            form.ShowInTaskbar = false; form.Show(); Application.DoEvents(); form.Refresh(); Application.DoEvents();
            using (var bitmap = new Bitmap(form.Width, form.Height)) {
                form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size));
                bitmap.Save(Path.Combine(output, name + ".png"));
            }
        }
        static T Field<T>(object form, string field)
        { return (T)form.GetType().GetField(field, BindingFlags.Instance | BindingFlags.NonPublic).GetValue(form); }
        static void ClickSection(IconGrid grid, string key)
        {
            foreach (ListViewItem row in grid.Items) {
                var section = row.Tag as PluginSection;
                if (section == null || section.Key != key) continue;
                Rectangle bounds = row.Bounds;
                typeof(Control).GetMethod("OnMouseClick", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(grid,
                    new object[] { new MouseEventArgs(MouseButtons.Left, 1, bounds.Left + 24, bounds.Top + bounds.Height / 2, 0) });
                Application.DoEvents(); return;
            }
            throw new Exception("Missing section " + key);
        }
        static int PluginRows(IconGrid grid)
        {
            int count = 0;
            foreach (ListViewItem row in grid.Items) if (row.Tag is CapturePluginStatus.PluginInfo) count++;
            return count;
        }
        static void CheckContinuousBackdrop(MainForm form)
        {
            var canvas = (Bitmap)form.BackgroundImage;
            Check(canvas != null && canvas.Size == form.ClientSize, "One canvas covers the window");
            foreach (string name in new[] { "mGrid", "mMineGrid", "mDsnGrid", "mBrdGrid" }) {
                var grid = Field<IconGrid>(form, name);
                if (!grid.Visible || grid.ClientSize.Width < 1 || grid.ClientSize.Height < 1) continue;
                var crop = grid.BackgroundImage as Bitmap;
                for (Control parent = grid.Parent; parent != null; parent = parent.Parent)
                    Check(parent.BackColor.A == 255, "Background containers avoid recursive transparent painting");
                Point origin = form.PointToClient(grid.PointToScreen(Point.Empty));
                Check(crop != null && crop.Size == grid.ClientSize, "Native grid crop matches size: " + name + " actual=" + (crop == null ? "null" : crop.Size.ToString()) + " expected=" + grid.ClientSize);
                foreach (int numerator in new[] { 1, 2, 3 }) {
                    int x = (crop.Width - 1) * numerator / 4, y = (crop.Height - 1) * numerator / 4;
                    Check(crop.GetPixel(x, y) == canvas.GetPixel(origin.X + x, origin.Y + y),
                        "Native grid shows the window pixel at its actual position: " + name);
                }
            }
        }
        [STAThread] static int Main(string[] args)
        {
            try {
                Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
                output = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "skin-validation");
                Directory.CreateDirectory(output);
                Check(Skins.Selected("toolbox").Id == "toolbox-b", "Fixed toolbox appearance");
                foreach (Skin skin in Skins.All) Check(Skins.Art(skin) != null, "Embedded artwork " + skin.Id);
                Check(Skins.Selected("orcad").Id == "orcad-a" && Skins.Selected("allegro").Id == "allegro-a", "Fixed companion appearance");
                Paths.Detect(); Manifest.Load(Path.Combine(Paths.Toolbox, "tools.ini"));
                using (var form = new MainForm()) {
                    var grid = Field<IconGrid>(form, "mGrid");
                    var categories = Field<ListBox>(form, "mCats");
                    form.Show(); Application.DoEvents();
                    Check(Field<Panel>(form, "mHelpPanel").Height == 36, "Details start collapsed");
                    foreach (string category in new[] { "OrCAD 工具", "Allegro 工具" }) {
                        categories.SelectedItem = category; Application.DoEvents();
                        var plugins = Field<IconGrid>(form, "mMineGrid");
                        Check(PluginRows(plugins) == 0, "Plugin categories initially collapsed: " + category);
                        var keys = new System.Collections.Generic.List<string>();
                        foreach (ListViewItem row in plugins.Items) {
                            var section = row.Tag as PluginSection;
                            if (section != null) keys.Add(section.Key);
                        }
                        Shot(form, category == "OrCAD 工具" ? "capture-groups-collapsed" : "allegro-groups-collapsed");
                        foreach (string key in keys) {
                            int before = PluginRows(plugins);
                            ClickSection(plugins, key);
                            Check(PluginRows(plugins) > before, "Click reveals tools in " + key);
                            typeof(Control).GetMethod("OnKeyDown", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(plugins,
                                new object[] { new KeyEventArgs(Keys.Left) });
                            Application.DoEvents();
                            Check(PluginRows(plugins) == before, "Left key collapses " + key);
                            typeof(Control).GetMethod("OnKeyDown", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(plugins,
                                new object[] { new KeyEventArgs(Keys.Right) });
                            Application.DoEvents();
                            Check(PluginRows(plugins) > before, "Right key expands " + key);
                        }
                        int expandedCount = PluginRows(plugins);
                        Shot(form, category == "OrCAD 工具" ? "capture-groups-expanded" : "allegro-groups-expanded");
                        categories.SelectedItem = "其他辅助工具"; Application.DoEvents();
                        categories.SelectedItem = category; Application.DoEvents();
                        Check(PluginRows(plugins) == expandedCount, "Category switch retains expansion: " + category);
                        foreach (string key in keys) ClickSection(plugins, key);
                        Check(PluginRows(plugins) == 0, "Click hides all tools: " + category);
                    }
                    foreach (string id in new[] { "toolbox-b" }) {
                        Check(Theme.Current.Id == id && grid.BackgroundImage != null, "Live skin and native background " + id);
                        foreach (Size size in new[] { new Size(960, 600), new Size(1200, 750) }) {
                            form.ClientSize = size; Application.DoEvents();
                            Image sharedCanvas = form.BackgroundImage;
                            for (int i = 0; i < categories.Items.Count; i++) {
                                categories.SelectedIndex = i; Application.DoEvents();
                                CheckContinuousBackdrop(form);
                                Check(ReferenceEquals(form.BackgroundImage, sharedCanvas), "Category switch reuses the rendered window canvas");
                                var recent = (string)categories.SelectedItem == "Allegro 工具" ? Field<IconGrid>(form, "mBrdGrid") : Field<IconGrid>(form, "mDsnGrid");
                                if (recent.Visible) Check(recent.View == View.Details && recent.Columns[0].Width < recent.ClientSize.Width, "Recent files stay in one bounded column");
                            }
                            Check(grid.BackgroundImage != null && grid.BackgroundImage.Width == grid.ClientSize.Width, "Artwork follows native grid resize");
                        }
                        categories.SelectedItem = "OrCAD 工具"; Shot(form, id);
                        CheckContinuousBackdrop(form);
                        var split = Field<SplitContainer>(form, "mSplit");
                        split.SplitterDistance = split.Panel1MinSize + 20;
                        Application.DoEvents(); CheckContinuousBackdrop(form);
                        Shot(form, id + "-divider");
                        categories.SelectedItem = "Allegro 工具"; Shot(form, id + "-allegro-page");
                        CheckContinuousBackdrop(form);
                        var skills = Field<IconGrid>(form, "mMineGrid");
                        Check(skills.View == View.Details && skills.CompactRows, "SKILL uses compact text rows");
                        if (skills.Items.Count > 0 && skills.Items[0].Tag is PluginSection)
                            ClickSection(skills, ((PluginSection)skills.Items[0].Tag).Key);
                        foreach (ListViewItem row in skills.Items) if (row.Tag is CapturePluginStatus.PluginInfo) {
                            row.Selected = true; Application.DoEvents();
                            Check(Field<Panel>(form, "mHelpPanel").Height == 146, "Selecting a tool expands details");
                            break;
                        }
                        Shot(form, id + "-details");
                        categories.SelectedItem = "OrCAD 工具"; Application.DoEvents();
                        Check(Field<Panel>(form, "mHelpPanel").Height == 36, "Changing categories collapses details");
                    }
                    foreach (string category in new[] { "Allegro 工具", "库与转换", "OrCAD 工具", "其他辅助工具", "库与转换" }) {
                        categories.SelectedItem = category; Application.DoEvents();
                        var icons = Field<IconGrid>(form, "mMineGrid");
                        if (category == "库与转换" || category == "其他辅助工具") {
                            Check(icons.View == View.LargeIcon && !icons.OwnerDraw && icons.LabelWrap, "Restore wrapped native icons after rows");
                            Size spacing = icons.Spacing;
                            foreach (ListViewItem item in icons.Items)
                                Check(item.GetBounds(ItemBoundsPortion.Label).Width <= spacing.Width, "Icon label stays inside its column");
                            Shot(form, category == "库与转换" ? "fixed-library" : "fixed-auxiliary");
                            CheckContinuousBackdrop(form);
                        }
                    }
                    var hint = Field<Label>(form, "mHint");
                    CaptionButton minimize = null, close = null;
                    foreach (Control control in hint.Controls) {
                        var button = control as CaptionButton;
                        if (button == null) continue;
                        if (button.AccessibleName == "关闭") close = button; else minimize = button;
                    }
                    Check(close != null && minimize != null && close.Size == minimize.Size, "Caption buttons have equal hit areas");
                    typeof(CaptionButton).GetMethod("OnMouseEnter", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(close, new object[] { EventArgs.Empty });
                    Shot(form, "caption-close-hover");
                    typeof(CaptionButton).GetMethod("OnMouseLeave", BindingFlags.Instance | BindingFlags.NonPublic).Invoke(close, new object[] { EventArgs.Empty });
                    minimize.PerformClick(); Application.DoEvents();
                    Check(form.WindowState == FormWindowState.Minimized, "Caption minimize action");
                    form.WindowState = FormWindowState.Normal; Application.DoEvents();
                    CheckContinuousBackdrop(form);
                    close.PerformClick(); Application.DoEvents();
                    Check(form.IsDisposed, "Caption close action");
                }
                Type type = typeof(AllegroHotkey).GetNestedType("ToolboxWindow", BindingFlags.NonPublic);
                foreach (string id in new[] { "allegro-a" }) {
                    using (var form = (SkinForm)Activator.CreateInstance(type, true)) {
                        var tree = Field<TreeView>(form, "tools");
                        Check(tree.Nodes.Count == 6 && tree.Nodes[0].Nodes.Count == 9, "All existing SKILL entries retained");
                        form.Show(); tree.Nodes[0].Expand(); tree.SelectedNode = tree.Nodes[0].Nodes[0]; Application.DoEvents();
                        Check(Field<Button>(form, "execute").Enabled, "Action enables execute");
                        Shot(form, id);
                        tree.SelectedNode = tree.Nodes[1]; Application.DoEvents();
                        Check(!Field<Button>(form, "execute").Enabled, "Empty group cannot execute");
                        tree.Nodes[0].Collapse(); tree.SelectedNode = tree.Nodes[0]; Application.DoEvents();
                        Check(!tree.Nodes[0].IsExpanded, "Selecting Allegro category does not force expansion");
                        Rectangle bounds = tree.Nodes[0].Bounds;
                        var click = new TreeNodeMouseClickEventArgs(tree.Nodes[0], MouseButtons.Left, 1, bounds.Left + 8, bounds.Top + bounds.Height / 2);
                        MethodInfo onClick = typeof(TreeView).GetMethod("OnNodeMouseClick", BindingFlags.Instance | BindingFlags.NonPublic);
                        onClick.Invoke(tree, new object[] { click }); Application.DoEvents();
                        Check(tree.Nodes[0].IsExpanded, "Allegro category label click expands");
                        onClick.Invoke(tree, new object[] { click }); Application.DoEvents();
                        Check(!tree.Nodes[0].IsExpanded, "Allegro category label click collapses");
                        MethodInfo onKey = typeof(Control).GetMethod("OnKeyDown", BindingFlags.Instance | BindingFlags.NonPublic);
                        onKey.Invoke(tree, new object[] { new KeyEventArgs(Keys.Enter) });
                        Check(tree.Nodes[0].IsExpanded, "Allegro Enter expands category");
                        onKey.Invoke(tree, new object[] { new KeyEventArgs(Keys.Space) });
                        Check(!tree.Nodes[0].IsExpanded, "Allegro Space collapses category");
                    }
                }
                using (var reopened = new MainForm()) Check(Theme.Current.Id == "toolbox-b", "Selection survives window recreation");
                Console.WriteLine(checks + " appearance checks passed. Screenshots: " + output); return 0;
            } catch (Exception error) { Console.WriteLine(error); return 1; }
        }
    }
}
