using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

// The native toolbox belongs to a different process from the gesture helper.
// Keep the test window in a child process to reproduce that arrangement.
class GestureChecks
{
    static readonly BindingFlags Flags = BindingFlags.Static | BindingFlags.NonPublic;
    static readonly Type Target = typeof(AllegroHotkey);
    static readonly ManualResetEvent WriterEntered = new ManualResetEvent(false);
    static readonly ManualResetEvent ReleaseWriter = new ManualResetEvent(false);
    static readonly StringBuilder Messages = new StringBuilder();
    [DllImport("user32.dll")] static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] static extern void mouse_event(uint flags, uint x, uint y, uint data, UIntPtr extra);
    [DllImport("user32.dll")] static extern void keybd_event(byte key, byte scan, uint flags, UIntPtr extra);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);

    sealed class Sink : TextWriter
    {
        public override Encoding Encoding { get { return Encoding.UTF8; } }
        public override void WriteLine(string text)
        {
            WriterEntered.Set(); ReleaseWriter.WaitOne();
            lock (Messages) Messages.AppendLine(text);
        }
    }
    static void Invoke(string name, params object[] args) { Target.GetMethod(name, Flags).Invoke(null, args); }
    static void ClickTwice(int x, int y)
    {
        SetCursorPos(x, y);
        for (int i = 0; i < 2; i++) {
            mouse_event(2, 0, 0, 0, UIntPtr.Zero);
            mouse_event(4, 0, 0, 0, UIntPtr.Zero);
            Thread.Sleep(100);
        }
    }
    [STAThread] static int Main(string[] args)
    {
        if (args.Length != 0) {
            using (var window = new Form { Text = "小开 SKILL 工具箱", TopMost = true,
                Width = 550, Height = 435, Left = 700, Top = 300, StartPosition = FormStartPosition.Manual }) {
                window.Shown += delegate { Console.WriteLine((window.Left + 150) + "," + (window.Top + 140)); Console.Out.Flush(); };
                new Thread(delegate() { Console.ReadLine(); window.BeginInvoke((Action)delegate { window.Close(); }); }) { IsBackground = true }.Start();
                Application.Run(window);
            }
            return 0;
        }
        using (var child = Process.Start(new ProcessStartInfo(Application.ExecutablePath, "window") {
            UseShellExecute = false, RedirectStandardOutput = true, RedirectStandardInput = true, CreateNoWindow = true })) {
            try {
                string[] point = child.StandardOutput.ReadLine().Split(',');
                int x = int.Parse(point[0]), y = int.Parse(point[1]);
                child.Refresh(); SetForegroundWindow(child.MainWindowHandle);
                Console.Error.WriteLine("Input desktop: cursor available=" + SetCursorPos(x, y) + ", foreground=" + GetForegroundWindow());
                Target.GetField("owner", Flags).SetValue(null, child);
                var stdout = Console.Out;
                Console.SetOut(new Sink());
                new Thread(delegate() { Invoke("WriteMessages"); }) { IsBackground = true }.Start();
                Invoke("Send", "TEST");
                if (!WriterEntered.WaitOne(2000)) throw new Exception("Writer did not start.");
                var watch = Stopwatch.StartNew();
                for (int i = 0; i < 25; i++) Invoke("Send", "QUEUE");
                watch.Stop(); ReleaseWriter.Set();
                if (watch.ElapsedMilliseconds > 1000) throw new Exception("Send blocked behind IPC writer.");
                var gestures = new Thread(delegate() { Invoke("GestureLoop"); }) { IsBackground = true };
                gestures.SetApartmentState(ApartmentState.STA); gestures.Start();
                Thread.Sleep(300);
                Console.Error.WriteLine("Gesture hooks: keyboard=" + Target.GetField("hook", Flags).GetValue(null)
                    + ", mouse=" + Target.GetField("mouseHook", Flags).GetValue(null));
                ClickTwice(x, y); Thread.Sleep(300);
                lock (Messages) Messages.Clear();
                // This thread represents the helper's UI while it builds a DRC list.
                var input = new Thread(delegate() {
                    Thread.Sleep(300); ClickTwice(x, y);
                    keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x4b, 0, 0, UIntPtr.Zero);
                    keybd_event(0x4b, 0, 2, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero);
                    Thread.Sleep(2400); ClickTwice(x, y);
                });
                input.Start(); Thread.Sleep(2600); input.Join(); Thread.Sleep(300);
                Console.SetOut(stdout);
                string output; lock (Messages) output = Messages.ToString();
                int runs = output.Split(new[] { "RUN" }, StringSplitOptions.None).Length - 1;
                uint foreground; GetWindowThreadProcessId(GetForegroundWindow(), out foreground);
                Console.WriteLine("Nonblocking send elapsed: " + watch.ElapsedMilliseconds + " ms");
                Console.WriteLine("Double clicks during and after 2600 ms UI stall: " + runs);
                Console.WriteLine("Alt+K during UI stall: " + output.Contains("OPEN"));
                if (runs != 2 || !output.Contains("OPEN")) throw new Exception("Gesture lost during UI stall (foreground process " + foreground + ").");
                return 0;
            }
            finally {
                child.StandardInput.WriteLine(); child.StandardInput.Flush();
                if (!child.WaitForExit(3000)) child.Kill();
            }
        }
    }
}
