"""Retirement of an original native holding; no capacity or Run decisions.

The trusted bootstrap supplier must obtain the genuine native pointer first.
This adapter neither loads a DLL nor acquires/adopts an allocator or profile.
"""
from __future__ import annotations

from ._local_native_memory_abi import bind as bind_memory

from ctypes import byref, c_int, c_void_p, c_uint64, c_ubyte, c_size_t, POINTER
from collections.abc import Iterator
from contextlib import contextmanager
from typing import Any, TYPE_CHECKING

if TYPE_CHECKING:
    from ._local_native_domain_borrow import _OriginalDomainBorrow
    from ._local_engine import _InstalledImageFileInput, _InstalledImageInput


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


class NativeHoldingInitializationError(RuntimeError):
    """Retain this same partially bound holding, not another domain claim."""
    def __init__(self, holding: _NativeHoldingLease) -> None:
        self.cleanup_holding = holding
        super().__init__('Original native holding binding failed or is unconfirmed')


class _NativeHoldingLease:
    """Private owner of a previously acquired opaque native holding pointer.

    Construction is for the trusted installed supplier, not a public input.
    The exact selected library must implement the original try_close contract:
    failure preserves its mapping, success clears the passed pointer slot.
    No Python ledger, quota, cleanup scheduler or Root is created here.
    """

    __slots__ = ('_pointer', '_try_close', '_library', '_core_identity',
                 '_generation', '_recipe', '_transfer_attempted',
                 '_close_failure', '_close_inflight', '_borrow', '_prefix')

    _borrow: _OriginalDomainBorrow | None

    def __init__(self, pointer: c_void_p, library: Any, *, generation: int, recipe: bytes) -> None:
        self._initialize_original(pointer, library, generation, recipe, 'actql_owned_')

    @classmethod
    def _from_native_provider(cls, pointer: c_void_p, library: Any, *,
                              generation: int, recipe: bytes) -> _NativeHoldingLease:
        """Move a trusted supplier's already acquired direct-provider slot.

        This does not load, acquire or grant anything. Unlike the historical
        Rust-forwarder entry, it can retain/enter the C holding before the
        dependent Rust DLL is imported. Both paths use the same C provider.
        """
        holding = cls.__new__(cls)
        holding._initialize_original(pointer, library, generation, recipe, 'actql_native_owned_')
        return holding

    def _initialize_original(self, pointer: c_void_p, library: Any, generation: int,
                             recipe: bytes, prefix: str) -> None:
        if type(pointer) is not c_void_p or pointer.value is None:
            raise ValueError('Unavailable original native holding')
        if (type(generation) is not int or not 0 < generation <= 2**64 - 1
                or type(recipe) is not bytes or len(recipe) != 32):
            raise ValueError('Invalid original native holding acquisition context')
        retire = bind_memory(library, prefix + 'try_close')
        # Retain the same loaded library as long as its native pointer exists.
        self._library = library
        self._pointer = c_void_p(pointer.value)
        self._try_close = retire
        self._core_identity: object | None = None
        # These are the original acquire supplier's facts. Do not derive them
        # from SDK input, a new random epoch, a current config or permission.
        self._generation, self._recipe = generation, recipe
        self._transfer_attempted = False
        self._close_failure: BaseException | None = None
        self._close_inflight = False
        self._borrow = None
        self._prefix = prefix
        # Move the trusted supplier's owning slot exactly once. A second wrapper
        # cannot consume that same slot. Arbitrary raw pointers are not trusted.
        pointer.value = None

    @classmethod
    def _from_original_borrow(cls, borrow: _OriginalDomainBorrow) -> _NativeHoldingLease:
        """Reuse one same-provider physical borrow. No acquire/profile/grant."""
        from ._local_native_domain_borrow import _OriginalDomainBorrow
        if type(borrow) is not _OriginalDomainBorrow or borrow._holding_consumer is not None:
            raise ValueError('Original child domain borrow is unavailable')
        holding = cls.__new__(cls)
        holding._pointer, holding._library = c_void_p(), borrow._functions.library
        holding._core_identity = None
        holding._generation, holding._recipe = borrow._material.scalars[0], borrow._material.recipe
        holding._transfer_attempted = False
        holding._close_failure, holding._close_inflight = None, False
        holding._borrow = borrow
        holding._prefix = ''  # Borrowed calls use the original typed borrow port.
        holding._try_close = holding._close_borrowed_slot
        failure = NativeHoldingInitializationError(holding)
        try:
            borrow._claim_holding(holding, holding._pointer)
        except BaseException as error:
            raise failure from error
        return holding

    def _close_borrowed_slot(self, slot: Any) -> int:
        assert self._borrow is not None
        return self._borrow._close_holding_slot(self, slot)

    def __copy__(self) -> _NativeHoldingLease:
        raise TypeError('Original native holding cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _NativeHoldingLease:
        raise TypeError('Original native holding cannot be copied')

    def _bind_core(self, identity: object) -> None:
        self._require_confirmed_retirement_state()
        if self._core_identity is not None or self._pointer.value is None:
            raise ValueError('Original native holding was already transferred or retired')
        self._core_identity = identity

    def _transfer_to_core(self, identity: object) -> None:
        """Observe the original native transfer once, after Core takes custody."""
        self._require_confirmed_retirement_state()
        if (identity is not self._core_identity or self._pointer.value is None
                or self._transfer_attempted):
            raise ValueError('Original native holding transfer is unavailable')
        self._transfer_attempted = True
        if self._borrow is not None:
            self._borrow._transfer_holding(self, self._pointer, self._generation, self._recipe)
            return
        transfer = bind_memory(self._library, self._prefix + 'transfer')
        recipe = (c_ubyte * 32).from_buffer_copy(self._recipe)
        code = transfer(self._pointer, self._generation, recipe)
        if type(code) is not int or code != 0:
            raise NativeHoldingTransferError(code if type(code) is int else None)

    def _verify_library(self, library: Any, *,
                        _installed_image: _InstalledImageFileInput | _InstalledImageInput | None = None,
                        _initialization_files: Any = None) -> None:
        self._require_confirmed_retirement_state()
        if library is self._library:
            return
        # Native control and Wasmtime are deliberately separate selected DLLs.
        # Only an installed original image may use the same provider imported
        # by that runtime. Raw diagnostics never obtain this from a name/Bool.
        from ._local_engine import _InstalledImageFileInput, _verify_original_provider_link
        if type(_installed_image) is not _InstalledImageFileInput:
            raise ValueError('Native Local holding and runtime library differ')
        if self._pointer.value is None:
            raise ValueError('Original native holding is retired')
        original = self._library
        if _initialization_files is None:
            _verify_original_provider_link(_installed_image, library, original)
        else:
            _verify_original_provider_link(_installed_image, library, original,
                                           _initialization_files=_initialization_files)
        self._require_confirmed_retirement_state()
        if self._library is not original or self._pointer.value is None:
            raise ValueError('Original native holding changed during provider verification')

    def _capacity_bytes(self) -> int:
        self._require_confirmed_retirement_state()
        if self._pointer.value is None:
            raise ValueError('Original native holding is retired')
        if self._borrow is not None:
            value = self._borrow._holding_capacity(self)
            if not 0 < value <= 2**63 - 1:
                raise NativeHoldingObservationError('capacity', None)
            return value
        inspect = bind_memory(self._library, self._prefix + 'capacity_bytes')
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
        if self._borrow is not None:
            with self._scope():
                self._borrow._holding_contains(self, address, length)
            return
        contains = bind_memory(self._library, self._prefix + 'contains_live_span')
        with self._scope():
            code = contains(self._pointer, address, length)
        if type(code) is not int or code != 0:
            raise NativeHoldingObservationError('span', code if type(code) is int else None)

    def _original_span_offset(self, address: c_void_p, length: int) -> int:
        """Original borrowed payload only, never an address-based supplier."""
        self._require_confirmed_retirement_state()
        if self._borrow is None or not self._transfer_attempted or self._pointer.value is None:
            raise ValueError('Original child domain span is unavailable')
        with self._scope():
            return self._borrow._holding_span_offset(self, self._pointer, address, length)

    @contextmanager
    def _scope(self) -> Iterator[None]:
        """Use native TLS ownership; do not infer or mirror native scope state."""
        self._require_confirmed_retirement_state()
        if self._pointer.value is None:
            raise ValueError('Original native holding is retired')
        if self._borrow is not None:
            with self._borrow._holding_scope(self):
                yield
            return
        enter = bind_memory(self._library, self._prefix + 'enter')
        leave = bind_memory(self._library, self._prefix + 'leave')
        code = enter(self._pointer)
        if type(code) is not int or code != 0:
            raise NativeHoldingScopeError('enter', code if type(code) is int else None)
        try:
            yield
        finally:
            code = leave(self._pointer)
            if type(code) is not int or code != 0:
                raise NativeHoldingScopeError('leave', code if type(code) is int else None)

    def _require_confirmed_retirement_state(self) -> None:
        if self._close_failure is not None:
            # Keep the original issue/cause, without retaining every previous
            # observer's frames for the lifetime of this Unknown holding.
            raise BaseException.with_traceback(self._close_failure, None)
        if self._close_inflight:
            raise NativeHoldingRetirementError(None)

    def close(self) -> None:
        self._require_confirmed_retirement_state()
        if self._pointer.value is None and (self._borrow is None or self._borrow._closed):
            return
        # Native close mutates this same retained slot. A lost return can leave
        # it NULL without an ACK; neither that NULL nor the old address permits
        # another physical close. A known nonzero reply with an unchanged slot
        # remains retryable under the original native contract.
        original = self._pointer.value
        self._close_inflight = True
        try:
            try:
                code = self._try_close(byref(self._pointer))
            except BaseException as cause:
                self._close_failure = cause
                raise
            if type(code) is int and code == 0 and self._pointer.value is None:
                return
            failure = NativeHoldingRetirementError(code if type(code) is int else None)
            if type(code) is not int or code == 0 or self._pointer.value != original:
                self._close_failure = failure
            raise failure
        finally:
            self._close_inflight = False
