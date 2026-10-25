"""Private bounded worker control frames on the original process/pipe only.

These frames transport the existing Native Owner's facts, not Client Wire,
nominal pointers, funding, grants or Run outcomes. Installed bootstrap must
already fund both sides' control records, buffers and pipe lifetimes.
"""
from __future__ import annotations

from struct import Struct
from typing import TYPE_CHECKING, NoReturn

if TYPE_CHECKING:
    from ._local_worker_process import OriginalWorkerProcess
    from ._local_worker_funding import OriginalWorkerFunding

from ._local_native_live_channel import _OriginalLiveChannelCustody, _OriginalLiveChannelError
from ._local_native_vm import _OriginalVMSpanData
from ._local_worker_pipe import OriginalWorkerPipe
from ._local_worker_slot import _OriginalDescriptor

# Fixed private transport, independent of the public Client--Host Wire.
_HEADER = Struct('!4sBqq')
_RESPONSE = Struct('!4sBqqq')
_ORDINAL = Struct('!i')
_USAGE = Struct('!iiiqqqqqqqiii')
_SPAN = Struct('!40s32s' + 'q' * 17)
_MAGIC = b'ALC1'
_BIND, _ADMIT, _CURRENT, _LIMIT, _CAPACITY, _REPORT, _STOP = range(7)
_SIZES = { _BIND: _SPAN.size, _ADMIT: 0, _CURRENT: 0, _LIMIT: _ORDINAL.size,
           _CAPACITY: _ORDINAL.size, _REPORT: _USAGE.size, _STOP: 0 }
_MAX_FRAME = _HEADER.size + _SPAN.size


def _request(operation: int, serial: int, nonce: int, payload: bytes = b'') -> bytes:
    """Encoding alone never acquires the original channel or import authority."""
    if (type(operation) is not int or operation not in _SIZES
            or type(serial) is not int or not 0 < serial <= 2**63 - 1
            or type(nonce) is not int or not 0 < nonce <= 2**63 - 1
            or type(payload) is not bytes or len(payload) != _SIZES[operation]):
        raise ValueError('Invalid bounded original worker control request')
    return _HEADER.pack(_MAGIC, operation, serial, nonce) + payload


def _span_payload(span: _OriginalVMSpanData) -> bytes:
    if (type(span) is not _OriginalVMSpanData or type(span.source) is not str
            or len(span.source) != 40 or any(c not in '0123456789abcdef' for c in span.source)
            or type(span.recipe) is not bytes or len(span.recipe) != 32
            or type(span.material) is not tuple or len(span.material) != 15
            or any(type(v) is not int or not 0 <= v <= 2**63 - 1
                   for v in (*span.material, span.offset, span.length))):
        raise ValueError('Invalid original worker VM span DATA')
    return _SPAN.pack(span.source.encode('ascii'), span.recipe,
                      *span.material, span.offset, span.length)


class _OriginalWorkerControlPending(RuntimeError):
    def __init__(self, control: _OriginalWorkerControlFrames) -> None:
        self.cleanup_control = control
        super().__init__('Original worker control exchange remains unconfirmed')


class _OriginalFirstControlPending(RuntimeError):
    def __init__(self, header: _OriginalFirstControlHeader) -> None:
        self.cleanup_header = header
        super().__init__('Original first child control header remains unconfirmed')


class _OriginalFirstControlHeader:
    """One bounded physical prefix before the original Native channel exists.

    The nonce is instance-correlation DATA, not a durable provisioning key,
    funding, authority or permission to launch/adopt another child. The same
    already funded process and pipe stay owned before and after this read.
    """
    _original: _OriginalFirstControlHeader
    _pipe: OriginalWorkerPipe
    _process: OriginalWorkerProcess
    _funding: OriginalWorkerFunding
    _pid: int
    _read: _OriginalDescriptor
    _write: _OriginalDescriptor
    _read_value: int
    _write_value: int
    _raw: bytes
    _chunk: bytes
    _unknown: BaseException | None
    _complete: bool
    _taken: bool
    _consumer: _OriginalWorkerControlFrames | None
    _nonce: int | None

    def __init__(self, pipe: OriginalWorkerPipe) -> None:
        raise TypeError('Original first control header requires the original pipe read')

    @classmethod
    async def _read_original(cls, pipe: OriginalWorkerPipe) -> _OriginalFirstControlHeader:
        if (type(pipe) is not OriginalWorkerPipe or pipe._control_header_original is not None
                or pipe._native_channel_original is not None or not pipe._prepared):
            raise ValueError('Original first control header is unavailable or already attempted')
        pipe._current()
        process = pipe._process
        if (process._stdin is None or process._stdout is None or type(process._pid) is not int
                or process._pid <= 0):
            raise ValueError('Original child pipe descriptions are unavailable')
        value = cls.__new__(cls)
        value._original, value._pipe, value._process = value, pipe, process
        value._funding, value._pid = pipe._funding, process._pid
        value._read, value._write = process._stdout[0], process._stdin[1]
        value._read_value, value._write_value = value._read.value, value._write.value
        value._raw, value._chunk = b'', b''
        value._unknown = None
        value._complete = value._taken = False
        value._consumer = None
        value._nonce = None
        pipe._control_header_original = value
        try:
            while len(value._raw) < _HEADER.size:
                value._current()
                value._chunk = await pipe.read(_HEADER.size - len(value._raw))
                # Keep the current chunk as well as the accumulated prefix on
                # allocation/postcheck failure; the pipe also retains its read.
                if (type(value._chunk) is not bytes or not value._chunk
                        or len(value._chunk) > _HEADER.size - len(value._raw)):
                    raise RuntimeError('Original first control header is incomplete')
                value._raw += value._chunk
                value._current()
            magic, operation, serial, nonce = _HEADER.unpack(value._raw)
            if magic != _MAGIC or operation != _BIND or serial != 1 or nonce <= 0:
                raise ValueError('Invalid original first child bind header')
            value._nonce, value._complete = nonce, True
            return value
        except BaseException as failure:
            value._unknown = failure
            raise _OriginalFirstControlPending(value) from failure

    def __copy__(self) -> NoReturn:
        raise TypeError('Original first control header cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original first control header cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original first control header cannot be serialized')

    def _current(self) -> None:
        if self._unknown is not None:
            raise _OriginalFirstControlPending(self) from self._unknown
        process, pipe = self._process, self._pipe
        if (self._original is not self or pipe._control_header_original is not self
                or pipe._process is not process or pipe._funding is not self._funding
                or process._pid != self._pid or process._stdin is None or process._stdout is None
                or process._stdin[1] is not self._write or process._stdout[0] is not self._read
                or type(self._read) is not _OriginalDescriptor or self._read._original is not self._read
                or type(self._write) is not _OriginalDescriptor or self._write._original is not self._write
                or not any(d is self._read for d in process._descriptors)
                or not any(d is self._write for d in process._descriptors)
                or self._read.value != self._read_value or self._write.value != self._write_value
                or self._read.closed or self._read.close_attempted
                or self._write.closed or self._write.close_attempted):
            raise ValueError('Original first child control pipe changed')
        pipe._current()

    def nonce_data(self) -> int:
        """Correlation for the same Native capture; not an admission receipt."""
        self._current()
        if not self._complete or type(self._nonce) is not int:
            raise ValueError('Original first child header is incomplete')
        return self._nonce

    def _bind_consumer(self, control: _OriginalWorkerControlFrames) -> None:
        self._current()
        if (self._consumer is not None or not self._complete or self._taken
                or control._pipe is not self._pipe or control._channel._nonce != self._nonce):
            raise ValueError('Original first child header cannot be rebound')
        self._consumer = control
        self._current()

    def _take_prefix(self, control: _OriginalWorkerControlFrames) -> bytes:
        self._current()
        if self._consumer is not control or self._taken or not self._complete:
            raise ValueError('Original first child header was already consumed or is foreign')
        self._taken = True
        return self._raw


class _OriginalWorkerControlFrames:
    """One parent-side physical exchange, not a worker or Run state machine.

    The exact existing channel chooses every Native handle and validates the
    original process/pipe/current scope. Sequence numbers correlate bytes only;
    they are not provisioning identities or permission to retry an operation.
    """
    def __init__(self, channel: _OriginalLiveChannelCustody, *,
                 _initial_header: _OriginalFirstControlHeader | None = None) -> None:
        if type(channel) is not _OriginalLiveChannelCustody:
            raise ValueError('Original Native worker channel is unavailable')
        channel._require_launch()
        if channel._control_original is not None:
            raise ValueError('Original Native worker channel already has control transport')
        if channel._pipe._control_header_original is not _initial_header:
            raise ValueError('Original first control header must stay with the same pipe')
        if _initial_header is not None and type(_initial_header) is not _OriginalFirstControlHeader:
            raise ValueError('Foreign first control header')
        self._original = self
        self._channel, self._pipe = channel, channel._pipe
        self._serial = 1
        self._active = False
        self._unknown: BaseException | None = None
        self._request_bytes = b''
        self._response_bytes: bytes | None = None
        self._written = 0
        self._initial_header = _initial_header
        self._prefix_started = False
        # Publish before any subsequent physical operation; no replacement on
        # partial read/write, callback failure, cancellation or lost response.
        channel._control_original = self
        if _initial_header is not None:
            try:
                _initial_header._bind_consumer(self)
            except BaseException as failure:
                self._unknown = failure
                raise _OriginalWorkerControlPending(self) from failure

    def __copy__(self) -> NoReturn:
        raise TypeError('Original worker control transport cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original worker control transport cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original worker control transport cannot be serialized')

    def _identity(self) -> None:
        if (self._original is not self or self._channel._control_original is not self
                or self._channel._pipe is not self._pipe
                or type(self._pipe) is not OriginalWorkerPipe):
            raise ValueError('Foreign original worker control transport')
        if self._unknown is not None:
            raise _OriginalWorkerControlPending(self) from self._unknown
        header = self._initial_header
        if header is not None and (header._original is not header or header._consumer is not self
                or header._pipe is not self._pipe or self._pipe._control_header_original is not header):
            raise ValueError('Original first control header custody changed')
        # Closing is observable for the existing report/stop/current ports;
        # fresh operation admission remains the Native Owner's decision.
        self._channel._identity(cleanup=True)

    async def _read_exact(self, length: int) -> bytes:
        while len(self._request_bytes) < length:
            chunk = await self._pipe.read(length - len(self._request_bytes))
            # Retain each observed byte before identity or format postchecks.
            self._request_bytes += chunk
            self._identity()
            if not chunk or len(self._request_bytes) > length:
                raise RuntimeError('Original worker control input is incomplete')
        return self._request_bytes

    def _dispatch(self, operation: int, nonce: int, payload: bytes) -> int:
        channel = self._channel
        if nonce != channel._nonce:
            raise ValueError('Foreign original worker control nonce')
        if operation == _BIND:
            values = _SPAN.unpack(payload)
            # DATA is checked against original material and physical child by
            # bind_original_vm; Python does not adopt a new child or capacity.
            source = values[0].decode('ascii')
            channel.bind_original_vm(_OriginalVMSpanData(
                source, values[1], tuple(values[2:17]), nonce, values[17], values[18]))
        elif operation == _ADMIT:
            channel.admit()
        elif operation == _CURRENT:
            return channel.state()
        elif operation in (_LIMIT, _CAPACITY):
            ordinal, = _ORDINAL.unpack(payload)
            count = 6 if operation == _LIMIT else 2
            if not 0 <= ordinal < count:
                raise ValueError('Invalid original worker control ordinal')
            values = channel.limits() if operation == _LIMIT else channel.capacities()
            value = values[ordinal]
            if type(value) is not int:
                raise RuntimeError('Original worker control fact is invalid')
            return value
        elif operation == _REPORT:
            channel.report(_USAGE.unpack(payload))
        elif operation == _STOP:
            channel.stop()
        else:
            raise ValueError('Unknown original worker control operation')
        return 0

    async def serve_once(self) -> None:
        """One bounded request/reply; no replay or implicit close/settle ACK.

        The trusted installed channel must call this on its original pipe when
        expecting a child control frame. A public Wire response is not accepted
        as control. No I/O is performed by construction or frame encoding.
        """
        self._identity()
        if self._active or self._serial > 2**63 - 1:
            raise ValueError('Original worker control transport is active or exhausted')
        self._active = True
        self._request_bytes, self._response_bytes, self._written = b'', None, 0
        try:
            if self._initial_header is not None and not self._prefix_started:
                self._prefix_started = True
                self._request_bytes = self._initial_header._take_prefix(self)
            header = await self._read_exact(_HEADER.size)
            magic, operation, serial, nonce = _HEADER.unpack(header)
            if (magic != _MAGIC or operation not in _SIZES or serial != self._serial
                    or nonce != self._channel._nonce):
                raise ValueError('Foreign or stale original worker control frame')
            frame = await self._read_exact(_HEADER.size + _SIZES[operation])
            if len(frame) > _MAX_FRAME:
                raise ValueError('Original worker control frame exceeds its bound')
            unknown: BaseException | None = None
            try:
                result = self._dispatch(operation, nonce, frame[_HEADER.size:])
            except _OriginalLiveChannelError as error:
                if error.cleanup_channel is not self._channel:
                    raise
                # These are the existing fixed import statuses. A known
                # refusal is not success; Unknown never authorizes another call.
                result = -41 if error.unknown else -42
                if error.unknown:
                    unknown = error
            if unknown is None:
                self._identity()
            if type(result) is not int or not -(2**63) <= result <= 2**63 - 1:
                raise RuntimeError('Original worker control reply is invalid')
            self._response_bytes = _RESPONSE.pack(_MAGIC, operation, serial, nonce, result)
            # Native Unknown can still be reported over the same owned pipe.
            # Identity below intentionally avoids invoking its unavailable
            # Native channel again, and never clears that original Unknown.
            while self._written < len(self._response_bytes):
                chunk = self._response_bytes[self._written:]
                count = await self._pipe.write(chunk)
                if type(count) is not int or not 0 < count <= len(chunk):
                    raise RuntimeError('Original worker control write progress is invalid')
                self._written += count
                if unknown is None:
                    self._identity()
            if unknown is not None:
                raise unknown
            self._serial += 1
        except BaseException as failure:
            self._unknown = failure
            raise _OriginalWorkerControlPending(self) from failure
        finally:
            self._active = False
