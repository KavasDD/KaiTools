# SPDX-License-Identifier: GPL-3.0-only
"""Archive tracked source plus generated license records from a CI build."""
from pathlib import Path
import subprocess
import sys
from zipfile import ZipFile, ZIP_DEFLATED

root = Path(__file__).resolve().parents[1]
names = subprocess.check_output(['git', 'ls-files', '-z'], cwd=root).decode('utf-8').split('\0')
names = set(filter(None, names))
names.update(p.relative_to(root).as_posix() for p in (root / 'LICENSES').rglob('*') if p.is_file())
commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root).decode().strip()
with ZipFile(sys.argv[1], 'w', compression=ZIP_DEFLATED) as archive:
    for name in sorted(names):
        archive.write(root / name, sys.argv[2] + '/' + name)
    archive.writestr(sys.argv[2] + '/SOURCE_REVISION.txt',
                     commit + '\nGenerated plugin and license outputs reflect this build environment.\n')
