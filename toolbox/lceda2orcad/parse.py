# SPDX-License-Identifier: GPL-3.0-only
"""立创EDA 标准版符号 → 中间表示 (IR)。

坐标单位：立创和 OrCAD Capture 内部都是 1 单位 = 10 mil，1:1 不缩放。
IR 坐标已相对符号原点（head.x/head.y），y 轴向下，与 Capture 一致。
"""
from __future__ import annotations

import re
from dataclasses import dataclass, field

# 引脚路径首段，形如 M315,185h10 / M 325 188 L 328 185 / M315 185 v-10
_PATH_HEAD = re.compile(
    r"M\s*(-?[\d.]+)[,\s]+(-?[\d.]+)\s*([hvlHVL])\s*(-?[\d.]+)(?:[,\s]+(-?[\d.]+))?"
)

LEFT, RIGHT, TOP, BOTTOM = "LEFT", "RIGHT", "TOP", "BOTTOM"


@dataclass
class Pin:
    number: str
    name: str
    # conn = 可连接的自由端（立创的引脚坐标），body = 与符号本体相接的一端
    conn_x: float
    conn_y: float
    body_x: float
    body_y: float
    side: str
    dot: bool = False          # 低电平有效圆点
    clock: bool = False
    name_visible: bool = True
    number_visible: bool = True

    @property
    def length(self) -> float:
        return abs(self.conn_x - self.body_x) + abs(self.conn_y - self.body_y)


@dataclass
class Rect:
    x: float
    y: float
    width: float
    height: float


@dataclass
class Polyline:
    points: list[tuple[float, float]]


@dataclass
class Symbol:
    lcsc: str
    name: str
    prefix: str          # 位号前缀，如 U?
    footprint: str
    manufacturer: str = ""
    mfr_part: str = ""
    pins: list[Pin] = field(default_factory=list)
    rects: list[Rect] = field(default_factory=list)
    polylines: list[Polyline] = field(default_factory=list)
    # 解析时发现但未转换的图元，用于生成报告
    skipped: list[str] = field(default_factory=list)

    @property
    def refdes_prefix(self) -> str:
        """U? -> U，Capture 的 refdesPrefix 不带问号。"""
        return self.prefix.rstrip("?") or "U"


def _num(value: str, default: float = 0.0) -> float:
    try:
        return float(value)
    except (TypeError, ValueError):
        return default


def _pin_side(conn: tuple[float, float], body: tuple[float, float]) -> str:
    """本体相对连接端的方向决定引脚贴在符号哪一侧。"""
    dx = body[0] - conn[0]
    dy = body[1] - conn[1]
    if abs(dx) >= abs(dy):
        return LEFT if dx > 0 else RIGHT
    return TOP if dy > 0 else BOTTOM


def parse_pin(raw: str) -> Pin | None:
    """解析一条 P~ 图元。7 段以 ^^ 分隔。"""
    seg = raw.split("^^")
    if len(seg) < 5:
        return None

    head = seg[0].split("~")
    if len(head) < 7:
        return None
    number = head[3].strip()
    conn_x, conn_y = _num(head[4]), _num(head[5])

    # 从路径推本体端，比旋转字段更可靠（旋转只有 4 个离散值）
    match = _PATH_HEAD.match(seg[2].split("~")[0].strip())
    if not match:
        return None
    px, py = _num(match.group(1)), _num(match.group(2))
    cmd, val = match.group(3), _num(match.group(4))
    if cmd == "h":
        body_x, body_y = px + val, py
    elif cmd == "H":
        body_x, body_y = val, py
    elif cmd == "v":
        body_x, body_y = px, py + val
    elif cmd == "V":
        body_x, body_y = px, val
    elif cmd == "l":
        body_x, body_y = px + val, py + _num(match.group(5))
    else:  # L
        body_x, body_y = val, _num(match.group(5))

    name_seg = seg[3].split("~")
    name = name_seg[4].strip() if len(name_seg) > 4 else ""
    name_visible = name_seg[0].strip() != "0"

    num_seg = seg[4].split("~")
    number_visible = num_seg[0].strip() != "0"
    if not number:  # head 里没有就退回显示文本
        number = num_seg[4].strip() if len(num_seg) > 4 else ""

    dot = len(seg) > 5 and seg[5].split("~")[0].strip() == "1"
    clock = len(seg) > 6 and seg[6].split("~")[0].strip() == "1"

    return Pin(
        number=number,
        name=name or number,
        conn_x=conn_x,
        conn_y=conn_y,
        body_x=body_x,
        body_y=body_y,
        side=_pin_side((conn_x, conn_y), (body_x, body_y)),
        dot=dot,
        clock=clock,
        name_visible=name_visible,
        number_visible=number_visible,
    )


def sanitize_footprint(name: str) -> str:
    """把封装名里的小数点换成 d —— Allegro 不接受封装名带小数点。

    只动小数点，别的字符原样留着：立创的封装名形如
    LQFN-56_L7.0-W7.0-P0.4-EP，横线和下划线 Allegro 是认的。
    """
    return name.replace(".", "d")


def parse_symbol(result: dict) -> Symbol:
    """把 fetch 拿到的 result 转成 IR。坐标平移到符号原点。"""
    data = result.get("dataStr") or {}
    head = data.get("head") or {}
    para = head.get("c_para") or {}
    ox, oy = _num(head.get("x")), _num(head.get("y"))

    sym = Symbol(
        lcsc=para.get("Supplier Part") or result.get("lcsc") or "",
        name=result.get("title") or para.get("name") or "",
        prefix=para.get("pre") or "U?",
        footprint=sanitize_footprint(para.get("package") or ""),
        manufacturer=para.get("Manufacturer") or "",
        mfr_part=para.get("Manufacturer Part") or "",
    )

    for raw in data.get("shape") or []:
        kind = raw.split("~", 1)[0]
        if kind == "P":
            pin = parse_pin(raw)
            if pin is None:
                sym.skipped.append(raw[:60])
                continue
            pin.conn_x -= ox
            pin.conn_y -= oy
            pin.body_x -= ox
            pin.body_y -= oy
            sym.pins.append(pin)
        elif kind == "R":
            f = raw.split("~")
            # R~x~y~rx~ry~width~height~...
            if len(f) >= 7:
                sym.rects.append(
                    Rect(_num(f[1]) - ox, _num(f[2]) - oy, _num(f[5]), _num(f[6]))
                )
        elif kind == "PL":
            f = raw.split("~")
            coords = [_num(v) for v in f[1].split(" ") if v.strip()] if len(f) > 1 else []
            pts = [
                (coords[i] - ox, coords[i + 1] - oy)
                for i in range(0, len(coords) - 1, 2)
            ]
            if len(pts) >= 2:
                sym.polylines.append(Polyline(pts))
        elif kind in ("E", "T", "A", "PT", "PI"):
            sym.skipped.append(kind)

    sym.pins.sort(key=lambda p: (len(p.number), p.number))
    return sym
