# SPDX-License-Identifier: GPL-3.0-only
"""Exercise the real local server without writing user config or using the network."""
from pathlib import Path
import argparse
import os
import json
import socket
import subprocess
import sys
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--executable', help='Validate the PyInstaller EXE instead of the Python source')
args = parser.parse_args()
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
command = [args.executable] if args.executable else [sys.executable, str(ROOT / "toolbox/selfsoftware2/app/server.py")]
process = subprocess.Popen(command + ["--port", str(port), "--no-browser"],
                           stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
try:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if process.poll() is not None:
            raise RuntimeError(process.stderr.read().decode("utf-8", "replace"))
        try:
            with opener.open(f"http://127.0.0.1:{port}/", timeout=1) as response:
                assert "元器件规格描述生成器" in response.read().decode("utf-8")
            break
        except OSError:
            time.sleep(0.1)
    else:
        log = Path(os.environ.get('LOCALAPPDATA', str(Path.home()))) / '\u5143\u5668\u4ef6\u89c4\u683c\u63cf\u8ff0\u751f\u6210\u5668' / 'run.log'
        if log.exists():
            print(log.read_text('utf-8')[-8000:], file=sys.stderr)
        # A windowed bootloader can show an error dialog before Python starts.
        if sys.platform == 'win32':
            import ctypes
            from ctypes import wintypes
            user = ctypes.windll.user32
            callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
            def describe(hwnd, unused):
                title = ctypes.create_unicode_buffer(4096)
                user.GetWindowTextW(hwnd, title, len(title))
                if title.value:
                    print('Window: ' + title.value, file=sys.stderr)
                return True
            user.EnumWindows(callback(describe), 0)
        raise RuntimeError("Local server did not start within 45 seconds")
    for asset in ("app.js", "style.css"):
        with opener.open(f"http://127.0.0.1:{port}/{asset}", timeout=3) as response:
            assert response.status == 200 and response.read()
    with opener.open(f"http://127.0.0.1:{port}/api/schema", timeout=3) as response:
        assert json.load(response)["categories"]
    print("PASS: specification generator starts; HTML, assets and schema are available (" + ("EXE" if args.executable else "source") + ")")
finally:
    if sys.platform == 'win32':
        subprocess.run(['taskkill', '/PID', str(process.pid), '/T', '/F'], capture_output=True)
    else:
        process.terminate()
    process.wait(timeout=10)
