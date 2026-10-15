"""Transport the SAME Core-issued fenced read child; no Python TX Owner.

Read start/stop observations never acknowledge the original uncertain write.
Persistent child/reply out-slots and the parent registration survive response
loss. Known cleanup uses only the same original Core child; no SQL is replayed.
"""
from __future__ import annotations

from ctypes import POINTER, byref, c_int, c_int32, c_int64, c_uint16, c_ubyte, c_void_p
from typing import Any, Callable, NoReturn

from ._local_native_sqlite_database import (
    _OriginalDatabaseCustody, _OriginalDatabaseFact, _OriginalDatabaseFunctions,
    _read_database_fact, _text)


class _OriginalLookupError(RuntimeError):
    def __init__(self, original: _OriginalLookupCustody, *, unknown: bool,
                 operation: int, fact: _OriginalDatabaseFact | None = None) -> None:
        self.cleanup_lookup = original
        self.cleanup_database = original._database
        self.unknown, self.operation, self.fact = unknown, operation, fact
        super().__init__('Original Native lookup read is unconfirmed' if unknown
                         else 'Original Native lookup read was refused')


class _OriginalLookupFunctions:
    def __init__(self, library: Any) -> None:
        p, pp, text = c_void_p, POINTER(c_void_p), POINTER(c_uint16)
        signatures: dict[str, tuple[list[Any], Any]] = {
            'start_into': ([p, p, pp, pp], c_int),
            'observe_into': ([p, p, pp], c_int),
            'read_utf16_into': ([p, p, text, c_int32, text, c_int32, c_int64, pp], c_int),
            'scan_utf16_into': ([p, p, text, c_int32, text, c_int32, c_int64, pp], c_int),
            'header_utf16_into': ([p, p, text, c_int32, text, c_int32, pp], c_int),
            'capacity_utf16_into': ([p, p, text, c_int32, text, c_int32, pp], c_int),
            'capacity_usage_utf16_into': ([p, p, text, c_int32, pp], c_int),
            'database_usage_into': ([p, p, pp], c_int),
            'finish_into': ([p, p, pp], c_int),
            'close_into': ([p, p, pp], c_int),
            'drop': ([pp], c_int),
        }
        self.calls: dict[str, Any] = {}
        for name, (args, result) in signatures.items():
            call = getattr(library, 'actql_sqlite_lookup_' + name)
            call.argtypes, call.restype = args, result
            self.calls[name] = call


class _OriginalLookupCustody:
    """An alias of Core's nominal read child, registered before foreign start.

    Local flags describe retained transport custody only. Every actual read
    still passes the original Core current/nominal checks. Cleanup ACKs cannot
    turn a failed observation or the old write into a successful operation.
    """
    __slots__ = ('_database', '_calls', '_lookup', '_reply', '_closed',
                 '_response_unknown', '_retirement_unknown', '_unknown_carrier',
                 '_last_operation', '_cleanup_ack', '_failed_observation')
    _database: _OriginalDatabaseCustody
    _calls: _OriginalLookupFunctions
    _lookup: c_void_p
    _reply: c_void_p
    _closed: bool
    _response_unknown: _OriginalLookupError | None
    _retirement_unknown: _OriginalLookupError | None
    _unknown_carrier: _OriginalLookupError
    _last_operation: int
    _cleanup_ack: _OriginalDatabaseFact | None
    _failed_observation: bool

    @property
    def _functions(self) -> _OriginalDatabaseFunctions:
        return self._database._functions

    @property
    def _original(self) -> c_void_p:
        return self._database._original

    @property
    def _bound(self) -> int:
        return self._database._bound

    @classmethod
    def _prepare(cls, database: _OriginalDatabaseCustody) -> _OriginalLookupCustody:
        if type(database) is not _OriginalDatabaseCustody:
            raise ValueError('Original Native lookup Database is unavailable')
        database._local(allow_unconfirmed=True)
        calls = _OriginalLookupFunctions(database._functions.library)
        original = cls.__new__(cls)
        original._database, original._calls = database, calls
        original._lookup, original._reply = c_void_p(), c_void_p()
        original._closed, original._failed_observation = False, False
        original._response_unknown = original._retirement_unknown = None
        original._last_operation, original._cleanup_ack = 22, None
        original._unknown_carrier = _OriginalLookupError(original, unknown=True, operation=22)
        owner = database._library._domain._owner
        owner._enter()
        known: _OriginalLookupError | None = None
        try:
            # Known busy/thread/current refusal precedes registration and FFI.
            database._local(allow_unconfirmed=True)
            if database._lookup_original is not None:
                raise ValueError('Original Native Database has a retained read child')
            database._lookup_original = original
            try:
                code = calls.calls['start_into'](database._host, database._original,
                    byref(original._lookup), byref(original._reply))
                original._status(code)
                fact = original._fact(22)
                if (fact.stage not in (0, 1) or fact.after_issue_family != 0
                        or (fact.stage == 1) != (original._lookup.value is not None)
                        or fact.stage == 0 and not fact.issue_family):
                    raise original._mark_unknown()
                original._drop_reply()
                if fact.issue_family:
                    known = _OriginalLookupError(original, unknown=False, operation=22, fact=fact)
                    original._failed_observation = True
                    if original._lookup.value is None:
                        original._closed = True
                        database._lookup_original = None
                    raise known
            except BaseException as error:
                if error is known or error is original._retirement_unknown or error is original._response_unknown:
                    raise
                raise original._mark_unknown() from error
        finally:
            owner._busy = False
        return original

    def __copy__(self) -> _OriginalLookupCustody:
        raise TypeError('Original Native lookup custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalLookupCustody:
        raise TypeError('Original Native lookup custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Native lookup custody cannot be serialized')

    def _mark_unknown(self) -> _OriginalLookupError:
        self._failed_observation = True
        if self._response_unknown is None:
            if self._retirement_unknown is None:
                self._unknown_carrier.operation = self._last_operation
            self._response_unknown = self._unknown_carrier
        return self._response_unknown

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _fact(self, operation: int) -> _OriginalDatabaseFact:
        return _read_database_fact(self, operation,
            preflight=operation in (24, 25, 26, 27, 28), preflight_operation=23)

    def _local(self, *, cleanup: bool = False) -> None:
        self._database._local(allow_unconfirmed=True)
        if self._database._lookup_original is not self or self._closed:
            raise ValueError('Original Native lookup child is retired or foreign')
        if self._retirement_unknown is not None:
            raise self._retirement_unknown
        if not cleanup:
            if self._response_unknown is not None:
                raise self._response_unknown
            if self._failed_observation or self._lookup.value is None:
                raise ValueError('Original Native lookup observation is unavailable')

    def _drop_reply(self) -> None:
        if self._reply.value is None:
            return
        try:
            code = self._functions.calls['drop_reply'](byref(self._reply), self._database._host,
                self._database._native_library, self._original)
            if type(code) is not int or code != 0 or self._reply.value is not None:
                raise RuntimeError('Original lookup reply retirement is unconfirmed')
        except BaseException as error:
            if self._response_unknown is None:
                self._unknown_carrier.operation = self._last_operation
            self._retirement_unknown = self._unknown_carrier
            self._failed_observation = True
            raise self._retirement_unknown from error

    def _managed(self, operation: int, call: Callable[[Any], Any], *,
                 output: Any = None, capacity: int = 0,
                 key_output: tuple[Any, int, c_int64] | None = None
                 ) -> tuple[_OriginalDatabaseFact, int | None]:
        self._local()
        database = self._database
        attempted = False
        known: _OriginalLookupError | None = None
        try:
            with database._library._domain._read_scope(database._read):
                owner = database._library._domain._owner
                owner._enter()
                known = None
                try:
                    self._local()
                    if self._reply.value is not None:
                        raise self._mark_unknown()
                    self._last_operation = operation
                    try:
                        attempted = True
                        self._status(call(byref(self._reply)))
                        fact = self._fact(operation)
                        length: int | None = None
                        if not fact.issue_family and not fact.after_issue_family and fact.has_row:
                            size = c_int64(-1)
                            self._status(self._functions.calls['copy_row'](self._reply, database._host,
                                database._native_library, self._original, output, capacity, byref(size)))
                            if not 0 <= size.value <= min(capacity, self._bound):
                                raise self._mark_unknown()
                            length = size.value
                            if key_output is not None:
                                key, key_capacity, key_size = key_output
                                self._status(self._functions.calls['copy_key'](self._reply, database._host,
                                    database._native_library, self._original, key, key_capacity, byref(key_size)))
                                if not 0 < key_size.value <= min(key_capacity, 512):
                                    raise self._mark_unknown()
                        self._drop_reply()
                        if fact.issue_family or fact.after_issue_family:
                            known = _OriginalLookupError(self, unknown=False, operation=operation, fact=fact)
                            if operation == 30 or fact.after_issue_family:
                                self._failed_observation = True
                            raise known
                        if fact.stage != 2:
                            raise self._mark_unknown()
                        if operation == 30:
                            self._cleanup_ack = fact
                        return fact, length
                    except BaseException as error:
                        if error is known or error is self._retirement_unknown or error is self._response_unknown:
                            raise
                        raise self._mark_unknown() from error
                finally:
                    owner._busy = False
        except BaseException as error:
            if attempted and error is not known:
                self._failed_observation = True
            raise

    def read_into(self, scope: str, key: str, output: bytearray) -> tuple[_OriginalDatabaseFact, int | None]:
        s, sn = _text(scope); k, kn = _text(key)
        if type(output) is not bytearray or not 0 < len(output) <= self._bound:
            raise ValueError('Original lookup output bound is invalid')
        buffer = (c_ubyte * len(output)).from_buffer(output)
        return self._managed(24, lambda r: self._calls.calls['read_utf16_into'](
            self._database._host, self._lookup, s, sn, k, kn, len(output), r),
            output=buffer, capacity=len(output))

    def scan_after_into(self, scope: str, after_key: str, key_output: bytearray,
                        body_output: bytearray) -> tuple[_OriginalDatabaseFact, int, int]:
        s, sn = _text(scope); k, kn = _text(after_key, cursor=True)
        if (type(key_output) is not bytearray or not 0 < len(key_output) <= 512
                or type(body_output) is not bytearray or len(body_output) > self._bound
                or key_output is body_output):
            raise ValueError('Original lookup scan bounds are invalid')
        body = (c_ubyte * len(body_output)).from_buffer(body_output)
        key = (c_ubyte * len(key_output)).from_buffer(key_output)
        key_size = c_int64(-1)
        fact, size = self._managed(25, lambda r: self._calls.calls['scan_utf16_into'](
            self._database._host, self._lookup, s, sn, k, kn, len(body_output), r),
            output=body, capacity=len(body_output), key_output=(key, len(key_output), key_size))
        if size is None:
            raise self._mark_unknown()
        return fact, key_size.value, size

    def _key_fact(self, operation: int, name: str, scope: str, key: str) -> _OriginalDatabaseFact:
        s, sn = _text(scope); k, kn = _text(key)
        fact, _ = self._managed(operation, lambda r: self._calls.calls[name](
            self._database._host, self._lookup, s, sn, k, kn, r))
        return fact

    def read_header(self, scope: str, key: str) -> _OriginalDatabaseFact:
        return self._key_fact(26, 'header_utf16_into', scope, key)

    def read_capacity(self, scope: str, key: str) -> _OriginalDatabaseFact:
        return self._key_fact(27, 'capacity_utf16_into', scope, key)

    def capacity_usage(self, scope: str) -> _OriginalDatabaseFact:
        s, sn = _text(scope)
        fact, _ = self._managed(28, lambda r: self._calls.calls['capacity_usage_utf16_into'](
            self._database._host, self._lookup, s, sn, r))
        return fact

    def database_usage(self) -> _OriginalDatabaseFact:
        fact, _ = self._managed(29, lambda r: self._calls.calls['database_usage_into'](
            self._database._host, self._lookup, r))
        return fact

    def finish(self) -> _OriginalDatabaseFact:
        fact, _ = self._managed(30, lambda r: self._calls.calls['finish_into'](
            self._database._host, self._lookup, r))
        owner = self._database._library._domain._owner
        owner._enter()
        try:
            self._local(cleanup=True)
            self._release_after_ack()
        finally:
            owner._busy = False
        return fact

    def _release_after_ack(self) -> None:
        if self._cleanup_ack is None or self._reply.value is not None:
            raise self._mark_unknown()
        try:
            code = self._calls.calls['drop'](byref(self._lookup))
            if type(code) is not int or code != 0 or self._lookup.value is not None:
                raise RuntimeError('Original lookup alias retirement is unconfirmed')
        except BaseException as error:
            if self._response_unknown is None:
                self._unknown_carrier.operation = self._last_operation
            self._retirement_unknown = self._unknown_carrier
            raise self._retirement_unknown from error
        self._closed = True
        self._database._lookup_original = None

    def close(self) -> None:
        if self._closed:
            self._database._parent_current()
            return
        self._local(cleanup=True)
        database = self._database
        # Refuse known reentry before inspecting transient out-slots or
        # recording Unknown. Domain scope entry has its own same Owner guard.
        owner = database._library._domain._owner
        owner._enter()
        try:
            self._local(cleanup=True)
        finally:
            owner._busy = False
        # Drain a published SAME response under the existing cleanup scope;
        # never repeat its original start/read/finish operation.
        if self._reply.value is not None:
            with database._library._domain._read_scope(database._read, cleanup=True):
                owner = database._library._domain._owner
                owner._enter()
                try:
                    self._local(cleanup=True)
                    fact = self._fact(self._last_operation)
                    if fact.operation == 31 and fact.stage == 3 and not fact.issue_family and not fact.after_issue_family:
                        self._cleanup_ack = fact
                    self._drop_reply()
                finally:
                    owner._busy = False
        if self._lookup.value is None:
            # Absence after an unconfirmed start/drop is not a physical ACK.
            raise self._mark_unknown()
        owner = database._library._domain._owner
        owner._enter()
        known: _OriginalLookupError | None = None
        try:
            self._local(cleanup=True)
            if self._cleanup_ack is None:
                self._last_operation = 31
                try:
                    self._status(self._calls.calls['close_into'](
                        database._host, self._lookup, byref(self._reply)))
                    fact = self._fact(31)
                    if fact.issue_family or fact.after_issue_family:
                        self._drop_reply()
                        known = _OriginalLookupError(self, unknown=False, operation=31, fact=fact)
                        raise known
                    if fact.stage != 3:
                        raise self._mark_unknown()
                    self._cleanup_ack = fact
                    self._drop_reply()
                except BaseException as error:
                    if error is known or error is self._retirement_unknown or error is self._response_unknown:
                        raise
                    raise self._mark_unknown() from error
            self._release_after_ack()
        finally:
            owner._busy = False
