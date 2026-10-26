# SPDX-License-Identifier: GPL-3.0-only
"""Validate generated OOXML independently using synthetic, public test data."""
from pathlib import Path
import os
import shutil
import subprocess
from zipfile import ZipFile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent
NS = {'s': 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'}


def read_book(path):
    with ZipFile(path) as archive:
        assert archive.testzip() is None
        for name in archive.namelist():
            ET.fromstring(archive.read(name))
        book = ET.fromstring(archive.read('xl/workbook.xml'))
        result = {}
        for number, sheet in enumerate(book.findall('s:sheets/s:sheet', NS), 1):
            doc = ET.fromstring(archive.read(f'xl/worksheets/sheet{number}.xml'))
            rows = []
            for row in doc.findall('s:sheetData/s:row', NS):
                values = []
                for cell in row:
                    assert cell.find('s:f', NS) is None, 'Text must never become a formula'
                    if cell.get('t') == 'inlineStr':
                        values.append(''.join(cell.find('s:is', NS).itertext()))
                    else:
                        values.append(cell.find('s:v', NS).text)
                rows.append(values)
            result[sheet.get('name')] = rows
        return result


def main():
    tclsh = os.environ.get('TCLSH') or shutil.which('tclsh')
    if not tclsh:
        raise SystemExit('Set TCLSH to a Tcl 8.6 interpreter')
    output = ROOT / 'test-output/xlsx-validation'
    output.mkdir(parents=True, exist_ok=True)
    workbook = output / 'special.xlsx'
    plugin = ROOT.parent.parent / 'autoload/bomtoolMenu.tcl'
    script = output / 'run.tcl'
    script.write_text('''encoding system utf-8
source -encoding utf-8 {%s}
set text "\\u4e2d\\u6587 & < > \\"quoted\\" \\n0402"
set path {%s}
bomtool::writeWorkbook $path [list [list Special {Text Footprint Quantity} [list [list $text 0402 2] [list {=1+1} 0603 3]] {3}]]
set before [bomtool::readText $path binary]
if {![catch {bomtool::writeWorkbook $path [list [list Limits {Text} [list [list [string repeat x 32768]]]]]}]} {error "Oversize cell accepted"}
if {$before ne [bomtool::readText $path binary]} {error "Failed export damaged previous workbook"}
puts {PASS: workbook write and atomic failure checks}
''' % (plugin.as_posix(), workbook.as_posix()), encoding='utf-8')
    subprocess.run([tclsh, str(script)], check=True)
    book = read_book(workbook)
    assert list(book) == ['Special']
    rows = book['Special']
    assert rows[0] == ['Text', 'Footprint', 'Quantity']
    assert rows[1] == ['中文 & < > "quoted" \n0402', '0402', '2']
    assert rows[2] == ['=1+1', '0603', '3']
    print('PASS: workbook CRC/XML, Unicode, leading zeros, formula safety and atomic failure')


if __name__ == '__main__':
    main()
