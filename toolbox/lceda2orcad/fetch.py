# SPDX-License-Identifier: GPL-3.0-only
"""立创EDA 标准版器件抓取 + 磁盘缓存。

只负责拿到原始 JSON 并存盘，不做任何解析加工。
解析映射会反复调整，原始响应落盘后可以离线重跑。
"""
from __future__ import annotations

import json
import re
import urllib.error
import urllib.request
from pathlib import Path

from .parse import sanitize_footprint

API = "https://easyeda.com/api/products/{lcsc}/components?version=6.4.19.5"

# 缺少 Referer/Origin 会被挡回 403，这两个头是必需的
HEADERS = {
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0 Safari/537.36"
    ),
    "Accept": "application/json, text/plain, */*",
    "Accept-Language": "zh-CN,zh;q=0.9",
    "Referer": "https://easyeda.com/",
    "Origin": "https://easyeda.com",
}

LCSC_RE = re.compile(r"^C\d+$")
CACHE_DIR = Path(__file__).resolve().parent.parent / "cache"


class FetchError(RuntimeError):
    pass


def normalize_lcsc(part: str) -> str:
    """把用户输入规整成 C12345 形式。"""
    s = part.strip().upper()
    if s.isdigit():
        s = "C" + s
    if not LCSC_RE.match(s):
        raise FetchError(f"不是合法的立创编号: {part!r}（应形如 C8734）")
    return s


def cache_path(lcsc: str, cache_dir: Path | None = None) -> Path:
    return (cache_dir or CACHE_DIR) / f"{lcsc}.json"


def fetch(
    part: str,
    *,
    cache_dir: Path | None = None,
    refresh: bool = False,
    timeout: int = 20,
) -> tuple[dict, bool]:
    """取一个器件的原始响应。

    返回 (result_dict, from_cache)。result_dict 是接口 result 字段的内容。
    refresh=True 时忽略已有缓存重新抓取。
    """
    lcsc = normalize_lcsc(part)
    path = cache_path(lcsc, cache_dir)

    if path.exists() and not refresh:
        with path.open(encoding="utf-8") as fh:
            return json.load(fh), True

    url = API.format(lcsc=lcsc)
    try:
        req = urllib.request.Request(url, headers=HEADERS)
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            raw = resp.read().decode("utf-8")
    except urllib.error.HTTPError as exc:
        raise FetchError(f"{lcsc} 抓取失败: HTTP {exc.code} {exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise FetchError(f"{lcsc} 抓取失败: 网络不可达 ({exc.reason})") from exc

    payload = json.loads(raw)
    if not payload.get("success"):
        raise FetchError(f"{lcsc} 接口返回失败: code={payload.get('code')}")

    result = payload.get("result")
    if not result:
        raise FetchError(f"{lcsc} 接口返回为空，编号可能不存在")
    if "dataStr" not in result:
        raise FetchError(f"{lcsc} 响应里没有 dataStr，不是可解析的器件")

    path.parent.mkdir(parents=True, exist_ok=True)
    # 原样存盘（含 uuid/updateTime），上游改版时能对比出来
    with path.open("w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False, indent=1)

    return result, False


def summarize(result: dict) -> dict:
    """从原始 result 里挑出人工核对用的关键字段。"""
    head = result.get("dataStr", {}).get("head", {})
    para = head.get("c_para", {})
    shapes = result.get("dataStr", {}).get("shape", [])
    pkg = result.get("packageDetail") or {}
    pkg_shapes = pkg.get("dataStr", {}).get("shape", []) if pkg else []
    return {
        "lcsc": para.get("Supplier Part") or result.get("lcsc"),
        "title": result.get("title"),
        "manufacturer": para.get("Manufacturer"),
        "mfr_part": para.get("Manufacturer Part"),
        "prefix": para.get("pre"),
        # 跟 parse 走同一套清洗，否则 info/ls 显示的名字和进库的不一致
        "footprint": sanitize_footprint(para.get("package") or "") or None,
        "uuid": result.get("uuid"),
        "updated_at": result.get("updated_at"),
        "editor_version": head.get("editorVersion"),
        "pin_count": sum(1 for s in shapes if s.startswith("P~")),
        "sym_shape_count": len(shapes),
        "has_footprint": bool(pkg_shapes),
        "pad_count": sum(1 for s in pkg_shapes if s.startswith("PAD~")),
        "subpart_count": len(result.get("subparts") or []),
    }
