"""Verify pinned source and patch applicability without a native compiler."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile


def verify(crate: Path) -> dict[str, object]:
    candidate = Path(__file__).resolve().parent
    record = json.loads((candidate / 'source-inputs.json').read_text())
    digest = hashlib.sha256(crate.read_bytes()).hexdigest()
    if digest != record['wasmtime_crate_sha256']:
        raise ValueError('Pinned Wasmtime crate digest mismatch')
    sources: dict[str, bytes] = {}
    with tarfile.open(crate) as archive:
        for item in record['source_inputs']:
            name = 'wasmtime-38.0.0/' + item['crate_member']
            member = archive.getmember(name)
            if not member.isfile() or member.size > 2 * 1024 * 1024:
                raise ValueError('Unexpected pinned source member')
            stream = archive.extractfile(member)
            if stream is None:
                raise ValueError('Missing pinned source member')
            source = stream.read(member.size + 1)
            if len(source) != member.size or hashlib.sha256(source).hexdigest() != item['sha256']:
                raise ValueError('Pinned source blob digest mismatch')
            sources[item['path']] = source
    with tempfile.TemporaryDirectory(prefix='actql-owned-capacity-source-') as directory:
        root = Path(directory)
        for path, source in sources.items():
            target = root / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(source)
        result = subprocess.run(
            ['git', 'apply', '--check', '--unidiff-zero', str(candidate / 'wasmtime-mmap-review.patch')],
            cwd=root, capture_output=True, text=True, timeout=10, check=False,
        )
        if result.returncode != 0:
            raise ValueError('Pinned source patch applicability failure: ' + result.stderr)
    return {
        'verified_source_blobs': len(sources),
        'applicable_upstream_patch_files': 1,
        'candidate_sha256': {
            name: hashlib.sha256((candidate / name).read_bytes()).hexdigest()
            for name in ['owned_capacity.c', 'owned_capacity.h', 'wasmtime-mmap-review.patch']
        },
        'native_compile': 0,
        'native_execution': 0,
        'complete_supplier': False,
        'public_e2e': 0,
    }


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--wasmtime-crate', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(verify(args.wasmtime_crate), sort_keys=True))
