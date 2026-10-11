"""Private physical Wasm bridge. Run decisions remain in MoonBit Core."""
from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
import hashlib
from importlib import import_module
import secrets
import sys
from threading import RLock
from typing import Any


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
    """Trusted installed Host limits, independent of instruction fuel."""

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


@dataclass(slots=True)
class _PhysicalInput:
    payload: bytes
    cleanup: Callable[[], bool]
    stopped: Callable[[int], bool]


@dataclass(frozen=True, slots=True, eq=False)
class _Output:
    owner: object
    ticket: int
    handle: int
    limit: int
    family: str = "material"


# This is the private in-process ABI, independent of Client wire versions.
_BUFFER_SIGNATURES = {
    'open': ('i64 i64 i32 i32 i32 i32 i32 i64 i64 i64', 'i32'),
    'reserve': ('i64 i32 i32 i64', 'i32'),
    'fill': ('i64 i32 i32 i32', 'i32'),
    'seal': ('i64 i32', 'i32'),
    'byte': ('i64 i32 i32', 'i32'),
    'borrow': ('i64 i32', 'i32'),
    'return': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
    'allocated': ('i64', 'i64'),
    'reserved': ('i64', 'i64'),
    'close_pool': ('i64', 'i32'),
}
_PROGRAM_SIGNATURES = {
    'install_environment': ('i64 i32', 'i32'),
    'install_source_environment': ('i64 i32', 'i32'),
    'reserve_preparation': ('i64 i32 i32 i32', 'i32'),
    'prepare': ('i64 i32', 'i32'),
    'prepared_results': ('i64 i32', 'i32'),
    'prepared_tasks': ('i64 i32', 'i32'),
    'close_preparation': ('i64 i32', 'i32'),
    'close_environment': ('i64 i32', 'i32'),
}
_RUN_SIGNATURES = {
    'dispatch_action': ('i64 i32 i32 i32', 'i32'),
    'install_configuration': ('i64 i32', 'i32'),
    'reserve': ('i64 i32 i32 i32', 'i32'),
    'prepare': ('i64 i32', 'i32'),
    'restore': ('i64 i32 i32', 'i32'),
    'prepared': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
    'close_configuration': ('i64 i32', 'i32'),
    'reserve_physical_start': ('i64 i32 i32 i32', 'i32'),
    'confirm_physical_start': ('i64 i32', 'i32'),
    'physical_start_ready': ('i64 i32', 'i32'),
    'close_physical_start': ('i64 i32', 'i32'),
}
_SUBMISSION_SIGNATURES = {
    'reserve': ('i64 i32 i32 i32 i32 i64', 'i32'),
    'produce': ('i64 i32', 'i32'),
    'length': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
}
_SOURCE_PUBLICATION_SIGNATURES = {
    'reserve': ('i64 i32 i32 i32 i64', 'i32'),
    'prepare': ('i64 i32 i32', 'i32'),
    'advance': ('i64 i32 i32', 'i32'),
    'progress': ('i64 i32 i32', 'i64'),
    'finish': ('i64 i32 i32', 'i32'),
    'length': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
}
_MATERIAL_SIGNATURES = {
    'reserve': ('i64 i32 i32 i32 i64', 'i32'),
    'produce': ('i64 i32', 'i32'),
    'length': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
    'reserve_restoration': ('i64 i32', 'i32'),
    'restore': ('i64 i32', 'i32'),
    'restored': ('i64 i32', 'i32'),
    'close_restoration': ('i64 i32', 'i32'),
}
_PUBLICATION_SIGNATURES = {
    'reserve': ('i64 i32 i32 i32 i64', 'i32'),
    'prepare': ('i64 i32 i32', 'i32'),
    'advance': ('i64 i32 i32 i32', 'i32'),
    'progress': ('i64 i32 i32', 'i64'),
    'finish': ('i64 i32 i32', 'i32'),
    'length': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
    'prepare_commit': ('i64 i32 i32 i32', 'i32'),
    'advance_commit': ('i64 i32 i32 i32', 'i32'),
    'commit_progress': ('i64 i32 i32', 'i64'),
    'finish_commit': ('i64 i32 i32', 'i32'),
}
_PUBLICATION_PREFLIGHT_SIGNATURES = {
    'reserve': ('i64 i32 i32 i32 i64', 'i32'),
    'prepare': ('i64 i32 i32', 'i32'),
    'length': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
}
_PUBLICATION_COMMIT_EXPORT_SIGNATURES = {
    'reserve': ('i64 i32 i32 i64', 'i32'),
    'produce': ('i64 i32 i32', 'i32'),
    'length': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
}
_RESULT_BINDING_SIGNATURES = {
    'reserve': ('i64 i32 i32 i32 i32 i64', 'i32'),
    'produce': ('i64 i32 i32', 'i32'),
    'length': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
}
_SOURCE_SIGNATURES = {
    'reserve_configuration': ('i64 i32 i32', 'i32'),
    'configure': ('i64 i32', 'i32'),
    'configured': ('i64 i32', 'i32'),
    'configuration_issue': ('i64 i32', 'i32'),
    'capacity': ('i64 i32 i32', 'i64'),
    'close_configuration': ('i64 i32', 'i32'),
    'reserve_attempt': ('i64 i32 i32 i32', 'i32'),
    'start': ('i64 i32', 'i32'),
    'started': ('i64 i32', 'i32'),
    'close_attempt': ('i64 i32', 'i32'),
    'accept': ('i64 i32 i32 i32', 'i32'),
    'completed': ('i64 i32', 'i32'),
    'close_event': ('i64 i32', 'i32'),
    'reserve_command': ('i64 i32 i32 i32 i32 i64', 'i32'),
    'produce_command': ('i64 i32', 'i32'),
    'command_length': ('i64 i32', 'i32'),
    'close_command': ('i64 i32', 'i32'),
}
_TASK_SIGNATURES = {
    'reserve': ('i64 i32 i32', 'i32'),
    'start': ('i64 i32', 'i32'),
    'started': ('i64 i32', 'i32'),
    'issue': ('i64 i32', 'i32'),
    'assessment': ('i64 i32 i32 i32', 'i64'),
    'feed': ('i64 i32 i32', 'i32'),
    'inputs_ready': ('i64 i32', 'i32'),
    'advance': ('i64 i32 i32', 'i32'),
    'progress': ('i64 i32 i32', 'i64'),
    'prepare_finalization': ('i64 i32', 'i32'),
    'advance_finalization': ('i64 i32 i32', 'i32'),
    'complete': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
}
_COMPUTE_SIGNATURES = {
    'reserve': ('i64 i32 i32', 'i32'),
    'configure': ('i64 i32', 'i32'),
    'configured': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
}
_RESULT_SIGNATURES = {
    'reserve': ('i64 i32 i32', 'i32'),
    'start': ('i64 i32', 'i32'),
    'feed': ('i64 i32 i32', 'i32'),
    'inputs_ready': ('i64 i32', 'i32'),
    'advance': ('i64 i32 i32', 'i32'),
    'progress': ('i64 i32 i32', 'i32'),
    'finish_preparation': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
    'reserve_chunk': ('i64 i32 i32 i64', 'i32'),
    'produce_chunk': ('i64 i32', 'i32'),
    'chunk_length': ('i64 i32', 'i32'),
    'chunk_final': ('i64 i32', 'i32'),
    'close_chunk': ('i64 i32', 'i32'),
}
_WORKSPACE_SIGNATURES = {
    'reserve': ('i64 i32 i64', 'i32'),
    'close': ('i64 i32', 'i32'),
    'root_reserved': ('i64', 'i64'),
}
_IMPORT_SIGNATURES = {
    'input_byte': ('i32 i32', 'i32'),
    'input_cleanup': ('i32', 'i32'),
    'reader_stop': ('i32 i32', 'i32'),
    'native_settled': ('i32', 'i32'),
    'native_stopped': ('i32', 'i32'),
    'native_cleaned': ('i32', 'i32'),
}
_MEMORY_LIMIT = 16 * 1024 * 1024


def _signature(value: Any) -> tuple[str, str]:
    return (' '.join(str(item) for item in value.params),
            ' '.join(str(item) for item in value.results))


class LocalCore:
    """Serialize calls into one instance and preserve its physical custody.

    This bridge does not implement Client routing, admission, recovery, or a
    global memory guarantee. The installed Host must reserve the full Wasm
    allowance and its other holdings in the existing shared capacity Owner.
    """

    def __init__(self, module: bytes, *, digest: str, transfer_capacity: int, resources: LocalCoreResources,
                 slots: int = 32, fuel: int = 100_000_000) -> None:
        if (type(module) is not bytes or hashlib.sha256(module).hexdigest() != digest
                or type(transfer_capacity) is not int
                or not 0 < transfer_capacity <= 2**63 - 1
                or type(slots) is not int or not 1 <= slots <= 1024
                or type(fuel) is not int or not 0 < fuel <= 2**64 - 1
                or type(resources) is not LocalCoreResources or not resources.valid()
                or transfer_capacity > resources.execution_bytes - _MEMORY_LIMIT):
            raise ValueError('Invalid installed Local Core artifact or capacity')
        # Remote-only imports never import or initialize the optional engine.
        try:
            wasmtime = import_module('wasmtime')
        except ImportError as error:
            raise RuntimeError('Python Local requires the optional Wasmtime runtime') from error
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
        self._engine: Any = None
        self._store: Any = None
        self._module: Any = None
        self._linker: Any = None
        try:
            config = wasmtime.Config()
            config.consume_fuel = True
            self._engine = wasmtime.Engine(config)
            self._store = wasmtime.Store(self._engine)
            self._store.set_fuel(fuel)
            self._store.set_limits(memory_size=_MEMORY_LIMIT, memories=1)
            self._module = wasmtime.Module(self._engine, module)
            imports = self._module.imports
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
            expected.update({'actql_run_' + name: value
                             for name, value in _RUN_SIGNATURES.items()})
            expected.update({'actql_submission_' + name: value
                             for name, value in _SUBMISSION_SIGNATURES.items()})
            expected.update({'actql_source_publication_' + name: value
                             for name, value in _SOURCE_PUBLICATION_SIGNATURES.items()})
            expected.update({'actql_material_' + name: value
                             for name, value in _MATERIAL_SIGNATURES.items()})
            expected.update({'actql_publication_' + name: value
                             for name, value in _PUBLICATION_SIGNATURES.items()})
            expected.update({'actql_publication_preflight_' + name: value
                             for name, value in _PUBLICATION_PREFLIGHT_SIGNATURES.items()})
            expected.update({'actql_publication_commit_export_' + name: value
                             for name, value in _PUBLICATION_COMMIT_EXPORT_SIGNATURES.items()})
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
            expected['actql_host_abi_version'] = ('', 'i32')
            exports = {item.name: item.type for item in self._module.exports}
            if (any(name not in exports or
                    not isinstance(exports[name], wasmtime.FuncType) or
                    _signature(exports[name]) != signature
                    for name, signature in expected.items()) or
                    any(name.startswith('actql_') and name not in expected
                        for name in exports)):
                raise ValueError('Unrecognized Local Core exports')
            memory = exports.get('memory')
            if (not isinstance(memory, wasmtime.MemoryType) or memory.is_64 or
                    memory.is_shared or memory.limits.max != 256 or
                    memory.limits.min > 256):
                raise ValueError('Unbounded Local Core linear memory')
            self._linker = wasmtime.Linker(self._engine)
            for name, callback in [('input_byte', self._read),
                                   ('input_cleanup', self._cleanup),
                                   ('reader_stop', self._stopped),
                                   ('native_settled', self._native_settled),
                                   ('native_stopped', self._native_stopped),
                                   ('native_cleaned', self._native_cleaned)]:
                params = [wasmtime.ValType.i32()
                          for _ in _IMPORT_SIGNATURES[name][0].split()]
                self._linker.define_func('actql_host', name,
                    wasmtime.FuncType(params, [wasmtime.ValType.i32()]), callback)
            instance = self._linker.instantiate(self._store, self._module)
            self._exports = instance.exports(self._store)
            if self._exports['actql_host_abi_version'](self._store) != 23:
                raise ValueError('Unsupported Local Core ABI version')
            self._check('open', self._call('buffer', 'open', transfer_capacity,
                                        slots, 1_048_576, resources.planning_work,
                                        resources.attempts, resources.holdings,
                                        resources.transfer_bytes, resources.retained_bytes,
                                        resources.execution_bytes))
        except BaseException as error:
            self._retired = True
            self._closing = True
            try:
                self._dispose()
            except Exception:
                raise LocalCoreInitializationError(self) from error
            raise

    def _call(self, family: str, name: str, *arguments: int) -> int:
        if self._closed or self._retired:
            raise RuntimeError('Local Core is closed')
        if self._invoking:
            raise RuntimeError('Local Core callbacks cannot reenter the instance')
        self._invoking = True
        try:
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
                                sys.getsizeof(payload))
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
                    not 0 < configuration < 2**31 or type(kind) is not int or kind not in (1, 2)):
                raise ValueError('Invalid Local Submission projection')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 4096
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) + sys.getsizeof(b'')
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'submission')))
            handle = self._call('submission', 'reserve', configuration, source.handle,
                                kind, ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_submission_projection', handle)
            value = _Output(self._identity, ticket, handle, limit, 'submission')
            self._loans[ticket] = value
            return value

    def produce_submission_projection(self, value: _Output) -> None:
        self._produce_output(value, 'submission', 'produce')

    def read_submission_projection(self, value: _Output) -> bytes:
        return self._read_output(value, 'submission', 'length')

    def close_submission_projection(self, value: _Output) -> bool:
        return self._close_output(value, 'submission', 'close')

    def reserve_source_publication(self, compute: _Compute, source: _Input, *,
                                   cleanup: Callable[[], bool]) -> _Output:
        """Borrow the original acquisition; never fetch it or publish a Run."""
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
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) + sys.getsizeof(b'')
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit, 'source_publication')))
            handle = self._call('source_publication', 'reserve', compute.handle, source.handle,
                                ticket, physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_source_publication', handle)
            value = _Output(self._identity, ticket, handle, limit, 'source_publication')
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

    def reserve_publication_preflight(self, source: _Output, request: _Input, *,
                                      cleanup: Callable[[], bool]) -> _Output:
        """Private original intent before Compute; grants no Store permission."""
        with self._lock:
            self._owned_output(source, 'source_publication')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) + sys.getsizeof(b'')
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

    def read_publication_preflight(self, value: _Output) -> bytes:
        return self._read_output(value, 'publication_preflight', 'length')

    def close_publication_preflight(self, value: _Output) -> bool:
        return self._close_output(value, 'publication_preflight', 'close')

    def reserve_publication(self, source: _Output, request: _Input, *,
                            cleanup: Callable[[], bool]) -> _Output:
        """Private complete Result capture; not a durable publication commit."""
        with self._lock:
            self._owned_output(source, 'source_publication')
            self._owned_input(request)
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) + sys.getsizeof(b'')
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
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) + sys.getsizeof(b'')
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

    def reserve_publication_commit_export(self, publication: _Output, *,
                                          cleanup: Callable[[], bool]) -> _Output:
        """Read the original validated candidate; grants no Store permission."""
        with self._lock:
            self._owned_output(publication, 'publication')
            if self._closing:
                raise RuntimeError('Local Core is closing')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) + sys.getsizeof(b'')
                              + sys.getsizeof(_Output(self._identity, ticket, 0, limit,
                                                      'publication_commit_export')))
            handle = self._call('publication_commit_export', 'reserve',
                                publication.handle, ticket, physical_bytes)
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

    def read_publication_commit_export(self, value: _Output) -> bytes:
        return self._read_output(value, 'publication_commit_export', 'length')

    def close_publication_commit_export(self, value: _Output) -> bool:
        return self._close_output(value, 'publication_commit_export', 'close')

    def reserve_material(self, run: int, kind: int, *,
                         cleanup: Callable[[], bool]) -> _Output:
        """Private Host projection; neither Run admission nor durable storage.

        The Host retains the returned loan through persistence and cleanup.
        Its trusted Run handle belongs to this instance; it is not a wire ref.
        """
        with self._lock:
            if (self._closing or type(run) is not int or run <= 0 or
                    type(kind) is not int or kind not in (1, 2, 3, 4, 5)):
                raise ValueError('Invalid Local material projection')
            ticket = self._next_ticket
            if ticket >= 2**31:
                raise RuntimeError('Local Core input identity exhausted')
            self._next_ticket += 1
            limit = 1_048_576
            # Register physical custody before entering Wasm, but allocate
            # the large destination only after Core reserves its capacity.
            self._inputs[ticket] = _PhysicalInput(b'', cleanup, lambda _: True)
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) +
                              sys.getsizeof(b'') +
                              sys.getsizeof(_Output(self._identity, ticket, 0, limit)))
            handle = self._call('material', 'reserve', run, kind, ticket,
                                physical_bytes)
            if handle <= 0:
                del self._inputs[ticket]
                raise LocalCoreError('reserve_material', handle)
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
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) +
                              sys.getsizeof(b'') + sys.getsizeof(
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
            physical_bytes = (2 * limit + sys.getsizeof(bytearray()) + sys.getsizeof(b'')
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

    def _read_output(self, value: _Output, family: str, operation: str) -> bytes:
        """Copy exact Core bytes within the same pre-reserved physical loan."""
        with self._lock:
            self._owned_output(value, family)
            physical = self._inputs.get(value.ticket)
            if physical is None:
                raise RuntimeError('Local projection cleanup has completed')
            if physical.payload:
                return physical.payload
            length = self._call(family, operation, value.handle)
            if not 0 <= length <= value.limit:
                raise LocalCoreError(operation, length)
            destination = bytearray(length)
            for start in range(0, length, 16_384):
                for index in range(start, min(start + 16_384, length)):
                    byte = self._call('buffer', 'byte', value.handle, index)
                    if not 0 <= byte <= 255:
                        raise LocalCoreError('projection_byte', byte)
                    destination[index] = byte
            physical.payload = bytes(destination)
            return physical.payload

    def close_material(self, value: _Output) -> bool:
        return self._close_output(value, 'material', 'close')

    def close_native_command(self, value: _Output) -> bool:
        return self._close_output(value, 'source', 'close_command')

    def _close_output(self, value: _Output, family: str, operation: str) -> bool:
        with self._lock:
            self._owned_output(value, family)
            code = self._call(family, operation, value.handle)
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
            self._check('fill', self._call('buffer', 'fill', value.handle, start, count))

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
        for name in ('_store', '_linker', '_module', '_engine'):
            value = getattr(self, name)
            if value is not None:
                value.close()
                setattr(self, name, None)
        self._closed = True
        self._inputs.clear()
        self._loans.clear()
        self._released.clear()
        self._native_observers.clear()
        self._native_loans.clear()
        self._compute_loans.clear()
        self._task_loans.clear()
        self._result_loans.clear()
