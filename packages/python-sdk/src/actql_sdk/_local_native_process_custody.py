"""Original Native process transport; no supplier, worker FSM or authority.

All preparation, launch, current, stop and cleanup decisions remain in the
same original installed Host/domain/Holder. Persistent C slots retain partial
custody even when a foreign response is lost. No Loader/Engine/VM is started.
"""
from __future__ import annotations

from ctypes import byref, c_int32, c_uint16, c_ubyte, c_void_p
from typing import Any

from ._local_native_control_custody import _OriginalArenaFact, _OriginalControlCustody
from ._local_native_domain_custody import _OriginalDomainCustody
from ._local_native_shim_abi import bind


class _OriginalInstalledProcessError(RuntimeError):
    def __init__(self, process: _OriginalInstalledProcessCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_process, self.unknown, self.fact = process, unknown, fact
        super().__init__('Original Native process outcome is unconfirmed' if unknown
                         else 'Original Native process operation was refused')


class _OriginalInstalledProcessFunctions:
    def __init__(self, library: Any) -> None:
        self.library = library
        self.prepare = bind(library, 'actql_process_prepare_utf16_into')
        self.operate = bind(library, 'actql_process_operate_into')
        self.child = bind(library, 'actql_process_child_utf16_into')
        self.originals = bind(library, 'actql_process_originals_into')
        self.operation = bind(library, 'actql_process_operation')
        self.issue = bind(library, 'actql_process_issue_family')
        self.facts = bind(library, 'actql_process_copy_facts')
        self.drop = bind(library, 'actql_process_drop_reply')
        self.finish = bind(library, 'actql_process_finish_closed_data')
        self.refused = bind(library, 'actql_process_finish_refused_prepare')


def _text(value: str) -> tuple[Any, int]:
    if type(value) is not str or not value or '\0' in value:
        raise ValueError('Original process text is unavailable')
    raw = value.encode('utf-16-le', errors='strict')
    if len(raw) // 2 > 2**31 - 1:
        raise ValueError('Original process text exceeds its ABI')
    return (c_uint16 * (len(raw) // 2)).from_buffer_copy(raw), len(raw) // 2


def _fields(values: tuple[str, ...]) -> bytes:
    if any(type(value) is not str or '\0' in value for value in values):
        raise ValueError('Original process fields are unavailable')
    return b''.join(value.encode('utf-8', errors='strict') + b'\0' for value in values)


class _OriginalInstalledProcessCustody:
    """Thin same-Owner opaque references, not another process cleanup machine."""
    __slots__ = ('_domain', '_owner', '_functions', '_host', '_native_domain',
                 '_process', '_channel', '_frame', '_reply', '_unknown',
                 '_unknown_carrier', '_closed')

    _domain: _OriginalDomainCustody
    _owner: _OriginalControlCustody
    _functions: _OriginalInstalledProcessFunctions
    _host: c_void_p
    _native_domain: c_void_p
    _process: c_void_p
    _channel: c_void_p
    _frame: c_void_p
    _reply: c_void_p
    _unknown: _OriginalInstalledProcessError | None
    _unknown_carrier: _OriginalInstalledProcessError
    _closed: bool

    def __init__(self) -> None:
        raise TypeError('Original process requires trusted installed physical assembly')

    @classmethod
    def _prepare_original(cls, domain: _OriginalDomainCustody,
                          functions: _OriginalInstalledProcessFunctions, *, path: str,
                          nonce: int, retained: int, execution: int) -> _OriginalInstalledProcessCustody:
        if (type(domain) is not _OriginalDomainCustody
                or type(functions) is not _OriginalInstalledProcessFunctions
                or functions.library is not domain._functions.library
                or functions.library is not domain._owner._functions.library
                or any(type(n) is not int or not 0 <= n <= 2**63 - 1
                       for n in (nonce, retained, execution))):
            raise ValueError('Original Native process inputs are unavailable')
        text, units = _text(path)
        process = cls.__new__(cls)
        process._domain, process._owner, process._functions = domain, domain._owner, functions
        process._host, process._native_domain, process._process = c_void_p(), c_void_p(), c_void_p()
        process._channel, process._frame, process._reply = c_void_p(), c_void_p(), c_void_p()
        process._unknown, process._closed = None, False
        process._unknown_carrier = _OriginalInstalledProcessError(process, unknown=True)
        # Known local entry failures remain outside the uncertain foreign-call
        # catch. No Native responsibility exists or is changed by this refusal.
        process._owner._enter()
        if (domain._closed or domain._unknown is not None or domain._domain.value is None
                or domain._installed_process_original is not None
                or domain._worker_process_original is not None
                or domain._live_channel_original is not None
                or domain._descriptor.closed or domain._descriptor.close_attempted):
            process._owner._busy = False
            raise ValueError('Original Native process domain is unavailable')
        domain._installed_process_original = process
        known: _OriginalInstalledProcessError | None = None
        try:
            process._status(functions.prepare(domain._host, domain._domain, text, units,
                domain._descriptor.value, nonce, retained, execution, byref(process._reply)))
            process._status(functions.originals(process._reply, byref(process._host),
                byref(process._native_domain), byref(process._process),
                byref(process._channel), byref(process._frame)))
            if (process._host.value != domain._host.value
                    or process._native_domain.value != domain._domain.value):
                raise process._mark_unknown()
            fact = process._fact(1)
            if process._process.value is None:
                if fact.issue_family == 0:
                    raise process._mark_unknown()
                process._status(functions.refused(byref(process._host),
                    byref(process._native_domain), byref(process._reply)))
                if any(slot.value is not None for slot in process._slots()):
                    raise process._mark_unknown()
                process._closed = True
                domain._installed_process_original = None
            else:
                process._drop()
            if fact.issue_family != 0:
                known = _OriginalInstalledProcessError(process, unknown=False, fact=fact)
                raise known
            return process
        except BaseException as error:
            if error is process._unknown or error is known:
                raise
            raise process._mark_unknown() from error
        finally:
            process._owner._busy = False

    def _slots(self) -> tuple[c_void_p, ...]:
        return (self._host, self._native_domain, self._process,
                self._channel, self._frame, self._reply)

    def _status(self, status: int) -> None:
        if type(status) is not int or status != 0:
            raise self._mark_unknown()

    def _mark_unknown(self) -> _OriginalInstalledProcessError:
        self._unknown = self._unknown_carrier
        return self._unknown_carrier

    def _fact(self, expected: int) -> _OriginalArenaFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        operation, issue = self._functions.operation(self._reply), self._functions.issue(self._reply)
        if (type(operation) is not int or operation != expected
                or type(issue) is not int or not 0 <= issue <= 11):
            raise self._mark_unknown()
        return _OriginalArenaFact(operation, issue)

    def _drop(self) -> None:
        self._status(self._functions.drop(byref(self._reply), self._host,
            self._native_domain, self._process))
        if self._reply.value is not None:
            raise self._mark_unknown()

    def _enter(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        self._owner._enter()
        if (self._closed or self._domain._installed_process_original is not self
                or self._process.value is None or self._domain._closed
                or self._domain._unknown is not None):
            self._owner._busy = False
            raise ValueError('Original Native process is unavailable')

    def _operate(self, operation: int) -> tuple[_OriginalArenaFact, tuple[int, ...] | None]:
        if type(operation) is not int or operation not in (2, 3, 4, 5, 6, 7, 8, 9, 11, 12):
            raise ValueError('Original Native process operation is unavailable')
        values = (c_int32 * 4)()
        self._enter()
        known: _OriginalInstalledProcessError | None = None
        try:
            self._drop()
            self._status(self._functions.operate(self._host, self._native_domain,
                self._process, operation, byref(self._reply)))
            fact = self._fact(operation)
            result = None
            if fact.issue_family == 0 and operation in (3, 6, 9, 12):
                self._status(self._functions.facts(self._reply, self._host,
                    self._native_domain, self._process, values))
                result = tuple(values)
            if fact.issue_family == 0 and operation in (7, 8):
                self._status(self._functions.finish(byref(self._host), byref(self._native_domain),
                    byref(self._process), byref(self._channel), byref(self._frame), byref(self._reply)))
                if any(slot.value is not None for slot in self._slots()):
                    raise self._mark_unknown()
                self._closed = True
                self._domain._installed_process_original = None
            else:
                self._drop()
            if fact.issue_family != 0:
                known = _OriginalInstalledProcessError(self, unknown=False, fact=fact)
                raise known
            return fact, result
        except BaseException as error:
            if error is self._unknown or error is known:
                raise
            raise self._mark_unknown() from error
        finally:
            self._owner._busy = False

    def prepare_child(self, executable: str, arguments: tuple[str, ...],
                      environment: tuple[tuple[str, str], ...]) -> None:
        if (type(arguments) is not tuple or len(arguments) > 255 or type(environment) is not tuple
                or len(environment) > 4 or any(type(pair) is not tuple or len(pair) != 2 for pair in environment)):
            raise ValueError('Original Native child inputs are unavailable')
        text, units = _text(executable)
        args, env = _fields(arguments), _fields(tuple(value for pair in environment for value in pair))
        argument_bytes, environment_bytes = (c_ubyte * len(args)).from_buffer_copy(args), (c_ubyte * len(env)).from_buffer_copy(env)
        self._enter()
        known: _OriginalInstalledProcessError | None = None
        try:
            self._drop()
            self._status(self._functions.child(self._host, self._native_domain, self._process,
                text, units, argument_bytes, len(args), environment_bytes, len(env), byref(self._reply)))
            fact = self._fact(10)
            self._drop()
            if fact.issue_family != 0:
                known = _OriginalInstalledProcessError(self, unknown=False, fact=fact)
                raise known
        except BaseException as error:
            if error is self._unknown or error is known:
                raise
            raise self._mark_unknown() from error
        finally:
            self._owner._busy = False

    def current(self) -> None:
        self._operate(2)

    def spawn(self) -> None:
        self._operate(11)

    def request_stop(self) -> bool:
        """Relay to the same original child; never observe stop or release.

        False means the request was not confirmed. A lost/invalid response
        keeps the existing sticky Unknown; it does not retry the signal.
        """
        _, facts = self._operate(12)
        if facts is None or facts[3] not in (0, 1):
            raise self._mark_unknown()
        return facts[3] == 1

    def restrict_transport(self) -> None:
        self._operate(4)

    def return_transport(self) -> None:
        self._operate(5)

    def poll_stop(self) -> bool:
        _, facts = self._operate(6)
        if facts is None or facts[3] not in (1, 2):
            raise self._mark_unknown()
        return facts[3] == 2

    def close_unstarted(self) -> None:
        if self._closed:
            self._owner._enter()
            self._owner._busy = False
            return
        self._operate(7)

    def retire_stopped(self) -> None:
        self._operate(8)

    def __copy__(self) -> Any:
        raise TypeError('Original Native process cannot be copied')

    def __deepcopy__(self, memo: Any) -> Any:
        raise TypeError('Original Native process cannot be copied')

    def __reduce__(self) -> Any:
        raise TypeError('Original Native process cannot be serialized')
