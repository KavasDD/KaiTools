# SPDX-License-Identifier: GPL-3.0-only
"""lceda2orcad 命令行入口。

  python -m lceda2orcad.cli fetch C8734 C25804
  python -m lceda2orcad.cli info C8734
  python -m lceda2orcad.cli ls
"""
from __future__ import annotations

import argparse
import os
import re
import sys
from pathlib import Path

# Windows 控制台默认 cp936，中文与厂家名会变成乱码
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(encoding="utf-8", errors="replace")
    except (AttributeError, OSError):  # 被重定向或旧版本时忽略
        pass

if __package__ in (None, ""):  # 支持直接 python cli.py 运行
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from toolbox.lceda2orcad.emit import emit
    from toolbox.lceda2orcad.fetch import CACHE_DIR, FetchError, fetch, summarize
    from toolbox.lceda2orcad.parse import parse_symbol
else:
    from .emit import emit
    from .fetch import CACHE_DIR, FetchError, fetch, summarize
    from .parse import parse_symbol

FIELD_LABELS = [
    ("lcsc", "立创编号"),
    ("title", "名称"),
    ("manufacturer", "厂家"),
    ("mfr_part", "厂家型号"),
    ("prefix", "位号前缀"),
    ("footprint", "封装"),
    ("pin_count", "引脚数"),
    ("pad_count", "焊盘数"),
    ("sym_shape_count", "符号图元数"),
    ("subpart_count", "子部件数"),
    ("editor_version", "编辑器版本"),
    ("uuid", "uuid"),
    ("updated_at", "上游更新时间"),
]


def cmd_fetch(args: argparse.Namespace) -> int:
    cache_dir = Path(args.cache) if args.cache else CACHE_DIR
    failures = 0
    for part in args.parts:
        try:
            result, cached = fetch(part, cache_dir=cache_dir, refresh=args.refresh)
        except FetchError as exc:
            print(f"  x {exc}", file=sys.stderr)
            failures += 1
            continue
        info = summarize(result)
        tag = "缓存" if cached else "已抓取"
        warn = "" if info["has_footprint"] else "  [无封装数据]"
        print(
            f"  {tag}  {info['lcsc']:<10} {info['title']:<28} "
            f"{info['pin_count']:>3}引脚  {info['footprint'] or '-'}{warn}"
        )
    if failures:
        print(f"\n{failures} 个失败，其余已缓存到 {cache_dir}", file=sys.stderr)
    return 1 if failures else 0


def cmd_info(args: argparse.Namespace) -> int:
    cache_dir = Path(args.cache) if args.cache else CACHE_DIR
    try:
        result, cached = fetch(args.part, cache_dir=cache_dir)
    except FetchError as exc:
        print(exc, file=sys.stderr)
        return 1
    info = summarize(result)
    print(f"来源: {'本地缓存' if cached else '在线抓取'}")
    for key, label in FIELD_LABELS:
        value = info.get(key)
        if value not in (None, "", 0) or key == "pin_count":
            print(f"  {label:<12} {value}")
    if not info["has_footprint"]:
        print("  注意         该器件没有 PCB 封装数据")
    return 0


def cmd_convert(args: argparse.Namespace) -> int:
    cache_dir = Path(args.cache) if args.cache else CACHE_DIR
    out_dir = Path(args.out)
    symbols = []
    failures = 0
    for part in args.parts:
        try:
            result, _ = fetch(part, cache_dir=cache_dir, refresh=args.refresh)
        except FetchError as exc:
            print(f"  x {exc}", file=sys.stderr)
            failures += 1
            continue
        symbols.append(parse_symbol(result))

    if not symbols:
        print("没有可转换的器件", file=sys.stderr)
        return 1

    # 库是删掉重建的（append 模式会攒重复包并越跑越慢），所以每次都得把缓存里
    # 的历史器件一起写进去，否则上次转的元件在库里就没了：已经放下的靠 Capture
    # 设计缓存还在，但想再放一次就找不到包了。
    requested = {sym.lcsc for sym in symbols}
    carried = []
    if not args.only:
        for path in sorted(cache_dir.glob("*.json")):
            if path.stem in requested:
                continue
            try:
                result, _ = fetch(path.stem, cache_dir=cache_dir)
                sym = parse_symbol(result)
            except Exception as exc:  # 单个坏缓存不该让整库建不出来
                print(f"  ! 跳过缓存 {path.name}: {exc}", file=sys.stderr)
                continue
            symbols.append(sym)
            carried.append(sym)

    xml_path, lib_tcl, reports = emit(symbols, out_dir, lib_name=args.name)

    for sym in symbols:
        if sym.lcsc not in requested:
            continue
        rep = reports[sym.lcsc]
        note = "" if rep.clean else "  <-- 有改动"
        print(f"  {sym.lcsc:<9} {sym.name:<26} {len(sym.pins):>3}引脚{note}")
        if rep.translate != (0, 0):
            print(f"      整体平移 {rep.translate} 以对齐 100mil 栅格")
        if rep.renamed:
            print(f"      {rep.renamed} 个重名引脚加了递增后缀（OrCAD 不允许同名）")
        if rep.moved:
            print(f"      {rep.moved}/{rep.total} 个引脚被吸附到栅格")
        if rep.collisions:
            pairs = ", ".join(f"{a}/{b}" for a, b in rep.collisions[:5])
            print(f"      引脚重叠已外推: {pairs}（原始间距非 100mil 整数倍）")
        if sym.skipped:
            print(f"      未转换图元: {', '.join(sorted(set(sym.skipped)))}")

    if carried:
        names = ", ".join(s.name for s in carried[:8])
        more = f" 等 {len(carried)} 个" if len(carried) > 8 else ""
        print(f"\n另外带上缓存里的历史器件（库是整体重建的）：{names}{more}")

    print(f"\n已生成 {xml_path}（共 {len(symbols)} 个器件）")
    print("在 OrCAD Capture 的 View > Command Window 里依次执行两行：")
    print(f"  source {{{str(lib_tcl.resolve()).replace(chr(92), '/')}}}")
    print("  lceda2orcadImport")
    print("(Command Window 逐行求值，多行 if/proc 会被拆散，所以用 source 加载)")
    first = symbols[0].name if symbols else "PKGNAME"
    print(f"\n摆放（先在 Capture 里打开一页原理图）：\n  lceda2orcadPlace {first}")
    print("  # Value 由库里的符号带出来（显示格式 = Value Only），不用传属性。")
    print("  # 要额外带别的属性就传两个等长列表（注意可能会把 Value 显示挤掉）：")
    print(f"  lceda2orcadPlace {first} {{Value {{PCB Footprint}}}} {{{first} QFN56}}")
    if failures:
        print(f"\n{failures} 个器件抓取失败，未包含在库里", file=sys.stderr)
    return 1 if failures else 0


def cmd_ls(args: argparse.Namespace) -> int:
    cache_dir = Path(args.cache) if args.cache else CACHE_DIR
    files = sorted(cache_dir.glob("C*.json")) if cache_dir.exists() else []
    if not files:
        print(f"缓存为空: {cache_dir}")
        return 0
    total = sum(f.stat().st_size for f in files)
    print(f"{cache_dir}  共 {len(files)} 个器件, {total / 1024:.0f} KB")
    for path in files:
        print(f"  {path.stem:<10} {path.stat().st_size / 1024:>7.1f} KB")
    return 0


PROJECT_ROOT = Path(__file__).resolve().parent.parent
MENU_SRC = PROJECT_ROOT / "autoload" / "lceda2orcadMenu.tcl"

# Capture 的用户级 autoload 目录，相对 Cadence 的 HOME（就是 SPB_Data）。
# 不带版本号那一层；带 17.4.0 的实测不扫。目录位置写死在 Capture.exe 的 C++ 里，
# CaptureTclAutoLoadScope 只是范围开关，改不了路径，所以只能按这个相对结构找。
AUTOLOAD_REL = Path("cdssetup/OrCAD_Capture/tclscripts/capAutoLoad")


def find_spb_data() -> Path | None:
    """找 Cadence 的 SPB_Data 目录。装 Cadence 时会设 HOME 指向它。"""
    home = os.environ.get("HOME")
    if home and (Path(home) / "cdssetup").is_dir():
        return Path(home)

    # HOME 没设或被别的程序改过，就按常见安装位置猜
    for drive in ("C:", "D:", "E:"):
        for name in ("orcad/Cadence/SPB_Data", "Cadence/SPB_Data"):
            p = Path(f"{drive}/{name}")
            if (p / "cdssetup").is_dir():
                return p
    return None


def cmd_installmenu(args: argparse.Namespace) -> int:
    if not MENU_SRC.exists():
        print(f"找不到菜单文件: {MENU_SRC}", file=sys.stderr)
        return 1

    if args.dest:
        dst_dir = Path(args.dest)
    else:
        spb = find_spb_data()
        if spb is None:
            print(
                "找不到 Cadence 的 SPB_Data 目录。用 --dest 手动指定，例如：\n"
                r"  --dest C:\orcad\Cadence\SPB_Data\cdssetup\OrCAD_Capture"
                r"\tclscripts\capAutoLoad",
                file=sys.stderr,
            )
            return 1
        dst_dir = spb / AUTOLOAD_REL
        print(f"Cadence SPB_Data: {spb}")

    # 路径和 python 解释器换机器就变，所以安装时把探测到的真实值写进副本，
    # 源文件保持占位不动。
    text = MENU_SRC.read_text(encoding="ascii")
    root_tcl = PROJECT_ROOT.as_posix()
    py_tcl = Path(sys.executable).as_posix()
    text = re.sub(
        r'^set ::lceda2orcadRoot .*$',
        f'set ::lceda2orcadRoot "{root_tcl}"',
        text,
        count=1,
        flags=re.M,
    )
    text = re.sub(
        r'^set ::lceda2orcadPython .*$',
        f'set ::lceda2orcadPython "{py_tcl}"',
        text,
        count=1,
        flags=re.M,
    )

    dst_dir.mkdir(parents=True, exist_ok=True)
    dst = dst_dir / MENU_SRC.name
    dst.write_text(text, encoding="ascii", newline="\n")

    print(f"项目目录: {root_tcl}")
    print(f"Python:   {py_tcl}")
    print(f"已安装 {dst}")
    print("重启 Capture 生效。之后转新器件不用重装（菜单打开时才枚举器件列表）。")
    return 0


def cmd_doctor(args: argparse.Namespace) -> int:
    """换机器后先跑这个：把装环境需要的东西一次查完。"""
    ok = True

    print(f"Python      {sys.version.split()[0]}  {Path(sys.executable).as_posix()}")
    if sys.version_info < (3, 10):
        print("  ! 需要 3.10+（代码里用了 X | None 写法）")
        ok = False

    print(f"项目目录    {PROJECT_ROOT.as_posix()}")
    print(f"菜单文件    {'有' if MENU_SRC.exists() else '缺失'}  {MENU_SRC.name}")
    if not MENU_SRC.exists():
        ok = False

    spb = find_spb_data()
    if spb is None:
        print("Cadence     找不到 SPB_Data（HOME 没设？装 Cadence 会设）")
        ok = False
    else:
        print(f"Cadence     {spb}")
        d = spb / AUTOLOAD_REL
        print(f"  autoload  {'已存在' if d.is_dir() else '装的时候会建'}  {d}")
        installed = d / MENU_SRC.name
        print(f"  已装菜单  {'是' if installed.exists() else '否'}")

    # tclsh 只是用来在装之前查生成的 TCL 语法，不是运行时依赖
    tclsh = None
    if spb is not None:
        for p in sorted(spb.parent.glob("SPB_*/tcltk/bin/tclsh.exe")):
            tclsh = p
            break
    print(f"tclsh       {tclsh.as_posix() if tclsh else '没找到（可选，只用于语法自检）'}")

    try:
        import urllib.request  # noqa: F401

        print("网络模块    urllib 可用")
    except Exception as exc:
        print(f"网络模块    ! {exc}")
        ok = False

    cache = Path(args.cache) if args.cache else CACHE_DIR
    n = len(list(cache.glob("C*.json"))) if cache.is_dir() else 0
    print(f"缓存        {n} 个器件  {cache}")

    print()
    print("环境没问题，可以装了。" if ok else "上面有 ! 的项要先解决。")
    return 0 if ok else 1


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="lceda2orcad", description="立创EDA 器件抓取与转换"
    )
    parser.add_argument("--cache", help=f"缓存目录（默认 {CACHE_DIR}）")
    sub = parser.add_subparsers(dest="cmd", required=True)

    p_fetch = sub.add_parser("fetch", help="抓取器件并缓存")
    p_fetch.add_argument("parts", nargs="+", metavar="LCSC", help="立创编号，如 C8734")
    p_fetch.add_argument("--refresh", action="store_true", help="忽略缓存重新抓取")
    p_fetch.set_defaults(func=cmd_fetch)

    p_info = sub.add_parser("info", help="查看单个器件的关键字段")
    p_info.add_argument("part", metavar="LCSC")
    p_info.set_defaults(func=cmd_info)

    p_conv = sub.add_parser("convert", help="转换成 OrCAD 库 XML + TCL 脚本")
    p_conv.add_argument("parts", nargs="+", metavar="LCSC")
    p_conv.add_argument("--out", default="out", help="输出目录（默认 out）")
    p_conv.add_argument("--name", default="lceda", help="库名（默认 lceda）")
    p_conv.add_argument("--refresh", action="store_true", help="忽略缓存重新抓取")
    p_conv.add_argument(
        "--only",
        action="store_true",
        help="只建命令行上这几个器件，不带缓存里的历史器件（库会因此丢掉上次转的元件）",
    )
    p_conv.set_defaults(func=cmd_convert)

    p_ls = sub.add_parser("ls", help="列出已缓存的器件")
    p_ls.set_defaults(func=cmd_ls)

    p_menu = sub.add_parser("installmenu", help="把 Accessories 菜单文件装进 Capture")
    p_menu.add_argument("--dest", help="覆盖安装目录（默认自动找用户级 capAutoLoad）")
    p_menu.set_defaults(func=cmd_installmenu)

    p_doc = sub.add_parser("doctor", help="换机器后自检：Python/Cadence/路径")
    p_doc.add_argument("--cache", help="指定缓存目录")
    p_doc.set_defaults(func=cmd_doctor)

    args = parser.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
