# SPDX-License-Identifier: GPL-3.0-only
# -*- coding: utf-8 -*-
"""元器件规格描述生成器 —— 本地小工具（只用 Python 标准库）。

    python app/server.py            # 启动并自动打开浏览器
    python app/server.py --port 9000 --no-browser

只监听 127.0.0.1，不对外网开放，因此没有做登录鉴权；
请不要把它改成 0.0.0.0 暴露到局域网。

发行版不显示命令行窗口，所以：
  * 起不来（端口占用、缺文件）要弹窗告知，不能一闪就没；
  * 出错细节写日志文件，位置在网页的运行状态里给出；
  * 退出改成网页上的按钮（/api/quit），没有黑窗口可关了。
"""
import argparse
import ctypes
import json
import mimetypes
import os
import secrets
import sys
import threading
import time
import traceback
import urllib.request
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs

# 打包成 exe 后，网页文件和 schema.json 被解到 sys._MEIPASS 这个临时目录里，
# 不能再用 __file__ 所在目录去找。
if getattr(sys, 'frozen', False):
    HERE = sys._MEIPASS
else:
    HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import config  # noqa: E402
import lcsc  # noqa: E402

SCHEMA_PATH = os.path.join(HERE, 'schema.json')
STATIC = {'/': 'index.html', '/index.html': 'index.html',
          '/app.js': 'app.js', '/style.css': 'style.css'}

# 启动信息给网页用。以前只 print 到控制台，但那个黑窗口用户一般不看，
# 打包成 exe 后更是能最小化就最小化，出了问题只能来问我。
START = {'port': 0, 'at': 0.0, 'log': '', 'token': ''}

# 日志文件。没有控制台了，出错信息必须落到文件里，否则用户只看到"抓取失败"。
# 放用户目录，程序目录可能在只读位置（比如 Program Files 或网盘）。
LOG_PATH = os.path.join(
    os.environ.get('LOCALAPPDATA') or os.path.expanduser('~'),
    '元器件规格描述生成器', 'run.log')


def log(msg):
    """写一行日志，失败也不能影响主流程。"""
    try:
        os.makedirs(os.path.dirname(LOG_PATH), exist_ok=True)
        with open(LOG_PATH, 'a', encoding='utf-8') as fh:
            fh.write('[%s] %s\n' % (time.strftime('%Y-%m-%d %H:%M:%S'), msg))
    except OSError:
        pass


def alert(msg, title='元器件规格描述生成器'):
    """弹个窗。没有控制台，起不来的时候只能靠这个告诉用户原因。"""
    log('弹窗：' + msg.replace('\n', ' '))
    try:
        # 0x10 = MB_ICONERROR，0x40000 = MB_TOPMOST，别被浏览器窗口盖住
        ctypes.windll.user32.MessageBoxW(None, msg, title, 0x10 | 0x40000)
    except Exception:
        # pythonw / --windowed 下 stderr 是 None，写它会再抛一个异常
        if sys.stderr is not None:
            sys.stderr.write(msg + '\n')


def say(msg):
    """往控制台写一行。发行版没有控制台，stdout 是 None，写了会炸。"""
    if sys.stdout is not None:
        try:
            print(msg)
        except OSError:
            pass


def load_schema():
    with open(SCHEMA_PATH, encoding='utf-8') as f:
        return json.load(f)


_schema_mtime = None
_cfg_mtime = None
CFG = {'notes': [], 'err': ''}          # 配置的加载情况，给 /api/status 看


def _cfg_stamp():
    """配置文件的 mtime。没有这个文件也是一种状态，用 0 表示。"""
    try:
        return os.path.getmtime(config.path())
    except OSError:
        return 0


def schema_now():
    """取当前 schema（已经盖上配置），schema.json 或 config.json 变了就重算。

    以前是启动时读一次就一直用。结果重新生成 schema 后，还开着的旧窗口会
    一直发旧数据，界面上看不出任何异常——改成固定值的字段照旧显示成可填的输入框，
    很容易以为代码没生效。这文件几百 KB，变了才读，代价可以忽略。

    配置也一起盯着 mtime：改完名字点保存，界面刷一下就能看到，不用重启。
    """
    global _schema_mtime, _cfg_mtime
    try:
        m = os.path.getmtime(SCHEMA_PATH)
    except OSError:
        return Handler.schema
    c = _cfg_stamp()
    if m != _schema_mtime or c != _cfg_mtime:
        base = load_schema()
        cfg, err = config.load()
        merged, notes = config.apply(base, cfg)
        CFG['notes'], CFG['err'] = notes, err
        if err:
            log('配置：' + err)
        for n in notes:
            log('配置：' + n)
        Handler.schema = merged
        _schema_mtime, _cfg_mtime = m, c
    return Handler.schema


def find_fields(schema, cat_code, type_name):
    """按分类编号 + 物料名称找到字段定义。"""
    for cat in schema['categories']:
        if cat['code'] != cat_code:
            continue
        for t in cat['types']:
            if t['name'] == type_name:
                return t['fields']
    return None

class Handler(BaseHTTPRequestHandler):
    server_version = 'SpecTool/1.0'
    schema = None

    def log_message(self, fmt, *args):
        # 没有控制台了，出错的请求写进日志文件，方便事后查。
        # log_request 传进来的是 (requestline, code, size)，状态码在 args[1]。
        code = str(args[1]) if len(args) > 1 else ''
        if not code.startswith('2'):
            log('%s - %s' % (self.address_string(), fmt % args))

    def _send(self, code, body, ctype='application/json; charset=utf-8'):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode('utf-8')
        elif isinstance(body, str):
            body = body.encode('utf-8')
        self.send_response(code)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        path = urlparse(self.path).path
        if path in STATIC:
            return self._static(STATIC[path])
        if path == '/api/schema':
            return self._send(200, schema_now())
        if path == '/api/status':
            return self._send(200, self._status())
        if path == '/api/quit':
            return self._quit(parse_qs(urlparse(self.path).query))
        if path == '/api/config':
            return self._get_config()
        if path == '/api/lcsc':
            return self._lcsc(parse_qs(urlparse(self.path).query))
        self._send(404, {'error': '没有这个地址'})

    def do_POST(self):
        path = urlparse(self.path).path
        if path == '/api/config':
            return self._put_config(parse_qs(urlparse(self.path).query))
        self._send(404, {'error': '没有这个地址'})

    def _get_config(self):
        """把配置原样给网页，另外带上表格里的原始分类，界面上才能对照着改。"""
        cfg, err = config.load()
        base = load_schema()
        cats = [{'code': c['code'], 'name': c['name'],
                 'types': [t['name'] for t in c['types']]}
                for c in base['categories']]
        return self._send(200, {'config': cfg, 'path': config.path(),
                                'base': cats, 'err': err,
                                'notes': CFG['notes']})

    def _put_config(self, q):
        """保存配置。跟 /api/quit 一样要 token——别的网页也能 POST 到
        127.0.0.1，不校验的话它们能改掉用户的配置。"""
        if (q.get('token') or [''])[0] != START['token']:
            return self._send(403, {'error': '口令不对，拒绝保存'})
        try:
            n = int(self.headers.get('Content-Length') or 0)
        except ValueError:
            return self._send(400, {'error': '请求头不对'})
        if n <= 0 or n > 2 * 1024 * 1024:      # 配置就几 KB，超了肯定不对
            return self._send(400, {'error': '内容为空或过大'})
        try:
            body = json.loads(self.rfile.read(n).decode('utf-8'))
        except (ValueError, UnicodeDecodeError) as e:
            return self._send(400, {'error': '内容不是合法 JSON：%s' % e})
        if not isinstance(body, dict):
            return self._send(400, {'error': '内容必须是一个对象'})
        cfg = config.blank()
        for k in cfg:
            v = body.get(k)
            if isinstance(v, (dict, list)):
                cfg[k] = v
        # 先试着盖一遍。配置写坏了（比如改名撞车）在这儿就能看出来，
        # 别等存下去之后界面变空才发现。
        try:
            merged, notes = config.apply(load_schema(), cfg)
        except Exception as e:
            return self._send(400, {'error': '这份配置套不上去：%s' % e})
        if not merged['categories']:
            return self._send(400, {'error': '这么改会把所有物料都藏起来，没保存'})
        try:
            p = config.save(cfg)
        except OSError as e:
            return self._send(500, {'error': '写配置文件失败：%s' % e})
        log('配置已保存到 %s' % p)
        # 下次 schema_now() 会看到新的 mtime，自己重算
        return self._send(200, {'ok': True, 'path': p, 'notes': notes,
                                'types': sum(len(c['types'])
                                             for c in merged['categories'])})

    def _quit(self, q):
        """网页上点"退出"用。没有控制台窗口可关，只能这样退。

        带一个启动时随机生成的 token：本机上别的网页（或者装了什么浏览器
        插件）也能访问 127.0.0.1，不校验的话它们能悄悄把工具关掉。
        """
        if (q.get('token') or [''])[0] != START['token']:
            return self._send(403, {'error': '口令不对，拒绝退出'})
        self._send(200, {'ok': True})
        log('用户从网页点了退出')
        # 先把这个响应发完再停，否则浏览器那边看到的是连接被掐断
        threading.Thread(target=self.server.shutdown, daemon=True).start()

    def _status(self):
        """控制台原来打印的那些，改成给网页看。"""
        sch = schema_now()
        cats = sch['categories']
        return {
            'port': START['port'],
            'source': sch.get('source', ''),
            'cats': len(cats),
            'types': sum(len(c['types']) for c in cats),
            # schema 重新生成过就变，界面上能看出用的是新表还是旧表
            'schemaAt': time.strftime('%Y-%m-%d %H:%M',
                                      time.localtime(_schema_mtime or 0)),
            'upSec': int(time.time() - START['at']) if START['at'] else 0,
            'frozen': bool(getattr(sys, 'frozen', False)),
            'log': LOG_PATH,
            'token': START['token'],
            'cfg': config.path(),
            'cfgOn': os.path.isfile(config.path()),
            # 配置有问题要在界面上说出来，否则只会觉得"改了没生效"
            'cfgErr': CFG['err'],
            'cfgNotes': CFG['notes'],
        }

    def _static(self, name):
        full = os.path.join(HERE, name)
        if not os.path.isfile(full):
            return self._send(404, {'error': f'缺少文件 {name}'})
        ctype = mimetypes.guess_type(name)[0] or 'application/octet-stream'
        with open(full, 'rb') as f:
            data = f.read()
        self._send(200, data, f'{ctype}; charset=utf-8')

    def _lcsc(self, q):
        code = (q.get('code') or [''])[0]
        cat = (q.get('cat') or [''])[0]
        tname = (q.get('type') or [''])[0]
        if not cat or not tname:
            return self._send(400, {'error': '请先在左边选一种物料，再抓取参数'})
        try:
            info = lcsc.fetch(code)
        except RuntimeError as e:
            return self._send(502, {'error': str(e)})
        except Exception as e:                     # 网络层的意外情况
            return self._send(502, {'error': f'抓取出错：{e}'})

        fields = find_fields(schema_now(), cat, tname)
        if fields is None:
            # 别静默返回空结果，否则界面只显示"已填 0 项"，看不出原因
            return self._send(400, {'error': f'表格里没有「{cat} / {tname}」这种物料'})
        out = {'info': info}
        out.update(lcsc.map_to_fields(info, fields))
        return self._send(200, out)


class Server(ThreadingHTTPServer):
    """把 allow_reuse_address 关掉。

    标准库的 HTTPServer 默认开 SO_REUSEADDR。在 Windows 上这个选项的语义和
    Unix 不一样：它允许另一个进程绑到已经在 LISTEN 的同一个端口上，bind 不
    报错，于是同一端口挂着两个服务，新连接给谁不确定。实测就撞上了——8765 上
    同时躺着昨天的旧服务和新起的这个，接口一半走旧的，返回 404。
    关掉之后端口被占用会老实抛 OSError，listen() 才能往后找空端口。
    """
    allow_reuse_address = False


def _is_ours(port):
    """这个端口上跑的是不是本工具的另一个实例。"""
    try:
        with urllib.request.urlopen(
                'http://127.0.0.1:%d/api/status' % port, timeout=1.5) as r:
            return isinstance(json.load(r).get('types'), int)
    except Exception:
        return False


def listen(port, auto):
    """占端口。被占用时往后找空的，返回 (httpd, 实际端口)。

    没有控制台窗口了，所以"端口被占用"不能只抛异常了事——那样双击后
    什么都不发生。已经开着一个的话直接把浏览器指过去，别再起第二个。
    """
    last = None
    for p in range(port, port + (20 if auto else 1)):
        if _is_ours(p):
            return None, p          # 已经有一个在跑，复用它
        try:
            return Server(('127.0.0.1', p), Handler), p
        except OSError as e:
            last = e
    raise OSError(last)


def main():
    ap = argparse.ArgumentParser(description='元器件规格描述生成器')
    ap.add_argument('--port', type=int, default=8765)
    ap.add_argument('--no-browser', action='store_true')
    ap.add_argument('--fixed-port', action='store_true',
                    help='端口被占用就报错，不自动往后找')
    args = ap.parse_args()

    if not os.path.isfile(SCHEMA_PATH):
        return alert('缺少 schema.json，程序无法启动。\n\n'
                     '这个文件是从规格表格生成的，请重新解压一份完整的程序，'
                     '或运行 tools/extract_schema.py 生成。')
    try:
        schema_now()           # 顺手记下 mtime，免得第一个请求又读一遍
    except (OSError, ValueError) as e:
        return alert('schema.json 读不出来，程序无法启动。\n\n%s' % e)

    try:
        httpd, port = listen(args.port, not args.fixed_port)
    except OSError as e:
        return alert('端口 %d 起不来，程序无法启动。\n\n%s\n\n'
                     '可以换个端口重试。' % (args.port, e))

    url = 'http://127.0.0.1:%d/' % port
    if httpd is None:
        # 已经开着一个了，把浏览器指过去就行，别起第二个占着端口
        log('已有实例在 %d，复用' % port)
        webbrowser.open(url)
        return

    START.update(port=port, at=time.time(), log=LOG_PATH,
                 token=secrets.token_urlsafe(16))
    log('启动于 %s' % url)
    # 源码运行时控制台能看见地址；发行版没有控制台，say 会自己跳过
    say('已启动：%s' % url)
    if not args.no_browser:
        threading.Timer(0.6, webbrowser.open, [url]).start()
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
        log('已退出')


if __name__ == '__main__':
    try:
        main()
    except Exception:
        # 没有控制台，未捕获的异常会静默死掉，必须弹窗 + 写日志
        alert('程序出错退出了。\n\n%s\n\n详细信息见日志：\n%s'
              % (traceback.format_exc().strip().split('\n')[-1], LOG_PATH))
        log('未捕获的异常：\n' + traceback.format_exc())
        raise
