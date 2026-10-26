# SPDX-License-Identifier: GPL-3.0-only
# -*- coding: utf-8 -*-
"""嘉立创 3D 模型下载器 (JLC3D-Downloader)

按元器件编号(如 C8734)从嘉立创把对应的 STEP 3D 模型抓下来。

只用标准库。原来那版为了三个 POST 依赖 requests,打包时跟着把整个包
塞进 exe —— urllib 够用,少一个依赖,也少一步 pip。

打包成 exe:  powershell -NoProfile -File toolbox\\make-jlc3d.ps1
"""
import configparser
import json
import os
import re
import subprocess
import sys
import threading
import tkinter as tk
import urllib.error
import urllib.parse
import urllib.request
import webbrowser
from datetime import datetime
from tkinter import filedialog, messagebox, scrolledtext, ttk

APP_NAME = "嘉立创 3D 模型下载器"
VERSION = "2.0"
HOME_URL = "https://github.com/zhutongxueya/JLC3DDownload"

CONFIG_DIR = os.path.join(os.path.expanduser("~"), ".jlc3d")
CONFIG_FILE = os.path.join(CONFIG_DIR, "config.ini")


def default_dir():
    """默认存桌面。取不到就退回用户目录 —— 域账户的桌面可能被重定向掉。"""
    desktop = os.path.join(os.path.expanduser("~"), "Desktop")
    return desktop if os.path.isdir(desktop) else os.path.expanduser("~")


def load_download_dir():
    """读记住的下载目录。配置坏了不算错,退回默认值就行。"""
    try:
        cfg = configparser.ConfigParser()
        cfg.read(CONFIG_FILE, encoding="utf-8")
        saved = cfg.get("PATH", "DownloadPath", fallback="")
        if saved and os.path.isdir(saved):
            return saved
    except (configparser.Error, OSError):
        pass
    return default_dir()

def save_download_dir(path):
    try:
        os.makedirs(CONFIG_DIR, exist_ok=True)
        cfg = configparser.ConfigParser()
        cfg["PATH"] = {"DownloadPath": path}
        with open(CONFIG_FILE, "w", encoding="utf-8") as f:
            cfg.write(f)
    except OSError:
        pass          # 记不住路径只是下次要重选,不该为此弹错误框


# =====================================================
# 嘉立创 API
# =====================================================
BASE_API = "https://pro.lceda.cn/api"
MODULE_URL = "https://modules.lceda.cn/qAxj6KHrDKw4blvCG8QJPs7Y/"

# Referer 和 Origin 必须带 —— 少了直接 403,而且返回的是一页 HTML,
# 不是 JSON 错误,所以症状是解析失败而不是"没权限"。
HEADERS = {
    "User-Agent": ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
                   "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0 Safari/537.36"),
    "Referer": "https://pro.lceda.cn/",
    "Origin": "https://pro.lceda.cn",
}

CODE_RE = re.compile(r"^C\d{1,10}$", re.IGNORECASE)


class ApiError(Exception):
    """能直接显示给用户看的错误。堆栈对用户没用。"""


def _post(path, fields):
    body = urllib.parse.urlencode(fields, doseq=True).encode("utf-8")
    req = urllib.request.Request(BASE_API + path, data=body,
                                 headers=HEADERS, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as resp:
            raw = resp.read()
    except urllib.error.HTTPError as exc:
        raise ApiError("服务器返回 HTTP %s" % exc.code) from exc
    except urllib.error.URLError as exc:
        raise ApiError("连不上嘉立创(%s),检查网络或代理" % exc.reason) from exc
    except TimeoutError as exc:
        raise ApiError("请求超时,网络太慢或被挡住了") from exc
    try:
        data = json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, ValueError) as exc:
        raise ApiError("返回的不是 JSON,接口可能改了") from exc
    # 查不到时没有 result 这个键,所以必须先看 success 再取 result。
    if not data.get("success", True):
        raise ApiError(data.get("message") or "接口返回失败")
    return data

def search_product(code):
    """按编号找器件,返回 (device_uuid, 型号)。

    搜索是**模糊**的:查 C8734 会连 DAC8734SPFB 一起返回。原来那版直接取
    第一条,所以编号打错一位就静悄悄下载了另一个件的模型 —— 文件名还是你
    输入的那个编号,根本看不出来。这里只认编号完全相同的那条。
    """
    data = _post("/eda/product/search",
                 {"keyword": code, "needAggs": "true",
                  "currPage": "1", "pageSize": "10"})
    products = (data.get("result") or {}).get("productList") or []
    if not products:
        raise ApiError("没有找到 %s" % code)

    want = code.upper()
    exact = [p for p in products if (p.get("code") or "").upper() == want]
    if not exact:
        near = ", ".join((p.get("code") or "?") for p in products[:3])
        raise ApiError("没有编号为 %s 的器件(搜到的是 %s)" % (code, near))

    hit = exact[0]
    device = hit.get("hasDevice")
    if not device:
        raise ApiError("%s(%s)在立创EDA里没有符号/模型数据"
                       % (code, hit.get("model") or "型号未知"))
    return device, (hit.get("model") or "")


def get_model_uuid(device_uuid):
    data = _post("/devices/searchByIds", {"uuids[]": device_uuid})
    result = data.get("result") or []
    if not result:
        raise ApiError("器件数据是空的")
    attrs = result[0].get("attributes") or {}
    if not attrs.get("3D Model"):
        raise ApiError("这个器件没有 3D 模型")
    return attrs["3D Model"], attrs.get("3D Model Title") or ""


def get_model_file(model_uuid):
    data = _post("/components/searchByIds?forceOnline=1",
                 {"uuids[]": model_uuid, "dataStr": "yes"})
    result = data.get("result") or []
    if not result:
        raise ApiError("取不到 3D 模型记录")
    try:
        payload = json.loads(result[0]["dataStr"])
    except (KeyError, ValueError) as exc:
        raise ApiError("3D 模型记录的格式不对") from exc
    if not payload.get("model"):
        raise ApiError("3D 模型记录里没有文件名")
    return payload["model"], result[0].get("title") or ""

def download_step(model_file, on_progress=None, should_stop=None):
    """边下边报进度。STEP 动辄十几 MB,一次 read() 到底的话进度条是假的。"""
    req = urllib.request.Request(MODULE_URL + model_file, headers=HEADERS)
    chunks = []
    got = 0
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            total = int(resp.headers.get("Content-Length") or 0)
            while True:
                if should_stop is not None and should_stop():
                    raise ApiError("已取消")
                block = resp.read(65536)
                if not block:
                    break
                chunks.append(block)
                got += len(block)
                if on_progress is not None:
                    on_progress(got, total)
    except urllib.error.HTTPError as exc:
        raise ApiError("下载失败,HTTP %s" % exc.code) from exc
    except urllib.error.URLError as exc:
        raise ApiError("下载中断(%s)" % exc.reason) from exc
    except TimeoutError as exc:
        raise ApiError("下载超时") from exc

    data = b"".join(chunks)
    # 认一下文件头。接口出错时会返回一页 HTML,存下来也是个 .step,
    # 直到在 CAD 里打不开才发现 —— 那时候早就不知道是哪一步的问题了。
    if not data.lstrip()[:13].startswith(b"ISO-10303-21"):
        raise ApiError("返回的不是 STEP 文件(可能是错误页)")
    return data


# =====================================================
# 存盘
# =====================================================
BAD_CHARS = re.compile(r'[<>:"/\\|?*\x00-\x1f]')


def safe_name(text):
    """Windows 不收的字符换成下划线。型号里带 / 的很常见(如 74HC00/SO14)。"""
    cleaned = BAD_CHARS.sub("_", text).strip(" .")
    return cleaned[:80] or "model"


def unique_path(folder, stem, ext=".step"):
    """已经有同名文件就加 (2)(3),不覆盖。

    重下一遍常常是为了对比新旧,直接覆盖会把上一个悄悄弄没了。
    """
    candidate = os.path.join(folder, stem + ext)
    n = 2
    while os.path.exists(candidate):
        candidate = os.path.join(folder, "%s (%d)%s" % (stem, n, ext))
        n += 1
    return candidate


def write_atomic(path, data):
    """先写 .part 再改名。写一半断电/断网的话,留下的是 .part,
    不是一个看着能用、实际截断了的 .step。"""
    tmp = path + ".part"
    with open(tmp, "wb") as f:
        f.write(data)
    os.replace(tmp, path)

def reveal(path):
    """在文件管理器里选中这个文件。"""
    if sys.platform.startswith("win"):
        # explorer 的 /select 后面必须紧跟逗号,而且路径要是反斜杠形式。
        # 它对成功也返回 1,所以不看返回码。
        subprocess.Popen(["explorer", "/select,", os.path.normpath(path)])
    elif sys.platform == "darwin":
        subprocess.Popen(["open", "-R", path])
    else:
        subprocess.Popen(["xdg-open", os.path.dirname(path)])


def app_icon():
    """打包后 .ico 跟在 exe 边上(--add-data),开发时在 toolbox\\ 里。"""
    names = []
    base = getattr(sys, "_MEIPASS", None)
    if base:
        names.append(os.path.join(base, "jlc3d.ico"))
    here = os.path.dirname(os.path.abspath(__file__))
    names.append(os.path.join(os.path.dirname(here), "jlc3d.ico"))
    names.append(os.path.join(here, "jlc3d.ico"))
    for name in names:
        if os.path.isfile(name):
            return name
    return None


# =====================================================
# 界面
# =====================================================
BG = "#f8f9fa"
GREEN = "#28a745"
GREY = "#6c757d"


class JLC3DApp(tk.Tk):
    def __init__(self):
        super().__init__()
        self.title("%s v%s" % (APP_NAME, VERSION))
        self.configure(bg=BG)
        self.minsize(560, 400)
        self.center(self, 620, 460)

        icon = app_icon()
        if icon:
            try:
                self.iconbitmap(icon)
            except tk.TclError:
                pass      # 图标坏了不该让程序起不来

        self.download_dir = load_download_dir()
        self.last_file = None
        self.busy = False
        self.cancel = False

        self.build_menu()
        self.build_ui()
        self.entry.focus_set()
        self.log_line("输入元器件编号,回车开始。多个编号用空格或逗号隔开。")

    @staticmethod
    def center(win, width, height):
        win.update_idletasks()
        x = (win.winfo_screenwidth() - width) // 2
        y = (win.winfo_screenheight() - height) // 2
        win.geometry("%dx%d+%d+%d" % (width, height, max(x, 0), max(y, 0)))

    def build_menu(self):
        bar = tk.Menu(self)
        self.config(menu=bar)

        file_menu = tk.Menu(bar, tearoff=0)
        bar.add_cascade(label="文件", menu=file_menu)
        file_menu.add_command(label="修改下载路径...", command=self.choose_dir)
        file_menu.add_command(label="打开下载目录", command=self.open_dir)
        file_menu.add_separator()
        file_menu.add_command(label="退出", command=self.destroy)

        help_menu = tk.Menu(bar, tearoff=0)
        bar.add_cascade(label="帮助", menu=help_menu)
        help_menu.add_command(label="关于", command=self.show_about)

    def build_ui(self):
        root = tk.Frame(self, bg=BG, padx=20, pady=12)
        root.pack(fill="both", expand=True)

        row = tk.Frame(root, bg=BG)
        row.pack(pady=(24, 4), fill="x")

        tk.Label(row, text="元器件编号:", bg=BG,
                 font=("Microsoft YaHei", 12, "bold")).pack(side="left", padx=(0, 10))

        self.entry = ttk.Entry(row, font=("Consolas", 14))
        self.entry.pack(side="left", fill="x", expand=True)
        self.entry.bind("<Return>", lambda _e: self.start())

        self.btn = tk.Button(row, text="立即下载", bg=GREEN, fg="white",
                             font=("Microsoft YaHei", 11, "bold"), relief="flat",
                             width=10, cursor="hand2", activebackground="#1e7e34",
                             activeforeground="white", command=self.start)
        self.btn.pack(side="left", padx=(14, 0))

        # 进度条常驻。只在下载时才 pack 的话,每次出现都会把下面的控件顶一下。
        self.progress = ttk.Progressbar(root, mode="determinate", maximum=100)
        self.progress.pack(fill="x", pady=(12, 10))

        self.log = scrolledtext.ScrolledText(root, height=9, font=("Consolas", 10),
                                             bg="white", relief="solid", borderwidth=1,
                                             state="disabled", wrap="word")
        self.log.pack(fill="both", expand=True)

        foot = tk.Frame(root, bg=BG, pady=12)
        foot.pack(fill="x")
        self.path_label = tk.Label(foot, bg=BG, fg="#495057", anchor="w",
                                   font=("Microsoft YaHei", 9))
        self.path_label.pack(side="left", fill="x", expand=True)
        ttk.Button(foot, text="定位文件", width=10,
                   command=self.locate).pack(side="right")
        self.show_dir()

    # ---- 小工具 ----------------------------------------------------
    def show_dir(self):
        self.path_label.config(text="保存至: " + self.download_dir)

    def log_line(self, msg, stamp=True):
        self.log.config(state="normal")
        prefix = datetime.now().strftime("[%H:%M:%S] ") if stamp else ""
        self.log.insert("end", prefix + msg + "\n")
        self.log.see("end")
        self.log.config(state="disabled")

    def ui(self, fn, *a):
        """从工作线程回主线程。Tk 不是线程安全的,所有控件操作都得走这里。"""
        self.after(0, lambda: fn(*a))

    def choose_dir(self):
        picked = filedialog.askdirectory(initialdir=self.download_dir,
                                         title="选择模型保存目录")
        if picked:
            self.download_dir = picked
            save_download_dir(picked)
            self.show_dir()
            self.log_line("保存目录改为 " + picked)

    def open_dir(self):
        if os.path.isdir(self.download_dir):
            reveal(os.path.join(self.download_dir, "."))
        else:
            messagebox.showwarning(APP_NAME, "目录不存在:\n" + self.download_dir)

    def locate(self):
        if self.last_file and os.path.exists(self.last_file):
            reveal(self.last_file)
        else:
            messagebox.showinfo(APP_NAME, "还没有下载成功的文件可以定位。")

    def show_about(self):
        win = tk.Toplevel(self)
        win.title("关于")
        win.configure(bg=BG)
        win.transient(self)
        win.resizable(False, False)
        self.center(win, 420, 250)

        tk.Label(win, text=APP_NAME, bg=BG,
                 font=("Microsoft YaHei", 13, "bold")).pack(pady=(22, 6))
        tk.Label(win, text="版本 %s   作者 Jupiter" % VERSION, bg=BG,
                 fg="#495057", font=("Microsoft YaHei", 10)).pack()
        tk.Label(win, text="按元器件编号从嘉立创下载 STEP 3D 模型", bg=BG,
                 fg="#495057", font=("Microsoft YaHei", 9)).pack(pady=(10, 14))

        link = tk.Label(win, text=HOME_URL, bg=BG, fg="#0d6efd",
                        cursor="hand2", font=("Consolas", 9, "underline"))
        link.pack()
        link.bind("<Button-1>", lambda _e: webbrowser.open(HOME_URL))

        tk.Label(win, text="感谢 kulya97 的原始思路", bg=BG, fg="#868e96",
                 font=("Microsoft YaHei", 8)).pack(pady=(14, 0))
        ttk.Button(win, text="关闭", command=win.destroy).pack(pady=14)

    # ---- 下载 ------------------------------------------------------
    def parse_codes(self, text):
        """空格/逗号/分号/换行都当分隔符。从浏览器复制过来常常带一堆空白。"""
        seen, codes, bad = set(), [], []
        for token in re.split(r"[\s,;、]+", text.strip()):
            if not token:
                continue
            token = token.upper()
            if not CODE_RE.match(token):
                bad.append(token)
            elif token not in seen:
                seen.add(token)
                codes.append(token)
        return codes, bad

    def start(self):
        if self.busy:            # 回车按连击时别开第二个线程
            return
        codes, bad = self.parse_codes(self.entry.get())
        if bad:
            messagebox.showwarning(APP_NAME,
                                   "这些不像立创商品编号:\n\n%s\n\n"
                                   "编号是 C 加数字,例如 C8734。"
                                   % "  ".join(bad[:8]))
            return
        if not codes:
            messagebox.showwarning(APP_NAME, "请先输入元器件编号,例如 C8734。")
            return
        if not os.path.isdir(self.download_dir):
            messagebox.showwarning(APP_NAME,
                                   "保存目录不存在:\n%s\n\n"
                                   "用 文件 - 修改下载路径 重新选一个。"
                                   % self.download_dir)
            return

        self.busy = True
        self.cancel = False
        self.btn.config(text="取消", bg=GREY, command=self.stop)
        threading.Thread(target=self.worker, args=(codes,), daemon=True).start()

    def stop(self):
        self.cancel = True
        self.btn.config(state="disabled", text="取消中")

    def finish(self):
        self.busy = False
        self.cancel = False
        self.progress.config(value=0)
        self.btn.config(state="normal", text="立即下载", bg=GREEN, command=self.start)

    def set_progress(self, got, total):
        if total > 0:
            self.progress.config(mode="determinate", value=got * 100.0 / total)
        else:
            # 没有 Content-Length 时百分比是编不出来的,改成来回跑的条。
            if str(self.progress.cget("mode")) != "indeterminate":
                self.progress.config(mode="indeterminate")
                self.progress.start(12)

    def worker(self, codes):
        ok = 0
        for index, code in enumerate(codes, 1):
            if self.cancel:
                self.ui(self.log_line, "已取消,剩下 %d 个没下。" % (len(codes) - index + 1))
                break
            tag = "[%d/%d] " % (index, len(codes)) if len(codes) > 1 else ""
            try:
                self.ui(self.log_line, "%s%s 查询器件..." % (tag, code))
                device, model = search_product(code)
                if model:
                    self.ui(self.log_line, "    型号 " + model)

                model_uuid, _title = get_model_uuid(device)
                model_file, _t = get_model_file(model_uuid)

                self.ui(self.log_line, "    下载 STEP...")
                data = download_step(
                    model_file,
                    on_progress=lambda got, total: self.ui(self.set_progress, got, total),
                    should_stop=lambda: self.cancel)

                stem = "%s_%s" % (code, safe_name(model)) if model else code
                path = unique_path(self.download_dir, stem)
                write_atomic(path, data)
                self.last_file = path
                ok += 1
                self.ui(self.log_line, "    完成 %.1f MB  ->  %s"
                        % (len(data) / 1048576.0, os.path.basename(path)))
            # 捕获后立刻转成字符串。写成 lambda: ...{e}... 的话,except 块一结束
            # Python 就把 e 解绑了,回到主线程再求值就是 NameError —— 于是错误
            # 信息一个字都不显示,真正的原因还被那个 NameError 盖掉。
            except ApiError as exc:
                self.ui(self.log_line, "    失败:%s" % exc)
            except OSError as exc:
                self.ui(self.log_line, "    写文件失败:%s" % exc)
            except Exception as exc:                     # noqa: BLE001
                self.ui(self.log_line, "    意外错误:%s: %s"
                        % (type(exc).__name__, exc))

        if len(codes) > 1:
            self.ui(self.log_line, "共 %d 个,成功 %d 个。" % (len(codes), ok))
        self.ui(self.progress.stop)
        self.ui(self.finish)


def main():
    app = JLC3DApp()
    app.mainloop()


if __name__ == "__main__":
    main()
