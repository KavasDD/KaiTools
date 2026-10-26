# SPDX-License-Identifier: GPL-3.0-only
# -*- coding: utf-8 -*-
"""配置文件层：让物料名称和下拉选项可以改，不用动 Excel、不用重新打包。

为什么要这一层
--------------
schema.json 是从规格表格生成的，改它等于改生成结果，下次重新生成就没了。
所以另存一个 config.json，启动时把它盖在 schema 上。表格更新了照样重新
生成 schema，用户改过的名称和选项还在。

配置文件长这样（都可以省略，省略就是不改）：

    {
      "rename":  {"3.1": {"DC-DC电源芯片": "DC-DC 电源"}},
      "hide":    {"3.2": ["DDR SDRAM"]},
      "add":     {"3.1": [{"name": "自定义电源", "like": "线性稳压器(LDO)"}]},
      "options": {"3.1": {"*": {"工作温度": ["-40~85℃", "-40~125℃"]},
                          "DC-DC电源芯片": {"类型": ["降压", "升压"]}}},
      "labels":  {"1.1": {"*": {"阻值（单位：Ω）": "阻值"},
                          "排阻": {"误差": "阻值精度"}}}
    }

键都是分类编号（"1.1"、"3.3"），不是分类名——名字可能会改，编号不会。
options 和 labels 里的 "*" 表示这个分类下所有物料都套用，写具体物料名
就只管那一种；两个都写时具体物料名的那份优先。
labels 是改栏位名称（左边那一列的标题），里外都按表格里的原栏位名做键：
改过名之后再改一次，配置里不会堆出中间名字。
"""
import io
import json
import os
import sys
import time

# 配置文件名。放程序目录旁边，跟着文件夹一起拷走；
# 程序目录只读（Program Files、网盘）时退到用户目录。
NAME = 'config.json'


def app_dir():
    """配置文件该放哪个目录。

    打包版用 exe 所在目录，不能用 _MEIPASS——那是临时解压目录，每次启动
    都不一样，退出就删了，配置写进去等于没写。
    源码/绿色版这些代码在 app\\ 子目录里，配置放它的上一级，也就是整个
    文件夹的根上：用户要找它、要删它都方便，不用翻进 app\\ 里。
    """
    if getattr(sys, 'frozen', False):
        return os.path.dirname(os.path.abspath(sys.executable))
    here = os.path.dirname(os.path.abspath(__file__))
    up = os.path.dirname(here)
    return up if os.path.basename(here).lower() == 'app' and up else here


def user_dir():
    base = os.environ.get('LOCALAPPDATA') or os.path.expanduser('~')
    return os.path.join(base, '元器件规格描述生成器')


def path():
    """配置文件的实际位置。程序目录里有就用它（便携版、跟着文件夹走），
    没有就看用户目录，两边都没有就返回程序目录——首次保存优先写那儿。"""
    p = os.path.join(app_dir(), NAME)
    if os.path.isfile(p):
        return p
    u = os.path.join(user_dir(), NAME)
    if os.path.isfile(u):
        return u
    return p


def blank():
    return {'rename': {}, 'hide': {}, 'add': {}, 'options': {}, 'labels': {}}


def load(p=None):
    """读配置。读不出来不能让程序起不来——配置是锦上添花，坏了就当没有。

    返回 (配置, 出错原因)，出错原因是空串表示一切正常。
    """
    p = p or path()
    if not os.path.isfile(p):
        return blank(), ''
    try:
        with io.open(p, encoding='utf-8') as fh:
            raw = json.load(fh)
    except (OSError, ValueError) as e:
        return blank(), '%s 读不出来：%s' % (os.path.basename(p), e)
    if not isinstance(raw, dict):
        return blank(), '%s 的内容不是一个对象' % os.path.basename(p)
    cfg = blank()
    for k in cfg:
        v = raw.get(k)
        if isinstance(v, (dict, list)):
            cfg[k] = v
    return cfg, ''


def _write(p, body):
    """先写临时文件再改名，中途断电不会留下半个坏文件。"""
    try:
        os.makedirs(os.path.dirname(p), exist_ok=True)
    except OSError:
        pass
    tmp = p + '.tmp'
    with io.open(tmp, 'w', encoding='utf-8') as fh:
        json.dump(body, fh, ensure_ascii=False, indent=2, sort_keys=True)
    os.replace(tmp, p)


def save(cfg, p=None):
    """写配置，返回实际写到哪儿。

    程序目录可能是只读的（Program Files、网盘、解压到 C 盘根目录又没提权），
    写不进去就退到用户目录，别让用户改半天点保存报个错就没了。
    """
    body = dict(cfg)
    body['savedAt'] = time.strftime('%Y-%m-%d %H:%M:%S')
    target = p or path()
    try:
        _write(target, body)
        return target
    except OSError:
        if p:
            raise                    # 调用方指定了位置，不擅自换地方
        alt = os.path.join(user_dir(), NAME)
        if os.path.abspath(alt) == os.path.abspath(target):
            raise
        _write(alt, body)
        return alt


def _set_name(fields, name):
    """物料名称是固定值，就是子分类名。改名字必须把它一起改，
    否则描述第一段还是老名字，跟左边列表对不上。"""
    for f in fields:
        if f['label'] == '物料名称':
            f['kind'] = 'fixed'
            f['fixed'] = name
            f['raw'] = name       # 描述是拼 raw 出来的，这个不改就白改
            f['sample'] = name
            f['options'] = []


def _desc(fields):
    """按规则重拼描述：非空的 raw 用全角逗号连起来。"""
    return '，'.join(f['raw'] for f in fields if f.get('raw'))


def apply(schema, cfg):
    """把配置盖到 schema 上，返回 (新 schema, 提示列表)。

    不改原对象——schema 是热加载的共享数据，改了会串味。
    顺序：先加、再改选项、再改名、最后隐藏。改名放后面，这样配置里
    add/options 都按表格里的原名写，不用跟着改名同步。
    """
    notes = []
    out = json.loads(json.dumps(schema))     # 够用的深拷贝，纯 JSON 数据
    by_code = {c['code']: c for c in out['categories']}

    def part(key):
        """取配置里的一段。手写的配置什么形状都可能有，不是字典就当空的——
        配置写错了顶多是改动不生效，不能让整个程序起不来。"""
        v = cfg.get(key)
        if isinstance(v, dict):
            return v
        if v:
            notes.append('配置里的 %s 不是按分类编号组织的，已忽略' % key)
        return {}

    for code, items in part('add').items():
        cat = by_code.get(code)
        if cat is None:
            notes.append('配置里的分类 %s 表格里没有，已跳过' % code)
            continue
        have = {t['name'] for t in cat['types']}
        for it in items if isinstance(items, list) else []:
            name = (it.get('name') or '').strip() if isinstance(it, dict) else ''
            if not name or name in have:
                continue
            # 新物料的字段照抄同分类里的一种——字段是表格定的，凭空造不出来
            like = it.get('like') or (cat['types'][0]['name'] if cat['types'] else '')
            src = next((t for t in cat['types'] if t['name'] == like), None)
            if src is None:
                notes.append('%s 的「%s」找不到可参照的物料，已跳过' % (code, name))
                continue
            new = json.loads(json.dumps(src))
            new['name'] = name
            new['custom'] = True     # 界面上标一下，跟表格里的区分开
            _set_name(new['fields'], name)
            new['regenDesc'] = _desc(new['fields'])
            cat['types'].append(new)
            have.add(name)

    for code, spec in part('options').items():
        cat = by_code.get(code)
        if cat is None or not isinstance(spec, dict):
            continue
        for t in cat['types']:
            # 先套 "*"（整个分类通用），再套本物料的，后者能覆盖前者
            for key in ('*', t['name']):
                per = spec.get(key)
                if not isinstance(per, dict):
                    continue
                for f in t['fields']:
                    opts = per.get(f['label'])
                    if not isinstance(opts, list):
                        continue
                    clean = [str(o).strip() for o in opts if str(o).strip()]
                    if f['label'] == '物料名称':
                        continue          # 固定值，给它选项没有意义
                    f['options'] = clean
                    # 有选项就是下拉，空列表就是让它退回输入框
                    f['kind'] = 'select' if clean else 'text'

    for code, pairs in part('rename').items():
        cat = by_code.get(code)
        if cat is None or not isinstance(pairs, dict):
            continue
        used = {t['name'] for t in cat['types']}
        for t in cat['types']:
            new = (pairs.get(t['name']) or '').strip()
            if not new or new == t['name']:
                continue
            if new in used:
                notes.append('%s 里已经有「%s」了，改名跳过' % (code, new))
                continue
            used.discard(t['name'])
            used.add(new)
            t['origName'] = t['name']    # 界面上告诉用户表格里原来叫什么
            t['name'] = new
            _set_name(t['fields'], new)
            t['regenDesc'] = _desc(t['fields'])

    # 改栏位名称放在改物料名之后：上面那些逻辑都靠 label == '物料名称' 认人，
    # 先把标题换掉它们就认不出来了。
    for code, spec in part('labels').items():
        cat = by_code.get(code)
        if cat is None or not isinstance(spec, dict):
            continue
        for t in cat['types']:
            # "*" 是整个分类通用，写物料名的只管那一种，后者覆盖前者。
            # 这里用原名（改过名的物料也认），配置里一律记表格原名。
            for key in ('*', t.get('origName') or t['name'], t['name']):
                per = spec.get(key)
                if not isinstance(per, dict):
                    continue
                for f in t['fields']:
                    # 按原栏位名查：改过一次之后 label 已经不是表格里那个了，
                    # 再改一次还得能对上，否则配置里会堆出一串中间名字
                    src = f.get('origLabel') or f['label']
                    new = per.get(src)
                    if not isinstance(new, str):
                        continue
                    new = new.strip()
                    if not new or new == f['label']:
                        continue
                    f['origLabel'] = src     # 抓取参数按原名匹配，别名表才查得到
                    f['label'] = new
        # 同一种物料里两栏撞成一个名字，描述看不出谁是谁，得说一声
        for t in cat['types']:
            seen = {}
            for f in t['fields']:
                seen[f['label']] = seen.get(f['label'], 0) + 1
            dup = [k for k, v in seen.items() if v > 1]
            if dup:
                notes.append('%s 的「%s」里有重名栏位：%s'
                             % (code, t['name'], '、'.join(dup)))

    for code, names in part('hide').items():
        cat = by_code.get(code)
        if cat is None or not isinstance(names, list):
            continue
        drop = set(names)
        # 隐藏用的是表格原名还是改后的名字都认，不然改完名再隐藏就失效了
        cat['types'] = [t for t in cat['types']
                        if t['name'] not in drop
                        and t.get('origName') not in drop]

    out['categories'] = [c for c in out['categories'] if c['types']]
    return out, notes
