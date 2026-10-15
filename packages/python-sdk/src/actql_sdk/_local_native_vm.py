"""Same-instance physical observations, never a funding or execution grant.

Only LocalCore captures this after observing its selected native VM span.
The future live-child import port must use this original, not caller-provided
addresses, capacity DATA, a copied nonce, or a different Store's Caller.
"""
from __future__ import annotations

from ctypes import c_void_p, cast
from os import getpid
from threading import Thread, current_thread
from typing import Any, NoReturn, TYPE_CHECKING

if TYPE_CHECKING:
    from ._local_core import LocalCore
    from ._local_native_holding import _NativeHoldingLease


def _context_address(value: Any) -> int:
    address = cast(value._context(), c_void_p).value
    if address is None:
        raise ValueError('Original Local Store context is unavailable')
    return address


class _OriginalVMObservation:
    """Retain the original Core/Store/holding until physical cleanup succeeds."""

    _original: _OriginalVMObservation
    _core: LocalCore | None
    _identity: object
    _nonce: int
    _store: Any
    _exports: Any
    _memory: Any
    _context: int
    _holding: _NativeHoldingLease
    _generation: int
    _recipe: bytes
    _library: Any
    _span: tuple[int, int]
    _memory_class: type[Any]
    _caller_class: type[Any]
    _process: int
    _thread: Thread

    def __init__(self) -> None:
        raise TypeError('Local VM observations require the original Core')

    @classmethod
    def _capture(cls, core: LocalCore, runtime: Any) -> _OriginalVMObservation:
        from ._local_core import LocalCore
        if (type(core) is not LocalCore or core._physical_vm_observation is not None
                or core._closed or core._retired or core._closing
                or core._physical_holding is None or core._store is None
                or core._physical_vm_span is None or core._physical_vm_type is not None):
            raise ValueError('Original Local VM observation is unavailable')
        memory = core._exports.get('memory')
        if not isinstance(memory, runtime.Memory):
            raise ValueError('Original Local memory is unavailable')
        value = cls.__new__(cls)
        value._original = value
        value._core = core
        value._identity, value._nonce = core._identity, core._nonce
        value._store, value._exports, value._memory = core._store, core._exports, memory
        value._context = _context_address(core._store)
        value._holding = core._physical_holding
        value._generation, value._recipe = value._holding._generation, value._holding._recipe
        value._library = value._holding._library
        value._span = core._physical_vm_span
        value._memory_class, value._caller_class = runtime.Memory, runtime.Caller
        value._process, value._thread = getpid(), current_thread()
        # Publish the original before fallible physical validation. Core keeps
        # every same handle on initialization/cleanup failure.
        core._physical_vm_observation = value
        value._require_core_current()
        return value

    def __copy__(self) -> NoReturn:
        raise TypeError('Original Local VM observation cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original Local VM observation cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Local VM observation cannot be serialized')

    def _require_core_current(self) -> None:
        core = self._core
        if (self._original is not self or self._process != getpid()
                or self._thread is not current_thread() or core is None
                or core._physical_vm_observation is not self
                or core._identity is not self._identity or core._nonce != self._nonce
                or core._closed or core._retired or core._store is not self._store
                or core._exports is not self._exports
                or core._exports.get('memory') is not self._memory
                or core._physical_holding is not self._holding
                or core._physical_vm_span != self._span
                or self._holding._core_identity is not self._identity
                or not self._holding._transfer_attempted
                or self._holding._generation != self._generation
                or self._holding._recipe != self._recipe
                or self._holding._library is not self._library):
            raise ValueError('Foreign or retired original Local VM observation')
        # Closing is deliberately permitted: lifecycle identity is distinct
        # from admitting new work. The original Owner decides stop/report.
        if (_context_address(self._store) != self._context
                or cast(self._memory.data_ptr(self._store), c_void_p).value != self._span[0]):
            raise ValueError('Original Local Store or memory changed')
        self._holding._require_confirmed_retirement_state()
        self._holding._require_live_span(c_void_p(self._span[0]), self._span[1])

    def _require_caller(self, caller: Any, nonce: int) -> None:
        """Check the calling instance as well as the original physical backing."""
        if type(nonce) is not int or nonce != self._nonce or not isinstance(caller, self._caller_class):
            raise ValueError('Foreign original Local callback')
        self._require_core_current()
        if _context_address(caller) != self._context:
            raise ValueError('Foreign original Local callback Store')
        memory = caller.get('memory')
        if (not isinstance(memory, self._memory_class)
                or cast(memory.data_ptr(caller), c_void_p).value != self._span[0]):
            raise ValueError('Foreign original Local callback memory')
        self._require_core_current()

    def _retire_metadata(self, core: LocalCore) -> None:
        """Break references only after Core confirms Store-last and holding close."""
        if (self._original is not self or self._core is not core
                or core._physical_vm_observation is not self
                or core._store is not None or core._physical_holding is not None
                or not core._retired):
            raise ValueError('Original Local VM physical retirement is unconfirmed')
        self._core = None
        del self._store, self._exports, self._memory, self._holding, self._library
