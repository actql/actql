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
            openssl: Path, destination: Path, seconds: int) -> dict:
    if target != 'darwin-arm64' or sdk is None:
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
    sqlite = SQLITE.build_process_import(source, archive, clang, sdk,
        destination / 'sqlite', max(1, int(deadline - time.monotonic())))
    if time.monotonic() >= deadline:
        raise ValueError('Bundle component preparation budget exhausted')
    crypto = CRYPTO.produce(destination / 'crypto', openssl, clang, sdk)
    sqlite_path = destination / 'sqlite' / SQLITE.LIBRARY
    crypto_path = destination / 'crypto/libactql_crypto_component.dylib'
    result = {'source': source, 'target': target,
        'sqlite': {'path': str(sqlite_path), **sqlite['library']},
        'crypto': {'path': str(crypto_path), **crypto['library']},
        'sqlite_recipe': sqlite['recipe_sha256'], 'crypto_recipe': crypto['recipe'],
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
    parser.add_argument('--openssl-prefix', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--seconds', type=int, required=True)
    args = parser.parse_args()
    result = prepare(args.source, args.target, args.clang, args.sdk,
                     args.openssl_prefix, args.destination, args.seconds)
    print(json.dumps(result, sort_keys=True))
