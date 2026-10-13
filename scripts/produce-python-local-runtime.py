"""Assemble fixed Python Local components from original physical receipts.

This maintainer producer does not compile, load an engine, build a wheel,
execute a Run, publish, or grant authority. Consumers only install wheels.
"""
from __future__ import annotations

import argparse
import hashlib
import importlib.util
import json
from pathlib import Path
import platform
import stat
import subprocess
import sys
import tomllib
from typing import Any, cast

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
from actql_sdk._local_core import LOCAL_CORE_ABI  # noqa: E402
from actql_sdk._local_distribution import WASMTIME_VERSION, _pairs, _read_file  # noqa: E402

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


def produce(core_receipt: Path, duckdb_receipt: Path, destination: Path) -> dict[str, object]:
    source = clean_source()
    core, core_hash = read_receipt(core_receipt)
    duckdb, duckdb_hash = read_receipt(duckdb_receipt)
    require(set(core) == {'source_sha', 'module', 'module_sha256', 'scope', 'moonc', 'python',
                         'result', 'physical', 'workspace', 'positive_native_result_acceptance',
                         'public_local_acceptance'}, 'Select the original physical-boundary Core receipt')
    require(core['source_sha'] == source and duckdb.get('source_sha') == source,
            'Physical receipts must belong to this exact producer source')
    require(core['scope'] == 'physical_buffer_bridge_workspace_only'
            and core['positive_native_result_acceptance'] is False
            and core['public_local_acceptance'] is False,
            'Core physical receipt is not public Local acceptance')
    pins = json.loads((ROOT / 'toolchain.json').read_bytes())
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
    body = {'source_sha': source, 'package_version': sdk['version'], 'platform': 'darwin-arm64',
            'core_abi': LOCAL_CORE_ABI, 'wasmtime_version': WASMTIME_VERSION,
            'module': component(module, digest, 32 * 1024 * 1024, 'client_host_wasm.wasm'),
            'duckdb': component(library, duckdb['library_sha256'], 128 * 1024 * 1024, 'libduckdb.dylib'),
            'duckdb_version': version, 'notices': {}}
    notices = recipe.notice_originals()
    notice_hashes = {name: hashlib.sha256(_read_file(path, maximum=1024 * 1024)).hexdigest()
                     for name, path in notices.items()}
    body['notices'] = notice_hashes
    recipe.library_target(library)
    destination.mkdir()
    for name, path in {'client_host_wasm.wasm': module, 'libduckdb.dylib': library, **notices}.items():
        maximum = 32 * 1024 * 1024 if name == 'client_host_wasm.wasm' else (
            128 * 1024 * 1024 if name == 'libduckdb.dylib' else 1024 * 1024)
        expected = digest if name == 'client_host_wasm.wasm' else (
            duckdb['library_sha256'] if name == 'libduckdb.dylib' else notice_hashes[name])
        copy_original(path, destination / name, maximum, expected)
    wire = (json.dumps(body, indent=2) + '\n').encode('utf-8')
    require(len(wire) <= 65536, 'Python Local artifact metadata exceeds its fixed envelope')
    (destination / 'artifact.json').write_bytes(wire)
    # Reuse the same consumer/recipe checks, including copied target and notices.
    recipe.verify_artifact(destination)
    require(clean_source() == source, 'Producer source changed during component copying')
    require(read_receipt(core_receipt)[1] == core_hash
            and read_receipt(duckdb_receipt)[1] == duckdb_hash,
            'Original physical receipt changed during production')
    result: dict[str, object] = {
        'source_sha': source, 'package_version': sdk['version'], 'core_abi': LOCAL_CORE_ABI,
        'artifact_sha256': hashlib.sha256(wire).hexdigest(),
        'toolchain_pin_sha256': hashlib.sha256((ROOT / 'toolchain.json').read_bytes()).hexdigest(),
        'core_receipt_sha256': core_hash, 'duckdb_receipt_sha256': duckdb_hash,
        'artifact': body, 'runtime_executed': False, 'wheel_built': False,
        'public_local_accepted': False,
    }
    (destination / 'producer.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--core-receipt', type=Path, required=True)
    parser.add_argument('--duckdb-receipt', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(produce(args.core_receipt, args.duckdb_receipt, args.destination)))
