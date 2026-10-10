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


@dataclass(frozen=True, slots=True, eq=False)
class _Input:
    owner: object
    ticket: int
    handle: int
    length: int


@dataclass(slots=True)
class _PhysicalInput:
    payload: bytes
    cleanup: Callable[[], bool]
    stopped: Callable[[int], bool]


# This is the private in-process ABI, independent of Client wire versions.
_BUFFER_SIGNATURES = {
    'open': ('i64 i64 i32 i32', 'i32'),
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
    'reserve_preparation': ('i64 i32 i32 i32', 'i32'),
    'prepare': ('i64 i32', 'i32'),
    'prepared_results': ('i64 i32', 'i32'),
    'prepared_tasks': ('i64 i32', 'i32'),
    'close_preparation': ('i64 i32', 'i32'),
    'close_environment': ('i64 i32', 'i32'),
}
_RUN_SIGNATURES = {
    'install_configuration': ('i64 i32', 'i32'),
    'reserve': ('i64 i32 i32 i32', 'i32'),
    'prepare': ('i64 i32', 'i32'),
    'prepared': ('i64 i32', 'i32'),
    'close': ('i64 i32', 'i32'),
    'close_configuration': ('i64 i32', 'i32'),
}
_IMPORT_SIGNATURES = {
    'input_byte': ('i32 i32', 'i32'),
    'input_cleanup': ('i32', 'i32'),
    'reader_stop': ('i32 i32', 'i32'),
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

    def __init__(self, module: bytes, *, digest: str, transfer_capacity: int,
                 slots: int = 32, fuel: int = 100_000_000) -> None:
        if (type(module) is not bytes or hashlib.sha256(module).hexdigest() != digest
                or type(transfer_capacity) is not int
                or not 0 < transfer_capacity <= 2**63 - 1
                or type(slots) is not int or not 1 <= slots <= 1024
                or type(fuel) is not int or not 0 < fuel <= 2**64 - 1):
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
        self._loans: dict[int, _Input] = {}
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
                                   ('reader_stop', self._stopped)]:
                params = [wasmtime.ValType.i32()
                          for _ in _IMPORT_SIGNATURES[name][0].split()]
                self._linker.define_func('actql_host', name,
                    wasmtime.FuncType(params, [wasmtime.ValType.i32()]), callback)
            instance = self._linker.instantiate(self._store, self._module)
            self._exports = instance.exports(self._store)
            if self._exports['actql_host_abi_version'](self._store) != 1:
                raise ValueError('Unsupported Local Core ABI version')
            self._check('open', self._call('buffer', 'open', transfer_capacity,
                                        slots, 1_048_576))
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

    def _owned(self, value: _Input) -> None:
        if (value.owner is not self._identity or
                self._loans.get(value.ticket) is not value):
            raise ValueError('Foreign or released Local input')

    def fill_input(self, value: _Input, start: int, count: int) -> None:
        with self._lock:
            self._owned(value)
            self._check('fill', self._call('buffer', 'fill', value.handle, start, count))

    def seal_input(self, value: _Input) -> None:
        with self._lock:
            self._owned(value)
            self._check('seal', self._call('buffer', 'seal', value.handle))

    def close_input(self, value: _Input) -> bool:
        with self._lock:
            self._owned(value)
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
