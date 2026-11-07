"""Compile one selected source-original image; no instance, Run, wheel or publication.

Actual compilation requires an original physical holding from the trusted
maintainer supplier. This is not an installed user action or loader fallback.
"""
from __future__ import annotations

import argparse
from ctypes import CDLL, byref, c_ubyte, c_void_p
import hashlib
from importlib import import_module
import importlib.util
import json
import math
import os
import platform
import stat
from pathlib import Path
import subprocess
import sys
import time
from threading import current_thread
from typing import Any, NamedTuple, cast

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'packages/python-sdk/src'))
sys.path.insert(0, str(ROOT / 'scripts'))
from python_release_cohort import read_cohort  # noqa: E402
from actql_sdk._local_core import _validate_core_module  # noqa: E402
from actql_sdk._local_wasm_abi import LOCAL_CORE_ABI  # noqa: E402
from actql_sdk._local_distribution import WASMTIME_VERSION, _read_file  # noqa: E402
from actql_sdk._local_engine import (  # noqa: E402
    _configure_selected_engine, _selected_engine_settings, _verify_selected_provider_link,
)
from actql_sdk._local_image_recipe import _SelectedImageRecipe, _recipe_from_original  # noqa: E402
from actql_sdk._local_native_holding import _NativeHoldingLease  # noqa: E402
from actql_sdk._local_native_memory_abi import bind as bind_memory  # noqa: E402
from actql_sdk._local_distribution import _closed, _pairs  # noqa: E402
from actql_sdk._local_native_control_custody import _OriginalControlCustody, _OriginalControlFunctions  # noqa: E402
from actql_sdk._local_native_backing_custody import _OriginalBackingCustody, _OriginalBackingFunctions  # noqa: E402
from actql_sdk._local_native_domain_custody import (  # noqa: E402
    _OriginalDomainCustody, _OriginalDomainFunctions, _OriginalDomainMaterialFunctions,
)
from actql_sdk._local_native_process_custody import (  # noqa: E402
    _OriginalInstalledProcessCustody, _OriginalInstalledProcessFunctions,
    _OriginalInstalledProcessError,
)
from actql_sdk._local_native_shim_abi import bind as bind_native  # noqa: E402
from actql_sdk._local_worker_slot import _OriginalDescriptor  # noqa: E402

spec = importlib.util.spec_from_file_location('image_component_assembly', ROOT / 'scripts/produce-python-local-runtime.py')
if spec is None or spec.loader is None:
    raise ValueError('Original image component assembly is unavailable')
assembly = importlib.util.module_from_spec(spec)
spec.loader.exec_module(assembly)


def _compiler_configuration_header(recipe: _SelectedImageRecipe) -> bytes:
    """Project the existing validated Engine Owner into one C preparation.

    The caller must already own both native objects in its original scope.
    Returned errors and both objects remain the caller's custody. No Engine,
    module, instance, funding or physical acceptance is issued here.
    """
    settings = _selected_engine_settings(recipe)
    provider_digest, _ = recipe.owned_provider()
    lines = [
        '/* Generated from the original validated Python Engine Owner. */',
        '#ifndef ACTQL_COMPILER_CONFIGURATION_GENERATED_H',
        '#define ACTQL_COMPILER_CONFIGURATION_GENERATED_H',
        '#include <wasmtime.h>',
    ]
    lines.append(f'#define ACTQL_COMPILER_SOURCE_SHA "{recipe.source_sha}"')
    if recipe.image_bytes_limit > 2**63 - 1:
        raise ValueError('Original image bound is not representable by the selected C compiler')
    lines.append(f'#define ACTQL_COMPILER_IMAGE_MAX_BYTES {recipe.image_bytes_limit}ULL')
    for name, digest in (('MODULE', recipe.module_sha256),
                        ('RUNTIME', recipe.runtime_library_sha256),
                        ('PROVIDER', provider_digest),
                        ('ENGINE', hashlib.sha256(recipe.engine_body).hexdigest())):
        lines.append(f'#define ACTQL_COMPILER_{name}_SHA256 "{digest}"')
    lines += ['static inline wasmtime_error_t *actql_compiler_configure(',
              '    wasm_config_t *config, wasmtime_pooling_allocation_config_t *pool) {']
    for domain, name, value in settings:
        if name == 'strategy':
            # The original validator admits only Cranelift. Use the selected
            # official header enum, not an independently assumed numeric ABI.
            literal = 'WASMTIME_STRATEGY_CRANELIFT'
        elif type(value) is bool:
            literal = 'true' if value else 'false'
        elif type(value) is int:
            literal = str(value) + 'ULL'
        else:
            literal = json.dumps(value, ensure_ascii=True)
        prefix = 'wasmtime_config_' if domain == 'config' else 'wasmtime_pooling_allocation_config_'
        call = f'{prefix}{name}_set({domain}, {literal})'
        if name == 'target':
            lines += [f'    wasmtime_error_t *error = {call};', '    if (error != NULL) return error;']
        else:
            lines.append(f'    {call};')
    lines += ['    wasmtime_pooling_allocation_strategy_set(config, pool);',
              '    return NULL;', '}', '#endif', '']
    return '\n'.join(lines).encode('ascii')


def prepare_compiler_configuration(core_receipt: Path, expected_source: str,
                                   destination: Path) -> dict[str, object]:
    """Same original-module verifier, with no native loading or execution."""
    original = verify(core_receipt, expected_source)
    header = _compiler_configuration_header(original['recipe'])
    if (not destination.is_absolute() or destination.exists() or destination.is_symlink()
            or destination.resolve() != destination):
        raise ValueError('Select a fresh canonical compiler configuration directory')
    destination.mkdir()
    (destination / 'compiler_configuration.generated.h').write_bytes(header)
    result = {'scope': 'original_compiler_configuration_only',
        'source_sha': expected_source, 'module_sha256': original['module_sha256'],
        'core_receipt_sha256': original['core_receipt_sha256'],
        'header_sha256': hashlib.sha256(header).hexdigest(),
        'engine_sha256': hashlib.sha256(original['recipe'].engine_body).hexdigest(),
        'native_engine_started': False, 'compiled': False, 'physical_acceptance': False}
    (destination / 'configuration-receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


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


class _InitialCompilerDomainOriginal(NamedTuple):
    """Closed source selection of non-byte limits, not a quota or extent."""

    work: int
    attempts: int
    holdings: int
    transfer: int


class _CompilerParentOriginal(NamedTuple):
    """Source-bound maintainer selection, not a Ledger or worker permit."""

    holding: _CompilerHoldingOriginal
    parent: tuple[int, ...]
    child: tuple[int, ...] | _InitialCompilerDomainOriginal
    recipe: bytes


def _compiler_parent_original(original: dict[str, Any],
                              selected: _CompilerHoldingOriginal) -> _CompilerParentOriginal:
    if type(selected) is not _CompilerHoldingOriginal or selected != _compiler_holding_original(original):
        raise ValueError('Foreign original compiler selection')
    raw = assembly.recipe._source_original(ROOT, original['source'],
        'packages/python-local-runtime/selected-compiler-parent.json',
        'Selected source-original compiler parent')
    body = _closed(json.loads(raw, object_pairs_hook=_pairs),
                   ('scope', 'holding_sha256', 'parent', 'child'))
    parent = _closed(body['parent'], ('bytes', 'work', 'attempts', 'holdings',
                                     'transfer', 'retained', 'execution', 'control_envelope'))
    initial = type(body['child']) is dict and 'kind' in body['child']
    if initial:
        child = _closed(body['child'], ('kind', 'work', 'attempts', 'holdings', 'transfer'))
        if child['kind'] != 'initial_execution_domain':
            raise ValueError('Unknown source-original compiler child selection')
        child_numbers = tuple(child[k] for k in ('work', 'attempts', 'holdings', 'transfer'))
    else:
        child = _closed(body['child'], ('bytes', 'work', 'attempts', 'holdings',
                                       'transfer', 'retained', 'execution'))
        child_numbers = tuple(child.values())
    if (body['scope'] != 'image_compiler_parent_only'
            or body['holding_sha256'] != selected.recipe.hex()
            or selected.generation > 2**63 - 1
            or parent['bytes'] != selected.capacity_bytes
            or any(type(n) is not int or not 0 <= n <= 2**63 - 1
                   for n in (*parent.values(), *child_numbers))
            or any(n > 2**31 - 1 for n in (parent['work'], parent['attempts'], parent['holdings'],
                                           child['work'], child['attempts'], child['holdings']))
            or parent['bytes'] <= 0 or parent['execution'] != parent['bytes']
            or parent['retained'] != 0 or parent['control_envelope'] <= 0
            or (not initial and (child['bytes'] <= 0 or child['bytes'] > parent['bytes']))):
        raise ValueError('Compiler parent differs from its source-original envelope')
    # Adequacy, quota/delegation and physical page rounding remain Native
    # decisions. There is deliberately no default profile or inferred grant.
    fields = ('bytes', 'work', 'attempts', 'holdings', 'transfer', 'retained', 'execution')
    child_original = (_InitialCompilerDomainOriginal(*(child[k] for k in ('work', 'attempts', 'holdings', 'transfer')))
                      if initial else tuple(child[k] for k in fields))
    return _CompilerParentOriginal(selected, tuple(parent[k] for k in (*fields, 'control_envelope')),
                                    child_original, hashlib.sha256(raw).digest())


class CompilerParentAcquisitionError(RuntimeError):
    """Same Native partial originals and borrowed FD; never another acquire."""

    def __init__(self, parent: _CompilerParent) -> None:
        self.cleanup_parent = parent
        super().__init__('Original compiler parent acquisition is pending')


class CompilerControlInitializationError(RuntimeError):
    """Keep the same selected component and original initialization slot.

    This carrier never unloads, repeats initialization or claims process
    retirement. The existing process/runtime responsibility outlives arenas.
    """

    def __init__(self, runtime: _CompilerControlRuntime) -> None:
        self.cleanup_runtime = runtime
        super().__init__('Original compiler control initialization is unavailable or unconfirmed')


class _CompilerControlRuntime:
    """Thin original process record, not another resource or permission Owner."""

    def __init__(self, original: _CompilerHoldingOriginal) -> None:
        self.original = original
        self.library: Any = None
        self.slot = c_void_p()
        self._process, self._thread = os.getpid(), current_thread()
        self._current: Any = None
        self._initialized = False
        self._unknown: CompilerControlInitializationError | None = None
        self.failure = CompilerControlInitializationError(self)

    def __copy__(self) -> _CompilerControlRuntime:
        raise TypeError('Original compiler control cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _CompilerControlRuntime:
        raise TypeError('Original compiler control cannot be copied')

    def __reduce__(self) -> Any:
        raise TypeError('Original compiler control cannot be serialized')

    def current(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if (os.getpid() != self._process or current_thread() is not self._thread
                or not self._initialized):
            raise ValueError('Original compiler control process/thread is unavailable')
        try:
            code = self._current(self.slot)
            if type(code) is not int or code != 0:
                raise self.failure
        except BaseException as primary:
            self._unknown = self.failure
            raise self.failure from primary


def _prepare_compiler_control(original: dict[str, Any],
                              selected: _CompilerHoldingOriginal) -> _CompilerControlRuntime:
    """One same-component initializer within the trusted control envelope.

    This is neither arena funding nor a loader fallback. Native publishes its
    process-lifetime original before invoking its own emitted initializer.
    Every failure keeps this carrier, including a loaded library without a
    confirmed initialization reply. Nothing here issues or closes a Ledger.
    """
    if type(selected) is not _CompilerHoldingOriginal or selected != _compiler_holding_original(original):
        raise ValueError('Foreign original compiler control selection')
    recipe = original['recipe']
    provider = original['provider_library']
    _read_file(provider, maximum=recipe.provider_library_bytes,
               expected=recipe.provider_library_bytes, digest=recipe.provider_library_sha256)
    runtime = _CompilerControlRuntime(selected)
    try:
        runtime.library = CDLL(str(provider))
        _read_file(provider, maximum=recipe.provider_library_bytes,
                   expected=recipe.provider_library_bytes, digest=recipe.provider_library_sha256)
        initialize = bind_native(runtime.library, 'actql_control_runtime_initialize_into')
        runtime._current = bind_native(runtime.library, 'actql_control_runtime_current')
        code = initialize(byref(runtime.slot))
        if type(code) is not int or code != 0 or runtime.slot.value is None:
            raise runtime.failure
        runtime._initialized = True
        runtime.current()
        return runtime
    except BaseException as primary:
        runtime._unknown = runtime.failure
        raise runtime.failure from primary


class _CompilerParent:
    """Private assembly of existing Native owners, not OriginalWorkerFunding.

    Process preparation uses this same domain and its original child budget.
    It does not fund independent DLL/loader/Python/VM domains. Native keeps the
    actual child/delegation and process/descriptor/region confirmations.
    """

    def __init__(self, original: _CompilerParentOriginal, runtime: _CompilerControlRuntime,
                 descriptor: _OriginalDescriptor) -> None:
        self.original, self.runtime, self.descriptor = original, runtime, descriptor
        self.library = runtime.library
        self.host: _OriginalControlCustody | None = None
        self.backing: _OriginalBackingCustody | None = None
        self.domain: _OriginalDomainCustody | None = None
        self._closed = False
        self.failure = CompilerParentAcquisitionError(self)

    def __copy__(self) -> _CompilerParent:
        raise TypeError('Original compiler parent cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _CompilerParent:
        raise TypeError('Original compiler parent cannot be copied')

    def __reduce__(self) -> Any:
        raise TypeError('Original compiler parent cannot be serialized')

    def prepare_process(self, *, path: str, nonce: int) -> _OriginalInstalledProcessCustody:
        """Bind the selected child to its original Native process Owner.

        No caller-supplied quota, reconstructed Ledger or separate POSIX owner
        is introduced. The existing domain registers partial process custody
        before the first foreign call. A lost reply retains it on this parent.
        """
        domain = self.domain
        if (self._closed or type(domain) is not _OriginalDomainCustody
                or domain._owner is not self.host or domain._scope is not self.backing
                or domain._descriptor is not self.descriptor
                or domain._functions.library is not self.library):
            raise ValueError('Original compiler parent domain is unavailable')
        for carrier in (self.host, self.backing, domain):
            if carrier._unknown is not None:
                raise carrier._unknown
        if self.host._busy:
            raise ValueError('Original compiler parent is busy')
        self.runtime.current()
        functions = _OriginalInstalledProcessFunctions(self.library)
        child = self.original.child
        if type(child) is _InitialCompilerDomainOriginal:
            # This projection comes from the same live original domain now,
            # not from a guessed ratio, previous DATA snapshot or new Ledger.
            material = domain._project_original_material(_OriginalDomainMaterialFunctions(self.library))
            if (material.source != self.original.holding.source_sha
                    or material.recipe != self.original.recipe):
                raise ValueError('Original compiler domain material changed')
            retained, execution = material.scalars[13:15]
        else:
            retained, execution = child[5:7]
        try:
            return _OriginalInstalledProcessCustody._prepare_original(domain, functions,
                path=path, nonce=nonce, retained=retained, execution=execution)
        except _OriginalInstalledProcessError as primary:
            # The same domain already holds the original process, including a
            # partial/Unknown reply. Do not replay preparation or release its
            # backing when reporting this parent-level assembly failure.
            raise self.failure from primary

    def close_unstarted(self) -> None:
        """Retire only after any original process has confirmed its cleanup.

        Known pending retries stay in the existing Native owners. Lost replies
        remain sticky there. FD is borrowed: this assembly never closes it.
        """
        if self._closed:
            return
        for carrier in (self.host, self.backing, self.domain):
            if carrier is not None and carrier._unknown is not None:
                raise carrier._unknown
        if (self.domain is not None and (self.domain._worker_process_original is not None
                or self.domain._installed_process_original is not None)):
            raise ValueError('Original compiler domain still has process custody')
        self.runtime.current()
        if self.backing is not None:
            self.backing.return_after_stop()
        if self.domain is not None:
            self.domain.close_after_stop()
        if self.host is not None:
            self.host.close()
        self._closed = True


def _acquire_compiler_parent(original: dict[str, Any], selected: _CompilerHoldingOriginal,
                             descriptor: _OriginalDescriptor) -> _CompilerParent:
    """Connect trusted compiler preparation to real Native bootstrap/domain.

    The matching component initializes once in its original process custody.
    The Native bootstrap creates/reserves the original Ledger before acquiring
    this actual FD backing. Python neither exposes it nor creates a substitute.
    Missing declaration/new private ABI refuses before physical acquisition.
    """
    declaration = _compiler_parent_original(original, selected)
    if (type(descriptor) is not _OriginalDescriptor or descriptor._original is not descriptor
            or descriptor.closed or descriptor.close_attempted
            or type(descriptor.value) is not int or not 0 <= descriptor.value <= 2**31 - 1):
        raise ValueError('Original compiler backing descriptor is unavailable')
    opened = os.fstat(descriptor.value)
    if not stat.S_ISREG(opened.st_mode) or opened.st_size != declaration.parent[0]:
        raise ValueError('Original compiler descriptor differs from its selected backing')
    runtime = _prepare_compiler_control(original, selected)
    parent = _CompilerParent(declaration, runtime, descriptor)
    size, work, attempts, holdings, transfer, retained, execution, envelope = declaration.parent
    try:
        runtime.current()
        control = _OriginalControlFunctions(parent.library)
        backing = _OriginalBackingFunctions(parent.library)
        domain = _OriginalDomainFunctions(parent.library)
        if type(declaration.child) is _InitialCompilerDomainOriginal:
            # Check selected transport availability before the first Host/FD
            # acquisition; exporting a symbol still supplies no funding.
            bind_native(parent.library, 'actql_domain_prepare_initial_into')
        parent.host = _OriginalControlCustody._prepare_original(control,
            source=selected.source_sha, recipe=declaration.recipe, generation=selected.generation,
            size=size, work=work, attempts=attempts, holdings=holdings, transfer=transfer,
            retained=retained, execution=execution, envelope=envelope)
        parent.host.acquire_fd(descriptor)
        parent.host.current()
        current = os.fstat(descriptor.value)
        if (current.st_dev, current.st_ino, current.st_size) != (opened.st_dev, opened.st_ino, opened.st_size):
            raise ValueError('Original compiler descriptor changed during acquisition')
        parent.backing = _OriginalBackingCustody._borrow_original(parent.host, backing)
        child = declaration.child
        with parent.backing._physical_scope():
            if type(child) is _InitialCompilerDomainOriginal:
                parent.domain = _OriginalDomainCustody._prepare_initial_original(
                    parent.host, parent.backing, descriptor, domain, work=child.work,
                    attempts=child.attempts, holdings=child.holdings, transfer=child.transfer)
            else:
                size, work, attempts, holdings, transfer, retained, execution = child
                parent.domain = _OriginalDomainCustody._prepare_original(
                    parent.host, parent.backing, descriptor, domain, size=size, work=work,
                    attempts=attempts, holdings=holdings, transfer=transfer, retained=retained,
                    execution=execution)
        # Existing physical preparation is one-shot and precedes projecting
        # child material. It is neither process start nor a stop/cleanup ACK.
        # Store the same domain above before this foreign call can lose reply.
        parent.domain.transfer()
        parent.domain.current()
        return parent
    except BaseException as primary:
        # Every existing acquisition carrier must remain reachable even when
        # assignment was interrupted after the same Native out-slot changed.
        if parent.host is None:
            parent.host = getattr(primary, 'cleanup_host', None)
        if parent.backing is None:
            parent.backing = getattr(primary, 'cleanup_borrow', None)
        if parent.domain is None:
            parent.domain = getattr(primary, 'cleanup_domain', None)
        raise parent.failure from primary


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
            or any(type(value) is not str for value in selected[:5])
            or type(selected.capacity_bytes) is not int
            or type(selected.generation) is not int or type(selected.recipe) is not bytes
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


def verify(core_receipt: Path, expected_source: str, *,
           runtime_allocation: str = 'native-owned') -> dict[str, Any]:
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
    original = assembly.recipe.module_image_recipe_original(ROOT, source, module, digest,
        runtime_allocation=runtime_allocation)
    recipe = _recipe_from_original(original, source_sha=source,
                                   package_version=version, module_sha256=digest)
    return {'source': source, 'module': module, 'module_sha256': digest,
        'core_receipt_sha256': receipt_hash, 'recipe': recipe}


class _CompilerRuntime(NamedTuple):
    """Retained preparation bytes, not image/physical admission or funding."""

    source_sha: str
    recipe: _SelectedImageRecipe
    directory: Path
    files: tuple[tuple[str, int, str], ...]


def _runtime_files(directory: Path, recipe: _SelectedImageRecipe) -> tuple[tuple[str, int, str], ...]:
    """Snapshot/check only the output of the shared original staging routine."""
    provider_digest, provider_bytes = recipe.owned_provider()
    if (not directory.is_absolute() or directory.resolve() != directory
            or directory.is_symlink() or not directory.is_dir()):
        raise ValueError('Original compiler private runtime directory is unavailable')
    records: list[tuple[str, int, str]] = []
    for path in sorted(directory.rglob('*')):
        mode = path.lstat().st_mode
        if stat.S_ISDIR(mode):
            continue
        if not stat.S_ISREG(mode):
            raise ValueError('Compiler private runtime contains a nonregular member')
        name = path.relative_to(directory).as_posix()
        selected = {
            'actql_local_runtime/_wasmtime/darwin-aarch64/_libwasmtime.dylib':
                (recipe.runtime_library_bytes, recipe.runtime_library_sha256),
            'actql_local_runtime/_wasmtime/darwin-aarch64/libactql_native_control.dylib':
                (provider_bytes, provider_digest),
        }.get(name)
        if selected is not None:
            size, digest = selected
            _read_file(path, maximum=size, expected=size, digest=digest)
        else:
            raw = _read_file(path, maximum=2 * 1024 * 1024)
            size, digest = len(raw), hashlib.sha256(raw).hexdigest()
        records.append((name, size, digest))
    return tuple(records)


def prepare_compiler_runtime(original: dict[str, Any], bindings_source: Path,
                             native_libraries: Path, destination: Path) -> _CompilerRuntime:
    """Same private product source/DLL preparation, before any native import.

    The caller retains this fresh directory on every outcome. It must not be
    an automatic temporary cleanup while native aliases or an original holding
    may remain. No LocalComponents/image/physical success is synthesized.
    """
    if not destination.is_absolute() or destination.exists() or destination.is_symlink():
        raise ValueError('Select a fresh absolute compiler preparation directory')
    destination = destination.resolve()
    if destination.exists():
        raise ValueError('Compiler preparation already exists at its canonical path')
    original_init = assembly.recipe._source_original(ROOT, original['source'],
        'packages/python-local-runtime/src/actql_local_runtime/__init__.py',
        'Original private runtime package')
    destination.mkdir()
    package = destination / 'actql_local_runtime'
    package.mkdir()
    (package / '__init__.py').write_bytes(original_init)
    assembly.recipe.stage_selected_private_runtime(original['recipe'], bindings_source,
                                                   native_libraries, package)
    return _CompilerRuntime(original['source'], original['recipe'], destination,
                            _runtime_files(destination, original['recipe']))


class _PhysicalCoreInputs:
    """Verified preparation DATA, not components, parent funding or authority.

    The actual Native parent/domain admission remains an independent mandatory
    input to the physical caller. No preparation can issue an instance, acquire
    a replacement holding or satisfy the final component verifier by itself.
    """

    _original: _PhysicalCoreInputs
    _core_receipt: Path
    _image_receipt: Path
    _source: str
    _module_sha256: str
    _module_receipt_hash: str
    _image_receipt_hash: str
    _image_path: Path
    _image_bytes: int
    _image_sha256: str
    _runtime: _CompilerRuntime

    def __init__(self) -> None:
        raise TypeError('Physical Core inputs require original preparation')

    @classmethod
    def prepare(cls, core_receipt: Path, image_receipt: Path, expected_source: str,
                *, scope: str, bindings_source: Path, native_libraries: Path,
                destination: Path) -> _PhysicalCoreInputs:
        if scope != 'physical_core_conformance_only':
            raise ValueError('Select the closed private physical Core verifier scope')
        if any(not path.is_absolute() for path in (core_receipt, image_receipt)):
            raise ValueError('Select absolute original physical Core receipts')
        original = verify(core_receipt, expected_source)
        image, image_receipt_hash = assembly.read_receipt(image_receipt)
        image_path, item = assembly.verify_original_image(image, original['recipe'],
            original['source'], original['module_sha256'])
        # Shared ordinary source, ABI, two-library, target, license and actual
        # link-input preparation. No native import or final component is used.
        runtime = prepare_compiler_runtime(original, bindings_source, native_libraries, destination)
        value = cls.__new__(cls)
        value._original = value
        value._core_receipt, value._image_receipt = core_receipt, image_receipt
        value._source = expected_source
        value._module_sha256 = original['module_sha256']
        value._module_receipt_hash = original['core_receipt_sha256']
        value._image_receipt_hash = image_receipt_hash
        value._image_path = image_path
        value._image_bytes, value._image_sha256 = cast(int, item['bytes']), cast(str, item['sha256'])
        value._runtime = runtime
        value.require_current()
        return value

    def __copy__(self) -> _PhysicalCoreInputs:
        raise TypeError('Original physical Core preparation cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _PhysicalCoreInputs:
        raise TypeError('Original physical Core preparation cannot be copied')

    def __reduce__(self) -> Any:
        raise TypeError('Original physical Core preparation cannot be serialized')

    def require_current(self) -> dict[str, Any]:
        if self._original is not self:
            raise ValueError('Foreign physical Core preparation')
        original = verify(self._core_receipt, self._source)
        image, receipt_hash = assembly.read_receipt(self._image_receipt)
        path, item = assembly.verify_original_image(image, original['recipe'],
            original['source'], original['module_sha256'])
        if (original['core_receipt_sha256'] != self._module_receipt_hash
                or original['module_sha256'] != self._module_sha256
                or receipt_hash != self._image_receipt_hash
                or (path, item['bytes'], item['sha256']) !=
                   (self._image_path, self._image_bytes, self._image_sha256)):
            raise ValueError('Original physical Core inputs changed')
        return _runtime_original(original, self._runtime)


    def bind_original_process(self, process: _OriginalInstalledProcessCustody) -> _OriginalInstalledProcessCustody:
        """Retain preparation on the actual same Native process, never launch.

        Its existing domain/channel/frame/current remains the only physical
        authority. This consumes neither another domain nor another Ledger.
        It supplies no missing pre-root funding and cannot authorize Config,
        image capture or a scalar-open fallback.
        """
        self._require_original_process(process, bound=False)
        original = self.require_current()
        _verify_physical_process_provider(original, process)
        # Retain the exact DATA before a current/projection reply can be lost.
        # The same original process remains its pending/partial cleanup carrier.
        process._preparation_original = self
        self.require_bound_original_process(process)
        return process

    def _require_original_process(self, process: _OriginalInstalledProcessCustody, *, bound: bool) -> None:
        if type(process) is not _OriginalInstalledProcessCustody:
            raise ValueError('Select the actual original Native process')
        if process._unknown is not None:
            raise process._unknown
        domain, owner = process._domain, process._owner
        if domain._unknown is not None:
            raise domain._unknown
        if (self._original is not self or process._closed or domain._closed
                or domain._installed_process_original is not process
                or domain._owner is not owner or owner._closed or owner._busy
                or process._functions.library is not domain._functions.library
                or process._functions.library is not owner._functions.library
                or domain._descriptor.closed or domain._descriptor.close_attempted
                or process._host.value != domain._host.value
                or process._native_domain.value != domain._domain.value
                or any(slot.value is None for slot in (process._host, process._native_domain,
                                                       process._process, process._channel, process._frame))
                or process._reply.value is not None
                or (process._preparation_original is not self if bound
                    else process._preparation_original is not None)):
            raise ValueError('Original physical preparation process is unavailable or already bound')

    def require_bound_original_process(self, process: _OriginalInstalledProcessCustody) -> None:
        self._require_original_process(process, bound=True)
        original = self.require_current()
        _verify_physical_process_provider(original, process)
        process.current()
        material = process._domain._project_original_material(
            _OriginalDomainMaterialFunctions(process._functions.library))
        if material.source != self._source:
            raise ValueError('Original physical preparation domain source changed')
        process.current()
        self._require_original_process(process, bound=True)


def _verify_physical_process_provider(original: dict[str, Any],
                                      process: _OriginalInstalledProcessCustody) -> None:
    provider = process._functions.library
    if (not isinstance(provider, CDLL) or type(provider._name) is not str
            or Path(provider._name) != original['provider_library']):
        raise ValueError('Original physical process uses a different selected provider')


def _runtime_original(original: dict[str, Any], prepared: _CompilerRuntime | None) -> dict[str, Any]:
    if (type(prepared) is not _CompilerRuntime or prepared.source_sha != original['source']
            or prepared.recipe != original['recipe']
            or prepared.files != _runtime_files(prepared.directory, prepared.recipe)):
        raise ValueError('Compiler private runtime differs from its original preparation')
    library = prepared.directory / 'actql_local_runtime/_wasmtime/darwin-aarch64/_libwasmtime.dylib'
    return {**original, 'runtime_library': library,
        'provider_library': library.parent / 'libactql_native_control.dylib',
        'private_runtime': prepared}


def _import_compiler_runtime(custody: _CompilerCustody, original: dict[str, Any]) -> tuple[Any, Any]:
    prepared = original['private_runtime']
    _runtime_original(original, prepared)
    if any(name == 'actql_local_runtime' or name.startswith('actql_local_runtime.')
           for name in sys.modules):
        raise ValueError('Compiler private runtime namespace is already loaded')
    before_path, before_bytecode = sys.path[:], sys.dont_write_bytecode
    try:
        sys.path.insert(0, str(prepared.directory))
        sys.dont_write_bytecode = True
        # This function runs only inside the same actual holding's scope.
        # A partial import may have loaded the DLL and captured its addresses.
        # Preserve its aliases and original holding rather than retry/import
        # replacement or guessing native retirement from sys.modules cleanup.
        try:
            runtime = import_module('actql_local_runtime._wasmtime')
            ffi = import_module('actql_local_runtime._wasmtime._ffi')
            _runtime_original(original, prepared)
            members = {name for name, _, _ in prepared.files}
            for name, module in sys.modules.copy().items():
                if name == 'actql_local_runtime' or name.startswith('actql_local_runtime.'):
                    filename = getattr(module, '__file__', None)
                    if (not isinstance(filename, str)
                            or not Path(filename).is_relative_to(prepared.directory)
                            or Path(filename).relative_to(prepared.directory).as_posix() not in members):
                        raise ValueError('Compiler imported a foreign private runtime member')
            return runtime, ffi
        except BaseException as error:
            custody._unknown = error
            raise
        finally:
            custody.runtime_modules = tuple(module for name, module in sys.modules.copy().items()
                if name == 'actql_local_runtime' or name.startswith('actql_local_runtime.'))
    finally:
        sys.path[:] = before_path
        sys.dont_write_bytecode = before_bytecode



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

    def __init__(self, holding: _NativeHoldingLease | None, *,
                 runtime_allocation: str = 'native-owned') -> None:
        if (runtime_allocation not in ('native-owned', 'platform')
                or (holding is None) != (runtime_allocation == 'platform')):
            raise ValueError('Compiler allocation selection does not match its original')
        self.holding = holding
        self.preparation: _CompilerRuntime | None = None
        self.runtime_modules: tuple[Any, ...] = ()
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
        if self.holding is None:
            return operation()
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
        if self.holding is not None:
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


def compile_platform_image(core_receipt: Path, expected_source: str,
                           destination: Path) -> dict[str, object]:
    """Prepare the ordinary image using the pinned platform runtime service.

    This creates real Config/pool/Engine/Module handles and closes them. It
    supplies no arena, worker, Run result or final installed acceptance.
    """
    from actql_sdk._local_engine import _platform_runtime_library
    original = verify(core_receipt, expected_source, runtime_allocation='platform')
    selected = original['recipe']
    if selected.runtime_allocation != 'platform' or destination.exists():
        raise ValueError('Select a fresh ordinary platform image preparation')
    library = _platform_runtime_library(selected)
    wasm = _read_file(original['module'], maximum=32 * 1024 * 1024,
                     digest=original['module_sha256'], capture=True)
    custody = _CompilerCustody(None, runtime_allocation='platform')
    primary: BaseException | None = None
    encoded: bytes | bytearray | None = None
    try:
        runtime = import_module('wasmtime')
        ffi = import_module('wasmtime._ffi')
        if Path(ffi.filename) != library or Path(ffi.dll._name) != library:
            raise ValueError('Compiler loaded another platform runtime')
        _platform_runtime_library(selected)
        custody.ffi = ffi
        custody.config = runtime.Config()
        custody.pool = ffi.wasmtime_pooling_allocation_config_new()
        if not custody.pool:
            raise RuntimeError('Platform compiler pool allocation failed')
        _configure_selected_engine(custody.config, custody.pool, ffi, runtime, selected)
        custody.close_pool()
        custody.engine = runtime.Engine(custody.config)
        custody.config = None
        custody.module = runtime.Module(custody.engine, wasm)
        _validate_core_module(runtime, custody.module)
        encoded = custody.module.serialize()
        if not isinstance(encoded, (bytes, bytearray)) or not 0 < len(encoded) <= selected.image_bytes_limit:
            raise ValueError('Compiled image exceeds the selected file limit')
    except BaseException as error:
        primary = error
    try:
        custody.close()
    except BaseException as cleanup_error:
        raise ImageCompilerCleanupError(custody, primary) from cleanup_error
    if primary is not None:
        raise primary
    assert encoded is not None
    final = verify(core_receipt, expected_source, runtime_allocation='platform')
    if (final['recipe'] != selected or _platform_runtime_library(selected) != library
            or final['core_receipt_sha256'] != original['core_receipt_sha256']):
        raise ValueError('Ordinary image compiler inputs changed')
    destination.mkdir()
    image = destination / 'client_host_wasm.cwasm'
    with image.open('xb') as output:
        output.write(encoded)
    image_hash = hashlib.sha256(encoded).hexdigest()
    _read_file(image, maximum=selected.image_bytes_limit, expected=len(encoded), digest=image_hash)
    result: dict[str, object] = {'source_sha': expected_source,
        'module_sha256': original['module_sha256'], 'core_abi': LOCAL_CORE_ABI,
        'wasmtime_version': WASMTIME_VERSION, 'runtime_allocation': 'platform',
        'runtime_library_sha256': selected.runtime_library_sha256,
        'provider_library_sha256': None,
        'engine_sha256': hashlib.sha256(selected.engine_body).hexdigest(),
        'image': str(image.resolve()), 'image_sha256': image_hash,
        'compiled': True, 'runtime_executed': False, 'public_local_acceptance': False}
    (destination / 'image-receipt.json').write_text(json.dumps(result, indent=2) + '\n')
    return result


def compile_image(core_receipt: Path, expected_source: str, destination: Path, *,
                  _holding: _NativeHoldingLease | None = None,
                  _runtime: _CompilerRuntime | None = None) -> dict[str, object]:
    original = verify(core_receipt, expected_source)
    if destination.exists():
        raise ValueError('Image compiler destination already exists')
    if _holding is None:
        raise ValueError('Select an unbound original native compiler holding')
    original = _runtime_original(original, _runtime)
    _verify_compiler_holding(original, _holding)
    assert _holding is not None
    recipe = original['recipe']
    wasm = _read_file(original['module'], maximum=32 * 1024 * 1024,
                     digest=original['module_sha256'], capture=True)
    custody = _CompilerCustody(_holding)
    custody.preparation = _runtime

    def compile_selected() -> bytes | bytearray:
        wasmtime, ffi = _import_compiler_runtime(custody, original)
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
    final = _runtime_original(verify(core_receipt, expected_source), _runtime)
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


def prepare_compiler_executable(core_receipt: Path, expected_source: str,
                                destination: Path, *, bindings_source: Path | None,
                                native_libraries: Path | None, preparation: Path | None,
                                c_api_headers: Path | None, clang: Path | None,
                                sdk: Path | None, seconds: float) -> dict[str, object]:
    """Ordinary producer preparation, with no native import or compiler child.

    This shares the exact original module, private binding/library staging,
    Engine configuration and generated ABI paths with image production. No
    physical acceptance receipt or invented LocalComponents is needed to
    compile the producer's own executable. Actual execution still needs the
    original Native parent/domain and its selected physical backing.
    """
    from python_compiler_program import prepare_program, verify_program

    original = verify(core_receipt, expected_source)
    if any(value is None for value in (bindings_source, native_libraries, preparation,
                                       c_api_headers, clang, sdk)):
        raise ValueError('Select original compiler binding/library/header/toolchain inputs')
    assert bindings_source is not None and native_libraries is not None and preparation is not None
    assert c_api_headers is not None and clang is not None and sdk is not None
    prepared = prepare_compiler_runtime(original, bindings_source, native_libraries, preparation)
    selected = _runtime_original(original, prepared)
    program = prepare_program(selected, headers=c_api_headers, clang=clang, sdk=sdk,
                              destination=destination, seconds=seconds)
    final = _runtime_original(verify(core_receipt, expected_source), prepared)
    if final['recipe'] != original['recipe']:
        raise ValueError('Original compiler preparation changed')
    verify_program(final, program)
    result: dict[str, object] = {'scope': 'original_compiler_executable_inputs_only',
        'source_sha': expected_source, 'module_sha256': original['module_sha256'],
        'core_receipt_sha256': original['core_receipt_sha256'],
        'executable': {'path': program.executable[0], 'bytes': program.executable[1],
                       'sha256': program.executable[2]},
        'program_receipt': str(destination / 'program-receipt.json'),
        'native_loaded': False, 'Config': False, 'Engine': False, 'Module': False,
        'image_compiled': False, 'physical_acceptance': False, 'normal_profile': None}
    return result


class CompilerProcessAssemblyError(RuntimeError):
    """Retain the same original aliases; no retry, close or release policy.

    Native parent/process/region owners remain authoritative. Even a closed
    descriptor does not retire the parent control runtime's process lifetime.
    """

    def __init__(self, preparation: _CompilerRuntime, program: Any) -> None:
        self.preparation, self.program = preparation, program
        self.cleanup_parent: _CompilerParent | None = None
        self.cleanup_descriptor: _OriginalDescriptor | None = None
        self.cleanup_runtime: _CompilerControlRuntime | None = None
        self.response = b''
        self.primary: BaseException | None = None
        self.cleanup_error: BaseException | None = None
        self.diagnostic_error: BaseException | None = None
        # Call progress only, never a physical ACK. Invoke's same Native owners
        # must independently have completed before descriptor-only cleanup.
        self.transport_returned = False
        super().__init__('Original compiler process assembly failed or is unconfirmed')


def _record_failed_compiler_response(failure: CompilerProcessAssemblyError) -> None:
    """Retain the original bounded bytes without admitting them or retrying I/O."""
    if (type(failure) is not CompilerProcessAssemblyError
            or type(failure.response) is not bytes or len(failure.response) > 4097):
        raise ValueError('Original compiler failure response is unavailable')
    # The existing transport can retain one overflow byte as rejection evidence.
    # A partial/failed file write is not repeated and cannot replace the primary
    # error or prevent the same original physical cleanup below.
    with (failure.program.directory.parent / 'compiler-failure-response.bin').open('xb') as record:
        record.write(failure.response)


def _finish_failed_compiler_with_diagnostics(
        failure: CompilerProcessAssemblyError, *, seconds: float) -> dict[str, Any]:
    """Diagnostic storage cannot prevent the existing same-original cleanup."""
    try:
        _record_failed_compiler_response(failure)
    except BaseException as diagnostic_error:
        failure.diagnostic_error = diagnostic_error
        failure.add_note('Original compiler diagnostic could not be fully retained; no retry')
    return finish_failed_compilation(failure, seconds=seconds)


class _CompilerImage(NamedTuple):
    """Image metadata plus original process-lifetime aliases, not admission."""

    receipt: dict[str, object]
    parent: _CompilerParent
    preparation: _CompilerRuntime
    program: Any


def finish_failed_compilation(failure: CompilerProcessAssemblyError,
                              *, seconds: float) -> dict[str, object]:
    """Explicit same-invocation cleanup, never another compile or acceptance.

    Only a registered failed child transport is supported here. Earlier partial
    acquisition retains its existing error/carriers rather than falling through
    to unrelated cleanup. The Native chain confirms process/region/parent
    retirement before this original descriptor's one-shot close. Even then the
    original failure and runtime aliases remain, with no accepted image.
    """
    from python_compiler_process import (CompilerChildProcessError,
        finish_original_compiler_after_stop_request)
    from python_compiler_program import _CompilerProgram

    if (type(failure) is not CompilerProcessAssemblyError
            or type(seconds) not in (int, float) or not math.isfinite(seconds) or seconds <= 0):
        raise ValueError('Select the original compiler failure and finite cleanup budget')
    parent, descriptor, primary = failure.cleanup_parent, failure.cleanup_descriptor, failure.primary
    if (type(parent) is not _CompilerParent or type(descriptor) is not _OriginalDescriptor
            or parent.descriptor is not descriptor
            or descriptor._original is not descriptor
            or failure.cleanup_runtime is not parent.runtime
            or type(failure.program) is not _CompilerProgram
            or failure.program.source != parent.original.holding.source_sha
            or failure.program.module_sha256 != parent.original.holding.module_sha256
            or failure.program.engine_sha256 != parent.original.holding.engine_sha256):
        raise ValueError('Original failed compiler child cleanup is unavailable')
    try:
        if type(primary) is CompilerChildProcessError and primary.cleanup_parent is parent:
            relayed = finish_original_compiler_after_stop_request(primary, timeout=seconds)
        else:
            # Report/image validation can fail after invoke's Native chain has
            # already returned. Only those same owners' completed projections,
            # with no Unknown or registered user, permit descriptor-only cleanup.
            if not failure.transport_returned or not parent._closed:
                raise ValueError('Original failed compiler child cleanup is unavailable')
            parent.runtime.current()
            relayed = False
        if (not parent._closed
                or any(carrier is None or not carrier._closed or carrier._unknown is not None
                    for carrier in (parent.host, parent.backing, parent.domain))
                or parent.domain is None
                or parent.domain._installed_process_original is not None
                or parent.domain._worker_process_original is not None):
            raise ValueError('Original compiler parent cleanup remains unconfirmed')
        descriptor.close()
        return {'scope': 'original_compiler_failure_cleanup_only',
            'source_sha': failure.program.source, 'request_relayed': relayed,
            'original_process_closed': True,
            'original_parent_closed': parent._closed,
            'backing_descriptor_closed': descriptor.closed,
            'process_runtime_retirement_ACK': False,
            'image_accepted': False, 'physical_acceptance': False, 'normal_profile': None}
    except BaseException as cleanup_error:
        failure.cleanup_error = cleanup_error
        raise failure from cleanup_error


def _compiler_process_report(raw: bytes, maximum: int) -> dict[str, Any]:
    """Closed compilation observation only, never a physical cleanup ACK."""
    if type(raw) is not bytes or not 0 < len(raw) <= 4096:
        raise ValueError('Original compiler report is unavailable')
    value = _closed(json.loads(raw, object_pairs_hook=_pairs), (
        'compilation_status', 'image_bytes', 'handles_close', 'leave', 'holding_close',
        'holding_closed', 'runtime_retained', 'config_attempted', 'engine_attempted',
        'module_attempted', 'instance', 'physical_acceptance'))
    integers = ('compilation_status', 'image_bytes', 'handles_close', 'leave', 'holding_close')
    booleans = ('holding_closed', 'runtime_retained', 'config_attempted', 'engine_attempted',
                'module_attempted', 'instance', 'physical_acceptance')
    if (any(type(value[k]) is not int for k in integers)
            or any(type(value[k]) is not bool for k in booleans)
            or value['compilation_status'] != 0 or value['handles_close'] != 0 or value['leave'] != 0
            or not 0 < value['image_bytes'] <= maximum
            or not all(value[k] for k in ('config_attempted', 'engine_attempted', 'module_attempted'))
            or value['instance'] or value['physical_acceptance']
            # Existing owned_capacity.h status: OK=0; BUSY=-3. BUSY stays
            # RuntimeRetained; it is never upgraded to allocation-level close.
            or not ((value['holding_close'] == 0 and value['holding_closed'] and not value['runtime_retained'])
                    or (value['holding_close'] == -3 and not value['holding_closed'] and value['runtime_retained']))):
        raise ValueError('Original compiler did not confirm compilation')
    return value


def compile_from_original(core_receipt: Path, expected_source: str,
                          destination: Path, *, bindings_source: Path | None = None,
                          native_libraries: Path | None = None,
                          preparation: Path | None = None,
                          c_api_headers: Path | None = None, clang: Path | None = None,
                          sdk: Path | None = None, seconds: float = 50) -> _CompilerImage:
    """Ordinary compiler through the same funded original Native process.

    The source declaration precedes Native acquisition. Program preparation
    shares the original Engine/configuration, module, DLL and actual C inputs.
    No unbound holding, in-process Engine import or alternate compiler is used.
    The caller must retain the returned parent runtime aliases until its own
    process retires; neither this image nor Engine close acknowledges that.
    """
    from python_compiler_program import prepare_program, verify_program
    from python_compiler_process import invoke_original_compiler

    if (type(seconds) not in (int, float) or not math.isfinite(seconds) or seconds <= 0
            or not destination.is_absolute() or destination.resolve() != destination
            or destination.exists() or destination.is_symlink()):
        raise ValueError('Select a fresh canonical compiler destination and finite budget')
    deadline = time.monotonic() + seconds
    original = verify(core_receipt, expected_source)
    selected = _compiler_holding_original(original)
    # Metadata selects this same original; it does not issue a Ledger or backing.
    _compiler_parent_original(original, selected)
    if any(value is None for value in (bindings_source, native_libraries, preparation,
                                       c_api_headers, clang, sdk)):
        raise ValueError('Select original compiler binding/library/header/toolchain inputs')
    assert bindings_source is not None and native_libraries is not None and preparation is not None
    assert c_api_headers is not None and clang is not None and sdk is not None
    prepared = prepare_compiler_runtime(original, bindings_source, native_libraries, preparation)
    original = _runtime_original(original, prepared)
    destination.mkdir(mode=0o700)
    program = prepare_program(original, headers=c_api_headers, clang=clang, sdk=sdk,
        destination=destination / 'program', seconds=deadline - time.monotonic())
    original = _runtime_original(verify(core_receipt, expected_source), prepared)
    executable = verify_program(original, program)
    failure = CompilerProcessAssemblyError(prepared, program)
    try:
        descriptor = _OriginalDescriptor(os.open(destination / 'compiler-parent.backing',
            os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC, 0o600))
        failure.cleanup_descriptor = descriptor
        os.ftruncate(descriptor.value, selected.capacity_bytes)
        parent = _acquire_compiler_parent(original, selected, descriptor)
        failure.cleanup_parent, failure.cleanup_runtime = parent, parent.runtime
        image = destination / 'client_host_wasm.cwasm'
        response = invoke_original_compiler(parent, executable=executable,
            executable_bytes=program.executable[1], executable_sha256=program.executable[2],
            module=original['module'], destination=image,
            slot=str(destination / 'compiler-process.slot'), nonce=selected.generation,
            timeout=deadline - time.monotonic())
        failure.transport_returned = True
        failure.response = response
        if not parent._closed:
            raise ValueError('Original compiler process/region cleanup is unconfirmed')
        # The helper returns only after the same Native process Owner confirmed
        # stop/IPC/region retirement and parent cleanup. Report bytes never do so.
        descriptor.close()
        report = _compiler_process_report(response, original['recipe'].image_bytes_limit)
        encoded = _read_file(image, maximum=original['recipe'].image_bytes_limit,
                             expected=report['image_bytes'], capture=True)
        image_hash = hashlib.sha256(encoded).hexdigest()
        final = _runtime_original(verify(core_receipt, expected_source), prepared)
        verify_program(final, program)
        if (final['core_receipt_sha256'] != original['core_receipt_sha256']
                or final['recipe'] != original['recipe']):
            raise ValueError('Original image compiler materials changed')
        recipe = final['recipe']
        result: dict[str, object] = {'source_sha': expected_source,
            'module_sha256': original['module_sha256'], 'core_abi': LOCAL_CORE_ABI,
            'wasmtime_version': WASMTIME_VERSION,
            'runtime_library_sha256': recipe.runtime_library_sha256,
            'provider_library_sha256': recipe.provider_library_sha256,
            'engine_sha256': hashlib.sha256(recipe.engine_body).hexdigest(),
            'image': str(image.resolve()), 'image_sha256': image_hash,
            'compiled': True, 'runtime_executed': False, 'public_local_acceptance': False}
        (destination / 'compiler-process-receipt.json').write_text(json.dumps({
            'scope': 'original_compiler_process_only', 'source_sha': expected_source,
            'program_executable': program.executable, 'compilation_observation': report,
            'parent_domain_region_closed': True, 'backing_descriptor_closed': descriptor.closed,
            'parent_runtime_retirement_ACK': False, 'physical_acceptance': False,
            'normal_profile': None}, indent=2) + '\n')
        (destination / 'image-receipt.json').write_text(json.dumps(result, indent=2) + '\n')
        return _CompilerImage(result, parent, prepared, program)
    except BaseException as primary:
        failure.primary = primary
        failure.cleanup_parent = getattr(primary, 'cleanup_parent', None) or failure.cleanup_parent
        failure.cleanup_runtime = getattr(primary, 'cleanup_runtime', None) or failure.cleanup_runtime
        partial = getattr(primary, 'response', None)
        if type(partial) in (bytes, bytearray):
            failure.response = bytes(cast(bytes | bytearray, partial))
        # A descriptor opened before any Native operation is still this call's
        # original. Once control/parent acquisition is attempted, retain all
        # partial carriers; never infer release or repeat their foreign cleanup.
        raise failure from primary


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source', required=True)
    parser.add_argument('--core-receipt', type=Path, required=True)
    parser.add_argument('--destination', type=Path, required=True)
    parser.add_argument('--bindings-source', type=Path)
    parser.add_argument('--native-libraries', type=Path)
    parser.add_argument('--preparation', type=Path)
    parser.add_argument('--c-api-headers', type=Path)
    parser.add_argument('--clang', type=Path)
    parser.add_argument('--sdk', type=Path)
    parser.add_argument('--seconds', type=float, default=50)
    parser.add_argument('--cleanup-seconds', type=float, default=5,
                        help='Separate bounded failed-child cleanup window; never another compilation')
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument('--verify-only', action='store_true')
    mode.add_argument('--prepare-c-config', action='store_true')
    mode.add_argument('--prepare-c-program', action='store_true')
    mode.add_argument('--compile', action='store_true')
    mode.add_argument('--compile-platform', action='store_true')
    args = parser.parse_args()
    if args.compile and (not math.isfinite(args.cleanup_seconds) or args.cleanup_seconds <= 0):
        parser.error('Select a finite positive failed-child cleanup window')
    if args.verify_only:
        checked = verify(args.core_receipt, args.source)
        print(json.dumps({'scope': 'original_module_and_recipe_only',
            'private_runtime_prepared': False,
            'source_sha': args.source, 'module_sha256': checked['module_sha256'],
            'engine_sha256': hashlib.sha256(checked['recipe'].engine_body).hexdigest(),
            'image_bytes_limit': checked['recipe'].image_bytes_limit,
            'native_engine_started': False, 'compiled': False, 'public_local_acceptance': False}))
    elif args.prepare_c_config:
        print(json.dumps(prepare_compiler_configuration(args.core_receipt, args.source, args.destination)))
    elif args.prepare_c_program:
        print(json.dumps(prepare_compiler_executable(args.core_receipt, args.source, args.destination,
            bindings_source=args.bindings_source, native_libraries=args.native_libraries,
            preparation=args.preparation, c_api_headers=args.c_api_headers,
            clang=args.clang, sdk=args.sdk, seconds=args.seconds)))
    elif args.compile_platform:
        if any((args.bindings_source, args.native_libraries, args.preparation,
                args.c_api_headers, args.clang, args.sdk)):
            parser.error('Platform compiler uses only the original pinned dependency')
        print(json.dumps(compile_platform_image(args.core_receipt, args.source, args.destination)))
    else:
        try:
            compiled = compile_from_original(args.core_receipt, args.source, args.destination,
                bindings_source=args.bindings_source, native_libraries=args.native_libraries,
                preparation=args.preparation, c_api_headers=args.c_api_headers,
                clang=args.clang, sdk=args.sdk, seconds=args.seconds)
        except CompilerProcessAssemblyError as failure:
            # This maintainer caller explicitly chooses same-original cleanup.
            # The compilation remains failed even when physical cleanup ends;
            # no report, partial image, new child or final receipt is accepted.
            try:
                cleanup = _finish_failed_compiler_with_diagnostics(failure, seconds=args.cleanup_seconds)
                with (args.destination / 'compiler-failure-cleanup.json').open('x') as record:
                    record.write(json.dumps(cleanup, indent=2) + '\n')
            except BaseException as cleanup_error:
                if cleanup_error is failure:
                    raise
                failure.cleanup_error = cleanup_error
                raise failure from cleanup_error
            print(json.dumps(cleanup), file=sys.stderr, flush=True)
            raise
        print(json.dumps(compiled.receipt))
