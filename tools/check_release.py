"""Validate the release allowlist; optionally compare it with another mod copy.

The public Workshop package stops at ``tools/package-files.json``. The
experimental Steam P2P transport lives in a second manifest and is only added
when ``--dev-transport`` is passed, so a normal release can never ship those
binaries by accident while a test build still can.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent
DEV_MANIFEST = 'tools/package-dev-files.json'
# Everything the experimental manifest is allowed to add; anything else there is
# a mistake and would otherwise slip past the public allowlist.
DEV_PREFIX = 'steam-p2p/'


def _read_manifest(root, name):
    names = json.loads((root / name).read_text(encoding='utf-8'))
    if not isinstance(names, list) or not names:
        raise ValueError(f'{name} must be a nonempty list')
    return names


def release_files(root=ROOT, dev_transport=False):
    names = _read_manifest(root, 'tools/package-files.json')
    if dev_transport:
        names = names + _read_manifest(root, DEV_MANIFEST)
    mod = (root / 'onlinecoop').resolve()
    seen, result = set(), []
    for name in names:
        if not isinstance(name, str):
            raise ValueError('Release paths must be strings')
        rel = PurePosixPath(name)
        if not name or rel.is_absolute() or '..' in rel.parts or ':' in name or '\\' in name:
            raise ValueError(f'Unsafe release path: {name}')
        if name.casefold() in seen:
            raise ValueError(f'Duplicate release path: {name}')
        seen.add(name.casefold())
        path = (mod / name).resolve()
        if not path.is_relative_to(mod) or not path.is_file():
            raise ValueError(f'Missing or outside mod folder: {name}')
        if rel.parts[0] in ('tests', 'diagnostics') or path.suffix.lower() in ('.log', '.dmp', '.run'):
            raise ValueError(f'Diagnostic file in release: {name}')
        if rel.parts[0] == 'lan' and name not in ('lan/LanTransport.cs', 'lan/LanDiscovery.cs'):
            raise ValueError(f'Unexpected LAN runtime file in release: {name}')
        if name.startswith(DEV_PREFIX):
            if not dev_transport:
                raise ValueError(f'Experimental Steam P2P file needs the dev manifest: {name}')
        elif name in _read_manifest(root, DEV_MANIFEST):
            raise ValueError(f'Dev manifest may only hold {DEV_PREFIX} files: {name}')
        result.append((name, path))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare', type=Path, help='Other onlinecoop folder to compare (read-only)')
    parser.add_argument('--dev-transport', action='store_true',
                        help='Expect the experimental Steam P2P files as well')
    args = parser.parse_args()
    files = release_files(dev_transport=args.dev_transport)
    if args.compare:
        different = []
        for name, path in files:
            other = args.compare / name
            if not other.is_file() or hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(other.read_bytes()).digest():
                different.append(name)
        if different:
            raise SystemExit('Release copies differ:\n' + '\n'.join(different))
    label = 'release files (dev transport)' if args.dev_transport else 'release files'
    print(f'PASS: {len(files)} {label}' + ('; compared copy matches' if args.compare else ''))


if __name__ == '__main__':
    main()
