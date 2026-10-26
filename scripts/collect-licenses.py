# SPDX-License-Identifier: GPL-3.0-only
"""Collect actual build-environment licenses; no credentials or local paths."""
from pathlib import Path
import importlib.metadata as metadata
import json
import shutil
import sys

ROOT = Path(__file__).resolve().parents[1]
DEST = ROOT / "LICENSES"
DEST.mkdir(exist_ok=True)
python_license = Path(sys.base_prefix) / "LICENSE.txt"
if not python_license.is_file():
    raise SystemExit("Python LICENSE.txt is missing; use an official Windows CPython installation")
shutil.copyfile(python_license, DEST / "Python.txt")
# CPython's Windows license contains the terms for the Microsoft runtime.
# Keep the complete upstream text instead of reconstructing legal excerpts.
shutil.copyfile(python_license, DEST / "VC-Runtime.txt")
for name in ("Tcl.txt", "Tk.txt"):
    if not (DEST / name).is_file():
        raise SystemExit(f"Missing checked-in runtime license: {name}")
records = []
for dist in sorted(metadata.distributions(), key=lambda d: d.metadata["Name"].lower()):
    name, version = dist.metadata["Name"], dist.version
    found = []
    for item in dist.files or []:
        # Read only license/copyright files provided by distribution metadata.
        if ".dist-info/" not in str(item).replace("\\", "/"):
            continue
        if not any(word in str(item).lower() for word in ("license", "copying", "copyright", "notice")):
            continue
        source = Path(dist.locate_file(item))
        if not source.is_file():
            continue
        relative = str(item).replace("\\", "/").split(".dist-info/", 1)[1]
        target = DEST / "build-dependencies" / name / relative
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        found.append(target.relative_to(ROOT).as_posix())
        if name.lower() == "pyinstaller" and source.name == "COPYING.txt":
            shutil.copyfile(source, DEST / "PyInstaller.txt")
    records.append({"name": name, "version": version, "licenses": found})
if not (DEST / "PyInstaller.txt").is_file():
    raise SystemExit("PyInstaller license was not found")
(ROOT / "BUILD_ENVIRONMENT.json").write_text(
    json.dumps({"python": sys.version.split()[0], "platform": sys.platform, "packages": records},
               ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"Collected licenses for Python {sys.version.split()[0]} and {len(records)} build dependencies")
