"""Physical caller's original SharedBorrow references; no execution decisions.

The selected library and original Host are supplied by the existing trusted
control assembly. No loader, raw lease transfer, provider close or Run Owner.
"""
from __future__ import annotations

from ._local_native_shim_abi import bind as bind_native

from collections.abc import Iterator
from contextlib import contextmanager
from ctypes import POINTER, byref, c_int, c_int32, c_void_p
from typing import Any, NoReturn

from ._local_native_control_custody import _OriginalArenaFact, _OriginalControlCustody


def _new_backing_slots() -> tuple[c_void_p, c_void_p, c_void_p]:
    return c_void_p(), c_void_p(), c_void_p()


class _OriginalBackingError(RuntimeError):
    def __init__(self, borrow: _OriginalBackingCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_borrow, self.unknown, self.fact = borrow, unknown, fact
        super().__init__('Original backing outcome is unconfirmed' if unknown
                         else 'Original backing operation was refused')


class _OriginalBackingFunctions:
    """Bind the same already-selected component, without loading/adopting it."""

    def __init__(self, library: Any) -> None:
        self.library = library
        self.borrow = bind_native(library, 'actql_backing_borrow_into')
        self.current = bind_native(library, 'actql_backing_current_into')
        self.return_loan = bind_native(library, 'actql_backing_return_into')
        self.enter_scope = bind_native(library, 'actql_backing_enter_scope_into')
        self.leave_scope = bind_native(library, 'actql_backing_leave_scope_into')
        self.originals = bind_native(library, 'actql_backing_originals_into')
        self.drop = bind_native(library, 'actql_backing_drop_reply')
        self.finish = bind_native(library, 'actql_backing_finish_returned_data')
        self.refused = bind_native(library, 'actql_backing_finish_refused_borrow')
        self.operation = bind_native(library, 'actql_backing_operation')
        self.issue = bind_native(library, 'actql_backing_issue_family')


class _OriginalBackingCustody:
    """Owning data slots for one loan decided by the existing Core Owner.

    Unknown is sticky and retains this carrier. Known typed refusal allows only
    an explicit caller retry. Return is for a trusted physical caller after its
    same use stopped; it neither stops the caller nor acknowledges Host cleanup.
    """

    __slots__ = ('_owner', '_functions', '_host', '_loan', '_reply', '_unknown',
                 '_unknown_carrier', '_closed')
    _owner: _OriginalControlCustody
    _functions: _OriginalBackingFunctions
    _host: c_void_p
    _loan: c_void_p
    _reply: c_void_p
    _unknown: _OriginalBackingError | None
    _unknown_carrier: _OriginalBackingError
    _closed: bool

    @classmethod
    def _borrow_original(cls, owner: _OriginalControlCustody,
                         functions: _OriginalBackingFunctions) -> _OriginalBackingCustody:
        if (type(owner) is not _OriginalControlCustody
                or type(functions) is not _OriginalBackingFunctions
                or functions.library is not owner._functions.library):
            raise ValueError('Original backing component is unavailable')
        # Carrier slots and sticky failure metadata precede the first call;
        # failure here cannot lose a caller original or an issued Core loan.
        borrow = cls.__new__(cls)
        borrow._owner, borrow._functions = owner, functions
        borrow._host, borrow._loan, borrow._reply = _new_backing_slots()
        borrow._unknown, borrow._closed = None, False
        # Allocate the same-loan failure carrier before Core can issue a loan.
        # Unknown reply reporting then retains these slots without allocation.
        borrow._unknown_carrier = _OriginalBackingError(borrow, unknown=True)
        owner._enter(require_initial=True)
        if owner._closed or owner._original.value is None:
            owner._busy = False
            raise ValueError('Original Host is retired')
        known: _OriginalBackingError | None = None
        try:
            borrow._status(functions.borrow(owner._original, byref(borrow._reply)))
            borrow._status(functions.originals(borrow._reply, byref(borrow._host), byref(borrow._loan)))
            if borrow._host.value is None or borrow._host.value != owner._original.value:
                raise borrow._mark_unknown()
            fact = borrow._fact(1)
            if fact.issue_family != 0:
                if borrow._loan.value is not None:
                    raise borrow._mark_unknown()
                borrow._status(functions.refused(byref(borrow._host), byref(borrow._reply)))
                if borrow._host.value is not None or borrow._reply.value is not None:
                    raise borrow._mark_unknown()
                borrow._closed = True
                known = _OriginalBackingError(borrow, unknown=False, fact=fact)
                raise known
            if borrow._loan.value is None:
                raise borrow._mark_unknown()
            borrow._drop()
            return borrow
        except BaseException as error:
            if error is borrow._unknown or error is known:
                raise
            raise borrow._mark_unknown() from error
        finally:
            owner._busy = False

    def __copy__(self) -> _OriginalBackingCustody:
        raise TypeError('Original backing custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalBackingCustody:
        raise TypeError('Original backing custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original backing custody cannot be serialized')

    def _mark_unknown(self) -> _OriginalBackingError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _fact(self, expected: int) -> _OriginalArenaFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        operation = self._functions.operation(self._reply)
        issue = self._functions.issue(self._reply)
        if (type(operation) is not int or operation != expected
                or type(issue) is not int or not 0 <= issue <= 7):
            raise self._mark_unknown()
        return _OriginalArenaFact(operation, issue)

    def _drop(self) -> None:
        if self._reply.value is None:
            return
        self._status(self._functions.drop(byref(self._reply), self._host, self._loan))
        if self._reply.value is not None:
            raise self._mark_unknown()

    def _enter(self, *, require_initial: bool = False) -> None:
        if self._unknown is not None:
            raise self._unknown
        self._owner._enter(require_initial=require_initial)

    def current(self) -> _OriginalArenaFact:
        self._enter(require_initial=True)
        if self._closed or self._loan.value is None:
            self._owner._busy = False
            raise ValueError('Original backing loan is retired')
        known: _OriginalBackingError | None = None
        try:
            self._drop()
            self._status(self._functions.current(self._host, self._loan, byref(self._reply)))
            fact = self._fact(2)
            self._drop()
            if fact.issue_family != 0:
                known = _OriginalBackingError(self, unknown=False, fact=fact)
                raise known
            return fact
        except BaseException as error:
            if error is self._unknown or error is known:
                raise
            raise self._mark_unknown() from error
        finally:
            self._owner._busy = False

    def return_after_stop(self) -> None:
        """Trusted physical caller only; this method does not perform a stop."""
        self._enter()
        known: _OriginalBackingError | None = None
        try:
            if self._closed:
                return
            self._drop()
            self._status(self._functions.return_loan(self._host, self._loan, byref(self._reply)))
            fact = self._fact(3)
            if fact.issue_family != 0:
                known = _OriginalBackingError(self, unknown=False, fact=fact)
                raise known
            self._status(self._functions.finish(byref(self._host), byref(self._loan), byref(self._reply)))
            if any(slot.value is not None for slot in (self._host, self._loan, self._reply)):
                raise self._mark_unknown()
            self._closed = True
        except BaseException as error:
            if error is self._unknown or error is known:
                raise
            raise self._mark_unknown() from error
        finally:
            self._owner._busy = False

    def _change_physical_scope(self, operation: int) -> None:
        if type(operation) is not int or operation not in (4, 5):
            raise ValueError('Invalid original physical scope operation')
        self._enter(require_initial=operation == 4)
        if self._closed or self._loan.value is None:
            self._owner._busy = False
            raise ValueError('Original backing loan is retired')
        known: _OriginalBackingError | None = None
        try:
            self._drop()
            call = self._functions.enter_scope if operation == 4 else self._functions.leave_scope
            self._status(call(self._host, self._loan, byref(self._reply)))
            fact = self._fact(operation)
            self._drop()
            if fact.issue_family != 0:
                known = _OriginalBackingError(self, unknown=False, fact=fact)
                raise known
        except BaseException as error:
            if error is self._unknown or error is known:
                raise
            raise self._mark_unknown() from error
        finally:
            self._owner._busy = False

    @contextmanager
    def _physical_scope(self) -> Iterator[None]:
        """Same provider use only; Core, not Python counters, owns its depth."""
        self._change_physical_scope(4)
        try:
            yield
        except BaseException as primary:
            try:
                self._change_physical_scope(5)
            except BaseException as cleanup:
                raise cleanup from primary
            raise
        else:
            self._change_physical_scope(5)
