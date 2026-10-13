"""Verify the exact private Native bootstrap source closure without compiling.

This is a build-input check, not installed supplier adoption or physical funding.
The selected compiler, SDK, MoonBit runtime and final artifact remain separately
required build inputs. Runtime packaging must not accept this source manifest as
an installed component or infer a completed numerical Host profile from it.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
import subprocess


INPUTS = (
    'src/platform_native/host_bootstrap/moon.pkg',
    'src/platform_native/host_bootstrap/bootstrap_native.mbt',
    'src/platform_native/host_bootstrap/bootstrap_stub.c',
    'src/platform_native/host_bootstrap/bootstrap_wbtest.mbt',
    'packages/python-local-runtime/native/pre-root/owned_capacity.c',
    'packages/python-local-runtime/native/pre-root/owned_capacity.h',
)
MANIFEST = 'packages/python-local-runtime/native/pre-root/host-bootstrap-source.json'


def _closed_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    result: dict[str, object] = {}
    for key, value in pairs:
        if key in result:
            raise ValueError('Duplicate bootstrap source field')
        result[key] = value
    return result


def verify_source(root: Path, source: str) -> dict[str, object]:
    """Require committed exact inputs, same selected target and no symlink paths."""
    if re.fullmatch('[0-9a-f]{40}', source) is None:
        raise ValueError('Full source SHA is required')
    raw = subprocess.check_output(['git', 'show', f'{source}:{MANIFEST}'], cwd=root)
    manifest = json.loads(raw, object_pairs_hook=_closed_object)
    if (type(manifest) is not dict or set(manifest) != {'status', 'target', 'inputs'}
            or manifest['status'] != 'source-preparation-only'
            or manifest['target'] != 'aarch64-apple-darwin'
            or type(manifest['inputs']) is not list
            or len(manifest['inputs']) != len(INPUTS)):
        raise ValueError('Invalid private bootstrap source manifest')
    manifest_path = root / MANIFEST
    if manifest_path.is_symlink() or manifest_path.read_bytes() != raw:
        raise ValueError('Private bootstrap manifest mismatch')
    for path, entry in zip(INPUTS, manifest['inputs'], strict=True):
        if (type(entry) is not dict or set(entry) != {'path', 'bytes', 'sha256'}
                or entry['path'] != path or type(entry['bytes']) is not int
                or entry['bytes'] <= 0
                or type(entry['sha256']) is not str
                or re.fullmatch('[0-9a-f]{64}', entry['sha256']) is None):
            raise ValueError('Invalid private bootstrap input')
        current = root
        for part in Path(path).parts:
            current = current / part
            if current.is_symlink():
                raise ValueError('Symlink bootstrap input is unavailable')
        data = current.read_bytes()
        blob = subprocess.check_output(['git', 'show', f'{source}:{path}'], cwd=root)
        if (data != blob or len(data) != entry['bytes']
                or hashlib.sha256(data).hexdigest() != entry['sha256']):
            raise ValueError('Private bootstrap source mismatch')
    return {'source': source, 'target': manifest['target'],
            'verified_inputs': len(INPUTS),
            'manifest_sha256': hashlib.sha256(raw).hexdigest(),
            'native_execution': 0, 'installed_capability': False}


if __name__ == '__main__':
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, required=True)
    parser.add_argument('--source', required=True)
    arguments = parser.parse_args()
    print(json.dumps(verify_source(arguments.root, arguments.source), sort_keys=True))
