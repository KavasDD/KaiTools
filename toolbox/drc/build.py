# SPDX-License-Identifier: GPL-3.0-only
"""Development only; deployed plugin needs only Capture's own Tcl runtime."""
from pathlib import Path
import base64

ROOT = Path(__file__).resolve().parent

def build():
    text = '\n\n'.join((ROOT / name).read_text('utf-8') for name in ('core.tcl', 'presentation.tcl', 'capture.tcl', 'netlist.tcl', 'ui.tcl'))
    # Preserve Unicode in both quoted UI strings and braced HTML templates,
    # regardless of Capture's system source encoding (e.g. GBK).
    payload = base64.b64encode(text.encode('utf-8')).decode('ascii')
    text = '# Xiaokai Capture native DRC; namespace ::xiaokai::drc\n' + \
        'namespace eval :: [encoding convertfrom utf-8 [binary decode base64 {' + payload + '}]]'
    output = ROOT.parent.parent / 'autoload' / 'drctoolMenu.tcl'
    output.write_text(text + '\n', encoding='ascii', newline='\n')
    return output

if __name__ == '__main__':
    print(build())
