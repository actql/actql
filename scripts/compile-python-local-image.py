"""Compile one selected source-original image; no instance, Run, wheel or publication.

Actual compilation requires the coordinator's fixed-source finite lane. This
script is not an installed user action and never runs as a loader fallback.
"""
from __future__ import annotations

import argparse
import hashlib
from importlib import import_module, metadata, resources
import importlib.util
import json
import platform
from pathlib import Path
import subprocess
import sys
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
sys.path.insert(0, str(ROOT / 'scripts'))
from python_release_cohort import read_cohort  # noqa: E402
from actql_sdk._local_core import LOCAL_CORE_ABI, _validate_core_module  # noqa: E402
from actql_sdk._local_distribution import WASMTIME_VERSION, _read_file  # noqa: E402
from actql_sdk._local_engine import _configure_selected_engine  # noqa: E402
from actql_sdk._local_image_recipe import _recipe_from_original  # noqa: E402

spec = importlib.util.spec_from_file_location('image_component_assembly', ROOT / 'scripts/produce-python-local-runtime.py')
if spec is None or spec.loader is None:
    raise ValueError('Original image component assembly is unavailable')
assembly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembly)


def verify(core_receipt: Path, expected_source: str) -> dict[str, Any]:
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT):
        raise ValueError('Compile the image from committed clean source')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if source != expected_source:
        raise ValueError('Selected image compiler source changed')
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise ValueError('Image compiler requires the selected darwin-arm64 profile')
    core, receipt_hash = assembly.read_receipt(core_receipt)
    digest = assembly.verify_original_core(ROOT, core, source)
    module = Path(core['module'])
    if not module.is_absolute():
        raise ValueError('Original image compiler module path is unavailable')
    assembly.component(module, digest, 32 * 1024 * 1024, 'client_host_wasm.wasm')
    version = read_cohort(ROOT)
    original = assembly.recipe.image_recipe_original(ROOT, source)
    recipe = _recipe_from_original(original, source_sha=source,
                                   package_version=version, module_sha256=digest)
    if metadata.version('wasmtime') != WASMTIME_VERSION:
        raise ValueError('Image compiler Wasmtime version mismatch')
    runtime = resources.files('wasmtime')
    if not isinstance(runtime, Path):
        raise ValueError('Image compiler requires an ordinary installed Wasmtime wheel')
    library = runtime / 'darwin-aarch64/_libwasmtime.dylib'
    _read_file(library, maximum=recipe.runtime_library_bytes,
               expected=recipe.runtime_library_bytes, digest=recipe.runtime_library_sha256)
    return {'source': source, 'module': module, 'module_sha256': digest,
        'core_receipt_sha256': receipt_hash, 'recipe': recipe, 'runtime_library': library}


def compile_image(core_receipt: Path, expected_source: str, destination: Path) -> dict[str, object]:
    original = verify(core_receipt, expected_source)
    if destination.exists():
        raise ValueError('Image compiler destination already exists')
    recipe = original['recipe']
    wasm = _read_file(original['module'], maximum=32 * 1024 * 1024,
                     digest=original['module_sha256'], capture=True)
    wasmtime = import_module('wasmtime')
    ffi = import_module('wasmtime._ffi')
    library = original['runtime_library']
    if Path(ffi.filename) != library or Path(ffi.dll._name) != library:
        raise ValueError('Image compiler loaded a different runtime library')
    _read_file(library, maximum=recipe.runtime_library_bytes,
               expected=recipe.runtime_library_bytes, digest=recipe.runtime_library_sha256)
    config = pool = engine = module = None
    try:
        config = wasmtime.Config()
        pool = ffi.wasmtime_pooling_allocation_config_new()
        if not pool:
            raise ValueError('Original image compiler pooling configuration is unavailable')
        _configure_selected_engine(config, pool, ffi, wasmtime, recipe)
        ffi.wasmtime_pooling_allocation_config_delete(pool)
        pool = None
        engine = wasmtime.Engine(config)
        config = None
        module = wasmtime.Module(engine, wasm)
        _validate_core_module(wasmtime, module)
        encoded = module.serialize()
        if not 0 < len(encoded) <= recipe.image_bytes_limit:
            raise ValueError('Compiled image exceeds the selected original file envelope')
        # No Wasm instance or Store is created. Signature validation and
        # serialization are not execution, admission or product acceptance.
    finally:
        for value in (module, engine, config):
            if value is not None:
                value.close()
        if pool is not None:
            ffi.wasmtime_pooling_allocation_config_delete(pool)
    final = verify(core_receipt, expected_source)
    if (final['core_receipt_sha256'] != original['core_receipt_sha256']
            or final['recipe'] != recipe):
        raise ValueError('Original image compiler materials changed')
    destination.mkdir()
    image = destination / 'client_host_wasm.cwasm'
    with image.open('xb') as output:
        output.write(encoded)
    image_hash = hashlib.sha256(encoded).hexdigest()
    _read_file(image, maximum=recipe.image_bytes_limit, expected=len(encoded), digest=image_hash)
    result: dict[str, object] = {'source_sha': expected_source,
        'module_sha256': original['module_sha256'], 'core_abi': LOCAL_CORE_ABI,
        'wasmtime_version': WASMTIME_VERSION,
        'runtime_library_sha256': recipe.runtime_library_sha256,
        'engine_sha256': hashlib.sha256(recipe.engine_body).hexdigest(),
        'image': str(image.resolve()), 'image_sha256': image_hash,
        'compiled': True, 'runtime_executed': False, 'public_local_acceptance': False}
    (destination / 'image-receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--core-receipt', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--verify-only', action='store_true')
    mode.add_argument('--compile', action='store_true')
    args = parser.parse_args()
    if args.verify_only:
        checked = verify(args.core_receipt, args.source)
        print(json.dumps({'source_sha': args.source, 'module_sha256': checked['module_sha256'],
            'engine_sha256': hashlib.sha256(checked['recipe'].engine_body).hexdigest(),
            'image_bytes_limit': checked['recipe'].image_bytes_limit,
            'native_engine_started': False, 'compiled': False, 'public_local_acceptance': False}))
    else:
        print(json.dumps(compile_image(args.core_receipt, args.source, args.destination)))
