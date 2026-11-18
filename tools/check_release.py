"""Validate the release allowlist; optionally compare it with another mod copy.

The public Workshop package stops at ``tools/package-files.json``. The
experimental Steam P2P transport is not part of it: those binaries live only in
the author's local test build, so any ``steam-p2p/`` path in the manifest is
rejected here rather than shipped by accident.
"""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import json

ROOT = Path(__file__).resolve().parent.parent


def _read_manifest(root, name):
    names = json.loads((root / name).read_text(encoding='utf-8'))
    if not isinstance(names, list) or not names:
        raise ValueError(f'{name} must be a nonempty list')
    return names


def release_files(root=ROOT):
    names = _read_manifest(root, 'tools/package-files.json')
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
        if rel.parts[0] == 'steam-p2p' or name.startswith('steam-p2p/'):
            raise ValueError(f'Steam P2P transport must not ship: {name}')
        result.append((name, path))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compare', type=Path, help='Other onlinecoop folder to compare (read-only)')
    args = parser.parse_args()
    files = release_files()
    if args.compare:
        different = []
        for name, path in files:
            other = args.compare / name
            if not other.is_file() or hashlib.sha256(path.read_bytes()).digest() != hashlib.sha256(other.read_bytes()).digest():
                different.append(name)
        if different:
            raise SystemExit('Release copies differ:\n' + '\n'.join(different))
    print(f'PASS: {len(files)} release files' + ('; compared copy matches' if args.compare else ''))


if __name__ == '__main__':
    main()
