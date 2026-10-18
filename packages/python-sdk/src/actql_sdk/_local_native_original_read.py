"""Same original Native parent-read transport; no Python grant or Ledger.

The private installed caller supplies a reviewed declaration and its original
domain. Missing ordinary profile/funding is not filled by these integers.
Native keeps the joined claim/loan, scoped aliases and final retirement.
"""
from __future__ import annotations

from ._local_native_shim_abi import bind as bind_native

from collections.abc import Iterator
from contextlib import contextmanager
from ctypes import POINTER, byref, c_int, c_int32, c_int64, c_void_p
from typing import Any, NoReturn

from ._local_native_control_custody import _OriginalArenaFact
from ._local_native_domain_custody import _OriginalDomainCustody

_RETIRED_PARENT_READ_DATA = object()
_RETIRED_PARENT_RUNTIME_DATA = object()


class _OriginalParentReadError(RuntimeError):
    def __init__(self, original: _OriginalParentReadCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_read, self.unknown, self.fact = original, unknown, fact
        super().__init__('Original parent read outcome is unconfirmed' if unknown
                         else 'Original parent read operation was refused')


class _OriginalParentReadFunctions:
    """Mandatory matching symbols in the same selected physical component."""
    def __init__(self, library: Any) -> None:
        self.library = library
        self.prepare = bind_native(library, 'actql_parent_read_prepare_into')
        self.current = bind_native(library, 'actql_parent_read_current_into')
        self.enter = bind_native(library, 'actql_parent_read_enter_into')
        self.leave = bind_native(library, 'actql_parent_read_leave_into')
        self.cleanup = bind_native(library, 'actql_parent_read_cleanup_into')
        self.close = bind_native(library, 'actql_parent_read_close_into')
        self.originals = bind_native(library, 'actql_parent_read_originals_into')
        self.drop = bind_native(library, 'actql_parent_read_drop_reply')
        self.finish = bind_native(library, 'actql_parent_read_finish_closed_data')
        self.refused = bind_native(library, 'actql_parent_read_finish_refused_prepare')
        self.operation = bind_native(library, 'actql_parent_read_operation')
        self.issue = bind_native(library, 'actql_parent_read_issue_family')


class _OriginalParentReadCustody:
    """Persistent slots for one Native-issued joined carrier, including failure.

    Response loss never starts another attempt, leaves/closes twice, or invents
    retirement. Known pending cleanup returns to this same original Owner.
    Scope flags remember only acknowledged physical entry/leave for this handle.
    """
    __slots__ = ('_domain', '_functions', '_host', '_native_domain', '_original',
                 '_reply', '_unknown', '_unknown_carrier', '_closed', '_scope_open',
                 '_runtime_original', '_adoption_original', '_crypto_original')
    _domain: _OriginalDomainCustody
    _functions: _OriginalParentReadFunctions
    _host: c_void_p
    _native_domain: c_void_p
    _original: c_void_p
    _reply: c_void_p
    _unknown: _OriginalParentReadError | None
    _unknown_carrier: _OriginalParentReadError
    _closed: bool
    _scope_open: bool
    _runtime_original: object | None
    _adoption_original: object | None
    _crypto_original: object | None

    @classmethod
    def _prepare_original(cls, domain: _OriginalDomainCustody,
                          functions: _OriginalParentReadFunctions, *,
                          bootstrap_retained: int, bootstrap_execution: int,
                          workspace_execution: int, read_retained: int,
                          read_execution: int) -> _OriginalParentReadCustody:
        values = (bootstrap_retained, bootstrap_execution, workspace_execution,
                  read_retained, read_execution)
        if (cls is not _OriginalParentReadCustody
                or type(domain) is not _OriginalDomainCustody
                or type(functions) is not _OriginalParentReadFunctions
                or functions.library is not domain._functions.library
                or any(type(v) is not int or not -(2**63) <= v <= 2**63 - 1 for v in values)):
            raise ValueError('Original parent read inputs are unavailable')
        if domain._unknown is not None:
            raise domain._unknown
        if (domain._closed or domain._parent_read_original is not None
                or domain._sqlite_library_original is not None
                or domain._live_channel_original is not None
                or domain._worker_process_original is not None):
            raise ValueError('Original parent read domain is unavailable')
        original = cls.__new__(cls)
        original._domain, original._functions = domain, functions
        original._host, original._native_domain = c_void_p(), c_void_p()
        original._original, original._reply = c_void_p(), c_void_p()
        original._unknown, original._closed, original._scope_open = None, False, False
        original._runtime_original = None
        original._adoption_original = None
        original._crypto_original = None
        original._unknown_carrier = _OriginalParentReadError(original, unknown=True)
        reply_out, host_out = byref(original._reply), byref(original._host)
        domain_out, original_out = byref(original._native_domain), byref(original._original)
        known: _OriginalParentReadError | None = None
        # Entry refuses locally before any native mutation. Do not register a
        # foreign responsibility or replace that refusal with a new Unknown.
        domain._owner._enter()
        try:
            if (domain._closed or domain._parent_read_original is not None
                    or domain._sqlite_library_original is not None
                    or domain._live_channel_original is not None
                    or domain._worker_process_original is not None):
                raise ValueError('Original parent read domain is unavailable')
            if domain._unknown is not None:
                raise domain._unknown
            domain._parent_read_original = original
            try:
                original._status(functions.prepare(domain._host, domain._domain,
                    *values, reply_out))
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
                    known = original._owner_issue(fact)
                    raise known
            except BaseException as error:
                if error is known or error is original._unknown:
                    raise
                raise original._mark_unknown() from error
        finally:
            domain._owner._busy = False
        return original

    def __copy__(self) -> _OriginalParentReadCustody:
        raise TypeError('Original parent read custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalParentReadCustody:
        raise TypeError('Original parent read custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original parent read custody cannot be serialized')

    def _mark_unknown(self) -> _OriginalParentReadError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _owner_issue(self, fact: _OriginalArenaFact) -> _OriginalParentReadError:
        # The existing Core imported Owner reports Unknown explicitly. It is
        # not a local known refusal or authorization to repeat the physical op.
        if fact.issue_family == 9:
            self._unknown_carrier.fact = fact
            return self._mark_unknown()
        return _OriginalParentReadError(self, unknown=False, fact=fact)

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _fact(self, expected: int) -> _OriginalArenaFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        operation, issue = self._functions.operation(self._reply), self._functions.issue(self._reply)
        if (type(operation) is not int or operation != expected
                or type(issue) is not int or not 0 <= issue <= 12):
            raise self._mark_unknown()
        return _OriginalArenaFact(operation, issue)

    def _drop(self) -> None:
        if self._reply.value is None:
            return
        self._status(self._functions.drop(byref(self._reply), self._host,
            self._native_domain, self._original))
        if self._reply.value is not None:
            raise self._mark_unknown()

    def _finish_data_ack(self) -> None:
        if (any(slot.value is not None for slot in
                (self._host, self._native_domain, self._original, self._reply))
                or self._domain._parent_read_original is not self):
            raise self._mark_unknown()
        self._closed = True
        self._domain._parent_read_original = _RETIRED_PARENT_READ_DATA
        from ._local_native_host_resources import _retire_host_resources_registration
        _retire_host_resources_registration(self._domain._owner)

    def _call(self, operation: int) -> _OriginalArenaFact:
        if self._unknown is not None:
            raise self._unknown
        domain = self._domain
        if domain._unknown is not None:
            raise domain._unknown
        if (self._closed or domain._closed or domain._parent_read_original is not self
                or self._original.value is None):
            raise ValueError('Original parent read carrier is retired')
        if (operation in (3, 5, 6) and self._scope_open) or (operation == 4 and not self._scope_open):
            raise ValueError('Original parent read scope is unavailable')
        if (operation in (3, 5, 6) and self._runtime_original is not None
                and self._runtime_original is not _RETIRED_PARENT_RUNTIME_DATA):
            raise ValueError('Original packaged Runtime cleanup must finish first')
        if operation in (5, 6):
            from ._local_native_read_crypto import _require_read_crypto_retired
            _require_read_crypto_retired(self)
        if operation in (3, 5, 6):
            from ._local_native_adoption import _require_adoption_retired
            _require_adoption_retired(self)
        reply_out = byref(self._reply)
        known: _OriginalParentReadError | None = None
        domain._owner._enter()
        try:
            self._drop()
            call = {2:self._functions.current, 3:self._functions.enter,
                    4:self._functions.leave, 5:self._functions.cleanup,
                    6:self._functions.close}[operation]
            self._status(call(self._host, self._original, reply_out))
            fact = self._fact(operation)
            if fact.issue_family == 0:
                if operation in (3, 5):
                    self._scope_open = True
                elif operation == 4:
                    self._scope_open = False
            if operation == 6 and fact.issue_family == 0:
                self._status(self._functions.finish(byref(self._host),
                    byref(self._native_domain), byref(self._original), byref(self._reply)))
                self._finish_data_ack()
            else:
                self._drop()
            if fact.issue_family != 0:
                known = self._owner_issue(fact)
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

    def leave_scope(self) -> None:
        """Explicit retry of this same scope after a known leave refusal only.

        An unconfirmed response remains sticky Unknown and cannot call again.
        This observes no context/alias retirement or original loan return.
        """
        from ._local_native_host_resources import _resources_for_domain
        joined = _resources_for_domain(self._domain)
        if joined is not None and joined[0]._read is self and joined[0]._phase == 'read':
            joined[0].leave_scope()
            return
        self._call(4)

    @contextmanager
    def scope(self, *, cleanup: bool = False) -> Iterator[None]:
        """Whole managed input/result/failure lifetime, not read permission."""
        from ._local_native_host_resources import _resources_for_domain
        joined = _resources_for_domain(self._domain)
        if joined is not None:
            if joined[0]._read is not self:
                raise ValueError('Foreign original Host read carrier')
            if not (cleanup and joined[0]._refused_bind_data_retired()):
                with joined[0].scope('read', cleanup=cleanup):
                    yield
                return
            # Refused bind DATA does not grant a phase. Continue only the
            # existing original Read cleanup and its own leave ACK below.
        self._call(5 if cleanup else 3)
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
        """Outer installer after scoped caller references retire, same Owner."""
        if self._unknown is not None:
            raise self._unknown
        if self._closed:
            self._domain._owner._enter()
            self._domain._owner._busy = False
            return
        self._call(6)
