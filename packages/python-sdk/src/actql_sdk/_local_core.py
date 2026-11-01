"""Private physical Wasm bridge. Run decisions remain in MoonBit Core."""
from __future__ import annotations

from collections.abc import Callable, Iterator
from contextlib import contextmanager
from dataclasses import dataclass
import hashlib
import json
from ctypes import c_void_p, cast
from importlib import import_module
import secrets
import sys
from threading import RLock
from typing import TYPE_CHECKING, Any, Literal

if TYPE_CHECKING:
    from ._local_engine import _InstalledImageInput, _InstalledImageFileInput
    from ._local_native_image import _NativeImageHolding
    from ._local_native_vm import _OriginalVMObservation
    from ._local_worker_child_control import _OriginalChildControlPipe
    from ._local_distribution import LocalComponents

from ._local_journal_port import _JournalCallbacks
from ._local_storage import _NamespaceReader, LocalByteStore
from ._local_native_holding import _NativeHoldingLease

_NORMAL_HOST_BOOTSTRAP_FUEL = 1_000_000_000
_NORMAL_HOST_OPERATION_FUEL = 32_000_000_000
_NORMAL_HOST_CLEANUP_FUEL = 100_000_000


class LocalCoreError(RuntimeError):
    """An ABI failure, never permission to retry a Submission or Compute."""

    def __init__(self, operation: str, code: int) -> None:
        self.operation = operation
        self.code = code
        super().__init__(f'Local Core {operation} returned {code}')


class LocalCoreInitializationError(RuntimeError):
    """Failed construction still owns native cleanup through the same bridge."""

    def __init__(self, cleanup_core: LocalCore) -> None:
        self.cleanup_core = cleanup_core
        super().__init__('Local Core initialization failed with cleanup pending')


@dataclass(frozen=True, slots=True)
class LocalCoreResources:
    """Managed Host allowances, independent of fuel and physical acquisition.

    They are not an allocation, original native holding or hard RSS bound.
    """

    planning_work: int
    attempts: int
    holdings: int
    transfer_bytes: int
    retained_bytes: int
    execution_bytes: int

    def valid(self) -> bool:
        return (all(type(value) is int and 0 <= value <= 2**31 - 1
                    for value in (self.planning_work, self.attempts, self.holdings))
                and self.attempts >= 2
                and all(type(value) is int and 0 <= value <= 2**63 - 1
                        for value in (self.transfer_bytes, self.retained_bytes,
                                      self.execution_bytes)))


@dataclass(frozen=True, slots=True, eq=False)
class _Workspace:
    owner: object
    ticket: int
    handle: int


@dataclass(frozen=True, slots=True, eq=False)
class _Input:
    owner: object
    ticket: int
    handle: int
    length: int


@dataclass(frozen=True, slots=True, eq=False)
class _Task:
    owner: object
    handle: int


@dataclass(frozen=True, slots=True, eq=False)
class _ResultExport:
    owner: object
    handle: int


@dataclass(frozen=True, slots=True)
class LocalResultProgress:
    ready: bool
    work: int


@dataclass(frozen=True, slots=True)
class LocalTaskProgress:
    complete: bool
    waiting: bool
    progress: int
    work: int


@dataclass(frozen=True, slots=True)
class LocalNativeCapacity:
    retained_bytes: int
    execution_bytes: int
    transfer_bytes: int


@dataclass(frozen=True, slots=True, eq=False)
class _Compute:
    owner: object
    handle: int


@dataclass(frozen=True, slots=True, eq=False)
class _NativeAttempt:
    owner: object
    handle: int


@dataclass(frozen=True, slots=True)
class _PublisherFact:
    """Original six Owner facts; not a policy body, grant or Store outcome."""

    stage: str
    namespace_id: str
    authority_scope_cid: str
    run_definition_cid: str
    publication_request_cid: str
    public_index_entry_cid: str | None


@dataclass(slots=True)
class _PublisherCallbacks:
    current: Callable[[], bool]
    authorize: Callable[[_PublisherFact], bool]
    buffer: bytearray | None = None
    received: int = 0


_PUBLISHER_LIMIT = 8192


def _publisher_fact(payload: bytearray) -> _PublisherFact:
    def closed_pairs(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate publisher fact field')
            result[key] = value
        return result

    value = json.loads(payload, object_pairs_hook=closed_pairs)
    fields = ('stage', 'namespace_id', 'authority_scope_cid', 'run_definition_cid',
              'publication_request_cid', 'public_index_entry_cid')
    if (type(value) is not dict or set(value) != set(fields)
            or any(type(value[key]) is not str or not value[key] for key in fields[:-1])
            or value['stage'] not in ('request', 'commit', 'return_committed')
            or (value['public_index_entry_cid'] is not None
                and (type(value['public_index_entry_cid']) is not str
                     or not value['public_index_entry_cid']))
            or ((value['stage'] == 'request') != (value['public_index_entry_cid'] is None))):
        raise ValueError('Invalid original publisher facts')
    return _PublisherFact(**value)


@dataclass(slots=True)
class _PhysicalInput:
    payload: bytes
    cleanup: Callable[[], bool]
    stopped: Callable[[int], bool]
    publisher: _PublisherCallbacks | None = None
    journal: _JournalCallbacks | None = None


@dataclass(frozen=True, slots=True, eq=False)
class _Output:
    owner: object
    ticket: int
    handle: int
    limit: int
    family: str = "material"


# Existing publication field selection is separate from scalar signatures.
_CommitMaterialField = Literal['wire', 'name', 'identity_field', 'identity']
_COMMIT_MATERIAL_FIELDS = {'wire': 0, 'name': 1, 'identity_field': 2, 'identity': 3}


# Scalar declarations are generated from the original MoonBit boundary.
from ._local_wasm_abi import (
    LOCAL_CORE_ABI,
    _BUFFER_SIGNATURES,
    _PROGRAM_SIGNATURES,
    _CHECK_SIGNATURES,
    _RUN_SIGNATURES,
    _SUBMISSION_SIGNATURES,
    _BOOTSTRAP_SIGNATURES,
    _SOURCE_PUBLICATION_SIGNATURES,
    _RUN_INVOCATION_SIGNATURES,
    _MATERIAL_SIGNATURES,
    _PUBLICATION_SIGNATURES,
    _PUBLICATION_PREFLIGHT_SIGNATURES,
    _PUBLICATION_COMMIT_EXPORT_SIGNATURES,
    _PAYLOAD_REQUEST_SIGNATURES,
    _RESULT_BINDING_SIGNATURES,
    _PAYLOAD_CHUNK_SIGNATURES,
    _PAYLOAD_RECORD_SIGNATURES,
    _PAYLOAD_RESERVATION_SIGNATURES,
    _PAYLOAD_WRITING_SIGNATURES,
    _PAYLOAD_ALLOCATION_SIGNATURES,
    _PAYLOAD_NAMES_SIGNATURES,
    _PAYLOAD_BINDING_SIGNATURES,
    _SOURCE_SIGNATURES,
    _TASK_SIGNATURES,
    _COMPUTE_SIGNATURES,
    _RESULT_SIGNATURES,
    _WORKSPACE_SIGNATURES,
    _PUBLISHER_SIGNATURES,
    _IMPORT_SIGNATURES,
    _JOURNAL_SIGNATURES,
    _CURRENT_SIGNATURES,
    _ORIGINAL_SIGNATURES,
)
_MEMORY_LIMIT = 16 * 1024 * 1024


def _signature(value: Any) -> tuple[str, str]:
    return (' '.join(str(item) for item in value.params),
            ' '.join(str(item) for item in value.results))


def _validate_core_module(wasmtime: Any, module: Any) -> None:
    imports = module.imports
    if (len(imports) != len(_IMPORT_SIGNATURES) or
            {(item.module, item.name) for item in imports} !=
            {('actql_host', name) for name in _IMPORT_SIGNATURES} or
            any(not isinstance(item.type, wasmtime.FuncType) or
                _signature(item.type) != _IMPORT_SIGNATURES[item.name]
                for item in imports)):
        raise ValueError('Unrecognized Local Core physical imports')
    expected = {'actql_buffer_' + name: value
                for name, value in _BUFFER_SIGNATURES.items()}
    expected.update({'actql_program_' + name: value
                     for name, value in _PROGRAM_SIGNATURES.items()})
    expected.update({'actql_check_' + name: value
                     for name, value in _CHECK_SIGNATURES.items()})
    expected.update({'actql_run_' + name: value
                     for name, value in _RUN_SIGNATURES.items()})
    expected.update({'actql_submission_' + name: value
                     for name, value in _SUBMISSION_SIGNATURES.items()})
    expected.update({'actql_bootstrap_' + name: value
                     for name, value in _BOOTSTRAP_SIGNATURES.items()})
    expected.update({'actql_source_publication_' + name: value
                     for name, value in _SOURCE_PUBLICATION_SIGNATURES.items()})
    expected.update({'actql_run_invocation_' + name: value
                     for name, value in _RUN_INVOCATION_SIGNATURES.items()})
    expected.update({'actql_material_' + name: value
                     for name, value in _MATERIAL_SIGNATURES.items()})
    expected.update({'actql_publication_' + name: value
                     for name, value in _PUBLICATION_SIGNATURES.items()})
    expected.update({'actql_publication_preflight_' + name: value
                     for name, value in _PUBLICATION_PREFLIGHT_SIGNATURES.items()})
    expected.update({'actql_publication_commit_export_' + name: value
                     for name, value in _PUBLICATION_COMMIT_EXPORT_SIGNATURES.items()})
    expected.update({'actql_payload_request_' + name: value
                     for name, value in _PAYLOAD_REQUEST_SIGNATURES.items()})
    expected.update({'actql_payload_chunk_' + name: value
                     for name, value in _PAYLOAD_CHUNK_SIGNATURES.items()})
    expected.update({'actql_payload_record_' + name: value
                     for name, value in _PAYLOAD_RECORD_SIGNATURES.items()})
    expected.update({'actql_payload_reservation_' + name: value
                     for name, value in _PAYLOAD_RESERVATION_SIGNATURES.items()})
    expected.update({'actql_payload_writing_' + name: value
                     for name, value in _PAYLOAD_WRITING_SIGNATURES.items()})
    expected.update({'actql_payload_allocation_' + name: value
                     for name, value in _PAYLOAD_ALLOCATION_SIGNATURES.items()})
    expected.update({'actql_payload_names_' + name: value
                     for name, value in _PAYLOAD_NAMES_SIGNATURES.items()})
    expected.update({'actql_payload_binding_' + name: value
                     for name, value in _PAYLOAD_BINDING_SIGNATURES.items()})
    expected.update({'actql_result_binding_' + name: value
                     for name, value in _RESULT_BINDING_SIGNATURES.items()})
    expected.update({'actql_source_' + name: value
                     for name, value in _SOURCE_SIGNATURES.items()})
    expected.update({'actql_workspace_' + name: value
                     for name, value in _WORKSPACE_SIGNATURES.items()})
    expected.update({'actql_compute_' + name: value
                     for name, value in _COMPUTE_SIGNATURES.items()})
    expected.update({'actql_task_' + name: value
                     for name, value in _TASK_SIGNATURES.items()})
    expected.update({'actql_result_' + name: value
                     for name, value in _RESULT_SIGNATURES.items()})
    expected.update({'actql_publisher_' + name: value
                     for name, value in _PUBLISHER_SIGNATURES.items()})
    expected.update({'actql_journal_' + name: value
                     for name, value in _JOURNAL_SIGNATURES.items()})
    expected.update({'actql_current_' + name: value
                     for name, value in _CURRENT_SIGNATURES.items()})
    expected.update({'actql_original_' + name: value
                     for name, value in _ORIGINAL_SIGNATURES.items()})
    expected['actql_host_abi_version'] = ('', 'i32')
    exports = {item.name: item.type for item in module.exports}
    if (any(name not in exports or
            not isinstance(exports[name], wasmtime.FuncType) or
            _signature(exports[name]) != signature
            for name, signature in expected.items()) or
            set(exports) != set(expected) | {'memory'}):
        raise ValueError('Unrecognized Local Core exports')
    memory = exports.get('memory')
    if (not isinstance(memory, wasmtime.MemoryType) or memory.is_64 or
            memory.is_shared or memory.limits.max != 256 or
            memory.limits.min > 256):
        raise ValueError('Unbounded Local Core linear memory')


def _valid_core_limits(transfer_capacity: int, slots: int, fuel: int,
                       resources: LocalCoreResources, host_capacity_bytes: int = 0) -> bool:
    return (type(transfer_capacity) is int and 0 < transfer_capacity <= 2**63 - 1
            and type(slots) is int and 1 <= slots <= 1024
            and type(fuel) is int and 0 < fuel <= 2**64 - 1
            and type(resources) is LocalCoreResources and resources.valid()
            and type(host_capacity_bytes) is int and 0 <= host_capacity_bytes <= 2**63 - 1
            and transfer_capacity <= resources.execution_bytes - _MEMORY_LIMIT - host_capacity_bytes
            and (host_capacity_bytes == 0 or resources.attempts >= 3))


class LocalCore:
    """Serialize calls into one instance and preserve its physical custody.

    This bridge does not implement Client routing, admission, recovery, or a
    global memory guarantee. The installed Host accounts for its Wasm and copy
    allowances through the existing Owner, acquires real runtime resources and
    keeps any explicitly supplied native holding until its actual cleanup ACK.
    """

    @classmethod
    def _from_installed_image(cls, components: LocalComponents, *, resources: LocalCoreResources,
                              transfer_capacity: int, slots: int = 64,
                              _host_capacity_bytes: int = 0,
                              _physical_holding: _NativeHoldingLease | None = None,
                              _child_control: _OriginalChildControlPipe | None = None,
                              _ordinary_host: bool = False) -> LocalCore:
        if not _valid_core_limits(transfer_capacity, slots, 100_000_000, resources,
                                  _host_capacity_bytes):
            raise ValueError('Invalid installed Local Core artifact or capacity')
        if _child_control is not None:
            from ._local_worker_child_control import _OriginalChildControlPipe
            if type(_child_control) is not _OriginalChildControlPipe or _physical_holding is None:
                raise ValueError('Invalid original child control')
            _child_control._require_unbound_holding(_physical_holding)
        from ._local_engine import _checked_installed_image, _checked_installed_image_file
        image = (_checked_installed_image(components) if _physical_holding is None
                 else _checked_installed_image_file(components))
        return cls(None, digest=components.module_sha256, transfer_capacity=transfer_capacity,
                   resources=resources, slots=slots, _compiled_image=image,
                   fuel=_NORMAL_HOST_BOOTSTRAP_FUEL if _ordinary_host else 100_000_000,
                   _ordinary_host=_ordinary_host,
                   _host_capacity_bytes=_host_capacity_bytes, _physical_holding=_physical_holding,
                   _child_control=_child_control)

    def __init__(self, module: bytes | None, *, digest: str, transfer_capacity: int, resources: LocalCoreResources,
                 slots: int = 32, fuel: int = 100_000_000,
                 _compiled_image: _InstalledImageInput | _InstalledImageFileInput | None = None,
                 _host_capacity_bytes: int = 0,
                 _physical_holding: _NativeHoldingLease | None = None,
                 _child_control: _OriginalChildControlPipe | None = None,
                 _ordinary_host: bool = False) -> None:
        from ._local_engine import _InstalledImageInput, _InstalledImageFileInput
        from ._local_native_image import _NativeImageHolding
        from ._local_image_recipe import _SelectedImageRecipe
        if type(_compiled_image) is _InstalledImageFileInput:
            original_valid = (module is None and type(_compiled_image.recipe) is _SelectedImageRecipe
                and _compiled_image.recipe.module_sha256 == digest
                and type(_compiled_image.length) is int
                and 0 < _compiled_image.length <= _compiled_image.recipe.image_bytes_limit
                and type(_compiled_image.sha256) is str and len(_compiled_image.sha256) == 64
                and all(char in '0123456789abcdef' for char in _compiled_image.sha256)
                and type(_physical_holding) is _NativeHoldingLease)
        else:
            original_valid = (type(module) is bytes and hashlib.sha256(module).hexdigest() == digest
                if _compiled_image is None else type(_compiled_image) is _InstalledImageInput
                    and module is None and type(_compiled_image.recipe) is _SelectedImageRecipe
                    and _compiled_image.recipe.module_sha256 == digest
                    and type(_compiled_image.encoded) is bytes
                    and hashlib.sha256(_compiled_image.encoded).hexdigest() == _compiled_image.sha256)
        if not original_valid or not _valid_core_limits(transfer_capacity, slots, fuel, resources,
                                                       _host_capacity_bytes):
            raise ValueError('Invalid installed Local Core artifact or capacity')
        if type(_ordinary_host) is not bool or (_ordinary_host and _compiled_image is None):
            raise ValueError('Ordinary Host fuel requires the installed image')
        if _compiled_image is not None:
            _compiled_image.recipe.validate()
            expected_fuel = _NORMAL_HOST_BOOTSTRAP_FUEL if _ordinary_host else 100_000_000
            if fuel != expected_fuel:
                raise ValueError('Installed Local image requires the original instruction fuel')
        if _physical_holding is not None and (type(_physical_holding) is not _NativeHoldingLease
                                               or _compiled_image is None):
            raise ValueError('Invalid original native holding')
        if _child_control is not None:
            from ._local_worker_child_control import _OriginalChildControlPipe
            if type(_child_control) is not _OriginalChildControlPipe or _physical_holding is None:
                raise ValueError('Invalid original child control')
            _child_control._require_unbound_holding(_physical_holding)
        self._lock = RLock()
        self._identity = object()
        self._nonce = secrets.randbelow(2**63 - 1) + 1
        self._inputs: dict[int, _PhysicalInput] = {}
        self._task_loans: dict[int, _Task] = {}
        self._result_loans: dict[int, _ResultExport] = {}
        self._compute_loans: dict[int, _Compute] = {}
        self._native_loans: dict[int, _NativeAttempt] = {}
        self._native_observers: dict[int, tuple[Callable[[], bool], Callable[[], bool], Callable[[], bool]]] = {}
        self._loans: dict[int, _Input | _Output | _Workspace] = {}
        self._released: set[int] = set()
        self._next_ticket = 1
        self._closed = False
        self._retired = False
        self._closing = False
        self._invoking = False
        self._ordinary_host = _ordinary_host
        self._host_fuel_phase: str | None = 'initial' if _ordinary_host else None
        self._host_initial_claimed = False
        # One bounded same-instance observation generation, never a grant,
        # Run identity, submitted continuation or independent fuel allowance.
        self._host_operation_sequence = 0
        self._host_operation_id = 0
        self._host_cleanup_depth = 0
        self._engine: Any = None
        self._engine_configuration: Any = None
        self._pool_configuration: Any = None
        self._pool_ffi: Any = None
        self._store: Any = None
        self._module: Any = None
        self._linker: Any = None
        self._physical_vm_type: Any = None
        self._physical_vm_span: tuple[int, int] | None = None
        self._physical_vm_observation: _OriginalVMObservation | None = None
        self._physical_child_control = _child_control
        if _physical_holding is not None:
            _physical_holding._bind_core(self._identity)
        self._physical_holding = _physical_holding
        self._physical_image: _NativeImageHolding | None = None
        try:
            if self._physical_child_control is not None:
                self._physical_child_control._attach_core(self)
            if self._physical_holding is not None:
                self._physical_holding._transfer_to_core(self._identity)
            with self._native_scope():
                # Keep an already supplied holding through optional import failure.
                # Remote-only imports never initialize the optional engine.
                runtime_name = ('actql_local_runtime._wasmtime'
                                if self._physical_holding is not None else 'wasmtime')
                try:
                    wasmtime = import_module(runtime_name)
                except ImportError as error:
                    raise RuntimeError('Python Local requires the optional Wasmtime runtime') from error
                if _compiled_image is not None:
                    _compiled_image.recipe.validate()
                    from ._local_engine import (_configure_selected_engine, _verify_loaded_runtime,
                                                _InitializationLibraryFiles)
                    ffi = import_module(runtime_name + '._ffi')
                    with _InitializationLibraryFiles(_compiled_image.recipe,
                                                     _compiled_image.runtime_library) as originals:
                        _verify_loaded_runtime(_compiled_image, ffi, _initialization_files=originals)
                        if self._physical_holding is not None:
                            self._physical_holding._verify_library(ffi.dll, _installed_image=_compiled_image,
                                                                  _initialization_files=originals)
                self._engine_configuration = wasmtime.Config()
                if _compiled_image is None:
                    # Original raw-Wasm physical diagnostics remain separately
                    # qualified. The installed product never selects this branch.
                    self._engine_configuration.consume_fuel = True
                else:
                    self._pool_ffi = ffi
                    self._pool_configuration = ffi.wasmtime_pooling_allocation_config_new()
                    if not self._pool_configuration:
                        raise RuntimeError('Selected Local pooling configuration is unavailable')
                    _configure_selected_engine(self._engine_configuration, self._pool_configuration,
                                               ffi, wasmtime, _compiled_image.recipe)
                    # Pinned C API clones the pool settings; retire the temporary
                    # configuration only after that copy succeeds.
                    ffi.wasmtime_pooling_allocation_config_delete(self._pool_configuration)
                    self._pool_configuration = None
                self._engine = wasmtime.Engine(self._engine_configuration)
                self._engine_configuration = None
                self._store = wasmtime.Store(self._engine)
                self._store.set_fuel(fuel)
                self._store.set_limits(memory_size=_MEMORY_LIMIT, memories=1)
                if type(_compiled_image) is _InstalledImageFileInput:
                    assert self._physical_holding is not None
                    self._physical_image = _NativeImageHolding(self._physical_holding, _compiled_image)
                    self._physical_image.capture()
                    # Retain the original high-level module before native output
                    # can be produced, including scope-exit/exception failure.
                    self._module = wasmtime.Module.__new__(wasmtime.Module)
                    self._physical_image.deserialize_into(self._engine, self._module, wasmtime, ffi)
                    self._physical_image.close()
                    self._physical_image = None
                elif _compiled_image is None:
                    self._module = wasmtime.Module(self._engine, module)
                else:
                    assert type(_compiled_image) is _InstalledImageInput
                    self._module = wasmtime.Module.deserialize(self._engine, _compiled_image.encoded)
                _validate_core_module(wasmtime, self._module)
                self._linker = wasmtime.Linker(self._engine)
                for name, callback in [('input_byte', self._read),
                                       ('input_cleanup', self._cleanup),
                                       ('reader_stop', self._stopped),
                                       ('native_settled', self._native_settled),
                                       ('native_stopped', self._native_stopped),
                                       ('native_cleaned', self._native_cleaned),
                                       ('publisher_current', self._publisher_current),
                                       ('publisher_begin', self._publisher_begin),
                                       ('publisher_finish', self._publisher_finish),
                                       ('journal_current', self._journal_current),
                                       ('journal_current_operation', self._journal_current_operation),
                                       ('journal_schema', self._journal_schema),
                                       ('journal_begin', self._journal_begin),
                                       ('journal_query', self._journal_query),
                                       ('journal_length', self._journal_length),
                                       ('journal_revision', self._journal_revision),
                                       ('journal_release', self._journal_release)]:
                    params = [wasmtime.ValType.i32()
                              for _ in _IMPORT_SIGNATURES[name][0].split()]
                    self._linker.define_func('actql_host', name,
                        wasmtime.FuncType(params, [wasmtime.ValType.i64() if
                            _IMPORT_SIGNATURES[name][1] == 'i64' else wasmtime.ValType.i32()]), callback)
                for name, callback in [('input_copy', self._input_copy),
                                       ('publisher_copy', self._publisher_copy),
                                       ('journal_query_copy', self._journal_query_copy),
                                       ('journal_copy', self._journal_copy)]:
                    params = [wasmtime.ValType.i32()
                              for _ in _IMPORT_SIGNATURES[name][0].split()]
                    self._linker.define_func('actql_host', name,
                        wasmtime.FuncType(params, [wasmtime.ValType.i32()]),
                        callback, access_caller=True)
                for name in ('execution_child_admit', 'execution_child_current',
                             'execution_child_limit', 'execution_child_capacity',
                             'execution_child_report', 'execution_child_stop'):
                    params = [wasmtime.ValType.i64() if item == 'i64' else wasmtime.ValType.i32()
                              for item in _IMPORT_SIGNATURES[name][0].split()]
                    result_type = (wasmtime.ValType.i64() if _IMPORT_SIGNATURES[name][1] == 'i64'
                                   else wasmtime.ValType.i32())
                    child_callback = (self._unavailable_execution_child
                        if self._physical_child_control is None else
                        getattr(self._physical_child_control, name.removeprefix('execution_child_')))
                    self._linker.define_func('actql_host', name,
                        wasmtime.FuncType(params, [result_type]), child_callback, access_caller=True)
                instance = self._linker.instantiate(self._store, self._module)
                self._exports = instance.exports(self._store)
                if self._exports['actql_host_abi_version'](self._store) != LOCAL_CORE_ABI:
                    raise ValueError('Unsupported Local Core ABI version')
                if self._physical_holding is not None:
                    self._observe_original_vm_span(wasmtime)
                    self._validate_original_native_projection(_host_capacity_bytes)
                    from ._local_native_vm import _OriginalVMObservation
                    _OriginalVMObservation._capture(self, wasmtime)
                if self._physical_child_control is not None:
                    if self._physical_vm_observation is None:
                        raise ValueError('Original child VM observation is unavailable')
                    self._physical_child_control._bind_original_vm(self._physical_vm_observation)
                    # The existing portable Owner imports the original child
                    # Ledger/VM/Host capacities. Never fall back to scalar open.
                    self._check('open_live', self._call('buffer', 'open_live',
                                                       transfer_capacity, slots, 1_048_576))
                else:
                    self._check('open', self._call('buffer', 'open', transfer_capacity,
                                                slots, 1_048_576, resources.planning_work,
                                                resources.attempts, resources.holdings,
                                                resources.transfer_bytes, resources.retained_bytes,
                                                resources.execution_bytes, _host_capacity_bytes))
                self._host_fuel_phase = None
        except BaseException as error:
            self._retired = True
            self._closing = True
            try:
                self._dispose()
            except Exception:
                raise LocalCoreInitializationError(self) from error
            raise

    def _observe_original_vm_span(self, wasmtime: Any) -> None:
        """Observe only this instance/Store's original reserved VM backing span.

        This establishes physical membership, not capacity funding or permission.
        Do not accept an address, memory, Store or size from a public caller.
        """
        holding = self._physical_holding
        if (holding is None or self._store is None or self._physical_vm_span is not None
                or self._closed or self._retired or self._closing):
            raise ValueError('Original native VM observation is unavailable')
        memory = self._exports.get('memory')
        if not isinstance(memory, wasmtime.Memory):
            raise ValueError('Original Local instance memory is unavailable')
        self._physical_vm_type = memory.type(self._store)
        limits = self._physical_vm_type.limits
        if (self._physical_vm_type.is_64 or self._physical_vm_type.is_shared
                or type(limits.max) is not int or limits.max != _MEMORY_LIMIT // 65536
                or type(limits.min) is not int or not 0 <= limits.min <= limits.max):
            raise ValueError('Original Local VM reservation differs from its selected contract')
        address = cast(memory.data_ptr(self._store), c_void_p)
        holding._require_live_span(address, _MEMORY_LIMIT)
        if address.value is None:
            raise ValueError('Original Local VM reservation has no physical address')
        self._physical_vm_span = (address.value, _MEMORY_LIMIT)
        self._physical_vm_type.close()
        self._physical_vm_type = None

    def _unavailable_execution_child(self, caller: Any, nonce: int, *arguments: int) -> int:
        """No scalar-open or diagnostic holding supplies parent live authority.

        The installed physical issuer must replace this missing supplier with
        its original channel/native access. A Caller observation is necessary
        but never sufficient for admission, capacity, report or stop authority.
        """
        observation = self._physical_vm_observation
        if observation is None:
            return -42
        observation._require_caller(caller, nonce)
        return -42

    def _validate_original_native_projection(self, host_capacity_bytes: int) -> None:
        """Refuse undercounting the original mapping before opening its Root.

        VM membership is a prerequisite for subtracting its existing reserved
        allowance. Child retirement does not release the outer mapping. This
        necessary lower bound does not supply outside Python/SQLite funding or
        adopt a numerical Host profile.
        """
        holding = self._physical_holding
        if (holding is None or self._store is None or self._physical_vm_span is None
                or self._physical_vm_span[1] != _MEMORY_LIMIT
                or self._closed or self._retired or self._closing
                or type(host_capacity_bytes) is not int
                or not 0 < host_capacity_bytes <= 2**63 - 1):
            raise ValueError('Original native capacity projection is unavailable')
        capacity = holding._capacity_bytes()
        if capacity < _MEMORY_LIMIT or capacity - _MEMORY_LIMIT > host_capacity_bytes:
            raise ValueError('Original native holding exceeds its selected Host capacity')

    @contextmanager
    def _native_scope(self) -> Iterator[None]:
        holding: _NativeHoldingLease | None = getattr(self, '_physical_holding', None)
        if holding is None:
            yield
        else:
            with holding._scope():
                yield

    def _call(self, family: str, name: str, *arguments: int) -> int:
        if self._closed or self._retired:
            raise RuntimeError('Local Core is closed')
        if self._invoking:
            raise RuntimeError('Local Core callbacks cannot reenter the instance')
        if getattr(self, '_ordinary_host', False) and self._host_fuel_phase is None:
            raise RuntimeError('Local Core requires its admitted Host operation')
        self._invoking = True
        try:
            with self._native_scope():
                observation = getattr(self, '_physical_vm_observation', None)
                if observation is not None:
                    observation._require_core_current()
                result = self._exports[f'actql_{family}_{name}'](
                    self._store, self._nonce, *arguments)
        except BaseException:
            # The Core may already own the original invocation/ticket. Block
            # new work while retaining this instance for explicit retirement.
            self._closing = True
            raise
        finally:
            self._invoking = False
        if type(result) is not int:
            raise RuntimeError('Invalid Local Core scalar response')
        return result

    @contextmanager
    def _host_operation(self, *, initial: bool = False) -> Iterator[None]:
        """One outer operation; internal calls never replenish its fuel.

        The initial factory continues the constructor's original allowance.
        A failed operation fences normal work; only explicit original cleanup
        may obtain its independent finite allowance afterwards.
        """
        if not getattr(self, '_ordinary_host', False):
            yield
            return
        with self._lock:
            if self._host_fuel_phase is not None or self._invoking:
                raise RuntimeError('Original Host operation is already active')
            if self._closed or self._retired or self._closing:
                raise RuntimeError('Original Host normal work is fenced')
            sequence = getattr(self, '_host_operation_sequence', 0)
            if type(sequence) is not int or not 0 <= sequence < 2**63 - 1:
                raise RuntimeError('Original Host operation observation identity exhausted')
            if initial:
                if self._host_initial_claimed:
                    raise RuntimeError('Original Host bootstrap was already attempted')
                self._host_initial_claimed = True
            else:
                self._store.set_fuel(_NORMAL_HOST_OPERATION_FUEL)
            self._host_operation_sequence = sequence + 1
            self._host_operation_id = sequence + 1
            self._host_fuel_phase = 'operation'
        try:
            yield
        finally:
            with self._lock:
                self._host_operation_id = 0
                self._host_fuel_phase = None

    @contextmanager
    def _host_cleanup(self) -> Iterator[None]:
        """Same-original close only; joining never refreshes an active scope."""
        if not getattr(self, '_ordinary_host', False) or self._closed or self._store is None:
            yield
            return
        with self._lock:
            if self._invoking:
                raise RuntimeError('Original Host callback cannot start cleanup')
            joined = self._host_fuel_phase is not None
            self._host_cleanup_depth = getattr(self, '_host_cleanup_depth', 0) + 1
            if not joined:
                self._store.set_fuel(_NORMAL_HOST_CLEANUP_FUEL)
                self._host_fuel_phase = 'cleanup'
        try:
            yield
        finally:
            with self._lock:
                self._host_cleanup_depth -= 1
                if not joined:
                    self._host_fuel_phase = None

    @staticmethod
    def _check(operation: str, code: int) -> None:
        if code != 0:
            raise LocalCoreError(operation, code)

    def _read(self, ticket: int, index: int) -> int:
        value = self._inputs.get(ticket)
        if value is None or not 0 <= index < len(value.payload):
            return -1
        return value.payload[index]

    def _native_settled(self, handle: int) -> int:
        return self._native_fact(handle, 0)

    def _native_stopped(self, handle: int) -> int:
        return self._native_fact(handle, 1)

    def _native_cleaned(self, handle: int) -> int:
        return self._native_fact(handle, 2)

    def _native_fact(self, handle: int, fact: int) -> int:
        # Physical exceptions, truthy values and unknown handles are not facts.
        observers = self._native_observers.get(handle)
        if observers is None:
            return 1
        try:
            return 0 if observers[fact]() is True else 1
        except BaseException:
            return 1

    def _input_copy_bytes(self, payload: bytes) -> int:
        original = sys.getsizeof(payload)
        if not getattr(self, '_ordinary_host', False):
            return original
        # Memory.write receives a bytearray, so it makes no hidden second
        # payload copy. The temporary is bounded and charged before fill.
        return original + min(16384, len(payload)) + sys.getsizeof(bytearray())

    def _output_copy_bytes(self, limit: int) -> int:
        complete = 2 * limit + sys.getsizeof(bytearray()) + sys.getsizeof(b'')
        if not getattr(self, '_ordinary_host', False):
            return complete
        # At small bounds, Memory.read's bytearray and its immutable block can
        # overlap the destination. Charge that actual peak, not just two full
        # outputs; large outputs already have the larger final-copy allowance.
        block = (limit + 2 * min(16384, limit)
                 + 2 * sys.getsizeof(bytearray()) + sys.getsizeof(b''))
        return max(complete, block)

    def _bulk_memory_current(self, memory: Any) -> None:
        # This is the same entered instance's fixed linear memory. No address
        # or view escapes the synchronous copy or replaces its original loan.
        if (self._closing or self._closed or self._retired
                or self._exports.get('memory') is not memory):
            raise ValueError('Foreign or retired original Local transfer memory')
        observation = getattr(self, '_physical_vm_observation', None)
        if observation is not None:
            observation._require_core_current()

    def _bulk_memory(self, caller: Any, offset: int, length: int) -> Any:
        memory = self._exports.get('memory')
        self._bulk_memory_current(memory)
        actual = caller.get('memory')
        if (memory is None or actual is None
                or type(offset) is not int or offset < 0
                or type(length) is not int or not 0 < length <= 16384
                or cast(actual.data_ptr(caller), c_void_p).value !=
                   cast(memory.data_ptr(self._store), c_void_p).value):
            raise ValueError('Foreign or invalid original Local transfer memory')
        size = actual.data_len(caller)
        if size > _MEMORY_LIMIT or offset > size or length > size - offset:
            raise ValueError('Original Local transfer exceeds its memory')
        return memory

    def _input_copy(self, caller: Any, ticket: int, start: int,
                    offset: int, length: int) -> int:
        physical = self._inputs.get(ticket)
        if physical is None:
            return -5
        try:
            original = physical.payload
            memory = self._bulk_memory(caller, offset, length)
            if (type(start) is not int or start < 0 or start > len(original)
                    or length > len(original) - start):
                return -5
            payload = bytearray(memoryview(original)[start:start + length])
            copied = memory.write(caller, payload, offset)
            self._bulk_memory_current(memory)
            if (self._inputs.get(ticket) is not physical or physical.payload is not original
                    or copied != length):
                return -5
            return length
        except BaseException:
            return -5

    def _read_output_block(self, value: _Output, start: int, length: int) -> bytes:
        with self._native_scope():
            self._owned_output(value, value.family)
            physical = self._inputs.get(value.ticket)
            memory = self._exports.get('memory')
            self._bulk_memory_current(memory)
            if (physical is None or type(start) is not int or start < 0
                    or type(length) is not int or not 0 < length <= 16384):
                raise ValueError('Invalid original Local output block')
            offset = self._call('buffer', 'read_block', value.handle, start, length)
            size = memory.data_len(self._store)
            if (size > _MEMORY_LIMIT or offset < 0 or offset > size
                    or length > size - offset):
                raise LocalCoreError('projection_block', offset)
            raw = bytes(memory.read(self._store, offset, offset + length))
            self._bulk_memory_current(memory)
            self._owned_output(value, value.family)
            if self._inputs.get(value.ticket) is not physical or len(raw) != length:
                raise LocalCoreError('projection_block', -5)
            return raw

    def _journal_query_copy(self, caller: Any, ticket: int, index: int,
                            offset: int, length: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        if callbacks is None:
            return -41
        try:
            memory = self._bulk_memory(caller, offset, length)
            raw = bytes(memory.read(caller, offset, offset + length))
            self._bulk_memory_current(memory)
            if self._journal_callbacks(ticket) is not callbacks or len(raw) != length:
                raise ValueError('Original Local query transfer changed')
            return callbacks.query_copy(index, raw)
        except BaseException as error:
            return callbacks._fail(error)

    def _journal_copy(self, caller: Any, ticket: int, field: int, index: int,
                      offset: int, length: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        if callbacks is None:
            return -41
        try:
            memory = self._bulk_memory(caller, offset, length)
            original = callbacks.row
            raw = callbacks.row_copy(field, index, length)
            copied = memory.write(caller, raw, offset)
            self._bulk_memory_current(memory)
            if (self._journal_callbacks(ticket) is not callbacks or callbacks.row is not original
                    or len(raw) != length or copied != length):
                raise ValueError('Original Local row transfer changed')
            return length
        except BaseException as error:
            return callbacks._fail(error)

    def _publisher_copy(self, caller: Any, ticket: int, index: int,
                        offset: int, length: int) -> int:
        callbacks = self._publisher_callbacks(ticket)
        if callbacks is None or callbacks.buffer is None:
            return -2
        try:
            original = callbacks.buffer
            memory = self._bulk_memory(caller, offset, length)
            if (type(index) is not int or index != callbacks.received or index < 0
                    or index > len(original) or length > len(original) - index):
                return -2
            raw = bytes(memory.read(caller, offset, offset + length))
            self._bulk_memory_current(memory)
            if (self._publisher_callbacks(ticket) is not callbacks
                    or callbacks.buffer is not original or callbacks.received != index
                    or len(raw) != length):
                return -2
            original[index:index + length] = raw
            callbacks.received += length
            return length
        except BaseException:
            return -2

    def _journal_callbacks(self, ticket: int) -> _JournalCallbacks | None:
        value = self._inputs.get(ticket)
        return None if value is None else value.journal

    def _journal_current(self, ticket: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -41 if callbacks is None else callbacks.check_current()

    def _journal_schema(self, ticket: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -41 if callbacks is None else callbacks.schema()

    def _journal_current_operation(self, ticket: int) -> int:
        """Fresh original current plus this entered Host operation's DATA.

        Zero selects complete original observation for raw/cleanup callers.
        It is not an Allow, permission cache, reader handle or continuation.
        """
        callbacks = self._journal_callbacks(ticket)
        if callbacks is None or callbacks.failure is not None:
            return -41
        loan = self._loans.get(ticket)
        if type(loan) is not _Output or loan.family != 'current':
            return -41
        try:
            self._owned_output(loan, 'current')
        except ValueError:
            return -41
        if (not getattr(self, '_ordinary_host', False)
                or self._host_fuel_phase != 'operation'
                or getattr(self, '_host_cleanup_depth', 0) != 0
                or self._closing or self._closed or self._retired):
            return 0 if callbacks.check_current() == 0 else -41
        # Only the standard original receiver has completed the full physical
        # singleton/settings fence in this very reader. Other private/raw
        # suppliers keep Core's complete observation path, never an error fallback.
        from ._local_host_binding import OriginalHostBinding
        receiver = getattr(callbacks.current, '__self__', None)
        if (type(receiver) is not OriginalHostBinding
                or callbacks.current is not receiver._current_observer):
            return 0 if callbacks.check_current() == 0 else -41
        try:
            # This checks the SAME reader's complete required SQL fences and
            # original physical current together. A preceding check_current
            # would repeat that same observation before this synchronous call.
            receiver._require_observation_frame(self, loan, callbacks.reader)
        except BaseException as error:
            return callbacks._fail(error)
        operation = getattr(self, '_host_operation_id', 0)
        if (not self._invoking or type(operation) is not int
                or not 0 < operation < 2**63
                or operation != self._host_operation_sequence):
            return -41
        return operation

    def _journal_begin(self, ticket: int, mode: int, namespace_bytes: int, key_bytes: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -41 if callbacks is None else callbacks.begin(mode, namespace_bytes, key_bytes)

    def _journal_query_byte(self, ticket: int, index: int, byte: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -41 if callbacks is None else callbacks.byte(index, byte)

    def _journal_query(self, ticket: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -41 if callbacks is None else callbacks.query()

    def _journal_length(self, ticket: int, field: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -41 if callbacks is None else callbacks.length(field)

    def _journal_byte(self, ticket: int, field: int, index: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -41 if callbacks is None else callbacks.row_byte(field, index)

    def _journal_revision(self, ticket: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -1 if callbacks is None else callbacks.revision()

    def _journal_release(self, ticket: int) -> int:
        callbacks = self._journal_callbacks(ticket)
        return -41 if callbacks is None else callbacks.release()

    def reserve_host_current(self, source: _Input, *, store: LocalByteStore,
                             current: Callable[[], object], cleanup: Callable[[], bool]) -> _Output:
        """Retain actual original bytes and one same-Store physical callback ticket.

        Only Core inspects adoption and issues original current scope metadata.
        The trusted Host current port checks retained filesystem/settings/epoch
        and generation facts; it cannot return a caller permission boolean.
        """
        with self._lock:
            self._owned_input(source)
            if (self._closing or type(store) is not LocalByteStore
                    or not callable(current) or not callable(cleanup)):
                raise ValueError('Invalid original Local current reservation')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            callbacks = _JournalCallbacks(current, store)

            def retire() -> bool:
                if callbacks.reader is not None or cleanup() is not True:
                    return False
                callbacks.release()
                return True

            self._inputs[ticket] = _PhysicalInput(b'', retire, lambda _: True, journal=callbacks)
            limit = source.length + 256
            allowance = (2 * limit + 2 * 262144 + 4096 + sys.getsizeof(callbacks)
                         + sys.getsizeof(self._inputs[ticket]))
            handle = self._call('current', 'reserve', source.handle, ticket, allowance)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_host_current', handle)
            value = _Output(self._identity, ticket, handle, limit, 'current')
            self._loans[ticket] = value
            return value

    @contextmanager
    def host_current_frame(self, value: _Output, reader: _NamespaceReader) -> Iterator[None]:
        """Use this ticket only inside the original transaction/thread loan.

        No reader survives the frame. Failure retains its original callback
        cause and query copies for explicit cleanup. The frame does not begin,
        commit, rollback, adopt, authorize or repair the physical transaction.
        """
        with self._lock:
            self._owned_output(value, 'current')
            callbacks = self._journal_callbacks(value.ticket)
            if (self._closing or type(reader) is not _NamespaceReader or callbacks is None
                    or reader.owner is not callbacks.store or callbacks.reader is not None
                    or callbacks.failure is not None):
                raise ValueError('Invalid original Local current transaction loan')
            callbacks.reader = reader
            try:
                if callbacks.check_current() != 0:
                    assert callbacks.failure is not None
                    raise callbacks.failure
                yield
                if callbacks.failure is not None:
                    raise callbacks.failure
            except Exception as error:
                if callbacks.failure is not None and callbacks.failure is not error:
                    raise callbacks.failure from error
                raise
            finally:
                callbacks.reader = None

    def _host_current_ready(self, value: _Output) -> _JournalCallbacks:
        self._owned_output(value, 'current')
        callbacks = self._journal_callbacks(value.ticket)
        if callbacks is None or callbacks.reader is None or self._closing:
            raise ValueError('Original Local current frame is unavailable')
        if callbacks.check_current() != 0:
            assert callbacks.failure is not None
            raise callbacks.failure
        return callbacks

    def _host_current_call(self, value: _Output, operation: str) -> None:
        with self._lock:
            callbacks = self._host_current_ready(value)
            code = self._call('current', operation, value.handle)
            if callbacks.failure is not None:
                raise callbacks.failure
            self._check('host_current_' + operation, code)

    def bind_host_current(self, value: _Output) -> None:
        self._host_current_call(value, 'bind')

    def produce_host_current(self, value: _Output) -> None:
        self._host_current_call(value, 'produce')

    def validate_host_current(self, value: _Output) -> None:
        self._host_current_call(value, 'validate')

    def read_host_current(self, value: _Output) -> bytes:
        with self._lock:
            self.validate_host_current(value)
            result = self._read_output(value, 'current', 'length')
            self.validate_host_current(value)
            return result

    def close_host_current(self, value: _Output) -> bool:
        return self._close_output(value, 'current', 'close')

    def reserve_journal_observation(self, material: _Output, current_configuration: int, *,
                                    store: LocalByteStore, current: Callable[[], object],
                                    cleanup: Callable[[], bool]) -> _Output:
        """Retain one original same-Store callback loan; no admission/ACK is issued.

        Call inspect_journal_observation inside the original fenced SQLite
        callback while holding Core before Store. SQLite/Core parser workspace
        and original retained inputs need their existing separate reservations.
        """
        with self._lock:
            self._owned_output(material, 'material')
            if (self._closing or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31
                    or type(store) is not LocalByteStore
                    or not callable(current) or not callable(cleanup)):
                raise ValueError('Invalid original Local journal observation')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            callbacks = _JournalCallbacks(current, store)

            def retire() -> bool:
                if cleanup() is not True:
                    return False
                callbacks.release()
                callbacks.reader = None
                return True

            self._inputs[ticket] = _PhysicalInput(b'', retire, lambda _: True,
                                                 journal=callbacks)
            limit = 1_048_576
            # Concurrent raw row/key and request/decode copies, bounded before
            # the physical query; this is not a global Python/SQLite memory claim.
            allowance = (2 * limit + 4096 + sys.getsizeof(callbacks)
                         + sys.getsizeof(self._inputs[ticket]))
            handle = self._call('journal', 'reserve', material.handle,
                                current_configuration, ticket, allowance)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_journal_observation', handle)
            value = _Output(self._identity, ticket, handle, limit, 'journal')
            self._loans[ticket] = value
            return value

    def inspect_journal_observation(self, value: _Output, reader: _NamespaceReader) -> None:
        """Invoke the original Core inspection within the same physical snapshot."""
        with self._lock:
            self._owned_output(value, 'journal')
            callbacks = self._journal_callbacks(value.ticket)
            if (self._closing or type(reader) is not _NamespaceReader or callbacks is None
                    or reader.owner is not callbacks.store
                    or callbacks.reader is not None or callbacks.failure is not None):
                raise ValueError('Invalid original Local journal transaction loan')
            callbacks.reader = reader
            try:
                code = self._call('journal', 'inspect', value.handle)
                if callbacks.failure is not None:
                    raise callbacks.failure
                self._check('inspect_journal_observation', code)
            finally:
                # No reader survives its transaction. Failed query copies stay
                # under the same buffer ticket until explicit successful cleanup.
                callbacks.reader = None

    def journal_observation_revisions(self, value: _Output, reader: _NamespaceReader) -> tuple[int, int, int]:
        """Read Core-observed revisions under a newly checked original snapshot.

        The Host rechecks original current/epoch/configuration fences. These
        revisions are not a COMMIT acknowledgement or permission to dispatch.
        """
        with self._lock:
            self._owned_output(value, 'journal')
            callbacks = self._journal_callbacks(value.ticket)
            if (self._closing or type(reader) is not _NamespaceReader or callbacks is None
                    or reader.owner is not callbacks.store
                    or callbacks.reader is not None or callbacks.failure is not None):
                raise ValueError('Invalid original Local journal transaction loan')
            callbacks.reader = reader
            try:
                result = tuple(self._call('journal', 'revision', value.handle, field) for field in range(3))
                if callbacks.failure is not None:
                    raise callbacks.failure
                if any(value < 0 for value in result):
                    raise LocalCoreError('journal_observation_revisions', -31)
                return result[0], result[1], result[2]
            finally:
                callbacks.reader = None

    def close_journal_observation(self, value: _Output) -> bool:
        return self._close_output(value, 'journal', 'close')

    def read_journal_admission(self, value: _Output, reader: _NamespaceReader) -> bytes:
        """Transfer Core's saved admission in the same original current frame.

        Core retains the original validated definition/request/revision. Cached
        transport bytes never bypass current checks or become a COMMIT ACK,
        dispatch permit, Result or permission to resend a Submission.
        """
        with self._lock:
            self._owned_output(value, 'journal')
            callbacks = self._journal_callbacks(value.ticket)
            if (self._closing or type(reader) is not _NamespaceReader or callbacks is None
                    or reader.owner is not callbacks.store
                    or callbacks.reader is not None or callbacks.failure is not None):
                raise ValueError('Invalid original Local journal transaction loan')
            callbacks.reader = reader
            try:
                # Validate before _read_output can return its physical cache.
                length = self._call('journal', 'admission_length', value.handle)
                if callbacks.failure is not None:
                    raise callbacks.failure
                if not 0 < length <= 4096:
                    raise LocalCoreError('journal_admission_length', length)
                result = self._read_output(value, 'journal', 'admission_length')
                final_length = self._call('journal', 'admission_length', value.handle)
                if callbacks.failure is not None:
                    raise callbacks.failure
                if final_length != length or len(result) != length:
                    raise LocalCoreError('journal_admission_length', final_length)
                return result
            finally:
                callbacks.reader = None

    def _publisher_callbacks(self, ticket: int) -> _PublisherCallbacks | None:
        value = self._inputs.get(ticket)
        return None if value is None else value.publisher

    def _publisher_current(self, ticket: int) -> int:
        callbacks = self._publisher_callbacks(ticket)
        if callbacks is None:
            return -2
        try:
            value = callbacks.current()
            return 0 if value is True else (-1 if value is False else -2)
        except BaseException:
            return -2

    def _publisher_begin(self, ticket: int, length: int) -> int:
        callbacks = self._publisher_callbacks(ticket)
        if (callbacks is None or callbacks.buffer is not None or type(length) is not int
                or not 0 < length <= _PUBLISHER_LIMIT):
            return -2
        # Core already holds the collector/decoder allowance in its buffer pool.
        try:
            callbacks.buffer = bytearray(length)
            callbacks.received = 0
        except BaseException:
            return -2
        return 0

    def _publisher_byte(self, ticket: int, index: int, byte: int) -> int:
        callbacks = self._publisher_callbacks(ticket)
        if (callbacks is None or callbacks.buffer is None or type(index) is not int
                or index != callbacks.received or not 0 <= index < len(callbacks.buffer)
                or type(byte) is not int or not 0 <= byte < 256):
            return -2
        callbacks.buffer[index] = byte
        callbacks.received += 1
        return 0

    def _publisher_finish(self, ticket: int) -> int:
        callbacks = self._publisher_callbacks(ticket)
        if callbacks is None or callbacks.buffer is None:
            return -2
        try:
            if callbacks.received != len(callbacks.buffer):
                return -2
            fact = _publisher_fact(callbacks.buffer)
            value = callbacks.authorize(fact)
            return 0 if value is True else (-1 if value is False else -2)
        except BaseException:
            return -2
        finally:
            # No successful grant or facts survive for reuse by another stage.
            callbacks.buffer = None
            callbacks.received = 0

    def reserve_publisher(self, preflight: _Output, request: _Input, *,
                          current: Callable[[], bool],
                          authorize: Callable[[_PublisherFact], bool],
                          cleanup: Callable[[], bool]) -> _Output:
        """Private trusted Host port, never a public SDK authorization option.

        The installed Host must supply its independent current publisher Owner
        bound to original Policy/target/Store. The existing Common Account port evaluates original/current publish
        separately from these physical fences. Callback-owned resources require
        their own reservations.
        """
        with self._lock:
            self._owned_output(preflight, 'publication_preflight')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if not all(callable(value) for value in (current, authorize, cleanup)):
                raise ValueError('Publisher requires trusted Host callbacks')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            callbacks = _PublisherCallbacks(current, authorize)
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True, callbacks)
            # Collector + UTF-8 decode + six Unicode strings + closed parser
            # containers, including overlap. This is not a global memory claim.
            allowance = (128 * _PUBLISHER_LIMIT + 4096 + sys.getsizeof(callbacks)
                         + sys.getsizeof(self._inputs[ticket]))
            handle = self._call('publisher', 'reserve', preflight.handle, request.handle,
                                ticket, allowance)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_publisher', handle)
            value = _Output(self._identity, ticket, handle, _PUBLISHER_LIMIT, 'publisher')
            self._loans[ticket] = value
            return value

    def install_publisher(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'publisher')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publisher configuration')
            self._check('install_publisher', self._call(
                'publisher', 'install', value.handle, current_configuration))

    def authorize_publisher(self, value: _Output, current_configuration: int, *,
                            stage: str, publication: _Output | None = None) -> None:
        """Check original stage permission; neither commit nor acknowledge Store."""
        with self._lock:
            self._owned_output(value, 'publisher')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            stages = {'request': 0, 'commit': 1, 'return_committed': 2}
            if (type(current_configuration) is not int or not 0 < current_configuration < 2**31
                    or type(stage) is not str or stage not in stages
                    or ((stage == 'request') != (publication is None))):
                raise ValueError('Invalid original publisher stage')
            if publication is not None:
                self._owned_output(publication, 'publication')
            self._check('authorize_publisher', self._call(
                'publisher', 'authorize', value.handle, current_configuration,
                stages[stage], 0 if publication is None else publication.handle))

    def close_publisher(self, value: _Output) -> bool:
        with self._lock:
            self._owned_output(value, 'publisher')
            code = self._call('publisher', 'close', value.handle)
            if code == -9:
                return False
            self._check('close_publisher', code)
            self._loans.pop(value.ticket)
            self._released.discard(value.ticket)
            return True

    def _cleanup(self, ticket: int) -> int:
        if ticket in self._released:
            return 0
        value = self._inputs.get(ticket)
        if value is None:
            return 1
        try:
            complete = value.cleanup() is True
        except Exception:
            return 1
        if not complete:
            return 1
        # Keep the physical completion fact until Core confirms retirement.
        # A trap after this callback must not repeat cleanup or lose custody.
        self._released.add(ticket)
        del self._inputs[ticket]
        return 0

    def _stopped(self, ticket: int, reader: int) -> int:
        value = self._inputs.get(ticket)
        if value is None:
            return 1
        try:
            return 0 if value.stopped(reader) is True else 1
        except Exception:
            return 1

    def reserve_input(self, payload: bytes, *, cleanup: Callable[[], bool],
                      stopped: Callable[[int], bool]) -> _Input:
        """Issue custody before transfer. Neither callback starts physical IO."""
        with self._lock:
            if self._closing or type(payload) is not bytes:
                raise ValueError('Local Core requires open immutable byte input')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            # Register callbacks before crossing Wasm. A trap cannot cause a
            # physical ticket to disappear while the Core may still own it.
            self._inputs[ticket] = _PhysicalInput(payload, cleanup, stopped)
            handle = self._call('buffer', 'reserve', ticket, len(payload),
                                self._input_copy_bytes(payload))
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve', handle)
            value = _Input(self._identity, ticket, handle, len(payload))
            self._loans[ticket] = value
            return value

    def _owned(self, value: _Input | _Output | _Workspace) -> None:
        if (type(value) not in (_Input, _Output, _Workspace) or
                value.owner is not self._identity or
                self._loans.get(value.ticket) is not value):
            raise ValueError('Foreign or released Local input')

    def _owned_output(self, value: _Output, family: str = "material") -> None:
        self._owned(value)
        if type(value) is not _Output or value.family != family:
            raise ValueError('Local projection requires the matching output loan')

    def _owned_input(self, value: _Input) -> None:
        self._owned(value)
        if type(value) is not _Input:
            raise ValueError('Local transfer requires an input loan')

    def dispatch_action(self, run: int, current_configuration: int, facts: _Input) -> int:
        """Project the existing Owner decision; no durable reservation or I/O."""
        with self._lock:
            self._owned_input(facts)
            if (self._closing or type(run) is not int or not 0 < run < 2**31
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid Local dispatch projection')
            action = self._call('run', 'dispatch_action', run, current_configuration, facts.handle)
            if type(action) is not int or action not in (1, 2):
                raise LocalCoreError('dispatch_action', action)
            return action

    def reserve_workspace(self, bytes: int, *, stopped: Callable[[], bool],
                          cleanup: Callable[[], bool]) -> _Workspace:
        """Reserve before physical allocation; this loan permits no Run I/O."""
        with self._lock:
            if (self._closing or type(bytes) is not int or not 0 < bytes <= 2**63 - 1
                    or not callable(stopped) or not callable(cleanup)):
                raise ValueError('Invalid Local physical workspace reservation')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: stopped())
            handle = self._call('workspace', 'reserve', ticket, bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_workspace', handle)
            value = _Workspace(self._identity, ticket, handle)
            self._loans[ticket] = value
            return value

    def close_workspace(self, value: _Workspace) -> bool:
        with self._lock:
            self._owned(value)
            if type(value) is not _Workspace:
                raise ValueError('Local workspace requires its exact loan')
            code = self._call('workspace', 'close', value.handle)
            if code == -9:
                return False
            self._check('close_workspace', code)
            self._loans.pop(value.ticket)
            self._released.discard(value.ticket)
            return True

    def reserve_submission_projection(self, configuration: int, source: _Input,
                                      kind: int, *, cleanup: Callable[[], bool]) -> _Output:
        """Retain one Core epoch/identity projection, never execution permission."""
        with self._lock:
            self._owned_input(source)
            if (self._closing or type(configuration) is not int or
                    not 0 < configuration < 2**31 or type(kind) is not int or kind not in (1, 2, 3, 4, 5, 6, 7, 8)):
                raise ValueError('Invalid Local Submission projection')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1048576 if kind in (3, 4, 5, 6, 7, 8) else 4096
            family = ('submission_append' if kind == 3 else
                      'submission_lookup' if kind in (4, 5, 6, 7, 8) else 'submission')
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, family)))
            handle = self._call('submission', 'reserve', configuration, source.handle,
                                kind, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_submission_projection', handle)
            value = _Output(self._identity, ticket, handle, limit, family)
            self._loans[ticket] = value
            return value

    def reserve_client_check(self, environment: int, configuration: int, source: _Input,
                             kind: int, *, cleanup: Callable[[], bool]) -> _Output:
        """Retain same-Host reporting custody before the actual Common call."""
        with self._lock:
            self._owned_input(source)
            if (self._closing or type(environment) is not int or not 0 < environment < 2**31
                    or type(configuration) is not int or not 0 < configuration < 2**31
                    or type(kind) is not int or kind not in (0, 1) or not callable(cleanup)):
                raise ValueError('Invalid original Local Check reservation')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            allowance = (self._output_copy_bytes(limit)
                         + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'check')))
            handle = self._call('check', 'reserve', environment, configuration,
                                source.handle, kind, ticket, allowance)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_client_check', handle)
            value = _Output(self._identity, ticket, handle, limit, 'check')
            self._loans[ticket] = value
            return value

    def produce_client_check(self, value: _Output, current: _Output) -> None:
        with self._lock:
            self._owned_output(value, 'check')
            self._host_current_ready(current)
            self._check('current_client_check', self._call(
                'check', 'current', value.handle, current.handle))
            self._check('produce_client_check', self._call('check', 'produce', value.handle))

    def read_client_check(self, value: _Output, current: _Output) -> bytes:
        with self._lock:
            self._host_current_ready(current)
            self._owned_output(value, 'check')
            self._check('current_client_check', self._call(
                'check', 'current', value.handle, current.handle))
            raw = self._read_output(value, 'check', 'length')
            self._check('current_client_check', self._call(
                'check', 'current', value.handle, current.handle))
            return raw

    def close_client_check(self, value: _Output) -> bool:
        return self._close_output(value, 'check', 'close')

    def reserve_bootstrap(self, source: _Input, *, cleanup: Callable[[], bool]) -> _Output:
        """Borrow original root/clock bytes for first-adoption metadata only.

        The existing Common factory supplies policy/engine originals. This
        performs no adoption, writes, authority, Run admission or execution.
        The Host must restore saved originals instead of calling this again.
        """
        return self._reserve_bootstrap(source, cleanup=cleanup, sdk=False)

    def reserve_sdk_bootstrap(self, source: _Input, *, cleanup: Callable[[], bool]) -> _Output:
        """Explicit first-install metadata; never upgrade an adopted Host."""
        return self._reserve_bootstrap(source, cleanup=cleanup, sdk=True)

    def _reserve_bootstrap(self, source: _Input, *, cleanup: Callable[[], bool], sdk: bool) -> _Output:
        with self._lock:
            self._owned_input(source)
            if self._closing or not callable(cleanup):
                raise ValueError('Invalid Local bootstrap reservation')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'bootstrap')))
            handle = self._call('bootstrap', 'reserve', source.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_bootstrap', handle)
            value = _Output(self._identity, ticket, handle, limit, 'bootstrap_sdk' if sdk else 'bootstrap')
            self._loans[ticket] = value
            return value

    def reserve_original_metadata(self, source: _Input, kind: int, *, cleanup: Callable[[], bool]) -> _Output:
        """Retain original physical observations before the existing Core codec.

        Kind selects initialization/configuration custody/journal custody/selected
        settings metadata. Core emits their exact original bodies and CIDs. No
        method initializes a Host, commits, authorizes or begins a Run.
        """
        with self._lock:
            self._owned_input(source)
            if self._closing or type(kind) is not int or kind not in (1, 2, 3, 4) or not callable(cleanup):
                raise ValueError('Invalid Local original metadata reservation')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'original')))
            handle = self._call('original', 'reserve', source.handle, kind, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_original_metadata', handle)
            value = _Output(self._identity, ticket, handle, limit, 'original')
            self._loans[ticket] = value
            return value

    def produce_original_metadata(self, value: _Output) -> None:
        self._produce_output(value, 'original', 'produce')

    def read_original_metadata(self, value: _Output) -> bytes:
        return self._read_output(value, 'original', 'length')

    def close_original_metadata(self, value: _Output) -> bool:
        return self._close_output(value, 'original', 'close')

    def produce_bootstrap(self, value: _Output) -> None:
        self._produce_output(value, 'bootstrap', 'produce')

    def read_bootstrap(self, value: _Output) -> bytes:
        return self._read_output(value, 'bootstrap', 'length')

    def close_bootstrap(self, value: _Output) -> bool:
        return self._close_output(value, 'bootstrap', 'close')

    def produce_sdk_bootstrap(self, value: _Output) -> None:
        with self._lock:
            self._owned_output(value, 'bootstrap_sdk')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            self._check('produce_sdk_bootstrap', self._call('bootstrap', 'produce_sdk', value.handle))

    def read_sdk_bootstrap(self, value: _Output) -> bytes:
        return self._read_output(value, 'bootstrap_sdk', 'length', abi_family='bootstrap')

    def close_sdk_bootstrap(self, value: _Output) -> bool:
        return self._close_output(value, 'bootstrap_sdk', 'close', abi_family='bootstrap')

    def produce_submission_projection(self, value: _Output) -> None:
        self._produce_output(value, 'submission', 'produce')

    def read_submission_projection(self, value: _Output) -> bytes:
        return self._read_output(value, 'submission', 'length')

    def close_submission_projection(self, value: _Output) -> bool:
        return self._close_output(value, 'submission', 'close')

    def produce_submission_append(self, value: _Output, current: _Output) -> None:
        """Inspect original rows in the current Store snapshot; never write/ACK."""
        with self._lock:
            self._owned_output(value, 'submission_append')
            callbacks = self._host_current_ready(current)
            code = self._call('submission', 'produce', value.handle)
            if callbacks.failure is not None:
                raise callbacks.failure
            self._check('produce_submission_append', code)
            self.validate_submission_append(value, current)

    def validate_submission_append(self, value: _Output, current: _Output) -> None:
        """Reinspect the same original candidate before cache or physical CAS."""
        with self._lock:
            self._owned_output(value, 'submission_append')
            callbacks = self._host_current_ready(current)
            code = self._call('submission', 'validate_append', value.handle, current.handle)
            if callbacks.failure is not None:
                raise callbacks.failure
            self._check('validate_submission_append', code)

    def read_submission_append(self, value: _Output, current: _Output) -> bytes:
        with self._lock:
            self.validate_submission_append(value, current)
            result = self._read_output(value, 'submission_append', 'length', abi_family='submission')
            self.validate_submission_append(value, current)
            return result

    def close_submission_append(self, value: _Output) -> bool:
        return self._close_output(value, 'submission_append', 'close', abi_family='submission')

    def produce_submission_lookup(self, value: _Output, current: _Output) -> None:
        """Read only the original history in the same current Store snapshot."""
        with self._lock:
            self._owned_output(value, 'submission_lookup')
            callbacks = self._host_current_ready(current)
            code = self._call('submission', 'produce', value.handle)
            if callbacks.failure is not None:
                raise callbacks.failure
            self._check('produce_submission_lookup', code)
            self.validate_submission_lookup(value, current)

    def validate_submission_lookup(self, value: _Output, current: _Output) -> None:
        with self._lock:
            self._owned_output(value, 'submission_lookup')
            callbacks = self._host_current_ready(current)
            code = self._call('submission', 'validate_append', value.handle, current.handle)
            if callbacks.failure is not None:
                raise callbacks.failure
            self._check('validate_submission_lookup', code)

    def read_submission_lookup(self, value: _Output, current: _Output) -> bytes:
        with self._lock:
            self.validate_submission_lookup(value, current)
            raw = self._read_output(value, 'submission_lookup', 'length', abi_family='submission')
            self.validate_submission_lookup(value, current)
            return raw

    def produce_and_read_submission_lookup(self, value: _Output, current: _Output) -> bytes:
        """One synchronous handoff in the same original Host read snapshot.

        Production's postcheck is also the adjacent transfer precheck. The
        standalone methods keep their contracts; post-copy validation remains.
        No successful validation is retained or reused by another operation.
        """
        with self._lock:
            self.produce_submission_lookup(value, current)
            raw = self._read_output(value, 'submission_lookup', 'length', abi_family='submission')
            self.validate_submission_lookup(value, current)
            return raw

    def close_submission_lookup(self, value: _Output) -> bool:
        return self._close_output(value, 'submission_lookup', 'close', abi_family='submission')

    def retire_submission_append_output(self, value: _Output) -> bool:
        """Retire transport while Core retains original input/Run relationships."""
        with self._lock:
            self._owned_output(value, 'submission_append')
            code = self._call('submission', 'retire_output', value.handle)
            if code == -9:
                return False
            self._check('retire_submission_append_output', code)
            return True

    def reserve_source_publication(self, compute: _Compute, source: _Input, *,
                                   cleanup: Callable[[], bool]) -> _Output:
        """Borrow the original acquisition; never fetch it or publish a Run."""
        return self._reserve_invocation_output(
            compute, source, cleanup, 'source_publication', 'reserve')

    def reserve_source_free_invocation(self, compute: _Compute, source: _Input, *,
                                        cleanup: Callable[[], bool]) -> _Output:
        """Borrow the original Compute/input; Core issues the formal invocation."""
        return self._reserve_invocation_output(
            compute, source, cleanup, 'run_invocation', 'reserve_source_free')

    def _reserve_invocation_output(self, compute: _Compute, source: _Input,
                                   cleanup: Callable[[], bool], family: str,
                                   operation: str) -> _Output:
        with self._lock:
            self._owned_compute(compute)
            self._owned_input(source)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65_536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, family)))
            handle = self._call(family, operation, compute.handle, source.handle,
                                ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError(operation, handle)
            value = _Output(self._identity, ticket, handle, limit, family)
            self._loans[ticket] = value
            return value

    def prepare_source_publication(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'source_publication')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current Source publication configuration')
            self._check('prepare_source_publication', self._call(
                'source_publication', 'prepare', value.handle, current_configuration))

    def advance_source_publication(self, value: _Output, quantum: int) -> LocalResultProgress:
        if type(quantum) is not int or not 0 < quantum <= 2**31 - 1:
            raise ValueError('Invalid Local Source identity quantum')
        with self._lock:
            self._owned_output(value, 'source_publication')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            self._check('advance_source_publication', self._call(
                'source_publication', 'advance', value.handle, quantum))
            ready = self._call('source_publication', 'progress', value.handle, 0)
            work = self._call('source_publication', 'progress', value.handle, 1)
            if ready not in (0, 1) or not 0 <= work <= quantum:
                raise LocalCoreError('source_publication_progress', -33)
            return LocalResultProgress(ready == 1, work)

    def source_publication_work(self, value: _Output) -> int:
        with self._lock:
            self._owned_output(value, 'source_publication')
            work = self._call('source_publication', 'progress', value.handle, 2)
            if work < 0:
                raise LocalCoreError('source_publication_work', work)
            return work

    def finish_source_publication(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'source_publication')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current Source publication configuration')
            self._check('finish_source_publication', self._call(
                'source_publication', 'finish', value.handle, current_configuration))

    def read_source_publication(self, value: _Output) -> bytes:
        return self._read_output(value, 'source_publication', 'length')

    def close_source_publication(self, value: _Output) -> bool:
        return self._close_output(value, 'source_publication', 'close')

    def prepare_source_free_invocation(self, value: _Output,
                                       current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'run_invocation')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current invocation configuration')
            self._check('prepare_source_free_invocation', self._call(
                'run_invocation', 'prepare_source_free', value.handle, current_configuration))

    def read_source_free_invocation(self, value: _Output) -> bytes:
        return self._read_output(value, 'run_invocation', 'length_source_free')

    def close_source_free_invocation(self, value: _Output) -> bool:
        return self._close_output(value, 'run_invocation', 'close_source_free')

    def _owned_invocation_output(self, value: _Output) -> None:
        self._owned(value)
        if type(value) is not _Output or value.family not in ('source_publication', 'run_invocation'):
            raise ValueError('Local publication requires the original invocation loan')

    def reserve_publication_preflight(self, source: _Output, request: _Input, *,
                                      cleanup: Callable[[], bool]) -> _Output:
        """Private original intent before Compute; grants no Store permission."""
        with self._lock:
            self._owned_invocation_output(source)
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'publication_preflight')))
            handle = self._call('publication_preflight', 'reserve', source.handle,
                                request.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_publication_preflight', handle)
            value = _Output(self._identity, ticket, handle, limit, 'publication_preflight')
            self._loans[ticket] = value
            return value

    def prepare_publication_preflight(self, value: _Output,
                                      current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'publication_preflight')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current preflight configuration')
            self._check('prepare_publication_preflight', self._call(
                'publication_preflight', 'prepare', value.handle, current_configuration))

    def publication_preflight_result_count(self, value: _Output, current_configuration: int) -> int:
        with self._lock:
            self._owned_output(value, 'publication_preflight')
            if (self._closing or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK preflight configuration')
            count = self._call('publication_preflight', 'result_count', value.handle,
                               current_configuration)
            if type(count) is not int or not 0 < count < 2**31:
                raise LocalCoreError('preflight_result_count', count if type(count) is int else -33)
            return count

    def read_publication_preflight(self, value: _Output) -> bytes:
        return self._read_output(value, 'publication_preflight', 'length')

    def retire_publication_preflight_output(self, value: _Output) -> bool:
        """Retire copied output, retaining the original semantic preflight loan."""
        with self._lock:
            self._owned_output(value, 'publication_preflight')
            code = self._call('publication_preflight', 'retire_output', value.handle)
            if code == -9:
                return False
            self._check('retire_publication_preflight_output', code)
            return True

    def close_publication_preflight(self, value: _Output) -> bool:
        return self._close_output(value, 'publication_preflight', 'close')

    def reserve_publication(self, source: _Output, request: _Input, *,
                            cleanup: Callable[[], bool]) -> _Output:
        """Private complete Result capture; not a durable publication commit."""
        with self._lock:
            self._owned_invocation_output(source)
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'publication')))
            handle = self._call('publication', 'reserve', source.handle, request.handle,
                                ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_publication', handle)
            value = _Output(self._identity, ticket, handle, limit, 'publication')
            self._loans[ticket] = value
            return value

    def _publication_configuration(self, value: _Output, current_configuration: int) -> None:
        self._owned_output(value, 'publication')
        if self._closing:
            raise RuntimeError('Local Core is closing')
        if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
            raise ValueError('Invalid current publication configuration')

    def validate_publication_run(self, value: _Output, original_run: int,
                                 current_configuration: int) -> None:
        """Check the Core publication's original Run loan; no read or ACK grant."""
        with self._lock:
            self._publication_configuration(value, current_configuration)
            if type(original_run) is not int or not 0 < original_run < 2**31:
                raise ValueError('Invalid original publication Run')
            self._check('validate_publication_run', self._call(
                'publication', 'validate_run', value.handle, original_run,
                current_configuration))

    def prepare_publication(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._check('prepare_publication', self._call(
                'publication', 'prepare', value.handle, current_configuration))

    def advance_publication(self, value: _Output, current_configuration: int,
                            quantum: int) -> LocalResultProgress:
        if type(quantum) is not int or not 0 < quantum <= 2**31 - 1:
            raise ValueError('Invalid Local publication quantum')
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._check('advance_publication', self._call(
                'publication', 'advance', value.handle, current_configuration, quantum))
            ready = self._call('publication', 'progress', value.handle, 0)
            work = self._call('publication', 'progress', value.handle, 1)
            if ready not in (0, 1) or not 0 <= work <= quantum:
                raise LocalCoreError('publication_progress', -33)
            return LocalResultProgress(ready == 1, work)

    def publication_work(self, value: _Output) -> int:
        with self._lock:
            self._owned_output(value, 'publication')
            work = self._call('publication', 'progress', value.handle, 2)
            if work < 0:
                raise LocalCoreError('publication_work', work)
            return work

    def finish_publication(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._check('finish_publication', self._call(
                'publication', 'finish', value.handle, current_configuration))

    def read_publication(self, value: _Output) -> bytes:
        return self._read_output(value, 'publication', 'length')

    def retire_publication_output(self, value: _Output) -> bool:
        """Retire transport bytes, keeping original semantic publication custody."""
        with self._lock:
            self._owned_output(value, 'publication')
            code = self._call('publication', 'retire_output', value.handle)
            if code == -9:
                return False
            self._check('retire_publication_output', code)
            return True

    def close_publication(self, value: _Output) -> bool:
        return self._close_output(value, 'publication', 'close')

    def reserve_result_binding(self, publication: _Output, index: int,
                               observations: _Input, *,
                               cleanup: Callable[[], bool]) -> _Output:
        """Bind observed Store bytes to an original Result, without committing."""
        with self._lock:
            self._owned_output(publication, 'publication')
            self._owned_input(observations)
            if type(index) is not int or not 0 <= index < 2**31:
                raise ValueError('Invalid original Result index')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'result_binding')))
            handle = self._call('result_binding', 'reserve', publication.handle,
                                index, observations.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_result_binding', handle)
            value = _Output(self._identity, ticket, handle, limit, 'result_binding')
            self._loans[ticket] = value
            return value

    def produce_result_binding(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'result_binding')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publication configuration')
            self._check('produce_result_binding', self._call(
                'result_binding', 'produce', value.handle, current_configuration))

    def read_result_binding(self, value: _Output) -> bytes:
        return self._read_output(value, 'result_binding', 'length')

    def close_result_binding(self, value: _Output) -> bool:
        return self._close_output(value, 'result_binding', 'close')

    def prepare_publication_commit(self, value: _Output, request: _Input,
                                   current_configuration: int) -> None:
        """Validate proposed Store facts against original Core custody.

        This is neither a Store write nor permission to publish or retry.
        Core retains the immutable input until this publication closes.
        """
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._owned_input(request)
            self._check('prepare_publication_commit', self._call(
                'publication', 'prepare_commit', value.handle, request.handle,
                current_configuration))

    def advance_publication_commit(self, value: _Output, current_configuration: int,
                                   quantum: int) -> LocalResultProgress:
        if type(quantum) is not int or not 0 < quantum <= 2**31 - 1:
            raise ValueError('Invalid Local publication commit quantum')
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._check('advance_publication_commit', self._call(
                'publication', 'advance_commit', value.handle,
                current_configuration, quantum))
            ready = self._call('publication', 'commit_progress', value.handle, 0)
            work = self._call('publication', 'commit_progress', value.handle, 1)
            if ready not in (0, 1) or not 0 <= work <= quantum:
                raise LocalCoreError('publication_commit_progress', -33)
            return LocalResultProgress(ready == 1, work)

    def finish_publication_commit(self, value: _Output, current_configuration: int) -> None:
        """Finish Core chain validation, without a durable acknowledgement."""
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._check('finish_publication_commit', self._call(
                'publication', 'finish_commit', value.handle, current_configuration))

    def prepare_publication_lookup(self, value: _Output, response: _Input,
                                   publisher: _Output, current_configuration: int) -> None:
        """Borrow the same physical index/reference packet for Core lookup.

        The packet transports original bytes, not Python scope, equality or
        permission. Core admits the index, checks its Store reference and
        original scope/request, and retains this input through dependent reads.
        This does not complete chain validation or confirm a Store commit.
        """
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._owned_input(response)
            self._owned_output(publisher, 'publisher')
            self._check('prepare_publication_lookup', self._call(
                'publication', 'prepare_lookup', value.handle, response.handle,
                publisher.handle, current_configuration))

    def retire_publication_lookup(self, value: _Output) -> bool:
        """Retry the original index borrow stop after dependent loan cleanup.

        The original physical input remains owned separately. No Source/Result
        parent, Run, publication or unknown operation is closed or replayed.
        """
        with self._lock:
            self._owned_output(value, 'publication')
            code = self._call('publication', 'retire_lookup', value.handle)
            if code == -9:
                return False
            self._check('retire_publication_lookup', code)
            return True

    def prepare_publication_observation(self, value: _Output, response: _Input,
                                        publisher: _Output, current_configuration: int) -> None:
        """Validate an original trusted Store response, retaining its same loan.

        Host lookup uses the original Core key, File/six-fact fences and current
        publisher before this call. Response is a closed physical observation,
        never a Python scope/comparison/accepted/committed decision. Failed parse
        or validation retains the same input until explicit physical cleanup.
        """
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._owned_input(response)
            self._owned_output(publisher, 'publisher')
            self._check('prepare_publication_observation', self._call(
                'publication', 'prepare_observation', value.handle, response.handle,
                publisher.handle, current_configuration))

    def advance_publication_observation(self, value: _Output, current_configuration: int,
                                       quantum: int) -> LocalResultProgress:
        if type(quantum) is not int or not 0 < quantum < 2**31:
            raise ValueError('Invalid Local publication observation quantum')
        with self._lock:
            self._publication_configuration(value, current_configuration)
            self._check('advance_publication_observation', self._call(
                'publication', 'advance_observation', value.handle,
                current_configuration, quantum))
            ready = self._call('publication', 'observation_progress', value.handle, 0)
            work = self._call('publication', 'observation_progress', value.handle, 1)
            if type(ready) is not int or type(work) is not int or ready not in (0, 1) or not 0 <= work <= quantum:
                raise LocalCoreError('publication_observation_progress', -33)
            return LocalResultProgress(ready == 1, work)

    def finish_publication_observation(self, value: _Output, current_configuration: int
                                      ) -> Literal['append_unknown', 'confirm_uncommitted_failure', 'adopt_committed_index']:
        """Read a Core action after current authorization/full-chain checks.

        This is an instruction to the original publication flow, not a durable
        ACK. AppendUnknown needs the existing durable record Owner; confirmed
        NotFound grants no permission to replay an unknown operation. The Host
        must recheck original six physical facts before adoption/publication.
        """
        with self._lock:
            self._publication_configuration(value, current_configuration)
            action = self._call('publication', 'finish_observation',
                                value.handle, current_configuration)
            if type(action) is not int or action not in (1, 3, 4):
                code = action if type(action) is int and action < 0 else -33
                raise LocalCoreError('finish_publication_observation', code)
            if action == 1:
                return 'append_unknown'
            if action == 3:
                return 'confirm_uncommitted_failure'
            return 'adopt_committed_index'

    def retire_publication_observation(self, value: _Output) -> bool:
        """Retry the same response borrow's stop; no submit, commit or cancel."""
        with self._lock:
            self._owned_output(value, 'publication')
            code = self._call('publication', 'retire_observation', value.handle)
            if code == -9:
                return False
            self._check('retire_publication_observation', code)
            return True

    def reserve_publication_commit_export(self, publication: _Output, *,
                                          cleanup: Callable[[], bool],
                                          maximum: int = 1_048_576) -> _Output:
        """Read the original candidate within its reserved field byte bound."""
        return self._reserve_publication_read_export(publication, 'publication', cleanup, maximum)

    def reserve_saved_result_export(self, original: _Output, *,
                                    cleanup: Callable[[], bool],
                                    maximum: int = 1_048_576) -> _Output:
        """Borrow the same saved-read Owner within its bounded field output."""
        return self._reserve_publication_read_export(original, 'submission_lookup', cleanup, maximum)

    def _reserve_publication_read_export(self, publication: _Output, family: str,
                                         cleanup: Callable[[], bool],
                                         maximum: int = 1_048_576) -> _Output:
        if type(maximum) is not int or not 1 <= maximum <= 1_048_576:
            raise ValueError('Invalid original publication field output bound')
        with self._lock:
            self._owned_output(publication, family)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = maximum
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'publication_commit_export')))
            handle = (self._call('publication_commit_export', 'reserve',
                                 publication.handle, ticket, physical_bytes) if limit == 1_048_576
                      else self._call('publication_commit_export', 'reserve_bounded',
                                      publication.handle, ticket, limit, physical_bytes))
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_publication_commit_export', handle)
            value = _Output(self._identity, ticket, handle, limit, 'publication_commit_export')
            self._loans[ticket] = value
            return value

    def produce_publication_commit_export(self, value: _Output,
                                          current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publication configuration')
            self._check('produce_publication_commit_export', self._call(
                'publication_commit_export', 'produce', value.handle, current_configuration))

    def publication_commit_material_count(self, publication: _Output,
                                          current_configuration: int) -> int:
        """Count original validated references, not durable Store entries."""
        with self._lock:
            self._publication_configuration(publication, current_configuration)
            count = self._call('publication_commit_export', 'count',
                               publication.handle, current_configuration)
            if type(count) is not int or not 8 <= count < 2**31:
                code = count if type(count) is int and count < 0 else -33
                raise LocalCoreError('publication_commit_material_count', code)
            return count

    def publication_commit_result_count(self, publication: _Output,
                                        current_configuration: int) -> int:
        """Count original completed Result occurrences, without Store or I/O."""
        with self._lock:
            self._publication_configuration(publication, current_configuration)
            count = self._call('publication_commit_export', 'result_count',
                               publication.handle, current_configuration)
            if type(count) is not int or not 0 <= count < 2**31:
                code = count if type(count) is int and count < 0 else -33
                raise LocalCoreError('publication_commit_result_count', code)
            return count

    def produce_publication_commit_material(self, value: _Output,
                                            current_configuration: int, ordinal: int, *,
                                            field: _CommitMaterialField = 'wire') -> None:
        """Project one exact original field into a single accounted child.

        Core fixes the child's ordinal and field at first production. Changing
        them requires a fresh reservation; this never writes or grants a Store.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publication configuration')
            if type(ordinal) is not int or not 0 <= ordinal < 2**31:
                raise ValueError('Invalid original commit material ordinal')
            if type(field) is not str or field not in _COMMIT_MATERIAL_FIELDS:
                raise ValueError('Invalid original commit material field')
            self._check('produce_publication_commit_material', self._call(
                'publication_commit_export', 'produce_material', value.handle,
                current_configuration, ordinal, _COMMIT_MATERIAL_FIELDS[field]))

    def produce_publication_lookup_reference(self, value: _Output,
                                             current_configuration: int, *,
                                             field: Literal['request', 'attempt']) -> None:
        """Project the actual stored index's Core-checked lookup reference.

        Read it using the existing commit-material output loan. It neither
        chooses a different Store/scope nor grants commit or retry permission.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publication configuration')
            if type(field) is not str or field not in ('request', 'attempt'):
                raise ValueError('Invalid stored publication lookup reference field')
            self._check('produce_publication_lookup_reference', self._call(
                'publication_commit_export', 'produce_lookup_reference', value.handle,
                current_configuration, 0 if field == 'request' else 1))

    def produce_publication_commit_index_key(self, value: _Output,
                                             current_configuration: int) -> None:
        """Project the original index's Owner-derived physical Store key.

        Read it with read_publication_commit_material(). Core retains the
        immutable projection and rechecks current access before reuse. This
        neither grants publisher authority nor confirms a Store commit.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publication configuration')
            self._check('produce_publication_commit_index_key', self._call(
                'publication_commit_export', 'produce_index_key', value.handle,
                current_configuration))

    def produce_publication_observed_index(self, value: _Output,
                                           current_configuration: int, *,
                                           field: _CommitMaterialField = 'wire') -> None:
        """Copy the actually stored index after a fresh current publisher check."""
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publication configuration')
            if type(field) is not str or field not in _COMMIT_MATERIAL_FIELDS:
                raise ValueError('Invalid observed index field')
            self._check('produce_publication_observed_index', self._call(
                'publication_commit_export', 'produce_observed_index', value.handle,
                current_configuration, _COMMIT_MATERIAL_FIELDS[field]))

    def produce_publication_observed_run_state(self, value: _Output,
                                               observed_at: _Input,
                                               current_configuration: int) -> None:
        """Copy the existing RunState Owner's original full-chain observation.

        The input carries only the physical observation time. Core retains its
        loan and separately checks current publisher and Account run/read.
        Read with read_publication_commit_material(); close the output before
        closing this same input. This supplies no durable ACK or read grant.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_input(observed_at)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publication configuration')
            self._check('produce_publication_observed_run_state', self._call(
                'publication_commit_export', 'produce_run_state', value.handle,
                observed_at.handle, current_configuration))

    def produce_publication_sdk_run_state(self, value: _Output, original_run: int,
                                           source: _Input,
                                           current_configuration: int) -> None:
        """Prepare original durable observation metadata, never a COMMIT ACK."""
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_input(source)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(original_run) is not int or not 0 < original_run < 2**31
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK Run observation')
            self._check('produce_publication_sdk_run_state', self._call(
                'publication_commit_export', 'produce_sdk_run_state', value.handle,
                original_run, source.handle, current_configuration))

    def validate_publication_sdk_run_state(self, value: _Output,
                                            current_configuration: int) -> None:
        """Check the same prior row inside its actual physical CAS transaction."""
        self._publication_sdk_run_state_step(value, current_configuration, 'validate_sdk_run_state')

    def confirm_publication_sdk_run_state(self, value: _Output,
                                           current_configuration: int) -> None:
        """Reread the exact committed original before exposing candidate wire."""
        self._publication_sdk_run_state_step(value, current_configuration, 'confirm_sdk_run_state')

    def _publication_sdk_run_state_step(self, value: _Output, current_configuration: int,
                                       operation: str) -> None:
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current SDK Run observation')
            self._check(operation, self._call(
                'publication_commit_export', operation, value.handle, current_configuration))

    def produce_publication_sdk_read_original(self, value: _Output, request: _Input,
                                              original_run: int,
                                              current_configuration: int,
                                              ordinal: int, *,
                                              field: Literal['wire', 'identity']) -> None:
        """Copy one Core-issued original body/CID, never permission or ACK.

        Core requires the original finite Run, complete observed chain and
        independent current publisher/Account read decisions. The original
        request loan remains borrowed until this output's cleanup succeeds.
        Persisting these bytes and issuing a grant are separate operations.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(original_run) is not int or not 0 < original_run < 2**31
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31
                    or type(ordinal) is not int or not 0 <= ordinal <= 2
                    or type(field) is not str or field not in ('wire', 'identity')):
                raise ValueError('Invalid original SDK read projection')
            self._check('produce_publication_sdk_read_original', self._call(
                'publication_commit_export', 'produce_sdk_read_original', value.handle,
                request.handle, original_run, current_configuration, ordinal,
                0 if field == 'wire' else 1))

    def produce_publication_sdk_read_evidence_decision(self, value: _Output,
                                                      request: _Input,
                                                      original_run: int,
                                                      current_configuration: int) -> None:
        """Project Core's typed append/retained proposal from actual Store rows.

        No Python comparison or physical COMMIT result supplies this decision.
        Unknown attempted writes keep original custody and are never replayed.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(original_run) is not int or not 0 < original_run < 2**31
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK read evidence decision')
            self._check('produce_sdk_read_evidence_decision', self._call(
                'publication_commit_export', 'produce_sdk_read_evidence_decision',
                value.handle, request.handle, original_run, current_configuration))

    def produce_publication_sdk_delivery_lookup(self, value: _Output,
                                               request: _Input,
                                               original_run: int,
                                               current_configuration: int) -> None:
        """Project only Common's original read-only delivery-attempt response."""
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(original_run) is not int or not 0 < original_run < 2**31
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK delivery lookup')
            self._check('produce_sdk_delivery_lookup', self._call(
                'publication_commit_export', 'produce_sdk_delivery_lookup',
                value.handle, request.handle, original_run, current_configuration))

    def retire_publication_sdk_delivery_output(self, value: _Output) -> bool:
        """Retire transport only; the actual first preparation/request stay owned."""
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            code = self._call('publication_commit_export', 'retire_sdk_delivery_output', value.handle)
            if type(code) is not int:
                raise RuntimeError('Invalid Local Core retirement status')
            if code == -9:
                return False
            if code != 0:
                raise LocalCoreError('retire_sdk_delivery_output', code)
            return True

    def prepare_publication_sdk_payload_codecs(self, value: _Output,
                                               clock: _Input,
                                               current_configuration: int) -> None:
        """Connect original retained first codecs, without payload/sink/Store ACK."""
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_input(clock)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK payload configuration')
            code = self._call('publication_commit_export', 'prepare_sdk_payload_codecs',
                              value.handle, clock.handle, current_configuration)
            if type(code) is not int:
                raise RuntimeError('Invalid Local Core codec status')
            if code != 0:
                raise LocalCoreError('prepare_sdk_payload_codecs', code)

    def publication_sdk_payload_ordinal(self, first: _Output,
                                        current_configuration: int, *,
                                        field: Literal['result', 'binding']) -> int:
        """Read a Core routing coordinate, never a read grant or Store ACK."""
        with self._lock:
            self._owned_output(first, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31
                    or type(field) is not str or field not in ('result', 'binding')):
                raise ValueError('Invalid original SDK routing selector')
            ordinal = self._call('publication_commit_export', 'sdk_payload_ordinal',
                first.handle, current_configuration, 0 if field == 'result' else 1)
            if type(ordinal) is not int:
                raise RuntimeError('Invalid Local Core payload ordinal')
            if ordinal < 0:
                raise LocalCoreError('sdk_payload_ordinal', ordinal)
            if ordinal >= 8:
                raise RuntimeError('Invalid Local Core payload ordinal')
            self._owned_output(first, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            return ordinal

    def bind_publication_sdk_payload_record(self, first: _Output, record: _Output,
                                           current_configuration: int,
                                           result: int, binding_index: int) -> None:
        """Bind the selected original Sealed record through existing Core Owners.

        Python proposes only physical inventory ordinals. Core matches the
        actual read binding and keeps the source loan until first cleanup.
        """
        with self._lock:
            self._owned_output(first, 'publication_commit_export')
            self._owned_output(record, 'payload_record')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31
                    or any(type(index) is not int or not 0 <= index < 2**31
                           for index in (result, binding_index))):
                raise ValueError('Invalid original SDK payload record binding')
            code = self._call('publication_commit_export', 'bind_sdk_payload_record',
                              first.handle, record.handle, current_configuration,
                              result, binding_index)
            if type(code) is not int:
                raise RuntimeError('Invalid Local Core payload binding status')
            if code != 0:
                raise LocalCoreError('bind_sdk_payload_record', code)
            self._owned_output(first, 'publication_commit_export')
            self._owned_output(record, 'payload_record')
            if self._closing:
                raise RuntimeError('Local Core is closing')

    def prepare_publication_sdk_payload_input(self, first: _Output,
                                             clock: _Input,
                                             current_configuration: int) -> None:
        """Check Core's current original read and backpressure before file I/O.

        This is not a durable permit. Producing the actual chunk rechecks the
        same current/Store facts; no read grant, use or attempt is installed.
        """
        with self._lock:
            self._owned_output(first, 'publication_commit_export')
            self._owned_input(clock)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK payload configuration')
            code = self._call('publication_commit_export', 'prepare_sdk_payload_input',
                              first.handle, clock.handle, current_configuration)
            if type(code) is not int:
                raise RuntimeError('Invalid Local Core payload status')
            if code != 0:
                raise LocalCoreError('prepare_sdk_payload_input', code)
            self._owned_output(first, 'publication_commit_export')
            self._owned_input(clock)
            if self._closing:
                raise RuntimeError('Local Core is closing')

    def produce_publication_sdk_payload_chunk(self, value: _Output, first: _Output,
                                             chunk: _Input, clock: _Input,
                                             current_configuration: int, *, eof: bool) -> None:
        """Offer bounded original bytes to Core's codecs and existing sink.

        Physical acceptance, reader release and terminal Store ACK remain
        separate. Errors keep all original loans for their explicit cleanup.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_output(first, 'publication_commit_export')
            self._owned_input(chunk)
            self._owned_input(clock)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (value is first or chunk.length > 65536 or type(eof) is not bool
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK payload chunk')
            code = self._call('publication_commit_export', 'produce_sdk_payload_chunk',
                              value.handle, first.handle, chunk.handle, clock.handle,
                              int(eof), current_configuration)
            if type(code) is not int:
                raise RuntimeError('Invalid Local Core payload status')
            if code != 0:
                raise LocalCoreError('produce_sdk_payload_chunk', code)
            for output in (value, first):
                self._owned_output(output, 'publication_commit_export')
            for original in (chunk, clock):
                self._owned_input(original)
            if self._closing:
                raise RuntimeError('Local Core is closing')

    def confirm_publication_sdk_payload_chunk(self, value: _Output) -> int:
        """Record actual sink acceptance, without a new permit or Store ACK.

        Recording an already accepted chunk remains distinct from starting
        another read; closing does not fabricate acceptance or cancel the Run.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            count = self._call('publication_commit_export', 'confirm_sdk_payload_chunk',
                               value.handle)
            if type(count) is not int:
                raise RuntimeError('Invalid Local Core confirmed byte count')
            if count < 0:
                raise LocalCoreError('confirm_sdk_payload_chunk', count)
            # Core returns cumulative confirmed bytes, not this input chunk's
            # length. Its sink Owner enforces the original total byte limit.
            if count >= 2**63:
                raise RuntimeError('Invalid Local Core confirmed byte count')
            self._owned_output(value, 'publication_commit_export')
            return count

    def produce_publication_sdk_payload_receipt(self, value: _Output, first: _Output,
                                               clock: _Input,
                                               current_configuration: int) -> None:
        """Project Core's explicit sink-completion receipt, never durable ACK."""
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_output(first, 'publication_commit_export')
            self._owned_input(clock)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (value is first or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK payload receipt')
            code = self._call('publication_commit_export', 'produce_sdk_payload_receipt',
                              value.handle, first.handle, clock.handle,
                              current_configuration)
            if type(code) is not int:
                raise RuntimeError('Invalid Local Core payload status')
            if code != 0:
                raise LocalCoreError('produce_sdk_payload_receipt', code)
            self._owned_output(value, 'publication_commit_export')
            self._owned_output(first, 'publication_commit_export')
            self._owned_input(clock)
            if self._closing:
                raise RuntimeError('Local Core is closing')

    def produce_publication_sdk_terminal_storage(self, value: _Output, first: _Output,
                                                 clock: _Input,
                                                 current_configuration: int) -> None:
        """Project the original successor CAS; no physical COMMIT ACK occurs."""
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_output(first, 'publication_commit_export')
            self._owned_input(clock)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (value is first or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK terminal projection')
            code = self._call('publication_commit_export', 'produce_sdk_terminal_storage',
                              value.handle, first.handle, clock.handle,
                              current_configuration)
            if type(code) is not int:
                raise RuntimeError('Invalid Local Core terminal status')
            if code != 0:
                raise LocalCoreError('produce_sdk_terminal_storage', code)
            self._owned_output(value, 'publication_commit_export')
            self._owned_output(first, 'publication_commit_export')
            self._owned_input(clock)
            if self._closing:
                raise RuntimeError('Local Core is closing')

    def observe_publication_sdk_terminal(self, first: _Output,
                                        current_configuration: int) -> None:
        """Validate actual saved terminal evidence; never write or replay bytes."""
        with self._lock:
            self._owned_output(first, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK terminal observation')
            code = self._call('publication_commit_export', 'observe_sdk_terminal',
                              first.handle, current_configuration)
            if type(code) is not int:
                raise RuntimeError('Invalid Local Core terminal status')
            if code != 0:
                raise LocalCoreError('observe_sdk_terminal', code)
            self._owned_output(first, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')

    def produce_publication_sdk_read_delivery_storage(self, value: _Output,
                                                      request: _Input,
                                                      original_run: int,
                                                      current_configuration: int) -> None:
        """Project the existing delivery/usage Owners' same-TX first CAS only.

        This neither acknowledges physical COMMIT nor starts payload delivery.
        Core chooses original keys/body/revisions; unknown attempts need lookup.
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(original_run) is not int or not 0 < original_run < 2**31
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK delivery storage projection')
            self._check('produce_sdk_read_delivery_storage', self._call(
                'publication_commit_export', 'produce_sdk_read_delivery_storage',
                value.handle, request.handle, original_run, current_configuration))

    def produce_publication_sdk_read_evidence(self, value: _Output, request: _Input,
                                              original_run: int,
                                              current_configuration: int, *,
                                              field: Literal['wire', 'identity']) -> None:
        """Project the exact Core evidence packet/key, without a Store write."""
        self._produce_publication_sdk_read_entry(value, request, original_run,
            current_configuration, field, 'produce_sdk_read_evidence')

    def produce_publication_sdk_read_grant(self, value: _Output, request: _Input,
                                           original_run: int,
                                           current_configuration: int, *,
                                           field: Literal['wire', 'identity']) -> None:
        """Issue through Core only after the same Store's actual evidence read.

        A grant body is not its persistence, usage claim, delivery or Run state.
        Query failure/missing/changed evidence retain the exact same loans.
        """
        self._produce_publication_sdk_read_entry(value, request, original_run,
            current_configuration, field, 'produce_sdk_read_grant')

    def _produce_publication_sdk_read_entry(self, value: _Output, request: _Input,
                                           original_run: int, current_configuration: int,
                                           field: Literal['wire', 'identity'],
                                           operation: str) -> None:
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if (type(original_run) is not int or not 0 < original_run < 2**31
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31
                    or type(field) is not str or field not in ('wire', 'identity')):
                raise ValueError('Invalid original SDK read entry projection')
            self._check(operation, self._call(
                'publication_commit_export', operation, value.handle, request.handle,
                original_run, current_configuration, 0 if field == 'wire' else 1))

    def produce_publication_commit_schema(self, value: _Output,
                                           current_configuration: int, result: int, *,
                                           field: Literal['identity', 'wire']) -> None:
        """Project one original receipt field, without schema/CID regeneration.

        Result follows the original preflight inventory, not material ordinals.
        Core rechecks nominal Result/current access on every call and fixes each
        output's field. Read with read_publication_commit_material().
        """
        with self._lock:
            self._owned_output(value, 'publication_commit_export')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current publication configuration')
            if type(result) is not int or not 0 <= result < 2**31:
                raise ValueError('Invalid original schema Result index')
            if type(field) is not str or field not in ('identity', 'wire'):
                raise ValueError('Invalid original schema field')
            self._check('produce_publication_commit_schema', self._call(
                'publication_commit_export', 'produce_schema', value.handle,
                current_configuration, result, 0 if field == 'identity' else 1))

    def validate_publication_commit_payload_binding(
            self, publication: _Output, record: _Output,
            current_configuration: int, result: int, binding_index: int) -> None:
        """Match original Core custody; no physical Store lookup or commit ACK.

        Result and binding indexes belong to distinct original inventories.
        The same physical generation/reservation still needs a Host fence;
        success here is neither publisher authority nor permission to retry.
        """
        with self._lock:
            self._publication_configuration(publication, current_configuration)
            self._owned_output(record, 'payload_record')
            if (type(result) is not int or not 0 <= result < 2**31
                    or type(binding_index) is not int or not 0 <= binding_index < 2**31):
                raise ValueError('Invalid original Result or commit binding index')
            self._check('validate_publication_commit_payload_binding', self._call(
                'publication_commit_export', 'validate_payload_binding', publication.handle,
                record.handle, current_configuration, result, binding_index))

    def validate_saved_payload_binding(self, original: _Output, record: _Output,
                                       current_configuration: int, result: int,
                                       binding_index: int) -> None:
        """Match the same saved-read Owner and original Sealed row; no grant."""
        with self._lock:
            self._owned_output(original, 'submission_lookup')
            self._owned_output(record, 'payload_record')
            if (type(current_configuration) is not int or not 0 < current_configuration < 2**31
                    or any(type(value) is not int or not 0 <= value < 8
                           for value in (result, binding_index))):
                raise ValueError('Invalid original saved payload coordinates')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            self._check('validate_saved_payload_binding', self._call(
                'publication_commit_export', 'validate_payload_binding', original.handle,
                record.handle, current_configuration, result, binding_index))

    def begin_saved_read_cleanup(self, original: _Output) -> None:
        """Retire interrupted synchronous call latches, never physical duties.

        The original serialized invocation must have returned or trapped. Normal
        work remains fenced; this neither repeats it nor acknowledges any Store,
        Reader, buffer loan, native child or parent. Their existing close ports
        still decide whether the same original can retire.
        """
        with self._lock:
            self._owned_output(original, 'submission_lookup')
            if (not getattr(self, '_ordinary_host', False) or not self._closing
                    or self._invoking or self._host_fuel_phase != 'cleanup'):
                raise RuntimeError('Original saved read requires quiescent terminal cleanup')
            self._check('begin_saved_read_cleanup', self._call(
                'submission', 'begin_cleanup', original.handle))

    def read_publication_commit_material(self, value: _Output) -> bytes:
        """Read original raw bytes, without parsing or recreating a contract."""
        return self._read_output(value, 'publication_commit_export', 'length')

    def read_publication_commit_export(self, value: _Output) -> bytes:
        return self._read_output(value, 'publication_commit_export', 'length')

    def close_publication_commit_export(self, value: _Output) -> bool:
        return self._close_output(value, 'publication_commit_export', 'close')

    def reserve_payload_request(self, publication: _Output, index: int,
                                request: _Input, *, cleanup: Callable[[], bool]) -> _Output:
        """Project existing Core payload intent; grants no write permission."""
        with self._lock:
            self._owned_output(publication, 'publication')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(index) is not int or not 0 <= index < 2**31:
                raise ValueError('Invalid original payload Result index')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65_536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'payload_request')))
            handle = self._call('payload_request', 'reserve', publication.handle, index,
                                request.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_payload_request', handle)
            value = _Output(self._identity, ticket, handle, limit, 'payload_request')
            self._loans[ticket] = value
            return value

    def produce_payload_request(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'payload_request')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('produce_payload_request', self._call(
                'payload_request', 'produce', value.handle, current_configuration))

    def read_payload_request(self, value: _Output) -> bytes:
        return self._read_output(value, 'payload_request', 'length')

    def close_payload_request(self, value: _Output) -> bool:
        return self._close_output(value, 'payload_request', 'close')

    def start_payload_replay(self, value: _Output, current_configuration: int) -> None:
        """Read the original Result through Core; does not start a Store write."""
        with self._lock:
            self._owned_output(value, 'payload_request')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('start_payload_replay', self._call(
                'payload_request', 'start_replay', value.handle, current_configuration))

    def reserve_payload_chunk(self, request: _Output, *,
                              cleanup: Callable[[], bool]) -> _Output:
        """Reserve one accounted copy before the original replay Owner advances."""
        with self._lock:
            self._owned_output(request, 'payload_request')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65_536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'payload_chunk')))
            handle = self._call('payload_chunk', 'reserve', request.handle,
                                ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_payload_chunk', handle)
            value = _Output(self._identity, ticket, handle, limit, 'payload_chunk')
            self._loans[ticket] = value
            return value

    def produce_payload_chunk(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'payload_chunk')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('produce_payload_chunk', self._call(
                'payload_chunk', 'produce', value.handle, current_configuration))

    def read_payload_chunk(self, value: _Output, current_configuration: int) -> tuple[bytes, bool]:
        """Recheck current custody even for cached bytes; EOF is not Store commit."""
        with self._lock:
            self._owned_output(value, 'payload_chunk')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('read_payload_chunk', self._call(
                'payload_chunk', 'validate', value.handle, current_configuration))
            wire = self._read_output(value, 'payload_chunk', 'length')
            final = self._call('payload_chunk', 'final', value.handle)
            if final not in (0, 1):
                raise LocalCoreError('payload_chunk_final', final)
            return wire, final == 1

    def close_payload_chunk(self, value: _Output) -> bool:
        return self._close_output(value, 'payload_chunk', 'close')

    def reserve_payload_record(self, request: _Output, *,
                               cleanup: Callable[[], bool]) -> _Output:
        """Retain the original Core Intent; does not reserve disk capacity."""
        return self._reserve_original_payload_record(request, 'payload_request', cleanup)

    def reserve_saved_payload_record(self, original: _Output, *,
                                     cleanup: Callable[[], bool]) -> _Output:
        """Restore only the selected original Sealed state; cannot begin a write."""
        return self._reserve_original_payload_record(original, 'submission_lookup', cleanup)

    def _reserve_original_payload_record(self, request: _Output, family: str,
                                          cleanup: Callable[[], bool]) -> _Output:
        with self._lock:
            self._owned_output(request, family)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65_536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'payload_record')))
            handle = self._call('payload_record', 'reserve', request.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_payload_record', handle)
            value = _Output(self._identity, ticket, handle, limit, 'payload_record')
            self._loans[ticket] = value
            return value

    def produce_payload_record(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'payload_record')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('produce_payload_record', self._call(
                'payload_record', 'produce', value.handle, current_configuration))

    def read_payload_record(self, value: _Output, current_configuration: int) -> bytes:
        with self._lock:
            self._owned_output(value, 'payload_record')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('read_payload_record', self._call(
                'payload_record', 'validate', value.handle, current_configuration))
            return self._read_output(value, 'payload_record', 'length')

    def begin_payload_record(self, value: _Output, current_configuration: int) -> None:
        """Mark this one physical write; a repeated begin is not a resend permit."""
        with self._lock:
            self._owned_output(value, 'payload_record')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('begin_payload_record', self._call(
                'payload_record', 'begin', value.handle, current_configuration))

    def confirm_payload_record(self, value: _Output, observation: _Input,
                               current_configuration: int) -> None:
        """Resolve the original pending Intent from actual physical Store bytes."""
        with self._lock:
            self._owned_output(value, 'payload_record')
            self._owned_input(observation)
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('confirm_payload_record', self._call(
                'payload_record', 'confirm', value.handle, observation.handle, current_configuration))

    def close_payload_record(self, value: _Output) -> bool:
        return self._close_output(value, 'payload_record', 'close')

    def validate_payload_snapshot(self, value: _Output, observation: _Input,
                                  current_configuration: int) -> None:
        """Compare fresh trusted physical facts with the original Sealed record.

        The Host supplies actual original completed-reader facts under its
        Core-to-File lock order, retains the reader/reservation, and rechecks
        before physical commit. Success grants no publisher authority or ACK.
        This call keeps both original loans and performs no physical I/O.
        """
        with self._lock:
            self._owned_output(value, 'payload_record')
            self._owned_input(observation)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('validate_payload_snapshot', self._call(
                'payload_record', 'validate_snapshot', value.handle,
                observation.handle, current_configuration))

    def reserve_payload_reservation(self, request: _Output, *,
                               cleanup: Callable[[], bool]) -> _Output:
        """Project the original Reserved transition; does not reserve disk capacity."""
        with self._lock:
            self._owned_output(request, 'payload_record')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65_536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'payload_reservation')))
            handle = self._call('payload_reservation', 'reserve', request.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_payload_reservation', handle)
            value = _Output(self._identity, ticket, handle, limit, 'payload_reservation')
            self._loans[ticket] = value
            return value

    def produce_payload_reservation(self, value: _Output, observation: _Input,
                                    current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'payload_reservation')
            self._owned_input(observation)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('produce_payload_reservation', self._call(
                'payload_reservation', 'produce', value.handle, observation.handle, current_configuration))

    def read_payload_reservation(self, value: _Output, current_configuration: int) -> bytes:
        with self._lock:
            self._owned_output(value, 'payload_reservation')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('read_payload_reservation', self._call(
                'payload_reservation', 'validate', value.handle, current_configuration))
            return self._read_output(value, 'payload_reservation', 'length')

    def begin_payload_reservation(self, value: _Output, current_configuration: int) -> None:
        """Mark this one physical write; a repeated begin is not a resend permit."""
        with self._lock:
            self._owned_output(value, 'payload_reservation')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('begin_payload_reservation', self._call(
                'payload_reservation', 'begin', value.handle, current_configuration))

    def confirm_payload_reservation(self, value: _Output, observation: _Input,
                               current_configuration: int) -> None:
        """Confirm the original Reserved transition from actual physical Store bytes."""
        with self._lock:
            self._owned_output(value, 'payload_reservation')
            self._owned_input(observation)
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('confirm_payload_reservation', self._call(
                'payload_reservation', 'confirm', value.handle, observation.handle, current_configuration))

    def close_payload_reservation(self, value: _Output) -> bool:
        return self._close_output(value, 'payload_reservation', 'close')

    def reserve_payload_writing(self, request: _Output, kind: int, *,
                               cleanup: Callable[[], bool]) -> _Output:
        """Project Writing (1), physical ownership (2) or Sealed (3); Core decides."""
        with self._lock:
            self._owned_output(request, 'payload_record')
            if type(kind) is not int or kind not in (1, 2, 3):
                raise ValueError('Invalid payload writing transition')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65_536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'payload_writing')))
            handle = self._call('payload_writing', 'reserve', request.handle, kind, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_payload_writing', handle)
            value = _Output(self._identity, ticket, handle, limit, 'payload_writing')
            self._loans[ticket] = value
            return value

    def produce_payload_writing(self, value: _Output, observation: _Input | None,
                                    current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'payload_writing')
            if observation is not None:
                self._owned_input(observation)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('produce_payload_writing', self._call(
                'payload_writing', 'produce', value.handle, 0 if observation is None else observation.handle,
                current_configuration))

    def read_payload_writing(self, value: _Output, current_configuration: int) -> bytes:
        with self._lock:
            self._owned_output(value, 'payload_writing')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('read_payload_writing', self._call(
                'payload_writing', 'validate', value.handle, current_configuration))
            return self._read_output(value, 'payload_writing', 'length')

    def begin_payload_writing(self, value: _Output, current_configuration: int) -> None:
        """Mark this one physical write; a repeated begin is not a resend permit."""
        with self._lock:
            self._owned_output(value, 'payload_writing')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('begin_payload_writing', self._call(
                'payload_writing', 'begin', value.handle, current_configuration))

    def confirm_payload_writing(self, value: _Output, observation: _Input,
                               current_configuration: int) -> None:
        """Confirm the original Writing/Owned transition from actual Store bytes."""
        with self._lock:
            self._owned_output(value, 'payload_writing')
            self._owned_input(observation)
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('confirm_payload_writing', self._call(
                'payload_writing', 'confirm', value.handle, observation.handle, current_configuration))

    def close_payload_writing(self, value: _Output) -> bool:
        return self._close_output(value, 'payload_writing', 'close')

    def reserve_payload_names(self, record: _Output, *, cleanup: Callable[[], bool]) -> _Output:
        """Retain original Core-selected names; this grants no file or Store I/O."""
        with self._lock:
            self._owned_output(record, 'payload_record')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1024
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'payload_names')))
            handle = self._call('payload_names', 'reserve', record.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_payload_names', handle)
            value = _Output(self._identity, ticket, handle, limit, 'payload_names')
            self._loans[ticket] = value
            return value

    def produce_payload_names(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'payload_names')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('produce_payload_names', self._call(
                'payload_names', 'produce', value.handle, current_configuration))

    def read_payload_names(self, value: _Output, current_configuration: int) -> bytes:
        with self._lock:
            self._owned_output(value, 'payload_names')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('read_payload_names', self._call(
                'payload_names', 'validate', value.handle, current_configuration))
            return self._read_output(value, 'payload_names', 'length')

    def close_payload_names(self, value: _Output) -> bool:
        return self._close_output(value, 'payload_names', 'close')

    def reserve_payload_binding(self, record: _Output, *, cleanup: Callable[[], bool]) -> _Output:
        """Bind the original confirmed Sealed record; no Store or publisher grant."""
        with self._lock:
            self._owned_output(record, 'payload_record')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'payload_binding')))
            handle = self._call('payload_binding', 'reserve', record.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_payload_binding', handle)
            value = _Output(self._identity, ticket, handle, limit, 'payload_binding')
            self._loans[ticket] = value
            return value

    def produce_payload_binding(self, value: _Output, current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'payload_binding')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('produce_payload_binding', self._call(
                'payload_binding', 'produce', value.handle, current_configuration))

    def read_payload_binding(self, value: _Output, current_configuration: int) -> bytes:
        with self._lock:
            self._owned_output(value, 'payload_binding')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('read_payload_binding', self._call(
                'payload_binding', 'validate', value.handle, current_configuration))
            return self._read_output(value, 'payload_binding', 'length')

    def close_payload_binding(self, value: _Output) -> bool:
        return self._close_output(value, 'payload_binding', 'close')

    def reserve_payload_allocation(self, request: _Output, kind: int, *,
                               cleanup: Callable[[], bool]) -> _Output:
        """Project original allocation intent (1) or directory ownership (2)."""
        with self._lock:
            self._owned_output(request, 'payload_record')
            if type(kind) is not int or kind not in (1, 2):
                raise ValueError('Invalid payload allocation write')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65_536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'payload_allocation')))
            handle = self._call('payload_allocation', 'reserve', request.handle, kind, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_payload_allocation', handle)
            value = _Output(self._identity, ticket, handle, limit, 'payload_allocation')
            self._loans[ticket] = value
            return value

    def produce_payload_allocation(self, value: _Output, observation: _Input,
                                    current_configuration: int) -> None:
        with self._lock:
            self._owned_output(value, 'payload_allocation')
            self._owned_input(observation)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('produce_payload_allocation', self._call(
                'payload_allocation', 'produce', value.handle, observation.handle,
                current_configuration))

    def read_payload_allocation(self, value: _Output, current_configuration: int) -> bytes:
        with self._lock:
            self._owned_output(value, 'payload_allocation')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('read_payload_allocation', self._call(
                'payload_allocation', 'validate', value.handle, current_configuration))
            return self._read_output(value, 'payload_allocation', 'length')

    def begin_payload_allocation(self, value: _Output, current_configuration: int) -> None:
        """Mark this one physical write; a repeated begin is not a resend permit."""
        with self._lock:
            self._owned_output(value, 'payload_allocation')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('begin_payload_allocation', self._call(
                'payload_allocation', 'begin', value.handle, current_configuration))

    def confirm_payload_allocation(self, value: _Output, observation: _Input,
                               current_configuration: int) -> None:
        """Observe the same allocation CAS; grants no acquisition or resend permission."""
        with self._lock:
            self._owned_output(value, 'payload_allocation')
            self._owned_input(observation)
            if type(current_configuration) is not int or not 0 < current_configuration < 2**31:
                raise ValueError('Invalid current payload configuration')
            self._check('confirm_payload_allocation', self._call(
                'payload_allocation', 'confirm', value.handle, observation.handle, current_configuration))

    def close_payload_allocation(self, value: _Output) -> bool:
        return self._close_output(value, 'payload_allocation', 'close')

    def reserve_material(self, run: int, kind: int, *,
                         cleanup: Callable[[], bool]) -> _Output:
        """Private Host projection; neither Run admission nor durable storage.

        The Host retains the returned loan through persistence and cleanup.
        Its trusted Run handle belongs to this instance; it is not a wire ref.
        """
        with self._lock:
            if (self._closing or type(run) is not int or run <= 0 or
                    type(kind) is not int or kind not in (1, 2, 3, 4, 5, 7, 8, 9)):
                raise ValueError('Invalid Local material projection')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            # Register physical custody before entering Wasm, but allocate
            # the large destination only after Core reserves its capacity.
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit) +
                              sys.getsizeof(_Output(self._identity, ticket, 0, limit)))
            handle = self._call('material', 'reserve', run, kind, ticket,
                                physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_material', handle)
            value = _Output(self._identity, ticket, handle, limit)
            self._loans[ticket] = value
            return value

    def reserve_submitted_run_rows(self, run: int, current: int, source: _Input, *,
                                   cleanup: Callable[[], bool]) -> _Output:
        """Project original Owner row candidates, never a committed admission.

        The original Run/current configuration and input borrow remain in Core
        until this same output handle finishes cleanup. The installed Host must
        separately fence authenticated epoch, count and current authority in
        the actual Store transaction before any public acceptance.
        """
        with self._lock:
            if (self._closing or type(run) is not int or run <= 0
                    or type(current) is not int or current <= 0):
                raise ValueError('Invalid original Local submitted row projection')
            self._owned_input(source)
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit)))
            handle = self._call('material', 'reserve_submitted_rows', run, current,
                                source.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_submitted_run_rows', handle)
            value = _Output(self._identity, ticket, handle, limit)
            self._loans[ticket] = value
            return value

    def _owned_native(self, value: _NativeAttempt) -> None:
        if (type(value) is not _NativeAttempt or value.owner is not self._identity
                or self._native_loans.get(value.handle) is not value):
            raise ValueError('Foreign or released Local Native attempt')

    def native_configuration_capacity(self, configuration: int) -> LocalNativeCapacity:
        """Read the existing Core inventory; this does not reserve or start I/O."""
        with self._lock:
            if self._closing or type(configuration) is not int or configuration <= 0:
                raise ValueError('Invalid Local Native configuration')
            values = [self._call('source', 'capacity', configuration, field)
                      for field in range(3)]
            for value in values:
                if value < 0:
                    raise LocalCoreError('native_configuration_capacity', value)
            return LocalNativeCapacity(*values)

    def reserve_native_attempt(self, configuration: int, start: int, input: _Input, *,
                               settled: Callable[[], bool], stopped: Callable[[], bool],
                               cleaned: Callable[[], bool]) -> _NativeAttempt:
        """Bind physical observations before starting the issued Core attempt.

        Configuration/start are private handles from this installed instance.
        This operation neither starts DuckDB I/O nor decides Source completion.
        """
        with self._lock:
            self._owned_input(input)
            if (self._closing or type(configuration) is not int or configuration <= 0
                    or type(start) is not int or start <= 0
                    or not all(callable(item) for item in (settled, stopped, cleaned))):
                raise ValueError('Invalid Local Native attempt reservation')
            handle = self._call('source', 'reserve_attempt', configuration, start,
                                input.handle)
            if handle <= 0:
                raise LocalCoreError('reserve_native_attempt', handle)
            value = _NativeAttempt(self._identity, handle)
            self._native_loans[handle] = value
            self._native_observers[handle] = (settled, stopped, cleaned)
            return value

    def start_native_attempt(self, value: _NativeAttempt) -> None:
        with self._lock:
            self._owned_native(value)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            self._check('start_native_attempt', self._call('source', 'start', value.handle))
            self._check('native_attempt_started', self._call('source', 'started', value.handle))

    def accept_native_event(self, value: _NativeAttempt, kind: int, input: _Input) -> None:
        with self._lock:
            self._owned_native(value)
            self._owned_input(input)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            if type(kind) is not int or kind not in (1, 2, 3, 4, 5, 6):
                raise ValueError('Invalid Local Native event kind')
            self._check('accept_native_event', self._call('source', 'accept',
                                                        value.handle, kind, input.handle))

    def close_native_event(self, value: _NativeAttempt) -> bool:
        with self._lock:
            self._owned_native(value)
            code = self._call('source', 'close_event', value.handle)
            if code == -9:
                return False
            self._check('close_native_event', code)
            return True

    def native_source_completed(self, value: _NativeAttempt) -> bool:
        """Core receipt completion only; not a Run success/publication result."""
        with self._lock:
            self._owned_native(value)
            code = self._call('source', 'completed', value.handle)
            if code == -33:
                return False
            self._check('native_source_completed', code)
            return True

    def close_native_attempt(self, value: _NativeAttempt) -> bool:
        with self._lock:
            self._owned_native(value)
            code = self._call('source', 'close_attempt', value.handle)
            if code == -9:
                return False
            self._check('close_native_attempt', code)
            del self._native_loans[value.handle]
            del self._native_observers[value.handle]
            return True

    def _owned_compute(self, value: _Compute) -> None:
        if (type(value) is not _Compute or value.owner is not self._identity
                or self._compute_loans.get(value.handle) is not value):
            raise ValueError('Foreign or released Local Compute configuration')

    def reserve_native_compute(self, attempt: _NativeAttempt, input: _Input) -> _Compute:
        """Issue custody before configuring the exact completed Native capture."""
        with self._lock:
            self._owned_native(attempt)
            self._owned_input(input)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            handle = self._call('compute', 'reserve', attempt.handle, input.handle)
            if handle <= 0:
                raise LocalCoreError('reserve_native_compute', handle)
            value = _Compute(self._identity, handle)
            self._compute_loans[handle] = value
            return value

    def configure_native_compute(self, value: _Compute) -> None:
        """Configuration is not task activation, Run success or publication."""
        with self._lock:
            self._owned_compute(value)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            self._check('configure_native_compute', self._call('compute', 'configure', value.handle))
            self._check('native_compute_configured', self._call('compute', 'configured', value.handle))

    def close_native_compute(self, value: _Compute) -> bool:
        with self._lock:
            self._owned_compute(value)
            code = self._call('compute', 'close', value.handle)
            if code == -9:
                return False
            self._check('close_native_compute', code)
            del self._compute_loans[value.handle]
            return True

    def _owned_task(self, value: _Task) -> None:
        if (type(value) is not _Task or value.owner is not self._identity
                or self._task_loans.get(value.handle) is not value):
            raise ValueError('Foreign or released Local task')

    def reserve_task(self, compute: _Compute, current_configuration: int) -> _Task:
        with self._lock:
            self._owned_compute(compute)
            if (self._closing or type(current_configuration) is not int
                    or current_configuration <= 0):
                raise ValueError('Invalid current Local task configuration')
            handle = self._call('task', 'reserve', compute.handle, current_configuration)
            if handle <= 0:
                raise LocalCoreError('reserve_task', handle)
            value = _Task(self._identity, handle)
            self._task_loans[handle] = value
            return value

    def reserve_next_sdk_task(self, compute: _Compute, current_configuration: int) -> _Task | None:
        """Drive Core's original next task; explicit end is checked there."""
        with self._lock:
            self._owned_compute(compute)
            if (self._closing or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK task configuration')
            handle = self._call('task', 'reserve_next_sdk', compute.handle, current_configuration)
            if type(handle) is not int or not 0 <= handle < 2**31:
                raise LocalCoreError('reserve_next_sdk_task', handle if type(handle) is int else -33)
            if handle == 0:
                return None
            value = _Task(self._identity, handle)
            self._task_loans[handle] = value
            return value

    def start_task(self, value: _Task) -> None:
        self._task_operation(value, 'start')
        self._task_operation(value, 'started')

    def _task_operation(self, value: _Task, operation: str, *arguments: int) -> None:
        with self._lock:
            self._owned_task(value)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            self._check(operation, self._call('task', operation, value.handle, *arguments))

    def feed_task(self, value: _Task, quantum: int) -> bool:
        if type(quantum) is not int or not 0 < quantum <= 2**31 - 1:
            raise ValueError('Invalid Local task quantum')
        with self._lock:
            self._task_operation(value, 'feed', quantum)
            code = self._call('task', 'inputs_ready', value.handle)
            if code == -7:
                return False
            self._check('task_inputs_ready', code)
            return True

    def advance_task(self, value: _Task, quantum: int, *, finalization: bool = False) -> LocalTaskProgress:
        if (type(quantum) is not int or not 0 < quantum <= 2**31 - 1
                or type(finalization) is not bool):
            raise ValueError('Invalid Local task quantum')
        with self._lock:
            self._task_operation(value, 'advance_finalization' if finalization else 'advance', quantum)
            fields = [self._call('task', 'progress', value.handle, index) for index in range(4)]
            if fields[0] not in (0, 1) or fields[1] not in (0, 1) or min(fields[2:]) < 0:
                raise LocalCoreError('task_progress', -33)
            return LocalTaskProgress(fields[0] == 1, fields[1] == 1, fields[2], fields[3])

    def prepare_task_finalization(self, value: _Task) -> None:
        self._task_operation(value, 'prepare_finalization')

    def complete_task(self, value: _Task) -> None:
        self._task_operation(value, 'complete')

    def close_task(self, value: _Task) -> bool:
        with self._lock:
            self._owned_task(value)
            code = self._call('task', 'close', value.handle)
            if code == -9:
                return False
            self._check('close_task', code)
            del self._task_loans[value.handle]
            return True

    def reserve_native_command(self, attempt: _NativeAttempt, kind: int, account: _Input, *,
                               cleanup: Callable[[], bool]) -> _Output:
        """Borrow current authority and reserve one Core-issued command copy.

        A positive handle retains custody even when output reservation was
        refused. Producing a command is not physical dispatch or Run admission.
        """
        with self._lock:
            self._owned_input(account)
            self._owned_native(attempt)
            if (self._closing or
                    type(kind) is not int or kind not in (1, 2, 3)):
                raise ValueError('Invalid Local Native command projection')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 100_000
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit) + sys.getsizeof(
                                  _Output(self._identity, ticket, 0, limit, 'source')))
            handle = self._call('source', 'reserve_command', attempt.handle, kind,
                                account.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_native_command', handle)
            value = _Output(self._identity, ticket, handle, limit, 'source')
            self._loans[ticket] = value
            return value

    def _owned_result(self, value: _ResultExport) -> None:
        if (type(value) is not _ResultExport or value.owner is not self._identity
                or self._result_loans.get(value.handle) is not value):
            raise ValueError('Foreign or released Local Result export')

    def reserve_result_export(self, task: _Task, index: int) -> _ResultExport:
        with self._lock:
            self._owned_task(task)
            if self._closing or type(index) is not int or not 0 <= index <= 2**31 - 1:
                raise ValueError('Invalid Local Named Result selection')
            handle = self._call('result', 'reserve', task.handle, index)
            if handle <= 0:
                raise LocalCoreError('reserve_result', handle)
            result = _ResultExport(self._identity, handle)
            self._result_loans[handle] = result
            return result

    def reserve_result_from_compute(self, compute: _Compute, index: int,
                                    current_configuration: int) -> _ResultExport:
        """Core maps original inventory ordinal to its completed producer."""
        with self._lock:
            self._owned_compute(compute)
            if (self._closing or type(index) is not int or not 0 <= index < 2**31
                    or type(current_configuration) is not int
                    or not 0 < current_configuration < 2**31):
                raise ValueError('Invalid original SDK Result selection')
            handle = self._call('result', 'reserve_from_compute', compute.handle, index,
                                current_configuration)
            if type(handle) is not int or not 0 < handle < 2**31:
                raise LocalCoreError('reserve_result_from_compute', handle if type(handle) is int else -33)
            result = _ResultExport(self._identity, handle)
            self._result_loans[handle] = result
            return result

    def _result_operation(self, result: _ResultExport, operation: str, *arguments: int) -> None:
        self._owned_result(result)
        if self._closing:
            raise RuntimeError('Local Core is closing')
        self._check(operation, self._call('result', operation, result.handle, *arguments))

    def start_result_export(self, result: _ResultExport) -> None:
        with self._lock:
            self._result_operation(result, 'start')

    def feed_result_export(self, result: _ResultExport, quantum: int) -> bool:
        if type(quantum) is not int or not 0 < quantum <= 2**31 - 1:
            raise ValueError('Invalid Local Result quantum')
        with self._lock:
            self._result_operation(result, 'feed', quantum)
            code = self._call('result', 'inputs_ready', result.handle)
            if code == -7:
                return False
            self._check('result_inputs_ready', code)
            return True

    def advance_result_export(self, result: _ResultExport, quantum: int) -> LocalResultProgress:
        if type(quantum) is not int or not 0 < quantum <= 2**31 - 1:
            raise ValueError('Invalid Local Result quantum')
        with self._lock:
            self._result_operation(result, 'advance', quantum)
            ready = self._call('result', 'progress', result.handle, 0)
            work = self._call('result', 'progress', result.handle, 1)
            if ready not in (0, 1) or work < 0:
                raise LocalCoreError('result_progress', -33)
            return LocalResultProgress(ready == 1, work)

    def finish_result_export_preparation(self, result: _ResultExport) -> None:
        with self._lock:
            self._result_operation(result, 'finish_preparation')

    def reserve_result_chunk(self, result: _ResultExport, *, cleanup: Callable[[], bool]) -> _Output:
        with self._lock:
            self._owned_result(result)
            if self._closing or not callable(cleanup):
                raise ValueError('Invalid Local Result chunk custody')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 65_536
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (self._output_copy_bytes(limit)
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'result')))
            handle = self._call('result', 'reserve_chunk', result.handle, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_result_chunk', handle)
            chunk = _Output(self._identity, ticket, handle, limit, 'result')
            self._loans[ticket] = chunk
            return chunk

    def produce_result_chunk(self, chunk: _Output) -> None:
        self._produce_output(chunk, 'result', 'produce_chunk')

    def read_result_chunk(self, chunk: _Output) -> tuple[bytes, bool]:
        with self._lock:
            wire = self._read_output(chunk, 'result', 'chunk_length')
            final = self._call('result', 'chunk_final', chunk.handle)
            if final not in (0, 1):
                raise LocalCoreError('result_chunk_final', final)
            return wire, final == 1

    def result_chunk_finished(self, chunk: _Output) -> bool:
        """Inspect only the original export finish marker, without copying rows."""
        with self._lock:
            self._owned_output(chunk, 'result')
            code = self._call('result', 'chunk_final', chunk.handle)
            if type(code) is not int or code not in (0, 1):
                raise LocalCoreError('result_chunk_final', code if type(code) is int else -33)
            return code == 1

    def close_result_chunk(self, chunk: _Output) -> bool:
        return self._close_output(chunk, 'result', 'close_chunk')

    def close_result_export(self, result: _ResultExport) -> bool:
        with self._lock:
            self._owned_result(result)
            code = self._call('result', 'close', result.handle)
            if code == -9:
                return False
            self._check('close_result', code)
            del self._result_loans[result.handle]
            return True

    def produce_material(self, value: _Output) -> None:
        self._produce_output(value, 'material', 'produce')

    def validate_submitted_run_rows(self, value: _Output, current: _Output) -> None:
        """Revalidate the same Core candidate inside the original Store frame.

        No Python count, row comparison or acceptance decision substitutes for
        the existing Core supplier. This is inspection, not a COMMIT ACK.
        """
        with self._lock:
            self._owned_output(value)
            self._host_current_ready(current)
            code = self._call('material', 'validate_submitted_rows', value.handle)
            callbacks = self._journal_callbacks(current.ticket)
            if callbacks is not None and callbacks.failure is not None:
                raise callbacks.failure
            self._check('validate_submitted_run_rows', code)
            self._host_current_ready(current)

    def read_submitted_run_rows(self, value: _Output, current: _Output) -> bytes:
        """Keep cached transport bytes subordinate to fresh current/Store checks."""
        with self._lock:
            self.validate_submitted_run_rows(value, current)
            raw = self._read_output(value, 'material', 'length')
            self._host_current_ready(current)
            return raw

    def _sdk_start_material_current(self, value: _Output, current: _Output, operation: str) -> None:
        self._owned_output(value)
        self._host_current_ready(current)
        self._owned_output(value)
        self._owned_output(current, 'current')
        code = self._call('material', operation, value.handle)
        callbacks = self._journal_callbacks(current.ticket)
        if callbacks is not None and callbacks.failure is not None:
            raise callbacks.failure
        self._check(operation, code)
        self._host_current_ready(current)
        self._owned_output(value)
        self._owned_output(current, 'current')

    def validate_sdk_start_step(self, value: _Output, current: _Output) -> None:
        with self._lock:
            self._sdk_start_material_current(value, current, 'validate_sdk_start')

    def read_sdk_start_step(self, value: _Output, current: _Output) -> bytes:
        with self._lock:
            self._sdk_start_material_current(value, current, 'validate_sdk_start')
            raw = self._read_output(value, 'material', 'length')
            self._host_current_ready(current)
            return raw

    def confirm_sdk_start_step(self, value: _Output, current: _Output) -> None:
        """Read original saved CAS successor; not a candidate or IO permission."""
        with self._lock:
            self._sdk_start_material_current(value, current, 'confirm_sdk_start')

    def validate_sdk_publication_binding(self, value: _Output, current: _Output) -> None:
        """Recheck original Common candidate/current in the same Store frame."""
        with self._lock:
            self._sdk_start_material_current(value, current, 'validate_sdk_publication')

    def read_sdk_publication_binding(self, value: _Output, current: _Output) -> bytes:
        with self._lock:
            self._sdk_start_material_current(value, current, 'validate_sdk_publication')
            raw = self._read_output(value, 'material', 'length')
            self._host_current_ready(current)
            return raw

    def confirm_sdk_publication_binding(self, value: _Output, current: _Output) -> None:
        """Adopt actual saved binding, never a publication ACK or permission Bool."""
        with self._lock:
            self._sdk_start_material_current(value, current, 'confirm_sdk_publication')

    def retire_material_output(self, value: _Output) -> bool:
        """Release transport only; original Core proof/borrow/children survive."""
        with self._lock:
            self._owned_output(value)
            code = self._call('material', 'retire_output', value.handle)
            if code == -9:
                return False
            self._check('retire_material_output', code)
            return True

    def produce_native_command(self, value: _Output) -> None:
        self._produce_output(value, 'source', 'produce_command')

    def _produce_output(self, value: _Output, family: str, operation: str) -> None:
        with self._lock:
            self._owned_output(value, family)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            self._check(operation, self._call(family, operation, value.handle))

    def read_material(self, value: _Output) -> bytes:
        return self._read_output(value, 'material', 'length')

    def read_native_command(self, value: _Output) -> bytes:
        return self._read_output(value, 'source', 'command_length')

    def _read_output(self, value: _Output, family: str, operation: str, *, abi_family: str | None = None) -> bytes:
        """Copy exact Core bytes within the same pre-reserved physical loan."""
        with self._lock:
            self._owned_output(value, family)
            physical = self._inputs.get(value.ticket)
            if physical is None:
                raise RuntimeError('Local projection cleanup has completed')
            if physical.payload:
                return physical.payload
            length = self._call(abi_family if abi_family is not None else family, operation, value.handle)
            if not 0 <= length <= value.limit:
                raise LocalCoreError(operation, length)
            destination = bytearray(length)
            if getattr(self, '_ordinary_host', False):
                for start in range(0, length, 16384):
                    count = min(16384, length - start)
                    destination[start:start + count] = self._read_output_block(value, start, count)
            else:
                # The explicit raw diagnostic facade retains its scalar ABI.
                # An ordinary block refusal never selects this separate route.
                for start in range(0, length, 7):
                    count = min(7, length - start)
                    packed = self._call('buffer', 'read_packed', value.handle, start, count)
                    if not 0 <= packed < 1 << (8 * count):
                        raise LocalCoreError('projection_bytes', packed)
                    for offset in range(count):
                        destination[start + offset] = packed & 255
                        packed >>= 8
            physical.payload = bytes(destination)
            return physical.payload

    def close_material(self, value: _Output) -> bool:
        return self._close_output(value, 'material', 'close')

    def close_native_command(self, value: _Output) -> bool:
        return self._close_output(value, 'source', 'close_command')

    def _close_output(self, value: _Output, family: str, operation: str, *, abi_family: str | None = None) -> bool:
        with self._lock:
            self._owned_output(value, family)
            code = self._call(abi_family if abi_family is not None else family, operation, value.handle)
            if code == -9:
                return False
            self._check(operation, code)
            self._loans.pop(value.ticket)
            self._released.discard(value.ticket)
            return True

    def fill_input(self, value: _Input, start: int, count: int) -> None:
        with self._lock:
            self._owned_input(value)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            operation = 'fill_block' if getattr(self, '_ordinary_host', False) else 'fill'
            self._check('fill', self._call('buffer', operation, value.handle, start, count))

    def seal_input(self, value: _Input) -> None:
        with self._lock:
            self._owned_input(value)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            self._check('seal', self._call('buffer', 'seal', value.handle))

    def close_input(self, value: _Input) -> bool:
        with self._lock:
            self._owned_input(value)
            code = self._call('buffer', 'close', value.handle)
            if code == -9:
                return False
            self._check('close', code)
            self._loans.pop(value.ticket)
            self._released.discard(value.ticket)
            return True

    def close(self) -> bool:
        with self._host_cleanup():
            return self._close_core()

    def _close_core(self) -> bool:
        """Keep the same instance on pending cleanup; do not cancel a Run."""
        with self._lock:
            if self._closed:
                return True
            self._closing = True
            if not self._retired:
                code = self._call('buffer', 'close_pool')
                if code == -9:
                    return False
                self._check('close_pool', code)
                self._retired = True
            self._dispose()
            return True

    def _dispose(self) -> None:
        # Pinned Wasmtime Store owns an Engine clone and the live instance.
        # Keep the Store, and therefore the original Wasm Root, until every
        # other native handle has retired. A failed child/Engine cleanup must
        # not destroy that Root or drop its pending capacity first.
        image: _NativeImageHolding | None = getattr(self, '_physical_image', None)
        if image is not None:
            image.close()
            self._physical_image = None
        if any(getattr(self, name, None) is not None for name in
               ('_physical_vm_type', '_linker', '_module', '_engine', '_engine_configuration',
                '_pool_configuration', '_store')):
            with self._native_scope():
                for name in ('_physical_vm_type', '_linker', '_module', '_engine', '_engine_configuration'):
                    value = getattr(self, name, None)
                    if value is not None:
                        value.close()
                        setattr(self, name, None)
                if getattr(self, '_pool_configuration', None) is not None:
                    self._pool_ffi.wasmtime_pooling_allocation_config_delete(self._pool_configuration)
                    self._pool_configuration = None
                if getattr(self, '_store', None) is not None:
                    self._store.close()
                    self._store = None
                    # This VM reservation no longer exists after Store success,
                    # even when the original outer holding still needs unmap.
                    self._physical_vm_span = None
        holding: _NativeHoldingLease | None = getattr(self, '_physical_holding', None)
        if holding is not None:
            # Store success retires the executable Wasm Root. A final native
            # unmap failure retains only this same Core identity and original
            # holding for physical retirement retry; never reopen that Root or
            # repeat already retired Store/native handles.
            holding.close()
            self._physical_holding = None
        observation = getattr(self, '_physical_vm_observation', None)
        if observation is not None:
            observation._retire_metadata(self)
            self._physical_vm_observation = None
        child_control = getattr(self, '_physical_child_control', None)
        if child_control is not None:
            child_control._retire_metadata(self)
            self._physical_child_control = None
        self._closed = True
        self._physical_vm_span = None
        self._inputs.clear()
        self._loans.clear()
        self._released.clear()
        self._native_observers.clear()
        self._native_loans.clear()
        self._compute_loans.clear()
        self._task_loans.clear()
        self._result_loans.clear()
