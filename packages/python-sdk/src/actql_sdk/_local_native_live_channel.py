"""Same original Native channel/process/pipe custody, never a funding supplier.

The trusted installed control uses this only after complete original pre-spawn
funding. It does not start a child, choose a numerical profile, load a library,
create a Ledger or accept SDK-supplied native references. Core still decides
admission, current, cumulative usage and cleanup through its original domain.
"""
from __future__ import annotations

from ._local_native_shim_abi import bind as bind_native

from ctypes import POINTER, byref, c_int, c_int32, c_int64, c_void_p
from os import getpid
from threading import current_thread
from typing import Any, NoReturn

from ._local_native_control_custody import _OriginalArenaFact, _OriginalControlCustody
from ._local_native_domain_custody import _OriginalDomainCustody, _OriginalDomainMaterialFunctions
from ._local_native_vm import _OriginalVMSpanData
from ._local_worker_channel import OriginalWorkerPipeChannel
from ._local_worker_funding import OriginalWorkerFunding
from ._local_worker_pipe import OriginalWorkerPipe
from ._local_worker_process import OriginalWorkerProcess
from ._local_worker_slot import _OriginalDescriptor


_RETIRED_CHANNEL_DATA = object()


class _OriginalLiveChannelError(RuntimeError):
    def __init__(self, channel: _OriginalLiveChannelCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_channel, self.unknown, self.fact = channel, unknown, fact
        super().__init__('Original Native live-channel outcome is unconfirmed' if unknown
                         else 'Original Native live-channel operation was refused')


class _OriginalLiveChannelFunctions:
    """Mandatory matching exports of the same selected component, no fallback."""

    def __init__(self, library: Any) -> None:
        self.library = library
        self.prepare = bind_native(library, 'actql_live_channel_prepare_into')
        self.bind = bind_native(library, 'actql_live_channel_bind_into')
        self.operate = bind_native(library, 'actql_live_channel_operate_into')
        self.report = bind_native(library, 'actql_live_channel_report_into')
        self.originals = bind_native(library, 'actql_live_channel_originals_into')
        self.drop = bind_native(library, 'actql_live_channel_drop_reply')
        self.finish = bind_native(library, 'actql_live_channel_finish_retired_data')
        self.refused = bind_native(library, 'actql_live_channel_finish_refused_prepare')
        self.state = bind_native(library, 'actql_live_channel_copy_state')
        self.limits = bind_native(library, 'actql_live_channel_copy_limits')
        self.capacities = bind_native(library, 'actql_live_channel_copy_capacities')
        self.operation = bind_native(library, 'actql_live_channel_operation')
        self.issue = bind_native(library, 'actql_live_channel_issue_family')


class _OriginalLivePreparationFunctions:
    """Actual matching pre-spawn/frame ABI of the same selected provider.

    The old post-spawn diagnostic entry remains separate; missing new exports
    cannot select it as a compatibility path.
    """

    def __init__(self, library: Any) -> None:
        self.legacy = _OriginalLiveChannelFunctions(library)
        self.before = bind_native(library, 'actql_live_channel_prepare_before_spawn_into')
        self.child = bind_native(library, 'actql_live_channel_bind_child_into')
        self.prepare = bind_native(library, 'actql_channel_ledger_prepare_into')
        self.operate = bind_native(library, 'actql_channel_ledger_operate_into')
        self.originals = bind_native(library, 'actql_channel_ledger_originals_into')
        self.operation = bind_native(library, 'actql_channel_ledger_operation')
        self.issue = bind_native(library, 'actql_channel_ledger_issue_family')
        self.limits = bind_native(library, 'actql_channel_ledger_copy_limits')
        self.drop = bind_native(library, 'actql_channel_ledger_drop_reply')
        self.finish = bind_native(library, 'actql_channel_ledger_finish_retired_data')


class _OriginalLiveChannelCustody:
    """Retain one existing domain/channel and physical caller across failures.

    A backed installed supplier uses the same domain as its physical/delegation
    carrier and its original Control as the opaque accounting Owner carrier.
    This identity check supplies no coverage of separate process/FD/VM domains:
    the existing funding supplier must already establish those before spawn.
    """

    __slots__ = ('_original', '_domain', '_owner', '_process', '_pipe', '_funding',
                 '_functions', '_nonce', '_material_functions', '_funding_originals',
                 '_read', '_write', '_read_value', '_write_value', '_child_pid',
                 '_host', '_native_domain', '_channel', '_reply', '_unknown',
                 '_unknown_carrier', '_closed', '_bind_attempted', '_admit_attempted',
                 '_stop_attempted', '_stop_acknowledged', '_control_original',
                 '_preparation_functions', '_child_binding_attempted', '_child_bound',
                 '_frame_host', '_frame_domain', '_frame_channel', '_frame', '_frame_reply',
                 '_frame_prepare_attempted', '_frame_values')
    _original: _OriginalLiveChannelCustody
    _domain: _OriginalDomainCustody
    _owner: _OriginalControlCustody
    _process: OriginalWorkerProcess
    _pipe: OriginalWorkerPipe
    _funding: OriginalWorkerFunding
    _functions: _OriginalLiveChannelFunctions
    _nonce: int
    _material_functions: _OriginalDomainMaterialFunctions
    _funding_originals: tuple[object | None, object | None, object | None, object | None]
    _read: _OriginalDescriptor
    _write: _OriginalDescriptor
    _read_value: int
    _write_value: int
    _child_pid: int | None
    _host: c_void_p
    _native_domain: c_void_p
    _channel: c_void_p
    _reply: c_void_p
    _unknown: _OriginalLiveChannelError | None
    _unknown_carrier: _OriginalLiveChannelError
    _closed: bool
    _bind_attempted: bool
    _admit_attempted: bool
    _stop_attempted: bool
    _stop_acknowledged: bool
    _control_original: object | None
    _preparation_functions: _OriginalLivePreparationFunctions | None
    _child_binding_attempted: bool
    _child_bound: bool
    _frame_host: c_void_p
    _frame_domain: c_void_p
    _frame_channel: c_void_p
    _frame: c_void_p
    _frame_reply: c_void_p
    _frame_prepare_attempted: bool
    _frame_values: tuple[int | None, ...] | None

    def __init__(self) -> None:
        raise TypeError('Original live-channel custody requires the installed physical caller')

    @classmethod
    def _capture_original(cls, domain: _OriginalDomainCustody,
                          process: OriginalWorkerProcess, pipe: OriginalWorkerPipe,
                          functions: _OriginalLiveChannelFunctions, *, nonce: int,
                          _preparation: _OriginalLivePreparationFunctions | None = None) -> _OriginalLiveChannelCustody:
        if (type(domain) is not _OriginalDomainCustody
                or type(process) is not OriginalWorkerProcess or type(pipe) is not OriginalWorkerPipe
                or type(functions) is not _OriginalLiveChannelFunctions
                or functions.library is not domain._functions.library
                or functions.library is not domain._owner._functions.library
                or pipe._process is not process or process._parent_pipe_consumer is not pipe
                or pipe._funding is not process._funding
                or type(nonce) is not int or not 0 < nonce <= 2**63 - 1):
            raise ValueError('Original Native live-channel inputs are unavailable')
        before_spawn = _preparation is not None
        if before_spawn and (type(_preparation) is not _OriginalLivePreparationFunctions
                or _preparation.legacy is not functions or not process._descriptors_prepared
                or process._spawn_attempted or process._spawn_syscall_attempted or process._pid is not None):
            raise ValueError('Original pre-spawn descriptors are unavailable')
        funding = process._funding
        if (type(funding) is not OriginalWorkerFunding or funding._physical is not domain
                or funding._delegation is not domain or funding._ledger is not domain._owner
                or process._native_domain is not domain or domain._worker_process_original is not process
                or process._native_metadata_retired or process._native_dup_unknown
                or process._native_duplicate is None
                or (before_spawn and (process._native_duplicate.closed or process._native_duplicate.close_attempted)
                    or not before_spawn and not process._native_duplicate.closed)
                or domain._live_channel_original is not None or pipe._native_channel_original is not None):
            raise ValueError('Original live-channel funding or one-shot domain is unavailable')
        if process._stdin is None or process._stdout is None:
            raise ValueError('Original worker pipes are unavailable')
        channel = cls.__new__(cls)
        channel._original = channel
        channel._domain, channel._owner = domain, domain._owner
        channel._process, channel._pipe, channel._funding = process, pipe, funding
        channel._functions, channel._nonce = functions, nonce
        channel._material_functions = _OriginalDomainMaterialFunctions(functions.library)
        channel._funding_originals = (funding._physical, funding._ledger, funding._delegation, funding._durable)
        channel._read, channel._write = process._stdout[0], process._stdin[1]
        channel._read_value, channel._write_value, channel._child_pid = (
            channel._read.value, channel._write.value, process._pid)
        channel._host, channel._native_domain, channel._channel, channel._reply = (
            c_void_p(), c_void_p(), c_void_p(), c_void_p())
        channel._unknown = None
        channel._unknown_carrier = _OriginalLiveChannelError(channel, unknown=True)
        channel._closed = False
        channel._bind_attempted = channel._admit_attempted = channel._stop_attempted = False
        channel._stop_acknowledged = False
        channel._control_original = None
        channel._preparation_functions = _preparation
        channel._child_binding_attempted = channel._child_bound = not before_spawn
        channel._frame_host, channel._frame_domain, channel._frame_channel = c_void_p(), c_void_p(), c_void_p()
        channel._frame, channel._frame_reply = c_void_p(), c_void_p()
        channel._frame_prepare_attempted = False
        channel._frame_values = None
        # Same existing custody before current/physical capture can fail. Even
        # a lost return never allows a second capture on the same pipe/domain.
        domain._live_channel_original = pipe._native_channel_original = channel
        known: _OriginalLiveChannelError | None = None
        with process._lock:
            try:
                channel._require_launch()
                channel._owner._enter()
            except BaseException:
                # No foreign call has started. A known local entry refusal
                # owns no channel aliases and must not poison parent cleanup.
                if domain._live_channel_original is channel:
                    domain._live_channel_original = None
                if pipe._native_channel_original is channel:
                    pipe._native_channel_original = None
                channel._closed = True
                raise
            try:
                try:
                    if _preparation is None:
                        channel._status(functions.prepare(domain._host, domain._domain,
                            process._pid, channel._read.value, channel._write.value, nonce, byref(channel._reply)))
                    else:
                        channel._status(_preparation.before(domain._host, domain._domain,
                            channel._read.value, channel._write.value, nonce, byref(channel._reply)))
                    channel._status(functions.originals(channel._reply, byref(channel._host),
                        byref(channel._native_domain), byref(channel._channel)))
                    if (channel._host.value is None or channel._host.value != domain._host.value
                            or channel._native_domain.value is None
                            or channel._native_domain.value != domain._domain.value):
                        raise channel._mark_unknown()
                    fact = channel._fact(10 if before_spawn else 1)
                    if channel._channel.value is None:
                        if fact.issue_family == 0:
                            raise channel._mark_unknown()
                        channel._status(functions.refused(byref(channel._host),
                            byref(channel._native_domain), byref(channel._reply)))
                        if any(x.value is not None for x in (channel._host, channel._native_domain, channel._reply)):
                            raise channel._mark_unknown()
                        channel._closed = True
                        channel._detach_retired_data()
                    else:
                        channel._drop_reply()
                finally:
                    channel._owner._busy = False
                # A postcheck can lose authority, never the original handles.
                if not channel._closed:
                    channel._require_launch()
                if fact.issue_family != 0:
                    known = _OriginalLiveChannelError(channel, unknown=False, fact=fact)
                    raise known
                return channel
            except BaseException as error:
                if error is known or error is channel._unknown:
                    raise
                raise channel._mark_unknown() from error

    @classmethod
    def _prepare_original(cls, domain: _OriginalDomainCustody,
                          process: OriginalWorkerProcess, pipe: OriginalWorkerPipe,
                          functions: _OriginalLivePreparationFunctions, *, nonce: int) -> _OriginalLiveChannelCustody:
        if type(functions) is not _OriginalLivePreparationFunctions:
            raise ValueError('Matching original pre-spawn transport is unavailable')
        return cls._capture_original(domain, process, pipe, functions.legacy,
                                     nonce=nonce, _preparation=functions)

    def prepare_original_frame(self) -> None:
        """Project this live ticket once; never create a scalar child root."""
        with self._process._lock:
            functions = self._preparation_functions
            self._require_launch()
            if functions is None or self._frame_prepare_attempted:
                raise ValueError('Original resource frame preparation is unavailable or already attempted')
            self._owner._enter()
            self._frame_prepare_attempted = True
            try:
                self._status(functions.prepare(self._host, self._native_domain, self._channel,
                                               byref(self._frame_reply)))
                self._status(functions.originals(self._frame_reply, byref(self._frame_host),
                    byref(self._frame_domain), byref(self._frame_channel), byref(self._frame)))
                if (self._frame_host.value != self._host.value or self._frame_host.value is None
                        or self._frame_domain.value != self._native_domain.value
                        or self._frame_domain.value is None
                        or self._frame_channel.value != self._channel.value or self._frame_channel.value is None):
                    raise self._mark_unknown()
                channel_values = (self._frame_host.value, self._frame_domain.value,
                                  self._frame_channel.value, self._frame.value)
                self._frame_values = channel_values
                fact = self._frame_fact(1)
                if fact.issue_family == 0 and self._frame.value is None:
                    raise self._mark_unknown()
                # A no-frame known refusal retains the original typed reply
                # for final alias retirement. Partial frames stay here too.
                if self._frame.value is not None:
                    self._drop_frame_reply()
            except BaseException as error:
                if error is self._unknown:
                    raise
                raise self._mark_unknown() from error
            finally:
                self._owner._busy = False
            self._frame_postcheck(fact, cleanup=False)

    def _frame_fact(self, expected: int) -> _OriginalArenaFact:
        functions = self._preparation_functions
        if functions is None or self._frame_reply.value is None:
            raise self._mark_unknown()
        operation, issue = functions.operation(self._frame_reply), functions.issue(self._frame_reply)
        if (type(operation) is not int or operation != expected
                or type(issue) is not int or not 0 <= issue <= 10):
            raise self._mark_unknown()
        if issue == 10:
            # The existing Common imported-child Unknown is not a known denial.
            raise self._mark_unknown()
        return _OriginalArenaFact(operation, issue)

    def _drop_frame_reply(self) -> None:
        functions = self._preparation_functions
        if functions is None:
            raise self._mark_unknown()
        if self._frame_reply.value is not None:
            self._status(functions.drop(byref(self._frame_reply), self._frame_host,
                self._frame_domain, self._frame_channel, self._frame))
            if self._frame_reply.value is not None:
                raise self._mark_unknown()

    def _require_frame_identity(self) -> None:
        if (self._frame_values is None or
                (self._frame_host.value, self._frame_domain.value, self._frame_channel.value,
                 self._frame.value) != self._frame_values
                or self._frame_host.value != self._host.value
                or self._frame_domain.value != self._native_domain.value
                or self._frame_channel.value != self._channel.value):
            raise ValueError('Original Native resource frame aliases changed')

    def _frame_postcheck(self, fact: _OriginalArenaFact, *, cleanup: bool) -> None:
        try:
            self._require_frame_identity()
            if cleanup:
                self._identity(cleanup=True)
            else:
                self._require_launch()
        except BaseException as error:
            if error is self._unknown:
                raise
            raise self._mark_unknown() from error
        if fact.issue_family != 0:
            raise _OriginalLiveChannelError(self, unknown=False, fact=fact)

    def _frame_operation(self, operation: int, retained: int = 0, execution: int = 0,
                         *, cleanup: bool = False, keep_reply: bool = False) -> tuple[int, ...] | None:
        functions = self._preparation_functions
        # Closed transport selection, not an authority or accounting decision.
        if (functions is None or type(operation) is not int or not 2 <= operation <= 10
                or type(retained) is not int or type(execution) is not int
                or not 0 <= retained <= 2**63 - 1 or not 0 <= execution <= 2**63 - 1
                or (operation == 3 and execution == 0)
                or (operation != 3 and (retained != 0 or execution != 0))):
            raise ValueError('Original resource frame operation is not representable')
        limits = (c_int64 * 6)(*([-1] * 6))
        value: tuple[int, ...] | None = None
        with self._process._lock:
            if cleanup:
                self._identity(cleanup=True)
            else:
                self._require_launch()
            self._require_frame_identity()
            if self._frame.value is None:
                raise ValueError('Original resource frame is unavailable')
            self._owner._enter()
            try:
                self._drop_frame_reply()
                self._status(functions.operate(self._frame_host, self._frame_domain,
                    self._frame_channel, self._frame, operation, retained, execution, byref(self._frame_reply)))
                fact = self._frame_fact(operation)
                if operation == 5 and fact.issue_family == 0:
                    self._status(functions.limits(self._frame_reply, self._frame_host,
                        self._frame_domain, self._frame_channel, self._frame, limits))
                    value = tuple(limits)
                    if any(item < 0 for item in value):
                        raise self._mark_unknown()
                if not keep_reply:
                    self._drop_frame_reply()
            except BaseException as error:
                if error is self._unknown:
                    raise
                raise self._mark_unknown() from error
            finally:
                self._owner._busy = False
            self._frame_postcheck(fact, cleanup=cleanup)
            return value

    def start_original_frame(self) -> None:
        self._frame_operation(2)

    def reserve_original_bootstrap(self, *, retained: int, execution: int) -> None:
        # Actual Common reservation from the original delegation. This accepts
        # no parent/Frame/Owner supplied by a caller and chooses no profile.
        self._frame_operation(3, retained, execution)

    def require_original_frame_current(self) -> None:
        self._frame_operation(4)

    def original_frame_limits(self) -> tuple[int, ...]:
        value = self._frame_operation(5)
        assert value is not None
        return value

    def report_original_frame(self) -> None:
        # Existing Common snapshot, not caller-supplied usage or a fresh credit.
        self._frame_operation(6, cleanup=True)

    def stop_original_frame(self) -> None:
        # Logical stop alone never calls physical/metadata retirement.
        self._frame_operation(7, cleanup=True)

    def stop_transport_use(self) -> None:
        """Ask the same Native Owner to restrict fresh transport work.

        The physical caller must still finish actual I/O and return its opaque
        endpoint borrow. This confirmation is no FD close, scoped process stop,
        metadata retirement, quota settlement or business acknowledgment.
        """
        self._frame_operation(10, cleanup=True)

    def require_original_bootstrap_current(self) -> None:
        self._frame_operation(9)

    def bind_original_child(self) -> None:
        """Bind only the PID captured by this original process's one spawn.

        Neither an external PID argument nor a lost spawn response can adopt a
        different child. A lost/denied binding remains one-shot in this record.
        """
        with self._process._lock:
            functions, process = self._preparation_functions, self._process
            if functions is None or self._child_binding_attempted:
                raise ValueError('Original child binding is unavailable or already attempted')
            process._nominal()
            if (not process._spawn_syscall_attempted or not process._spawn_attempted
                    or type(process._pid) is not int or not 0 < process._pid <= 2**31 - 1
                    or process._native_duplicate is None or not process._native_duplicate.closed
                    or process._native_dup_unknown):
                raise ValueError('Original spawned child is unconfirmed')
            self._child_binding_attempted = True
            self._child_pid = process._pid
            self._perform(11, functions.child, (process._pid,))
            self._child_bound = True

    def __copy__(self) -> NoReturn:
        raise TypeError('Original Native live-channel custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original Native live-channel custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Native live-channel custody cannot be serialized')

    def _mark_unknown(self) -> _OriginalLiveChannelError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _detach_retired_data(self) -> None:
        # Keep one-shot tombstones without a domain -> channel -> domain cycle.
        # Unknown keeps the same actual carrier instead of reaching this path.
        if self._domain._live_channel_original is self:
            self._domain._live_channel_original = _RETIRED_CHANNEL_DATA
        if self._pipe._native_channel_original is self:
            self._pipe._native_channel_original = _RETIRED_CHANNEL_DATA

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _identity(self, *, cleanup: bool) -> None:
        process, pipe, funding, domain = self._process, self._pipe, self._funding, self._domain
        if (self._original is not self or self._closed or self._unknown is not None):
            if self._unknown is not None:
                raise self._unknown
            raise ValueError('Foreign or retired original Native live channel')
        process._nominal()
        if (pipe._original is not pipe or pipe._process is not process
                or process._parent_pipe_consumer is not pipe or pipe._funding is not funding
                or process._funding is not funding or funding._original is not funding or funding._closed
                or funding._supplier._original_supplier is not funding._supplier
                or funding._supplier._consumer is not funding
                or any(a is not b for a, b in zip(self._funding_originals,
                    (funding._physical, funding._ledger, funding._delegation, funding._durable), strict=True))
                or domain._owner is not self._owner or domain._closed or domain._unknown is not None
                or domain._host.value is None or domain._domain.value is None
                or self._owner._closed or self._owner._unknown is not None
                or domain._host.value != self._owner._original.value
                or getpid() != self._owner._process or current_thread() is not self._owner._thread
                or self._owner._busy
                or domain._live_channel_original is not self or pipe._native_channel_original is not self
                or process._stdin is None or process._stdout is None
                or process._stdin[1] is not self._write or process._stdout[0] is not self._read
                or process._parent_pipe_borrowed or pipe._active
                or (self._child_binding_attempted and
                    (not process._spawn_attempted or type(process._pid) is not int or process._pid <= 0
                     or process._pid != self._child_pid))
                or (not self._child_binding_attempted and
                    (process._pid is not None or process._spawn_syscall_attempted
                     or not cleanup and process._spawn_attempted))
                or self._read.value != self._read_value or self._write.value != self._write_value):
            raise ValueError('Original Native channel physical identities changed')
        for descriptor in (self._read, self._write):
            if (type(descriptor) is not _OriginalDescriptor or descriptor._original is not descriptor
                    or not any(value is descriptor for value in process._descriptors)
                    or type(descriptor.value) is not int or not 0 <= descriptor.value <= 2**31 - 1
                    or not cleanup and (descriptor.closed or descriptor.close_attempted)):
                raise ValueError('Original Native channel descriptor is unavailable')
        if not cleanup and (process._closing or process._parent_closed or process._exit is not None
                or process._wait_unknown is not None or pipe._closing or pipe._closed):
            raise ValueError('Original Native channel is not available for execution')

    def _require_launch(self) -> None:
        self._identity(cleanup=False)
        self._funding.require_launch()
        self._identity(cleanup=False)

    def _fact(self, expected: int) -> _OriginalArenaFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        operation, issue = self._functions.operation(self._reply), self._functions.issue(self._reply)
        if type(operation) is not int or operation != expected or type(issue) is not int or not 0 <= issue <= 8:
            raise self._mark_unknown()
        return _OriginalArenaFact(operation, issue)

    def _drop_reply(self) -> None:
        if self._reply.value is None:
            return
        self._status(self._functions.drop(byref(self._reply), self._host, self._native_domain, self._channel))
        if self._reply.value is not None:
            raise self._mark_unknown()

    def _perform(self, expected: int, call: Any, arguments: tuple[Any, ...], *, cleanup: bool = False,
                 read: str | None = None) -> tuple[_OriginalArenaFact, int | tuple[int, ...] | None]:
        # Allocate bounded outputs before the call can produce a native result.
        state, limits = c_int32(-1), (c_int64 * 6)(*([-1] * 6))
        capacities = (c_int64 * 2)(-1, -1)
        known: _OriginalLiveChannelError | None = None
        result: int | tuple[int, ...] | None = None
        with self._process._lock:
            if cleanup:
                self._identity(cleanup=True)
            else:
                self._require_launch()
            self._owner._enter()
            try:
                self._drop_reply()
                self._status(call(self._host, self._native_domain, self._channel, *arguments, byref(self._reply)))
                fact = self._fact(expected)
                if fact.issue_family == 0:
                    if read == 'state':
                        self._status(self._functions.state(self._reply, self._host, self._native_domain,
                                                          self._channel, byref(state)))
                        if state.value not in (0, 1):
                            raise self._mark_unknown()
                        result = state.value
                    elif read == 'limits':
                        self._status(self._functions.limits(self._reply, self._host, self._native_domain,
                                                           self._channel, limits))
                        result = tuple(limits)
                        if any(value < 0 for value in result):
                            raise self._mark_unknown()
                    elif read == 'capacities':
                        self._status(self._functions.capacities(self._reply, self._host, self._native_domain,
                                                               self._channel, capacities))
                        result = tuple(capacities)
                        if (result[0] != 16777216 or result[1] <= 0
                                or result[1] > 2**63 - 1 - result[0]):
                            raise self._mark_unknown()
                self._drop_reply()
            except BaseException as error:
                if error is self._unknown:
                    raise
                raise self._mark_unknown() from error
            finally:
                self._owner._busy = False
            try:
                if cleanup:
                    self._identity(cleanup=True)
                else:
                    self._require_launch()
                if fact.issue_family != 0:
                    known = _OriginalLiveChannelError(self, unknown=False, fact=fact)
                    raise known
                return fact, result
            except BaseException as error:
                if error is known or error is self._unknown:
                    raise
                raise self._mark_unknown() from error

    def bind_original_vm(self, span: _OriginalVMSpanData) -> None:
        """Trusted same-pipe control reply from the child's original observation.

        DATA is compared with the actual original Owner material; the Native
        provider separately validates the actual child/backing/live allocation.
        It is not a public input accepting a foreign Store or Caller identity.
        """
        self._require_launch()
        if not self._child_bound:
            raise ValueError('Original Native child binding is unconfirmed')
        if self._bind_attempted:
            raise ValueError('Original Native channel VM binding was already attempted')
        if (type(span) is not _OriginalVMSpanData or type(span.nonce) is not int or span.nonce != self._nonce
                or type(span.source) is not str or type(span.recipe) is not bytes
                or type(span.material) is not tuple or len(span.material) != 15
                or any(type(value) is not int or not 0 <= value <= 2**63 - 1 for value in span.material)
                or type(span.offset) is not int or not 0 <= span.offset <= 2**63 - 1
                or type(span.length) is not int or not 0 < span.length <= 2**63 - 1):
            raise ValueError('Original child VM DATA is unavailable')
        self._bind_attempted = True
        original = self._domain._project_original_material(self._material_functions)
        self._require_launch()
        if (span.source != original.source or span.recipe != original.recipe or span.material != original.scalars):
            raise ValueError('Foreign original child VM material')
        self._perform(2, self._functions.bind, (span.nonce, span.offset, span.length))

    def admit(self) -> None:
        self._require_launch()
        if not self._child_bound:
            raise ValueError('Original Native child binding is unconfirmed')
        if self._admit_attempted:
            raise ValueError('Original Native channel admission was already attempted')
        self._admit_attempted = True
        self._perform(3, self._functions.operate, (3,))

    def state(self) -> int:
        with self._process._lock:
            _, value = self._perform(4, self._functions.operate, (4,), cleanup=True, read='state')
            assert type(value) is int
            # Core-confirmed Closing remains observable for cleanup. Open must
            # also pass the current installed funding boundary before it can be
            # returned to a child import that might request fresh reservations.
            if value == 0:
                self._require_launch()
            return value

    def limits(self) -> tuple[int, ...]:
        _, value = self._perform(5, self._functions.operate, (5,), read='limits')
        assert isinstance(value, tuple)
        return value

    def capacities(self) -> tuple[int, int]:
        """Original VM/Native baseline coverage, never unused/external funding.

        These are existing Owner-selected facts. Python neither subtracts from
        a payload nor invents a Host allowance from resource limits. The Native
        baseline includes its original controls and remains held until cleanup.
        """
        _, value = self._perform(9, self._functions.operate, (9,), read='capacities')
        assert isinstance(value, tuple)
        return value[0], value[1]

    def report(self, usage: tuple[int, ...]) -> None:
        if (type(usage) is not tuple or len(usage) != 13
                or any(type(v) is not int or not -(2**31) <= v <= 2**31 - 1 for v in (*usage[:3], *usage[10:]))
                or any(type(v) is not int or not -(2**63) <= v <= 2**63 - 1 for v in usage[3:10])):
            raise ValueError('Original cumulative usage is not representable')
        self._perform(6, self._functions.report, usage, cleanup=True)

    def stop(self) -> None:
        self._identity(cleanup=True)
        if self._stop_acknowledged:
            return
        if self._stop_attempted:
            raise ValueError('Original Native channel stop was already attempted')
        self._stop_attempted = True
        self._perform(7, self._functions.operate, (7,), cleanup=True)
        self._stop_acknowledged = True

    def retire_after_owner_ack(self, channel: OriginalWorkerPipeChannel, observation: object) -> None:
        """Existing supplier's separate scoped stop + Host/Store + parent FD ACKs.

        PID/exit alone, cancellation, logical stop and an arbitrary boolean are
        insufficient. No delegation settlement/domain close is performed here.
        """
        if self._original is not self:
            raise ValueError('Foreign original Native live-channel custody')
        if self._closed and self._unknown is None:
            self._owner._enter()
            self._owner._busy = False
            return
        with self._process._lock:
            self._identity(cleanup=True)
            self._require_retirement_observations(channel, observation)
            known: _OriginalLiveChannelError | None = None
            try:
                self._funding._ack(self._funding._supplier.require_scoped_stop(
                    *self._funding_originals, observation))
                self._identity(cleanup=True)
                self._require_retirement_observations(channel, observation)
                if self._frame.value is not None:
                    self._frame_operation(8, cleanup=True, keep_reply=True)
                self._require_retirement_observations(channel, observation)
                self._owner._enter()
                try:
                    self._drop_reply()
                    self._status(self._functions.operate(self._host, self._native_domain, self._channel,
                                                       8, byref(self._reply)))
                    fact = self._fact(8)
                    if fact.issue_family != 0:
                        known = _OriginalLiveChannelError(self, unknown=False, fact=fact)
                        raise known
                    if self._frame_prepare_attempted:
                        functions = self._preparation_functions
                        assert functions is not None
                        self._status(functions.finish(byref(self._frame_host), byref(self._frame_domain),
                            byref(self._frame_channel), byref(self._frame), byref(self._frame_reply), self._reply))
                        if any(value.value is not None for value in (self._frame_host, self._frame_domain,
                                self._frame_channel, self._frame, self._frame_reply)):
                            raise self._mark_unknown()
                    self._status(self._functions.finish(byref(self._host), byref(self._native_domain),
                                                       byref(self._channel), byref(self._reply)))
                    if any(x.value is not None for x in (self._host, self._native_domain, self._channel, self._reply)):
                        raise self._mark_unknown()
                    self._closed = True
                    if self._process._native_domain is not None:
                        self._process._retire_native_metadata(self)
                    self._detach_retired_data()
                finally:
                    self._owner._busy = False
            except BaseException as error:
                if error is known or error is self._unknown:
                    raise
                raise self._mark_unknown() from error

    def _require_retirement_observations(self, channel: OriginalWorkerPipeChannel, observation: object) -> None:
        if (type(channel) is not OriginalWorkerPipeChannel or channel._process is not self._process
                    or channel._pipe is not self._pipe or channel._funding is not self._funding
                    or channel._original_channel is not channel or not channel._closed
                    or not channel._host_close_confirmed or not self._pipe._closed
                    or channel._close_active or channel._exchange_active
                    or self._pipe._readiness is not None or self._process._parent_close_inflight
                    or not self._process._parent_closed
                    or channel._control._original is not channel._control or channel._control._channel is not channel
                    or not self._funding._opaque(observation)):
            raise ValueError('Original worker scoped cleanup is unconfirmed')
