// SPDX-License-Identifier: GPL-3.0-only
using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Reflection;
using System.Threading;
using System.Windows.Forms;

namespace CadenceToolbox
{
    static class PerformanceChecks
    {
        [STAThread] static int Main(string[] args)
        {
            Application.SetUnhandledExceptionMode(UnhandledExceptionMode.ThrowException);
            Application.EnableVisualStyles(); Application.SetCompatibleTextRenderingDefault(false);
            Paths.Detect(); Manifest.Load(Path.Combine(Paths.Toolbox, "tools.ini"));
            using (var form = new MainForm()) {
                form.ClientSize = new Size(1200, 750); form.ShowInTaskbar = false;
                form.TopMost = true; form.Show(); form.Activate(); Application.DoEvents(); form.Refresh();
                var area = new Rectangle(form.PointToScreen(new Point(212, 40)), new Size(form.ClientSize.Width - 224, form.ClientSize.Height - 90));
                int sampling = 1, frames = 0, darkFrames = 0;
                Exception captureError = null;
                bool capture = Array.IndexOf(args, "--capture") >= 0;
                Thread recorder = null;
                if (capture) {
                    recorder = new Thread(delegate() {
                        try {
                            using (var frame = new Bitmap(area.Width, area.Height))
                            using (Graphics graphics = Graphics.FromImage(frame)) {
                                while (Interlocked.CompareExchange(ref sampling, 1, 1) == 1) {
                                    graphics.CopyFromScreen(area.Location, Point.Empty, area.Size);
                                    int dark = 0, samples = 0;
                                    for (int y = 8; y < frame.Height; y += 16)
                                        for (int x = 8; x < frame.Width; x += 16) {
                                            Color pixel = frame.GetPixel(x, y); samples++;
                                            if (pixel.R < 5 && pixel.G < 5 && pixel.B < 5) dark++;
                                        }
                                    frames++;
                                    if (dark > samples / 10) darkFrames++;
                                    Thread.Sleep(8);
                                }
                            }
                        } catch (Exception error) { captureError = error; }
                    });
                    recorder.Start();
                }
                try {
                var cats = (ListBox)typeof(MainForm).GetField("mCats", BindingFlags.Instance | BindingFlags.NonPublic).GetValue(form);
                Console.WriteLine("Version " + MainForm.Version + "; switch includes queued layout and synchronous repaint");
                for (int round = 0; round < 3; round++) {
                    for (int i = 0; i < cats.Items.Count; i++) {
                        var watch = Stopwatch.StartNew();
                        cats.SelectedIndex = i; double selected = watch.Elapsed.TotalMilliseconds;
                        Application.DoEvents(); double layout = watch.Elapsed.TotalMilliseconds;
                        form.Refresh(); Application.DoEvents();
                        watch.Stop();
                        Console.WriteLine("round={0} category={1} ms={2:F1} select={3:F1} queued={4:F1} paint={5:F1}", round, cats.Items[i], watch.Elapsed.TotalMilliseconds, selected, layout - selected, watch.Elapsed.TotalMilliseconds - layout);
                    }
                }
                } finally {
                    Interlocked.Exchange(ref sampling, 0);
                    if (recorder != null) recorder.Join();
                }
                if (capture) {
                    if (captureError != null) throw captureError;
                    Console.WriteLine("Live screen frames={0}; frames with >10% near-black samples={1}", frames, darkFrames);
                    if (frames < 5 || darkFrames != 0) throw new Exception("Black frame capture check failed");
                }
                form.Close();
            }
            return 0;
        }
    }
}
