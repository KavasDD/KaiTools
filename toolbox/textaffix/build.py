# SPDX-License-Identifier: GPL-3.0-only
"""Build the single-file plugin; Capture itself needs no Python."""
import base64
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parent
helper = ROOT / "test-output" / "textaffixKeys.exe"
helper.parent.mkdir(exist_ok=True)
csc = Path("C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe")
subprocess.run([str(csc), "/nologo", "/target:winexe", "/optimize+",
                "/out:" + str(helper), str(ROOT / "EscapeWatcher.cs")], check=True)
payload = "\n\n".join((ROOT / name).read_text("utf-8") for name in ("core.tcl", "capture.tcl", "ui.tcl"))
encoded = base64.b64encode(payload.encode("utf-8")).decode("ascii")
output = ROOT.parent.parent / "autoload" / "textaffixMenu.tcl"
output.write_text(
    "# Xiaokai text affix; namespace ::xiaokai::textaffix; version 1.0.1\n"
    "namespace eval ::xiaokai::textaffix {variable helperImage {"
    + base64.b64encode(helper.read_bytes()).decode("ascii") + "}}\n"
    "namespace eval :: [encoding convertfrom utf-8 [binary decode base64 {" + encoded + "}]]\n",
    encoding="ascii", newline="\n",
)
print(output)
