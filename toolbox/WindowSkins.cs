// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.IO;
using System.Reflection;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace XiaokaiAppearance
{
    sealed class Skin
    {
        public readonly string Id, Name;
        public readonly Color Background, Surface, Header, Text, Muted, Accent, Border;
        public Skin(string id, string name, string background, string surface, string header,
            string text, string muted, string accent, string border)
        {
            Id = id; Name = name; Background = C(background); Surface = C(surface); Header = C(header);
            Text = C(text); Muted = C(muted); Accent = C(accent); Border = C(border);
        }
        static Color C(string hex) { return ColorTranslator.FromHtml(hex); }
        public override string ToString() { return Name; }
    }

    static class Skins
    {
        public static readonly Skin[] All = {
            new Skin("toolbox-b", "静谧流光", "#111B2B", "#1C2C3E", "#263C50", "#EEF4FA", "#ACBDCD", "#84BCD9", "#3E556D"),
            new Skin("orcad-a", "蓝白图纸", "#F3F8FF", "#FFFFFF", "#E5EFFD", "#193352", "#5B7290", "#2563CE", "#CBDCF2"),
            new Skin("allegro-a", "赤焰走线", "#121216", "#1B1C24", "#30212A", "#F6EEF1", "#BCA6AF", "#F15366", "#52303D"),
        };
        static readonly Dictionary<string, Image> Artwork = new Dictionary<string, Image>();
        public static Skin Selected(string host)
        {
            foreach (Skin skin in All) if (skin.Id.StartsWith(host + "-", StringComparison.Ordinal)) return skin;
            throw new ArgumentException("Unknown window host");
        }
        public static Image Art(Skin skin)
        {
            Image image;
            if (!Artwork.TryGetValue(skin.Id, out image)) {
                using (Stream source = Assembly.GetExecutingAssembly().GetManifestResourceStream("skin." + skin.Id + ".png")) {
                    if (source == null) return null;
                    using (Image decoded = Image.FromStream(source)) image = new Bitmap(decoded);
                }
                Artwork[skin.Id] = image;
            }
            return image;
        }
        public static Bitmap Render(Skin skin, Size size)
        {
            var image = new Bitmap(Math.Max(1, size.Width), Math.Max(1, size.Height), System.Drawing.Imaging.PixelFormat.Format32bppPArgb);
            using (Graphics graphics = Graphics.FromImage(image)) {
                graphics.Clear(skin.Background);
                Image art = Art(skin);
                if (art != null) {
                    graphics.InterpolationMode = InterpolationMode.HighQualityBicubic;
                    if (skin.Id.StartsWith("toolbox-", StringComparison.Ordinal)) {
                        using (var attributes = new System.Drawing.Imaging.ImageAttributes()) {
                            var matrix = new System.Drawing.Imaging.ColorMatrix(); matrix.Matrix33 = 0.28f;
                            attributes.SetColorMatrix(matrix);
                            graphics.DrawImage(art, new Rectangle(Point.Empty, image.Size), 0, 0, art.Width, art.Height, GraphicsUnit.Pixel, attributes);
                        }
                        var fade = new Rectangle(0, 0, Math.Max(1, image.Width * 3 / 4), image.Height);
                        using (var brush = new LinearGradientBrush(fade, skin.Background, Color.FromArgb(0, skin.Background), LinearGradientMode.Horizontal))
                            graphics.FillRectangle(brush, fade);
                    } else graphics.DrawImage(art, new Rectangle(Point.Empty, image.Size));
                }
            }
            return image;
        }
    }

    // Shared by the launcher and Allegro's companion windows.
    class SkinForm : Form
    {
        protected readonly string SkinHost;
        protected Skin CurrentSkin;
        public SkinForm(string host)
        {
            SkinHost = host; DoubleBuffered = true; CurrentSkin = Skins.Selected(host);
            Activated += delegate { RefreshSkin(); };
        }
        protected override void OnPaintBackground(PaintEventArgs e)
        {
            e.Graphics.Clear(CurrentSkin.Background); Image image = Skins.Art(CurrentSkin);
            if (image != null) e.Graphics.DrawImage(image, ClientRectangle);
        }
        protected override void OnShown(EventArgs e) { base.OnShown(e); RefreshSkin(); }
        public void RefreshSkin()
        {
            CurrentSkin = Skins.Selected(SkinHost); BackColor = CurrentSkin.Background; ForeColor = CurrentSkin.Text;
            ApplyControls(this); Invalidate(true);
        }
        void ApplyControls(Control parent)
        {
            foreach (Control control in parent.Controls) {
                control.ForeColor = CurrentSkin.Text;
                if (control is Label || control is CheckBox) control.BackColor = Color.Transparent;
                else control.BackColor = CurrentSkin.Surface;
                var tree = control as TreeView;
                if (tree != null) { tree.LineColor = CurrentSkin.Border; tree.BorderStyle = BorderStyle.FixedSingle; }
                var button = control as Button;
                if (button != null) { button.FlatStyle = FlatStyle.Flat; button.FlatAppearance.BorderColor = CurrentSkin.Border; }
                if (control.Tag as string == "primary") {
                    control.BackColor = CurrentSkin.Accent; control.ForeColor = CurrentSkin.Background;
                }
                ApplyControls(control);
            }
        }
    }
}
