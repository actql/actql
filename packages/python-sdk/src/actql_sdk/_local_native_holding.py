"""Retirement of an original native holding; no capacity or Run decisions.

The trusted bootstrap supplier must obtain the genuine native pointer first.
This adapter neither loads a DLL nor acquires/adopts an allocator or profile.
"""
from __future__ import annotations

from ctypes import byref, c_int, c_void_p, c_uint64, c_ubyte, c_size_t, POINTER
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any


class NativeHoldingRetirementError(RuntimeError):
    """Original holding remains owned; this is not successful cleanup or ACK."""

    def __init__(self, code: int | None) -> None:
        self.code = code
        super().__init__('Native Local holding retirement failed or is unconfirmed')


class NativeHoldingScopeError(RuntimeError):
    """An unconfirmed native call scope; never successful cleanup or ACK."""

    def __init__(self, operation: str, code: int | None) -> None:
        self.operation, self.code = operation, code
        super().__init__(f'Native Local holding {operation} failed or is unconfirmed')


class NativeHoldingTransferError(RuntimeError):
    """Physical transfer is denied or unknown, never an Engine or Run permission."""

    def __init__(self, code: int | None) -> None:
        self.code = code
        super().__init__('Original native holding transfer failed or is unconfirmed')


class NativeHoldingObservationError(RuntimeError):
    """Physical observation was denied or unknown; no capacity/Run conclusion."""

    def __init__(self, operation: str, code: int | None) -> None:
        self.operation, self.code = operation, code
        super().__init__(f'Original native holding {operation} is unavailable or unconfirmed')


class _NativeHoldingLease:
    """Private owner of a previously acquired opaque native holding pointer.

    Construction is for the trusted installed supplier, not a public input.
    The exact selected library must implement the original try_close contract:
    failure preserves its mapping, success clears the passed pointer slot.
    No Python ledger, quota, cleanup scheduler or Root is created here.
    """

    __slots__ = ('_pointer', '_try_close', '_library', '_core_identity',
                 '_generation', '_recipe', '_transfer_attempted')

    def __init__(self, pointer: c_void_p, library: Any, *, generation: int, recipe: bytes) -> None:
        if type(pointer) is not c_void_p or pointer.value is None:
            raise ValueError('Unavailable original native holding')
        if (type(generation) is not int or not 0 < generation <= 2**64 - 1
                or type(recipe) is not bytes or len(recipe) != 32):
            raise ValueError('Invalid original native holding acquisition context')
        retire = library.actql_owned_try_close
        retire.argtypes = [POINTER(c_void_p)]
        retire.restype = c_int
        # Retain the same loaded library as long as its native pointer exists.
        self._library = library
        self._pointer = c_void_p(pointer.value)
        self._try_close = retire
        self._core_identity: object | None = None
        # These are the original acquire supplier's facts. Do not derive them
        # from SDK input, a new random epoch, a current config or permission.
        self._generation, self._recipe = generation, recipe
        self._transfer_attempted = False
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

    def _transfer_to_core(self, identity: object) -> None:
        """Observe the original native transfer once, after Core takes custody."""
        if (identity is not self._core_identity or self._pointer.value is None
                or self._transfer_attempted):
            raise ValueError('Original native holding transfer is unavailable')
        self._transfer_attempted = True
        transfer = self._library.actql_owned_transfer
        transfer.argtypes = [c_void_p, c_uint64, POINTER(c_ubyte)]
        transfer.restype = c_int
        recipe = (c_ubyte * 32).from_buffer_copy(self._recipe)
        code = transfer(self._pointer, self._generation, recipe)
        if type(code) is not int or code != 0:
            raise NativeHoldingTransferError(code if type(code) is int else None)

    def _verify_library(self, library: Any) -> None:
        if library is not self._library:
            raise ValueError('Native Local holding and runtime library differ')

    def _capacity_bytes(self) -> int:
        if self._pointer.value is None:
            raise ValueError('Original native holding is retired')
        inspect = self._library.actql_owned_capacity_bytes
        inspect.argtypes = [c_void_p, POINTER(c_uint64)]
        inspect.restype = c_int
        observed = c_uint64()
        code = inspect(self._pointer, byref(observed))
        if (type(code) is not int or code != 0
                or not 0 < observed.value <= 2**63 - 1):
            raise NativeHoldingObservationError('capacity', code if type(code) is int else None)
        return observed.value

    def _require_live_span(self, address: c_void_p, length: int) -> None:
        if (type(address) is not c_void_p or address.value is None
                or type(length) is not int or not 0 < length <= 2**63 - 1):
            raise ValueError('Invalid original native span observation')
        contains = self._library.actql_owned_contains_live_span
        contains.argtypes = [c_void_p, c_void_p, c_size_t]
        contains.restype = c_int
        with self._scope():
            code = contains(self._pointer, address, length)
        if type(code) is not int or code != 0:
            raise NativeHoldingObservationError('span', code if type(code) is int else None)

    @contextmanager
    def _scope(self) -> Iterator[None]:
        """Use native TLS ownership; do not infer or mirror native scope state."""
        if self._pointer.value is None:
            raise ValueError('Original native holding is retired')
        enter = self._library.actql_owned_enter
        leave = self._library.actql_owned_leave
        for function in (enter, leave):
            function.argtypes = [c_void_p]
            function.restype = c_int
        code = enter(self._pointer)
        if type(code) is not int or code != 0:
            raise NativeHoldingScopeError('enter', code if type(code) is int else None)
        try:
            yield
        finally:
            code = leave(self._pointer)
            if type(code) is not int or code != 0:
                raise NativeHoldingScopeError('leave', code if type(code) is int else None)

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
