# SPDX-License-Identifier: GPL-3.0-only
"""Publish an existing tag using UTF-8 JSON files, avoiding shell pipe encoding."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('tag')
    parser.add_argument('--repo', default='KavasDD/KaiTools')
    parser.add_argument('--gh', default='gh')
    args = parser.parse_args()
    version = args.tag.removeprefix('v')
    notes = (ROOT / 'docs/releases' / f'{args.tag}.md').read_text('utf-8-sig')
    title = notes.splitlines()[0].removeprefix('# ')
    if not title or '???' in notes or '\ufffd' in notes:
        raise SystemExit('Release notes have invalid text')
    artifacts = ROOT / 'artifacts'
    expected = [f'XiaokaiToolbox-setup-v{version}.exe',
                f'XiaokaiToolbox-portable-v{version}.zip',
                f'XKGJX-source-v{version}.zip', 'SHA256SUMS.txt']
    for name in expected:
        if not (artifacts / name).is_file():
            raise SystemExit(f'Missing artifact: {name}')
    for line in (artifacts / 'SHA256SUMS.txt').read_text('utf-8-sig').splitlines():
        digest, name = line.split('  ', 1)
        if name not in expected or hashlib.sha256((artifacts / name).read_bytes()).hexdigest() != digest:
            raise SystemExit(f'Checksum mismatch: {name}')

    def gh(*command):
        return subprocess.check_output([args.gh, *command], cwd=ROOT).decode('utf-8')

    def api(method, route, payload):
        with tempfile.TemporaryDirectory(prefix='xiaokai-release-') as temp:
            path = Path(temp) / 'payload.json'
            path.write_text(json.dumps(payload, ensure_ascii=False), encoding='utf-8')
            return json.loads(gh('api', '--method', method, route, '--input', str(path)))

    # A tag must already exist on GitHub; never create one implicitly.
    gh('api', f'repos/{args.repo}/git/ref/tags/{args.tag}')
    release = api('POST', f'repos/{args.repo}/releases',
                  {'tag_name': args.tag, 'name': title, 'body': notes, 'draft': True})
    gh('release', 'upload', args.tag, '--repo', args.repo,
       *(str(artifacts / name) for name in expected))
    release = api('PATCH', f'repos/{args.repo}/releases/{release["id"]}',
                  {'draft': False, 'make_latest': 'true'})
    actual = json.loads(gh('api', f'repos/{args.repo}/releases/tags/{args.tag}'))
    if actual['name'] != title or actual['body'].replace('\r\n', '\n').rstrip() != notes.rstrip():
        raise SystemExit('Release title/body verification failed')
    if {asset['name'] for asset in actual['assets']} != set(expected):
        raise SystemExit('Release assets verification failed')
    for asset in actual['assets']:
        digest = 'sha256:' + hashlib.sha256((artifacts / asset['name']).read_bytes()).hexdigest()
        if asset.get('digest') and asset['digest'] != digest:
            raise SystemExit('GitHub asset digest mismatch: ' + asset['name'])
    print(actual['html_url'])
    print('Verified UTF-8 title/body, four assets and GitHub SHA-256 digests.')


if __name__ == '__main__':
    main()
