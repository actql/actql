"""Original Core Host/reference custody at the private installed C boundary.

No DLL loader, supplier adoption, raw lease transfer or execution permission.
The trusted installed supplier must select/bind the matching component first.
This is not yet connected to ordinary Local factory or Wasmtime image use.
"""
from __future__ import annotations

from ctypes import POINTER, byref, c_int, c_int32, c_void_p
from dataclasses import dataclass
from threading import get_ident
from typing import Any


@dataclass(frozen=True)
class _OriginalArenaFact:
    """Explanation only; copying a fact transfers no original custody."""

    operation: int
    issue_family: int


class _OriginalControlError(RuntimeError):
    def __init__(self, host: _OriginalControlCustody, *, unknown: bool,
                 fact: _OriginalArenaFact | None = None) -> None:
        self.cleanup_host, self.unknown, self.fact = host, unknown, fact
        super().__init__('Original Native control outcome is unconfirmed' if unknown
                         else 'Original Native control cleanup is pending')


class _OriginalControlFunctions:
    """Bind an already selected library. This class neither loads nor adopts it."""

    def __init__(self, library: Any) -> None:
        self.library = library
        self.originals = library.actql_control_originals_into
        self.originals.argtypes = [c_void_p, POINTER(c_void_p), POINTER(c_void_p)]
        self.originals.restype = c_int
        self.current = library.actql_control_current_into
        self.current.argtypes = [c_void_p, POINTER(c_void_p)]
        self.current.restype = c_int
        self.close = library.actql_control_try_close_and_drop
        self.close.argtypes = [POINTER(c_void_p), POINTER(c_void_p)]
        self.close.restype = c_int
        self.drop = library.actql_control_drop_reply
        self.drop.argtypes = [POINTER(c_void_p), c_void_p]
        self.drop.restype = c_int
        self.operation = library.actql_control_operation
        self.issue = library.actql_control_issue_family
        for function in (self.operation, self.issue):
            function.argtypes = [c_void_p]
            function.restype = c_int32


class _OriginalControlCustody:
    """Owning references to one existing Core Host, not another cleanup Owner.

    Persistent slots are passed directly to C. Unknown never retries a call or
    recreates an original. Known pending cleanup can retry that same Owner.
    The retained reference is the same nominal Host, never an independent lease.
    """

    __slots__ = ('_functions', '_incoming', '_original', '_retained', '_reply',
                 '_unknown', '_busy', '_thread', '_closed')
    _functions: _OriginalControlFunctions
    _incoming: c_void_p
    _original: c_void_p
    _retained: c_void_p
    _reply: c_void_p
    _unknown: _OriginalControlError | None
    _busy: bool
    _thread: int
    _closed: bool

    @classmethod
    def _take_original_reply(cls, functions: _OriginalControlFunctions,
                             owning_reply: c_void_p) -> _OriginalControlCustody:
        if (type(functions) is not _OriginalControlFunctions
                or type(owning_reply) is not c_void_p or owning_reply.value is None):
            raise ValueError('Unavailable original Native reply')
        host = cls.__new__(cls)
        host._functions = functions
        host._incoming = c_void_p(owning_reply.value)
        owning_reply.value = None
        host._original, host._retained, host._reply = c_void_p(), c_void_p(), c_void_p()
        host._unknown = None
        host._busy, host._closed, host._thread = False, False, get_ident()
        host._enter()
        try:
            code = functions.originals(host._incoming, byref(host._original), byref(host._retained))
            if (type(code) is not int or code != 0 or host._original.value is None
                    or host._original.value != host._retained.value):
                raise host._mark_unknown()
            host._drop(host._incoming)
        except BaseException as error:
            if error is host._unknown:
                raise
            raise host._mark_unknown() from error
        finally:
            host._busy = False
        return host

    def __copy__(self) -> _OriginalControlCustody:
        raise TypeError('Original Native control custody cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalControlCustody:
        raise TypeError('Original Native control custody cannot be copied')

    def __reduce__(self) -> object:
        raise TypeError('Original Native control custody cannot be serialized')

    def _enter(self) -> None:
        if get_ident() != self._thread or self._busy:
            raise ValueError('Original Native control call scope is unavailable')
        if self._unknown is not None:
            raise self._unknown
        self._busy = True

    def _mark_unknown(self) -> _OriginalControlError:
        if self._unknown is None:
            self._unknown = _OriginalControlError(self, unknown=True)
        return self._unknown

    def _drop(self, slot: c_void_p) -> None:
        if slot.value is None:
            return
        code = self._functions.drop(byref(slot), self._retained)
        if type(code) is not int or code != 0 or slot.value is not None:
            raise self._mark_unknown()

    def _fact(self) -> _OriginalArenaFact:
        operation = self._functions.operation(self._reply)
        issue = self._functions.issue(self._reply)
        if (type(operation) is not int or not 1 <= operation <= 4
                or type(issue) is not int or not 0 <= issue <= 7):
            raise self._mark_unknown()
        return _OriginalArenaFact(operation, issue)

    def current(self) -> _OriginalArenaFact:
        self._enter()
        if self._closed or self._original.value is None or self._reply.value is not None:
            self._busy = False
            raise ValueError('Original Native control current observation is unavailable')
        try:
            code = self._functions.current(self._original, byref(self._reply))
            if type(code) is not int or code != 0 or self._reply.value is None:
                raise self._mark_unknown()
            fact = self._fact()
            if fact.operation != 3:
                raise self._mark_unknown()
            self._drop(self._reply)
            return fact
        except BaseException as error:
            if error is self._unknown:
                raise
            raise self._mark_unknown() from error
        finally:
            self._busy = False

    def close(self) -> None:
        self._enter()
        pending_error: _OriginalControlError | None = None
        try:
            if self._closed:
                return
            # Only a previously known typed pending reply reaches a retry.
            # Unknown is sticky and rejected by _enter before any native call.
            self._drop(self._reply)
            for slot in (self._original, self._retained):
                if slot.value is None:
                    continue
                code = self._functions.close(byref(slot), byref(self._reply))
                if type(code) is int and code == -3 and self._reply.value is not None:
                    fact = self._fact()
                    if fact.operation != 4 or fact.issue_family == 0:
                        raise self._mark_unknown()
                    pending_error = _OriginalControlError(self, unknown=False, fact=fact)
                    raise pending_error
                if type(code) is not int or code != 0 or slot.value is not None or self._reply.value is not None:
                    raise self._mark_unknown()
            # The second same-original reference uses Core's already-closed
            # idempotent path; it never calls the physical provider directly.
            self._closed = True
        except BaseException as error:
            if error is self._unknown or error is pending_error:
                raise
            raise self._mark_unknown() from error
        finally:
            self._busy = False
