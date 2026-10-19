"""Original Core Host/reference custody at the private installed C boundary.

No DLL loader, supplier adoption, raw lease transfer or execution permission.
The trusted installed supplier must select/bind the matching component first.
This is not yet connected to ordinary Local factory or Wasmtime image use.
"""
from __future__ import annotations

from ._local_native_shim_abi import bind as bind_native

from ctypes import POINTER, byref, c_int, c_int32, c_uint16, c_ubyte, c_void_p
from dataclasses import dataclass
from os import getpid
from threading import Thread, current_thread
from typing import TYPE_CHECKING, Any, NoReturn

if TYPE_CHECKING:
    from ._local_native_initial_custody import _OriginalPythonNativeInitial

from ._local_worker_slot import _OriginalDescriptor


def _new_control_slots() -> tuple[c_void_p, c_void_p, c_void_p, c_void_p]:
    """Allocate empty Python metadata before consuming any native reference."""
    return c_void_p(), c_void_p(), c_void_p(), c_void_p()


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
        self.originals = bind_native(library, 'actql_control_originals_into')
        self.current = bind_native(library, 'actql_control_current_into')
        self.acquire_fd = bind_native(library, 'actql_control_acquire_fd_into')
        self.close = bind_native(library, 'actql_control_try_close_and_drop')
        self.drop = bind_native(library, 'actql_control_drop_reply')
        self.operation = bind_native(library, 'actql_control_operation')
        self.issue = bind_native(library, 'actql_control_issue_family')


class _OriginalControlCustody:
    """Owning references to one existing Core Host, not another cleanup Owner.

    Persistent slots are passed directly to C. Unknown never retries a call or
    recreates an original. Known pending cleanup can retry that same Owner.
    The retained reference is the same nominal Host, never an independent lease.
    """

    __slots__ = ('_functions', '_incoming', '_original', '_retained', '_reply',
                 '_unknown', '_unknown_carrier', '_busy', '_thread', '_process', '_closed',
                 '_acquire_started', '_borrowed_fd', '_host_resources_original',
                 '_python_initial_original')
    _functions: _OriginalControlFunctions
    _incoming: c_void_p
    _original: c_void_p
    _retained: c_void_p
    _reply: c_void_p
    _unknown: _OriginalControlError | None
    _unknown_carrier: _OriginalControlError
    _busy: bool
    _thread: Thread
    _process: int
    _closed: bool
    _acquire_started: bool
    _borrowed_fd: _OriginalDescriptor | None
    _python_initial_original: _OriginalPythonNativeInitial | None
    _host_resources_original: object | None

    @classmethod
    def _empty_original(cls, functions: _OriginalControlFunctions) -> _OriginalControlCustody:
        host = cls.__new__(cls)
        host._functions = functions
        host._incoming, host._original, host._retained, host._reply = _new_control_slots()
        host._unknown = None
        host._busy, host._closed = False, False
        host._acquire_started, host._borrowed_fd = False, None
        host._host_resources_original = None
        host._python_initial_original = None
        host._thread, host._process = current_thread(), getpid()
        # Reporting a lost native reply must not allocate its cleanup carrier
        # after the original has moved. Failure here leaves the input untouched.
        host._unknown_carrier = _OriginalControlError(host, unknown=True)
        return host

    @classmethod
    def _prepare_original(cls, functions: _OriginalControlFunctions, *,
                          source: str, recipe: bytes, generation: int, size: int,
                          work: int, attempts: int, holdings: int, transfer: int,
                          retained: int, execution: int, envelope: int,
                          _python_initial: _OriginalPythonNativeInitial | None = None) -> _OriginalControlCustody:
        """Trusted private assembly, not an installed supplier or funding fact.

        The existing Native Owner creates/reserves its original Ledger only on
        subsequent actual acquire. Every Python slot precedes this first call;
        response loss retains the exact preparation reply, never a new Host.
        """
        if (type(functions) is not _OriginalControlFunctions or type(source) is not str
                or len(source) != 40 or any(c not in '0123456789abcdef' for c in source)
                or type(recipe) is not bytes or len(recipe) != 32
                or any(type(n) is not int or not 0 <= n <= 2**31 - 1
                       for n in (work, attempts, holdings))
                or any(type(n) is not int or not 0 <= n <= 2**63 - 1
                       for n in (generation, size, transfer, retained, execution, envelope))):
            raise ValueError('Original Native preparation inputs are unavailable')
        if _python_initial is not None:
            from ._local_native_initial_custody import _OriginalPythonNativeInitial
            if (type(_python_initial) is not _OriginalPythonNativeInitial
                    or _python_initial._functions.library is not functions.library):
                raise ValueError('Foreign original Python Native component')
            _python_initial.require_control_current()
        # Bind before any Owner call. An old component missing this new private
        # ABI is refused without acquiring or substituting a different library.
        prepare = bind_native(functions.library, 'actql_control_prepare_utf16_into')
        source_units = (c_uint16 * 40)(*map(ord, source))
        recipe_bytes = (c_ubyte * 32).from_buffer_copy(recipe)
        host = cls._empty_original(functions)
        if _python_initial is not None:
            # The operational Python path keeps its already initialized
            # Runtime/default original before the first Host allocation. The
            # declared Host limits still require their actual backing later.
            _python_initial._bind_control_host(host)
            host._python_initial_original = _python_initial
        host._enter()
        known: _OriginalControlError | None = None
        try:
            code = prepare(source_units, 40, recipe_bytes, 32, generation, size,
                           work, attempts, holdings, transfer, retained, execution,
                           envelope, byref(host._incoming))
            if type(code) is not int or code != 0 or host._incoming.value is None:
                raise host._mark_unknown()
            operation = functions.operation(host._incoming)
            issue = functions.issue(host._incoming)
            if (type(operation) is not int or operation != 1
                    or type(issue) is not int or not 0 <= issue <= 7):
                raise host._mark_unknown()
            if issue != 0:
                # Native permits this data drop only when the typed preparation
                # really has no original Host; an inconsistent partial stays.
                host._drop(host._incoming)
                host._closed = True
                known = _OriginalControlError(host, unknown=False,
                                              fact=_OriginalArenaFact(operation, issue))
                raise known
            code = functions.originals(host._incoming, byref(host._original), byref(host._retained))
            if (type(code) is not int or code != 0 or host._original.value is None
                    or host._original.value != host._retained.value):
                raise host._mark_unknown()
            host._drop(host._incoming)
            return host
        except BaseException as error:
            if error is host._unknown or error is known:
                raise
            raise host._mark_unknown() from error
        finally:
            host._busy = False

    @classmethod
    def _take_original_reply(cls, functions: _OriginalControlFunctions,
                             owning_reply: c_void_p) -> _OriginalControlCustody:
        if (type(functions) is not _OriginalControlFunctions
                or type(owning_reply) is not c_void_p or owning_reply.value is None):
            raise ValueError('Unavailable original Native reply')
        host = cls._empty_original(functions)
        host._enter()
        try:
            # Initialization/allocation failures above leave the caller's slot
            # untouched. After this move every failure returns this carrier.
            host._incoming.value = owning_reply.value
            owning_reply.value = None
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

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Native control custody cannot be serialized')

    def _enter(self) -> None:
        if getpid() != self._process or current_thread() is not self._thread or self._busy:
            raise ValueError('Original Native control call scope is unavailable')
        if self._unknown is not None:
            raise self._unknown
        self._busy = True

    def _mark_unknown(self) -> _OriginalControlError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
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
        if self._python_initial_original is not None:
            self._python_initial_original.require_control_current()
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

    def acquire_fd(self, descriptor: _OriginalDescriptor) -> _OriginalArenaFact:
        """Trusted installed physical caller only; no supplier or FD grant.

        The same descriptor remains caller-owned through confirmed mapping
        cleanup. A data fact returned here cannot cover its separate overhead,
        admit a worker or supply VM/Source/Model/publisher authorization.
        """
        if (type(descriptor) is not _OriginalDescriptor or descriptor._original is not descriptor or descriptor.closed
                or descriptor.close_attempted or type(descriptor.value) is not int
                or not 0 <= descriptor.value <= 2**31 - 1):
            raise ValueError('Original borrowed control descriptor is unavailable')
        if self._python_initial_original is not None:
            self._python_initial_original.require_control_current()
        self._enter()
        if (self._closed or self._acquire_started or self._original.value is None
                or self._reply.value is not None):
            self._busy = False
            raise ValueError('Original Native FD acquisition is unavailable')
        self._acquire_started = True
        # Retain the same FD carrier before Core/physical acquisition. The
        # caller owns its close; response loss cannot detach that responsibility.
        self._borrowed_fd = descriptor
        known: _OriginalControlError | None = None
        try:
            code = self._functions.acquire_fd(self._original, descriptor.value, byref(self._reply))
            if type(code) is not int or code != 0 or self._reply.value is None:
                raise self._mark_unknown()
            fact = self._fact()
            if fact.operation != 2:
                raise self._mark_unknown()
            self._drop(self._reply)
            if fact.issue_family != 0:
                known = _OriginalControlError(self, unknown=False, fact=fact)
                raise known
            return fact
        except BaseException as error:
            if error is self._unknown or error is known:
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
