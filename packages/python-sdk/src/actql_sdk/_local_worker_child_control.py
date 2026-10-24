"""Same child pipe/borrow binding for the fixed Core execution imports.

Only physical control bytes cross the original pipe. Complete pre-spawn and
independent Python/control/FD funding remain mandatory installed inputs; this
port is neither their supplier nor a public Client setting.
"""
from __future__ import annotations

import fcntl
import os
import stat
from threading import Thread, current_thread
from typing import TYPE_CHECKING, Any, NoReturn

from . import _local_worker_control_frames as frames
from ._local_native_domain_borrow import _OriginalDomainBorrow, _OriginalDomainBorrowFunctions
from ._local_native_domain_custody import _OriginalDomainMaterial
from ._local_worker_slot import _OriginalDescriptor

if TYPE_CHECKING:
    from ._local_core import LocalCore
    from ._local_native_holding import _NativeHoldingLease
    from ._local_native_vm import _OriginalVMObservation


class _OriginalChildControlPending(RuntimeError):
    def __init__(self, control: _OriginalChildControlPipe) -> None:
        self.cleanup_control = control
        super().__init__('Original child control transport remains unconfirmed')


class _OriginalChildControlPipe:
    """Synchronous bounded physical bytes during an original Wasmtime Caller.

    Do not await, move the Caller to a thread or synthesize Owner outcomes.
    Sequence numbers are correlation only. Unknown preserves the original
    request/partial response and prevents another physical exchange.
    """
    _original: _OriginalChildControlPipe
    _borrow: _OriginalDomainBorrow
    _read: _OriginalDescriptor
    _write: _OriginalDescriptor
    _backing_descriptor: _OriginalDescriptor
    _material: _OriginalDomainMaterial
    _functions: _OriginalDomainBorrowFunctions
    _holding: _NativeHoldingLease | None
    _process: int
    _thread: Thread
    _core: LocalCore | None
    _core_identity: object | None
    _observation: _OriginalVMObservation | None
    _attached: bool
    _bound_attempted: bool
    _bound: bool
    _retired: bool
    _active: bool
    _unknown: BaseException | None
    _serial: int
    _request_bytes: bytes | None
    _written: int
    _response_bytes: bytes
    _response_chunk: bytes
    _pipe_identities: tuple[tuple[int, int, int, int], ...] | None
    _generation: int
    _recipe: bytes
    _library: Any

    def __init__(self) -> None:
        raise TypeError('Original child control requires installed bootstrap')

    @classmethod
    def _capture(cls, borrow: _OriginalDomainBorrow, read: _OriginalDescriptor,
                 write: _OriginalDescriptor) -> _OriginalChildControlPipe:
        if (type(borrow) is not _OriginalDomainBorrow or borrow._original is not borrow
                or borrow._child_control_original is not None
                or borrow._descriptor.value != 4 or borrow._descriptor.closed
                or borrow._descriptor.close_attempted
                or any(type(d) is not _OriginalDescriptor or d._original is not d
                       or d.closed or d.close_attempted for d in (read, write))
                or read.value != 0 or write.value != 1):
            raise ValueError('Original inherited child control is unavailable')
        value = cls.__new__(cls)
        value._original = value
        value._borrow, value._read, value._write = borrow, read, write
        value._backing_descriptor = borrow._descriptor
        value._material, value._functions = borrow._material, borrow._functions
        value._holding = None
        value._process, value._thread = os.getpid(), current_thread()
        value._core = None
        value._core_identity = None
        value._observation = None
        value._attached = value._bound_attempted = value._bound = value._retired = False
        value._active = False
        value._unknown = None
        value._serial = 1
        value._request_bytes = None
        value._written = 0
        value._response_bytes = b''
        value._response_chunk = b''
        value._pipe_identities = None
        value._generation = borrow._material.scalars[0]
        value._recipe, value._library = borrow._material.recipe, borrow._functions.library
        # Capture before fallible physical inspection. A partial original cannot
        # be replaced with a fresh pipe/borrow or another bootstrap attempt.
        borrow._child_control_original = value
        try:
            value._pipe_identities = value._observe_pipes()
            value._identity()
        except BaseException as error:
            value._unknown = error
            raise _OriginalChildControlPending(value) from error
        return value

    def __copy__(self) -> NoReturn:
        raise TypeError('Original child control cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original child control cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original child control cannot be serialized')

    def _observe_pipes(self) -> tuple[tuple[int, int, int, int], ...]:
        identities = []
        for descriptor, number, access in ((self._read, 0, os.O_RDONLY),
                                            (self._write, 1, os.O_WRONLY)):
            if (type(descriptor) is not _OriginalDescriptor or descriptor._original is not descriptor
                    or descriptor.closed or descriptor.close_attempted
                    or type(descriptor.value) is not int or descriptor.value != number):
                raise ValueError('Original inherited child pipe changed')
            status = os.fstat(number)
            if (not stat.S_ISFIFO(status.st_mode) or status.st_uid != os.geteuid()
                    or not os.get_blocking(number)
                    or fcntl.fcntl(number, fcntl.F_GETFL) & os.O_ACCMODE != access):
                raise ValueError('Original inherited child pipe is unavailable')
            identities.append((status.st_dev, status.st_ino, status.st_mode, status.st_uid))
        if identities[0][:2] == identities[1][:2]:
            raise ValueError('Original child control requires distinct pipe descriptions')
        return tuple(identities)

    def _identity(self) -> None:
        if self._unknown is not None:
            raise _OriginalChildControlPending(self) from self._unknown
        borrow = self._borrow
        if (self._original is not self or self._retired or self._process != os.getpid()
                or self._thread is not current_thread() or borrow._original is not borrow
                or borrow._child_control_original is not self or borrow._closed or borrow._closing
                or borrow._descriptor is not self._backing_descriptor
                or borrow._descriptor._original is not borrow._descriptor
                or borrow._material is not self._material or borrow._functions is not self._functions
                or borrow._unknown is not None or borrow._busy
                or borrow._process != self._process or borrow._thread is not self._thread
                or borrow._descriptor.value != 4 or borrow._descriptor.closed
                or borrow._descriptor.close_attempted or borrow._material.scalars[0] != self._generation
                or borrow._material.recipe != self._recipe or borrow._functions.library is not self._library
                or self._pipe_identities != self._observe_pipes()):
            raise ValueError('Original child pipe or native borrow changed')
        core = self._core
        if core is not None:
            if (core._identity is not self._core_identity or core._physical_child_control is not self
                    or core._closed or core._retired or core._physical_holding is None
                    or core._physical_holding is not self._holding
                    or borrow._holding_consumer is not self._holding
                    or core._physical_holding._borrow is not borrow
                    or core._physical_holding._library is not self._library
                    or core._physical_holding._generation != self._generation
                    or core._physical_holding._recipe != self._recipe):
                raise ValueError('Original child Core or native holding changed')

    def _require_unbound_holding(self, holding: _NativeHoldingLease) -> None:
        from ._local_native_holding import _NativeHoldingLease
        self._identity()
        if (self._attached or type(holding) is not _NativeHoldingLease
                or holding._borrow is not self._borrow
                or self._borrow._holding_consumer is not holding
                or holding._library is not self._library or holding._generation != self._generation
                or holding._recipe != self._recipe or holding._core_identity is not None):
            raise ValueError('Original child holding was already consumed or is foreign')

    def _attach_core(self, core: LocalCore) -> None:
        from ._local_core import LocalCore
        if (type(core) is not LocalCore or self._attached
                or core._physical_child_control is not self
                or core._physical_holding is None
                or core._physical_holding._borrow is not self._borrow):
            raise ValueError('Original child Core binding is unavailable')
        self._core, self._core_identity, self._attached = core, core._identity, True
        self._holding = core._physical_holding
        self._identity()

    def _bind_original_vm(self, observation: _OriginalVMObservation) -> None:
        from ._local_native_vm import _OriginalVMObservation
        self._identity()
        if (self._bound_attempted or type(observation) is not _OriginalVMObservation
                or observation._core is not self._core or observation._identity is not self._core_identity):
            raise ValueError('Original child VM binding is unavailable')
        self._bound_attempted = True
        self._observation = observation
        # The existing observation derives its relative span from the actual
        # selected Memory/Store/holding. DATA cannot replace those originals.
        span = observation._project_original_span()
        result = self._exchange(frames._BIND, span.nonce, frames._span_payload(span))
        if result != 0:
            raise RuntimeError('Original child VM binding was refused')
        observation._require_core_current()
        self._bound = True

    def _exchange(self, operation: int, nonce: int, payload: bytes = b'') -> int:
        self._identity()
        observation = self._observation
        if observation is None or observation._nonce != nonce or self._active or self._serial > 2**63 - 1:
            raise ValueError('Original child control exchange is unavailable')
        observation._require_core_current()
        self._active = True
        self._request_bytes = None
        self._written, self._response_bytes, self._response_chunk = 0, b'', b''
        try:
            self._request_bytes = frames._request(operation, self._serial, nonce, payload)
            while self._written < len(self._request_bytes):
                self._identity()
                count = os.write(self._write.value, self._request_bytes[self._written:])
                if type(count) is not int or not 0 < count <= len(self._request_bytes) - self._written:
                    raise RuntimeError('Original child control write progress is invalid')
                self._written += count
                self._identity()
            while len(self._response_bytes) < frames._RESPONSE.size:
                self._identity()
                self._response_chunk = os.read(self._read.value, frames._RESPONSE.size - len(self._response_bytes))
                if (type(self._response_chunk) is not bytes or not self._response_chunk
                        or len(self._response_chunk) > frames._RESPONSE.size - len(self._response_bytes)):
                    raise RuntimeError('Original child control reply is incomplete')
                self._response_bytes += self._response_chunk
                self._identity()
            magic, actual_operation, serial, actual_nonce, result = frames._RESPONSE.unpack(self._response_bytes)
            if (magic != frames._MAGIC or actual_operation != operation or serial != self._serial
                    or actual_nonce != nonce or result < 0 and result not in (-41, -42)
                    or operation in (frames._BIND, frames._ADMIT, frames._REPORT, frames._STOP) and result > 0
                    or operation == frames._CURRENT and result > 1):
                raise RuntimeError('Original child control reply does not match its request')
            observation._require_core_current()
            self._identity()
            if result == -41:
                raise RuntimeError('Original parent control outcome remains unknown')
            self._serial += 1
            # Struct's bounded q field is exact signed Int64, not float/JSON.
            assert type(result) is int
            return result
        except BaseException as error:
            self._unknown = error
            raise _OriginalChildControlPending(self) from error
        finally:
            self._active = False

    def _callback(self, operation: int, caller: Any, nonce: int, *arguments: int) -> int:
        observation, core = self._observation, self._core
        if observation is None or core is None or not self._bound:
            raise ValueError('Original child VM control is not bound')
        # Foreign Callers never acquire or query this channel, including after
        # a previous transport Unknown. Keep the actual Caller on this thread.
        observation._require_caller(caller, nonce)
        if operation in (frames._LIMIT, frames._CAPACITY):
            count = 6 if operation == frames._LIMIT else 2
            if len(arguments) != 1 or type(arguments[0]) is not int or not 0 <= arguments[0] < count:
                raise ValueError('Invalid original execution import ordinal')
            payload = frames._ORDINAL.pack(arguments[0])
        elif operation == frames._REPORT:
            if (len(arguments) != 13
                    or any(type(v) is not int or not -(2**31) <= v < 2**31 for v in (*arguments[:3], *arguments[10:]))
                    or any(type(v) is not int or not -(2**63) <= v < 2**63 for v in arguments[3:10])):
                raise ValueError('Invalid original execution usage fields')
            payload = frames._USAGE.pack(*arguments)
        else:
            if arguments:
                raise ValueError('Unexpected original execution import arguments')
            payload = b''
        if core._closing and operation not in (frames._CURRENT, frames._REPORT, frames._STOP):
            return -42
        try:
            result = self._exchange(operation, nonce, payload)
            observation._require_caller(caller, nonce)
            return result
        except _OriginalChildControlPending as error:
            if error.cleanup_control is not self:
                raise
            # Return the existing typed import Unknown, allowing Common to
            # retain its original attempt/report. No further pipe I/O occurs.
            return -41
        except BaseException as error:
            self._unknown = error
            return -41

    def admit(self, caller: Any, nonce: int) -> int:
        return self._callback(frames._ADMIT, caller, nonce)

    def current(self, caller: Any, nonce: int) -> int:
        return self._callback(frames._CURRENT, caller, nonce)

    def limit(self, caller: Any, nonce: int, ordinal: int) -> int:
        return self._callback(frames._LIMIT, caller, nonce, ordinal)

    def capacity(self, caller: Any, nonce: int, ordinal: int) -> int:
        return self._callback(frames._CAPACITY, caller, nonce, ordinal)

    def report(self, caller: Any, nonce: int, *usage: int) -> int:
        return self._callback(frames._REPORT, caller, nonce, *usage)

    def stop(self, caller: Any, nonce: int) -> int:
        return self._callback(frames._STOP, caller, nonce)

    def _retire_metadata(self, core: LocalCore) -> None:
        if (self._original is not self or core is not self._core
                or core._identity is not self._core_identity or core._physical_child_control is not self
                or not core._retired or core._store is not None or core._physical_holding is not None):
            raise ValueError('Original child physical retirement is unconfirmed')
        self._core, self._observation, self._holding, self._retired = None, None, None, True
        # Keep original descriptors and any unknown bytes for bootstrap's
        # separate FD/stop/parent ACK boundary. This is no physical close.
