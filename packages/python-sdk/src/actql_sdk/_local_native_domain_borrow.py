"""Same-provider child mapping custody, never funding or worker admission.

The trusted installed bootstrap must validate original Core child/loan/current
and durable launch facts, and fund independent process/control/FD overhead,
before this private physical port. Material DATA is not that authorization.
"""
from __future__ import annotations

from contextlib import contextmanager
from collections.abc import Iterator
from ctypes import Array, POINTER, byref, c_int, c_int64, c_size_t, c_ubyte, c_uint64, c_void_p, alignment, cast
from os import getpid
from threading import Thread, current_thread
from typing import Any, NoReturn

from ._local_native_domain_custody import _OriginalDomainMaterial
from ._local_worker_slot import _OriginalDescriptor


class _OriginalDomainBorrowError(RuntimeError):
    def __init__(self, borrow: _OriginalDomainBorrow, *, unknown: bool, code: int | None = None) -> None:
        self.cleanup_borrow, self.unknown, self.code = borrow, unknown, code
        super().__init__('Original child domain operation is unconfirmed' if unknown
                         else 'Original child domain operation was refused')


class _OriginalDomainBorrowFunctions:
    """Only binds the selected original provider; never loads a DLL/fallback."""
    def __init__(self, library: Any) -> None:
        self.library = library
        self.size = library.actql_native_domain_borrow_storage_bytes
        self.align = library.actql_native_domain_borrow_storage_alignment
        for call in (self.size, self.align):
            call.argtypes = []
            call.restype = c_size_t
        self.open = library.actql_native_domain_borrow_open
        self.open.argtypes = [c_void_p, c_size_t, c_int, POINTER(c_ubyte), POINTER(c_int64)]
        self.open.restype = c_int
        self.status = library.actql_native_domain_borrow_status
        self.enter = library.actql_native_domain_borrow_enter
        self.leave = library.actql_native_domain_borrow_leave
        self.close = library.actql_native_domain_borrow_close
        for call in (self.status, self.enter, self.leave, self.close):
            call.argtypes = [c_void_p]
            call.restype = c_int
        self.pointer = library.actql_native_domain_borrow_pointer
        self.pointer.argtypes = [c_void_p, POINTER(c_void_p)]
        self.pointer.restype = c_int
        self.claim = library.actql_native_domain_borrow_claim_holding
        self.close_holding = library.actql_native_domain_borrow_close_holding
        for call in (self.claim, self.close_holding):
            call.argtypes = [c_void_p, POINTER(c_void_p)]
            call.restype = c_int
        self.transfer = library.actql_native_domain_borrow_transfer_holding
        self.transfer.argtypes = [c_void_p, c_void_p, c_uint64, POINTER(c_ubyte)]
        self.transfer.restype = c_int
        self.capacity = library.actql_native_domain_borrow_capacity
        self.capacity.argtypes = [c_void_p, POINTER(c_uint64)]
        self.capacity.restype = c_int
        self.contains = library.actql_native_domain_borrow_contains_live_span
        self.contains.argtypes = [c_void_p, c_void_p, c_size_t]
        self.contains.restype = c_int


class _OriginalDomainBorrow:
    """One physical C record. Known cleanup retries never reopen or reborrow.

    The caller-owned control record remains separate from the payload's capacity.
    A bounded metadata allocation is not proof of complete pre-spawn funding.
    Python stores no quota, Run state, stop conclusion or cleanup retry queue.
    """
    _original: _OriginalDomainBorrow
    _functions: _OriginalDomainBorrowFunctions
    _descriptor: _OriginalDescriptor
    _material: _OriginalDomainMaterial
    _storage: Array[c_uint64]
    _pointer: c_void_p
    _process: int
    _thread: Thread
    _busy: bool
    _closed: bool
    _closing: bool
    _unknown: _OriginalDomainBorrowError | None
    _unknown_carrier: _OriginalDomainBorrowError
    _holding_consumer: object | None

    @classmethod
    def _map_original(cls, functions: _OriginalDomainBorrowFunctions,
                      descriptor: _OriginalDescriptor, material: _OriginalDomainMaterial) -> _OriginalDomainBorrow:
        if (type(functions) is not _OriginalDomainBorrowFunctions
                or type(descriptor) is not _OriginalDescriptor or descriptor._original is not descriptor
                or descriptor.closed or descriptor.close_attempted or type(descriptor.value) is not int
                or not 0 <= descriptor.value <= 2**31 - 1 or type(material) is not _OriginalDomainMaterial
                or type(material.recipe) is not bytes or len(material.recipe) != 32
                or type(material.scalars) is not tuple or len(material.scalars) != 15
                or any(type(v) is not int or not 0 <= v <= 2**63 - 1 for v in material.scalars)):
            raise ValueError('Original child domain physical inputs are unavailable')
        size, align = functions.size(), functions.align()
        # This is the existing bounded control-copy quantum, not an adopted
        # memory profile or extra capacity. The verified component defines ABI.
        if (type(size) is not int or not 0 < size <= 65536
                or type(align) is not int or not 0 < align <= alignment(c_uint64)
                or alignment(c_uint64) % align != 0):
            raise ValueError('Original child domain record ABI is unavailable')
        borrow = cls()
        borrow._original = borrow
        borrow._functions, borrow._descriptor, borrow._material = functions, descriptor, material
        borrow._storage = (c_uint64 * ((size + 7) // 8))()
        borrow._pointer = cast(borrow._storage, c_void_p)
        borrow._process, borrow._thread = getpid(), current_thread()
        borrow._busy, borrow._closed, borrow._closing = False, False, False
        borrow._unknown = None
        borrow._holding_consumer = None
        borrow._unknown_carrier = _OriginalDomainBorrowError(borrow, unknown=True)
        recipe, values = (c_ubyte * 32).from_buffer_copy(material.recipe), (c_int64 * 15)(*material.scalars)
        borrow._begin()
        known: _OriginalDomainBorrowError | None = None
        try:
            code = functions.open(borrow._pointer, size, descriptor.value, recipe, values)
            if type(code) is not int:
                raise borrow._mark_unknown()
            if code != 0:
                known = _OriginalDomainBorrowError(borrow, unknown=False, code=code)
                raise known
            return borrow
        except BaseException as error:
            if error is known or error is borrow._unknown:
                raise
            raise borrow._mark_unknown() from error
        finally:
            borrow._busy = False

    def __copy__(self) -> NoReturn:
        raise TypeError('Original child domain borrow cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original child domain borrow cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original child domain borrow cannot be serialized')

    def _mark_unknown(self) -> _OriginalDomainBorrowError:
        if self._unknown is None:
            self._unknown = self._unknown_carrier
        return self._unknown

    def _begin(self) -> None:
        if (self._original is not self or self._process != getpid()
                or self._thread is not current_thread() or self._busy):
            raise ValueError('Foreign or active original child domain borrow')
        if self._unknown is not None:
            raise self._unknown
        self._busy = True

    def _call(self, operation: str) -> None:
        self._begin()
        if self._closed:
            self._busy = False
            if operation == 'close':
                return
            raise ValueError('Original child domain borrow is retired')
        if self._closing and operation not in ('leave', 'close'):
            self._busy = False
            raise ValueError('Original child domain borrow is closing')
        known: _OriginalDomainBorrowError | None = None
        try:
            if operation == 'close':
                self._closing = True
            call = {'status': self._functions.status, 'enter': self._functions.enter,
                    'leave': self._functions.leave, 'close': self._functions.close}[operation]
            code = call(self._pointer)
            if type(code) is not int:
                raise self._mark_unknown()
            if code != 0:
                known = _OriginalDomainBorrowError(self, unknown=False, code=code)
                raise known
            if operation == 'close':
                self._closed = True
        except BaseException as error:
            if error is known or error is self._unknown:
                raise
            raise self._mark_unknown() from error
        finally:
            self._busy = False

    def require_physical_current(self) -> None:
        """Physical record only; this is not Core current or Run authorization."""
        self._call('status')

    @contextmanager
    def _scope(self, *, _consumer: object | None = None) -> Iterator[None]:
        if self._holding_consumer is not None and self._holding_consumer is not _consumer:
            raise ValueError('Original child domain borrow belongs to its holding')
        self._call('enter')
        try:
            yield
        except BaseException as primary:
            try:
                self._call('leave')
            except BaseException as cleanup:
                raise cleanup from primary
            raise
        else:
            self._call('leave')

    def close(self) -> None:
        """Retire original map/borrow only; never FD/process/Owner/Run ACK."""
        if self._holding_consumer is not None:
            raise ValueError('Original child domain borrow belongs to its holding')
        self._call('close')

    def _claim_holding(self, consumer: object, slot: c_void_p) -> None:
        self._begin()
        if self._closed or self._closing or self._holding_consumer is not None or slot.value is not None:
            self._busy = False
            raise ValueError('Original child domain holding is unavailable')
        self._holding_consumer = consumer
        try:
            self._check_code(self._functions.claim(self._pointer, byref(slot)))
            if slot.value is None:
                raise self._mark_unknown()
        except _OriginalDomainBorrowError:
            raise
        except BaseException as error:
            raise self._mark_unknown() from error
        finally:
            self._busy = False

    def _check_code(self, code: Any) -> None:
        if type(code) is not int:
            raise self._mark_unknown()
        if code != 0:
            raise _OriginalDomainBorrowError(self, unknown=False, code=code)

    def _holding_identity(self, consumer: object) -> None:
        if self._holding_consumer is not consumer:
            raise ValueError('Foreign original child domain holding')

    def _transfer_holding(self, consumer: object, slot: c_void_p, generation: int, recipe: bytes) -> None:
        self._holding_identity(consumer)
        self._begin()
        try:
            self._check_code(self._functions.transfer(self._pointer, slot, generation,
                (c_ubyte * 32).from_buffer_copy(recipe)))
        except _OriginalDomainBorrowError:
            raise
        except BaseException as error:
            raise self._mark_unknown() from error
        finally:
            self._busy = False

    def _close_holding_slot(self, consumer: object, slot: Any) -> int:
        self._holding_identity(consumer)
        self._begin()
        self._closing = True
        try:
            original = cast(slot, POINTER(c_void_p))[0]
            code = self._functions.close_holding(self._pointer, slot)
            current = cast(slot, POINTER(c_void_p))[0]
            if type(code) is not int or (code == 0 and current is not None) or (code != 0 and current != original):
                raise self._mark_unknown()
            self._check_code(code)
            self._closed = True
            return 0
        except _OriginalDomainBorrowError as error:
            if not error.unknown and error.code is not None:
                return error.code
            raise
        except BaseException as error:
            raise self._mark_unknown() from error
        finally:
            self._busy = False

    def _holding_capacity(self, consumer: object) -> int:
        self._holding_identity(consumer)
        self._begin()
        try:
            value = c_uint64()
            self._check_code(self._functions.capacity(self._pointer, byref(value)))
            return value.value
        except _OriginalDomainBorrowError:
            raise
        except BaseException as error:
            raise self._mark_unknown() from error
        finally:
            self._busy = False

    def _holding_contains(self, consumer: object, address: c_void_p, size: int) -> None:
        self._holding_identity(consumer)
        self._begin()
        try:
            self._check_code(self._functions.contains(self._pointer, address, size))
        except _OriginalDomainBorrowError:
            raise
        except BaseException as error:
            raise self._mark_unknown() from error
        finally:
            self._busy = False

    @contextmanager
    def _holding_scope(self, consumer: object) -> Iterator[None]:
        self._holding_identity(consumer)
        with self._scope(_consumer=consumer):
            yield
