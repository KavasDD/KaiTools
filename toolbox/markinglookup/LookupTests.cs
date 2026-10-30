// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using System.Windows.Forms;

namespace XiaokaiMarking
{
    static class LookupTests
    {
        static int checks;
        static void Check(bool valid, string message)
        {
            if (!valid) throw new Exception(message);
            checks++;
        }
        [STAThread]
        static int Main(string[] args)
        {
            try
            {
                var parts = Catalog.Load();
                string[] markings = { "GA", "GB", "GD", "GG", "GJ", "GK", "GM", "LB33A", "SL", "2YL6",
                    "1YC", "C3H", "1AM", "R25", "SR", "A4t", "A7t", "T4", "5351", "A09T", "A19T",
                    "WA", "AF", "MR", "S1A", "KZ2", "S2A", "K72", "K27", "Y1", "R1", "BCJ",
                    "SS14", "SS24", "SS34", "A2", "1P", "2F", "U3" };
                Check(parts.Count >= markings.Length + 20, "Supplied entries and online examples are in the catalog");
                foreach (string marking in markings)
                    Check(Catalog.Search(parts, marking, "", "", 1, true).Count >= 1, "Exact marking: " + marking);
                foreach (Part part in parts)
                    foreach (string field in part.Fields) Check(!String.IsNullOrWhiteSpace(field), "Entry metadata populated");
                Check(Catalog.Search(parts, "a09t", "", "", 1, true)[0].Model == "AO3400", "Case-insensitive lookup");
                Check(Catalog.Search(parts, "Ａ０９Ｔ", "", "", 1, true)[0].Model == "AO3400", "Full width input");
                Check(Catalog.Search(parts, "SL SOD123", "", "", 0, false).Count == 1, "Multiple conditions and package normalization");
                Check(Catalog.Search(parts, "lmbt2222alt1g", "", "", 2, true)[0].Marking == "1P", "Exact model alias");
                Check(Catalog.Search(parts, "SOT23-5", "", "", 0, false).Count >= 2, "Package spelling normalization");
                Check(Catalog.Search(parts, "LB33A 3.3V", "", "", 0, false)[0].Marking == "LB33A", "Parameter search");
                Check(Catalog.Search(parts, "K1N", "", "", 1, true)[0].Model.Contains("MMBT3904"), "Online example marking");
                Check(Catalog.Search(parts, "G3P", "", "", 1, true)[0].CopyText().Contains("https://www.diodes.com/assets/Datasheets/AP2112.pdf"), "Online source copied");
                Check(Catalog.Search(parts, "JJ", "", "", 1, true)[0].Model == "BAV70"
                    && Catalog.Search(parts, "KJJ", "", "", 1, true)[0].Model == "BAV70", "Exact marking aliases");
                Check(Catalog.Search(parts, "润石", "", "", 0, false).Count == 1, "Manufacturer search");
                Check(Catalog.Search(parts, "L435D", "", "", 0, false)[0].Marking == "LB33A", "Trace line searchable with context");
                Check(Catalog.Search(parts, "A7", "", "", 1, true).Count == 0, "Exact lookup does not include suffix");
                Check(Catalog.Search(parts, "A7", "", "", 1, false)[0].Model == "BAV99W", "Partial marking search");
                Check(Catalog.Search(parts, "SL", "MOS 管 / N 沟道", "", 0, false).Count == 0, "Category condition intersects search");
                Check(Catalog.Search(parts, "", "", "SOD-323", 0, false).Count == 2, "Package filter");
                Check(Catalog.Search(parts, "no-such-part", "", "", 0, false).Count == 0, "No matches");
                var duplicates = new List<Part>(parts);
                duplicates.Add(new Part { Marking="SL", Model="另一个候选", Category="二极管 / 肖特基", Package="SOD-123",
                    Maker="其他厂商", Parameters="待核对", Notes="同码候选" });
                Check(Catalog.Search(duplicates, "SL", "", "", 1, true).Count == 2, "Same marking retains multiple candidates");
                Check(Catalog.Search(parts, "C3H", "", "", 1, true)[0].Notes.Contains("不能确认"), "Uncertain trace code identified");

                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                using (var form = new LookupForm())
                {
                    form.ShowInTaskbar = false;
                    form.Show(); Application.DoEvents();
                    Check(form.Grid.Rows.Count == parts.Count, "Initial rows");
                    form.Query.Text = "a09t"; Application.DoEvents();
                    Check(form.Grid.Rows.Count == 1 && form.Details.Text.Contains("AO3400"), "Live search updates selection and details");
                    form.Category.SelectedItem = "三极管 / NPN"; Application.DoEvents();
                    Check(form.Grid.Rows.Count == 0 && form.Count.Text.Contains("没有匹配"), "Empty state after category filter");
                    form.ResetFilters(); Application.DoEvents();
                    Check(form.Grid.Rows.Count == parts.Count, "Reset restores catalog");
                    form.Field.SelectedIndex=1; form.Exact.Checked=true; form.Query.Text="1P"; Application.DoEvents();
                    Check(form.Grid.Rows.Count == 1 && form.Details.Text.Contains("LMBT2222ALT1G"), "Exact marking UI and aliases");
                    form.ResetFilters(); form.Package.SelectedItem="SOD-323"; Application.DoEvents();
                    Check(form.Grid.Rows.Count == 2, "Package selector UI");
                    form.ResetFilters();
                    foreach (Size size in new[] { new Size(920, 640), new Size(1280, 840) })
                    {
                        form.Size=size; Application.DoEvents();
                        Rectangle grid = form.RectangleToClient(form.Grid.RectangleToScreen(form.Grid.ClientRectangle));
                        Rectangle details = form.RectangleToClient(form.Details.RectangleToScreen(form.Details.ClientRectangle));
                        Check(form.Grid.Height > 110 && grid.Bottom < details.Top, "Grid remains usable at " + size);
                        Check(details.Bottom < form.ClientSize.Height && form.Query.Width > 300, "Search and details remain in view");
                    }
                    if (args.Length > 0)
                    {
                        form.Size = new Size(1180, 800); Application.DoEvents();
                        using (var bitmap = new Bitmap(form.Width, form.Height))
                        { form.DrawToBitmap(bitmap, new Rectangle(Point.Empty, bitmap.Size)); bitmap.Save(args[0]); }
                    }
                    form.Close();
                }
                Console.WriteLine("PASS: " + checks + " catalog, search and WinForms checks");
                return 0;
            }
            catch (Exception ex) { Console.Error.WriteLine(ex); return 1; }
        }
    }
}
