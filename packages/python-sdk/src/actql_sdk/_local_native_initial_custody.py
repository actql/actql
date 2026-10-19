"""Same initial Python service into the selected Native component's original.

This binds an already verified, constructor-free private component. It is not
a loader, pre-load platform supplier, Worker admission or ordinary factory.
Restoring a default never retires its mapping, module or process-lived aliases.
"""
from __future__ import annotations

from ctypes import PyDLL, byref, c_void_p
from os import getpid
from threading import Thread, current_thread
from typing import Any, Callable, NoReturn

from ._local_initial_preparation import _OriginalPythonPreparation
from ._local_native_initial_abi import bind
from ._local_native_shim_abi import bind as bind_control


class _PythonNativeInitialPending(RuntimeError):
    def __init__(self, original: _OriginalPythonNativeInitial) -> None:
        self.cleanup_native_initial = original
        super().__init__('Original Python Native startup or default restoration is unconfirmed')


class _PythonNativeInitialFunctions:
    """ABI binding only; the existing assembly must verify/load the component."""
    def __init__(self, library: PyDLL) -> None:
        if type(library) is not PyDLL:
            raise TypeError('Selected Python Native calls must retain the original GIL')
        self.library = library
        self.begin = bind(library, 'actql_native_python_initial_platform_begin_into')
        self.current = bind(library, 'actql_native_python_initial_platform_current')
        self.restore = bind(library, 'actql_native_python_initial_platform_restore')


class _OriginalPythonNativeInitial:
    __slots__ = ('_original', '_initial', '_functions', '_process', '_thread',
                 '_slot', '_pending', '_unknown', '_busy', '_restored', '_issue',
                 '_call_failed', '_normal_refused', '_runtime_slot',
                 '_runtime_attempted', '_runtime_ready', '_runtime_initialize',
                 '_runtime_current')
    _original: _OriginalPythonNativeInitial
    _initial: _OriginalPythonPreparation
    _functions: _PythonNativeInitialFunctions
    _process: int
    _thread: Thread
    _slot: c_void_p
    _pending: _PythonNativeInitialPending
    _unknown: bool
    _busy: bool
    _restored: bool
    _issue: int | None
    _call_failed: bool
    _normal_refused: bool
    _runtime_slot: c_void_p
    _runtime_attempted: bool
    _runtime_ready: bool
    _runtime_initialize: Callable[[Any], int] | None
    _runtime_current: Callable[[c_void_p], int] | None

    @classmethod
    def prepare(cls, initial: _OriginalPythonPreparation,
                functions: _PythonNativeInitialFunctions) -> _OriginalPythonNativeInitial:
        if (type(initial) is not _OriginalPythonPreparation
                or type(functions) is not _PythonNativeInitialFunctions):
            raise TypeError('Original Python Native startup inputs are unavailable')
        initial.require_current()
        original = cls.__new__(cls)
        original._original = original
        original._initial, original._functions = initial, functions
        original._process, original._thread = getpid(), current_thread()
        original._slot = c_void_p()
        # This same Runtime out-slot must exist before a Moon initializer can
        # publish an original, including a failure or lost Python reply.
        original._runtime_slot = c_void_p()
        original._runtime_attempted = original._runtime_ready = False
        original._runtime_initialize = original._runtime_current = None
        original._unknown = original._busy = original._restored = False
        original._normal_refused = original._call_failed = False
        original._issue = None
        # Allocate the error/slot carrier before the physical entry can publish
        # a mapping or partial default. Never replace it after reply loss.
        original._pending = _PythonNativeInitialPending(original)
        initial.begin_native_attempt()
        original._busy = True
        try:
            result = functions.begin(byref(original._slot))
            if type(result) is not int or not original._slot.value:
                original._unknown = True
                raise original._pending
            original._issue = result
            if result != 0 or original._unknown or original._call_failed:
                raise original._pending
        except BaseException as failure:
            if failure is not original._pending:
                original._unknown = True
                raise original._pending from failure
            raise
        finally:
            original._busy = False
        return original

    def _require_receiver(self) -> None:
        if (self._original is not self or self._process != getpid()
                or self._thread is not current_thread()):
            raise ValueError('Foreign original Python Native startup')
        if self._busy:
            self._unknown = True
            self._call_failed = True
            raise self._pending

    def require_current(self) -> None:
        self._require_receiver()
        self._busy, self._call_failed = True, False
        try:
            self._initial.require_cleanup_service()
            if (self._unknown or self._restored or self._normal_refused
                    or self._issue != 0 or not self._slot.value):
                raise self._pending
            self._initial.require_service_current()
            if not self._functions.current(self._slot) or self._call_failed:
                raise self._pending
        except BaseException as failure:
            self._normal_refused = True
            if failure is not self._pending:
                raise self._pending from failure
            raise
        finally:
            self._busy = False

    def restore_default(self) -> None:
        self._require_receiver()
        self._busy, self._call_failed = True, False
        try:
            self._initial.require_cleanup_service()
            if self._restored:
                return
            if not self._slot.value:
                raise self._pending
            result = self._functions.restore(self._slot)
            if type(result) is not int or result != 1 or self._call_failed:
                raise self._pending
            self._restored = True
        except BaseException as failure:
            if failure is not self._pending:
                self._unknown = True
                raise self._pending from failure
            raise
        finally:
            self._busy = False

    def initialize_control(self) -> None:
        """Enter the existing same-component Moon initializer exactly once.

        The selected Native entry must already be current. This supplies no
        Host, parent, Ledger, Worker or VM; those acquisitions remain separate.
        A returned Runtime remains process-lived and is never reissued here.
        """
        self._require_receiver()
        if self._runtime_attempted:
            raise ValueError('Original Python control initialization was already attempted')
        self.require_current()
        # Resolve the existing generated ABI before spending the physical
        # attempt. Both calls retain exactly the same already selected PyDLL.
        initialize = bind_control(self._functions.library, 'actql_control_runtime_initialize_into')
        current = bind_control(self._functions.library, 'actql_control_runtime_current')
        self._runtime_initialize, self._runtime_current = initialize, current
        self._runtime_attempted = True
        self._busy, self._call_failed = True, False
        try:
            result = initialize(byref(self._runtime_slot))
            if (type(result) is not int or result != 0 or not self._runtime_slot.value
                    or self._call_failed or self._unknown):
                raise self._pending
            self._runtime_ready = True
        except BaseException as failure:
            self._unknown = True
            if failure is not self._pending:
                raise self._pending from failure
            raise
        finally:
            self._busy = False

    def require_control_current(self) -> None:
        """Observe the same initialized Runtime without minting an original."""
        self._require_receiver()
        self.require_current()
        if (not self._runtime_ready or self._runtime_current is None
                or not self._runtime_slot.value):
            raise ValueError('Original Python control initialization is unavailable')
        self._busy, self._call_failed = True, False
        try:
            result = self._runtime_current(self._runtime_slot)
            if type(result) is not int or result != 0 or self._call_failed:
                raise self._pending
        except BaseException as failure:
            self._normal_refused = True
            if failure is not self._pending:
                raise self._pending from failure
            raise
        finally:
            self._busy = False

    def __copy__(self) -> NoReturn:
        raise TypeError('Original Python Native startup cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original Python Native startup cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Python Native startup cannot be serialized')
