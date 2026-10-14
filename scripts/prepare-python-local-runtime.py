"""Stage a fixed installed runtime wheel recipe without building or publishing."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from python_release_cohort import read_cohort  # noqa: E402
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_distribution import LocalComponents, inspect_local_components, _read_file  # noqa: E402


def library_target(path: Path) -> None:
    """Read Mach-O metadata only; never load or execute the library."""
    with path.open('rb') as source:
        header = source.read(32)
        if header[:4] == b'\xca\xfe\xba\xbe':
            count = struct.unpack_from('>I', header, 4)[0]
            if not 1 <= count <= 8:
                raise ValueError('Invalid installed DuckDB architecture table')
            source.seek(8)
            entries = [struct.unpack('>IIIII', source.read(20)) for _ in range(count)]
            selected = [entry for entry in entries if entry[0] == 0x0100000c]
            if len(selected) != 1:
                raise ValueError('Installed DuckDB has no unique arm64 slice')
            offset, size = selected[0][2:4]
            if size < 32 or offset + size > path.stat().st_size:
                raise ValueError('Invalid installed DuckDB slice bounds')
            source.seek(offset)
            header = source.read(32)
        elif header[:4] == b'\xcf\xfa\xed\xfe':
            size = path.stat().st_size
        else:
            raise ValueError('Invalid installed DuckDB binary format')
        magic, cpu, _, _, count, command_bytes, _, _ = struct.unpack('<8I', header)
        if (magic != 0xfeedfacf or cpu != 0x0100000c or not 1 <= count <= 4096
                or not 8 <= command_bytes <= min(size - 32, 1048576)):
            raise ValueError('Invalid installed DuckDB arm64 metadata')
        commands = source.read(command_bytes)
        if len(commands) != command_bytes:
            raise ValueError('Incomplete installed DuckDB metadata')
        position = 0
        minimum = []
        for _ in range(count):
            command, length = struct.unpack_from('<II', commands, position)
            if length < 8 or length % 4 or position + length > len(commands):
                raise ValueError('Invalid installed DuckDB load command')
            if command == 0x32:
                if length < 24 or struct.unpack_from('<I', commands, position + 8)[0] != 1:
                    raise ValueError('Invalid installed DuckDB build target')
                minimum.append(struct.unpack_from('<I', commands, position + 12)[0])
            if command == 0x24:
                if length < 16:
                    raise ValueError('Invalid installed DuckDB minimum OS')
                minimum.append(struct.unpack_from('<I', commands, position + 8)[0])
            if command in (0xc, 0x18 | 0x80000000, 0x1f | 0x80000000, 0x20, 0x23 | 0x80000000):
                if length < 24:
                    raise ValueError('Invalid installed DuckDB dependency command')
                start = struct.unpack_from('<I', commands, position + 8)[0]
                if not 24 <= start < length:
                    raise ValueError('Invalid installed DuckDB dependency path')
                name = commands[position + start:position + length].split(b'\0', 1)[0]
                if not name.startswith((b'/usr/lib/', b'/System/Library/Frameworks/')):
                    raise ValueError('Installed DuckDB requires an unbundled non-system library')
            position += length
        if position != len(commands) or len(minimum) != 1 or minimum[0] > 11 << 16:
            raise ValueError('Installed DuckDB does not support the selected macOS11 profile')


def notice_originals() -> dict[str, Path]:
    return {
        'LICENSE': ROOT / 'LICENSE',
        'DUCKDB-LICENSE': ROOT / 'vendor/duckdb/1.4.3/LICENSE',
        'MOONBIT-CORE-LICENSE': ROOT / 'packages/local-node/MOONBIT-CORE-LICENSE',
        'MOONBIT-CORE-NOTICE': ROOT / 'packages/local-node/MOONBIT-CORE-NOTICE',
    }


def image_recipe_original(root: Path, source: str) -> bytes:
    """Bounded exact Git-original read; no unbounded git-show capture."""
    relative = 'packages/python-local-runtime/selected-image-recipe.json'
    try:
        original = _read_file(root / relative, maximum=65536)
        expected = subprocess.check_output(['git', 'rev-parse', '--verify',
            source + ':' + relative], cwd=root).strip()
        actual = subprocess.check_output(['git', 'hash-object', '--stdin'],
            cwd=root, input=original).strip()
        if actual != expected:
            raise ValueError('Selected image recipe differs from its committed original')
        return original
    except (OSError, subprocess.CalledProcessError) as failure:
        raise ValueError('Selected source-original image recipe is unavailable') from failure


def verify_artifact(artifact: Path) -> LocalComponents:
    """Reuse the fixed-source, component, target and original-notice checks."""
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT):
        raise ValueError('Use committed clean Python Local recipe source')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    version = read_cohort(ROOT)
    components = inspect_local_components(artifact, package_version=version)
    if components.source_sha != head:
        raise ValueError('Python Local producer source does not match the recipe source')
    with components.module.open('rb') as source:
        if source.read(8) != b'\0asm\x01\0\0\0':
            raise ValueError('Invalid installed Wasm module format')
    recipe_bytes = image_recipe_original(ROOT, head)
    if _read_file(components.engine_recipe, maximum=65536) != recipe_bytes:
        raise ValueError('Staged image recipe differs from its source original')
    library_target(components.duckdb)
    # Require the official notice bytes, not merely a manifest agreeing with
    # missing or unrelated notices. Component source/hash receipts stay separate.
    for name, original in notice_originals().items():
        if (artifact / name).read_bytes() != original.read_bytes():
            raise ValueError('Python Local notice does not match the repository notice')
    return components


def prepare(artifact: Path, destination: Path) -> dict[str, object]:
    components = verify_artifact(artifact)
    runtime = ROOT / 'packages/python-local-runtime'
    destination.mkdir()
    for name in ('pyproject.toml', 'setup.py'):
        shutil.copyfile(runtime / name, destination / name)
    target = destination / 'src/actql_local_runtime'
    target.mkdir(parents=True)
    shutil.copyfile(runtime / 'src/actql_local_runtime/__init__.py', target / '__init__.py')
    files = ('artifact.json', 'engine-recipe.json', 'client_host_wasm.cwasm',
             'client_host_wasm.wasm', 'libduckdb.dylib', 'LICENSE',
             'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE')
    for name in files:
        shutil.copyfile(artifact / name, target / name)
        if name.endswith('LICENSE') or name.endswith('NOTICE'):
            shutil.copyfile(artifact / name, destination / name)
    staged = inspect_local_components(target, package_version=components.package_version)
    if ((staged.source_sha, staged.package_version, staged.module_sha256,
         staged.duckdb_sha256, staged.duckdb_version, staged.image_sha256,
         staged.image_bytes, staged.engine_recipe_sha256) !=
            (components.source_sha, components.package_version, components.module_sha256,
             components.duckdb_sha256, components.duckdb_version, components.image_sha256,
             components.image_bytes, components.engine_recipe_sha256)):
        raise ValueError('Python Local components changed during preparation')
    for name in ('LICENSE', 'DUCKDB-LICENSE', 'MOONBIT-CORE-LICENSE', 'MOONBIT-CORE-NOTICE'):
        if (target / name).read_bytes() != (destination / name).read_bytes():
            raise ValueError('Python Local license copies differ')
    members = []
    for path in sorted(destination.rglob('*')):
        if path.is_file():
            digest = hashlib.sha256()
            with path.open('rb') as source:
                for block in iter(lambda: source.read(65536), b''):
                    digest.update(block)
            members.append({'path': str(path.relative_to(destination)), 'bytes': path.stat().st_size,
                            'sha256': digest.hexdigest()})
    receipt: dict[str, object] = {'source_sha': components.source_sha, 'package_version': components.package_version,
        'artifact_directory': str(artifact), 'stage': str(destination), 'files': members,
        'wheel_built': False, 'runtime_executed': False, 'public_local_accepted': False}
    (destination / 'preparation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-directory', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(prepare(args.artifact_directory, args.destination)))
