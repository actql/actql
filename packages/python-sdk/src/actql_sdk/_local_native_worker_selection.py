"""Same-component nominal worker selection references, never worker permission.

No DLL loader, adoption, resource reservation, spawn, journal write or physical
close. The installed caller must separately bind the original Host/provisioning
operation. Dropping these data references does not retire that operation.
"""
from __future__ import annotations

from ctypes import POINTER, byref, c_int, c_int32, c_void_p
from dataclasses import dataclass
from typing import Any, NoReturn

from ._local_native_control_custody import _OriginalControlCustody


@dataclass(frozen=True, slots=True)
class _OriginalWorkerSelectionFact:
    operation: int
    issue_family: int


class _OriginalWorkerSelectionError(RuntimeError):
    def __init__(self, selection: _OriginalWorkerSelectionCustody, *, unknown: bool,
                 fact: _OriginalWorkerSelectionFact | None = None) -> None:
        self.cleanup_selection, self.unknown, self.fact = selection, unknown, fact
        super().__init__('Original worker selection outcome is unconfirmed' if unknown
                         else 'Original worker selection was refused')


class _OriginalWorkerSelectionFunctions:
    """Bind the already selected original component; no load or adoption."""

    def __init__(self, library: Any) -> None:
        self.library = library
        self.select = library.actql_worker_select_into
        self.select.argtypes = [c_void_p, POINTER(c_void_p)]
        self.select.restype = c_int
        self.current = library.actql_worker_selection_current_into
        self.current.argtypes = [c_void_p, c_void_p, POINTER(c_void_p)]
        self.current.restype = c_int
        self.originals = library.actql_worker_selection_originals_into
        self.originals.argtypes = [c_void_p, POINTER(c_void_p), POINTER(c_void_p)]
        self.originals.restype = c_int
        self.operation = library.actql_worker_selection_operation
        self.issue = library.actql_worker_selection_issue_family
        for call in (self.operation, self.issue):
            call.argtypes = [c_void_p]
            call.restype = c_int32
        self.drop = library.actql_worker_selection_drop_reply
        self.drop.argtypes = [POINTER(c_void_p), c_void_p, c_void_p]
        self.drop.restype = c_int
        self.finish = library.actql_worker_selection_finish_data
        self.finish.argtypes = [POINTER(c_void_p), POINTER(c_void_p), POINTER(c_void_p)]
        self.finish.restype = c_int


class _OriginalWorkerSelectionCustody:
    """Owning metadata slots; the Native Owner decides nominal current/refusal.

    Exceptional replies keep this same carrier and never repeat selection or
    infer physical cleanup. The original Control serializes calls and retains
    its own independent physical responsibility.
    """

    __slots__ = ('_original', '_owner', '_functions', '_host', '_selection', '_reply',
                 '_unknown', '_unknown_carrier', '_closed')
    _original: _OriginalWorkerSelectionCustody
    _owner: _OriginalControlCustody
    _functions: _OriginalWorkerSelectionFunctions
    _host: c_void_p
    _selection: c_void_p
    _reply: c_void_p
    _unknown: _OriginalWorkerSelectionError | None
    _unknown_carrier: _OriginalWorkerSelectionError
    _closed: bool

    @classmethod
    def _select_original(cls, owner: _OriginalControlCustody,
                         functions: _OriginalWorkerSelectionFunctions) -> _OriginalWorkerSelectionCustody:
        if (type(owner) is not _OriginalControlCustody
                or type(functions) is not _OriginalWorkerSelectionFunctions
                or functions.library is not owner._functions.library):
            raise ValueError('Original worker selection component is unavailable')
        selected = cls.__new__(cls)
        selected._original, selected._owner, selected._functions = selected, owner, functions
        selected._host, selected._selection, selected._reply = c_void_p(), c_void_p(), c_void_p()
        selected._unknown, selected._closed = None, False
        selected._unknown_carrier = _OriginalWorkerSelectionError(selected, unknown=True)
        owner._enter()
        if owner._closed or owner._original.value is None:
            owner._busy = False
            raise ValueError('Original Host is retired')
        known: _OriginalWorkerSelectionError | None = None
        try:
            code = functions.select(owner._original, byref(selected._reply))
            if type(code) is not int or code != 0 or selected._reply.value is None:
                raise selected._mark_unknown()
            fact = selected._fact(1)
            code = functions.originals(selected._reply, byref(selected._host), byref(selected._selection))
            if (type(code) is not int or code != 0 or selected._host.value != owner._original.value
                    or selected._host.value is None
                    or fact.issue_family == 0 and selected._selection.value is None):
                raise selected._mark_unknown()
            selected._drop_reply()
            if fact.issue_family != 0:
                known = _OriginalWorkerSelectionError(selected, unknown=False, fact=fact)
                raise known
        except BaseException as error:
            if error is selected._unknown or error is known:
                raise
            raise selected._mark_unknown() from error
        finally:
            owner._busy = False
        return selected

    def __copy__(self) -> _OriginalWorkerSelectionCustody:
        raise TypeError('Original worker selection cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalWorkerSelectionCustody:
        raise TypeError('Original worker selection cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original worker selection cannot be serialized')

    def _mark_unknown(self) -> _OriginalWorkerSelectionError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _nominal(self) -> None:
        if self._original is not self or self._closed:
            raise ValueError('Foreign or retired original worker selection')
        if self._unknown is not None:
            raise self._unknown

    def _fact(self, operation: int) -> _OriginalWorkerSelectionFact:
        actual = self._functions.operation(self._reply)
        issue = self._functions.issue(self._reply)
        if type(actual) is not int or actual != operation or type(issue) is not int or not 0 <= issue <= 7:
            raise self._mark_unknown()
        return _OriginalWorkerSelectionFact(actual, issue)

    def _drop_reply(self) -> None:
        code = self._functions.drop(byref(self._reply), self._host, self._selection)
        if type(code) is not int or code != 0 or self._reply.value is not None:
            raise self._mark_unknown()

    def current(self) -> _OriginalWorkerSelectionFact:
        self._nominal()
        owner = self._owner
        owner._enter()
        if self._host.value is None or self._selection.value is None or self._reply.value is not None:
            owner._busy = False
            raise ValueError('Original worker selection is unavailable')
        known: _OriginalWorkerSelectionError | None = None
        try:
            code = self._functions.current(self._host, self._selection, byref(self._reply))
            if type(code) is not int or code != 0 or self._reply.value is None:
                raise self._mark_unknown()
            fact = self._fact(2)
            self._drop_reply()
            if fact.issue_family != 0:
                known = _OriginalWorkerSelectionError(self, unknown=False, fact=fact)
                raise known
            return fact
        except BaseException as error:
            if error is self._unknown or error is known:
                raise
            raise self._mark_unknown() from error
        finally:
            owner._busy = False

    def close(self) -> None:
        """Drop metadata only, including after the original Host has closed.

        This does not close the Host, release physical capacity, acknowledge a
        worker, update the durable child operation or settle a delegation.
        """
        if self._original is not self:
            raise ValueError('Foreign original worker selection')
        if self._closed:
            return
        self._nominal()
        owner = self._owner
        owner._enter()
        try:
            code = self._functions.finish(byref(self._host), byref(self._selection), byref(self._reply))
            if (type(code) is not int or code != 0 or self._host.value is not None
                    or self._selection.value is not None or self._reply.value is not None):
                raise self._mark_unknown()
            self._closed = True
        except BaseException as error:
            if error is self._unknown:
                raise
            raise self._mark_unknown() from error
        finally:
            owner._busy = False
