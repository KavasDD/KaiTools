using System;
using System.Collections.Generic;
using System.IO;

namespace XiaokaiAllegro
{
    // Shared by the launcher and installer: only the selected tools belong here.
    static class SkillFiles
    {
        public static readonly string[] Names = {
            "film_reorder.il", "Auto_artwork.il", "Quick_ColorS.il", "x_change_via_net.il",
            "Find_Component.il", "Find_DRC.il", "quick_grids.il", "quick_display.il",
            "conv.il", "highlight_padstack.il", "show_library.il", "show_height.il",
            "fTextTuneTools.il", "check_no_refdes.il", "gxl_wdzcheck_text_overlap.il", "jkcheck_refdes_cross.il", "x_silk_in_out.il", "xiaokaiTextTools.il",
            "lgs_hilight_no_fanout.il", "lgs_check_solder_to_line_V1_0.il", "quick_chSmd2ThrP.il", "find_pin_no_past.il", "find_pin_no_solder.il",
            "xiaokaiDanglings.il", "xiaokaiAllegroMenu.il", "xiaokaiAllegroHotkey.exe", "xiaokaiAiBridge.exe"
        };

        static void Add(List<string> homes, string root, bool explicitHome)
        {
            if (string.IsNullOrWhiteSpace(root)) return;
            try
            {
                root = Path.GetFullPath(Environment.ExpandEnvironmentVariables(root.Trim().Trim('"')));
                if (Path.GetFileName(root).Equals("pcbenv", StringComparison.OrdinalIgnoreCase))
                    root = Path.GetDirectoryName(root);
                if (!Directory.Exists(root)) return;
                if (!explicitHome && !Directory.Exists(Path.Combine(root, "pcbenv"))
                    && !Path.GetFileName(root).Equals("SPB_Data", StringComparison.OrdinalIgnoreCase)) return;
                if (!homes.Exists(delegate(string p) { return p.Equals(root, StringComparison.OrdinalIgnoreCase); }))
                    homes.Add(root);
            }
            catch (ArgumentException) { }
            catch (IOException) { }
            catch (UnauthorizedAccessException) { }
            catch (NotSupportedException) { }
        }

        public static List<string> FindHomes(string cadRoot)
        {
            var homes = new List<string>();
            Add(homes, Environment.GetEnvironmentVariable("HOME"), true);
            Add(homes, Environment.GetEnvironmentVariable("USERPROFILE"), false);
            if (!string.IsNullOrEmpty(cadRoot)) Add(homes, Path.Combine(cadRoot, "SPB_Data"), false);
            foreach (string key in new[] { "CDS_INST_DIR", "CDSROOT", "SPB_17_4", "SPB_17_2", "SPB_16_6" })
            {
                string value = Environment.GetEnvironmentVariable(key);
                if (string.IsNullOrWhiteSpace(value)) continue;
                try { Add(homes, Path.Combine(Path.GetDirectoryName(value.TrimEnd('\\', '/')), "SPB_Data"), false); }
                catch (ArgumentException) { }
            }
            foreach (DriveInfo drive in DriveInfo.GetDrives())
            {
                if (!drive.IsReady || drive.DriveType != DriveType.Fixed) continue;
                foreach (string relative in new[] { @"Cadence\SPB_Data", @"orcad\Cadence\SPB_Data",
                    @"Program Files\Cadence\SPB_Data", @"Program Files (x86)\Cadence\SPB_Data" })
                    Add(homes, Path.Combine(drive.RootDirectory.FullName, relative), false);
            }
            return homes;
        }

        public static bool Enabled(string pcbEnv, params string[] dependencies)
        {
            try
            {
                string init = Path.Combine(pcbEnv, "allegro.ilinit");
                if (!File.Exists(init)) return false;
                string text = File.ReadAllText(init);
                int begin = text.IndexOf("; BEGIN XIAOKAI ALLEGRO SELECTED TOOLS", StringComparison.Ordinal);
                int end = text.IndexOf("; END XIAOKAI ALLEGRO SELECTED TOOLS", StringComparison.Ordinal);
                if (begin < 0 || end <= begin) return false;
                string block = text.Substring(begin, end - begin);
                foreach (string file in dependencies)
                    if (!File.Exists(Path.Combine(pcbEnv, file)) ||
                        (file.EndsWith(".il") && block.IndexOf("/" + file + "\"", StringComparison.OrdinalIgnoreCase) < 0))
                        return false;
                return true;
            }
            catch (IOException) { return false; }
            catch (UnauthorizedAccessException) { return false; }
        }
    }
}
