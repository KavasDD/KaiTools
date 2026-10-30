// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Text;
using System.Windows.Forms;

[assembly: AssemblyTitle("小开工具箱 · 常见丝印反查")]
[assembly: AssemblyVersion("1.0.0.0")]
[assembly: AssemblyFileVersion("1.0.0.0")]

namespace XiaokaiMarking
{
    public sealed class Part
    {
        public string Marking, Model, Category, Package, Maker, Parameters, Notes, Source;
        public string[] Fields { get { return new[] { Marking, Model, Category, Package, Maker, Parameters, Notes, Source ?? "用户整理；待数据手册核对" }; } }
        public string CopyText()
        {
            return "丝印：" + Marking + "\r\n型号：" + Model + "\r\n类别：" + Category
                + "\r\n封装：" + Package + "\r\n厂商：" + Maker + "\r\n参数/用途：" + Parameters
                + "\r\n备注：" + Notes + "\r\n资料来源：" + (Source ?? "用户整理；待数据手册核对");
        }
    }

    public static class Catalog
    {
        public static List<Part> Load()
        {
            var parts = new List<Part>();
            using (Stream stream = Assembly.GetExecutingAssembly().GetManifestResourceStream("markings.tsv"))
            {
                if (stream == null) throw new InvalidDataException("未找到内置丝印库。");
                using (var reader = new StreamReader(stream, Encoding.UTF8, true))
                {
                    reader.ReadLine();
                    string line;
                    while ((line = reader.ReadLine()) != null)
                    {
                        if (String.IsNullOrWhiteSpace(line)) continue;
                        string[] f = line.Split('\t');
                        if (f.Length != 8) throw new InvalidDataException("丝印库条目应包含 8 列：" + line);
                        parts.Add(new Part { Marking=f[0], Model=f[1], Category=f[2], Package=f[3],
                            Maker=f[4], Parameters=f[5], Notes=f[6], Source=f[7] });
                    }
                }
            }
            return parts;
        }

        // Ignore case, width, spaces and punctuation in identifiers (SOT23-5 = SOT-23-5).
        public static string Normalize(string value)
        {
            var text = new StringBuilder();
            foreach (char c in (value ?? "").Normalize(NormalizationForm.FormKC))
                if (Char.IsLetterOrDigit(c)) text.Append(Char.ToUpperInvariant(c));
            return text.ToString();
        }

        static bool Matches(string value, string token, bool exact)
        {
            if (!exact) return Normalize(value).Contains(token);
            foreach (string alias in value.Split('|'))
                if (Normalize(alias) == token) return true;
            return false;
        }

        public static List<Part> Search(List<Part> parts, string query, string category,
            string package, int field, bool exact)
        {
            string[] rawTokens = (query ?? "").Split(new[] { ' ', '\t', '\r', '\n', '　' }, StringSplitOptions.RemoveEmptyEntries);
            var tokens = new List<string>();
            foreach (string raw in rawTokens)
            {
                string token = Normalize(raw);
                if (token.Length > 0) tokens.Add(token);
            }
            var result = new List<Part>();
            foreach (Part part in parts)
            {
                if (!String.IsNullOrEmpty(category) && part.Category != category) continue;
                if (!String.IsNullOrEmpty(package) && part.Package != package) continue;
                bool include = true;
                foreach (string token in tokens)
                {
                    bool found = false;
                    string[] fields = field == 1 ? new[] { part.Marking }
                        : field == 2 ? new[] { part.Model } : part.Fields;
                    foreach (string value in fields)
                        if (Matches(value, token, exact)) { found = true; break; }
                    if (!found) { include = false; break; }
                }
                if (include) result.Add(part);
            }
            string full = Normalize(query);
            result.Sort(delegate(Part a, Part b) {
                int aRank = Matches(a.Marking, full, true) ? 0 : Matches(a.Model, full, true) ? 1 : 2;
                int bRank = Matches(b.Marking, full, true) ? 0 : Matches(b.Model, full, true) ? 1 : 2;
                int rank = aRank.CompareTo(bRank);
                if (rank != 0) return rank;
                rank = String.Compare(a.Marking, b.Marking, StringComparison.OrdinalIgnoreCase);
                return rank != 0 ? rank : String.Compare(a.Model, b.Model, StringComparison.OrdinalIgnoreCase);
            });
            return result;
        }
    }

    public sealed class LookupForm : Form
    {
        readonly List<Part> parts;
        internal readonly TextBox Query = new TextBox();
        internal readonly ComboBox Category = new ComboBox(), Package = new ComboBox(), Field = new ComboBox();
        internal readonly CheckBox Exact = new CheckBox();
        internal readonly DataGridView Grid = new DataGridView();
        internal readonly TextBox Details = new TextBox();
        internal readonly Label Count = new Label();
        readonly Button copy = new Button();
        bool ready;

        public LookupForm()
        {
            parts = Catalog.Load();
            Text = "常见丝印反查 · 小开工具箱";
            Font = new Font("Microsoft YaHei UI", 9F);
            BackColor = Color.FromArgb(245, 247, 250);
            ForeColor = Color.FromArgb(35, 45, 60);
            StartPosition = FormStartPosition.CenterScreen;
            ClientSize = new Size(1140, 740);
            MinimumSize = new Size(920, 640);
            AutoScaleMode = AutoScaleMode.Font;
            Icon = Icon.ExtractAssociatedIcon(Application.ExecutablePath);

            var layout = new TableLayoutPanel { Dock=DockStyle.Fill, ColumnCount=1, RowCount=7, Padding=new Padding(18) };
            layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 44));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 42));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 40));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
            layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 180));
            layout.RowStyles.Add(new RowStyle(SizeType.Absolute, 38));
            Controls.Add(layout);
            layout.Controls.Add(new Label { Text="常见丝印反查", Font=new Font(Font.FontFamily, 18, FontStyle.Bold),
                AutoSize=true, Anchor=AnchorStyles.Left }, 0, 0);

            var search = new TableLayoutPanel { Dock=DockStyle.Fill, ColumnCount=4, RowCount=1 };
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 68));
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 130));
            search.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
            search.Controls.Add(new Label { Text="关键词", AutoSize=true, Anchor=AnchorStyles.Left }, 0, 0);
            Query.Dock = DockStyle.Fill;
            Query.AccessibleName = "搜索丝印、型号、封装或参数";
            search.Controls.Add(Query, 1, 0);
            Field.DropDownStyle = ComboBoxStyle.DropDownList;
            Field.Items.AddRange(new object[] { "全部字段", "仅丝印", "仅型号" });
            Field.SelectedIndex = 0;
            Field.Dock = DockStyle.Fill;
            search.Controls.Add(Field, 2, 0);
            Exact.Text = "精确匹配"; Exact.AutoSize = true;
            search.Controls.Add(Exact, 3, 0);
            layout.Controls.Add(search, 0, 1);

            var filters = new FlowLayoutPanel { Dock=DockStyle.Fill, WrapContents=false };
            filters.Controls.Add(new Label { Text="类别", AutoSize=true, Margin=new Padding(0, 7, 10, 0) });
            Category.Width = 210;
            FillFilter(Category, "全部类别", true);
            filters.Controls.Add(Category);
            filters.Controls.Add(new Label { Text="封装", AutoSize=true, Margin=new Padding(18, 7, 10, 0) });
            Package.Width = 230;
            FillFilter(Package, "全部封装", false);
            filters.Controls.Add(Package);
            var reset = new Button { Text="重置", AutoSize=true, Margin=new Padding(16, 0, 0, 0) };
            reset.Click += delegate { ResetFilters(); };
            filters.Controls.Add(reset);
            layout.Controls.Add(filters, 0, 2);
            Count.AutoSize = true;
            Count.Anchor = AnchorStyles.Left;
            layout.Controls.Add(Count, 0, 3);

            Grid.Dock = DockStyle.Fill;
            Grid.BackgroundColor = Color.White;
            Grid.BorderStyle = BorderStyle.None;
            Grid.ReadOnly = true;
            Grid.AllowUserToAddRows = false;
            Grid.AllowUserToDeleteRows = false;
            Grid.AllowUserToResizeRows = false;
            Grid.AutoGenerateColumns = false;
            Grid.RowHeadersVisible = false;
            Grid.MultiSelect = false;
            Grid.SelectionMode = DataGridViewSelectionMode.FullRowSelect;
            Grid.AutoSizeColumnsMode = DataGridViewAutoSizeColumnsMode.Fill;
            Grid.EnableHeadersVisualStyles = false;
            Grid.ColumnHeadersDefaultCellStyle.BackColor = Color.FromArgb(229, 235, 243);
            Grid.ColumnHeadersDefaultCellStyle.ForeColor = ForeColor;
            Grid.ColumnHeadersHeight = 34;
            Grid.RowTemplate.Height = 32;
            Grid.AlternatingRowsDefaultCellStyle.BackColor = Color.FromArgb(247, 249, 252);
            AddColumn("丝印", 75); AddColumn("候选型号", 185); AddColumn("类别", 125);
            AddColumn("封装", 130); AddColumn("参数 / 用途", 220); AddColumn("厂商", 130);
            Grid.SelectionChanged += delegate { ShowSelected(); };
            layout.Controls.Add(Grid, 0, 4);

            var detailLayout = new TableLayoutPanel { Dock=DockStyle.Fill, ColumnCount=2, RowCount=2, Padding=new Padding(0, 8, 0, 0) };
            detailLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            detailLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 225));
            detailLayout.RowStyles.Add(new RowStyle(SizeType.Absolute, 30));
            detailLayout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
            detailLayout.Controls.Add(new Label { Text="选中条目 · 参数与核对说明", AutoSize=true, Anchor=AnchorStyles.Left }, 0, 0);
            copy.Text = "复制条目（含来源链接）"; copy.Dock = DockStyle.Fill;
            copy.Click += delegate { CopySelected(); };
            detailLayout.Controls.Add(copy, 1, 0);
            Details.Multiline = true; Details.ReadOnly = true; Details.Dock = DockStyle.Fill;
            Details.ScrollBars = ScrollBars.Vertical; Details.BackColor = Color.White;
            detailLayout.Controls.Add(Details, 0, 1); detailLayout.SetColumnSpan(Details, 2);
            layout.Controls.Add(detailLayout, 0, 5);
            layout.Controls.Add(new Label { Text="同一丝印可能对应多个型号，请结合封装、厂商和电路核对。各条目注明用户资料或厂商数据手册来源。",
                AutoSize=true, Anchor=AnchorStyles.Left, ForeColor=Color.FromArgb(100, 110, 125) }, 0, 6);

            Query.TextChanged += delegate { RefreshResults(); };
            Category.SelectedIndexChanged += delegate { RefreshResults(); };
            Package.SelectedIndexChanged += delegate { RefreshResults(); };
            Field.SelectedIndexChanged += delegate { RefreshResults(); };
            Exact.CheckedChanged += delegate { RefreshResults(); };
            KeyPreview = true;
            KeyDown += delegate(object sender, KeyEventArgs e) {
                if (e.Control && e.KeyCode == Keys.F) { Query.Focus(); Query.SelectAll(); e.SuppressKeyPress=true; }
                if (e.KeyCode == Keys.Escape) { ResetFilters(); e.SuppressKeyPress=true; }
            };
            Shown += delegate { Query.Focus(); };
            ready = true;
            RefreshResults();
        }

        void AddColumn(string title, float weight)
        {
            Grid.Columns.Add(new DataGridViewTextBoxColumn { HeaderText=title, FillWeight=weight,
                MinimumWidth=65, SortMode=DataGridViewColumnSortMode.NotSortable });
        }

        void FillFilter(ComboBox combo, string all, bool categories)
        {
            combo.DropDownStyle = ComboBoxStyle.DropDownList;
            combo.Items.Add(all);
            var values = new List<string>();
            foreach (Part part in parts)
            {
                string value = categories ? part.Category : part.Package;
                if (!values.Contains(value)) values.Add(value);
            }
            values.Sort(StringComparer.CurrentCulture);
            foreach (string value in values) combo.Items.Add(value);
            combo.SelectedIndex = 0;
        }

        internal void ResetFilters()
        {
            ready = false;
            Query.Clear(); Category.SelectedIndex=0; Package.SelectedIndex=0; Field.SelectedIndex=0; Exact.Checked=false;
            ready = true;
            RefreshResults(); Query.Focus();
        }

        void RefreshResults()
        {
            if (!ready) return;
            List<Part> result = Catalog.Search(parts, Query.Text,
                Category.SelectedIndex > 0 ? Category.Text : "", Package.SelectedIndex > 0 ? Package.Text : "",
                Field.SelectedIndex, Exact.Checked);
            Grid.Rows.Clear();
            foreach (Part part in result)
            {
                int row = Grid.Rows.Add(part.Marking, part.Model, part.Category, part.Package, part.Parameters, part.Maker);
                Grid.Rows[row].Tag = part;
            }
            Count.Text = result.Count == 0 ? "没有匹配条目，可减少关键词或重置筛选。"
                : "找到 " + result.Count + " 条 / 库内 " + parts.Count + " 条 · 空格分隔多个条件，如 SL SOD123；优先显示完整丝印匹配";
            if (Grid.Rows.Count > 0) Grid.CurrentCell = Grid.Rows[0].Cells[0];
            ShowSelected();
        }

        Part SelectedPart()
        {
            return Grid.CurrentRow == null ? null : Grid.CurrentRow.Tag as Part;
        }

        void ShowSelected()
        {
            Part part = SelectedPart();
            copy.Enabled = part != null;
            Details.Text = part == null ? "输入丝印、型号、封装或参数即可实时反查。示例：A09T、LB33A、SOT-23、3.3V。" : part.CopyText();
        }

        void CopySelected()
        {
            Part part = SelectedPart();
            if (part == null) return;
            try { Clipboard.SetText(part.CopyText()); }
            catch (System.Runtime.InteropServices.ExternalException)
            { MessageBox.Show(this, "剪贴板暂时被占用，请稍后重试，或在详情框中选中文字复制。", "复制条目"); }
        }
    }

    static class Program
    {
        [STAThread]
        static void Main()
        {
            Application.EnableVisualStyles();
            Application.SetCompatibleTextRenderingDefault(false);
            try { Application.Run(new LookupForm()); }
            catch (Exception ex) { MessageBox.Show("丝印反查工具启动失败：" + ex.Message, "常见丝印反查"); }
        }
    }
}
