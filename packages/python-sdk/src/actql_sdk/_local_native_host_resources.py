"""Original Native Host pair custody; no Python funding or phase authority."""
from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from ctypes import byref, c_void_p
from dataclasses import dataclass
from typing import Any, Literal, NoReturn

from ._local_native_control_custody import _OriginalControlCustody
from ._local_native_domain_custody import _OriginalDomainCustody
from ._local_native_original_read import _OriginalParentReadCustody
from ._local_native_shim_abi import bind as bind_native
from ._local_native_sqlite import _OriginalSqliteCustody

_RETIRED_HOST_RESOURCES_DATA = object()
_Phase = Literal['read', 'sqlite']


@dataclass(frozen=True, slots=True)
class _OriginalHostResourcesFact:
    operation: int
    issue_origin: int
    issue_family: int


class _OriginalHostResourcesError(RuntimeError):
    def __init__(self, original: _OriginalHostResourcesCustody, *, unknown: bool,
                 fact: _OriginalHostResourcesFact | None = None) -> None:
        self.cleanup_resources, self.unknown, self.fact = original, unknown, fact
        super().__init__('Original Host resources outcome is unconfirmed' if unknown
                         else 'Original Host resources operation was refused')


class _OriginalHostResourcesFunctions:
    def __init__(self, library: Any) -> None:
        self.library = library
        self.bind = bind_native(library, 'actql_host_resources_bind_into')
        self.operate = bind_native(library, 'actql_host_resources_operate_into')
        self.claim_read = bind_native(library, 'actql_host_resources_claim_read_into')
        self.originals = bind_native(library, 'actql_host_resources_originals_into')
        self.operation = bind_native(library, 'actql_host_resources_operation')
        self.origin = bind_native(library, 'actql_host_resources_issue_origin')
        self.family = bind_native(library, 'actql_host_resources_issue_family')
        self.closed = bind_native(library, 'actql_host_resources_close_confirmed')
        self.drop = bind_native(library, 'actql_host_resources_drop_reply')
        self.finish = bind_native(library, 'actql_host_resources_finish_closed_data')
        self.refused = bind_native(library, 'actql_host_resources_finish_refused_bind_data')


class _OriginalHostResourcesCustody:
    """Persistent original slots, including partial calls and lost replies.

    Native alone selects phases and confirms retirement. The local phase and
    closed fields project acknowledged calls; they cannot issue capacity,
    return a domain/FD, recover Unknown or recreate an original.
    """
    __slots__ = ('_owner', '_read', '_sqlite', '_functions', '_host', '_sqlite_host',
                 '_native_read', '_native_sqlite', '_original', '_reply', '_unknown',
                 '_unknown_carrier', '_phase', '_bound', '_closed')
    _owner: _OriginalControlCustody
    _read: _OriginalParentReadCustody
    _sqlite: _OriginalSqliteCustody
    _functions: _OriginalHostResourcesFunctions
    _host: c_void_p
    _sqlite_host: c_void_p
    _native_read: c_void_p
    _native_sqlite: c_void_p
    _original: c_void_p
    _reply: c_void_p
    _unknown: _OriginalHostResourcesError | None
    _unknown_carrier: _OriginalHostResourcesError
    _phase: _Phase | None
    _bound: bool
    _closed: bool

    @classmethod
    def _bind_original(cls, read: _OriginalParentReadCustody,
                       sqlite: _OriginalSqliteCustody,
                       functions: _OriginalHostResourcesFunctions) -> _OriginalHostResourcesCustody:
        if (cls is not _OriginalHostResourcesCustody
                or type(read) is not _OriginalParentReadCustody
                or type(sqlite) is not _OriginalSqliteCustody
                or type(functions) is not _OriginalHostResourcesFunctions
                or read._domain._owner is not sqlite._domain._owner
                or read._domain is sqlite._domain
                or functions.library is not read._functions.library
                or functions.library is not sqlite._functions.library):
            raise ValueError('Original Host resource inputs are unavailable')
        owner = read._domain._owner
        original = cls.__new__(cls)
        original._owner, original._read, original._sqlite = owner, read, sqlite
        original._functions = functions
        original._host, original._sqlite_host = c_void_p(), c_void_p()
        original._native_read, original._native_sqlite = c_void_p(), c_void_p()
        original._original, original._reply = c_void_p(), c_void_p()
        original._unknown, original._phase = None, None
        original._closed, original._bound = False, False
        original._unknown_carrier = _OriginalHostResourcesError(original, unknown=True)
        outputs = tuple(byref(slot) for slot in original._slots())
        # Known entry refusal is outside the uncertain foreign-call boundary.
        owner._enter()
        known: _OriginalHostResourcesError | None = None
        try:
            for parent in (read, sqlite, read._domain, sqlite._domain):
                if parent._unknown is not None:
                    raise parent._unknown
                if parent._closed:
                    raise ValueError('Original Host resource input is retired')
            if (owner._closed or owner._original.value is None or read._scope_open
                    or read._domain._parent_read_original is not read
                    or sqlite._domain._sqlite_library_original is not sqlite
                    or read._host.value != owner._original.value
                    or sqlite._host.value != owner._original.value
                    or getattr(owner, '_host_resources_original', None) is not None):
                raise ValueError('Original Host resources are unavailable')
            # Register before any FFI output can become visible or be lost.
            owner._host_resources_original = original
            try:
                original._status(functions.bind(owner._original, read._original,
                    sqlite._original, outputs[-1]))
                original._status(functions.originals(original._reply, *outputs[:-1]))
                if (original._host.value != owner._original.value
                        or original._sqlite_host.value != owner._original.value
                        or original._native_read.value != read._original.value
                        or original._native_sqlite.value != sqlite._original.value):
                    raise original._mark_unknown()
                original._bound = original._original.value is not None
                fact = original._fact(1)
                if fact.issue_origin:
                    known = original._issue(fact)
                    if known.unknown or original._bound:
                        raise original._mark_unknown()
                    original._status(functions.refused(*outputs))
                    original._ack_data_retired()
                    # The failed selected binding still fences new work on
                    # these inputs until their separate original cleanup ACKs.
                    raise known
                if not original._bound:
                    raise original._mark_unknown()
                original._drop()
            except BaseException as error:
                if error is known or error is original._unknown:
                    raise
                raise original._mark_unknown() from error
        finally:
            owner._busy = False
        return original

    def _slots(self) -> tuple[c_void_p, ...]:
        return (self._host, self._sqlite_host, self._native_read,
                self._native_sqlite, self._original, self._reply)

    def __copy__(self) -> NoReturn:
        raise TypeError('Original Host resources cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original Host resources cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Host resources cannot be serialized')

    def _mark_unknown(self) -> _OriginalHostResourcesError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _issue(self, fact: _OriginalHostResourcesFact) -> _OriginalHostResourcesError:
        if fact.issue_origin == 2 and fact.issue_family == 9:
            self._unknown_carrier.fact = fact
            return self._mark_unknown()
        return _OriginalHostResourcesError(self, unknown=False, fact=fact)

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _fact(self, operation: int) -> _OriginalHostResourcesFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        values = (self._functions.operation(self._reply), self._functions.origin(self._reply),
                  self._functions.family(self._reply), self._functions.closed(self._reply))
        tag, origin, family, closed = values
        if (any(type(value) is not int for value in values) or tag != operation
                or not 0 <= origin <= 3 or not 0 <= family <= 20
                or (origin == 0) != (family == 0) or closed not in (0, 1)
                or closed != int(operation == 8 and origin == 0)):
            raise self._mark_unknown()
        return _OriginalHostResourcesFact(tag, origin, family)

    def _drop(self) -> None:
        self._status(self._functions.drop(byref(self._reply), *self._slots()[:-1]))
        if self._reply.value is not None:
            raise self._mark_unknown()

    def _ack_data_retired(self) -> None:
        if any(slot.value is not None for slot in self._slots()):
            raise self._mark_unknown()
        self._closed = True

    def _refused_bind_data_retired(self) -> bool:
        return self._closed and not self._bound and self._unknown is None

    def _call(self, operation: int, *, claim_quote: tuple[int, int] | None = None
              ) -> _OriginalHostResourcesFact:
        if self._unknown is not None:
            raise self._unknown
        if (self._closed or self._original.value is None
                or self._owner._host_resources_original is not self):
            raise ValueError('Original Host resources are retired')
        for parent in (self._read, self._sqlite, self._read._domain, self._sqlite._domain):
            if parent._unknown is not None:
                raise parent._unknown
        if operation in (3, 4, 6, 7, 9):
            from ._local_native_adoption import _require_adoption_retired
            _require_adoption_retired(self._read)
        if ((operation == 9) != (claim_quote is not None)
                or (claim_quote is not None
                    and (type(claim_quote) is not tuple or len(claim_quote) != 2
                         or any(type(value) is not int or not -(1 << 63) <= value < (1 << 63)
                                for value in claim_quote)
                         or self._phase is not None))):
            raise ValueError('Original read claim transport is unavailable')
        out = byref(self._reply)
        outputs = tuple(byref(slot) for slot in self._slots())
        known: _OriginalHostResourcesError | None = None
        self._owner._enter()
        try:
            try:
                self._drop()
                if claim_quote is None:
                    self._status(self._functions.operate(self._host, self._original, operation, out))
                else:
                    self._status(self._functions.claim_read(self._host, self._original,
                        claim_quote[0], claim_quote[1], out))
                fact = self._fact(operation)
                if fact.issue_origin:
                    known = self._issue(fact)
                    if known.unknown:
                        raise known
                    self._drop()
                    raise known
                if operation in (3, 4, 6, 7):
                    self._phase = 'read' if operation in (3, 6) else 'sqlite'
                    if self._phase == 'read':
                        self._read._scope_open = True
                elif operation == 5:
                    if self._phase == 'read':
                        self._read._scope_open = False
                    self._phase = None
                if operation == 8:
                    if self._phase is not None:
                        raise self._mark_unknown()
                    self._status(self._functions.finish(*outputs))
                    self._ack_data_retired()
                else:
                    self._drop()
                return fact
            except BaseException as error:
                if error is known or error is self._unknown:
                    raise
                raise self._mark_unknown() from error
        finally:
            self._owner._busy = False

    def current(self) -> _OriginalHostResourcesFact:
        return self._call(2)

    def claim_read(self, retained_bytes: int, execution_bytes: int) -> _OriginalHostResourcesFact:
        """Forward the complete original quote before any consuming phase.

        Native owns issuance/current and keeps the consumer in this same pair.
        This projection creates no Python permit or replacement read handle.
        """
        return self._call(9, claim_quote=(retained_bytes, execution_bytes))

    def leave_scope(self) -> None:
        if self._phase is None:
            raise ValueError('Original Host phase is unavailable')
        self._call(5)

    @contextmanager
    def scope(self, phase: _Phase, *, cleanup: bool = False) -> Iterator[None]:
        if (type(phase) is not str or phase not in ('read', 'sqlite')
                or type(cleanup) is not bool or self._phase is not None):
            raise ValueError('Original Host phase is unavailable')
        self._call((6 if phase == 'read' else 7) if cleanup else (3 if phase == 'read' else 4))
        try:
            yield
        except BaseException as primary:
            try:
                self.leave_scope()
            except BaseException as leave_failure:
                raise leave_failure from primary
            raise
        else:
            self.leave_scope()

    def close(self) -> None:
        if self._unknown is not None:
            raise self._unknown
        if not self._closed:
            from ._local_native_read_crypto import _require_read_crypto_retired
            _require_read_crypto_retired(self._read)
            from ._local_native_adoption import _require_adoption_retired
            _require_adoption_retired(self._read)
            # Foreign-response uncertainty or pending metadata belongs to those
            # same child wrappers even if a physical close may have completed.
            from ._local_native_sqlite_database import _RETIRED_DATABASE_DATA
            from ._local_native_original_read import _RETIRED_PARENT_RUNTIME_DATA
            for child, retired in ((self._sqlite._database_original, _RETIRED_DATABASE_DATA),
                                   (self._read._runtime_original, _RETIRED_PARENT_RUNTIME_DATA)):
                if child is not None and child is not retired:
                    error = getattr(child, '_unknown', None)
                    if error is not None:
                        raise error
                    raise ValueError('Original Host child cleanup or data remains pending')
            self._call(8)
        else:
            self._owner._enter()
            self._owner._busy = False
        if self._bound:
            # Reobserve those same Native closed originals to retire their
            # separately owned Python transport data. Native's already-closed
            # paths perform no second Library/context physical close.
            self._sqlite.close()
            self._read.close()
        _retire_host_resources_registration(self._owner)


def _retire_host_resources_registration(owner: _OriginalControlCustody) -> None:
    original = owner._host_resources_original
    if (type(original) is _OriginalHostResourcesCustody
            and original._closed and original._unknown is None
            and original._read._closed and original._sqlite._closed):
        # Pair DATA retirement alone does not retire either input. Break this
        # reverse registration only after both original parent DATA ACKs.
        owner._host_resources_original = _RETIRED_HOST_RESOURCES_DATA


def _resources_for_domain(domain: _OriginalDomainCustody) -> tuple[_OriginalHostResourcesCustody, _Phase] | None:
    original = getattr(domain._owner, '_host_resources_original', None)
    if type(original) is _OriginalHostResourcesCustody:
        if original._read._domain is domain:
            return original, 'read'
        if original._sqlite._domain is domain:
            return original, 'sqlite'
    return None
