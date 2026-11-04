"""Stage a fixed installed runtime wheel recipe without building or publishing."""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import struct
import subprocess
import sys
import tempfile
from typing import Any, TYPE_CHECKING, cast

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'scripts'))
from python_release_cohort import read_cohort  # noqa: E402
from python_wasm_table_geometry import defined_table_limits  # noqa: E402
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_distribution import (LocalComponents, WASMTIME_VERSION, inspect_local_components,
    _LOCAL_COMPONENT_PLATFORM, _inspect_local_components_for_packaging, _read_file)  # noqa: E402
if TYPE_CHECKING:
    from actql_sdk._local_image_recipe import _SelectedImageRecipe


def library_target(path: Path, *, identity: bytes | None = None,
                   bundled: tuple[bytes, ...] = (), rpaths: tuple[bytes, ...] | None = None) -> None:
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
        identities: list[bytes] = []
        observed_rpaths: list[bytes] = []
        observed_bundled: list[bytes] = []
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
                if name in bundled:
                    observed_bundled.append(name)
                elif not name.startswith((b'/usr/lib/', b'/System/Library/Frameworks/')):
                    raise ValueError('Installed DuckDB requires an unbundled non-system library')
            if command in (0xd, 0x8000001c):
                fixed = 24 if command == 0xd else 12
                if length < fixed:
                    raise ValueError('Invalid installed native library identity/search path')
                start = struct.unpack_from('<I', commands, position + 8)[0]
                if not fixed <= start < length:
                    raise ValueError('Invalid installed native library path offset')
                name = commands[position + start:position + length].split(b'\0', 1)[0]
                (identities if command == 0xd else observed_rpaths).append(name)
            position += length
        if position != len(commands) or len(minimum) != 1 or minimum[0] > 11 << 16:
            raise ValueError('Installed DuckDB does not support the selected macOS11 profile')
        if identity is not None and identities != [identity]:
            raise ValueError('Installed native library identity differs from the selected package')
        if sorted(observed_bundled) != sorted(bundled):
            raise ValueError('Installed native library bundled dependency inventory differs')
        if rpaths is not None and sorted(observed_rpaths) != sorted(rpaths):
            raise ValueError('Installed native library search path differs from the selected package')


def prepare_private_bindings(bindings_source: Path, stage: Path) -> dict[str, Any]:
    """Reuse the pinned sdist checker/namespace transformation without import."""
    spec = importlib.util.spec_from_file_location('original_private_bindings',
        Path(__file__).resolve().parents[1] / 'packages/python-local-runtime/native/pre-root/prepare_binding_source.py')
    if spec is None or spec.loader is None:
        raise ValueError('Original private binding source recipe is unavailable')
    binding = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(binding)
    return cast(dict[str, Any], binding.prepare(bindings_source, stage))


def stage_private_runtime(components: LocalComponents, bindings_source: Path,
                          native_libraries: Path, target: Path) -> dict[str, object]:
    """Final wheel caller keeps its original full component admission."""
    return stage_selected_private_runtime(components.image_recipe, bindings_source,
                                         native_libraries, target)


def stage_selected_private_runtime(selected: _SelectedImageRecipe, bindings_source: Path,
                                   native_libraries: Path, target: Path) -> dict[str, object]:
    """Generate pinned Python source and copy exact original DLLs; never import them."""
    selected.validate()
    provider_digest, provider_bytes = selected.owned_provider()
    if native_libraries.is_symlink() or not native_libraries.is_dir():
        raise ValueError('Original private native library directory is unavailable')
    libraries = (
        ('_libwasmtime.dylib', selected.runtime_library_bytes, selected.runtime_library_sha256),
        ('libactql_native_control.dylib', provider_bytes, provider_digest),
    )
    for name, size, digest in libraries:
        _read_file(native_libraries / name, maximum=size, expected=size, digest=digest)
    library_target(native_libraries / '_libwasmtime.dylib',
        identity=b'@rpath/_libwasmtime.dylib',
        bundled=(b'@rpath/libactql_native_control.dylib',), rpaths=(b'@loader_path',))
    library_target(native_libraries / 'libactql_native_control.dylib',
        identity=b'@rpath/libactql_native_control.dylib', rpaths=())
    with tempfile.TemporaryDirectory(prefix='actql-private-bindings-') as directory:
        stage = Path(directory) / 'source'
        report = prepare_private_bindings(bindings_source, stage)
        license_body = (stage / 'WASMTIME-PYTHON-LICENSE').read_bytes()
        # The fixed399f Rust source and pinned38 Python sdist carry the same
        # Apache2/LLVM-exception license bytes. Preserve that original notice.
        if hashlib.sha256(license_body).hexdigest() != '268872b9816f90fd8e85db5a28d33f8150ebb8dd016653fb39ef1f94f2686bc5':
            raise ValueError('Original Wasmtime license differs from the selected sources')
        shutil.copytree(stage / 'actql_local_runtime/_wasmtime', target / '_wasmtime')
        (target / 'WASMTIME-LICENSE').write_bytes(license_body)
        (target / '_wasmtime/binding-source.json').write_text(json.dumps(report, indent=2) + '\n')
    library_directory = target / '_wasmtime/darwin-aarch64'
    library_directory.mkdir()
    for name, size, digest in libraries:
        raw = _read_file(native_libraries / name, maximum=size, expected=size, digest=digest, capture=True)
        (library_directory / name).write_bytes(raw)
        _read_file(library_directory / name, maximum=size, expected=size, digest=digest)
    # Inspect the owned output after copying, not only the mutable input paths.
    library_target(library_directory / '_libwasmtime.dylib',
        identity=b'@rpath/_libwasmtime.dylib',
        bundled=(b'@rpath/libactql_native_control.dylib',), rpaths=(b'@loader_path',))
    library_target(library_directory / 'libactql_native_control.dylib',
        identity=b'@rpath/libactql_native_control.dylib', rpaths=())
    return {'python_source_sha256': report['source_sha256'],
            'python_files': len(report['inputs']), 'libraries': [
                {'file': name, 'bytes': size, 'sha256': digest} for name, size, digest in libraries],
            'native_loaded': False, 'engine_executed': False}


def notice_originals() -> dict[str, Path]:
    return {
        'LICENSE': ROOT / 'LICENSE',
        'DUCKDB-LICENSE': ROOT / 'vendor/duckdb/1.4.3/LICENSE',
        'MOONBIT-CORE-LICENSE': ROOT / 'packages/local-node/MOONBIT-CORE-LICENSE',
        'MOONBIT-CORE-NOTICE': ROOT / 'packages/local-node/MOONBIT-CORE-NOTICE',
    }


def _source_original(root: Path, source: str, relative: str, label: str) -> bytes:
    """Read a fixed maintainer input against its bounded exact Git original."""
    try:
        original = _read_file(root / relative, maximum=65536)
        expected = subprocess.check_output(['git', 'rev-parse', '--verify',
            source + ':' + relative], cwd=root).strip()
        actual = subprocess.check_output(['git', 'hash-object', '--stdin'],
            cwd=root, input=original).strip()
        if actual != expected:
            raise ValueError(f'{label} differs from its committed original')
        return original
    except (OSError, subprocess.CalledProcessError) as failure:
        raise ValueError(f'{label} is unavailable') from failure


def image_recipe_original(root: Path, source: str, *, runtime_allocation: str = 'native-owned') -> bytes:
    """Bounded exact Git-original read; no unbounded git-show capture."""
    names = {'native-owned': 'selected-image-recipe.json',
             'platform': 'selected-platform-image-recipe.json'}
    if runtime_allocation not in names:
        raise ValueError('Unknown selected image runtime allocation')
    return _source_original(root, source,
        'packages/python-local-runtime/' + names[runtime_allocation],
        'Selected source-original image recipe')


def module_image_recipe_original(root: Path, source: str, module: Path, module_sha256: str,
                                 *, runtime_allocation: str = 'native-owned') -> bytes:
    """Bind the selected pool table maximum to this exact original module.

    All other source recipe fields, including the 16 MiB memory ceiling, remain
    unchanged. The compiler, assembler and final copied-artifact verifier use
    this same projection; no caller-supplied capacity or runtime fallback exists.
    """
    from actql_sdk._local_image_recipe import _recipe_from_original
    original = image_recipe_original(root, source, runtime_allocation=runtime_allocation)
    selected = _recipe_from_original(original, source_sha=source,
        package_version=read_cohort(root), module_sha256=module_sha256)
    raw = _read_file(module, maximum=32 * 1024 * 1024, digest=module_sha256, capture=True)
    tables = defined_table_limits(raw)
    body = json.loads(original)
    pool = body['engine_body']['pooling']
    if pool['total_tables'] != len(tables) or pool['max_tables_per_module'] != len(tables):
        raise ValueError('Original Core table count differs from the selected pool')
    maximum = max(limit[1] for limit in tables)
    if pool['table_elements'] == maximum:
        return original
    pool['table_elements'] = maximum
    derived = (json.dumps(body, indent=2, ensure_ascii=True, allow_nan=False) + '\n').encode('ascii')
    checked = _recipe_from_original(derived, source_sha=source,
        package_version=selected.package_version, module_sha256=module_sha256)
    if checked.runtime_allocation != selected.runtime_allocation:
        raise ValueError('Module geometry changed the selected runtime allocation')
    return derived


def verify_artifact(artifact: Path, *, target_platform: str = _LOCAL_COMPONENT_PLATFORM) -> LocalComponents:
    """Reuse the fixed-source, component, target and original-notice checks."""
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT):
        raise ValueError('Use committed clean Python Local recipe source')
    head = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    version = read_cohort(ROOT)
    components = _inspect_local_components_for_packaging(artifact, target_platform=target_platform, package_version=version)
    if components.source_sha != head:
        raise ValueError('Python Local producer source does not match the recipe source')
    with components.module.open('rb') as source:
        if source.read(8) != b'\0asm\x01\0\0\0':
            raise ValueError('Invalid installed Wasm module format')
    recipe_bytes = module_image_recipe_original(ROOT, head, components.module, components.module_sha256,
        runtime_allocation=components.image_recipe.runtime_allocation)
    if _read_file(components.engine_recipe, maximum=65536) != recipe_bytes:
        raise ValueError('Staged image recipe differs from its source original')
    library_target(components.duckdb)
    # Require the official notice bytes, not merely a manifest agreeing with
    # missing or unrelated notices. Component source/hash receipts stay separate.
    for name, original in notice_originals().items():
        if (artifact / name).read_bytes() != original.read_bytes():
            raise ValueError('Python Local notice does not match the repository notice')
    return components


def prepare(artifact: Path, destination: Path, *, bindings_source: Path | None = None,
            native_libraries: Path | None = None,
            target_platform: str = _LOCAL_COMPONENT_PLATFORM) -> dict[str, object]:
    components = verify_artifact(artifact, target_platform=target_platform)
    platform_runtime = components.image_recipe.runtime_allocation == 'platform'
    if (platform_runtime and (bindings_source is not None or native_libraries is not None)
            or not platform_runtime and (bindings_source is None or native_libraries is None)):
        raise ValueError('Runtime preparation inputs do not match the selected allocation')
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
    if platform_runtime:
        shutil.copyfile(runtime / 'WASMTIME-LICENSE', target / 'WASMTIME-LICENSE')
        private_runtime = {'runtime_allocation': 'platform',
            'dependency': 'wasmtime==' + WASMTIME_VERSION,
            'native_loaded': False, 'engine_executed': False}
    else:
        assert bindings_source is not None and native_libraries is not None
        private_runtime = stage_private_runtime(components, bindings_source, native_libraries, target)
    shutil.copyfile(target / 'WASMTIME-LICENSE', destination / 'WASMTIME-LICENSE')
    staged = _inspect_local_components_for_packaging(target, target_platform=target_platform, package_version=components.package_version)
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
        'private_runtime': private_runtime,
        'wheel_built': False, 'runtime_executed': False, 'public_local_accepted': False}
    (destination / 'preparation.json').write_text(json.dumps(receipt, indent=2) + '\n')
    return receipt


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--artifact-directory', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--bindings-source', type=Path)
    parser.add_argument('--native-libraries', type=Path)
    parser.add_argument('--target-platform', choices=[_LOCAL_COMPONENT_PLATFORM], default=_LOCAL_COMPONENT_PLATFORM,
                        help='Original artifact target; does not enable execution on the preparation host')
    args = parser.parse_args()
    print(json.dumps(prepare(args.artifact_directory, args.destination,
        bindings_source=args.bindings_source, native_libraries=args.native_libraries, target_platform=args.target_platform)))
