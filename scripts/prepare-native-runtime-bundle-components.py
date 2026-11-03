"""Prepare the existing private components for one selected bundle test command.

This compiles the same SQLite/Crypto implementations against the executable's
original provider ports. It never loads components or acquires runtime capacity.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess
import time
import urllib.request

ROOT = Path(__file__).resolve().parents[1]


def load(name: str, filename: str):
    spec = importlib.util.spec_from_file_location(name, ROOT / 'scripts' / filename)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


SQLITE = load('bundle_original_sqlite', 'produce-python-sqlite-component.py')
CRYPTO = load('bundle_original_crypto', 'produce-native-crypto-component.py')


def prepare(source: str, target: str, clang: Path, sdk: Path | None,
            openssl: Path | None, destination: Path, seconds: int, *,
            darwin_crypto_profile: str = 'source-macos11',
            openssl_source_archive: Path | None = None) -> dict:
    if target not in ('darwin-arm64', 'linux-x64') or (target == 'darwin-arm64') != (sdk is not None):
        raise ValueError('No selected bundle component producer for this target')
    if type(seconds) is not int or not 0 < seconds <= 1800:
        raise ValueError('Explicit bounded component preparation required')
    def clean():
        if (subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() != source
                or subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT)):
            raise ValueError('Exact clean committed bundle component source required')
    clean()
    deadline = time.monotonic() + seconds
    destination.mkdir(parents=True, exist_ok=False)
    recipe = json.loads((SQLITE.SOURCE / 'source.json').read_bytes())
    archive = destination / 'sqlite-original.zip'
    expected = recipe['upstream']
    # Read exactly the pinned member container; never extract names from it.
    # Its existing stage verifies the complete archive and both source members.
    with urllib.request.urlopen(expected['url'], timeout=min(seconds, 60)) as response:
        raw = response.read(expected['bytes'] + 1)
    if len(raw) != expected['bytes'] or hashlib.sha256(raw).hexdigest() != expected['sha256']:
        raise ValueError('Pinned original SQLite archive mismatch')
    with archive.open('xb') as stream:
        stream.write(raw)
    remaining = max(1, int(deadline - time.monotonic()))
    sqlite = (SQLITE.build_process_import(source, archive, clang, sdk,
        destination / 'sqlite', remaining) if target == 'darwin-arm64' else
        SQLITE.build_linux_process_import(source, archive, clang,
            destination / 'sqlite', remaining, process_target='linux-x64-gnu'))
    if time.monotonic() >= deadline:
        raise ValueError('Bundle component preparation budget exhausted')
    remaining = max(1, int(deadline - time.monotonic()))
    if target == 'darwin-arm64' and darwin_crypto_profile == 'source-macos11':
        crypto = CRYPTO.produce_darwin_source(destination / 'crypto-source', clang, sdk,
            remaining, source_archive=openssl_source_archive, component_output=destination / 'crypto')
    elif target == 'darwin-arm64' and darwin_crypto_profile == 'homebrew26' and openssl is not None:
        crypto = CRYPTO.produce(destination / 'crypto', openssl, clang, sdk)
    elif target == 'linux-x64' and openssl is not None:
        crypto = CRYPTO.produce_linux(destination / 'crypto', openssl, clang, remaining)
    else:
        raise ValueError('No selected original Crypto input for this bundle component recipe')
    sqlite_path = destination / 'sqlite' / (SQLITE.LIBRARY if target == 'darwin-arm64' else SQLITE.LINUX_LIBRARY)
    crypto_path = destination / 'crypto' / ('libactql_crypto_component.dylib'
                  if target == 'darwin-arm64' else CRYPTO.LINUX_LIBRARY)
    result = {'source': source, 'target': target,
        'sqlite': {'path': str(sqlite_path), **sqlite['library']},
        'crypto': {'path': str(crypto_path), **crypto['library']},
        'sqlite_recipe': sqlite['recipe_sha256'], 'crypto_recipe': crypto['recipe'],
        'producer_receipts': {
            'sqlite': {'path': str(destination / 'sqlite/process-producer.json'),
                       **SQLITE.identity(destination / 'sqlite/process-producer.json', 32 * 1024 * 1024)},
            'crypto': {'path': str(destination / 'crypto/producer.json'),
                       **CRYPTO.original(destination / 'crypto/producer.json')},
        },
        'providers': 0, 'loaded': False, 'initialized': False}
    clean()
    (destination / 'bundle-components.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--target', required=True)
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--openssl-prefix', type=Path)
    parser.add_argument('--darwin-crypto-profile', choices=('source-macos11', 'homebrew26'), default='source-macos11')
    parser.add_argument('--openssl-source-archive', type=Path)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--seconds', type=int, required=True)
    args = parser.parse_args()
    result = prepare(args.source, args.target, args.clang, args.sdk,
                     args.openssl_prefix, args.destination, args.seconds,
                     darwin_crypto_profile=args.darwin_crypto_profile,
                     openssl_source_archive=args.openssl_source_archive)
    print(json.dumps(result, sort_keys=True))
