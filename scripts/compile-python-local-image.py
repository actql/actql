"""Compile one selected source-original image; no instance, Run, wheel or publication.

Actual compilation requires an original physical holding from the trusted
maintainer supplier. This is not an installed user action or loader fallback.
"""
from __future__ import annotations

import argparse
from ctypes import CDLL
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
from actql_sdk._local_engine import _configure_selected_engine, _verify_selected_provider_link  # noqa: E402
from actql_sdk._local_image_recipe import _recipe_from_original  # noqa: E402
from actql_sdk._local_native_holding import _NativeHoldingLease  # noqa: E402

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
    provider = library.parent / 'libactql_native_control.dylib'
    _read_file(provider, maximum=recipe.provider_library_bytes,
               expected=recipe.provider_library_bytes, digest=recipe.provider_library_sha256)
    return {'source': source, 'module': module, 'module_sha256': digest,
        'core_receipt_sha256': receipt_hash, 'recipe': recipe, 'runtime_library': library,
        'provider_library': provider}


class ImageCompilerCleanupError(RuntimeError):
    """Same original handles/holding remain pending; never compilation success."""

    def __init__(self, cleanup: _CompilerCustody, primary: BaseException | None) -> None:
        self.cleanup_compilation, self.primary = cleanup, primary
        super().__init__('Original image compiler cleanup is failed or unconfirmed')


class _CompilerCustody:
    """Maintainer call lifetime only; no Core identity, Run, quota or supplier.

    The original supplier has already acquired the holding. A lost native
    handle-close or scope return is sticky: keeping its Python reference is
    not an acknowledgment and does not permit replay of that foreign call.
    """

    def __init__(self, holding: _NativeHoldingLease) -> None:
        self.holding = holding
        self.ffi: Any = None
        self.config: Any = None
        self.pool: Any = None
        self.engine: Any = None
        self.module: Any = None
        self._unknown: BaseException | None = None
        self._closed = False

    def scoped(self, operation: Any) -> Any:
        if self._unknown is not None:
            raise self._unknown
        scope = self.holding._scope()
        try:
            scope.__enter__()
        except BaseException as error:
            self._unknown = error
            raise
        try:
            result = operation()
        except BaseException:
            try:
                scope.__exit__(*sys.exc_info())
            except BaseException as error:
                self._unknown = error
                raise
            raise
        else:
            try:
                scope.__exit__(None, None, None)
            except BaseException as error:
                self._unknown = error
                raise
            return result

    def close_pool(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if self.pool is not None:
            try:
                self.ffi.wasmtime_pooling_allocation_config_delete(self.pool)
            except BaseException as error:
                self._unknown = error
                raise
            self.pool = None

    def _close_handles(self) -> None:
        for name in ('module', 'engine', 'config'):
            value = getattr(self, name)
            if value is not None:
                try:
                    value.close()
                except BaseException as error:
                    self._unknown = error
                    raise
                setattr(self, name, None)
        self.close_pool()

    def close(self) -> None:
        if self._closed:
            return
        if self._unknown is not None:
            raise self._unknown
        if any(value is not None for value in (self.module, self.engine, self.config, self.pool)):
            self.scoped(self._close_handles)
        # Once all handles and scope leave are confirmed, a known retirement
        # refusal retries only this same holding, without reentering its TLS.
        self.holding.close()
        self._closed = True


def _verify_compiler_holding(original: dict[str, Any], holding: _NativeHoldingLease | None) -> None:
    if (type(holding) is not _NativeHoldingLease or holding._pointer.value is None
            or holding._core_identity is not None or holding._transfer_attempted
            or holding._borrow is not None):
        raise ValueError('Select an unbound original native compiler holding')
    holding._require_confirmed_retirement_state()
    provider = holding._library
    if (not isinstance(provider, CDLL) or type(provider._name) is not str
            or Path(provider._name) != original['provider_library']):
        raise ValueError('Original compiler holding uses a different selected provider')


def compile_image(core_receipt: Path, expected_source: str, destination: Path, *,
                  _holding: _NativeHoldingLease | None = None) -> dict[str, object]:
    original = verify(core_receipt, expected_source)
    if destination.exists():
        raise ValueError('Image compiler destination already exists')
    _verify_compiler_holding(original, _holding)
    assert _holding is not None
    recipe = original['recipe']
    wasm = _read_file(original['module'], maximum=32 * 1024 * 1024,
                     digest=original['module_sha256'], capture=True)
    custody = _CompilerCustody(_holding)

    def compile_selected() -> bytes:
        wasmtime = import_module('wasmtime')
        ffi = import_module('wasmtime._ffi')
        custody.ffi = ffi
        library = original['runtime_library']
        if Path(ffi.filename) != library or Path(ffi.dll._name) != library:
            raise ValueError('Image compiler loaded a different runtime library')
        _verify_selected_provider_link(recipe, library, ffi.dll, _holding._library)
        custody.config = wasmtime.Config()
        custody.pool = ffi.wasmtime_pooling_allocation_config_new()
        if not custody.pool:
            raise ValueError('Original image compiler pooling configuration is unavailable')
        _configure_selected_engine(custody.config, custody.pool, ffi, wasmtime, recipe)
        custody.close_pool()
        custody.engine = wasmtime.Engine(custody.config)
        custody.config = None
        custody.module = wasmtime.Module(custody.engine, wasm)
        _validate_core_module(wasmtime, custody.module)
        encoded = custody.module.serialize()
        if not 0 < len(encoded) <= recipe.image_bytes_limit:
            raise ValueError('Compiled image exceeds the selected original file envelope')
        # No Wasm instance or Store is created. Signature validation and
        # serialization are not execution, admission or product acceptance.
        return encoded

    primary: BaseException | None = None
    try:
        encoded = custody.scoped(compile_selected)
    except BaseException as error:
        primary = error
    try:
        custody.close()
    except BaseException as cleanup_error:
        raise ImageCompilerCleanupError(custody, primary) from cleanup_error
    if primary is not None:
        raise primary
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
        'provider_library_sha256': recipe.provider_library_sha256,
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
