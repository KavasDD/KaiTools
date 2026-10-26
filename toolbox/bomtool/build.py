# SPDX-License-Identifier: GPL-3.0-only
"""Development only: assemble the single-file Capture deliverable."""
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def build():
    output = ROOT.parent.parent / 'autoload' / 'bomtoolMenu.tcl'
    text = '\n\n'.join((ROOT / name).read_text('utf-8') for name in
                       ('core.tcl', 'recognition.tcl', 'xlsx.tcl', 'presentation.tcl', 'capture.tcl'))
    # Chinese UI strings use double quotes in Tcl; escape them so Capture's
    # system encoding cannot corrupt UTF-8 source on a GBK installation.
    text = ''.join(c if ord(c) < 128 else '\\u%04x' % ord(c) for c in text)
    output.write_text(text.rstrip() + '\n', encoding='utf-8', newline='\n')
    return output


if __name__ == '__main__':
    print(build())
