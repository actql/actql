"""Selected CPython startup controls, separate from backed worker funding.

The stdlib binding prelude and this bounded input operation use the original
interpreter allocator service. This is not a reservation, Native supplier,
whole SDK import envelope or an installed worker/Engine admission.
"""
from __future__ import annotations

import ctypes
import os
import sys
from threading import current_thread
from typing import NoReturn


class _Allocator(ctypes.Structure):
    # Selected CPython 3.12 PyMemAllocatorEx; callbacks are observed, never called
    # through guessed signatures, replaced or used to free Python objects.
    _fields_ = [('ctx', ctypes.c_void_p), ('malloc', ctypes.c_void_p),
                ('calloc', ctypes.c_void_p), ('realloc', ctypes.c_void_p),
                ('free', ctypes.c_void_p)]


def _allocator_snapshot() -> tuple[tuple[int | None, ...], ...]:
    # Independent typed wrappers avoid mutating ctypes.pythonapi's shared
    # argtypes/restype. PYFUNCTYPE keeps the original interpreter's GIL held.
    read = ctypes.PYFUNCTYPE(None, ctypes.c_int, ctypes.POINTER(_Allocator))(
        ('PyMem_GetAllocator', ctypes.pythonapi))
    result = []
    for domain in (0, 1, 2):  # Selected CPython RAW, MEM and OBJ domains.
        value = _Allocator()
        read(domain, ctypes.byref(value))
        if not all((value.malloc, value.calloc, value.realloc, value.free)):
            raise RuntimeError('Original CPython allocator service is unavailable')
        result.append((value.ctx, value.malloc, value.calloc, value.realloc, value.free))
    return tuple(result)


def _interpreter() -> int:
    value = ctypes.PYFUNCTYPE(ctypes.c_void_p)(
        ('PyInterpreterState_Get', ctypes.pythonapi))()
    if type(value) is not int or value == 0:
        raise RuntimeError('Original CPython interpreter is unavailable')
    return value


class _PythonPreparationPending(RuntimeError):
    def __init__(self, original: _OriginalPythonPreparation) -> None:
        self.cleanup_preparation = original
        super().__init__('Original Python startup input is unconfirmed')


class _OriginalPythonPreparation:
    """Actual interpreter-bound initial input custody, never capacity credit.

    Every state directory copy goes through this same current service. The
    retained original text and encoded bytes are bounded together. Retiring
    this input does not retire shared modules, allocator pools or the process.
    """
    __slots__ = ('_original', '_process', '_thread', '_interpreter', '_build',
                 '_allocators', '_attempted', '_retired', '_failure',
                 '_state_dir', '_state_dir_bytes', '_adopted', '_native_attempted')

    def __init__(self) -> None:
        if (sys.implementation.name != 'cpython'
                or sys.version_info[:3] != (3, 12, 12)
                or sys.getfilesystemencoding() != 'utf-8'
                or sys.getfilesystemencodeerrors() != 'surrogateescape'):
            raise RuntimeError('Selected Python initial preparation is unavailable')
        self._original = self
        self._process, self._thread = os.getpid(), current_thread()
        self._interpreter = _interpreter()
        self._build = (sys.version, sys.implementation.cache_tag, sys.abiflags,
                       sys.getfilesystemencoding(), sys.getfilesystemencodeerrors())
        self._allocators = _allocator_snapshot()
        self._attempted = self._retired = False
        self._adopted = False
        self._native_attempted = False
        self._failure: BaseException | None = None
        self._state_dir: str | None = None
        self._state_dir_bytes: bytes | None = None

    def __copy__(self) -> NoReturn:
        raise TypeError('Original Python preparation cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original Python preparation cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original Python preparation cannot be serialized')

    def require_current(self) -> None:
        if self._retired:
            raise ValueError('Retired original Python preparation input')
        self.require_service_current()

    def require_service_current(self) -> None:
        # Input DATA retirement neither retires nor reissues this service or
        # the separate Native original retained by its startup caller.
        if (self._original is not self
                or self._process != os.getpid() or self._thread is not current_thread()
                or self._build != (sys.version, sys.implementation.cache_tag, sys.abiflags,
                       sys.getfilesystemencoding(), sys.getfilesystemencodeerrors())
                or self._interpreter != _interpreter()
                or self._allocators != _allocator_snapshot()):
            raise ValueError('Foreign or retired original Python preparation')
        if self._failure is not None:
            raise _PythonPreparationPending(self) from self._failure

    def begin_native_attempt(self) -> None:
        self.require_current()
        if self._native_attempted:
            raise ValueError('Original Python Native startup was already attempted')
        self._native_attempted = True

    def require_cleanup_service(self) -> None:
        # No fresh allocator observation or normal-current recovery is needed
        # to restore the same Native default after a partial/failed startup.
        if (self._original is not self or self._process != os.getpid()
                or self._thread is not current_thread()
                or self._interpreter != _interpreter()):
            raise ValueError('Foreign original Python preparation')

    def capture_state_dir(self, value: object) -> None:
        self.require_current()
        if self._attempted:
            raise ValueError('Original Python startup input was already attempted')
        # No PathLike callbacks or arbitrary reachable object graphs are copied.
        # Unsupported forms remain unavailable at this private startup entrance.
        if value is not None and (type(value) is not str
                or not 0 < len(value) <= 4096 or '\x00' in value):
            raise ValueError('Unsupported original Python startup directory')
        self._attempted = True
        self._state_dir = value
        try:
            if value is not None:
                # Exact str admits the immutable builtin codec receiver. Do
                # not route this original through an ambient replaceable helper.
                encoded = value.encode('utf-8', 'surrogateescape')
                if not 0 < len(encoded) <= 4096:
                    raise ValueError('Original Python startup directory exceeds its byte bound')
                self._state_dir_bytes = encoded
            self.require_current()
        except BaseException as failure:
            self._failure = failure
            raise _PythonPreparationPending(self) from failure

    def retire_input(self) -> None:
        # This retires only this bounded DATA carrier. It is never a Native,
        # worker, descriptor, allocator-pool or interpreter retirement ACK.
        self.require_cleanup_service()
        self._state_dir = self._state_dir_bytes = None
        self._retired = True

    def adopt_captured_state_dir(self, value: str | os.PathLike[str] | None) -> None:
        """Adopt this same admitted input; never recopy or recapture a baseline."""
        self.require_current()
        if not self._attempted or self._state_dir is not value or self._adopted:
            raise ValueError('Foreign original Python startup input')
        self._adopted = True

    def retain_import_failure(self, failure: BaseException) -> None:
        """Spend normal preparation after a partial import, retaining its cause."""
        if (self._original is not self or self._retired or self._adopted
                or not self._attempted or self._process != os.getpid()
                or self._thread is not current_thread()):
            raise ValueError('Foreign original Python preparation import')
        # Retain an error even when normal current has become unavailable.
        # This neither invokes another CAPI binding nor acknowledges cleanup.
        if self._failure is None:
            self._failure = failure


def _capture_initial_preparation(
        state_dir: str | os.PathLike[str] | None) -> _OriginalPythonPreparation:
    """Establish the actual input service before the Local Host import graph.

    This bounded stdlib/CAPI binding prelude does not discover a distribution,
    load a Native component, reserve bytes or issue worker/VM funding.
    """
    from ._local_worker_funding import LocalWorkerFundingUnavailable
    initial: _OriginalPythonPreparation | None = None
    try:
        initial = _OriginalPythonPreparation()
        initial.capture_state_dir(state_dir)
    except Exception as failure:
        raise LocalWorkerFundingUnavailable(
            'Original Python initial preparation is unavailable',
            cleanup_preparation=initial) from failure
    return initial
