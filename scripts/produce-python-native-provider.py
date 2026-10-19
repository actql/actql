"""Build the selected private Native provider; never initialize it or create a VM.

Maintainer-only inputs. Invoke through the existing local-check guard; these
paths are not installed user configuration or allocation authority.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shlex
import subprocess
import sys
import time


ROOT = Path(__file__).resolve().parents[1]
ENTRY = 'src/platform_native/installed_arena_entry'
LIBRARY = 'libactql_native_control.dylib'
PACKAGE_INPUT = ROOT / 'scripts/python-native-provider-packages.json'
# Exact ordinary entry dependency closure, including effect_program_binding
# and the original scoped executor-slot process/descriptor Owner.
# This is compiler recipe selection, never runtime compatibility or authority.
_packages = json.loads(PACKAGE_INPUT.read_bytes())
if (type(_packages) is not list or len(_packages) != 163
        or any(type(p) is not str or not p.startswith('actql/actql/') for p in _packages)
        or len(set(_packages)) != len(_packages)):
    raise ValueError('Selected Native package inventory is unavailable')
PACKAGES = frozenset(_packages)
FOREIGN_SOURCES = (
    ('platform_native/host_bootstrap/bootstrap_stub.c', 'bootstrap'),
    ('platform_native/executor_slot/executor_slot_stub.c', 'executor-slot'),
    ('platform_native/filesystem/filesystem_stub.c', 'filesystem'),
    ('platform_native/http_client/http_client_stub.c', 'http'),
    ('platform_native/signature/signature_stub.c', 'signature'),
    ('platform_native/sqlite/sqlite_stub.c', 'sqlite'),
    ('platform_native/client_host/local_journal_shim.c', 'local-journal'),
    ('platform_native/publication_store/store_format_stub.c', 'publication-store'),
    ('platform_native/remote_journal/inspection_stub.c', 'journal'),
    ('connectors/duckdb/adapters/native/duckdb_stub.c', 'duckdb'),
    ('platform_native/remote_transfer_client/retry_wait_stub.c', 'transfer'),
)


def original(path: Path) -> dict[str, object]:
    if path.is_symlink() or not path.is_file():
        raise ValueError('Original Native provider input is unavailable: ' + str(path))
    raw = path.read_bytes()
    return {'path': str(path), 'bytes': len(raw), 'sha256': hashlib.sha256(raw).hexdigest()}


def original_dependency(path: Path, sdk: Path) -> dict[str, object]:
    # SDK aliases are compiler inputs, not source/provider discovery. Preserve
    # the requested spelling and allow resolution only within this exact SDK.
    if path.is_relative_to(sdk):
        resolved = path.resolve(strict=True)
        if not resolved.is_relative_to(sdk.resolve(strict=True)):
            raise ValueError('Selected Native SDK dependency escapes original SDK')
        return {'requested_path': str(path), **original(resolved)}
    return original(path)


def emission_commands(output: str, moon_home: Path) -> list[list[str]]:
    commands = []
    for line in output.splitlines():
        parts = shlex.split(line)
        if not parts or parts[0] != 'moonc':
            continue
        if len(parts) < 2 or parts[1] not in ('build-package', 'link-core'):
            raise ValueError('Unexpected selected Native compiler operation')
        # The pinned Moon dry-run quotes its one known installation placeholder.
        parts = [part.replace('$MOON_HOME', str(moon_home)) for part in parts]
        if any('$' in part for part in parts):
            raise ValueError('Unresolved selected Native toolchain placeholder')
        if '-target' not in parts or parts[parts.index('-target') + 1] != 'native':
            raise ValueError('Foreign selected Native emission target')
        # Transitive trait implementations require the original package
        # registry. The broader Runtime closure must not drop this argument.
        if parts[1] == 'build-package' and '-all-pkgs' not in parts:
            raise ValueError('Selected Native package registry is missing')
        parts[0] = str(moon_home / 'bin/moonc')
        commands.append(parts)
    if (sum(c[1] == 'build-package' for c in commands) != 163
            or sum(c[1] == 'link-core' for c in commands) != 1):
        raise ValueError('Selected Native emission inventory changed')
    if {c[c.index('-pkg') + 1] for c in commands if c[1] == 'build-package'} != PACKAGES:
        raise ValueError('Selected Native package closure changed')
    return commands


def require_emission_registry(commands: list[list[str]], registry: Path) -> None:
    """Require the same selected file under ordinary absolute/relative spelling.

    Moon emits repository-relative paths for an output inside its working root.
    Resolve both spellings against that exact root; never omit the registry or
    replace its package content with a fallback.
    """
    expected = registry.resolve()
    if any((ROOT / command[command.index('-all-pkgs') + 1]).resolve() != expected
           for command in commands if '-all-pkgs' in command):
        raise ValueError('Selected Native compiler registry binding changed')


def relocated_registry(raw: bytes, check_root: Path, build_root: Path,
                       moon_home: Path) -> bytes:
    """Preserve ordinary Moon metadata with only its artifact target relocated."""
    body = json.loads(raw)
    if type(body) is not dict or set(body) != {'packages'} or type(body['packages']) is not list:
        raise ValueError('Selected Native package registry changed')
    seen = set()
    for entry in body['packages']:
        if type(entry) is not dict or set(entry) != {'root', 'rel', 'artifact'}:
            raise ValueError('Selected Native package registry entry changed')
        root, rel, artifact = entry['root'], entry['rel'], entry['artifact']
        if (type(root) is not str or type(rel) is not str or type(artifact) is not str
                or rel.startswith('/') or (rel and any(p in ('', '.', '..') for p in rel.split('/')))
                or (root, rel) in seen):
            raise ValueError('Selected Native package registry identity changed')
        seen.add((root, rel))
        path = Path(artifact)
        if root == 'actql/actql':
            expected = check_root / rel / ((Path(rel).name if rel else 'actql') + '.mi')
            if path != expected:
                raise ValueError('Selected Native registry artifact changed')
            entry['artifact'] = str(build_root / path.relative_to(check_root))
        elif root != 'moonbitlang/core' or not path.is_relative_to(
                moon_home / 'lib/core/_build/native/release/bundle'):
            raise ValueError('Foreign selected Native registry package')
    if not PACKAGES.issubset(root + '/' + rel for root, rel in seen):
        raise ValueError('Selected Native registry closure is incomplete')
    return (json.dumps(body, indent=2) + '\n').encode()



def prepare_allocator_source(moon_home: Path, destination: Path,
                             scoped_read: bool) -> tuple[Path | None, dict[str, object]]:
    """Choose source only; no compile/load/default adoption or allocation grant."""
    if type(scoped_read) is not bool:
        raise ValueError('Explicit Native allocator source selection is required')
    if not scoped_read:
        return None, {'kind': 'selected-stock', 'toolchain_unchanged': True}
    import importlib.util
    spec = importlib.util.spec_from_file_location('scoped_allocator_source',
        ROOT / 'packages/python-local-runtime/native/pre-root/prepare_scoped_read.py')
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    selected = destination / 'derived-read-source'
    record = module.prepare(moon_home, selected)
    return selected, {'kind': 'derived-scoped-read',
        'patch_sha256': record['patch_sha256'], 'recipe_sha256': record['recipe_sha256'],
        'outputs': record['outputs'], 'toolchain_unchanged': True,
        'installed_supplier': False, 'normal_profile': None}

def build(source: str, moon_home: Path, clang: Path, sdk: Path,
          destination: Path, seconds: int, *, scoped_read: bool = False) -> dict[str, object]:
    if type(scoped_read) is not bool:
        raise ValueError('Explicit Native allocator source selection is required')
    deadline = time.monotonic() + seconds
    environment = {**os.environ, 'MOON_HOME': str(moon_home), 'MOONBIT_NEW_NATIVE': '0',
                   'SDKROOT': str(sdk), 'MACOSX_DEPLOYMENT_TARGET': '11.0',
                   'PATH': str(moon_home / 'bin') + ':/usr/bin:/bin:/usr/sbin:/sbin'}

    def run(command: list[str], *, capture: bool = False) -> str:
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            raise TimeoutError('Original Native provider build deadline exhausted')
        result = subprocess.run(command, cwd=ROOT, env=environment, check=True,
                                timeout=remaining, text=True, capture_output=capture)
        return result.stdout if capture else ''

    if platform.system() != 'Darwin' or platform.machine() != 'arm64':
        raise ValueError('Selected Native provider requires darwin-arm64')
    if (run(['git', 'rev-parse', 'HEAD'], capture=True).strip() != source
            or run(['git', 'status', '--porcelain'], capture=True)):
        raise ValueError('Exact committed clean Native provider source required')
    run([sys.executable, str(ROOT / 'scripts/generate-local-native-runtime-binding.py'), '--check'])
    run([sys.executable, str(ROOT / 'scripts/generate-local-native-shim-bindings.py'), '--check'])
    run([sys.executable, str(ROOT / 'scripts/generate-local-native-memory-binding.py'), '--check'])
    pin = json.loads((ROOT / 'toolchain.json').read_text())
    marker = json.loads((moon_home / 'installed.json').read_text())
    if marker != {'pin': pin, 'platform': 'darwin-arm64'}:
        raise ValueError('Selected Native provider MoonBit pin mismatch')
    if (run([str(moon_home / 'bin/moonc'), '-v'], capture=True).strip() != pin['moonc']
            or run([str(moon_home / 'bin/moon'), 'version'], capture=True).splitlines()[0]
            != 'moon ' + pin['moon']):
        raise ValueError('Selected Native provider compiler mismatch')
    if not sdk.is_dir() or sdk.is_symlink():
        raise ValueError('Selected Native provider SDK must be an original directory')
    destination.mkdir(parents=True, exist_ok=False)
    # Maintainer-only, explicit derived build. This never modifies the selected
    # toolchain/default source or supplies a trusted installed capacity grant.
    allocator, allocator_record = prepare_allocator_source(moon_home, destination, scoped_read)
    generated = destination / 'emission'
    # Let the pinned Moon produce the complete package graph. This check does
    # not execute C or initialize a supplier, and introduces no hand-written MI.
    metadata = destination / 'metadata'
    run([str(moon_home / 'bin/moon'), 'check', '--target', 'native',
         '--target-dir', str(metadata), '-j', '1', ENTRY])
    check_root = metadata / 'native/debug/check'
    registry_source = check_root / 'all_pkgs.json'
    dry = run([str(moon_home / 'bin/moon'), 'build', '--target', 'native',
               '--target-dir', str(generated), '--dry-run', '-j', '1', ENTRY], capture=True)
    (destination / 'moon-dry-run.txt').write_text(dry)
    commands = emission_commands(dry, moon_home)
    registry = generated / 'native/debug/build/all_pkgs.json'
    registry.parent.mkdir(parents=True, exist_ok=True)
    registry.write_bytes(relocated_registry(registry_source.read_bytes(), check_root,
                                          registry.parent, moon_home))
    require_emission_registry(commands, registry)
    source_roots = [ROOT / 'src' / name.removeprefix('actql/actql/') for name in PACKAGES]
    source_inputs = [original(path) for directory in sorted(source_roots)
                     for path in sorted(directory.iterdir())
                     if path.is_file() and path.suffix in ('.mbt', '.pkg')]
    source_inputs += [original(PACKAGE_INPUT), original(registry_source), original(registry)]
    inputs = source_inputs + [original(clang), original(sdk / 'SDKSettings.json'),
                              original(ROOT / 'toolchain.json'), original(ROOT / 'moon.mod'),
                              original(moon_home / 'installed.json')]
    foreign_directories = { (ROOT / 'src' / path).parent for path, _ in FOREIGN_SOURCES }
    for directory in (moon_home / 'include', moon_home / 'lib/runtime',
                      *sorted(foreign_directories),
                      ROOT / 'packages/python-local-runtime/native/pre-root', ROOT / ENTRY):
        inputs += [original(path) for path in sorted(directory.rglob('*'))
                   if path.is_file() and path.suffix in ('.c', '.h', '.inc')]
    inputs += [original(ROOT / 'vendor/duckdb/1.4.3' / name)
               for name in ('duckdb.h', 'LICENSE', 'manifest.json')]
    if allocator is not None:
        inputs += [original(path) for path in sorted(allocator.iterdir()) if path.is_file()]
        candidate = ROOT / 'packages/python-local-runtime/native/pre-root'
        inputs += [original(candidate / name) for name in (
            'scoped-read-source.json', 'scoped-read-review.patch', 'prepare_scoped_read.py')]
    inputs += [original(moon_home / name) for name in
               ('bin/moon', 'bin/moonc', 'lib/libmoonbitrun.o', 'lib/libbacktrace.a')]
    inputs += [original(path) for path in sorted((moon_home / 'lib/core/_build/native/release/bundle').rglob('*'))
               if path.is_file() and path.suffix in ('.mi', '.core')]
    (destination / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    (destination / 'emission-commands.json').write_text(json.dumps(commands, indent=2) + '\n')
    for command in commands:
        output = Path(command[command.index('-o') + 1])
        output.parent.mkdir(parents=True, exist_ok=True)
        run(command)
    emitted = generated / 'native/debug/build/platform_native/installed_arena_entry/installed_arena_entry.c'
    c_sources = [(emitted, 'original')]
    # Same ordinary Native foreign closure. Only host_bootstrap supplies the
    # selected scoped allocator; other stubs do not create another provider.
    c_sources += [(ROOT / 'src' / path, name) for path, name in FOREIGN_SOURCES]
    c_sources += [(ROOT / ENTRY / (name + '.c'), name)
                  for name in ('control_shim', 'backing_shim', 'domain_shim', 'domain_read_shim',
                               'worker_selection_shim', 'live_channel_shim', 'process_shim', 'sqlite_shim',
                               'sqlite_database_shim', 'original_read_shim', 'packaged_runtime_shim',
                               'packaged_product_shim', 'runtime_initialization_shim',
                               'local_host_resources_shim', 'local_adoption_shim', 'read_crypto_shim')]
    runtime_source = allocator if allocator is not None else moon_home / 'lib/runtime'
    c_sources += [(runtime_source / (name + '.c'), 'runtime-' + name)
                  for name in ('backtrace', 'env', 'runtime', 'sync_io', 'utf')]
    objects = []
    compiler_inputs = []
    for path, name in c_sources:
        obj, deps = destination / (name + '.o'), destination / (name + '.d')
        common = [str(clang), '-isysroot', str(sdk), '-mmacosx-version-min=11.0',
                  '-I' + str(allocator if allocator is not None else moon_home / 'include'),
                  '-I' + str(ROOT / ENTRY),
                  '-fwrapv', '-fno-strict-aliasing', '-fPIC', '-g', '-O0',
                  '-DMOONBIT_ALLOCATOR=MOONBIT_ALLOCATOR_MIMALLOC']
        if allocator is not None:
            # The exact derived header precedes original supplemental headers.
            common += ['-I' + str(moon_home / 'include'), '-DACTQL_SCOPED_READ_ALLOCATOR']
            if name == 'bootstrap':
                common += ['-DACTQL_SCOPED_READ_PROVIDER="' + str(allocator / 'owned_capacity.c') + '"']
        if name == 'original':
            common += ['-Wno-unused-value', '-Dmain=actql_original_control_initialize',
                       '-include', str(ROOT / ENTRY / 'domain_read_shim.h'),
                       '-include', str(ROOT / ENTRY / 'worker_selection_shim.h'),
                       '-include', str(ROOT / ENTRY / 'live_channel_shim.h'),
                       '-include', str(ROOT / ENTRY / 'process_shim.h'),
                       '-include', str(ROOT / ENTRY / 'sqlite_shim.h'),
                       '-include', str(ROOT / ENTRY / 'sqlite_database_shim.h'),
                       '-include', str(ROOT / ENTRY / 'original_read_shim.h'),
                       '-include', str(ROOT / ENTRY / 'packaged_runtime_shim.h'),
                       '-include', str(ROOT / ENTRY / 'packaged_product_shim.h'),
                       '-include', str(ROOT / ENTRY / 'local_adoption_shim.h'),
                       '-include', str(ROOT / ENTRY / 'local_host_resources_shim.h'),
                       '-include', str(ROOT / ENTRY / 'read_crypto_shim.h')]
        elif name.startswith('runtime-'):
            common += ['-Wno-unused-value', '-DMOONBIT_ALLOW_STACKTRACE']
        else:
            common += ['-std=c11', '-Wall', '-Wextra', '-Werror']
            if name == 'bootstrap':
                common += ['-Wno-error=deprecated-declarations']
        command = common + ['-MD', '-MF', str(deps), '-c', str(path), '-o', str(obj)]
        run(command)
        objects.append(obj)
        dependency_paths = shlex.split(deps.read_text().replace('\\\n', ' '))[1:]
        compiler_inputs += [original_dependency(Path(name), sdk) for name in dependency_paths]
        (destination / 'compiled-inputs.json').write_text(json.dumps(compiler_inputs, indent=2) + '\n')
    library = destination / LIBRARY
    link = [str(clang), '-isysroot', str(sdk), '-mmacosx-version-min=11.0',
            '-dynamiclib', '-Wl,-install_name,@rpath/' + LIBRARY, '-o', str(library),
            str(moon_home / 'lib/libmoonbitrun.o')] + [str(path) for path in objects]
    link += ['-lm', str(moon_home / 'lib/libbacktrace.a')]
    (destination / 'link-command.json').write_text(json.dumps(link, indent=2) + '\n')
    run(link)
    # Reuse the existing Mach-O target/system-dependency inspector, without load.
    import importlib.util
    spec = importlib.util.spec_from_file_location('local_runtime_recipe', ROOT / 'scripts/prepare-python-local-runtime.py')
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    module.library_target(library)
    for item in inputs:
        if original(Path(str(item['path']))) != item:
            raise ValueError('Original Native provider input changed during build')
    if (run(['git', 'rev-parse', 'HEAD'], capture=True).strip() != source
            or run(['git', 'status', '--porcelain'], capture=True)):
        raise ValueError('Original Native provider source changed during build')
    record = {'source': source, 'target': 'aarch64-apple-darwin', 'deployment_target': '11.0',
              'emission_build_packages': 163, 'emission_link_core': 1,
              'diagnostic_debug_registry_omitted': False,
              'c_compile': len(objects), 'c_link': 1, 'emitted_c': original(emitted),
              'library': original(library), 'objects': [original(path) for path in objects],
              'initializer_calls': 0, 'Engine': 0, 'VM': 0, 'worker': 0,
              'wheel': 0, 'public_e2e': 0, 'normal_numeric_profile': None,
              'allocator_source': allocator_record}
    (destination / 'provider-build.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--moon-home', required=True, type=Path)
    parser.add_argument('--clang', required=True, type=Path)
    parser.add_argument('--sdk', required=True, type=Path)
    parser.add_argument('--destination', required=True, type=Path)
    parser.add_argument('--seconds', type=int, default=300)
    parser.add_argument('--scoped-read', action='store_true',
        help='Build exact copied scoped allocator sources; no default/toolchain/profile adoption')
    args = parser.parse_args()
    print(json.dumps(build(args.source, args.moon_home, args.clang, args.sdk,
                           args.destination, args.seconds, scoped_read=args.scoped_read), sort_keys=True))
