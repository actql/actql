"""Check the artifact patch and copied source bindings; never build them."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tarfile
import tempfile
import tomllib


PROVIDER_SOURCES = (
    'owned_capacity.c', 'owned_capacity.h', 'owned_image.c', 'owned_region.h',
    'owned_region.inc', 'owned_domain_borrow.h', 'owned_domain_borrow.inc',
    'owned_domain_growth.inc',
    'owned_thread.h', 'owned_thread.inc', 'owned_rust_heap.inc',
)
RUST_COPIES = {
    'owned_heap.rs': 'crates/c-api/artifact/src/actql_owned_heap.rs',
    'owned_abi.rs': 'crates/c-api/artifact/src/actql_owned_abi.rs',
    'owned_build.rs': 'crates/c-api/artifact/actql_owned_build.rs',
    'owned_handler_thread.rs': 'crates/wasmtime/src/runtime/vm/sys/unix/actql_owned_handler_thread.rs',
}


def verify_provider_recipe(record: dict[str, object], candidate: Path) -> None:
    """Bind one external provider; copied C sources must not create another."""
    provider = record['provider_source_inputs']
    if (type(provider) is not list or any(type(item) is not dict for item in provider)
            or [item.get('source') for item in provider] != list(PROVIDER_SOURCES)
            or any(set(item) != {'source', 'sha256'} for item in provider)):
        raise ValueError('Invalid same-provider source closure')
    copies = record['copy_before_patch']
    if (type(copies) is not list or any(type(item) is not dict for item in copies)
            or len(copies) != len(RUST_COPIES)
            or any(set(item) != {'source', 'target', 'sha256'} for item in copies)
            or {item['source']: item['target'] for item in copies} != RUST_COPIES):
        raise ValueError('Only original Rust wrapper/forwarder/build sources may be copied')
    for item in provider + copies:
        if hashlib.sha256((candidate / item['source']).read_bytes()).hexdigest() != item['sha256']:
            raise ValueError('Original provider/copy source digest mismatch')
    if record['native_provider_link'] != {
        'kind': 'dynamic-original-provider', 'file': 'libactql_native_control.dylib',
        'build_directory_env': 'ACTQL_OWNED_PROVIDER_DIR',
        'runtime_resolution': '@loader_path', 'provider_artifact': None,
        'build_executed': False, 'installed_acceptance': False,
    }:
        raise ValueError('Invalid unadopted original-provider link')


def verify_linked_workspace(root: Path, original: dict[str, bytes]) -> None:
    """Check the applied source recipe, not compiled symbol/loader behavior."""
    if (root / 'crates/c-api/build.rs').read_bytes() != original['crates/c-api/build.rs']:
        raise ValueError('C API build must not compile a second provider')
    for name, relay in [
        ('crates/c-api/Cargo.toml', ['wasmtime/actql-owned-capacity']),
        ('crates/c-api/artifact/Cargo.toml', ['wasmtime-c-api/actql-owned-capacity']),
        ('crates/wasmtime/Cargo.toml', []),
    ]:
        before = tomllib.loads(original[name].decode())
        after = tomllib.loads((root / name).read_text())
        if after['features'].pop('actql-owned-capacity', None) != relay:
            raise ValueError('Original owned-capacity feature relay changed')
        if name == 'crates/c-api/artifact/Cargo.toml':
            if after['package'].pop('build', None) != 'actql_owned_build.rs':
                raise ValueError('Missing same-provider artifact build entry')
        if after != before:
            raise ValueError('Unrelated original Cargo inputs changed')


def verify_thread_patch(root: Path, originals: dict[str, bytes], candidate: Path) -> None:
    """Exact source preparation, never handler startup or retirement evidence."""
    workspace = json.loads((candidate / 'workspace-build-inputs.json').read_bytes())
    raw = (candidate / 'thread-source.json').read_bytes()
    if workspace['thread_preparation'] != {
        'source': 'thread-source.json', 'sha256': hashlib.sha256(raw).hexdigest(),
    }:
        raise ValueError('Original thread recipe digest mismatch')
    record = json.loads(raw)
    if (record['status'] != 'source-preparation-only' or record['normal_profile'] is not None
            or record['Engine_executed'] is not False or record['runtime_build_executed'] is not False
            or record['upstream_git_commit'] != workspace['upstream_git_commit']
            or record['target'] != workspace['target'] or record['feature'] != 'actql-owned-capacity'):
        raise ValueError('Invalid source-only thread preparation')
    expected = {
        'crates/wasmtime/src/runtime/vm/sys/unix/machports.rs',
        'crates/wasmtime/src/runtime/vm/sys/unix/traphandlers.rs',
        'crates/wasmtime/src/runtime/vm/traphandlers/signals.rs',
    }
    if (len(record['inputs']) != len(expected)
            or {item['path'] for item in record['inputs']} != expected
            or set(record['outputs']) != expected):
        raise ValueError('Original thread source closure mismatch')
    for item in record['inputs']:
        source = originals[item['path']]
        if len(source) != item['bytes'] or hashlib.sha256(source).hexdigest() != item['sha256']:
            raise ValueError('Original thread source digest mismatch')
    copied = record['copy']
    data = (candidate / 'owned_handler_thread.rs').read_bytes()
    if copied != {'source': 'owned_handler_thread.rs',
                  'target': RUST_COPIES['owned_handler_thread.rs'],
                  'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}:
        raise ValueError('Original thread wrapper copy mismatch')
    if (root / copied['target']).read_bytes() != data:
        raise ValueError('Changed original thread wrapper')
    patch = (candidate / 'wasmtime-owned-thread-review.patch').read_bytes()
    if record['patch'] != {'path': 'wasmtime-owned-thread-review.patch',
                           'bytes': len(patch), 'sha256': hashlib.sha256(patch).hexdigest()}:
        raise ValueError('Original thread patch digest mismatch')
    members = {str(path.relative_to(root)) for path in root.rglob('*') if path.is_file()}
    result = subprocess.run(['git', 'apply', '--no-index', '-'], input=patch,
                            cwd=root, capture_output=True, timeout=10)
    if result.returncode:
        raise ValueError('Original thread patch does not apply: ' + result.stderr.decode())
    if {str(path.relative_to(root)) for path in root.rglob('*') if path.is_file()} != members:
        raise ValueError('Unexpected original thread patch member')
    for name, expected in record['outputs'].items():
        data = (root / name).read_bytes()
        if len(data) != expected['bytes'] or hashlib.sha256(data).hexdigest() != expected['sha256']:
            raise ValueError('Derived original thread digest mismatch')


def verify(workspace: Path, wasmtime_crate: Path, c_api_crate: Path) -> dict[str, object]:
    candidate = Path(__file__).resolve().parent
    record = json.loads((candidate / 'workspace-build-inputs.json').read_text())
    verify_provider_recipe(record, candidate)
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
        for item in record['source_workspace_inputs']:
            path = item['path']
            if path.startswith('crates/wasmtime/') and path not in sources:
                member = archive.extractfile('wasmtime-38.0.0/' + path.removeprefix('crates/wasmtime/'))
                if member is None:
                    raise ValueError('Missing original Wasmtime thread input')
                sources[path] = member.read()
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
        subprocess.run(['git', 'apply', '--unidiff-zero',
                        str(candidate / 'wasmtime-owned-artifact-review.patch')],
                       cwd=root, capture_output=True, text=True, timeout=10, check=True)
        verify_linked_workspace(root, sources)
        verify_thread_patch(root, sources, candidate)
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
        'verified_provider_sources': len(PROVIDER_SOURCES),
        'applicable_artifact_patch_files': 4,
        'applicable_mmap_patch_files': 1,
        'applicable_thread_patch_files': 3,
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
