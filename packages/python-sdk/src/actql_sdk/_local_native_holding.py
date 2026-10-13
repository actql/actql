"""Retirement of an original native holding; no capacity or Run decisions.

The trusted bootstrap supplier must obtain the genuine native pointer first.
This adapter neither loads a DLL nor acquires/adopts an allocator or profile.
"""
from __future__ import annotations

from ctypes import byref, c_int, c_void_p, POINTER
from typing import Any


class NativeHoldingRetirementError(RuntimeError):
    """Original holding remains owned; this is not successful cleanup or ACK."""

    def __init__(self, code: int | None) -> None:
        self.code = code
        super().__init__('Native Local holding retirement failed or is unconfirmed')


class _NativeHoldingLease:
    """Private owner of a previously acquired opaque native holding pointer.

    Construction is for the trusted installed supplier, not a public input.
    The exact selected library must implement the original try_close contract:
    failure preserves its mapping, success clears the passed pointer slot.
    No Python ledger, quota, cleanup scheduler or Root is created here.
    """

    __slots__ = ('_pointer', '_try_close', '_library', '_core_identity')

    def __init__(self, pointer: c_void_p, library: Any) -> None:
        if type(pointer) is not c_void_p or pointer.value is None:
            raise ValueError('Unavailable original native holding')
        retire = library.actql_owned_try_close
        retire.argtypes = [POINTER(c_void_p)]
        retire.restype = c_int
        # Retain the same loaded library as long as its native pointer exists.
        self._library = library
        self._pointer = c_void_p(pointer.value)
        self._try_close = retire
        self._core_identity: object | None = None
        # Move the trusted supplier's owning slot exactly once. A second wrapper
        # cannot consume that same slot. Arbitrary raw pointers are not trusted.
        pointer.value = None

    def __copy__(self) -> _NativeHoldingLease:
        raise TypeError('Original native holding cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _NativeHoldingLease:
        raise TypeError('Original native holding cannot be copied')

    def _bind_core(self, identity: object) -> None:
        if self._core_identity is not None or self._pointer.value is None:
            raise ValueError('Original native holding was already transferred or retired')
        self._core_identity = identity

    def close(self) -> None:
        if self._pointer.value is None:
            return
        # The original slot is retained until both native success and the
        # expected cleared slot are observed. Exceptions/negative status do not
        # infer release, replace the holding or create a second native pointer.
        observed = c_void_p(self._pointer.value)
        code = self._try_close(byref(observed))
        if type(code) is not int or code != 0 or observed.value is not None:
            raise NativeHoldingRetirementError(code if type(code) is int else None)
        self._pointer = observed
