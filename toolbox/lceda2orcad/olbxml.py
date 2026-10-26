# SPDX-License-Identifier: GPL-3.0-only
"""IR → OrCAD Capture 元件库 XML（olb.xsd）。

生成的 XML 由 Capture 内置 TCL 命令转成 .olb：
    XMATIC_XML2OLB <xml> <olb>

结构（照 XMATIC_OLB2XML 导出的真库校对，olb.xsd 对 NormalView 的描述不完整）：
    Lib > Package > LibPart > {NormalView, PhysicalPart}
    NormalView > {SymbolColor, SymbolBBox, Is*, Contents*, PartValue, Reference,
                  Line, SymbolPinScalar}
    PhysicalPart > PinNumber

要点：PhysicalPart 在 LibPart 里面而不是 Package 里面；suffix 是 ".Normal"；
Cadence 自己从不在 NormalView 下写 Rect/SymbolVector，本体框用 4 条 Line；
每个 SymbolPinScalar 都要带齐 9 个布尔子元素；position 从 0 开始。

单位 1 = 10 mil，与立创一致，不缩放。PhysicalPart/PinNumber 靠 position 把序号
映射到真实引脚号。
"""
from __future__ import annotations

import math
import time
from dataclasses import dataclass
from xml.sax.saxutils import quoteattr

from .parse import BOTTOM, LEFT, RIGHT, TOP, Pin, Symbol

GRID = 10  # 10 单位 = 100 mil = Capture 默认栅格
# 引脚线长 3 格：Cadence 自带库就是 30（MICROPHONE start x=0、hotpt x=-30）。
# 引脚号是 Capture 按线长自动摆在引脚线上方的，线长对了号的位置才对。
PIN_LENGTH = 3 * GRID

# 引脚电气类型（从 Capture.exe 的标签表顺序确认）
PIN_INPUT, PIN_BIDIRECTIONAL, PIN_OUTPUT = 0, 1, 2
PIN_OPEN_COLLECTOR, PIN_PASSIVE, PIN_3STATE = 3, 4, 5
PIN_OPEN_EMITTER, PIN_POWER = 6, 7

# 立创的电气类型字段填写不可靠（STM32 全脚同值、RP2040 里 GND 与 GPIO 同值），
# 一律按 Passive 输出，避免误报 ERC。
DEFAULT_PIN_TYPE = PIN_PASSIVE


@dataclass
class SnapReport:
    """栅格吸附的改动记录，供人工核对。"""

    translate: tuple[int, int] = (0, 0)  # 对齐栅格的平移
    origin: tuple[int, int] = (0, 0)  # 把原点挪到本体左上角的偏移
    renamed: int = 0  # 因重名加了后缀的引脚数
    moved: int = 0
    total: int = 0
    collisions: list[tuple[str, str]] = None  # 被挪开的引脚对

    def __post_init__(self) -> None:
        if self.collisions is None:
            self.collisions = []

    @property
    def clean(self) -> bool:
        return self.moved == 0 and not self.collisions


def _snap(value: float) -> int:
    return int(round(value / GRID) * GRID)


def _floor(value: float) -> int:
    return int(math.floor(value / GRID) * GRID)


def _ceil(value: float) -> int:
    return int(math.ceil(value / GRID) * GRID)


def snap_pins(pins: list[Pin]) -> tuple[dict[str, tuple[int, int, int, int]], SnapReport]:
    """把引脚吸附到 100 mil 栅格。

    立创允许引脚落在任意位置，但 Capture 里引脚不在栅格上就连不上线。
    先找一个整体平移量让最多引脚天然落到栅格上（很多库整体偏半格），
    剩下的单独吸附；若吸附后与已占位置冲突，沿引脚朝向外推一格。
    返回 {引脚号: (conn_x, conn_y, body_x, body_y)} 和改动报告。
    """
    report = SnapReport(total=len(pins))
    if not pins:
        return {}, report

    # 候选平移量：半格偏移是最常见的情况
    best = max(
        (
            (dx, dy, sum(1 for p in pins if (p.conn_x + dx) % GRID == 0 and (p.conn_y + dy) % GRID == 0))
            for dx in (0, GRID // 2)
            for dy in (0, GRID // 2)
        ),
        key=lambda t: t[2],
    )
    dx, dy = best[0], best[1]
    report.translate = (dx, dy)

    # 朝符号外的单位向量（引脚伸出方向）
    outward = {LEFT: (-1, 0), RIGHT: (1, 0), TOP: (0, -1), BOTTOM: (0, 1)}
    # 冲突时要沿垂直于引脚的方向让位：左右脚往上下挪，上下脚往左右挪。
    # 沿引脚方向推只是把引脚拉长，两根脚还在同一行上，看起来照样叠着。
    aside = {LEFT: (0, 1), RIGHT: (0, 1), TOP: (1, 0), BOTTOM: (1, 0)}

    placed: dict[tuple[int, int], str] = {}
    result: dict[str, tuple[int, int, int, int]] = {}

    for pin in pins:
        cx, cy = pin.conn_x + dx, pin.conn_y + dy
        bx, by = pin.body_x + dx, pin.body_y + dy
        sx, sy = _snap(cx), _snap(cy)
        if (sx, sy) != (cx, cy):
            report.moved += 1

        ox, oy = outward.get(pin.side, (-1, 0))
        ax, ay = aside.get(pin.side, (0, 1))
        if (sx, sy) in placed:
            report.collisions.append((placed[(sx, sy)], pin.number))
            # 就近找空位：+1、-1、+2、-2 …… 让位幅度尽量小
            for step in (s for k in range(1, len(pins) + 2) for s in (k, -k)):
                nx, ny = sx + ax * step * GRID, sy + ay * step * GRID
                if (nx, ny) not in placed:
                    sx, sy = nx, ny
                    break

        placed[(sx, sy)] = pin.number
        # 本体端：保证引脚垂直贴在本体边上，长度一格
        sbx, sby = sx - ox * GRID, sy - oy * GRID
        result[pin.number] = (sx, sy, sbx, sby)

    return result, report


def dedupe_names(pins: list[Pin]) -> dict[str, str]:
    """OrCAD 不允许同名引脚，重名的一律加 1、2、3 递增后缀。

    返回 {引脚号: 显示名}。重名的**每一个**都带后缀（GND1/GND2/GND3），
    不留一个光的 GND —— 混着更难认。空名按引脚号兜底。
    """
    counts: dict[str, int] = {}
    for pin in pins:
        counts[pin.name] = counts.get(pin.name, 0) + 1

    seen: dict[str, int] = {}
    out: dict[str, str] = {}
    for pin in pins:
        base = pin.name or f"P{pin.number}"
        if counts.get(pin.name, 0) > 1:
            seen[pin.name] = seen.get(pin.name, 0) + 1
            out[pin.number] = f"{base}{seen[pin.name]}"
        else:
            out[pin.number] = base
    return out


def attach_pins(
    snapped: dict[str, tuple[int, int, int, int]],
    pins: list[Pin],
    body: tuple[int, int, int, int],
) -> None:
    """就地改写引脚坐标：本体端贴到本体边上，连接端往外伸满 PIN_LENGTH。

    立创的引脚长度五花八门，吸附后还可能被挪位。Capture 是按引脚线长自动摆引脚号的，
    所以统一成和自带库一样的 3 格线长，引脚号的位置才跟原生一致。
    垂直于引脚的那个坐标保留吸附结果（含让位），只改沿引脚方向的坐标。
    """
    x1, y1, x2, y2 = body
    edge = {LEFT: x1, RIGHT: x2, TOP: y1, BOTTOM: y2}
    sign = {LEFT: -1, RIGHT: 1, TOP: -1, BOTTOM: 1}
    for pin in pins:
        if pin.number not in snapped:
            continue
        cx, cy, _bx, _by = snapped[pin.number]
        e = edge.get(pin.side)
        if e is None:
            continue
        s = sign[pin.side]
        if pin.side in (LEFT, RIGHT):
            snapped[pin.number] = (e + s * PIN_LENGTH, cy, e, cy)
        else:
            snapped[pin.number] = (cx, e + s * PIN_LENGTH, cx, e)


def _bbox(coords: list[tuple[int, int]]) -> tuple[int, int, int, int]:
    xs = [c[0] for c in coords] or [0]
    ys = [c[1] for c in coords] or [0]
    return min(xs), min(ys), max(xs), max(ys)


def build_lib_xml(symbols: list[Symbol], olb_path: str = "lceda.olb") -> tuple[str, dict[str, SnapReport]]:
    """生成完整的库 XML。返回 (xml 文本, {lcsc: 吸附报告})。

    olb_path 是目标 .olb 的完整路径 —— Lib/Defn 的 name 用它，不是库昵称。
    """
    out: list[str] = []
    reports: dict[str, SnapReport] = {}
    w = out.append

    w('<?xml version="1.0" encoding="UTF-8" standalone="no" ?>')
    w("<Lib>")
    w(f"  <Defn name={quoteattr(olb_path)}/>")
    # 字体表：Cadence 两个自带库导出来一模一样的 24 项。引脚号的位置是 Capture
    # 按字体度量自动算的，不写这张表就用 app 默认字体，号会离引脚线偏远。
    w("  <DefaultValues>")
    w("    <Defn/>")
    for index in range(24):
        if index == 13:
            height, width, font = -9, 5, "Courier New"
        elif index in (3, 4) or index >= 17:
            height, width, font = 8, 0, "Arial"
        else:
            height, width, font = -9, 4, "Arial"
        w(
            f'    <DefaultFont><Defn charset="0" escapement="0" height="{height}"'
            f' index="{index}" italic="0" name="{font}" orientation="0"'
            f' weight="400" width="{width}"/></DefaultFont>'
        )
    w("  </DefaultValues>")

    for sym in symbols:
        snapped, report = snap_pins(sym.pins)
        names = dedupe_names(sym.pins)
        report.renamed = sum(1 for p in sym.pins if names[p.number] != p.name)
        reports[sym.lcsc] = report

        w("  <Package>")
        w(
            # alphabeticNumbering 不是布尔值，schema 里是 xs:long。实测把
            # PassiveFilter.olb 导成 XML，29 个包全是 alphabeticNumbering="2" +
            # isHomogeneous="1"：2 才是不带节后缀的单节器件。
            # 0 会显示成 U1-1，1 会显示成 U1A，都是错的。
            '    <Defn alphabeticNumbering="2" isHomogeneous="1" '
            "name={} pcbFootprint={} pcbLib=\"\" refdesPrefix={} "
            'timestamp="{}" timezone="0"/>'.format(
                quoteattr(sym.name),
                quoteattr(sym.footprint),
                quoteattr(sym.refdes_prefix),
                int(time.time()),
            )
        )
        w("    <LibPart>")
        w(f"      <Defn CellName={quoteattr(sym.name)}/>")
        w("      <NormalView>")
        w('        <Defn suffix=".Normal"/>')

        # 本体框：优先用立创的矩形，没有就按引脚范围兜底
        body: tuple[int, int, int, int] | None = None
        if sym.rects:
            r = sym.rects[0]
            # 用 floor/ceil 向外取整，避免矮矩形（如 0603 电阻本体只有 8 单位高）
            # 被四舍五入压成一条线
            tx, ty = report.translate
            body = (
                _floor(r.x + tx),
                _floor(r.y + ty),
                _ceil(r.x + r.width + tx),
                _ceil(r.y + r.height + ty),
            )
        elif snapped:
            bx = [v[2] for v in snapped.values()]
            by = [v[3] for v in snapped.values()]
            body = (min(bx), min(by), max(bx), max(by))

        # 把原点挪到本体左上角：Cadence 自带库的 bbox 全是 x0..N y0..M（非负），
        # 原点在本体左上角，摆放时元件朝右下方展开。原点落在本体中间的话，
        # 元件会挂在插入点上方，一放就顶到画布顶边。
        # 先把引脚贴到本体边上并伸满线长，再挪原点，这样偏移量对最终坐标生效
        if body:
            attach_pins(snapped, sym.pins, body)

        if body:
            offx, offy = -body[0], -body[1]
            if (offx, offy) != (0, 0):
                body = (0, 0, body[2] + offx, body[3] + offy)
                for _num, (_cx, _cy, _bx, _by) in list(snapped.items()):
                    snapped[_num] = (_cx + offx, _cy + offy, _bx + offx, _by + offy)
                report.origin = (offx, offy)

        # SymbolBBox 只框本体，不含引脚伸出的部分 —— Cadence 自带库全是这样
        # （MICROPHONE 的 bbox x0..20，引脚 hotpt 在 x=-30，在框外）。
        # Capture 靠这个框判断"本体内侧"来摆引脚名，框大了名字就跑到body外面去。
        if body:
            bx1, by1, bx2, by2 = body
        else:
            bx1, by1, bx2, by2 = _bbox(
                [(v[2], v[3]) for v in snapped.values()]  # 只用本体端
            )

        # 位号与 Value 的显示位置，放在本体上方/下方
        for prop_name, loc_y in (("Part Reference", by1 - GRID), ("Value", by2 + GRID)):
            w("        <SymbolDisplayProp>")
            w(
                f'          <Defn locX="{bx1}" locY="{loc_y}" '
                f"name={quoteattr(prop_name)} rotation=\"0\" textJustification=\"0\"/>"
            )
            w("          <PropFont>")
            w(
                '            <Defn charset="0" escapement="0" height="-9" italic="0"'
                ' name="" orientation="0" weight="400" width="4"/>'
            )
            w("          </PropFont>")
            w('          <PropColor><Defn val="48"/></PropColor>')
            w('          <PropDispType><Defn ValueIfValueExist="0" val="1"/></PropDispType>')
            w("        </SymbolDisplayProp>")

        w('        <SymbolColor><Defn val="48"/></SymbolColor>')
        w("        <SymbolBBox>")
        w(f'          <Defn x1="{bx1}" x2="{bx2}" y1="{by1}" y2="{by2}"/>')
        w("        </SymbolBBox>")
        w('        <IsPinNumbersVisible><Defn val="1"/></IsPinNumbersVisible>')
        # 上下两侧的引脚名要跟着转 90 度，Cadence 自带库 6 个封装全是 1
        w('        <IsPinNamesRotated><Defn val="1"/></IsPinNamesRotated>')
        w('        <IsPinNamesVisible><Defn val="1"/></IsPinNamesVisible>')
        w('        <ContentsLibName><Defn name=""/></ContentsLibName>')
        w('        <ContentsViewName><Defn name=""/></ContentsViewName>')
        w('        <ContentsViewType><Defn type="0"/></ContentsViewType>')
        w(f"        <PartValue><Defn name={quoteattr(sym.name)}/></PartValue>")
        w(f"        <Reference><Defn name={quoteattr(sym.refdes_prefix)}/></Reference>")

        # 本体框用 4 条 Line：Cadence 自己在 NormalView 下从不写 Rect
        if body:
            x1, y1, x2, y2 = body
            for lx1, ly1, lx2, ly2 in (
                (x1, y1, x2, y1),
                (x2, y1, x2, y2),
                (x2, y2, x1, y2),
                (x1, y2, x1, y1),
            ):
                w("        <Line>")
                w(
                    f'          <Defn lineStyle="0" lineWidth="0" '
                    f'x1="{lx1}" x2="{lx2}" y1="{ly1}" y2="{ly2}"/>'
                )
                w("        </Line>")

        # 立创折线拆成逐段 Line
        for poly in sym.polylines:
            pts = [
                (
                    _snap(x + report.translate[0]) + report.origin[0],
                    _snap(y + report.translate[1]) + report.origin[1],
                )
                for x, y in poly.points
            ]
            for (px1, py1), (px2, py2) in zip(pts, pts[1:]):
                if (px1, py1) == (px2, py2):
                    continue
                w("        <Line>")
                w(
                    f'          <Defn lineStyle="0" lineWidth="0" '
                    f'x1="{px1}" x2="{px2}" y1="{py1}" y2="{py2}"/>'
                )
                w("        </Line>")

        for index, pin in enumerate(sym.pins):
            cx, cy, bx, by = snapped[pin.number]
            w(
                "        <SymbolPinScalar>"
            )
            w(
                '          <Defn hotptX="{}" hotptY="{}" name={} position="{}" '
                'startX="{}" startY="{}" type="{}" visible="1"/>'.format(
                    cx, cy, quoteattr(names[pin.number]), index, bx, by, DEFAULT_PIN_TYPE
                )
            )
            # 9 个布尔子元素都要写齐，缺一个 XMATIC 就整库拒收
            for tag, val in (
                ("IsLong", 1),  # Line 形式（0 是 Short）
                ("IsClock", 1 if pin.clock else 0),
                ("IsDot", 1 if pin.dot else 0),
                ("IsLeftPointing", 0),
                ("IsRightPointing", 0),
                ("IsNetStyle", 0),
                ("IsNoConnect", 0),
                ("IsGlobal", 0),
                ("IsNumberVisible", 1 if pin.number_visible else 0),
            ):
                w(f'          <{tag}><Defn val="{val}"/></{tag}>')
            w("        </SymbolPinScalar>")

        w("      </NormalView>")

        # 物理引脚号映射：PhysicalPart 是 NormalView 的兄弟，在 LibPart 里面
        w("      <PhysicalPart>")
        w("        <Defn/>")
        for index, pin in enumerate(sym.pins):
            w("        <PinNumber>")
            w(f'          <Defn number={quoteattr(pin.number)} position="{index}"/>')
            w("        </PinNumber>")
        w("      </PhysicalPart>")
        w("    </LibPart>")
        w("  </Package>")

    w("</Lib>")
    return "\n".join(out) + "\n", reports
