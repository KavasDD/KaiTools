// Handles toolbox gestures and live component filtering for its Allegro owner.
// Database operations run through SKILL callbacks in Allegro's event loop.
using System;
using System.Diagnostics;
using System.IO;
using System.Collections.Generic;
using System.Linq;
using System.Web.Script.Serialization;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;
using XiaokaiAppearance;

internal static class AllegroHotkey
{
    delegate IntPtr HookProc(int code, IntPtr message, IntPtr data);
    [StructLayout(LayoutKind.Sequential)] struct KeyData
    { public uint Key, Scan, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] struct Point { public int X, Y; }
    [StructLayout(LayoutKind.Sequential)] struct MouseData
    { public Point Point; public uint Data, Flags, Time; public UIntPtr Extra; }
    [StructLayout(LayoutKind.Sequential)] struct Rect { public int L, T, R, B; }
    [StructLayout(LayoutKind.Sequential)] struct ProcessInfo
    { public IntPtr Reserved1, Peb, Reserved2, Reserved3, Id, Parent; }
    [DllImport("ntdll.dll")] static extern int NtQueryInformationProcess(IntPtr process, int kind,
        ref ProcessInfo info, int size, out int returned);
    [DllImport("user32.dll")] static extern IntPtr SetWindowsHookEx(int id, HookProc callback, IntPtr module, uint thread);
    [DllImport("user32.dll")] static extern bool UnhookWindowsHookEx(IntPtr hook);
    [DllImport("user32.dll")] static extern IntPtr CallNextHookEx(IntPtr hook, int code, IntPtr message, IntPtr data);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr window, StringBuilder text, int size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)] static extern IntPtr GetModuleHandle(string module);
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern IntPtr WindowFromPoint(Point point);
    [DllImport("user32.dll")] static extern IntPtr GetAncestor(IntPtr window, uint flags);
    [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr window, out Rect rect);
    [DllImport("user32.dll")] static extern uint GetDoubleClickTime();
    static Process owner;
    static IntPtr hook, mouseHook;
    static HookProc callback = OnKey;
    static HookProc mouseCallback = OnMouse;
    static bool kDown, fDown;
    static uint lastClick;
    static Point lastPoint;
    static IntPtr lastWindow;
    static ComponentWindow components;
    static DrcWindow drcs;
    static ToolboxWindow toolbox;
    static Process aiChat;
    static Control dispatcher;
    static readonly Queue<string> outgoing = new Queue<string>();
    static readonly AutoResetEvent outgoingReady = new AutoResetEvent(false);

    sealed class WindowOwner : IWin32Window
    {
        public IntPtr Handle { get { return owner.MainWindowHandle; } }
    }

    sealed class ComponentEntry
    {
        public string Name; public int Index;
        public override string ToString() { return Name; }
    }

    sealed class ComponentWindow : SkinForm
    {
        readonly TextBox filter = new TextBox(), current = new TextBox();
        readonly ListBox list = new ListBox();
        readonly Label count = new Label();
        readonly List<ComponentEntry> entries = new List<ComponentEntry>();
        bool updating;

        public ComponentWindow() : base("allegro")
        {
            Text = "A1 元件列表与定位"; Font = new Font("Microsoft YaHei UI", 9F);
            ClientSize = new Size(480, 540); MinimumSize = new Size(340, 280);
            StartPosition = FormStartPosition.CenterScreen; ShowInTaskbar = false;
            var label = new Label { Text = "输入位号片段，立即筛选（如 24）", AutoSize = true, Location = new System.Drawing.Point(12, 12) };
            filter.SetBounds(12, 38, 456, 26); filter.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            list.SetBounds(12, 76, 456, 388); list.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            list.IntegralHeight = false;
            current.SetBounds(12, 476, 456, 26); current.ReadOnly = true;
            current.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            count.SetBounds(12, 512, 456, 22); count.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            Controls.AddRange(new Control[] { label, filter, list, current, count });
            filter.TextChanged += delegate { Filter(); };
            list.SelectedIndexChanged += delegate {
                var entry = list.SelectedItem as ComponentEntry;
                if (!updating && entry != null) { current.Text = entry.Name; Send("LOCATE " + entry.Index); }
            };
            Shown += delegate { filter.Focus(); };
        }

        public void LoadNames(string path)
        {
            string[] names = File.ReadAllLines(path, Encoding.GetEncoding(936));
            entries.Clear();
            for (int i = 0; i < names.Length; i++) entries.Add(new ComponentEntry { Name = names[i], Index = i });
            Filter();
        }

        void Filter()
        {
            updating = true; list.BeginUpdate();
            try {
                list.Items.Clear();
                foreach (var entry in entries)
                    if (entry.Name.IndexOf(filter.Text, StringComparison.OrdinalIgnoreCase) >= 0) list.Items.Add(entry);
                list.SelectedIndex = -1; count.Text = list.Items.Count + " 个元件";
            }
            finally { list.EndUpdate(); updating = false; }
        }
    }

    sealed class DrcEntry
    {
        public int Index;
        public string Name, Layer, Actual, Expected, X, Y, Category;
    }

    sealed class DrcWindow : SkinForm
    {
        readonly ComboBox category = new ComboBox(), layer = new ComboBox(), type = new ComboBox();
        readonly CheckBox unfocused = new CheckBox(), showUnfocused = new CheckBox();
        readonly ListView list = new ListView();
        readonly Label status = new Label();
        readonly List<DrcEntry> entries = new List<DrcEntry>();
        readonly HashSet<string> ignored = new HashSet<string>(StringComparer.Ordinal);
        readonly string preferences = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "xiaokai_drc_unfocused.dat");
        bool updating;

        internal static string Classify(string name)
        {
            string text = name.ToLowerInvariant();
            if (Has(text, "solder", "paste", "mask")) return "阻焊与钢网";
            if (Has(text, "package", "component", "assembly", "place", "height", "dfa")) return "封装与装配";
            if (Has(text, "silk", "outline", "board edge", "mechanical")) return "丝印与机械";
            if (Has(text, "drill", "hole")) return "孔与焊盘";
            if (Has(text, "keepout", "keepin")) return "禁布与边界";
            if (Has(text, "spacing", "clearance", "short")) return "电气间距";
            if (Has(text, "via", "pad", "pin")) return "孔与焊盘";
            if (Has(text, "width", "length", "neck", "connect", "route", "differential", "impedance")) return "连接与走线";
            return "其他";
        }

        static bool Has(string text, params string[] words)
        { foreach (string word in words) if (text.Contains(word)) return true; return false; }

        public DrcWindow() : base("allegro")
        {
            Text = "A2 DRC 分类检查与定位"; Font = new Font("Microsoft YaHei UI", 9F);
            ClientSize = new Size(1000, 620); MinimumSize = new Size(820, 420);
            StartPosition = FormStartPosition.CenterScreen; ShowInTaskbar = false;
            try {
                if (File.Exists(preferences)) foreach (string line in File.ReadAllLines(preferences))
                    ignored.Add(Encoding.UTF8.GetString(Convert.FromBase64String(line)));
            } catch { status.Text = "关注设置读取失败，可重新设置。"; }
            AddChoice("类别", category, 12, 150);
            AddChoice("层", layer, 224, 140);
            AddChoice("类型", type, 426, 510);
            type.Anchor = AnchorStyles.Top | AnchorStyles.Left | AnchorStyles.Right;
            unfocused.Text = "暂不关注此类型"; unfocused.SetBounds(12, 51, 180, 26);
            showUnfocused.Text = "显示暂不关注的类型"; showUnfocused.SetBounds(202, 51, 220, 26);
            var refresh = new Button { Text = "刷新已有 DRC", Anchor = AnchorStyles.Top | AnchorStyles.Right };
            refresh.SetBounds(850, 49, 138, 30);
            list.SetBounds(12, 91, 976, 485); list.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            list.View = View.Details; list.FullRowSelect = true; list.MultiSelect = false; list.HideSelection = false;
            list.Columns.Add("类别", 116); list.Columns.Add("DRC 类型", 265); list.Columns.Add("层", 100);
            list.Columns.Add("实际值", 120); list.Columns.Add("要求值", 120); list.Columns.Add("坐标", 190);
            status.SetBounds(12, 588, 976, 26); status.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            Controls.AddRange(new Control[] { unfocused, showUnfocused, refresh, list, status });
            category.SelectedIndexChanged += delegate { if (!updating) RefreshTypes(); };
            layer.SelectedIndexChanged += delegate { if (!updating) RefreshTypes(); };
            type.SelectedIndexChanged += delegate { if (!updating) Filter(); };
            showUnfocused.CheckedChanged += delegate { if (!updating) Filter(); };
            unfocused.CheckedChanged += delegate {
                var choice = type.SelectedItem as DrcType;
                if (updating || choice == null || choice.Name == null) return;
                if (unfocused.Checked) ignored.Add(choice.Name); else ignored.Remove(choice.Name);
                try {
                    var data = new List<string>();
                    foreach (string name in ignored) data.Add(Convert.ToBase64String(Encoding.UTF8.GetBytes(name)));
                    File.WriteAllLines(preferences, data.ToArray()); Filter();
                } catch { status.Text = "关注设置保存失败，请检查目录写入权限。"; }
            };
            refresh.Click += delegate { Send("REFRESH_DRC"); };
            list.SelectedIndexChanged += delegate {
                if (!updating && list.SelectedItems.Count == 1)
                    Send("LOCATE_DRC " + ((DrcEntry)list.SelectedItems[0].Tag).Index);
            };
        }

        void AddChoice(string title, ComboBox choice, int x, int width)
        {
            var label = new Label { Text = title, AutoSize = true, Location = new System.Drawing.Point(x, 16) };
            choice.DropDownStyle = ComboBoxStyle.DropDownList; choice.SetBounds(x + 40, 12, width, 27);
            Controls.Add(label); Controls.Add(choice);
        }

        sealed class DrcType
        {
            public string Name; public int Count;
            public override string ToString() { return Name == null ? "全部类型（" + Count + "）" : Name + "（" + Count + "）"; }
        }

        static void Choices(ComboBox control, List<string> values, string previous)
        {
            control.Items.Clear(); control.Items.Add("全部");
            values.Sort(StringComparer.OrdinalIgnoreCase);
            foreach (string value in values) control.Items.Add(value);
            int index = control.Items.IndexOf(previous ?? "全部"); control.SelectedIndex = index < 0 ? 0 : index;
        }

        public void LoadRows(string path)
        {
            string previousCategory = category.SelectedItem as string, previousLayer = layer.SelectedItem as string;
            entries.Clear(); var categories = new List<string>(); var layers = new List<string>();
            int sourceIndex = 0;
            foreach (string line in File.ReadAllLines(path, Encoding.GetEncoding(936))) {
                int index = sourceIndex++;
                string[] parts = line.Split('\t');
                if (parts.Length != 7) continue;
                string layerName = parts[1]; int slash = layerName.LastIndexOf('/');
                if (slash >= 0) layerName = layerName.Substring(slash + 1);
                var entry = new DrcEntry { Index = index, Name = parts[0], Layer = layerName, Actual = parts[2],
                    Expected = parts[3], X = parts[4], Y = parts[5], Category = Classify(parts[0]) };
                entries.Add(entry);
                if (!categories.Contains(entry.Category)) categories.Add(entry.Category);
                if (!layers.Contains(entry.Layer)) layers.Add(entry.Layer);
            }
            updating = true;
            try { Choices(category, categories, previousCategory); Choices(layer, layers, previousLayer); }
            finally { updating = false; }
            RefreshTypes();
        }

        bool Matches(DrcEntry entry)
        {
            return (category.SelectedIndex == 0 || entry.Category == category.SelectedItem as string)
                && (layer.SelectedIndex == 0 || entry.Layer == layer.SelectedItem as string);
        }

        void RefreshTypes()
        {
            var previous = type.SelectedItem as DrcType;
            var counts = new SortedDictionary<string, int>(StringComparer.Ordinal); int total = 0;
            foreach (var entry in entries) if (Matches(entry)) {
                if (!counts.ContainsKey(entry.Name)) counts[entry.Name] = 0;
                counts[entry.Name]++; total++;
            }
            updating = true;
            try {
                type.Items.Clear(); type.Items.Add(new DrcType { Count = total }); int selected = 0;
                foreach (var item in counts) {
                    int index = type.Items.Add(new DrcType { Name = item.Key, Count = item.Value });
                    if (previous != null && item.Key == previous.Name) selected = index;
                }
                type.SelectedIndex = selected;
            } finally { updating = false; }
            Filter();
        }

        void Filter()
        {
            var choice = type.SelectedItem as DrcType; int hidden = 0;
            updating = true; list.BeginUpdate();
            try {
                unfocused.Enabled = choice != null && choice.Name != null;
                unfocused.Checked = unfocused.Enabled && ignored.Contains(choice.Name);
                list.Items.Clear();
                foreach (var entry in entries) if (Matches(entry) && (choice == null || choice.Name == null || entry.Name == choice.Name)) {
                    if (ignored.Contains(entry.Name) && !showUnfocused.Checked) { hidden++; continue; }
                    var row = new ListViewItem(new[] { entry.Category, entry.Name, entry.Layer, entry.Actual, entry.Expected, entry.X + ", " + entry.Y });
                    row.Tag = entry; if (ignored.Contains(entry.Name)) row.ForeColor = Color.Gray;
                    list.Items.Add(row);
                }
                status.Text = "显示 " + list.Items.Count + " / " + entries.Count + " 条；暂不关注隐藏 " + hidden + " 条。单击记录定位。";
            } finally { list.EndUpdate(); updating = false; }
        }
    }

    sealed class ToolboxWindow : SkinForm
    {
        readonly TreeView tools = new TreeView();
        readonly Label description = new Label();
        readonly Button execute = new Button();
        sealed class ActionItem
        {
            public string Command, Description;
            public ActionItem(string command, string description) { Command = command; Description = description; }
        }
        public ToolboxWindow() : base("allegro")
        {
            Text = "小开 SKILL 工具箱"; Font = new Font("Microsoft YaHei UI", 9F);
            ClientSize = new Size(690, 650); MinimumSize = new Size(550, 480);
            StartPosition = FormStartPosition.CenterScreen;
            Controls.Add(new Label { Text = "SKILL 工具集合", Left = 22, Top = 19, Width = 340, Height = 30,
                Font = new Font(Font.FontFamily, 16F, FontStyle.Bold) });
            Controls.Add(new Label { Text = "点击分类展开，双击工具直接运行", Left = 24, Top = 58, Width = 410, Height = 24 });
            tools.SetBounds(22, 96, 646, 414);
            tools.Anchor = AnchorStyles.Top | AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            tools.ItemHeight = 30; tools.FullRowSelect = true; tools.HideSelection = false;
            tools.ShowLines = false; tools.Indent = 22;
            tools.DrawMode = TreeViewDrawMode.OwnerDrawText;
            tools.DrawNode += delegate(object sender, DrawTreeNodeEventArgs e) {
                bool selected = (e.State & TreeNodeStates.Selected) != 0;
                Rectangle bounds = new Rectangle(e.Bounds.X, e.Bounds.Y,
                    Math.Max(0, tools.ClientSize.Width - e.Bounds.X), e.Bounds.Height);
                Color surface = CurrentSkin.Surface;
                Color highlight = Color.FromArgb((surface.R * 4 + CurrentSkin.Accent.R) / 5,
                    (surface.G * 4 + CurrentSkin.Accent.G) / 5, (surface.B * 4 + CurrentSkin.Accent.B) / 5);
                using (var brush = new SolidBrush(selected ? highlight : surface)) e.Graphics.FillRectangle(brush, bounds);
                if (selected) using (var brush = new SolidBrush(CurrentSkin.Accent)) e.Graphics.FillRectangle(brush, bounds.X, bounds.Y + 3, 3, bounds.Height - 6);
                bounds.X += 8; bounds.Width = Math.Max(0, bounds.Width - 10);
                TextRenderer.DrawText(e.Graphics, e.Node.Text, tools.Font, bounds,
                    selected ? CurrentSkin.Accent : CurrentSkin.Text, TextFormatFlags.Left | TextFormatFlags.VerticalCenter);
            };
            TreeNode view = tools.Nodes.Add("查看类");
            var aiButton = new Button { Text = "AI 命令辅助", Left = 528, Top = 30, Width = 140, Height = 34, Anchor = AnchorStyles.Top | AnchorStyles.Right };
            aiButton.Click += delegate { if (owner != null) Send("EXEC xk_ai"); };
            Controls.Add(aiButton);
            Add(view, "A1：元件列表与定位", "find component", "Ctrl+F 打开；输入位号片段实时筛选，选择元件定位并显示相关层。");
            Add(view, "A2：现有 DRC 浏览与定位", "find drc", "按类别、层和具体类型筛选已有 DRC，单击定位。");
            Add(view, "A3：快速切换格点", "quick_grids", "选择 mil 或 mm 格点值，修改当前设计格点。");
            Add(view, "A4：快速切换层显示", "quick_display", "十个可命名显示配置，可分别保存和读取。");
            Add(view, "A5：mm／mil 单位换算", "conv", "输入数值，在 mm 与 mil 之间换算。");
            Add(view, "A6：焊盘与孔径高亮", "hps", "选择焊盘名称或孔径，高亮对应引脚和过孔。");
            Add(view, "A7：修改库路径", "xk_library_paths", "选择或填写 PSMPATH、PADPATH、DEVPATH，保存后生效。");
            Add(view, "A8：生成元件高度文字", "show_height", "读取 PCB 封装高度属性，重建 HEIGHT_TEXT_TOP／BOTTOM 文字。");
            Add(view, "A9：一键设置光绘与层叠颜色", "xk_production_setup", "重建光绘、设置层叠颜色，并按光绘创建顺序显示。");
            TreeNode textTools = tools.Nodes.Add("丝印与文字整理");
            Add(textTools, "B1：文字调整与居中", "tt", "框选或点选元件，调整文字居中、方向、字号；原窗口默认装配层，需要丝印时选择 Silkscreen。");
            Add(textTools, "B2：丝印导出与导入", "xk_silk_io", "先框选元件或丝印元素，点击导出后选择保存路径；仅导出选中范围。原版导入会解除固定并替换文件所列层全部丝印。");
            Add(tools.Nodes.Add("过孔与走线修改"), "C1：过孔修改网络", "cvia", "选择过孔，右键 Done 后选择目标网络；跳过固定过孔。");
            tools.Nodes.Add("铜皮、布局与板图辅助"); tools.Nodes.Add("生产输出与转换");
            TreeNode checks = tools.Nodes.Add("检查类（Check）");
            Add(checks, "D1：悬空线／过孔／孤岛检查与处理", "xk_dangling_check", "分页检查、定位、刷新和删除悬空线、过孔及孤岛。");
            Add(checks, "D2：未扇出 SMD 引脚检查", "hl_nf", "选择顶层或底层，检查未扇出的 SMD 引脚并逐项定位。");
            Add(checks, "D3：焊盘与走线间距检查", "solder2line check", "保留原版矩形焊盘检查算法；按当前设计单位填写间距，检查顶层或底层并定位。");
            Add(checks, "D4：SMD 与通孔引脚间距检查", "quick_smd2thrp", "检查 SMD 元件与对面通孔引脚的间距，支持前后定位；默认 120 mil。");
            Add(checks, "D5：缺少锡膏开窗检查", "find_pin_no_past", "原版加密脚本，生成缺少锡膏开窗的引脚报告。");
            Add(checks, "D6：缺少阻焊开窗检查", "find_pin_no_solder", "原版加密脚本，生成缺少阻焊开窗的引脚报告。");
            Add(checks, "D7：缺失丝印位号检查", "Check_No_Refdes", "运行后直接显示并高亮缺少丝印位号的元件，自动打开检查报告；结果保留在 no_refdes.log。");
            Add(checks, "D8：丝印重叠检查（增强版）", "ch_text_overlap", "选择顶层或底层及检查项目，检查后用前后按钮定位；间距使用当前设计单位。");
            Add(checks, "D9：丝印位号交叉检查", "ch_cross", "检查交叉位号，在 MANUFACTURING/REFDES TOP DRC、BOTTOM DRC 层生成标记。");
            description.SetBounds(24, 526, 642, 58);
            description.Anchor = AnchorStyles.Bottom | AnchorStyles.Left | AnchorStyles.Right;
            description.Text = "展开分类并选择工具，可在此查看功能说明。";
            execute.Text = "执行"; execute.Tag = "primary"; execute.Enabled = false;
            execute.SetBounds(548, 599, 120, 32); execute.Anchor = AnchorStyles.Bottom | AnchorStyles.Right;
            var close = new Button { Text = "关闭", Left = 416, Top = 599, Width = 120, Height = 32,
                Anchor = AnchorStyles.Bottom | AnchorStyles.Right };
            close.Click += delegate { Close(); };
            tools.AfterSelect += delegate {
                var action = tools.SelectedNode.Tag as ActionItem;
                execute.Enabled = action != null;
                description.Text = action == null ? "展开分类后选择工具；空分类暂无已安装工具。" : action.Description;
            };
            tools.NodeMouseClick += delegate(object sender, TreeNodeMouseClickEventArgs e) {
                if (e.Button != MouseButtons.Left || e.Node.Tag is ActionItem || e.Node.Nodes.Count == 0) return;
                if ((tools.HitTest(e.Location).Location & TreeViewHitTestLocations.PlusMinus) != 0) return;
                if (e.Node.IsExpanded) e.Node.Collapse(); else e.Node.Expand();
            };
            tools.NodeMouseDoubleClick += delegate(object sender, TreeNodeMouseClickEventArgs e) { if (e.Node.Tag is ActionItem) RunSelected(); };
            tools.KeyDown += delegate(object sender, KeyEventArgs e) {
                if (e.KeyCode == Keys.Enter || e.KeyCode == Keys.Space) {
                    TreeNode node = tools.SelectedNode;
                    if (node != null && !(node.Tag is ActionItem)) {
                        if (node.IsExpanded) node.Collapse(); else node.Expand();
                    } else if (e.KeyCode == Keys.Enter) RunSelected();
                    e.Handled = true; e.SuppressKeyPress = true;
                }
            };
            execute.Click += delegate { RunSelected(); };
            Controls.AddRange(new Control[] { tools, description, execute, close });
            CancelButton = close;
        }
        static void Add(TreeNode group, string name, string command, string text)
        { group.Nodes.Add(new TreeNode(name) { Tag = new ActionItem(command, text) }); }
        void RunSelected()
        {
            var action = tools.SelectedNode == null ? null : tools.SelectedNode.Tag as ActionItem;
            if (action == null) return;
            if (owner == null) { MessageBox.Show(this, "这是独立皮肤预览。请在 Allegro 中按 Alt+K 执行工具。", "皮肤预览"); return; }
            Send("EXEC " + action.Command);
        }
    }

    static void ShowToolbox()
    {
        if (toolbox == null || toolbox.IsDisposed) { toolbox = new ToolboxWindow(); toolbox.Show(new WindowOwner()); }
        if (toolbox.WindowState == FormWindowState.Minimized) toolbox.WindowState = FormWindowState.Normal;
        toolbox.RefreshSkin(); toolbox.Activate();
    }

    static void ReadRequests()
    {
        try {
            string line;
            while ((line = Console.ReadLine()) != null) {
                string request = line;
                dispatcher.BeginInvoke((Action)delegate {
                    if (request == "TOOLBOX") { ShowToolbox(); }
                    else if (request == "AI_OPEN") { ShowAiChat(); }
                    else if (request.StartsWith("AI_CONTEXT_FILE ", StringComparison.Ordinal)) {
                        string[] fields = request.Split(new[] { ' ' }, 3);
                        if (fields.Length == 3 && aiChat != null && !aiChat.HasExited) {
                            try {
                                var rows = File.ReadAllLines(fields[2], Encoding.GetEncoding(936));
                                var parts = new List<object>();
                                for (int i = 1; i < rows.Length && i <= 5000; i++) parts.Add(new { index = i - 1, @ref = rows[i] });
                                string context = new JavaScriptSerializer().Serialize(new { platform = "allegro", scope = rows[0], board = rows[0], parts = parts.ToArray(), limit = "Only locate and open installed tools" });
                                aiChat.StandardInput.WriteLine("CTX\t" + fields[1] + "\t" + Convert.ToBase64String(Encoding.UTF8.GetBytes(context))); aiChat.StandardInput.Flush();
                            } catch { AiResult(fields[1], "未执行：无法读取当前板文件上下文，请重试。", false); }
                        }
                    }
                    else if (request.StartsWith("AI_RESULT ", StringComparison.Ordinal)) {
                        string[] fields = request.Split(' ');
                        if (fields.Length >= 3) AiResult(fields[1], fields[2] == "OK" ? "已在 Allegro 中执行对应动作。工具调用表示打开工具；具体修改请在工具中完成。" : "未执行：工程已切换、对象不存在或命令未完成，请重新发送。", fields[2] == "OK");
                    }
                    else if (request.StartsWith("COMPONENTS ", StringComparison.Ordinal)) {
                        try {
                            bool show = components == null || components.IsDisposed;
                            if (show) components = new ComponentWindow();
                            components.LoadNames(request.Substring(11));
                            if (show) components.Show(new WindowOwner());
                            components.Activate(); Send("COMPONENTS_LOADED");
                        }
                        catch { Send("COMPONENTS_FAILED"); }
                    }
                    else if (request.StartsWith("DRCS ", StringComparison.Ordinal)) {
                        try {
                            bool show = drcs == null || drcs.IsDisposed;
                            if (show) drcs = new DrcWindow();
                            drcs.LoadRows(request.Substring(5));
                            if (show) drcs.Show(new WindowOwner());
                            drcs.Activate(); Send("DRCS_LOADED");
                        } catch { Send("DRCS_FAILED"); }
                    }
                });
            }
        }
        catch { }
    }

    static void AiResult(string id, string message, bool success)
    {
        try { if (aiChat != null && !aiChat.HasExited) { aiChat.StandardInput.WriteLine((success ? "RESULT\t" : "ERROR\t") + id + "\t" + Convert.ToBase64String(Encoding.UTF8.GetBytes(message))); aiChat.StandardInput.Flush(); } } catch { }
    }
    static void ShowAiChat()
    {
        try {
            if (aiChat != null && !aiChat.HasExited) { aiChat.StandardInput.WriteLine("SHOW"); aiChat.StandardInput.Flush(); return; }
            string helper = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "xiaokaiAiBridge.exe");
            var process = new Process { StartInfo = new ProcessStartInfo(helper, "--chat allegro") {
                UseShellExecute = false, CreateNoWindow = true, RedirectStandardInput = true, RedirectStandardOutput = true,
                StandardOutputEncoding = Encoding.UTF8 } };
            process.Start(); aiChat = process;
            ThreadPool.QueueUserWorkItem(delegate {
                try {
                    string line;
                    while ((line = process.StandardOutput.ReadLine()) != null) {
                        string captured = line;
                        dispatcher.BeginInvoke((Action)delegate {
                            var fields = captured.Split('\t');
                            if (aiChat != process || fields.Length < 2 || !System.Text.RegularExpressions.Regex.IsMatch(fields[1], "^[a-f0-9]{32}$")) return;
                            if (fields[0] == "CONTEXT" && fields.Length == 2) Send("AI_CONTEXT " + fields[1]);
                            else if (fields[0] == "CANCEL") Send("AI_CANCEL " + fields[1]);
                            else if (fields[0] == "ACTION" && fields.Length == 8) {
                                int index;
                                if (fields[2] == "locate" && Int32.TryParse(fields[6], out index) && index >= 0 && index < 5000)
                                    Send("AI_ACTION " + fields[1] + " locate " + index);
                                else if (fields[2] == "open_tool" && new[] { "components", "drc", "grid", "display", "convert", "pads", "library", "height", "production", "via", "dangling" }.Contains(fields[7]))
                                    Send("AI_ACTION " + fields[1] + " open_tool " + fields[7]);
                                else AiResult(fields[1], "未执行：此动作尚未接入 Allegro。", false);
                            }
                        });
                    }
                } catch { }
                finally { try { process.StandardInput.Close(); } catch { } }
            });
        } catch { MessageBox.Show("AI 辅助程序未安装，请在小开工具箱重新加载新版 Allegro 插件集合。", "AI 命令辅助"); }
    }

    static bool IsOwner(IntPtr window, out string title)
    {
        uint process; GetWindowThreadProcessId(window, out process);
        var text = new StringBuilder(512); GetWindowText(window, text, text.Capacity);
        title = text.ToString();
        return process == owner.Id;
    }

    static bool IsToolContext(IntPtr window, out string title)
    {
        if (IsOwner(window, out title)) return true;
        uint process; GetWindowThreadProcessId(window, out process);
        return process == Process.GetCurrentProcess().Id && title == "小开 SKILL 工具箱";
    }

    static void Send(string message)
    {
        lock (outgoing) outgoing.Enqueue(message);
        outgoingReady.Set();
    }

    static void WriteMessages()
    {
        try {
            while (true) {
                outgoingReady.WaitOne();
                while (true) {
                    string message;
                    lock (outgoing) { if (outgoing.Count == 0) break; message = outgoing.Dequeue(); }
                    Console.Out.WriteLine(message); Console.Out.Flush();
                }
            }
        } catch { }
    }

    // Windows removes low-level hooks if their message thread stalls. Keep this
    // loop separate from DRC list population and never write IPC from a hook.
    static void GestureLoop()
    {
        hook = SetWindowsHookEx(13, callback, GetModuleHandle(null), 0);
        mouseHook = SetWindowsHookEx(14, mouseCallback, GetModuleHandle(null), 0);
        try { Application.Run(); }
        finally {
            if (hook != IntPtr.Zero) UnhookWindowsHookEx(hook);
            if (mouseHook != IntPtr.Zero) UnhookWindowsHookEx(mouseHook);
        }
    }

    static IntPtr OnMouse(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0 && message.ToInt64() == 0x201)
        {
            MouseData mouse = (MouseData)Marshal.PtrToStructure(data, typeof(MouseData));
            IntPtr window = GetAncestor(WindowFromPoint(mouse.Point), 2);
            string title; Rect rect;
            if (IsOwner(window, out title) && title == "小开 SKILL 工具箱" && GetWindowRect(window, out rect)
                && mouse.Point.X > rect.L + 26 && mouse.Point.X < rect.R - 24
                && mouse.Point.Y > rect.T + 60 && mouse.Point.Y < rect.B - 110)
            {
                if (window == lastWindow && unchecked(mouse.Time - lastClick) <= GetDoubleClickTime()
                    && Math.Abs(mouse.Point.X - lastPoint.X) <= 4 && Math.Abs(mouse.Point.Y - lastPoint.Y) <= 4)
                {
                    Send("RUN"); lastClick = 0;
                }
                else { lastClick = mouse.Time; lastPoint = mouse.Point; lastWindow = window; }
            }
        }
        return CallNextHookEx(mouseHook, code, message, data);
    }

    static Process FindOwner()
    {
        Process process = Process.GetCurrentProcess();
        for (int depth = 0; depth < 6; depth++)
        {
            ProcessInfo info = new ProcessInfo(); int returned;
            if (NtQueryInformationProcess(process.Handle, 0, ref info, Marshal.SizeOf(typeof(ProcessInfo)), out returned) != 0)
                throw new InvalidOperationException("Cannot find Allegro owner.");
            process = Process.GetProcessById(info.Parent.ToInt32());
            if (process.ProcessName.Equals("allegro", StringComparison.OrdinalIgnoreCase)) return process;
        }
        throw new InvalidOperationException("Allegro owner not found.");
    }

    static IntPtr OnKey(int code, IntPtr message, IntPtr data)
    {
        if (code >= 0)
        {
            KeyData key = (KeyData)Marshal.PtrToStructure(data, typeof(KeyData));
            bool down = message.ToInt64() == 0x100 || message.ToInt64() == 0x104;
            bool up = message.ToInt64() == 0x101 || message.ToInt64() == 0x105;
            if (key.Key == 0x46)
            {
                if (up) fDown = false;
                string title;
                if (down && !fDown && GetAsyncKeyState(0x11) < 0 && IsToolContext(GetForegroundWindow(), out title)
                    && (title.StartsWith("Allegro PCB Designer:", StringComparison.Ordinal) || title == "小开 SKILL 工具箱"))
                {
                    fDown = true; Send("FIND"); return (IntPtr)1;
                }
            }
            if (key.Key == 0x4b)
            {
                if (up) kDown = false;
                if (down && !kDown)
                {
                    kDown = true;
                    uint foreground; IntPtr window = GetForegroundWindow();
                    GetWindowThreadProcessId(window, out foreground);
                    StringBuilder title = new StringBuilder(512); GetWindowText(window, title, title.Capacity);
                    string contextTitle;
                    if ((key.Flags & 0x20) != 0 && IsToolContext(window, out contextTitle) &&
                        (title.ToString().StartsWith("Allegro PCB Designer:", StringComparison.Ordinal) ||
                         title.ToString() == "小开 SKILL 工具箱"))
                    {
                        Send("OPEN");
                    }
                }
            }
        }
        return CallNextHookEx(hook, code, message, data);
    }

    [STAThread] static int Main(string[] args)
    {
        try
        {
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            if (Array.IndexOf(args, "--preview") >= 0) { Application.Run(new ToolboxWindow()); return 0; }
            owner = FindOwner();
            bool created;
            using (Mutex unique = new Mutex(true, "Local\\XiaokaiAllegroHotkey-" + owner.Id, out created))
            {
                if (!created) return 0;
                dispatcher = new Control();
                IntPtr dispatchHandle = dispatcher.Handle;
                var input = new Thread(ReadRequests) { IsBackground = true };
                input.Start();
                new Thread(WriteMessages) { IsBackground = true }.Start();
                var gestures = new Thread(GestureLoop) { IsBackground = true };
                gestures.SetApartmentState(ApartmentState.STA);
                gestures.Start();
                using (System.Windows.Forms.Timer lifetime = new System.Windows.Forms.Timer())
                {
                    lifetime.Interval = 1000;
                    lifetime.Tick += delegate { if (owner.HasExited) Application.ExitThread(); };
                    lifetime.Start();
                    Application.Run();
                }
            }
            return 0;
        }
        catch { return 1; }
    }
}
