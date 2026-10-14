"""Original Native domain reply custody; no Python funding or Run decisions."""
from __future__ import annotations

from collections.abc import Iterator
from contextlib import contextmanager
from ctypes import POINTER, byref, c_int, c_int32, c_int64, c_void_p, c_ubyte
from dataclasses import dataclass
from typing import Any, NoReturn

from ._local_native_control_custody import _OriginalArenaFact, _OriginalControlCustody
from ._local_native_backing_custody import _OriginalBackingCustody
from ._local_worker_slot import _OriginalDescriptor


@dataclass(frozen=True, slots=True)
class _OriginalDomainMaterial:
    """Immutable explanation/transport DATA; no original custody or permit."""
    source: str
    recipe: bytes
    scalars: tuple[int, ...]


class _OriginalDomainMaterialFunctions:
    """Mandatory matching private exports, not a loader or compatibility path."""
    def __init__(self, library: Any) -> None:
        self.library = library
        self.project = library.actql_domain_project_into
        self.project.argtypes = [c_void_p, c_void_p, POINTER(c_void_p)]
        self.project.restype = c_int
        self.read = library.actql_domain_copy_material
        self.read.argtypes = [c_void_p, c_void_p, c_void_p,
                              POINTER(c_ubyte), POINTER(c_ubyte), POINTER(c_int64)]
        self.read.restype = c_int


def _new_domain_slots() -> tuple[c_void_p, c_void_p, c_void_p]:
    return c_void_p(), c_void_p(), c_void_p()


class _OriginalDomainError(RuntimeError):
    def __init__(self, domain: _OriginalDomainCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_domain, self.unknown, self.fact = domain, unknown, fact
        super().__init__('Original Native domain outcome is unconfirmed' if unknown
                         else 'Original Native domain operation was refused')


class _OriginalDomainFunctions:
    """Bind the same already-selected component; no load/adoption or fallback."""
    def __init__(self, library: Any) -> None:
        self.library = library
        self.prepare = library.actql_domain_prepare_into
        self.prepare.argtypes = [c_void_p, c_void_p, c_int32, c_int64,
                                 c_int32, c_int32, c_int32, c_int64, c_int64, c_int64,
                                 POINTER(c_void_p)]
        self.prepare.restype = c_int
        self.current = library.actql_domain_current_into
        self.transfer = library.actql_domain_transfer_into
        self.enter = library.actql_domain_enter_into
        self.leave = library.actql_domain_leave_into
        self.close = library.actql_domain_close_into
        for call in (self.current, self.transfer, self.enter, self.leave, self.close):
            call.argtypes = [c_void_p, c_void_p, POINTER(c_void_p)]
            call.restype = c_int
        self.originals = library.actql_domain_originals_into
        self.originals.argtypes = [c_void_p, POINTER(c_void_p), POINTER(c_void_p)]
        self.originals.restype = c_int
        self.drop = library.actql_domain_drop_reply
        self.drop.argtypes = [POINTER(c_void_p), c_void_p, c_void_p]
        self.drop.restype = c_int
        self.finish = library.actql_domain_finish_closed_data
        self.finish.argtypes = [POINTER(c_void_p), POINTER(c_void_p), POINTER(c_void_p)]
        self.finish.restype = c_int
        self.refused = library.actql_domain_finish_refused_prepare
        self.refused.argtypes = [POINTER(c_void_p), POINTER(c_void_p)]
        self.refused.restype = c_int
        self.operation = library.actql_domain_operation
        self.issue = library.actql_domain_issue_family
        for call in (self.operation, self.issue):
            call.argtypes = [c_void_p]
            call.restype = c_int32


class _OriginalDomainCustody:
    """One original Owner-issued domain, not another quota or cleanup Owner.

    Native owns current/transfer/scope/cleanup decisions. Persistent Python
    slots retain the exact partial result on response loss. FD and backing
    scope remain separately caller-owned; closing this data never retires them.
    """
    __slots__ = ('_owner', '_scope', '_descriptor', '_functions', '_host', '_domain',
                 '_reply', '_unknown', '_unknown_carrier', '_closed')
    _owner: _OriginalControlCustody
    _scope: _OriginalBackingCustody
    _descriptor: _OriginalDescriptor
    _functions: _OriginalDomainFunctions
    _host: c_void_p
    _domain: c_void_p
    _reply: c_void_p
    _unknown: _OriginalDomainError | None
    _unknown_carrier: _OriginalDomainError
    _closed: bool

    @classmethod
    def _prepare_original(cls, owner: _OriginalControlCustody,
                          scope: _OriginalBackingCustody, descriptor: _OriginalDescriptor,
                          functions: _OriginalDomainFunctions, *, size: int,
                          work: int, attempts: int, holdings: int, transfer: int,
                          retained: int, execution: int) -> _OriginalDomainCustody:
        if (type(owner) is not _OriginalControlCustody or type(scope) is not _OriginalBackingCustody
                or type(functions) is not _OriginalDomainFunctions or scope._owner is not owner
                or functions.library is not owner._functions.library
                or scope._functions.library is not functions.library
                or scope._closed or scope._unknown is not None or scope._loan.value is None
                or type(descriptor) is not _OriginalDescriptor or descriptor._original is not descriptor
                or descriptor.closed or descriptor.close_attempted
                or type(descriptor.value) is not int or not 0 <= descriptor.value <= 2**31 - 1
                or any(type(x) is not int or not -(2**31) <= x <= 2**31 - 1 for x in (work, attempts, holdings))
                or any(type(x) is not int or not -(2**63) <= x <= 2**63 - 1 for x in (size, transfer, retained, execution))):
            raise ValueError('Original Native domain inputs are unavailable')
        # Only ABI representability is checked here. Core validates the declared
        # limits and original physical scope; Python creates no quota or grant.
        domain = cls.__new__(cls)
        domain._owner, domain._scope, domain._descriptor = owner, scope, descriptor
        domain._functions = functions
        domain._host, domain._domain, domain._reply = _new_domain_slots()
        domain._unknown, domain._closed = None, False
        domain._unknown_carrier = _OriginalDomainError(domain, unknown=True)
        owner._enter()
        if owner._closed or owner._original.value is None:
            owner._busy = False
            raise ValueError('Original Native Host is retired')
        known: _OriginalDomainError | None = None
        try:
            domain._status(functions.prepare(owner._original, scope._loan, descriptor.value,
                size, work, attempts, holdings, transfer, retained, execution, byref(domain._reply)))
            domain._status(functions.originals(domain._reply, byref(domain._host), byref(domain._domain)))
            if domain._host.value is None or domain._host.value != owner._original.value:
                raise domain._mark_unknown()
            fact = domain._fact(1)
            if domain._domain.value is None:
                if fact.issue_family == 0:
                    raise domain._mark_unknown()
                domain._status(functions.refused(byref(domain._host), byref(domain._reply)))
                if domain._host.value is not None or domain._reply.value is not None:
                    raise domain._mark_unknown()
                domain._closed = True
            else:
                domain._drop()
            if fact.issue_family != 0:
                known = _OriginalDomainError(domain, unknown=False, fact=fact)
                raise known
            return domain
        except BaseException as error:
            if error is domain._unknown or error is known:
                raise
            raise domain._mark_unknown() from error
        finally:
            owner._busy = False

    def __copy__(self) -> _OriginalDomainCustody:
        raise TypeError('Original Native domain custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalDomainCustody:
        raise TypeError('Original Native domain custody cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Native domain custody cannot be serialized')

    def _mark_unknown(self) -> _OriginalDomainError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _status(self, code: Any) -> None:
        if type(code) is not int or code != 0:
            raise self._mark_unknown()

    def _fact(self, expected: int) -> _OriginalArenaFact:
        if self._reply.value is None:
            raise self._mark_unknown()
        operation, issue = self._functions.operation(self._reply), self._functions.issue(self._reply)
        if (type(operation) is not int or operation != expected
                or type(issue) is not int or not 0 <= issue <= 8):
            raise self._mark_unknown()
        return _OriginalArenaFact(operation, issue)

    def _drop(self) -> None:
        if self._reply.value is None:
            return
        self._status(self._functions.drop(byref(self._reply), self._host, self._domain))
        if self._reply.value is not None:
            raise self._mark_unknown()

    def _call(self, expected: int) -> _OriginalArenaFact:
        if self._unknown is not None:
            raise self._unknown
        self._owner._enter()
        if self._closed or self._domain.value is None:
            self._owner._busy = False
            raise ValueError('Original Native domain is retired')
        known: _OriginalDomainError | None = None
        try:
            self._drop()
            call = {2:self._functions.current, 3:self._functions.transfer,
                    4:self._functions.enter, 5:self._functions.leave, 6:self._functions.close}[expected]
            self._status(call(self._host, self._domain, byref(self._reply)))
            fact = self._fact(expected)
            if expected == 6 and fact.issue_family == 0:
                self._status(self._functions.finish(byref(self._host), byref(self._domain), byref(self._reply)))
                if any(slot.value is not None for slot in (self._host, self._domain, self._reply)):
                    raise self._mark_unknown()
                self._closed = True
            elif expected != 6:
                self._drop()
            if fact.issue_family != 0:
                known = _OriginalDomainError(self, unknown=False, fact=fact)
                raise known
            return fact
        except BaseException as error:
            if error is self._unknown or error is known:
                raise
            raise self._mark_unknown() from error
        finally:
            self._owner._busy = False

    def current(self) -> _OriginalArenaFact:
        return self._call(2)

    def _project_original_material(self, functions: _OriginalDomainMaterialFunctions) -> _OriginalDomainMaterial:
        """Get DATA from the same Owner; no scalar material can start a child.

        Each call obtains a new checked reply, retains the original slots on
        response loss and rechecks current after the exact bounded copy. No
        previous reply/cache bypasses current or supplies new execution quota.
        """
        if (type(functions) is not _OriginalDomainMaterialFunctions
                or functions.library is not self._functions.library):
            raise ValueError('Foreign original domain material component')
        if self._unknown is not None:
            raise self._unknown
        # Allocate bounded output metadata before consuming a native reply.
        source, recipe, scalars = (c_ubyte * 40)(), (c_ubyte * 32)(), (c_int64 * 15)()
        self._owner._enter()
        if self._closed or self._domain.value is None:
            self._owner._busy = False
            raise ValueError('Original Native domain is retired')
        known: _OriginalDomainError | None = None
        try:
            self._drop()
            self._status(functions.project(self._host, self._domain, byref(self._reply)))
            fact = self._fact(7)
            if fact.issue_family != 0:
                self._drop()
                known = _OriginalDomainError(self, unknown=False, fact=fact)
                raise known
            self._status(functions.read(self._reply, self._host, self._domain, source, recipe, scalars))
            text, values = bytes(source).decode('ascii'), tuple(scalars)
            # Encoding consistency only. The existing Core/physical Owners
            # validate limits, bounds and funding; Python creates no grant.
            if (any(c not in '0123456789abcdef' for c in text) or values[8] not in (0, 1)
                    or any(value < 0 for value in values)):
                raise self._mark_unknown()
            material = _OriginalDomainMaterial(text, bytes(recipe), values)
            self._drop()
            self._status(self._functions.current(self._host, self._domain, byref(self._reply)))
            fact = self._fact(2)
            self._drop()
            if fact.issue_family != 0:
                known = _OriginalDomainError(self, unknown=False, fact=fact)
                raise known
            return material
        except BaseException as error:
            if error is self._unknown or error is known:
                raise
            raise self._mark_unknown() from error
        finally:
            self._owner._busy = False

    def transfer(self) -> None:
        self._call(3)

    @contextmanager
    def _physical_scope(self) -> Iterator[None]:
        self._call(4)
        try:
            yield
        except BaseException as primary:
            try:
                self._call(5)
            except BaseException as cleanup:
                raise cleanup from primary
            raise
        else:
            self._call(5)

    def close_after_stop(self) -> None:
        """Trusted caller after same scoped stop/borrower retirement; no stop here."""
        if self._unknown is not None:
            raise self._unknown
        if self._closed:
            # Keep same-process/thread/reentry rejection for a retired alias.
            self._owner._enter()
            self._owner._busy = False
            return
        self._call(6)
