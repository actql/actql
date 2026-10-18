"""Thin transport of the existing scoped Native Runtime and original carrier.

This driver does not adopt files, issue capacity or interpret Run outcomes.
The existing Native Runtime owns Root/Reader cleanup. Its last data aliases
must be dropped before the outer original read can seek physical retirement.
"""
from __future__ import annotations

from ctypes import byref, c_uint16, c_void_p
from typing import Any, NoReturn

from ._local_native_runtime_abi import bind

from ._local_native_control_custody import _OriginalArenaFact
from ._local_native_original_read import (
    _OriginalParentReadCustody, _RETIRED_PARENT_RUNTIME_DATA)
from ._local_native_host_resources import (
    _OriginalHostResourcesCustody, _resources_for_domain)


class _OriginalPackagedRuntimeError(RuntimeError):
    def __init__(self, original: _OriginalPackagedRuntimeCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_runtime, self.unknown, self.fact = original, unknown, fact
        super().__init__('Original packaged Runtime outcome is unconfirmed' if unknown
                         else 'Original packaged Runtime operation was refused')


class _OriginalPackagedRuntimeFunctions:
    def __init__(self, library: Any) -> None:
        self.library = library
        calls = bind(library)
        self.capture = calls['capture_utf16_into']
        self.capture_pair = calls['capture_host_resources_utf16_into']
        self.current, self.close = calls['current_into'], calls['close_into']
        self.originals = calls['originals_into']
        self.drop = calls['drop_reply']
        self.finish = calls['finish_closed_data']
        self.refused = calls['finish_refused_capture']
        self.operation, self.issue = calls['operation'], calls['issue_family']



def _exact_utf16(value: str, maximum: int, *, exact: int | None = None) -> Any:
    if type(value) is not str or not value or len(value) > maximum:
        raise ValueError('Original packaged Runtime input is unavailable')
    raw = value.encode('utf-16-le', errors='strict')
    units = len(raw) // 2
    if units > maximum or exact is not None and units != exact:
        raise ValueError('Original packaged Runtime input is unavailable')
    return (c_uint16 * units).from_buffer_copy(raw)


class _OriginalPackagedRuntimeCustody:
    """Physical output-slot responsibility on the same Native read, not a FSM."""
    __slots__ = ('_read', '_functions', '_host', '_original_read', '_runtime',
                 '_reply', '_product_reply', '_unknown', '_unknown_carrier', '_closed', '_resources')
    _read: _OriginalParentReadCustody
    _functions: _OriginalPackagedRuntimeFunctions
    _host: c_void_p
    _original_read: c_void_p
    _runtime: c_void_p
    _reply: c_void_p
    _product_reply: c_void_p
    _unknown: _OriginalPackagedRuntimeError | None
    _unknown_carrier: _OriginalPackagedRuntimeError
    _closed: bool
    _resources: _OriginalHostResourcesCustody | None

    @classmethod
    def _capture_original(cls, read: _OriginalParentReadCustody,
                          functions: _OriginalPackagedRuntimeFunctions, *,
                          root_path: str, source_sha: str, platform: str,
                          manifest_sha256: str, diagnostic_ceiling: int
                          ) -> _OriginalPackagedRuntimeCustody:
        if (cls is not _OriginalPackagedRuntimeCustody
                or type(read) is not _OriginalParentReadCustody
                or type(functions) is not _OriginalPackagedRuntimeFunctions
                or functions.library is not read._functions.library
                or type(diagnostic_ceiling) is not int
                or not 0 < diagnostic_ceiling < 2**31):
            raise ValueError('Original packaged Runtime selection is unavailable')
        if read._unknown is not None:
            raise read._unknown
        if read._domain._unknown is not None:
            raise read._domain._unknown
        if read._closed or read._scope_open or read._runtime_original is not None:
            raise ValueError('Original packaged Runtime read is unavailable')
        owner = read._domain._owner
        binding = _resources_for_domain(read._domain)
        resources = None if binding is None else binding[0]
        if getattr(owner, '_host_resources_original', None) is not resources:
            raise ValueError('Original packaged Runtime Host pair is unavailable')
        if resources is not None:
            if resources._unknown is not None:
                raise resources._unknown
            if (binding is None or binding[1] != 'read' or resources._read is not read
                    or resources._closed or resources._phase is not None):
                raise ValueError('Original packaged Runtime Host pair is unavailable')
        buffers = (_exact_utf16(root_path, 4096),
                   _exact_utf16(source_sha, 40, exact=40),
                   _exact_utf16(platform, 32),
                   _exact_utf16(manifest_sha256, 64, exact=64))
        original = cls.__new__(cls)
        original._read, original._functions = read, functions
        original._resources = resources
        original._host, original._original_read = c_void_p(), c_void_p()
        original._runtime, original._reply = c_void_p(), c_void_p()
        original._product_reply = c_void_p()
        original._unknown, original._closed = None, False
        original._unknown_carrier = _OriginalPackagedRuntimeError(original, unknown=True)
        out, host_out = byref(original._reply), byref(original._host)
        read_out, runtime_out = byref(original._original_read), byref(original._runtime)
        known: _OriginalPackagedRuntimeError | None = None
        # All allocations precede entry. A known local refusal does not create
        # or poison foreign responsibility and never clears somebody's busy.
        owner._enter()
        try:
            if (read._closed or read._scope_open or read._runtime_original is not None
                    or read._domain._closed):
                raise ValueError('Original packaged Runtime read is unavailable')
            if read._unknown is not None:
                raise read._unknown
            if read._domain._unknown is not None:
                raise read._domain._unknown
            if (getattr(owner, '_host_resources_original', None) is not resources
                    or resources is not None and (resources._closed or resources._phase is not None)):
                raise ValueError('Original packaged Runtime Host pair is unavailable')
            if resources is not None and resources._unknown is not None:
                raise resources._unknown
            read._runtime_original = original
            try:
                a, b, c, d = buffers
                if resources is None:
                    original._status(functions.capture(read._host, read._original,
                        a, len(a), b, len(b), c, len(c), d, len(d), diagnostic_ceiling, out))
                else:
                    original._status(functions.capture_pair(read._host, read._original,
                        resources._original, a, len(a), b, len(b), c, len(c), d, len(d),
                        diagnostic_ceiling, out))
                original._status(functions.originals(original._reply,
                    host_out, read_out, runtime_out))
                if (original._host.value != read._host.value
                        or original._original_read.value != read._original.value):
                    raise original._mark_unknown()
                fact = original._fact(1)
                if original._runtime.value is None:
                    if fact.issue_family == 0:
                        raise original._mark_unknown()
                    original._status(functions.refused(byref(original._host),
                        byref(original._original_read), byref(original._reply)))
                    original._finish_ack()
                else:
                    original._drop()
                if fact.issue_family:
                    known = original._owner_issue(fact)
                    raise known
            except BaseException as error:
                if error is known or error is original._unknown:
                    raise
                raise original._mark_unknown() from error
        finally:
            owner._busy = False
        return original

    def __copy__(self) -> NoReturn:
        raise TypeError('Original packaged Runtime custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original packaged Runtime custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original packaged Runtime custody cannot be serialized')

    def _mark_unknown(self) -> _OriginalPackagedRuntimeError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _owner_issue(self, fact: _OriginalArenaFact) -> _OriginalPackagedRuntimeError:
        if fact.issue_family == 7:
            self._unknown_carrier.fact = fact
            return self._mark_unknown()
        return _OriginalPackagedRuntimeError(self, unknown=False, fact=fact)

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _fact(self, operation: int) -> _OriginalArenaFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        op, issue = self._functions.operation(self._reply), self._functions.issue(self._reply)
        if (type(op) is not int or op != operation
                or type(issue) is not int or not 0 <= issue <= 10):
            raise self._mark_unknown()
        return _OriginalArenaFact(op, issue)

    def _drop(self) -> None:
        if self._reply.value is not None:
            self._status(self._functions.drop(byref(self._reply), self._host,
                self._original_read, self._runtime))
            if self._reply.value is not None:
                raise self._mark_unknown()

    def _finish_ack(self) -> None:
        if (any(x.value is not None for x in
                (self._host, self._original_read, self._runtime, self._reply))
                or self._read._runtime_original is not self):
            raise self._mark_unknown()
        self._closed = True
        # Cut the reverse registration only after inner cleanup/data ACK.
        # An escaped retired alias cannot authorize another capture attempt.
        self._read._runtime_original = _RETIRED_PARENT_RUNTIME_DATA

    def _available(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if self._read._unknown is not None:
            raise self._read._unknown
        if self._read._domain._unknown is not None:
            raise self._read._domain._unknown
        if self._resources is not None:
            if self._resources._unknown is not None:
                raise self._resources._unknown
            if (self._resources._closed or self._resources._phase is not None
                    or self._read._domain._owner._host_resources_original is not self._resources):
                raise ValueError('Original packaged Runtime Host pair is unavailable')
        if (self._closed or self._read._closed or self._read._domain._closed
                or self._runtime.value is None
                or self._read._runtime_original is not self or self._read._scope_open
                or self._product_reply.value is not None):
            raise ValueError('Original packaged Runtime is retired or unavailable')

    def _call(self, operation: int) -> _OriginalArenaFact:
        if operation not in (2, 3):
            raise ValueError('Original packaged Runtime operation is unavailable')
        self._available()
        out = byref(self._reply)
        known: _OriginalPackagedRuntimeError | None = None
        owner = self._read._domain._owner
        owner._enter()
        try:
            self._available()
            try:
                self._drop()
                call = self._functions.current if operation == 2 else self._functions.close
                self._status(call(self._runtime, out))
                fact = self._fact(operation)
                if operation == 3 and fact.issue_family == 0:
                    self._status(self._functions.finish(byref(self._host),
                        byref(self._original_read), byref(self._runtime), byref(self._reply)))
                    self._finish_ack()
                else:
                    self._drop()
                if fact.issue_family:
                    known = self._owner_issue(fact)
                    raise known
            except BaseException as error:
                if error is known or error is self._unknown:
                    raise
                raise self._mark_unknown() from error
        finally:
            owner._busy = False
        return fact

    def current(self) -> _OriginalArenaFact:
        return self._call(2)

    def close(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if self._closed:
            self._read._domain._owner._enter()
            self._read._domain._owner._busy = False
            return
        self._call(3)
