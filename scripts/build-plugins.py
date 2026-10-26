# SPDX-License-Identifier: GPL-3.0-only
"""Rebuild all generated Capture scripts from the corresponding source."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
for component in ("bomtool", "drc", "textaffix"):
    subprocess.run([sys.executable, str(ROOT / "toolbox" / component / "build.py")], check=True)
text = "\n\n".join((ROOT / "dev" / name).read_text("utf-8-sig") for name in ("core.tcl", "capture.tcl"))
# All non-ASCII characters in this plugin's source are comments; UI text is
# already expressed as Tcl Unicode escapes for Capture's GBK source encoding.
assert text.isascii(), "lceda2orcad sources must remain ASCII-safe"
output = ROOT / "autoload/lceda2orcadMenu.tcl"
output.write_text(text.rstrip() + "\n", encoding="ascii", newline="\n")
print(output)
