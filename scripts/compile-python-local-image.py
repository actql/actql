"""Compile one selected source-original image; no instance, Run, wheel or publication.

Actual compilation requires an original physical holding from the trusted
maintainer supplier. This is not an installed user action or loader fallback.
"""
from __future__ import annotations

import argparse
from ctypes import CDLL, byref, c_ubyte, c_void_p
import hashlib
from importlib import import_module, metadata
import importlib.util
import json
import os
import platform
from pathlib import Path
import subprocess
import sys
from typing import Any, NamedTuple

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
sys.path.insert(0, str(ROOT / 'scripts'))
from python_release_cohort import read_cohort  # noqa: E402
from actql_sdk._local_core import _validate_core_module  # noqa: E402
from actql_sdk._local_wasm_abi import LOCAL_CORE_ABI  # noqa: E402
from actql_sdk._local_distribution import WASMTIME_VERSION, _read_file  # noqa: E402
from actql_sdk._local_engine import _configure_selected_engine, _verify_selected_provider_link  # noqa: E402
from actql_sdk._local_image_recipe import _recipe_from_original  # noqa: E402
from actql_sdk._local_native_holding import _NativeHoldingLease  # noqa: E402
from actql_sdk._local_native_memory_abi import bind as bind_memory  # noqa: E402
from actql_sdk._local_distribution import _closed, _pairs  # noqa: E402

spec = importlib.util.spec_from_file_location('image_component_assembly', ROOT / 'scripts/produce-python-local-runtime.py')
if spec is None or spec.loader is None:
    raise ValueError('Original image component assembly is unavailable')
assembly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembly)


class _CompilerHoldingOriginal(NamedTuple):
    """One source-bound maintainer input; never product funding or a grant."""

    source_sha: str
    module_sha256: str
    engine_sha256: str
    runtime_library_sha256: str
    provider_library_sha256: str
    capacity_bytes: int
    generation: int
    recipe: bytes


def _compiler_holding_original(original: dict[str, Any]) -> _CompilerHoldingOriginal:
    raw = assembly.recipe._source_original(ROOT, original['source'],
        'packages/python-local-runtime/selected-compiler-holding.json',
        'Selected source-original compiler holding')
    body = _closed(json.loads(raw, object_pairs_hook=_pairs), (
        'scope', 'module_sha256', 'engine_sha256', 'runtime_library_sha256',
        'provider_library_sha256', 'capacity_bytes', 'generation'))
    recipe = original['recipe']
    page = os.sysconf('SC_PAGE_SIZE')
    if (body['scope'] != 'image_compiler_only'
            or body['module_sha256'] != original['module_sha256']
            or body['engine_sha256'] != hashlib.sha256(recipe.engine_body).hexdigest()
            or body['runtime_library_sha256'] != recipe.runtime_library_sha256
            or body['provider_library_sha256'] != recipe.provider_library_sha256
            or type(body['capacity_bytes']) is not int
            or not 0 < body['capacity_bytes'] <= 2**63 - 1
            or page <= 0 or body['capacity_bytes'] % page != 0
            or type(body['generation']) is not int or not 0 < body['generation'] <= 2**64 - 1):
        raise ValueError('Compiler holding differs from its source/module/recipe original')
    return _CompilerHoldingOriginal(original['source'], body['module_sha256'],
        body['engine_sha256'], body['runtime_library_sha256'], body['provider_library_sha256'],
        body['capacity_bytes'], body['generation'], hashlib.sha256(raw).digest())


class CompilerHoldingAcquisitionError(RuntimeError):
    """Retain the same provider/out-slot; no replay or inferred close ACK.

    A known refusal with an empty slot remains a refusal. A lost reply,
    nonempty failed slot or inconsistent successful reply is unconfirmed.
    This carrier does not mint a holding from an uncertain observation.
    """

    def __init__(self, library: CDLL, slot: c_void_p,
                 original: _CompilerHoldingOriginal, code: int | None, *,
                 attempted: bool = True, holding: _NativeHoldingLease | None = None) -> None:
        self.library, self.slot, self.original, self.code = library, slot, original, code
        self.attempted, self.holding = attempted, holding
        self.refused = slot.value is None and (not attempted or (type(code) is int and code != 0))
        super().__init__('Original compiler holding acquisition refused' if self.refused
                         else 'Original compiler holding acquisition is unconfirmed')


def _acquire_compiler_holding(original: dict[str, Any],
                             selected: _CompilerHoldingOriginal) -> _NativeHoldingLease:
    """Physically acquire only this compiler extent through the same provider.

    The declaration is not the backing. Config/import/Engine work remains
    unavailable until the real C acquire has confirmed a nonempty original
    slot and the existing holding has consumed it. Provider loading belongs
    to the separate trusted maintainer control envelope, not this extent.
    """
    recipe = original['recipe']
    if (type(selected) is not _CompilerHoldingOriginal
            or selected.source_sha != original['source']
            or selected.module_sha256 != original['module_sha256']
            or selected.engine_sha256 != hashlib.sha256(recipe.engine_body).hexdigest()
            or selected.runtime_library_sha256 != recipe.runtime_library_sha256
            or selected.provider_library_sha256 != recipe.provider_library_sha256
            or selected != _compiler_holding_original(original)):
        raise ValueError('Compiler holding original belongs to another selected compilation')
    provider = original['provider_library']
    _read_file(provider, maximum=recipe.provider_library_bytes,
               expected=recipe.provider_library_bytes, digest=recipe.provider_library_sha256)
    library = CDLL(str(provider))
    slot = c_void_p()
    try:
        _read_file(provider, maximum=recipe.provider_library_bytes,
                   expected=recipe.provider_library_bytes, digest=recipe.provider_library_sha256)
        acquire = bind_memory(library, 'actql_native_owned_acquire')
    except BaseException as primary:
        raise CompilerHoldingAcquisitionError(library, slot, selected, None,
                                              attempted=False) from primary
    fingerprint = (c_ubyte * 32).from_buffer_copy(selected.recipe)
    try:
        code = acquire(selected.capacity_bytes, selected.generation, fingerprint, byref(slot))
    except BaseException as primary:
        raise CompilerHoldingAcquisitionError(library, slot, selected, None) from primary
    if type(code) is not int or code != 0 or slot.value is None:
        raise CompilerHoldingAcquisitionError(library, slot, selected,
                                             code if type(code) is int else None)
    # Retain the object before its existing Owner initializer moves the slot.
    # Even an exception immediately after that move keeps this same object;
    # neither the old address nor a cleared out-slot permits another acquire.
    holding = _NativeHoldingLease.__new__(_NativeHoldingLease)
    try:
        holding._initialize_original(slot, library, selected.generation,
                                     selected.recipe, 'actql_native_owned_')
    except BaseException as primary:
        raise CompilerHoldingAcquisitionError(library, slot, selected, code,
                                              holding=holding) from primary
    return holding


def verify(core_receipt: Path, expected_source: str) -> dict[str, Any]:
    if subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT):
        raise ValueError('Compile the image from committed clean source')
    source = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if source != expected_source:
        raise ValueError('Selected image compiler source changed')
    if sys.platform != 'darwin' or platform.machine() != 'arm64':
        raise ValueError('Image compiler requires the selected darwin-arm64 profile')
    core, receipt_hash = assembly.read_receipt(core_receipt)
    if core.get('scope') == assembly.MODULE_SCOPE:
        digest = assembly.verify_original_module(ROOT, core, source)
    else:
        digest = assembly.verify_original_core(ROOT, core, source)
    module = Path(core['module'])
    if not module.is_absolute():
        raise ValueError('Original image compiler module path is unavailable')
    assembly.component(module, digest, 32 * 1024 * 1024, 'client_host_wasm.wasm')
    version = read_cohort(ROOT)
    original = assembly.recipe.image_recipe_original(ROOT, source)
    recipe = _recipe_from_original(original, source_sha=source,
                                   package_version=version, module_sha256=digest)
    distribution = metadata.distribution('wasmtime')
    if distribution.version != WASMTIME_VERSION:
        raise ValueError('Image compiler Wasmtime version mismatch')
    # resources.files('wasmtime') imports its package and therefore the DLL
    # loader. Preflight must remain metadata/file-only before the original
    # compiler holding has entered its scope.
    runtime = distribution.locate_file('wasmtime')
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

    def compile_selected() -> bytes | bytearray:
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
        if not isinstance(encoded, (bytes, bytearray)) or not 0 < len(encoded) <= recipe.image_bytes_limit:
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


def compile_from_original(core_receipt: Path, expected_source: str,
                          destination: Path) -> dict[str, object]:
    """Maintainer-only CLI composition; no normal factory or runtime fallback."""
    original = verify(core_receipt, expected_source)
    if destination.exists():
        raise ValueError('Image compiler destination already exists')
    selected = _compiler_holding_original(original)
    holding = _acquire_compiler_holding(original, selected)
    try:
        if holding._capacity_bytes() != selected.capacity_bytes:
            raise ValueError('Physical compiler holding does not match its original extent')
        return compile_image(core_receipt, expected_source, destination, _holding=holding)
    except ImageCompilerCleanupError:
        # The existing carrier retains this same holding and every uncertain
        # handle. Do not retry its scope, handle close or physical retirement.
        raise
    except BaseException as primary:
        try:
            # Covers a changed second preflight or destination before the
            # compiler has taken custody. Already confirmed close is a no-op
            # in the existing holding; an uncertain close stays sticky there.
            holding.close()
        except BaseException as cleanup:
            raise ImageCompilerCleanupError(_CompilerCustody(holding), primary) from cleanup
        raise


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
        print(json.dumps(compile_from_original(args.core_receipt, args.source, args.destination)))
