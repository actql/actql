"""Same original Native Database transport; SQL/CAS/fencing stay in Core.

No Run admission, SQL executor, funding supplier, permission or recovery FSM.
The installed Host binds its original Store/adoption/intent before acquisition.
"""
from __future__ import annotations

from ctypes import (POINTER, byref, c_char_p, c_int, c_int32, c_int64,
                    c_uint16, c_uint64, c_ubyte, c_void_p, cast)
from dataclasses import dataclass
from typing import Any, Callable, NoReturn

from ._local_native_domain_custody import _OriginalDomainReadFunctions
from ._local_native_sqlite import _OriginalSqliteCustody

_RETIRED_DATABASE_DATA = object()


@dataclass(frozen=True, slots=True)
class _OriginalDatabaseFact:
    """Physical callback observation only; never a Store/Run durable ACK."""
    operation: int
    stage: int
    issue_family: int
    after_issue_family: int
    has_row: bool
    revision: int | None
    body_bound: int


class _OriginalDatabaseError(RuntimeError):
    def __init__(self, original: _OriginalDatabaseCustody, *, unknown: bool,
                 operation: int, fact: _OriginalDatabaseFact | None = None) -> None:
        self.cleanup_database = original
        self.unknown, self.operation, self.fact = unknown, operation, fact
        super().__init__('Original Native Database outcome is unconfirmed' if unknown
                         else 'Original Native Database operation was refused')


class _OriginalDatabaseFunctions:
    """Mandatory exports in the already selected same provider; no loader."""
    def __init__(self, library: Any) -> None:
        self.library = library
        p, pp = c_void_p, POINTER(c_void_p)
        text, blob = POINTER(c_uint16), POINTER(c_ubyte)
        signatures: dict[str, tuple[list[Any], Any]] = {
            'restore_utf16_into': ([p, p, text, c_int32, c_int64, pp], c_int),
            'initialize_utf16_into': ([p, p, text, c_int32, c_int64, c_uint64, c_uint64, pp], c_int),
            'observe_into': ([p, p, pp], c_int),
            'fence_into': ([p, p, pp], c_int),
            'close_into': ([p, p, pp], c_int),
            'read_utf16_into': ([p, p, text, c_int32, text, c_int32, c_int64, pp], c_int),
            'scan_utf16_into': ([p, p, text, c_int32, text, c_int32, c_int64, pp], c_int),
            'insert_utf16_into': ([p, p, text, c_int32, text, c_int32, blob, c_int64, pp], c_int),
            'compare_utf16_into': ([p, p, text, c_int32, text, c_int32, c_int64, blob, c_int64, pp], c_int),
            'transaction_into': ([p, p, c_int32, pp], c_int),
            'originals_into': ([p, pp, pp, pp], c_int),
            'drop_reply': ([pp, p, p, p], c_int),
            'finish_closed_data': ([pp, pp, pp, pp], c_int),
            'finish_refused_open': ([pp, pp, pp], c_int),
            'copy_row': ([p, p, p, p, blob, c_int64, POINTER(c_int64)], c_int),
            'copy_key': ([p, p, p, p, blob, c_int64, POINTER(c_int64)], c_int),
            **{name: ([p], c_int32) for name in
               ('operation', 'stage', 'issue_family', 'after_issue_family', 'has_row')},
            'revision': ([p], c_int64), 'body_bound': ([p], c_int64),
        }
        self.calls: dict[str, Any] = {}
        for name, (args, result) in signatures.items():
            call = getattr(library, 'actql_sqlite_database_' + name)
            call.argtypes, call.restype = args, result
            self.calls[name] = call


def _text(value: str, *, path: bool = False, cursor: bool = False) -> tuple[Any, int]:
    if (type(value) is not str or not cursor and (not value or '\0' in value)
            or (path and not value.startswith('/'))):
        raise ValueError('Original Native Database text is invalid')
    bound = 4096 if path else 512
    encoded = value.encode('utf-16-le')
    if len(encoded) // 2 > bound or not path and len(value.encode('utf-8')) > bound:
        raise ValueError('Original Native Database text exceeds its ABI bound')
    return (c_uint16 * (len(encoded) // 2)).from_buffer_copy(encoded), len(encoded) // 2


class _OriginalDatabaseCustody:
    """One original Database and partial carrier under its original Library.

    Known entry refusal happens before registration/foreign catch. Unknown
    data acquisition/drop/close keeps all slots and parent custody. A published
    but lost SQL reply instead retains that same operation: writes stay refused;
    explicit reconciliation can drain only its original reply, fence the SAME
    Core Database, and query committed rows. No original SQL is sent again.
    """
    __slots__ = ('_library', '_functions', '_read', '_host', '_native_library',
                 '_original', '_reply', '_bound', '_unknown', '_unknown_carrier',
                 '_write_unknown', '_fenced_unknown', '_closed')
    _library: _OriginalSqliteCustody
    _functions: _OriginalDatabaseFunctions
    _read: _OriginalDomainReadFunctions
    _host: c_void_p
    _native_library: c_void_p
    _original: c_void_p
    _reply: c_void_p
    _bound: int
    _unknown: _OriginalDatabaseError | None
    _unknown_carrier: _OriginalDatabaseError
    _write_unknown: _OriginalDatabaseError | None
    _fenced_unknown: bool
    _closed: bool

    @classmethod
    def _open_original(cls, library: _OriginalSqliteCustody,
                       functions: _OriginalDatabaseFunctions,
                       read: _OriginalDomainReadFunctions, *, path: str,
                       max_body_bytes: int, ownership: tuple[int, int] | None = None
                       ) -> _OriginalDatabaseCustody:
        """Trusted Host original-intent caller only; ownership DATA grants none."""
        if (type(library) is not _OriginalSqliteCustody
                or type(functions) is not _OriginalDatabaseFunctions
                or type(read) is not _OriginalDomainReadFunctions
                or functions.library is not library._functions.library
                or read.library is not functions.library
                or type(max_body_bytes) is not int or not 0 < max_body_bytes <= 2**31 - 1
                or ownership is not None and (type(ownership) is not tuple
                    or len(ownership) != 2 or any(type(n) is not int or not 0 <= n <= 2**64 - 1
                                                for n in ownership))):
            raise ValueError('Original Native Database selection is unavailable')
        text, units = _text(path, path=True)
        original = cls.__new__(cls)
        original._library, original._functions, original._read = library, functions, read
        original._host, original._native_library = c_void_p(), c_void_p()
        original._original, original._reply = c_void_p(), c_void_p()
        original._bound, original._closed = max_body_bytes, False
        original._unknown = None
        original._unknown_carrier = _OriginalDatabaseError(original, unknown=True, operation=0)
        original._write_unknown, original._fenced_unknown = None, False
        out = byref(original._reply)
        originals = (byref(original._host), byref(original._native_library), byref(original._original))
        known: _OriginalDatabaseError | None = None
        owner = library._domain._owner
        owner._enter()
        try:
            original._parent_current()
            if library._database_original is not None:
                raise ValueError('Original Native Database was already selected')
            library._database_original = original
            try:
                if ownership is None:
                    operation = 1
                    code = functions.calls['restore_utf16_into'](library._host, library._original,
                        text, units, max_body_bytes, out)
                else:
                    operation = 2
                    code = functions.calls['initialize_utf16_into'](library._host, library._original,
                        text, units, max_body_bytes, *ownership, out)
                original._status(code)
                original._status(functions.calls['originals_into'](original._reply, *originals))
                if (original._host.value != library._host.value
                        or original._native_library.value != library._original.value):
                    raise original._mark_unknown()
                fact = original._fact(operation)
                if original._original.value is None:
                    if fact.stage != 0 or fact.issue_family == 0:
                        raise original._mark_unknown()
                    original._status(functions.calls['finish_refused_open'](
                        byref(original._host), byref(original._native_library), byref(original._reply)))
                    original._finish_data_ack()
                else:
                    if fact.stage != 1 or fact.body_bound != max_body_bytes:
                        raise original._mark_unknown()
                    original._drop()
                if fact.issue_family or fact.after_issue_family:
                    known = _OriginalDatabaseError(original, unknown=False, operation=operation, fact=fact)
                    raise known
            except BaseException as error:
                if error is known or error is original._unknown:
                    raise
                raise original._mark_unknown() from error
        finally:
            owner._busy = False
        return original

    def __copy__(self) -> _OriginalDatabaseCustody:
        raise TypeError('Original Native Database custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalDatabaseCustody:
        raise TypeError('Original Native Database custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Native Database custody cannot be serialized')

    def _parent_current(self) -> None:
        library = self._library
        if library._unknown is not None:
            raise library._unknown
        if (library._closed or library._original.value is None or library._domain._closed
                or library._domain._sqlite_library_original is not library):
            raise ValueError('Original Native Database parent is retired')

    def _local(self, *, allow_unconfirmed: bool = False) -> None:
        if self._unknown is not None:
            raise self._unknown
        self._parent_current()
        if self._closed or self._original.value is None or self._library._database_original is not self:
            raise ValueError('Original Native Database is retired')
        if self._write_unknown is not None and not allow_unconfirmed:
            raise self._write_unknown

    def _mark_unknown(self) -> _OriginalDatabaseError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _fact(self, operation: int, *, preflight: bool = False) -> _OriginalDatabaseFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        values = [self._functions.calls[name](self._reply) for name in
                  ('operation', 'stage', 'issue_family', 'after_issue_family', 'has_row', 'revision', 'body_bound')]
        if (any(type(n) is not int for n in values) or not 0 <= values[1] <= 3
                or not 0 <= values[2] <= 20 or not 0 <= values[3] <= 20
                or values[4] not in (0, 1) or not -1 <= values[5] <= 2**63 - 1
                or not -1 <= values[6] <= 2**31 - 1):
            raise self._mark_unknown()
        actual, stage, issue, after, present, revision, bound = values
        if actual != operation:
            if not (preflight and actual == 3 and (issue or after) and stage in (0, 2)):
                raise self._mark_unknown()
        if self._original.value is not None and bound != self._bound:
            raise self._mark_unknown()
        if present and (actual not in (4, 12) or stage != 2 or issue != 0 or revision < 0):
            raise self._mark_unknown()
        return _OriginalDatabaseFact(actual, stage, issue, after, bool(present),
                                     None if revision == -1 else revision, bound)

    def _drop(self) -> None:
        if self._reply.value is not None:
            self._status(self._functions.calls['drop_reply'](byref(self._reply), self._host,
                                                           self._native_library, self._original))
            if self._reply.value is not None:
                raise self._mark_unknown()

    def _finish_data_ack(self) -> None:
        if any(slot.value is not None for slot in
               (self._host, self._native_library, self._original, self._reply)):
            raise self._mark_unknown()
        self._closed = True
        self._library._database_original = _RETIRED_DATABASE_DATA

    def _drain_original_response(self) -> None:
        if self._reply.value is None:
            return
        if self._write_unknown is None:
            raise self._mark_unknown()
        self._fact(self._write_unknown.operation, preflight=True)
        self._drop()

    def _managed(self, operation: int, call: Callable[[Any], Any], *,
                 output: Any = None, capacity: int = 0, allow_unconfirmed: bool = False,
                 key_output: tuple[Any, int, c_int64, Any] | None = None
                 ) -> tuple[_OriginalDatabaseFact, int | None]:
        self._local(allow_unconfirmed=allow_unconfirmed)
        reply_out, size = byref(self._reply), c_int64(-1)
        size_out = byref(size)
        # Entry refusals are local Owner results and remain outside the foreign
        # catch. The same read context also brackets every managed input/row.
        with self._library._domain._read_scope(self._read):
            owner = self._library._domain._owner
            owner._enter()
            try:
                self._local(allow_unconfirmed=allow_unconfirmed)
            except BaseException:
                owner._busy = False
                raise
            known: _OriginalDatabaseError | None = None
            try:
                if self._reply.value is not None:
                    raise self._mark_unknown()
                try:
                    code = call(reply_out)
                except BaseException as error:
                    if operation in (5, 6, 7, 8, 9) and self._reply.value is not None:
                        # Preserve a published SAME original reply. Reconciliation
                        # may inspect/drop it and fence Core; never resend SQL.
                        self._write_unknown = _OriginalDatabaseError(self, unknown=True, operation=operation)
                        raise self._write_unknown from error
                    raise
                self._status(code)
                fact = self._fact(operation, preflight=operation in (4, 5, 6, 12))
                length: int | None = None
                if not fact.issue_family and not fact.after_issue_family and fact.has_row:
                    self._status(self._functions.calls['copy_row'](self._reply, self._host,
                        self._native_library, self._original, output, capacity, size_out))
                    if not 0 <= size.value <= min(capacity, self._bound):
                        raise self._mark_unknown()
                    length = size.value
                    if key_output is not None:
                        key_buffer, key_capacity, key_size, key_size_out = key_output
                        self._status(self._functions.calls['copy_key'](self._reply, self._host,
                            self._native_library, self._original, key_buffer, key_capacity, key_size_out))
                        if not 0 < key_size.value <= min(key_capacity, 512):
                            raise self._mark_unknown()
                self._drop()
                if fact.issue_family or fact.after_issue_family:
                    known = _OriginalDatabaseError(self, unknown=False, operation=operation, fact=fact)
                    raise known
                if fact.stage != 2:
                    raise self._mark_unknown()
                return fact, length
            except BaseException as error:
                if error is known or error is self._unknown or error is self._write_unknown:
                    raise
                raise self._mark_unknown() from error
            finally:
                owner._busy = False

    def read_into(self, scope: str, key: str, output: bytearray) -> tuple[_OriginalDatabaseFact, int | None]:
        """Copy into caller's already-owned bounded buffer; retain no view."""
        return self._read_into(scope, key, output, unconfirmed=False)

    def _read_into(self, scope: str, key: str, output: bytearray, *, unconfirmed: bool
                   ) -> tuple[_OriginalDatabaseFact, int | None]:
        s, sn = _text(scope); k, kn = _text(key)
        if type(output) is not bytearray or not 0 < len(output) <= self._bound:
            raise ValueError('Original Native Database output bound is invalid')
        buffer = (c_ubyte * len(output)).from_buffer(output)
        return self._managed(4, lambda r: self._functions.calls['read_utf16_into'](
            self._host, self._original, s, sn, k, kn, len(output), r),
            output=buffer, capacity=len(output), allow_unconfirmed=unconfirmed)

    def scan_after_into(self, scope: str, after_key: str, key_output: bytearray,
                        body_output: bytearray) -> tuple[_OriginalDatabaseFact, int, int]:
        """One original bounded row; exact UTF-8 key into caller-owned storage.

        Empty cursor starts the existing SQLite order. NotFound remains that
        query's typed refusal, never a complete namespace or inventory proof.
        No cursor advancement, skipped large rows, or retained output alias.
        """
        s, sn = _text(scope); k, kn = _text(after_key, cursor=True)
        if (type(key_output) is not bytearray or not 0 < len(key_output) <= 512
                or type(body_output) is not bytearray or len(body_output) > self._bound
                or key_output is body_output):
            raise ValueError('Original Native Database scan output bounds are invalid')
        body = (c_ubyte * len(body_output)).from_buffer(body_output)
        key = (c_ubyte * len(key_output)).from_buffer(key_output)
        size = c_int64(-1)
        fact, length = self._managed(12, lambda r: self._functions.calls['scan_utf16_into'](
            self._host, self._original, s, sn, k, kn, len(body_output), r),
            output=body, capacity=len(body_output), key_output=(key, len(key_output), size, byref(size)))
        if length is None:
            raise self._mark_unknown()
        return fact, size.value, length

    def _write(self, operation: int, scope: str, key: str, body: bytes,
               expected: int | None = None) -> _OriginalDatabaseFact:
        s, sn = _text(scope); k, kn = _text(key)
        if (type(body) is not bytes or len(body) > self._bound or
                expected is not None and (type(expected) is not int or not 0 <= expected < 2**63 - 1)):
            raise ValueError('Original Native Database write input is invalid')
        # Borrow the same immutable Python bytes for the synchronous C call;
        # Native copies only inside its original managed scope.
        original_bytes = c_char_p(body)
        buffer = cast(original_bytes, POINTER(c_ubyte))
        invoke: Callable[[Any], Any]
        if operation == 5:
            invoke = lambda r: self._functions.calls['insert_utf16_into'](
                self._host, self._original, s, sn, k, kn, buffer, len(body), r)
        else:
            invoke = lambda r: self._functions.calls['compare_utf16_into'](
                self._host, self._original, s, sn, k, kn, expected, buffer, len(body), r)
        fact, _ = self._managed(operation, invoke)
        if fact.revision is None:
            raise self._mark_unknown()
        return fact

    def insert(self, scope: str, key: str, body: bytes) -> _OriginalDatabaseFact:
        return self._write(5, scope, key, body)

    def compare_exchange(self, scope: str, key: str, expected: int, body: bytes) -> _OriginalDatabaseFact:
        return self._write(6, scope, key, body, expected)

    def transaction(self, operation: int) -> _OriginalDatabaseFact:
        if type(operation) is not int or operation not in (7, 8, 9):
            raise ValueError('Original Native Database transaction selector is invalid')
        fact, _ = self._managed(operation, lambda r: self._functions.calls['transaction_into'](
            self._host, self._original, operation, r))
        return fact

    def lookup_unconfirmed_into(self, scope: str, key: str, output: bytearray
                                ) -> tuple[_OriginalDatabaseFact, int | None]:
        """Same original SQL response-loss reconciliation only; no write retry.

        Keep the original Unknown forever for mutating calls. Core's monotonic
        physical fence and actual autocommit observation decide whether this
        SAME connection can expose committed rows; this issues no COMMIT ACK.
        """
        self._local(allow_unconfirmed=True)
        if self._write_unknown is None:
            raise ValueError('No original Native Database SQL response is unconfirmed')
        # Invalid lookup DATA must not consume even a physical fence call.
        _text(scope)
        _text(key)
        if type(output) is not bytearray or not 0 < len(output) <= self._bound:
            raise ValueError('Original Native Database output bound is invalid')
        if not self._fenced_unknown:
            with self._library._domain._read_scope(self._read):
                owner = self._library._domain._owner
                owner._enter()
                known: _OriginalDatabaseError | None = None
                try:
                    self._drain_original_response()
                    self._status(self._functions.calls['fence_into'](self._host, self._original, byref(self._reply)))
                    fact = self._fact(11)
                    self._drop()
                    if fact.issue_family or fact.after_issue_family:
                        known = _OriginalDatabaseError(self, unknown=False, operation=11, fact=fact)
                        raise known
                    if fact.stage != 2:
                        raise self._mark_unknown()
                    self._fenced_unknown = True
                except BaseException as error:
                    if error is known or error is self._unknown:
                        raise
                    raise self._mark_unknown() from error
                finally:
                    owner._busy = False
        return self._read_into(scope, key, output, unconfirmed=True)

    def close(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        owner = self._library._domain._owner
        reply_out = byref(self._reply)
        owner._enter()
        known: _OriginalDatabaseError | None = None
        try:
            if self._closed:
                return
            self._local(allow_unconfirmed=True)
            try:
                self._drain_original_response()
                self._status(self._functions.calls['close_into'](self._host, self._original, reply_out))
                fact = self._fact(10)
                if fact.issue_family or fact.after_issue_family:
                    self._drop()
                    known = _OriginalDatabaseError(self, unknown=False, operation=10, fact=fact)
                    raise known
                if fact.stage != 3:
                    raise self._mark_unknown()
                self._status(self._functions.calls['finish_closed_data'](byref(self._host),
                    byref(self._native_library), byref(self._original), byref(self._reply)))
                self._finish_data_ack()
            except BaseException as error:
                if error is known or error is self._unknown:
                    raise
                raise self._mark_unknown() from error
        finally:
            owner._busy = False
