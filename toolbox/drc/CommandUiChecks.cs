using System;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Threading.Tasks;
using System.Windows.Forms;

class CommandUiChecks
{
    const BindingFlags Flags = BindingFlags.Instance | BindingFlags.NonPublic;
    static T Field<T>(object target, string name) { return (T)target.GetType().GetField(name, Flags).GetValue(target); }
    static void Check(bool ok, string message) { if (!ok) throw new Exception(message); }
    static void Act(Form form, string action)
    {
        var task = (Task)form.GetType().GetMethod("Act", Flags).Invoke(form, new object[] { action });
        var deadline = DateTime.UtcNow.AddSeconds(10);
        while (!task.IsCompleted && DateTime.UtcNow < deadline) { Application.DoEvents(); Thread.Sleep(10); }
        Check(task.IsCompleted, "UI operation timed out"); task.GetAwaiter().GetResult(); Application.DoEvents();
    }
    [STAThread] static int Main(string[] args)
    {
        try {
            Application.EnableVisualStyles();
            var assembly = Assembly.LoadFile(Path.GetFullPath(args[0]));
            var settingsType = assembly.GetType("AiBridge").GetNestedType("SharedSettings", BindingFlags.NonPublic);
            using (var form = (Form)Activator.CreateInstance(settingsType, true)) {
                form.Show(); Application.DoEvents();
                Field<TextBox>(form, "endpoint").Text = args[1]; Field<TextBox>(form, "key").Text = "dummy-ui-key";
                Act(form, "获取模型");
                var model = Field<ComboBox>(form, "model");
                Check(model.Items.Count == 2 && model.Items[0].ToString() == "fixture-model", "Fetched model dropdown");
                model.SelectedIndex = 0; Act(form, "保存");
                Check(Field<TextBox>(form, "key").Text == "********", "Saved key marker stays visible");
                Check(Field<TextBox>(form, "key").UseSystemPasswordChar, "Key field is masked");
                Field<TextBox>(form, "key").Clear(); Act(form, "保存");
                Check(Field<TextBox>(form, "key").Text == "********", "Blank input retains saved key");
                foreach (Control c in form.Controls) Check(c.Bounds.Bottom <= form.ClientSize.Height, "Settings layout fits");
                using (var image = new Bitmap(form.Width, form.Height)) { form.DrawToBitmap(image, new Rectangle(Point.Empty, image.Size)); image.Save(args[2]); }
            }
            using (var form = (Form)Activator.CreateInstance(settingsType, true)) {
                Check(Field<TextBox>(form, "key").Text == "********", "Reopen preserves key marker");
                Check(Field<ComboBox>(form, "model").Text == "fixture-model", "Reopen preserves selected model");
            }
            Console.WriteLine("PASS: real shared settings UI, fetched dropdown, visible masked key, blank retains key, reopen, layout screenshot"); return 0;
        } catch(Exception ex) { Console.WriteLine(ex); return 1; }
    }
}
