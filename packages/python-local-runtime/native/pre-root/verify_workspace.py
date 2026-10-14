"""Check the artifact patch and copied source bindings; never build them."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile


def verify(workspace: Path, wasmtime_crate: Path, c_api_crate: Path) -> dict[str, object]:
    candidate = Path(__file__).resolve().parent
    record = json.loads((candidate / 'workspace-build-inputs.json').read_text())
    for path, name in [(wasmtime_crate, 'actql-e-wasmtime38.crate'),
                       (c_api_crate, 'actql-e-wasmtime-c-api-38.crate')]:
        if hashlib.sha256(path.read_bytes()).hexdigest() != record['source_archives'][name]:
            raise ValueError('Pinned source archive digest mismatch')
    sources: dict[str, bytes] = {}
    with tarfile.open(wasmtime_crate) as archive:
        member = archive.extractfile('wasmtime-38.0.0/Cargo.toml.orig')
        if member is None:
            raise ValueError('Missing original Wasmtime Cargo input')
        sources['crates/wasmtime/Cargo.toml'] = member.read()
        mmap = archive.extractfile('wasmtime-38.0.0/src/runtime/vm/sys/unix/mmap.rs')
        if mmap is None:
            raise ValueError('Missing original mmap source')
        sources['crates/wasmtime/src/runtime/vm/sys/unix/mmap.rs'] = mmap.read()
    with tarfile.open(c_api_crate) as archive:
        for name, path in [('build.rs', 'crates/c-api/build.rs'),
                           ('Cargo.toml.orig', 'crates/c-api/Cargo.toml')]:
            member = archive.extractfile('wasmtime-c-api-impl-38.0.0/' + name)
            if member is None:
                raise ValueError('Missing original C API input')
            sources[path] = member.read()
    for item in record['source_workspace_inputs']:
        path = item['path']
        if path not in sources:
            sources[path] = (workspace / path).read_bytes()
        if hashlib.sha256(sources[path]).hexdigest() != item['sha256']:
            raise ValueError('Pinned workspace source digest mismatch: ' + path)
    with tempfile.TemporaryDirectory(prefix='actql-owned-workspace-source-') as directory:
        root = Path(directory)
        for path, source in sources.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source)
        for item in record['copy_before_patch']:
            source = (candidate / item['source']).read_bytes()
            if hashlib.sha256(source).hexdigest() != item['sha256']:
                raise ValueError('Native copied source digest mismatch')
            target = root / item['target']
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source)
        result = subprocess.run(
            ['git', 'apply', '--check', '--unidiff-zero',
             str(candidate / 'wasmtime-owned-artifact-review.patch')],
            cwd=root, capture_output=True, text=True, timeout=10, check=False,
        )
        if result.returncode != 0:
            raise ValueError('Artifact source patch applicability failure: ' + result.stderr)
        mmap_result = subprocess.run(
            ['git', 'apply', '--check', '--unidiff-zero',
             str(candidate / 'wasmtime-mmap-review.patch')],
            cwd=root, capture_output=True, text=True, timeout=10, check=False,
        )
        if mmap_result.returncode != 0:
            raise ValueError('Mmap source patch applicability failure: ' + mmap_result.stderr)
    return {
        'verified_upstream_inputs': len(sources),
        'verified_source_copies': len(record['copy_before_patch']),
        'applicable_artifact_patch_files': 5,
        'applicable_mmap_patch_files': 1,
        'compiler_executed': 0,
        'engine_executed': 0,
        'complete_supplier': False,
        'public_e2e': 0,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--workspace', type=Path, required=True)
    parser.add_argument('--wasmtime-crate', type=Path, required=True)
    parser.add_argument('--c-api-crate', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.workspace, args.wasmtime_crate, args.c_api_crate), sort_keys=True))
