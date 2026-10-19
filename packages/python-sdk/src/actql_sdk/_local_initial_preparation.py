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
                 '_state_dir', '_state_dir_bytes')

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
        if (self._original is not self or self._retired
                or self._process != os.getpid() or self._thread is not current_thread()
                or self._build != (sys.version, sys.implementation.cache_tag, sys.abiflags,
                       sys.getfilesystemencoding(), sys.getfilesystemencodeerrors())
                or self._interpreter != _interpreter()
                or self._allocators != _allocator_snapshot()):
            raise ValueError('Foreign or retired original Python preparation')
        if self._failure is not None:
            raise _PythonPreparationPending(self) from self._failure

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
        if (self._original is not self or self._process != os.getpid()
                or self._thread is not current_thread()
                or self._interpreter != _interpreter()):
            raise ValueError('Foreign original Python preparation')
        self._state_dir = self._state_dir_bytes = None
        self._retired = True
