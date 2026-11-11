"""Assemble fixed Python Local components from original physical receipts.

This maintainer producer does not compile, load an engine, build a wheel,
execute a Run, publish, or grant authority. Consumers only install wheels.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import platform
import shlex
import stat
import subprocess
import sys
import tomllib
from typing import Any, cast

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_wasm_abi import LOCAL_CORE_ABI  # noqa: E402
from actql_sdk._local_distribution import WASMTIME_VERSION, DUCKDB_VERSION, _pairs, _read_file, _valid_image_header  # noqa: E402
from actql_sdk._local_image_recipe import _SelectedImageRecipe, _recipe_from_original  # noqa: E402

_spec = importlib.util.spec_from_file_location(
    'python_local_runtime_recipe', ROOT / 'scripts/prepare-python-local-runtime.py')
if _spec is None or _spec.loader is None:
    raise RuntimeError('Python Local runtime recipe is unavailable')
recipe = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(recipe)


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValueError(message)


def clean_source() -> str:
    require(subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT) == b'',
            'Use committed clean Python Local producer source')
    return subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()


def read_receipt(path: Path) -> tuple[dict[str, Any], str]:
    raw = _read_file(path, maximum=65536)
    value = json.loads(raw, object_pairs_hook=_pairs)
    require(type(value) is dict, 'Invalid Python Local original receipt')
    return cast(dict[str, Any], value), hashlib.sha256(raw).hexdigest()


def component(path: Path, digest: str, maximum: int, filename: str) -> dict[str, object]:
    size = path.lstat()
    require(stat.S_ISREG(size.st_mode), 'Selected component must be an original regular file')
    _read_file(path, maximum=maximum, expected=size.st_size, digest=digest)
    return {'file': filename, 'bytes': size.st_size, 'sha256': digest}


def copy_original(path: Path, target: Path, maximum: int, digest: str) -> None:
    # Read the original through the same bounded, no-follow digest check at
    # copy time; a growing or replaced input cannot turn copying into unbounded I/O.
    raw = _read_file(path, maximum=maximum)
    require(hashlib.sha256(raw).hexdigest() == digest, 'Original component changed before copying')
    target.write_bytes(raw)


MODULE_SCOPE = 'compile_only_module_inputs'
MODULE_FIELDS = {'scope', 'source_sha', 'compiled_source_sha', 'module', 'module_sha256',
                 'moonc', 'source_inputs_sha256', 'toolchain', 'generated_abi',
                 'moon_home', 'compiler', 'link_response', 'link_inputs', 'link_output'}


def _original(path: Path, maximum: int) -> dict[str, Any]:
    require(path.is_absolute(), 'Select an absolute original module input')
    require(stat.S_ISREG(path.lstat().st_mode), 'Module input must be an original regular file')
    size = path.stat().st_size
    raw = _read_file(path, maximum=maximum, expected=size)
    return {'path': str(path), 'bytes': size, 'sha256': hashlib.sha256(raw).hexdigest()}


def _source_inputs(root: Path, source: str) -> str:
    require(type(source) is str and len(source) == 40
            and all(c in '0123456789abcdef' for c in source), 'Invalid original module source')
    selected = ['src', 'moon.mod', 'toolchain.json', 'scripts/generate-local-wasm-abi.py',
                'packages/python-sdk/src/actql_sdk/_local_wasm_abi.py']
    listing = subprocess.check_output(['git', 'ls-tree', '-rz', source, '--', *selected], cwd=root)
    require(bool(listing), 'Original module source membership is unavailable')
    records = []
    for entry in listing.split(b'\0')[:-1]:
        identity, raw_path = entry.split(b'\t', 1)
        mode, kind, blob = identity.decode('ascii').split()
        require(kind == 'blob' and mode in ('100644', '100755'), 'Nonregular module source member')
        path = raw_path.decode('utf-8')
        selected_path = root / path
        if selected_path.lstat().st_size == 0:
            # Empty source members are valid. Component _read_file deliberately
            # requires nonempty artifacts, so inspect only this zero-byte case
            # with the same no-follow/regular/stable-FD boundary, never an
            # unbounded Path.read_bytes fallback.
            with os.fdopen(os.open(selected_path, os.O_RDONLY | os.O_NOFOLLOW), 'rb') as selected_file:
                before = os.fstat(selected_file.fileno())
                require(stat.S_ISREG(before.st_mode) and before.st_size == 0
                        and selected_file.read(1) == b'', 'Empty module source member changed')
                after = os.fstat(selected_file.fileno())
                require((before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
                        == (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns),
                        'Empty module source member changed')
                raw = b''
        else:
            raw = _read_file(selected_path, maximum=16 * 1024 * 1024)
        # Git identity is correspondence, not a new signing authority. Keep a
        # strong byte digest in the complete selected membership as well.
        actual = hashlib.sha1(b'blob ' + str(len(raw)).encode() + b'\0' + raw).hexdigest()
        require(actual == blob, 'Original module source member changed: ' + path)
        records.append([mode, blob, path, hashlib.sha256(raw).hexdigest()])
    return hashlib.sha256(json.dumps(records, ensure_ascii=False,
        separators=(',', ':')).encode()).hexdigest()


def _compiler_originals(root: Path, moon_home: Path, pin: dict[str, Any]) -> dict[str, Any]:
    require(moon_home.is_absolute(), 'Select the original pinned compiler directory')
    marker = json.loads(_read_file(moon_home / 'installed.json', maximum=65536), object_pairs_hook=_pairs)
    require(type(marker) is dict and set(marker) == {'pin', 'platform'}
            and marker['pin'] == pin and marker['platform'] in pin['archives'],
            'Original module compiler pin mismatch')
    commands = {'moon': [str(moon_home / 'bin/moon'), 'version'],
                'moonc': [str(moon_home / 'bin/moonc'), '-v']}
    result = {name: _original(Path(command[0]), 128 * 1024 * 1024)
              for name, command in commands.items()}
    for name, command in commands.items():
        observed = subprocess.check_output(command, cwd=root, text=True, timeout=10).strip().splitlines()
        require(bool(observed) and observed[0] == ('moon ' if name == 'moon' else '') + pin[name],
                'Original module pinned compiler version mismatch')
    result['installed'] = _original(moon_home / 'installed.json', 65536)
    return result


def record_original_module(root: Path, source: str, compiled_source: str, module: Path,
                           link_response: Path, moon_home: Path) -> dict[str, Any]:
    """Inspect actual compiler inputs; no physical/Runtime/Run acceptance.

    The normal caller retains its genuine build result and original compiled
    source. Hashing inputs is not a compiler read trace. Input-equivalent reuse
    keeps that source explicitly, rather than relabelling an old build.
    """
    require(subprocess.check_output(['git', 'status', '--porcelain'], cwd=root) == b'',
            'Use committed clean module producer source')
    require(subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=root, text=True).strip() == source,
            'Original module must belong to the exact producer source')
    membership = _source_inputs(root, source)
    require(_source_inputs(root, compiled_source) == membership,
            'Original compiled module source inputs differ')
    pin = json.loads(_read_file(root / 'toolchain.json', maximum=65536), object_pairs_hook=_pairs)
    compiler = _compiler_originals(root, moon_home, pin)
    declaration = root / 'packages/python-sdk/src/actql_sdk/_local_wasm_abi.py'
    generator_path = root / 'scripts/generate-local-wasm-abi.py'
    generator_spec = importlib.util.spec_from_file_location('original_module_abi', generator_path)
    require(generator_spec is not None and generator_spec.loader is not None,
            'Original generated ABI is unavailable')
    assert generator_spec is not None and generator_spec.loader is not None
    generator = importlib.util.module_from_spec(generator_spec)
    generator_spec.loader.exec_module(generator)
    require(_read_file(declaration, maximum=1024 * 1024) == generator.render(root).encode(),
            'Original generated module ABI is stale')
    response = _original(link_response, 128 * 1024)
    args = shlex.split(_read_file(link_response, maximum=128 * 1024).decode())
    require(bool(args) and args[0] == 'link-core', 'Select the actual module link response')
    start = next((i for i in range(1, len(args)) if args[i].startswith('-')), len(args))
    inputs = args[1:start]
    require(bool(inputs) and len(inputs) <= 4096 and len(set(inputs)) == len(inputs)
            and all(Path(value).is_absolute() and value.endswith('.core') for value in inputs),
            'Invalid original module link inputs')
    def option(name: str) -> str:
        require(args.count(name) == 1 and args.index(name) + 1 < len(args),
                'Invalid original module link option: ' + name)
        return args[args.index(name) + 1]
    require(option('-target') == 'wasm' and option('-memory-limits-max') == '256',
            'Original module link target or memory limit differs')
    output = Path(option('-o'))
    original = _original(module, 32 * 1024 * 1024)
    linked = _original(output, 32 * 1024 * 1024)
    require(original['sha256'] == linked['sha256'] and original['bytes'] == linked['bytes'],
            'Retained original module differs from actual link output')
    require(_read_file(module, maximum=32 * 1024 * 1024, prefix=8) == b'\0asm\x01\0\0\0',
            'Original module binary header differs')
    result = {'scope': MODULE_SCOPE, 'source_sha': source, 'compiled_source_sha': compiled_source,
        'module': str(module), 'module_sha256': original['sha256'], 'moonc': pin['moonc'],
        'source_inputs_sha256': membership, 'moon_home': str(moon_home), 'compiler': compiler,
        'toolchain': _original(root / 'toolchain.json', 65536),
        'generated_abi': [_original(generator_path, 1024 * 1024), _original(declaration, 1024 * 1024)],
        'link_response': response, 'link_inputs': [_original(Path(value), 64 * 1024 * 1024)
                                                for value in inputs], 'link_output': linked}
    require(len(json.dumps(result, indent=2).encode()) <= 65536, 'Original module receipt exceeds its envelope')
    return result


def verify_original_module(root: Path, original: dict[str, Any], source: str) -> str:
    require(set(original) == MODULE_FIELDS and original['scope'] == MODULE_SCOPE,
            'Select the closed compile-only module original')
    require(original['source_sha'] == source, 'Module original does not belong to exact producer source')
    component(Path(original['module']), original['module_sha256'],
              32 * 1024 * 1024, 'client_host_wasm.wasm')
    actual = record_original_module(root, source, original['compiled_source_sha'],
        Path(original['module']), Path(original['link_response']['path']), Path(original['moon_home']))
    require(original == actual, 'Original module/compiler/ABI/link inputs changed')
    return cast(str, actual['module_sha256'])


def physical_core_cohort(selected: _SelectedImageRecipe, image_sha256: str) -> dict[str, str]:
    """Closed execution correspondence DATA, never admission or a cleanup ACK."""
    require(type(image_sha256) is str and len(image_sha256) == 64
            and all(c in '0123456789abcdef' for c in image_sha256),
            'Original selected-image physical cohort is unavailable')
    selected.validate()
    provider_digest, _ = selected.owned_provider()
    return {'execution_kind': 'selected_precompiled_image',
        'module_sha256': selected.module_sha256, 'image_sha256': image_sha256,
        'engine_sha256': hashlib.sha256(selected.engine_body).hexdigest(),
        'runtime_library_sha256': selected.runtime_library_sha256,
        'provider_library_sha256': provider_digest}


def verify_original_core(root: Path, core: dict[str, Any], source: str) -> str:
    require(set(core) == {'source_sha', 'module', 'module_sha256', 'scope', 'moonc', 'python',
                         'result', 'physical', 'workspace', 'positive_native_result_acceptance',
                         'public_local_acceptance', 'module_original', 'contract'},
            'Select the original physical-boundary Core receipt')
    require(core['source_sha'] == source,
            'Physical receipts must belong to this exact producer source')
    require(core['scope'] == 'physical_buffer_bridge_workspace_only'
            and core['positive_native_result_acceptance'] is False
            and core['public_local_acceptance'] is False,
            'Core physical receipt is not public Local acceptance')
    pins = json.loads((root / 'toolchain.json').read_bytes())
    require(core['moonc'] == pins['moonc'], 'Core receipt does not use the pinned compiler')
    digest = core['module_sha256']
    require(type(digest) is str and len(digest) == 64
            and all(c in '0123456789abcdef' for c in digest), 'Invalid original module digest')
    for name in ('result', 'physical', 'workspace'):
        value = core[name]
        require(type(value) is dict and value.get('success') is True
                and value.get('module_sha256') == digest
                and type(value.get('cases')) is list and bool(value['cases']),
                'Core physical receipt did not confirm the same module')
    contract = core['contract']
    require(type(contract) is dict and contract.get('success') is True
            and contract.get('module_sha256') == digest
            and type(contract.get('cases')) is list and bool(contract['cases']),
            'Core contract receipt did not confirm the same module with nonzero cases')
    cohort = contract.get('cohort')
    require(type(cohort) is dict, 'Original selected-image physical cohort is unavailable')
    original_recipe = recipe.module_image_recipe_original(root, source, Path(core['module']), digest)
    selected = _recipe_from_original(original_recipe, source_sha=source,
        package_version=recipe.read_cohort(root), module_sha256=digest)
    expected = physical_core_cohort(selected, cohort.get('image_sha256'))
    for name in ('contract', 'result', 'physical', 'workspace'):
        require(core[name].get('cohort') == expected,
                'Core physical observation did not execute the same selected image cohort')
    original = core['module_original']
    require(type(original) is dict and verify_original_module(root, original, source) == digest
            and original['module'] == core['module'], 'Core physical receipt module original differs')
    return cast(str, digest)


def verify_original_image(image: dict[str, Any], selected: _SelectedImageRecipe, source: str,
                          digest: str) -> tuple[Path, dict[str, object]]:
    """Verify image DATA only; physical admission remains an independent input.

    The final producer and private physical preparation use the same closed
    original fields, recipe, bytes and binary-target checks. This does not load
    a DLL, issue final components or accept a compiler receipt as physical work.
    """
    fields = {'source_sha', 'module_sha256', 'core_abi', 'wasmtime_version',
        'runtime_library_sha256', 'provider_library_sha256', 'engine_sha256', 'image', 'image_sha256',
        'compiled', 'runtime_executed', 'public_local_acceptance'}
    require(set(image) == fields | ({'runtime_allocation'} if selected.runtime_allocation == 'platform' else set()),
        'Select the original compiled-image production receipt')
    engine_hash = hashlib.sha256(selected.engine_body).hexdigest()
    require(image['source_sha'] == source and image['module_sha256'] == digest
        and type(image['core_abi']) is int and image['core_abi'] == LOCAL_CORE_ABI
        and image['wasmtime_version'] == WASMTIME_VERSION
        and image['runtime_library_sha256'] == selected.runtime_library_sha256
        and image['provider_library_sha256'] == selected.provider_library_sha256
        and image.get('runtime_allocation', 'native-owned') == selected.runtime_allocation
        and image['engine_sha256'] == engine_hash and image['compiled'] is True
        and image['runtime_executed'] is False and image['public_local_acceptance'] is False,
        'Compiled image receipt does not match the selected original recipe')
    require(type(image['image']) is str and Path(image['image']).is_absolute(),
            'Original compiled image path is unavailable')
    image_path = Path(image['image'])
    image_item = component(image_path, image['image_sha256'], selected.image_bytes_limit,
                           'client_host_wasm.cwasm')
    image_size, image_hash = cast(int, image_item['bytes']), cast(str, image_item['sha256'])
    header = _read_file(image_path, maximum=selected.image_bytes_limit,
                        expected=image_size, digest=image_hash, prefix=20)
    require(_valid_image_header(header, image_size), 'Incompatible original image binary target')
    return image_path, image_item


def produce_platform(core_receipt: Path, duckdb_receipt: Path,
                     image_receipt: Path, destination: Path) -> dict[str, object]:
    """Prepare ordinary components, never relabel a private physical receipt.

    The actual module/compiler/link and image belong to this exact source.
    The unchanged standalone DuckDB library keeps its original receipt/source;
    packaging does not promote that execution to this Host or a public Run.
    """
    source = clean_source()
    core, core_hash = read_receipt(core_receipt)
    digest = verify_original_module(ROOT, core, source)
    image, image_hash = read_receipt(image_receipt)
    duckdb, duckdb_hash = read_receipt(duckdb_receipt)
    require(set(duckdb) == {'source_sha', 'library', 'library_sha256', 'library_version',
        'python', 'platform', 'machine', 'tests', 'success', 'module_source',
        'workspace_selection', 'public_local_acceptance', 'wheel_acceptance'},
        'Select the original standalone DuckDB component receipt')
    require(duckdb['success'] is True and type(duckdb['tests']) is int and duckdb['tests'] == 20
        and duckdb['machine'] == 'arm64' and duckdb['module_source'] is None
        and duckdb['workspace_selection'] is False and duckdb['public_local_acceptance'] is False
        and duckdb['wheel_acceptance'] is False and duckdb['library_version'] == DUCKDB_VERSION,
        'Standalone DuckDB original component does not match')
    original = recipe.module_image_recipe_original(ROOT, source, Path(core['module']), digest,
        runtime_allocation='platform')
    version = recipe.read_cohort(ROOT)
    selected = _recipe_from_original(original, source_sha=source,
        package_version=version, module_sha256=digest)
    image_path, image_item = verify_original_image(image, selected, source, digest)
    module, library = Path(core['module']), Path(duckdb['library'])
    recipe_hash = hashlib.sha256(original).hexdigest()
    image_body = {'source_sha': source, 'package_version': version,
        'module_sha256': digest, 'core_abi': LOCAL_CORE_ABI,
        'wasmtime_version': WASMTIME_VERSION, 'runtime_allocation': 'platform',
        'runtime_library_sha256': selected.runtime_library_sha256,
        'provider_library_sha256': None, 'platform': 'darwin-arm64',
        'engine_body': json.loads(selected.engine_body),
        'engine_sha256': hashlib.sha256(selected.engine_body).hexdigest(), **image_item}
    notices = recipe.notice_originals()
    notice_hashes = {name: hashlib.sha256(_read_file(path, maximum=1024 * 1024)).hexdigest()
                     for name, path in notices.items()}
    body = {'source_sha': source, 'package_version': version, 'platform': 'darwin-arm64',
        'core_abi': LOCAL_CORE_ABI, 'wasmtime_version': WASMTIME_VERSION,
        'module': component(module, digest, 32 * 1024 * 1024, 'client_host_wasm.wasm'),
        'duckdb': component(library, duckdb['library_sha256'], 128 * 1024 * 1024, 'libduckdb.dylib'),
        'duckdb_version': DUCKDB_VERSION, 'notices': notice_hashes,
        'compiled_image': image_body,
        'engine_recipe': {'file': 'engine-recipe.json', 'bytes': len(original), 'sha256': recipe_hash}}
    recipe.library_target(library)
    destination.mkdir()
    copies = {'client_host_wasm.wasm': (module, 32 * 1024 * 1024, digest),
        'client_host_wasm.cwasm': (image_path, selected.image_bytes_limit, image_item['sha256']),
        'libduckdb.dylib': (library, 128 * 1024 * 1024, duckdb['library_sha256'])}
    copies.update({name: (path, 1024 * 1024, notice_hashes[name]) for name, path in notices.items()})
    for name, (path, maximum, checksum) in copies.items():
        copy_original(path, destination / name, maximum, checksum)
    (destination / 'engine-recipe.json').write_bytes(original)
    wire = (json.dumps(body, indent=2) + '\n').encode('utf-8')
    require(len(wire) <= 65536, 'Ordinary component manifest exceeds its limit')
    (destination / 'artifact.json').write_bytes(wire)
    recipe.verify_artifact(destination)
    require(clean_source() == source and read_receipt(core_receipt)[1] == core_hash
        and read_receipt(duckdb_receipt)[1] == duckdb_hash
        and read_receipt(image_receipt)[1] == image_hash,
        'Ordinary component inputs changed during preparation')
    result: dict[str, object] = {'scope': 'ordinary_platform_components_only',
        'source_sha': source, 'package_version': version, 'core_abi': LOCAL_CORE_ABI,
        'artifact_sha256': hashlib.sha256(wire).hexdigest(),
        'core_receipt_sha256': core_hash, 'image_receipt_sha256': image_hash,
        'duckdb_receipt_sha256': duckdb_hash, 'duckdb_execution_source': duckdb['source_sha'],
        'artifact': body, 'runtime_executed': False, 'wheel_built': False,
        'public_local_accepted': False}
    (destination / 'producer.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def produce(core_receipt: Path, duckdb_receipt: Path, image_receipt: Path, destination: Path) -> dict[str, object]:
    source = clean_source()
    core, core_hash = read_receipt(core_receipt)
    duckdb, duckdb_hash = read_receipt(duckdb_receipt)
    image, image_receipt_hash = read_receipt(image_receipt)
    digest = verify_original_core(ROOT, core, source)
    require(duckdb.get('source_sha') == source, 'Physical receipts must belong to this exact producer source')
    require(set(duckdb) == {'source_sha', 'library', 'library_sha256', 'library_version',
                           'python', 'platform', 'machine', 'tests', 'success', 'module_source',
                           'workspace_selection', 'public_local_acceptance', 'wheel_acceptance'},
            'Select the original standalone DuckDB physical receipt')
    version = 'v' + json.loads((ROOT / 'vendor/duckdb/1.4.3/manifest.json').read_bytes())['version']
    require(duckdb['success'] is True and type(duckdb['tests']) is int and duckdb['tests'] == 20
            and duckdb['machine'] == 'arm64' and type(duckdb['platform']) is str
            and duckdb['platform'].startswith('macOS-') and duckdb['module_source'] is None
            and duckdb['workspace_selection'] is False
            and duckdb['public_local_acceptance'] is False and duckdb['wheel_acceptance'] is False
            and duckdb['library_version'] == version,
            'Standalone DuckDB receipt does not confirm the selected physical profile')
    require(sys.platform == 'darwin' and platform.machine() == 'arm64',
            'Python Local producer requires the selected darwin-arm64 platform')
    require(type(core['module']) is str and type(duckdb['library']) is str,
            'Original component paths are unavailable')
    module, library = Path(core['module']), Path(duckdb['library'])
    require(module.is_absolute() and library.is_absolute(), 'Select absolute original component paths')
    sdk = tomllib.loads((ROOT / 'packages/python-sdk/pyproject.toml').read_text())['project']
    require(recipe.read_cohort(ROOT) == sdk['version'], 'Python packages must form one fixed release cohort')
    # This source-original is deliberately unavailable until the selected
    # recipe is reviewed/adopted. Never fill missing limits from a fixture,
    # Wasmtime defaults, or the image receipt supplied on the command line.
    original = recipe.module_image_recipe_original(ROOT, source, module, digest)
    selected = _recipe_from_original(original, source_sha=source,
        package_version=sdk['version'], module_sha256=digest)
    image_path, image_item = verify_original_image(image, selected, source, digest)
    require(core['contract']['cohort'] == physical_core_cohort(selected, cast(str, image_item['sha256'])),
            'Core physical observations differ from the original compiled image')
    engine_hash = hashlib.sha256(selected.engine_body).hexdigest()
    image_body = {'source_sha': source, 'package_version': sdk['version'],
        'module_sha256': digest, 'core_abi': LOCAL_CORE_ABI,
        'wasmtime_version': WASMTIME_VERSION,
        'runtime_library_sha256': selected.runtime_library_sha256,
        'provider_library_sha256': selected.provider_library_sha256,
        'platform': 'darwin-arm64', 'engine_body': json.loads(selected.engine_body),
        'engine_sha256': engine_hash, **image_item}
    body = {'source_sha': source, 'package_version': sdk['version'], 'platform': 'darwin-arm64',
            'core_abi': LOCAL_CORE_ABI, 'wasmtime_version': WASMTIME_VERSION,
            'module': component(module, digest, 32 * 1024 * 1024, 'client_host_wasm.wasm'),
            'duckdb': component(library, duckdb['library_sha256'], 128 * 1024 * 1024, 'libduckdb.dylib'),
            'duckdb_version': version, 'notices': {}, 'compiled_image': image_body,
            'engine_recipe': {'file': 'engine-recipe.json', 'bytes': len(original),
                              'sha256': hashlib.sha256(original).hexdigest()}}
    notices = recipe.notice_originals()
    notice_hashes = {name: hashlib.sha256(_read_file(path, maximum=1024 * 1024)).hexdigest()
                     for name, path in notices.items()}
    body['notices'] = notice_hashes
    recipe.library_target(library)
    destination.mkdir()
    for name, path in {'client_host_wasm.wasm': module, 'client_host_wasm.cwasm': image_path,
                       'libduckdb.dylib': library, **notices}.items():
        maximum = selected.image_bytes_limit if name == 'client_host_wasm.cwasm' else (
            32 * 1024 * 1024 if name == 'client_host_wasm.wasm' else (
            128 * 1024 * 1024 if name == 'libduckdb.dylib' else 1024 * 1024))
        expected = image['image_sha256'] if name == 'client_host_wasm.cwasm' else (
            digest if name == 'client_host_wasm.wasm' else (
            duckdb['library_sha256'] if name == 'libduckdb.dylib' else notice_hashes[name]))
        copy_original(path, destination / name, maximum, expected)
    (destination / 'engine-recipe.json').write_bytes(original)
    wire = (json.dumps(body, indent=2) + '\n').encode('utf-8')
    require(len(wire) <= 65536, 'Python Local artifact metadata exceeds its fixed envelope')
    (destination / 'artifact.json').write_bytes(wire)
    # Reuse the same consumer/recipe checks, including copied target and notices.
    recipe.verify_artifact(destination)
    require(clean_source() == source, 'Producer source changed during component copying')
    require(read_receipt(core_receipt)[1] == core_hash
            and read_receipt(duckdb_receipt)[1] == duckdb_hash,
            'Original physical receipt changed during production')
    require(read_receipt(image_receipt)[1] == image_receipt_hash,
            'Original image receipt changed during production')
    result: dict[str, object] = {
        'source_sha': source, 'package_version': sdk['version'], 'core_abi': LOCAL_CORE_ABI,
        'artifact_sha256': hashlib.sha256(wire).hexdigest(),
        'toolchain_pin_sha256': hashlib.sha256((ROOT / 'toolchain.json').read_bytes()).hexdigest(),
        'core_receipt_sha256': core_hash, 'duckdb_receipt_sha256': duckdb_hash,
        'image_receipt_sha256': image_receipt_hash,
        'artifact': body, 'runtime_executed': False, 'wheel_built': False,
        'public_local_accepted': False,
    }
    (destination / 'producer.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-receipt', type=Path)
    parser.add_argument('--duckdb-receipt', type=Path)
    parser.add_argument('--image-receipt', type=Path)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--record-module-original', action='store_true')
    parser.add_argument('--platform-runtime', action='store_true')
    parser.add_argument('--source')
    parser.add_argument('--compiled-source')
    parser.add_argument('--module', type=Path)
    parser.add_argument('--link-response', type=Path)
    parser.add_argument('--moon-home', type=Path)
    args = parser.parse_args()
    if args.record_module_original:
        if args.platform_runtime:
            parser.error('Module correspondence does not select a runtime')
        if (not all((args.source, args.compiled_source, args.module, args.link_response, args.moon_home))
                or any((args.core_receipt, args.duckdb_receipt, args.image_receipt))):
            parser.error('Select only the exact source/module/compiler/link originals')
        record = record_original_module(ROOT, args.source, args.compiled_source,
                                        args.module, args.link_response, args.moon_home)
        wire = json.dumps(record, indent=2) + '\n'
        try:
            with args.destination.open('x') as output:
                output.write(wire)
        except FileExistsError:
            previous, _ = read_receipt(args.destination)
            require(previous == record, 'Do not replace an existing original module receipt')
        print(json.dumps({'scope': record['scope'], 'source_sha': record['source_sha'],
            'compiled_source_sha': record['compiled_source_sha'], 'module_sha256': record['module_sha256'],
            'physical_acceptance': False, 'runtime_executed': False, 'public_local_acceptance': False}))
    else:
        if (not all((args.core_receipt, args.duckdb_receipt, args.image_receipt))
                or any((args.source, args.compiled_source, args.module, args.link_response, args.moon_home))):
            parser.error('Select all three original physical/component receipts')
        selected_producer = produce_platform if args.platform_runtime else produce
        print(json.dumps(selected_producer(args.core_receipt, args.duckdb_receipt,
            args.image_receipt, args.destination)))
