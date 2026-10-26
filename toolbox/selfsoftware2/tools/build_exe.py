# SPDX-License-Identifier: GPL-3.0-only
"""把工具打包成单个 exe（PyInstaller）。

用法：python tools/build_exe.py
产物：dist/元器件规格描述生成器.exe

网页文件和 schema.json 用 --add-data 塞进 exe，运行时由 server.py 从
sys._MEIPASS 读取。

用 --windowed 不显示命令行窗口。代价是出错信息没地方看，所以 server.py
里做了三件事顶上：起不来时弹 MessageBox、出错写日志文件、退出改成网页上
的按钮（没有窗口可关了）。
"""
import os
import shutil
import subprocess
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAME = '元器件规格描述生成器'
DATA = ['index.html', 'app.js', 'style.css', 'schema.json']


def main():
    app = os.path.join(ROOT, 'app')
    missing = [d for d in DATA if not os.path.isfile(os.path.join(app, d))]
    if missing:
        sys.exit('缺少文件：' + '、'.join(missing)
                 + '\nschema.json 需要先跑 tools/extract_schema.py 生成。')

    cmd = [sys.executable, '-m', 'PyInstaller',
           '--onefile', '--windowed', '--clean', '--noconfirm',
           '--name', NAME,
           '--distpath', os.path.join(ROOT, 'dist'),
           '--workpath', os.path.join(ROOT, 'build'),
           '--specpath', os.path.join(ROOT, 'build')]
    for d in DATA:
        # Windows 上 --add-data 的分隔符是分号，"." 表示放到解包目录根下
        cmd += ['--add-data', os.path.join(app, d) + os.pathsep + '.']
    # server.py 是用 sys.path + import 拿这两个模块的，PyInstaller 静态
    # 分析看不出来，得手动点名，否则打包版一启动就 ModuleNotFoundError
    cmd += ['--hidden-import', 'lcsc',
            '--hidden-import', 'config',
            '--paths', app,
            os.path.join(app, 'server.py')]

    print('运行：', ' '.join(cmd))
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode:
        sys.exit('打包失败，返回码 %d' % r.returncode)

    exe = os.path.join(ROOT, 'dist', NAME + '.exe')
    if not os.path.isfile(exe):
        sys.exit('打包完成但找不到 ' + exe)
    print('\n完成：%s（%.1f MB）' % (exe, os.path.getsize(exe) / 1048576))

    # build/ 只是中间产物，删掉省地方
    shutil.rmtree(os.path.join(ROOT, 'build'), ignore_errors=True)


if __name__ == '__main__':
    main()
