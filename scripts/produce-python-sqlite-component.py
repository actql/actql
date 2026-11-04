"""Build a relocatable private SQLite candidate with the one original provider.

Maintainer-only, through the existing bounded guard. No library is loaded,
initialized or selected by the product; no capacity/profile/authority is issued.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import re
import shlex
import stat
import subprocess
import sys
import time
from typing import Any, cast

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / 'packages/python-local-runtime/native/sqlite-component'
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_distribution import _hex, _pairs, _read_file  # noqa: E402


def load_recipe(name: str, path: Path) -> Any:
    spec = importlib.util.spec_from_file_location(name, path)
    if spec is None or spec.loader is None:
        raise ValueError('Selected SQLite producer recipe is unavailable')
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


STAGE = load_recipe('sqlite_source_stage', SOURCE / 'prepare.py')
METADATA = load_recipe('sqlite_native_metadata', ROOT / 'scripts/prepare-python-local-runtime.py')
LIBRARY = 'libactql_sqlite_component.dylib'
PROVIDER = 'libactql_native_control.dylib'
NOTICE = 'SQLITE-NOTICE'
EXPORTS = frozenset('_actql_sqlite_component_' + name for name in (
    'source_id', 'bind', 'free', 'close', 'allocate', 'resize', 'size',
    'heap_wal', 'readonly_heap_wal', 'descriptor_ack', 'borrow_api', 'release_api'))


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def identity(path: Path, maximum: int) -> dict[str, Any]:
    # The selected compiler is larger than a runtime member. Hash bounded
    # blocks without retaining that executable in a second Python buffer.
    with os.fdopen(os.open(path, os.O_RDONLY | os.O_NOFOLLOW | os.O_NONBLOCK), 'rb') as source:
        before = os.fstat(source.fileno())
        require(stat.S_ISREG(before.st_mode) and 0 < before.st_size <= maximum,
                'Invalid SQLite producer input size')
        checksum, remaining = hashlib.sha256(), before.st_size
        while remaining:
            block = source.read(min(65536, remaining))
            require(bool(block), 'Incomplete SQLite producer input')
            checksum.update(block)
            remaining -= len(block)
        after = os.fstat(source.fileno())
        fields = ('st_dev', 'st_ino', 'st_size', 'st_mtime_ns', 'st_ctime_ns')
        require(not source.read(1) and all(getattr(before, field) == getattr(after, field)
                for field in fields), 'SQLite producer input changed')
        return {'bytes': before.st_size, 'sha256': checksum.hexdigest()}


def checked_copy(source: Path, target: Path, expected: dict[str, Any], maximum: int) -> None:
    raw = _read_file(source, maximum=maximum, expected=expected['bytes'],
                     digest=expected['sha256'], capture=True)
    # A fresh output only. Neither an installed input nor an old failed stage
    # may be overwritten, even when the input and output digests would match.
    with target.open('xb') as output:
        output.write(raw)
    _read_file(target, maximum=maximum, expected=expected['bytes'], digest=expected['sha256'])


def compiled_input(path: Path, sdk: Path) -> dict[str, Any]:
    # Apple SDK headers include relative symlinks (e.g. pthread.h). Record
    # both spellings, allowing resolution only inside the selected SDK. Source,
    # provider and staged inputs retain the original no-follow requirement.
    selected_sdk = sdk.resolve(strict=True)
    if path.is_relative_to(sdk):
        resolved = path.resolve(strict=True)
        require(resolved.is_relative_to(selected_sdk), 'SDK dependency escapes selected SDK')
        return {'resolved_path': str(resolved), **identity(resolved, 16 * 1024 * 1024)}
    return {'resolved_path': str(path), **identity(path, 16 * 1024 * 1024)}


def selected_provider(record: Any, source: str, retained_source: str | None) -> tuple[Path, dict[str, Any]]:
    require(type(record) is dict and _hex(source, 40), 'Invalid selected SQLite source')
    expected = source if retained_source is None else retained_source
    require(_hex(expected, 40) and record.get('source') == expected,
            'Native provider must match the exact source or explicit retained diagnostic source')
    require(record.get('target') == 'aarch64-apple-darwin'
            and record.get('deployment_target') == '11.0'
            and record.get('normal_numeric_profile') is None
            and type(record.get('initializer_calls')) is int and record['initializer_calls'] == 0,
            'Incompatible original Native provider receipt')
    allocator = record.get('allocator_source')
    require(type(allocator) is dict and allocator.get('kind') == 'derived-scoped-read',
            'SQLite component requires the same scoped original Native provider')
    library = record.get('library')
    require(type(library) is dict and set(library) == {'path', 'bytes', 'sha256'}
            and type(library['path']) is str and Path(library['path']).is_absolute()
            and _hex(library['sha256'], 64)
            and type(library['bytes']) is int and 0 < library['bytes'] <= 128 * 1024 * 1024,
            'Invalid original Native provider descriptor')
    require(type(allocator.get('outputs')) is dict, 'Invalid original provider allocation outputs')
    original_header = allocator['outputs'].get('owned_capacity.h')
    expected_header = identity(ROOT / 'packages/python-local-runtime/native/pre-root/owned_capacity.h', 65536)
    require(original_header == expected_header,
            'Original provider allocation ABI header differs from this component')
    return Path(library['path']), library


def verify_bundle(directory: Path, *, source: str, provider_source: str,
                  provider_sha256: str) -> dict[str, Any]:
    """Inspect copied bytes/metadata only. This does not load or grant use."""
    raw = _read_file(directory / 'sqlite-component.json', maximum=65536, capture=True)
    body = json.loads(raw, object_pairs_hook=_pairs)
    require(type(body) is dict and set(body) == {
        'version', 'source_sha', 'provider_source_sha', 'platform', 'deployment_target',
        'component_api_abi', 'upstream_source_id', 'recipe_sha256', 'library', 'provider',
        'notice', 'cohort_compatible', 'normal_profile', 'loaded', 'initialized'},
        'Invalid closed SQLite bundle manifest')
    require(body['version'] == 'actql-python-sqlite-component-candidate/0.1'
            and _hex(source, 40) and body['source_sha'] == source
            and _hex(provider_source, 40) and body['provider_source_sha'] == provider_source
            and body['platform'] == 'darwin-arm64' and body['deployment_target'] == '11.0'
            and type(body['component_api_abi']) is int and body['component_api_abi'] == 2
            and body['normal_profile'] is None and body['loaded'] is False
            and body['initialized'] is False and type(body['cohort_compatible']) is bool
            and body['cohort_compatible'] == (source == provider_source),
            'SQLite candidate source/ABI/cohort mismatch')
    recipe = json.loads((SOURCE / 'source.json').read_bytes())
    require(body['recipe_sha256'] == hashlib.sha256((SOURCE / 'source.json').read_bytes()).hexdigest()
            and body['upstream_source_id'] == recipe['upstream']['source_id'],
            'SQLite candidate original recipe mismatch')
    for field, filename, maximum in (('library', LIBRARY, 128 * 1024 * 1024),
                                      ('provider', PROVIDER, 128 * 1024 * 1024),
                                      ('notice', NOTICE, 1024 * 1024)):
        item = body[field]
        require(type(item) is dict and set(item) == {'file', 'bytes', 'sha256'}
                and item['file'] == filename and type(item['bytes']) is int
                and 0 < item['bytes'] <= maximum and _hex(item['sha256'], 64),
                'Invalid SQLite bundle member descriptor')
        _read_file(directory / filename, maximum=maximum, expected=item['bytes'], digest=item['sha256'])
    require(body['provider']['sha256'] == provider_sha256,
            'SQLite bundle uses a different original provider')
    METADATA.library_target(directory / LIBRARY, identity=('@rpath/' + LIBRARY).encode(),
                            bundled=(('@loader_path/' + PROVIDER).encode(),), rpaths=())
    METADATA.library_target(directory / PROVIDER, identity=('@rpath/' + PROVIDER).encode(), rpaths=())
    return cast(dict[str, Any], body)


def build(source: str, archive: Path, provider_receipt: Path, clang: Path, sdk: Path,
          destination: Path, seconds: int, *, retained_provider_source: str | None = None) -> dict[str, Any]:
    require(sys.platform == 'darwin' and platform.machine() == 'arm64',
            'SQLite candidate build requires selected darwin-arm64')
    require(type(seconds) is int and seconds > 0 and _hex(source, 40), 'Invalid SQLite build selection')
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == source
            and not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT),
            'Use the exact committed clean SQLite producer source')
    require(not destination.exists() and not destination.is_symlink(), 'SQLite output already exists')
    receipt_raw = _read_file(provider_receipt, maximum=65536, capture=True)
    provider_record = json.loads(receipt_raw, object_pairs_hook=_pairs)
    provider, provider_item = selected_provider(provider_record, source, retained_provider_source)
    METADATA.library_target(provider, identity=('@rpath/' + PROVIDER).encode(), rpaths=())
    destination.mkdir(parents=True, exist_ok=False)
    bundle = destination / 'bundle'
    bundle.mkdir()
    stage = destination / 'source'
    staged = STAGE.prepare(archive, stage)
    copied_provider = bundle / PROVIDER
    checked_copy(provider, copied_provider, provider_item, 128 * 1024 * 1024)
    notice = identity(stage / 'NOTICE', 1024 * 1024)
    checked_copy(stage / 'NOTICE', bundle / NOTICE, notice, 1024 * 1024)
    inputs = {str(path): identity(path, maximum) for path, maximum in (
        (clang, 512 * 1024 * 1024), (sdk / 'SDKSettings.json', 1024 * 1024),
        (Path('/usr/bin/install_name_tool'), 16 * 1024 * 1024),
        (Path('/usr/bin/codesign'), 16 * 1024 * 1024),
        (provider_receipt, 65536), (SOURCE / 'source.json', 65536),
        (ROOT / 'scripts/produce-python-sqlite-component.py', 65536),
        (ROOT / 'scripts/prepare-python-local-runtime.py', 65536),
        (ROOT / 'packages/python-local-runtime/native/pre-root/owned_capacity.h', 65536))}
    (destination / 'inputs.json').write_text(json.dumps(inputs, indent=2) + '\n')
    deadline = time.monotonic() + seconds
    steps = []
    environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'SDKROOT': str(sdk),
                   'MACOSX_DEPLOYMENT_TARGET': '11.0', 'LANG': 'C', 'LC_ALL': 'C'}

    def run(name: str, args: list[str]) -> str:
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'SQLite candidate cumulative build budget exhausted')
        result = subprocess.run(args, cwd=ROOT, env=environment, capture_output=True,
                                text=True, timeout=remaining)
        (destination / (name + '.stdout')).write_text(result.stdout)
        (destination / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': args, 'exit': result.returncode})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        require(result.returncode == 0, 'SQLite candidate command failed: ' + name)
        return result.stdout

    common = [str(clang), '-std=c11', staged['optimization'], '-fPIC', '-fvisibility=hidden',
              '-mmacosx-version-min=11.0', '-isysroot', str(sdk), '-I' + str(stage),
              '-I' + str(ROOT / 'packages/python-local-runtime/native/pre-root')]
    obj, library = destination / 'component.o', bundle / LIBRARY
    run('compile', common + ['-MD', '-MF', str(destination / 'component.d'),
                            '-c', str(stage / 'component.c'), '-o', str(obj)])
    run('link', common + ['-dynamiclib', str(obj), '-L' + str(bundle), '-lactql_native_control',
                         '-Wl,-headerpad_max_install_names',
                         '-Wl,-install_name,@rpath/' + LIBRARY, '-o', str(library)])
    # The provider's own install identity remains unchanged. Bind this new
    # component directly to its sibling, without adding a runtime search path.
    run('bind-original-provider', ['/usr/bin/install_name_tool', '-change',
        '@rpath/' + PROVIDER, '@loader_path/' + PROVIDER, str(library)])
    # Refresh only this generated library's ad-hoc code signature after its
    # load-command change; no credential or installed artifact is involved.
    run('sign-generated-component', ['/usr/bin/codesign', '--force', '--sign', '-', str(library)])
    run('verify-generated-component', ['/usr/bin/codesign', '--verify', '--strict', str(library)])
    symbols = run('exports', ['/usr/bin/nm', '-gU', str(library)])
    require({line.split()[-1] for line in symbols.splitlines() if line.strip()} == EXPORTS,
            'Unexpected SQLite component exports or public SQLite API')
    item = identity(library, 128 * 1024 * 1024)
    body = {'version': 'actql-python-sqlite-component-candidate/0.1', 'source_sha': source,
            'provider_source_sha': provider_record['source'], 'platform': 'darwin-arm64',
            'deployment_target': '11.0', 'component_api_abi': 2,
            'upstream_source_id': staged['upstream']['source_id'],
            'recipe_sha256': staged['recipe_sha256'], 'library': {'file': LIBRARY, **item},
            'provider': {'file': PROVIDER, 'bytes': provider_item['bytes'], 'sha256': provider_item['sha256']},
            'notice': {'file': NOTICE, **notice}, 'cohort_compatible': source == provider_record['source'],
            'normal_profile': None, 'loaded': False, 'initialized': False}
    (bundle / 'sqlite-component.json').write_text(json.dumps(body, indent=2) + '\n')
    verify_bundle(bundle, source=source, provider_source=provider_record['source'],
                  provider_sha256=provider_item['sha256'])
    dependencies = shlex.split((destination / 'component.d').read_text().replace('\\\n', ' ').split(':', 1)[1])
    (destination / 'compiled-inputs.json').write_text(json.dumps({path: compiled_input(Path(path), sdk)
        for path in sorted(set(dependencies))}, indent=2) + '\n')
    for path, expected in inputs.items():
        require(identity(Path(path), 512 * 1024 * 1024) == expected, 'SQLite build input changed')
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == source
            and not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT),
            'SQLite build source changed')
    record = {'source_sha': source, 'provider_source_sha': provider_record['source'],
              'provider_receipt_sha256': hashlib.sha256(receipt_raw).hexdigest(),
              'bundle': str(bundle), 'manifest': identity(bundle / 'sqlite-component.json', 65536),
              'object': identity(obj, 128 * 1024 * 1024), 'component': body,
              'compile': 1, 'link': 1, 'loaded': False, 'initialized': False,
              'normal_profile': None, 'public_E2E': 0}
    (destination / 'producer.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


PROCESS_IMPORTS = frozenset('actql_' + name for name in (
    'native_owned_current', 'native_owned_retire', 'native_file_scoped_allocate',
    'native_file_scoped_free', 'read_context_retain',
    'read_context_release_after_owner_ack', 'bootstrap_current_read_context'))


def inspect_process_component(library: Path, *, execute: Any = subprocess.check_output) -> dict[str, Any]:
    """Check the component image only; no process provider or physical admission."""
    observed = identity(library, 64 * 1024 * 1024)
    def read(tool: str, arguments: list[str]) -> str:
        return cast(str, execute([tool, *arguments], text=True))
    names = {line.split()[-1] for line in read('/usr/bin/nm', ['-gU', str(library)]).splitlines()}
    require(names == EXPORTS, 'Unexpected process SQLite component exports')
    undefined = set(read('/usr/bin/nm', ['-u', str(library)]).split())
    require({name for name in undefined if name.startswith('_actql_')} ==
            {'_' + name for name in PROCESS_IMPORTS},
            'Original process SQLite provider imports differ')
    links = read('/usr/bin/otool', ['-L', str(library)])
    dependencies = [line.strip().split(' (', 1)[0] for line in links.splitlines()[1:]]
    require(dependencies == ['@rpath/' + LIBRARY, '/usr/lib/libSystem.B.dylib'],
            'Process SQLite component has another provider or library dependency')
    loads = read('/usr/bin/otool', ['-l', str(library)])
    require('cmd LC_RPATH' not in loads, 'Process SQLite component has an ambient search path')
    minimum = re.search(r'cmd LC_BUILD_VERSION\s+cmdsize \d+\s+platform 1\s+minos ([0-9.]+)', loads)
    if minimum is None or minimum[1] != '11.0':
        raise ValueError('Process SQLite component deployment identity differs')
    require(identity(library, 64 * 1024 * 1024) == observed,
            'Process SQLite component changed during inspection')
    return {'library': observed, 'exports': sorted(names),
            'provider_imports': sorted(PROCESS_IMPORTS), 'links': links,
            'minimum_macos': minimum[1]}


def build_process_import(source: str, archive: Path, clang: Path, sdk: Path,
                         destination: Path, seconds: int) -> dict[str, Any]:
    """Compile for the existing Native executable namespace, never another DLL.

    The same original process provider is still mandatory at actual bind. This
    does not satisfy the stronger Python bundle or its final loader gates.
    """
    require(sys.platform == 'darwin' and platform.machine() == 'arm64',
            'Process SQLite component requires selected darwin-arm64')
    require(type(seconds) is int and seconds > 0 and _hex(source, 40),
            'Invalid process SQLite build selection')
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == source
            and not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT),
            'Use the exact committed clean process SQLite producer source')
    require(not destination.exists() and not destination.is_symlink(), 'SQLite output already exists')
    destination.mkdir(parents=True, exist_ok=False)
    stage = destination / 'source'
    staged = STAGE.prepare(archive, stage)
    inputs = {str(path): identity(path, maximum) for path, maximum in (
        (archive, 5 * 1024 * 1024), (clang, 512 * 1024 * 1024),
        (sdk / 'SDKSettings.json', 1024 * 1024), (SOURCE / 'source.json', 65536),
        (ROOT / 'scripts/produce-python-sqlite-component.py', 65536),
        (ROOT / 'packages/python-local-runtime/native/pre-root/owned_capacity.h', 65536))}
    deadline = time.monotonic() + seconds
    steps: list[dict[str, Any]] = []
    environment = {'PATH': '/usr/bin:/bin:/usr/sbin:/sbin', 'SDKROOT': str(sdk),
                   'MACOSX_DEPLOYMENT_TARGET': '11.0', 'LANG': 'C', 'LC_ALL': 'C'}
    def run(name: str, arguments: list[str]) -> None:
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'Process SQLite build budget exhausted')
        result = subprocess.run(arguments, cwd=ROOT, env=environment, capture_output=True,
                                text=True, timeout=remaining)
        (destination / (name + '.stdout')).write_text(result.stdout)
        (destination / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': arguments, 'exit': result.returncode})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        require(result.returncode == 0, 'Process SQLite command failed: ' + name)
    obj, library = destination / 'component.o', destination / LIBRARY
    common = [str(clang), '-std=c11', staged['optimization'], '-fPIC', '-fvisibility=hidden',
              '-mmacosx-version-min=11.0', '-isysroot', str(sdk), '-I' + str(stage),
              '-I' + str(ROOT / 'packages/python-local-runtime/native/pre-root')]
    run('compile', common + ['-MD', '-MF', str(destination / 'component.d'),
                            '-c', str(stage / 'component.c'), '-o', str(obj)])
    run('link-process-imports', common + ['-dynamiclib', str(obj),
        '-Wl,-undefined,dynamic_lookup', '-Wl,-install_name,@rpath/' + LIBRARY, '-o', str(library)])
    inspected = inspect_process_component(library)
    dependencies = shlex.split((destination / 'component.d').read_text().replace('\\\n', ' ').split(':', 1)[1])
    compiled = {path: compiled_input(Path(path), sdk) for path in sorted(set(dependencies))}
    for path, expected in inputs.items():
        require(identity(Path(path), 512 * 1024 * 1024) == expected, 'Process SQLite build input changed')
    for path, expected in compiled.items():
        require(compiled_input(Path(path), sdk) == expected, 'Process SQLite compiler input changed')
    checked_copy(stage / 'NOTICE', destination / NOTICE, identity(stage / 'NOTICE', 1024 * 1024), 1024 * 1024)
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == source
            and not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT),
            'Process SQLite build source changed')
    record = {'source_sha': source, 'target': staged['target'],
              'provider_binding': 'same original process namespace; actual binding required before use',
              'recipe_sha256': staged['recipe_sha256'], 'stage': staged,
              **inspected, 'object': identity(obj, 128 * 1024 * 1024),
              'inputs': inputs, 'compiled_inputs': compiled,
              'notice': identity(destination / NOTICE, 1024 * 1024),
              'compile': 1, 'link': 1, 'loaded': False, 'initialized': False,
              'normal_profile': None, 'installed_supplier': False, 'public_E2E': 0}
    (destination / 'process-producer.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


LINUX_LIBRARY = 'libactql_sqlite_component.so'
_LINUX_SYSTEM_LIBRARIES = frozenset(('libc.so.6', 'libm.so.6', 'libdl.so.2', 'libpthread.so.0'))


def linux_process_architecture(process_target: str) -> tuple[str, str, int]:
    require(type(process_target) is str and process_target in ('linux-arm64-gnu', 'linux-x64-gnu'),
            'Unsupported Linux process SQLite target selection')
    return (('aarch64', 'AArch64', 183) if process_target == 'linux-arm64-gnu'
            else ('x86_64', 'x86-64', 62))


def inspect_linux_process_component(library: Path, *, process_target: str = 'linux-arm64-gnu',
                                    execute: Any = subprocess.check_output) -> dict[str, Any]:
    """Inspect the selected ELF image; actual same-process binding is separate."""
    architecture, image, machine = linux_process_architecture(process_target)
    observed = identity(library, 64 * 1024 * 1024)
    header = _read_file(library, maximum=64 * 1024 * 1024, prefix=64)
    require(len(header) == 64 and header[:7] == b'\x7fELF\x02\x01\x01'
            and header[7] in (0, 3) and int.from_bytes(header[20:24], 'little') == 1
            and int.from_bytes(header[52:54], 'little') == 64
            and int.from_bytes(header[16:18], 'little') == 3
            and int.from_bytes(header[18:20], 'little') == machine,
            'Process SQLite requires ELF64 little-endian ' + image + ' shared image')
    def read(tool: str, arguments: list[str]) -> str:
        return cast(str, execute([tool, *arguments], text=True))
    definitions = read('/usr/bin/nm', ['-D', '--defined-only', str(library)])
    names = {line.split()[-1] for line in definitions.splitlines() if line.strip()}
    require(names == {name[1:] for name in EXPORTS}, 'Unexpected Linux SQLite component exports')
    unresolved = read('/usr/bin/nm', ['-D', '--undefined-only', str(library)])
    imports: set[str] = set()
    for line in unresolved.splitlines():
        fields = line.split()
        if not fields:
            continue
        name = fields[-1]
        if name.startswith('actql_'):
            imports.add(name)
        else:
            require(not name.startswith('sqlite3_') and re.fullmatch(
                r'[A-Za-z_][A-Za-z0-9_]*@GLIBC_[0-9]+(?:\.[0-9]+)*', name) is not None,
                'Unexpected Linux component system import')
    require(imports == PROCESS_IMPORTS, 'Original process SQLite provider imports differ')
    dynamic = read('/usr/bin/readelf', ['--dynamic', '--wide', str(library)])
    dependencies = re.findall(r'\(NEEDED\).*\[([^\]]+)\]', dynamic)
    require(len(dependencies) == len(set(dependencies)) and 'libc.so.6' in dependencies
            and set(dependencies) <= _LINUX_SYSTEM_LIBRARIES,
            'Linux process SQLite has another provider or library dependency')
    require(re.findall(r'\(SONAME\).*\[([^\]]+)\]', dynamic) == [LINUX_LIBRARY],
            'Linux process SQLite SONAME differs')
    require(re.search(r'\((?:RPATH|RUNPATH|INIT|FINI|INIT_ARRAY|FINI_ARRAY|PREINIT_ARRAY)\)', dynamic) is None,
            'Linux process SQLite has an ambient search path or automatic initializer')
    segments = read('/usr/bin/readelf', ['--program-headers', '--wide', str(library)])
    require(re.search(r'^\s*TLS\s', segments, re.MULTILINE) is None,
            'Linux process SQLite has unselected component TLS')
    require(identity(library, 64 * 1024 * 1024) == observed,
            'Linux process SQLite component changed during inspection')
    return {'library': observed, 'exports': sorted(names),
            'provider_imports': sorted(imports), 'system_dependencies': sorted(dependencies),
            'target': architecture + '-unknown-linux-gnu', 'elf_machine': machine,
            'automatic_initializers': False,
            'component_tls': False}


def build_linux_process_import(source: str, archive: Path, clang: Path,
                               destination: Path, seconds: int, *,
                               process_target: str = 'linux-arm64-gnu') -> dict[str, Any]:
    """Prepare one ELF for the same original process; never a second provider.

    No image is loaded and no physical supplier, normal installation or Python
    release is admitted. Darwin process and strong Python bundle paths retain
    their original checks.
    """
    architecture, _, _ = linux_process_architecture(process_target)
    require(sys.platform == 'linux' and platform.machine() == architecture,
            'Linux process SQLite requires selected ' + process_target)
    require(type(seconds) is int and seconds > 0 and _hex(source, 40),
            'Invalid Linux process SQLite build selection')
    def clean() -> None:
        require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip() == source
                and not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT),
                'Use the exact committed clean Linux process SQLite producer source')
    clean()
    require(not destination.exists() and not destination.is_symlink(), 'SQLite output already exists')
    # Select and hash actual tools before their first invocation. Resolving the
    # trusted system bin link identifies the tool; it does not adopt a provider.
    nm, readelf = Path('/usr/bin/nm').resolve(strict=True), Path('/usr/bin/readelf').resolve(strict=True)
    inputs = {str(path): identity(path, maximum) for path, maximum in (
        (archive, 5 * 1024 * 1024), (clang, 512 * 1024 * 1024),
        (nm, 64 * 1024 * 1024), (readelf, 64 * 1024 * 1024),
        (SOURCE / 'source.json', 65536), (SOURCE / 'prepare.py', 65536),
        (ROOT / 'scripts/produce-python-sqlite-component.py', 65536),
        (ROOT / 'packages/python-local-runtime/native/pre-root/owned_capacity.h', 65536))}
    destination.mkdir(parents=True, exist_ok=False)
    deadline, steps = time.monotonic() + seconds, []
    environment = {'PATH': '/usr/bin:/bin', 'LANG': 'C', 'LC_ALL': 'C'}
    def run(name: str, arguments: list[str]) -> str:
        remaining = deadline - time.monotonic()
        require(remaining > 0, 'Linux process SQLite build budget exhausted')
        result = subprocess.run(arguments, cwd=ROOT, env=environment, capture_output=True,
                                text=True, timeout=remaining)
        (destination / (name + '.stdout')).write_text(result.stdout)
        (destination / (name + '.stderr')).write_text(result.stderr)
        steps.append({'name': name, 'command': arguments, 'exit': result.returncode})
        (destination / 'steps.json').write_text(json.dumps(steps, indent=2) + '\n')
        require(result.returncode == 0, 'Linux process SQLite command failed: ' + name)
        return result.stdout
    target = run('compiler-target', [str(clang), '-dumpmachine']).strip()
    require(re.fullmatch(architecture + r'-(?:[A-Za-z0-9_.]+-)?linux-gnu', target) is not None,
            'Selected compiler target is not GNU Linux ' + architecture)
    resource = Path(run('compiler-resource-dir', [str(clang), '-print-resource-dir']).strip())
    require(resource.is_absolute() and resource.is_dir(), 'Invalid compiler resource directory')
    stage = destination / 'source'
    staged = STAGE.prepare(archive, stage, process_target=process_target)
    obj, library = destination / 'component.o', destination / LINUX_LIBRARY
    common = [str(clang), '-std=c11', staged['optimization'], '-fPIC', '-fvisibility=hidden']
    if process_target == 'linux-arm64-gnu':
        common.append('-mno-outline-atomics')
    common += ['-I' + str(stage), '-I' + str(ROOT / 'packages/python-local-runtime/native/pre-root')]
    run('compile', common + ['-MD', '-MF', str(destination / 'component.d'),
                            '-c', str(stage / 'component.c'), '-o', str(obj)])
    exports = destination / 'component.exports'
    exports.write_text('{ global:\n' + ''.join('  ' + name[1:] + ';\n' for name in sorted(EXPORTS))
                       + 'local: *;\n};\n')
    run('link-process-imports', [str(clang), '-shared', '-nostartfiles', str(obj),
        '-Wl,--version-script=' + str(exports), '-Wl,-soname,' + LINUX_LIBRARY,
        '-Wl,-z,now', '-Wl,-z,relro', '-o', str(library), '-ldl', '-lpthread', '-lm'])
    require(Path('/usr/bin/nm').resolve(strict=True) == nm
            and Path('/usr/bin/readelf').resolve(strict=True) == readelf, 'Selected Linux inspection tool changed')
    inspected = inspect_linux_process_component(library, process_target=process_target)
    require(Path('/usr/bin/nm').resolve(strict=True) == nm
            and Path('/usr/bin/readelf').resolve(strict=True) == readelf, 'Selected Linux inspection tool changed')
    dependencies = shlex.split((destination / 'component.d').read_text().replace('\\\n', ' ').split(':', 1)[1])
    compiled = {}
    for name in sorted(set(dependencies)):
        path = Path(name)
        header_root = next((root for root in (resource, Path('/usr/include'))
                            if path.is_relative_to(root)), None)
        compiled[name] = (compiled_input(path, header_root) if header_root is not None
                          else {'resolved_path': name, **identity(path, 16 * 1024 * 1024)})
    for name, expected in inputs.items():
        require(identity(Path(name), 512 * 1024 * 1024) == expected,
                'Linux process SQLite build input changed')
    for name, expected in compiled.items():
        require(identity(Path(expected['resolved_path']), 16 * 1024 * 1024) ==
                {key: expected[key] for key in ('bytes', 'sha256')},
                'Linux process SQLite compiler input changed')
    checked_copy(stage / 'NOTICE', destination / NOTICE, identity(stage / 'NOTICE', 1024 * 1024), 1024 * 1024)
    clean()
    record = {'source_sha': source, 'provider_binding': 'same original process namespace; actual binding required before use',
              'recipe_sha256': staged['recipe_sha256'], 'stage': staged, **inspected,
              'object': identity(obj, 128 * 1024 * 1024), 'inputs': inputs,
              'compiled_inputs': compiled, 'compiler_target': target,
              'notice': identity(destination / NOTICE, 1024 * 1024),
              'compile': 1, 'link': 1, 'loaded': False, 'initialized': False,
              'normal_profile': None, 'installed_supplier': False, 'public_E2E': 0}
    (destination / 'process-producer.json').write_text(json.dumps(record, indent=2) + '\n')
    return record


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--archive', type=Path, required=True)
    binding = parser.add_mutually_exclusive_group(required=True)
    binding.add_argument('--provider-receipt', type=Path)
    binding.add_argument('--process-provider', action='store_true')
    parser.add_argument('--clang', type=Path, required=True)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--process-target', choices=('darwin-arm64', 'linux-arm64-gnu', 'linux-x64-gnu'), default='darwin-arm64')
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--seconds', type=int, default=50)
    parser.add_argument('--diagnostic-retained-provider-source',
                        help='Explicit mixed-source candidate only; never a matching release cohort')
    args = parser.parse_args()
    if args.process_provider:
        require(args.diagnostic_retained_provider_source is None,
                'Process component cannot borrow a diagnostic provider source')
        if args.process_target in ('linux-arm64-gnu', 'linux-x64-gnu'):
            require(args.sdk is None, 'Linux process preparation does not accept a Darwin SDK')
            result = build_linux_process_import(args.source, args.archive, args.clang, args.destination, args.seconds,
                process_target=args.process_target)
        else:
            require(args.sdk is not None, 'Darwin process preparation requires its selected SDK')
            result = build_process_import(args.source, args.archive, args.clang,
                args.sdk, args.destination, args.seconds)
    else:
        require(args.sdk is not None and args.process_target == 'darwin-arm64',
                'The original Python bundle requires its selected Darwin SDK and provider')
        result = build(args.source, args.archive, args.provider_receipt, args.clang,
            args.sdk, args.destination, args.seconds,
            retained_provider_source=args.diagnostic_retained_provider_source)
    print(json.dumps(result))
