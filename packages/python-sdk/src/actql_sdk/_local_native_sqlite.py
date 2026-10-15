"""Same original Native SQLite Library transport; no loader or funding policy.

The trusted installed caller selects the component and original funded domain.
Native owns one-shot acquisition, current and cleanup; Python retains slots.
"""
from __future__ import annotations

from ctypes import POINTER, byref, c_int, c_int32, c_int64, c_uint16, c_void_p
from typing import Any, NoReturn

from ._local_native_control_custody import _OriginalArenaFact
from ._local_native_domain_custody import _OriginalDomainCustody

_RETIRED_SQLITE_DATA = object()


class _OriginalSqliteError(RuntimeError):
    def __init__(self, original: _OriginalSqliteCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_library, self.unknown, self.fact = original, unknown, fact
        super().__init__('Original Native SQLite outcome is unconfirmed' if unknown
                         else 'Original Native SQLite operation was refused')


class _OriginalSqliteFunctions:
    """Bind mandatory exports in the already selected same-provider component."""
    def __init__(self, library: Any) -> None:
        self.library = library
        self.prepare = library.actql_sqlite_prepare_utf16_into
        self.prepare.argtypes = [c_void_p, c_void_p, POINTER(c_uint16), c_int32,
                                 c_int64, c_int32, POINTER(c_void_p)]
        self.current = library.actql_sqlite_current_into
        self.close = library.actql_sqlite_close_into
        for call in (self.current, self.close):
            call.argtypes = [c_void_p, c_void_p, POINTER(c_void_p)]
        self.originals = library.actql_sqlite_originals_into
        self.originals.argtypes = [c_void_p] + [POINTER(c_void_p)] * 3
        self.drop = library.actql_sqlite_drop_reply
        self.drop.argtypes = [POINTER(c_void_p), c_void_p, c_void_p, c_void_p]
        self.finish = library.actql_sqlite_finish_closed_data
        self.finish.argtypes = [POINTER(c_void_p)] * 4
        self.refused = library.actql_sqlite_finish_refused_prepare
        self.refused.argtypes = [POINTER(c_void_p)] * 3
        for call in (self.prepare, self.current, self.close, self.originals,
                     self.drop, self.finish, self.refused):
            call.restype = c_int
        self.operation = library.actql_sqlite_operation
        self.issue = library.actql_sqlite_issue_family
        for call in (self.operation, self.issue):
            call.argtypes = [c_void_p]
            call.restype = c_int32


class _OriginalSqliteCustody:
    """One original Library/partial carrier and its same Host/domain loans.

    All out-slots exist before a native call. Unknown is sticky and cannot
    cause a second prepare/close/drop. Known refusal retains original cleanup.
    """
    __slots__ = ('_domain', '_functions', '_host', '_native_domain',
                 '_original', '_reply', '_unknown', '_unknown_carrier', '_closed')
    _domain: _OriginalDomainCustody
    _functions: _OriginalSqliteFunctions
    _host: c_void_p
    _native_domain: c_void_p
    _original: c_void_p
    _reply: c_void_p
    _unknown: _OriginalSqliteError | None
    _unknown_carrier: _OriginalSqliteError
    _closed: bool

    @classmethod
    def _prepare_original(cls, domain: _OriginalDomainCustody,
                          functions: _OriginalSqliteFunctions,
                          *, path: str, heap_bytes: int, diagnostic_ceiling: int) -> _OriginalSqliteCustody:
        if (type(domain) is not _OriginalDomainCustody
                or type(functions) is not _OriginalSqliteFunctions
                or functions.library is not domain._functions.library
                or domain._closed or domain._unknown is not None
                or domain._sqlite_library_original is not None
                or type(path) is not str or not 0 < len(path) <= 4096
                or not path.startswith('/') or '\0' in path
                or type(heap_bytes) is not int or not -(2**63) <= heap_bytes <= 2**63 - 1
                or type(diagnostic_ceiling) is not int
                or not -(2**31) <= diagnostic_ceiling <= 2**31 - 1):
            raise ValueError('Original Native SQLite inputs are unavailable')
        raw = path.encode('utf-16-le')
        units = len(raw) // 2
        if units > 4096:
            raise ValueError('Original Native SQLite path exceeds its ABI bound')
        text = (c_uint16 * units).from_buffer_copy(raw)
        original = cls.__new__(cls)
        original._domain, original._functions = domain, functions
        original._host, original._native_domain = c_void_p(), c_void_p()
        original._original, original._reply = c_void_p(), c_void_p()
        original._unknown, original._closed = None, False
        original._unknown_carrier = _OriginalSqliteError(original, unknown=True)
        # These argument wrappers can allocate. Prepare them before consuming
        # the original entry scope or registering a foreign-call responsibility.
        reply_out, host_out = byref(original._reply), byref(original._host)
        domain_out, original_out = byref(original._native_domain), byref(original._original)
        known: _OriginalSqliteError | None = None
        # Busy/reentry/thread/process and an existing parent Unknown are the
        # original Owner's pre-call refusal, not an uncertain SQLite operation.
        domain._owner._enter()
        try:
            if (domain._closed or domain._unknown is not None
                    or domain._sqlite_library_original is not None):
                raise ValueError('Original Native SQLite domain is unavailable')
            # Register only after entry, but before an actual foreign call can
            # publish a partial Library/reply. Keep it on every later failure.
            domain._sqlite_library_original = original
            try:
                original._status(functions.prepare(domain._host, domain._domain, text, units,
                    heap_bytes, diagnostic_ceiling, reply_out))
                original._status(functions.originals(original._reply, host_out,
                    domain_out, original_out))
                if (original._host.value != domain._host.value
                        or original._native_domain.value != domain._domain.value):
                    raise original._mark_unknown()
                fact = original._fact(1)
                if original._original.value is None:
                    if fact.issue_family == 0:
                        raise original._mark_unknown()
                    original._status(functions.refused(byref(original._host),
                        byref(original._native_domain), byref(original._reply)))
                    original._finish_data_ack()
                else:
                    original._drop()
                if fact.issue_family != 0:
                    known = _OriginalSqliteError(original, unknown=False, fact=fact)
                    raise known
            except BaseException as error:
                if error is known or error is original._unknown:
                    raise
                raise original._mark_unknown() from error
        finally:
            domain._owner._busy = False
        return original

    def __copy__(self) -> _OriginalSqliteCustody:
        raise TypeError('Original Native SQLite custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalSqliteCustody:
        raise TypeError('Original Native SQLite custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Native SQLite custody cannot be serialized')

    def _mark_unknown(self) -> _OriginalSqliteError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _fact(self, operation: int) -> _OriginalArenaFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        actual, issue = self._functions.operation(self._reply), self._functions.issue(self._reply)
        if (type(actual) is not int or actual != operation
                or type(issue) is not int or not 0 <= issue <= 20):
            raise self._mark_unknown()
        return _OriginalArenaFact(actual, issue)

    def _drop(self) -> None:
        if self._reply.value is None:
            return
        self._status(self._functions.drop(byref(self._reply), self._host,
                                         self._native_domain, self._original))
        if self._reply.value is not None:
            raise self._mark_unknown()

    def _finish_data_ack(self) -> None:
        if any(slot.value is not None for slot in
               (self._host, self._native_domain, self._original, self._reply)):
            raise self._mark_unknown()
        self._closed = True
        # Same-domain one-shot tombstone, not a fresh permit/cleanup Owner.
        # Break the Python registration cycle only after known data-drop ACK.
        self._domain._sqlite_library_original = _RETIRED_SQLITE_DATA

    def _call(self, operation: int) -> _OriginalArenaFact:
        if self._unknown is not None:
            raise self._unknown
        domain = self._domain
        if (domain._sqlite_library_original is not self or self._closed
                or domain._closed or self._original.value is None):
            raise ValueError('Original Native SQLite carrier is retired')
        known: _OriginalSqliteError | None = None
        reply_out = byref(self._reply)
        # Entry can refuse before any drop/current/close has started. Preserve
        # that exact refusal and the original Library for later cleanup.
        domain._owner._enter()
        try:
            self._drop()
            call = self._functions.current if operation == 2 else self._functions.close
            self._status(call(self._host, self._original, reply_out))
            fact = self._fact(operation)
            if operation == 3 and fact.issue_family == 0:
                self._status(self._functions.finish(byref(self._host), byref(self._native_domain),
                    byref(self._original), byref(self._reply)))
                self._finish_data_ack()
            else:
                self._drop()
            if fact.issue_family != 0:
                known = _OriginalSqliteError(self, unknown=False, fact=fact)
                raise known
        except BaseException as error:
            if error is known or error is self._unknown:
                raise
            raise self._mark_unknown() from error
        finally:
            domain._owner._busy = False
        return fact

    def current(self) -> _OriginalArenaFact:
        return self._call(2)

    def close(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if self._closed:
            self._domain._owner._enter()
            self._domain._owner._busy = False
            return
        self._call(3)
