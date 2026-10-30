# SPDX-License-Identifier: GPL-3.0-only
"""Development only; deployed plugin needs only Capture's own Tcl runtime."""
from pathlib import Path
import base64
import hashlib
import subprocess
import json

ROOT = Path(__file__).resolve().parent

def build():
    helper = ROOT / 'test-output' / 'xiaokaiAiBridge.exe'
    helper.parent.mkdir(exist_ok=True)
    csc = Path('C:/Windows/Microsoft.NET/Framework64/v4.0.30319/csc.exe')
    pdf_runtime = ROOT / 'vendor' / 'pdf-runtime'
    pdf_dlls = sorted(pdf_runtime.glob('*.dll'))
    if not pdf_dlls:
        raise RuntimeError('Missing pinned PDF runtime; see vendor/README.md')
    hashes = json.loads((ROOT / 'vendor/runtime-sha256.json').read_text('ascii'))
    for dll in pdf_dlls:
        if hashlib.sha256(dll.read_bytes()).hexdigest() != hashes.get(dll.name):
            raise RuntimeError('PDF runtime hash mismatch: ' + dll.name)
    subprocess.run([str(csc), '/nologo', '/target:winexe', '/optimize+', '/codepage:65001',
                    '/r:System.dll', '/r:System.Core.dll', '/r:System.Drawing.dll',
                    '/r:System.Windows.Forms.dll', '/r:System.Security.dll', '/r:System.Web.Extensions.dll',
                    *('/r:' + str(p) for p in pdf_dlls),
                    *('/resource:' + str(p) + ',pdf.' + p.name for p in pdf_dlls),
                    '/resource:' + str(ROOT / 'vendor/THIRD-PARTY-NOTICES.txt') + ',pdf.NOTICES',
                    '/out:' + str(helper), str(ROOT / 'AiBridge.cs'), str(ROOT / 'Datasheets.cs'), str(ROOT / 'PanelJobs.cs'), str(ROOT / 'AiDiagnostics.cs'), str(ROOT / 'CommandAssistant.cs')], check=True)
    helper_bytes = helper.read_bytes()
    helper_name = 'xiaokaiAiBridge-' + hashlib.sha256(helper_bytes).hexdigest()[:16] + '.exe'
    text = '\n\n'.join((ROOT / name).read_text('utf-8') for name in ('core.tcl', 'presentation.tcl', 'capture.tcl', 'netlist.tcl', 'review.tcl', 'placement.tcl', 'connections.tcl', 'ai.tcl', 'datasheets.tcl', 'panels.tcl', 'ui.tcl', 'review-ui.tcl', 'commands.tcl', 'command-layout.tcl', 'command-style.tcl', 'command-labels.tcl', 'command-parts.tcl'))
    # Preserve Unicode in both quoted UI strings and braced HTML templates,
    # regardless of Capture's system source encoding (e.g. GBK).
    payload = base64.b64encode(text.encode('utf-8')).decode('ascii')
    text = '# Xiaokai Capture native DRC; namespace ::xiaokai::drc\n' + \
        'namespace eval ::xiaokai::drc {variable aiHelperName {' + helper_name + '}; variable aiHelperImage {' + base64.b64encode(helper_bytes).decode('ascii') + '}}\n' + \
        'namespace eval :: [encoding convertfrom utf-8 [binary decode base64 {' + payload + '}]]'
    output = ROOT.parent.parent / 'autoload' / 'drctoolMenu.tcl'
    output.write_text(text + '\n', encoding='ascii', newline='\n')
    return output

if __name__ == '__main__':
    print(build())
