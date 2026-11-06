"""Copy and verify the derived read allocator closure; never build or load it."""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import os
from pathlib import Path
import stat
import subprocess
import tempfile


HERE = Path(__file__).resolve().parent


def _identity(value: os.stat_result) -> tuple[int, int, int, int, int]:
    return (value.st_dev, value.st_ino, value.st_size, value.st_mtime_ns, value.st_ctime_ns)


def _relative(value: str) -> Path:
    path = Path(value)
    if path.is_absolute() or not path.parts or any(p in {'.', '..'} for p in path.parts):
        raise ValueError('Invalid source closure path')
    return path


def _read(root: Path, name: str, expected: dict[str, object]) -> bytes:
    path = root
    for part in _relative(name).parts:
        path = path / part
        if path.is_symlink():
            raise ValueError('Symlink source closure input')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        size = expected['bytes']
        if (type(size) is not int or not 0 < size <= 2 * 1024 * 1024
                or not stat.S_ISREG(before.st_mode) or before.st_size != size):
            raise ValueError('Source closure size mismatch')
        data = bytearray()
        while len(data) <= size:
            chunk = os.read(fd, min(65536, size + 1 - len(data)))
            if not chunk:
                break
            data.extend(chunk)
        after = os.fstat(fd)
        if (_identity(before) != _identity(after) or len(data) != size
                or hashlib.sha256(data).hexdigest() != expected['sha256']):
            raise ValueError('Source closure digest mismatch')
        return bytes(data)
    finally:
        os.close(fd)


def _select_target(manifest: dict[str, object], target: str | None) -> dict[str, object]:
    """Select pinned bytes only; target selection grants no execution authority."""
    selected = copy.deepcopy(manifest)
    if target is None or target == manifest['target']:
        return selected
    if target not in ('aarch64-unknown-linux-gnu', 'x86_64-unknown-linux-gnu'):
        raise ValueError('Unknown source closure target')
    variant = manifest.get('source_targets', {}).get(target)
    extra = ['ACTQL_NATIVE_LINUX_X64_BUNDLE_ENTRY'] if target.startswith('x86_64-') else []
    if (type(variant) is not dict
            or set(variant) != {'deployment_target', 'required_defines', 'binary_inputs', 'required_source_parameters'}
            or variant['required_source_parameters'] != ['ACTQL_NATIVE_LINUX_STOCK_FILE_SLOTS']
            or variant['deployment_target'] is not None
            or variant['required_defines'] != [*manifest['required_defines'],
                                               '_GNU_SOURCE',
                                               'ACTQL_NATIVE_OWNED_LINUX_PROCESS_DOMAIN', *extra]
            or set(variant['binary_inputs']) != {'lib/libmoonbitrun.o', 'lib/libbacktrace.a'}):
        raise ValueError('Invalid selected source target recipe')
    replaced = set()
    for item in selected['inputs']:
        if item['root'] == 'moonbit' and item['path'] in variant['binary_inputs']:
            expected = variant['binary_inputs'][item['path']]
            if set(expected) != {'bytes', 'sha256'}:
                raise ValueError('Invalid selected binary identity')
            item.update(expected)
            selected['outputs'][item['output']] = expected
            replaced.add(item['path'])
    if replaced != set(variant['binary_inputs']):
        raise ValueError('Incomplete selected binary inputs')
    selected.update(target=target, deployment_target=None,
                    required_defines=variant['required_defines'],
                    required_source_parameters=variant['required_source_parameters'])
    return selected


def prepare(moonbit: Path, destination: Path, *, provider: Path = HERE,
            target: str | None = None) -> dict[str, object]:
    """Publish only a fully verified copy. No installed source is overwritten."""
    if destination.exists() or destination.is_symlink():
        raise ValueError('Source closure destination already exists')
    selected = (provider.resolve(), moonbit.resolve())
    if any(destination.resolve().is_relative_to(root) for root in selected):
        raise ValueError('Source closure cannot overwrite selected inputs')
    raw = (provider / 'scoped-read-source.json').read_bytes()
    manifest = json.loads(raw)
    if (manifest['status'] != 'review-source-only' or manifest['normal_profile'] is not None
            or manifest['installed_supplier'] is not False):
        raise ValueError('Source closure is not a review-only recipe')
    manifest = _select_target(manifest, target)
    patch = _read(provider, manifest['patch']['path'], manifest['patch'])
    originals: dict[str, bytes] = {}
    for item in manifest['inputs']:
        if item['root'] not in {'provider', 'moonbit'}:
            raise ValueError('Unknown source closure root')
        output = str(_relative(item['output']))
        if len(Path(output).parts) != 1 or output in originals:
            raise ValueError('Duplicate or nested source closure output')
        originals[output] = _read(provider if item['root'] == 'provider' else moonbit,
                                  item['path'], item)
    # Patch only disposable copies. Its independent output digests are checked
    # before publishing; a syntactically applicable patch alone is insufficient.
    with tempfile.TemporaryDirectory(prefix='actql-scoped-read-') as temporary:
        stage = Path(temporary)
        for name, data in originals.items():
            (stage / name).write_bytes(data)
        result = subprocess.run(['git', 'apply', '--no-index', '-'], input=patch,
                                cwd=stage, capture_output=True, timeout=10)
        if result.returncode:
            raise ValueError('Source closure patch does not apply: ' + result.stderr.decode())
        if {p.name for p in stage.iterdir()} != set(manifest['outputs']):
            raise ValueError('Unexpected derived source closure member')
        outputs = {name: _read(stage, name, expected)
                   for name, expected in manifest['outputs'].items()}
    record = {
        'status': 'review-source-only', 'target': manifest['target'],
        'deployment_target': manifest['deployment_target'],
        'recipe_sha256': hashlib.sha256(raw).hexdigest(),
        'patch_sha256': manifest['patch']['sha256'],
        'required_defines': manifest['required_defines'], 'outputs': manifest['outputs'],
        'normal_profile': None, 'installed_supplier': False,
        'compiled': 0, 'loaded': 0, 'public_e2e': 0,
    }
    if 'required_source_parameters' in manifest:
        record['required_source_parameters'] = manifest['required_source_parameters']
    destination.mkdir(parents=True, exist_ok=False)
    for name, data in outputs.items():
        with (destination / name).open('xb') as stream:
            stream.write(data)
    for name, expected in manifest['outputs'].items():
        _read(destination, name, expected)
    # Completion metadata is last. A partial I/O failure is not a usable stage.
    with (destination / 'scoped-read-stage.json').open('x') as stream:
        stream.write(json.dumps(record, indent=2) + '\n')
    return record


def main(argv: list[str] | None = None) -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--moonbit', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--target', choices=['aarch64-apple-darwin',
                                              'aarch64-unknown-linux-gnu',
                                              'x86_64-unknown-linux-gnu'])
    args = parser.parse_args(argv)
    print(json.dumps(prepare(args.moonbit, args.destination, target=args.target)))


if __name__ == '__main__':
    main()
