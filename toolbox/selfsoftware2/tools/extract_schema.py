# SPDX-License-Identifier: GPL-3.0-only
"""Extract the component-classification schema from the source .xlsx into schema.json.

Layout of the source sheet (single sheet, column A = row index within a category):
  * category row : text only in column A, e.g. "1.1无源元件-电阻（贴片电阻、...）"
  * header row   : column A empty, column B == "物料名称"; columns B.. are field labels
  * data row     : column A = number, column B = 物料名称 value; column Q = the
                   expected standard description (all non-empty fields joined by "，")
A header row applies to every data row that follows it until the next header/category row.

Field kind is derived from the cell fill of the example row plus data validations:
  green  FF92D050 -> fixed value (not editable)
  blue   FF00B0F0 -> choose from a list
  a <dataValidation type="list"> on the cell supplies the actual options
"""
import json
import re
import sys
import unicodedata
import zipfile
from xml.etree import ElementTree as ET

M = '{http://schemas.openxmlformats.org/spreadsheetml/2006/main}'
GREEN, BLUE = 'FF92D050', 'FF00B0F0'
DESC_COL = 16               # column Q
PLACEHOLDERS = {'*', '**', '***', '*********', '/', '**********'}

# Known source typos: labels that appear in a header row but are not real fields.
# 'AVX' is a capacitor brand name that landed in the 固态电容 header (row 22,
# category 1.2) between 颜色（可选） and 品牌. Its data cells are empty, so it
# contributes nothing to the description; dropping it is safe and keeps the
# generated form from showing a meaningless input.
DROP_LABELS = {'AVX'}
CAT_RE = re.compile(r'^(\d+(?:\.\d+)?)\s*(.*)$', re.S)


def norm(s):
    """The workbook contains CJK compatibility ideographs (e.g. U+F9BE for 料).
    NFC folds those to their normal form without touching full-width punctuation."""
    return unicodedata.normalize('NFC', s or '')


def col_to_idx(ref):
    n = 0
    for ch in re.match(r'([A-Z]+)', ref).group(1):
        n = n * 26 + (ord(ch) - 64)
    return n - 1


def idx_to_col(i):
    s = ''
    i += 1
    while i:
        i, r = divmod(i - 1, 26)
        s = chr(65 + r) + s
    return s


def load_shared_strings(z):
    try:
        root = ET.fromstring(z.read('xl/sharedStrings.xml'))
    except KeyError:
        return []
    return [norm(''.join(t.text or '' for t in si.iter(M + 't')))
            for si in root.findall(M + 'si')]


def load_fill_map(z):
    """style index -> fill rgb (upper-case) or ''."""
    st = ET.fromstring(z.read('xl/styles.xml'))
    fills = []
    for f in st.find(M + 'fills'):
        pf = f.find(M + 'patternFill')
        rgb = ''
        if pf is not None and pf.get('patternType') == 'solid':
            fg = pf.find(M + 'fgColor')
            if fg is not None and fg.get('rgb'):
                rgb = fg.get('rgb').upper()
        fills.append(rgb)
    out = []
    for xf in st.find(M + 'cellXfs'):
        fid = int(xf.get('fillId') or 0)
        out.append(fills[fid] if fid < len(fills) else '')
    return out


def expand_sqref(sqref):
    """'C7 D9:D11' -> ['C7', 'D9', 'D10', 'D11']"""
    cells = []
    for part in sqref.split():
        if ':' not in part:
            cells.append(part)
            continue
        a, b = part.split(':')
        c1, r1 = col_to_idx(a), int(re.search(r'\d+', a).group())
        c2, r2 = col_to_idx(b), int(re.search(r'\d+', b).group())
        for c in range(min(c1, c2), max(c1, c2) + 1):
            for r in range(min(r1, r2), max(r1, r2) + 1):
                cells.append(f'{idx_to_col(c)}{r}')
    return cells


def load_validations(raw):
    """cell ref -> list of options (inline "a,b,c" lists only)."""
    out = {}
    for blk in re.findall(r'<dataValidation\b[^>]*?(?:/>|>.*?</dataValidation>)', raw, re.S):
        if 'type="list"' not in blk:
            continue
        sq = re.search(r'sqref="([^"]+)"', blk)
        f1 = re.search(r'<formula1>(.*?)</formula1>', blk, re.S)
        if not sq or not f1:
            continue
        formula = f1.group(1).strip()
        formula = formula.replace('&quot;', '"').replace('&amp;', '&')
        if not (formula.startswith('"') and formula.endswith('"')):
            continue        # a range reference; no inline options to read
        opts = [norm(o).strip() for o in formula[1:-1].split(',') if o.strip()]
        if not opts:
            continue
        for ref in expand_sqref(sq.group(1)):
            out[ref] = opts
    return out


def read_rows(raw, sst, fillmap):
    """row number -> {col idx: {'v': text, 'fill': rgb}}"""
    root = ET.fromstring(raw)
    sd = root.find(M + 'sheetData')
    rows = {}
    if sd is None:
        return rows
    for row in sd.findall(M + 'row'):
        cells = {}
        for c in row.findall(M + 'c'):
            ref = c.get('r')
            if not ref:
                continue
            t, s = c.get('t'), int(c.get('s') or 0)
            if t == 'inlineStr':
                isn = c.find(M + 'is')
                v = ''.join(x.text or '' for x in isn.iter(M + 't')) if isn is not None else ''
            else:
                vn = c.find(M + 'v')
                v = vn.text or '' if vn is not None else ''
                if t == 's' and v:
                    v = sst[int(v)]
            cells[col_to_idx(ref)] = {
                'v': norm(v).strip(),
                'fill': fillmap[s] if s < len(fillmap) else '',
            }
        rows[int(row.get('r'))] = cells
    return rows


def text(cells, i):
    c = cells.get(i)
    return c['v'] if c else ''


def is_header(cells):
    return not text(cells, 0) and text(cells, 1) == '物料名称'


def is_category(cells):
    """Category banner: text in column A only, and it is not a plain row number."""
    a = text(cells, 0)
    if not a or re.fullmatch(r'\d+', a):
        return False
    return not text(cells, 1)


def header_fields(cells):
    """Contiguous labels from column B up to the first gap (stops before stray notes)."""
    labels = []
    i = 1
    while True:
        v = text(cells, i)
        if not v:
            break
        labels.append((i, v))
        i += 1
    return labels


def build(xlsx_path, out_path, report_path):
    with zipfile.ZipFile(xlsx_path) as z:
        sst = load_shared_strings(z)
        fillmap = load_fill_map(z)
        sheet = [n for n in z.namelist()
                 if re.match(r'xl/worksheets/sheet\d+\.xml$', n)][0]
        raw = z.read(sheet).decode('utf-8')
    validations = load_validations(raw)
    rows = read_rows(raw, sst, fillmap)

    categories, warnings = [], []
    cur_cat, cur_hdr, cur_hdr_row = None, None, None

    for rnum in sorted(rows):
        cells = rows[rnum]
        if is_category(cells):
            m = CAT_RE.match(text(cells, 0))
            code, rest = (m.group(1), m.group(2)) if m else ('', text(cells, 0))
            name = re.split(r'[（(]', rest, maxsplit=1)[0].strip()
            cur_cat = {'code': code, 'name': name or rest.strip(),
                       'raw': text(cells, 0), 'types': []}
            categories.append(cur_cat)
            cur_hdr = None
            continue
        if is_header(cells):
            cur_hdr = [(ci, lb) for ci, lb in header_fields(cells)
                       if lb.strip() not in DROP_LABELS]
            cur_hdr_row = rnum
            continue
        # data row: needs a 物料名称 in column B and a description in column Q
        name = text(cells, 1)
        desc = text(cells, DESC_COL)
        if not name or not desc:
            continue
        if cur_cat is None or cur_hdr is None:
            warnings.append(f'row {rnum}: data row with no header/category, skipped')
            continue

        fields = []
        for ci, label in cur_hdr:
            cell = cells.get(ci, {'v': '', 'fill': ''})
            ref = f'{idx_to_col(ci)}{rnum}'
            opts = validations.get(ref) or validations.get(f'{idx_to_col(ci)}{cur_hdr_row}') or []
            sample = cell['v']
            fill = cell['fill']
            if fill == GREEN:
                kind = 'fixed'
            elif opts or fill == BLUE:
                kind = 'select'
            else:
                kind = 'text'
            clean_label = label.strip()
            fields.append({
                'label': clean_label,
                'col': idx_to_col(ci),
                'kind': kind,
                'optional': '可选' in clean_label,
                'options': opts,
                'raw': sample,
                'sample': '' if sample in PLACEHOLDERS else sample,
                'fixed': sample if kind == 'fixed' else '',
            })

        # 物料名称死死钉在当前分类名上：这一栏本来就没得选，取值只能是这一行的
        # 物料名，所以直接用 name，不看表里那格填的是什么。
        # 早先是拿示例值当固定值，靠"示例值刚好等于物料名"（194 行确实都相等），
        # 但要是哪版表格这格写成占位符或空着，就会退回可手填，不该由表格决定。
        for f in fields:
            if f['label'] == '物料名称':
                f['kind'] = 'fixed'
                f['fixed'] = name
                f['raw'] = name          # 描述由 raw 拼，要一起改才对得上
                f['sample'] = name
                f['options'] = []

        # sanity check: the description is every non-empty field value joined by "，"
        gen = '，'.join(f['raw'] for f in fields if f['raw'])
        cur_cat['types'].append({
            'name': name,
            'row': rnum,
            'headerRow': cur_hdr_row,
            'fields': fields,
            'exampleDesc': desc,
            'regenDesc': gen,
        })

    schema = {
        'source': xlsx_path.replace('\\', '/').split('/')[-1],
        'separator': '，',
        'descColumn': idx_to_col(DESC_COL),
        'categories': categories,
    }
    with open(out_path, 'w', encoding='utf-8') as fh:
        json.dump(schema, fh, ensure_ascii=False, indent=1)

    # report
    ntypes = sum(len(c['types']) for c in categories)
    lines = [f'categories: {len(categories)}   component types: {ntypes}',
             f'inline dropdown cells: {len(validations)}', '']
    for w in warnings:
        lines.append('WARN ' + w)
    lines.append('')
    lines.append('--- types whose regenerated description differs from column Q ---')
    diff = 0
    for c in categories:
        for t in c['types']:
            a = re.sub(r'\s+', '', t['regenDesc'])
            b = re.sub(r'\s+', '', t['exampleDesc'])
            if a != b:
                diff += 1
                lines.append(f'[{c["code"]}] {t["name"]} (row {t["row"]})')
                lines.append(f'   Q  : {t["exampleDesc"]}')
                lines.append(f'   gen: {t["regenDesc"]}')
    lines.insert(2, f'mismatched regenerations: {diff} / {ntypes}')
    lines.append('')
    lines.append('--- field inventory ---')
    for c in categories:
        lines.append(f'[{c["code"]}] {c["name"]}  ({len(c["types"])} types)')
        for t in c['types']:
            fl = ', '.join(
                f'{f["label"]}<{f["kind"]}{"*" if f["optional"] else ""}'
                f'{":" + "/".join(f["options"]) if f["options"] else ""}>'
                for f in t['fields'])
            lines.append(f'   - {t["name"]}: {fl}')
    with open(report_path, 'w', encoding='utf-8') as fh:
        fh.write('\n'.join(lines))
    print(f'{len(categories)} categories, {ntypes} types, {diff} description mismatches')


if __name__ == '__main__':
    build(sys.argv[1], sys.argv[2], sys.argv[3])
