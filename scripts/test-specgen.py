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
import tempfile
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--executable', help='Validate the PyInstaller EXE instead of the Python source')
args = parser.parse_args()
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    port = sock.getsockname()[1]
command = [args.executable] if args.executable else [sys.executable, str(ROOT / "toolbox/selfsoftware2/app/server.py")]
error_output = tempfile.TemporaryFile()
child_env = os.environ.copy()
# Verify source startup also survives an output stream that cannot encode Chinese.
child_env['PYTHONIOENCODING'] = 'ascii'
process = subprocess.Popen(command + ["--port", str(port), "--no-browser"],
                           stdout=subprocess.DEVNULL, stderr=error_output, env=child_env)
try:
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
    deadline = time.monotonic() + 45
    while time.monotonic() < deadline:
        if process.poll() is not None:
            # A one-file bootloader's child may inherit stderr. Reading a PIPE
            # would wait for that child indefinitely even after the parent exits.
            error_output.seek(0)
            raise RuntimeError("Application exited with code " + str(process.returncode)
                               + ': ' + error_output.read().decode("utf-8", "replace"))
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
            kernel = ctypes.windll.kernel32
            kernel.OpenProcess.restype = wintypes.HANDLE
            kernel.OpenProcess.argtypes = [wintypes.DWORD, wintypes.BOOL, wintypes.DWORD]
            kernel.QueryFullProcessImageNameW.argtypes = [wintypes.HANDLE, wintypes.DWORD, wintypes.LPWSTR, ctypes.POINTER(wintypes.DWORD)]
            kernel.CloseHandle.argtypes = [wintypes.HANDLE]
            callback = ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
            def describe_text(hwnd, unused):
                value = ctypes.create_unicode_buffer(4096)
                user.GetWindowTextW(hwnd, value, len(value))
                if value.value:
                    print('Application dialog: ' + value.value, file=sys.stderr)
                return True
            def describe(hwnd, unused):
                pid = wintypes.DWORD()
                user.GetWindowThreadProcessId(hwnd, ctypes.byref(pid))
                owned = pid.value == process.pid
                if args.executable:
                    handle = kernel.OpenProcess(0x1000, False, pid.value)
                    if handle:
                        image = ctypes.create_unicode_buffer(32768)
                        length = wintypes.DWORD(len(image))
                        owned = bool(kernel.QueryFullProcessImageNameW(handle, 0, image, ctypes.byref(length))) and Path(image.value) == Path(args.executable).resolve()
                        kernel.CloseHandle(handle)
                if owned:
                    describe_text(hwnd, 0)
                    user.EnumChildWindows(hwnd, callback(describe_text), 0)
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
    error_output.close()
