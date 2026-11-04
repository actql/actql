"""Stage a verified SQLite review candidate. Never compile, load or configure it."""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import stat
import zipfile

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]


def _read(path: Path, expected: dict, maximum: int = 12 * 1024 * 1024) -> bytes:
    for ancestor in (path, *path.parents):
        if ancestor.is_symlink():
            raise ValueError('Symlink SQLite source input')
    fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK)
    try:
        before = os.fstat(fd)
        if (not stat.S_ISREG(before.st_mode) or before.st_size != expected['bytes']
                or not 0 < before.st_size <= maximum):
            raise ValueError('SQLite source size mismatch')
        raw = bytearray()
        while len(raw) <= before.st_size:
            part = os.read(fd, min(65536, before.st_size + 1 - len(raw)))
            if not part:
                break
            raw.extend(part)
        after = os.fstat(fd)
        identity = lambda s: (s.st_dev, s.st_ino, s.st_size, s.st_mtime_ns, s.st_ctime_ns)
        if (identity(before) != identity(after) or len(raw) != before.st_size
                or hashlib.sha256(raw).hexdigest() != expected['sha256']):
            raise ValueError('SQLite source digest mismatch')
        return bytes(raw)
    finally:
        os.close(fd)


def process_recipe(original: bytes, target: str | None) -> tuple[dict, bytes]:
    recipe = json.loads(original)
    if target is None:
        return recipe, original
    if (type(target) is not str or target not in ('linux-arm64-gnu', 'linux-x64-gnu')
            or recipe['target'] != 'aarch64-apple-darwin'
            or recipe['deployment_target'] != '11.0'):
        raise ValueError('Unsupported SQLite process target selection')
    # A genuinely derived preparation identity. Never relabel the Darwin
    # recipe, nor change its source, provider inputs, heap or cleanup rules.
    architecture, image = (('aarch64', 'AArch64') if target == 'linux-arm64-gnu'
                           else ('x86_64', 'x86-64'))
    selected = dict(recipe, target=architecture + '-unknown-linux-gnu', deployment_target=None,
                    original_recipe_sha256=hashlib.sha256(original).hexdigest(),
                    process_format='ELF64-little-' + image + '-shared',
                    provider_binding='same original process namespace',
                    automatic_initializers=False, component_tls=False)
    return selected, (json.dumps(selected, sort_keys=True, separators=(',', ':')) + '\n').encode()


def prepare(archive: Path, destination: Path, *, source: Path = HERE,
            process_target: str | None = None) -> dict:
    # The recipe is a trusted repository input, not installer-supplied DATA or an
    # authority document. The stage does not acquire any allocation/Host grant.
    recipe_raw = (source / 'source.json').read_bytes()
    recipe, selected_raw = process_recipe(recipe_raw, process_target)
    if (recipe['status'] != 'review-candidate-not-adopted'
            or recipe['normal_profile'] is not None or recipe['installed_supplier'] is not False):
        raise ValueError('SQLite candidate is not a review-only recipe')
    if recipe.get('optimization') != '-O2':
        raise ValueError('SQLite component requires the pinned release optimization')
    if destination.exists() or destination.is_symlink():
        raise ValueError('SQLite stage destination exists')
    if destination.resolve().is_relative_to(source.resolve()):
        raise ValueError('SQLite stage cannot overwrite its source')
    upstream = recipe['upstream']
    for name, expected in recipe['provider_inputs'].items():
        _read(ROOT / name, expected)
    raw = _read(archive, upstream, 5 * 1024 * 1024)
    outputs = {}
    with zipfile.ZipFile(io.BytesIO(raw)) as selected:
        if len(selected.namelist()) != len(set(selected.namelist())):
            raise ValueError('Duplicate SQLite archive member')
        for name, expected in upstream['members'].items():
            item = selected.getinfo(upstream['prefix'] + name)
            if item.file_size != expected['bytes']:
                raise ValueError('SQLite archive member size mismatch')
            data = selected.read(item)
            if (hashlib.sha256(data).hexdigest() != expected['sha256']
                    or hashlib.sha3_256(data).hexdigest() != expected['sha3_256']):
                raise ValueError('SQLite archive member digest mismatch')
            outputs[name] = data
    # Fixed literal output names. No path from a zip entry is extracted.
    for name in ('component.c', 'component.h', 'api.h', 'NOTICE'):
        outputs[name] = _read(source / name, recipe['local'][name])
    record = {'status': recipe['status'], 'recipe_sha256': hashlib.sha256(selected_raw).hexdigest(),
              'upstream': upstream, 'target': recipe['target'],
              'deployment_target': recipe['deployment_target'], 'defines': recipe['defines'],
              'optimization': recipe['optimization'],
              'provider_inputs': recipe['provider_inputs'], 'memory': recipe['memory'],
              'outputs': {name: {'bytes': len(data), 'sha256': hashlib.sha256(data).hexdigest()}
                          for name, data in outputs.items()},
              'compiled': 0, 'loaded': 0, 'installed_supplier': False, 'normal_profile': None}
    if process_target is not None:
        record['selected_process_recipe'] = recipe
        record['original_recipe_sha256'] = hashlib.sha256(recipe_raw).hexdigest()
    destination.mkdir(parents=True, exist_ok=False)
    for name, data in outputs.items():
        with (destination / name).open('xb') as output:
            output.write(data)
        _read(destination / name, record['outputs'][name])
    with (destination / 'sqlite-stage.json').open('x') as output:
        output.write(json.dumps(record, indent=2) + '\n')
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--archive', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.archive, args.destination)))
