# SPDX-License-Identifier: GPL-3.0-only
"""Exercise the real local server without writing user config or using the network."""
from pathlib import Path
import argparse
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
    for attempt in range(300):
        if process.poll() is not None:
            raise RuntimeError(process.stderr.read().decode("utf-8", "replace"))
        try:
            with opener.open(f"http://127.0.0.1:{port}/", timeout=1) as response:
                assert "元器件规格描述生成器" in response.read().decode("utf-8")
            break
        except OSError:
            time.sleep(0.1)
    else:
        raise RuntimeError("Local server did not start")
    for asset in ("app.js", "style.css"):
        with opener.open(f"http://127.0.0.1:{port}/{asset}", timeout=3) as response:
            assert response.status == 200 and response.read()
    with opener.open(f"http://127.0.0.1:{port}/api/schema", timeout=3) as response:
        assert json.load(response)["categories"]
    print("PASS: specification generator starts; HTML, assets and schema are available (" + ("EXE" if args.executable else "source") + ")")
finally:
    process.terminate()
    process.wait(timeout=10)
