// SPDX-License-Identifier: GPL-3.0-only
// Capture 17.4 reserves Escape before custom accelerators are dispatched.
// This windowless helper watches Escape only while Capture owns foreground.
// Its redirected input keeps its lifetime tied to the plugin's open pipe.
using System;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;

internal static class EscapeWatcher
{
    [DllImport("user32.dll")] static extern short GetAsyncKeyState(int key);
    [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr window, out uint process);
    static volatile bool stopped;

    [STAThread]
    static int Main(string[] args)
    {
        int owner;
        if (args.Length != 1 || !int.TryParse(args[0], out owner)) return 2;
        try
        {
            Process capture = Process.GetProcessById(owner);
            Thread input = new Thread(delegate()
            {
                try { Console.In.ReadLine(); } catch { }
                stopped = true;
            });
            input.IsBackground = true;
            input.Start();
            bool wasDown = (GetAsyncKeyState(27) & 0x8000) != 0;
            while (!stopped && !capture.HasExited)
            {
                uint foreground;
                GetWindowThreadProcessId(GetForegroundWindow(), out foreground);
                short state = GetAsyncKeyState(27);
                bool down = (state & 0x8000) != 0;
                if (foreground == (uint)owner && !wasDown && (down || (state & 1) != 0))
                {
                    Console.Out.WriteLine("ESC");
                    Console.Out.Flush();
                    return 0;
                }
                wasDown = down;
                Thread.Sleep(15);
            }
            return 0;
        }
        catch { return 1; }
    }
}
