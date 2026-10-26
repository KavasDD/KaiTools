# SPDX-License-Identifier: GPL-3.0-only
# -*- coding: utf-8 -*-
"""立创商城参数抓取与字段映射（只用 Python 标准库）。

    fetch(code)                 -> dict  抽平后的产品信息
    map_to_fields(info, fields) -> dict  映射到 schema 字段的填充结果

物料类型由用户在左边自己选，这里不做猜测。

命令行自检：
    python app/lcsc.py C17414
"""
import io
import json
import re
import ssl
import sys
import unicodedata
import urllib.error
import urllib.request

TIMEOUT = 12
UA = ('Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/122.0 Safari/537.36')

# 立创详情接口换过几次，按顺序尝试，先成功者胜出。
ENDPOINTS = [
    'https://wmsc.lcsc.com/wmsc/product/detail?productCode={code}',
    'https://wmsc.lcsc.com/ftps/wm/product/detail?productCode={code}',
    'https://item.szlcsc.com/api/product/detail?productCode={code}',
]
CODE_RE = re.compile(r'C\d{3,10}', re.I)


def norm(s):
    """NFC 归一化：折叠 CJK 兼容汉字，同时保留全角标点、Ω、℃。"""
    return unicodedata.normalize('NFC', str(s or '')).strip()


def clean_code(s):
    """从编号或商品链接里取出 C 编号。

    支持 'C17414' / 'c17414' / 'https://item.szlcsc.com/17414.html'
    （商品链接里的数字 ID 没有 C 前缀，要单独补上）。
    """
    s = norm(s)
    m = CODE_RE.search(s)
    if m:
        return m.group(0).upper()
    m = re.search(r'szlcsc\.com/(?:product/detail/)?(\d{3,10})', s, re.I)
    return 'C' + m.group(1) if m else ''

def _get_json(url):
    req = urllib.request.Request(url, headers={
        'User-Agent': UA,
        'Accept': 'application/json, text/plain, */*',
        'Accept-Language': 'zh-CN,zh;q=0.9',
        'Referer': 'https://www.szlcsc.com/',
    })
    ctx = ssl.create_default_context()
    with urllib.request.urlopen(req, timeout=TIMEOUT, context=ctx) as r:
        body = r.read().decode('utf-8', 'replace')
    return json.loads(body)


def _unwrap(payload):
    """接口有时把产品对象包在 result / data 里。"""
    if not isinstance(payload, dict):
        return {}
    for key in ('result', 'data'):
        inner = payload.get(key)
        if isinstance(inner, dict) and inner:
            return inner
    return payload


def _params(prod):
    """把参数列表抽平成 {参数名: 参数值}。"""
    out = {}
    for key in ('paramVOList', 'productParamList', 'paramList'):
        for item in prod.get(key) or []:
            if not isinstance(item, dict):
                continue
            name = norm(item.get('paramNameZh') or item.get('paramName')
                        or item.get('paramNameEn'))
            val = norm(item.get('paramValueZh') or item.get('paramValue')
                       or item.get('paramValueEn'))
            if name and val and val not in ('-', '—', 'null'):
                out.setdefault(name, val)
    return out

def fetch(code):
    """抓取一个 C 编号。返回 dict，失败时抛 RuntimeError。"""
    code = clean_code(code)
    if not code:
        raise RuntimeError('请输入立创编号，例如 C17414')
    errors = []
    for tpl in ENDPOINTS:
        try:
            prod = _unwrap(_get_json(tpl.format(code=code)))
        except (urllib.error.URLError, urllib.error.HTTPError, OSError,
                ValueError, TimeoutError) as e:
            errors.append(f'{tpl.split("/")[2]}: {e}')
            continue
        if not prod.get('productCode') and not prod.get('productModel'):
            errors.append(f'{tpl.split("/")[2]}: 返回内容里没有产品信息')
            continue
        return {
            'code': norm(prod.get('productCode')) or code,
            'model': norm(prod.get('productModel')),
            'brand': norm((prod.get('brandNameZh') or prod.get('brandName')
                           or prod.get('brandNameEn'))),
            'encap': norm(prod.get('encapStandard')),
            # 分类名只剩一个用处：推断贴片/直插（_mount_type）。
            'catalog': norm(prod.get('catalogName') or prod.get('parentCatalogName')),
            'params': _params(prod),
            # 注意：不能用 item.szlcsc.com/<去掉C的数字>.html，那个数字是站内
            # 另一套 id，拼出来是别的产品（实测 C1525 会指到一个贴片电阻）。
            'url': f'https://www.lcsc.com/product-detail/{code}.html',
        }
    raise RuntimeError('抓取失败（可能是无法联网或编号不存在）：' + '；'.join(errors[:3]))

# schema 字段标签 -> 立创参数名候选（按优先级）。标签先去掉"（可选）"再查。
ALIASES = {
    '供应商型号': ['型号', '产品型号', '厂家型号'],
    '品牌': ['品牌', '厂家', '制造商'],
    '封装/尺寸': ['封装', '封装规格', '尺寸', '外形尺寸'],
    '阻值': ['电阻', '阻值', '电阻值'],
    '容值': ['电容', '容值', '电容值'],
    '感值': ['电感', '感值', '电感值'],
    '误差': ['精度', '误差', '容差', '阻值精度', '容值精度', '电感精度'],
    '额定功率': ['功率', '额定功率'],
    '额定电压': ['额定电压', '电压', '耐压'],
    '耐压值': ['额定电压', '耐压', '电压'],
    '温度系数': ['温度系数'],
    '材质': ['材质', '介质材料', '介质'],
    '工作环境温度': ['工作温度', '温度范围', '工作温度范围'],
    '包装方式': ['包装', '包装方式'],
    '颜色': ['颜色', '发光颜色'],
    '电流': ['电流', '额定电流'],
    '通道数': ['通道数', '路数'],
    '引脚数': ['引脚数目', '引脚数', '脚位数'],
    '间距': ['间距', '脚距', '螺距'],
    '正向电压': ['正向电压', '正向压降'],
    '反向电压': ['反向电压', '反向耐压'],
    '频率': ['频率', '标称频率'],
    '接口类型': ['接口类型', '接口'],
    '安装类型': ['安装类型', '类型'],
}
# 判断贴片/直插用的兜底关键词
SMD_HINTS = ('smd', 'smt', '贴片', '表面贴装', 'qfn', 'bga', 'sop', 'qfp',
             'sot', 'dfn', 'lga', 'csp', 'lqfp', 'tqfp', 'ssop', 'msop')
DIP_HINTS = ('dip', '直插', '插件', 'through hole', 'tht', 'to-', 'plug')

def base_label(label):
    """去掉"（可选）"等括号补充，得到用于匹配的主标签。"""
    s = re.sub(r'[（(][^）)]*[）)]', '', norm(label))
    return s.strip()


def _squash(s):
    return re.sub(r'[\s\-_/]', '', norm(s)).lower()


SI = {'p': 1e-12, 'n': 1e-9, 'u': 1e-6, 'μ': 1e-6, 'µ': 1e-6, 'm': 1e-3,
      'k': 1e3, 'K': 1e3, 'M': 1e6, 'G': 1e9}
QTY_RE = re.compile(r'^([\d.]+)\s*(?:/\s*([\d.]+))?\s*([pnuμµmkKMG])?\s*'
                    r'(W|Ω|ohm|R|V|A|F|Hz|H)?$', re.I)


DASHES = '‐‑‒–—―−－'   # 各种连字符/减号/负号
TEMP_RE = re.compile(r'([+-]?\d+)\s*(?:°?\s*C|℃|摄氏度)?\s*'
                     r'(?:~|～|to|至|-|—)\s*'
                     r'([+-]?\d+)\s*(?:°?\s*C|℃|摄氏度)?')


def _temp_range(s):
    """解析温度区间，返回 (低, 高)，解析不了返回 None。

    表格写 '–40°C to +85°C'（U+2013 短横 + °C），立创写 '-40℃~+85℃'，
    是同一个区间，要能对上，否则每次都得手动重选下拉。
    """
    t = norm(s)
    for d in DASHES:                 # 统一成 ASCII 减号再解析
        t = t.replace(d, '-')
    t = re.sub(r'\s+', ' ', t)
    m = TEMP_RE.search(t)
    if not m:
        return None
    try:
        return int(m.group(1)), int(m.group(2))
    except ValueError:
        return None


def _qty(s):
    """把 '125mW' / '1/8W' / '10kΩ' 解析成 (数值, 单位)，解析不了返回 None。

    立创用 mW、kΩ 这类写法，表格里用 1/8W 这类分数写法，两边要能对上。
    """
    t = re.sub(r'[\s,]', '', norm(s))
    m = QTY_RE.match(t)
    if not m:
        return None
    num, den, prefix, unit = m.groups()
    try:
        val = float(num) / float(den) if den else float(num)
    except (ValueError, ZeroDivisionError):
        return None
    if prefix:
        val *= SI.get(prefix, SI.get(prefix.lower(), 1))
    return val, (unit or '').upper().replace('OHM', 'Ω').replace('R', 'Ω')


def _snap(value, options):
    """把抓到的值贴到下拉选项上。返回 (值, 是否命中选项)。"""
    if not options:
        return value, True
    sv = _squash(value)
    for o in options:
        if _squash(o) == sv:
            return o, True
    tv = _temp_range(value)         # 温度区间等值，如 -40℃~+85℃ == –40°C to +85°C
    if tv:
        for o in options:
            if _temp_range(o) == tv:
                return o, True
    qv = _qty(value)                # 数量等值，如 125mW == 1/8W
    if qv:
        for o in options:
            qo = _qty(o)
            if qo and qo[1] == qv[1] and abs(qo[0] - qv[0]) <= abs(qv[0]) * 1e-6:
                return o, True
    for o in options:               # 互为子串，如 "SMD" ⊂ "SMD贴片"
        so = _squash(o)
        if so and sv and (so in sv or sv in so):
            return o, True
    for hints, tag in ((SMD_HINTS, 'SMD'), (DIP_HINTS, 'DIP')):
        if any(h in sv for h in hints):
            for o in options:
                if _squash(tag) in _squash(o):
                    return o, True
    return value, False


def _mount_type(info):
    """从封装/分类文字推断贴片还是直插。"""
    blob = _squash(' '.join([info.get('encap', ''), info.get('catalog', ''),
                             info['params'].get('安装类型', '')]))
    if any(h in blob for h in SMD_HINTS):
        return 'SMD'
    if any(h in blob for h in DIP_HINTS):
        return 'DIP'
    return ''

def _candidates(base, info):
    """按优先级给出这个标签可能的取值来源。"""
    p = info['params']
    out = []
    if base in p:
        out.append(p[base])
    for alias in ALIASES.get(base, []):
        if alias in p:
            out.append(p[alias])
    if base in ('供应商型号', '型号') and info.get('model'):
        out.append(info['model'])
    if base == '品牌' and info.get('brand'):
        out.append(info['brand'])
    if base in ('封装/尺寸', '封装', '尺寸') and info.get('encap'):
        out.append(info['encap'])
    if not out:                      # 兜底：参数名互为子串
        sb = _squash(base)
        for name, val in p.items():
            sn = _squash(name)
            if sn and sb and (sb in sn or sn in sb):
                out.append(val)
                break
    return out


def map_to_fields(info, fields):
    """把抓取结果映射到 schema 字段。

    返回 {'values': {标签: 值}, 'fuzzy': [标签], 'unmapped': {参数名: 值}}
    fuzzy 里的值没落在下拉选项上，界面上要提示用户确认。
    """
    values, fuzzy, used = {}, [], set()
    for f in fields:
        label = f['label']
        # 查别名表用表格里的原栏位名：用户把栏位改名了（origLabel 会记下原名），
        # 别名表还是按原名写的，拿改后的名字去查一个都对不上，这一栏就再也
        # 填不进值了。返回的键仍用现在的 label，界面是按它对号入座的。
        base = base_label(f.get('origLabel') or label)
        # 物料名称现在也是固定值（就是子分类名），一并跳过
        if f['kind'] == 'fixed':
            continue
        if base == '封装形式':
            mt = _mount_type(info)
            if mt:
                snapped, ok = _snap(mt, f.get('options') or [])
                values[label] = snapped
                if not ok:
                    fuzzy.append(label)
            continue
        for cand in _candidates(base, info):
            if not cand:
                continue
            snapped, ok = _snap(cand, f.get('options') or [])
            values[label] = snapped
            if not ok:
                fuzzy.append(label)
            for name, val in info['params'].items():
                if val == cand:
                    used.add(name)
            break
    unmapped = {k: v for k, v in info['params'].items() if k not in used}
    return {'values': values, 'fuzzy': fuzzy, 'unmapped': unmapped}


if __name__ == '__main__':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')
    arg = sys.argv[1] if len(sys.argv) > 1 else 'C17414'
    try:
        got = fetch(arg)
    except RuntimeError as exc:
        print('FAIL:', exc)
        sys.exit(1)
    print(json.dumps(got, ensure_ascii=False, indent=2))
