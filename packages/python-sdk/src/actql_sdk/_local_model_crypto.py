"""Physical AES-GCM for one original Python Local Model worker.

Core owns the private evidence format and the Call/Store decision. This child
owns the verified code image, its allocator, and the disjoint FFI byte buffers.
"""
from __future__ import annotations

import _ctypes
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from ctypes import (
    Array, CDLL, POINTER, RTLD_LOCAL, byref, c_size_t, c_uint, c_void_p,
    create_string_buffer, memset, string_at,
)
import mmap
import os
from struct import unpack_from
import sys
from threading import current_thread
from typing import TYPE_CHECKING

from ._local_distribution import (
    LocalComponentReadCleanupPending, LocalInstallationError, _MODEL_CRYPTO_MAXIMUM,
    _OriginalComponentFile,
)

if TYPE_CHECKING:
    from ctypes import _CFuncPtr, c_char

    from ._local_core import LocalCore, _Workspace
    from ._local_work import OriginalLocalWork

_ARENA_BYTES = 512 * 1024
_APPROVAL_ARENA_BYTES = 768 * 1024
_SIGNATURE_BYTES = 64
_SIGNATURE_MISMATCH = 6
_PACKET_OVERHEAD = 12 + 16
_MAX_PLAINTEXT = 1048576
_MAX_HEADER = 65536


def _crypto_control_bytes() -> int:
    # The handle class, two pointer types and three array types each hold a
    # ctypes type and dictionary. Include separate function instances,
    # their argument declarations, invocation cells and physical ownership.
    ctypes_type = max(sys.getsizeof(kind) for kind in (Array, c_size_t, c_uint, c_void_p))
    return 6 * 2 * ctypes_type + 4096


def _read_exact(fd: int, offset: int, size: int) -> bytes:
    value = os.pread(fd, size, offset)
    if len(value) != size:
        raise LocalInstallationError('Incomplete original Model crypto image geometry')
    return value


def _mapped_extent(fd: int, size: int) -> int:
    """Bound the actual admitted library segments before the dynamic load."""
    header = _read_exact(fd, 0, 64)
    page = mmap.PAGESIZE
    mapped = 0

    def charge(address: int, memory: int, offset: int, file: int) -> None:
        nonlocal mapped
        if file > memory or offset > size or file > size - offset:
            raise LocalInstallationError('Invalid original Model crypto load segment')
        if memory:
            mapped += (memory + address % page + page - 1) // page * page

    if sys.platform == 'darwin':
        magic, machine, _, file_type, count, extent = unpack_from('<6I', header)
        if (magic, machine, file_type) != (0xFEEDFACF, 0x0100000C, 6):
            raise LocalInstallationError('Invalid original Darwin Model crypto image')
        if not 0 < count <= 128 or not 0 < extent <= min(_MAX_HEADER, size - 32):
            raise LocalInstallationError('Invalid original Darwin Model crypto commands')
        commands = _read_exact(fd, 32, extent)
        index = 0
        for _ in range(count):
            if extent - index < 8:
                raise LocalInstallationError('Incomplete original Darwin Model crypto commands')
            command, length = unpack_from('<II', commands, index)
            if not 8 <= length <= extent - index:
                raise LocalInstallationError('Invalid original Darwin Model crypto command')
            if command == 0x19:  # LC_SEGMENT_64
                if length < 72:
                    raise LocalInstallationError('Incomplete original Darwin Model crypto segment')
                address, memory, offset, file = unpack_from('<4Q', commands, index + 24)
                charge(address, memory, offset, file)
            index += length
        if index != extent:
            raise LocalInstallationError('Original Darwin Model crypto commands changed')
    else:
        if (sys.platform != 'linux' or header[:7] != b'\x7fELF\x02\x01\x01'
                or unpack_from('<HH', header, 16) != (3, 62)):
            raise LocalInstallationError('Invalid original Linux Model crypto image')
        offset, = unpack_from('<Q', header, 32)
        width, count = unpack_from('<HH', header, 54)
        if (width != 56 or not 0 < count <= 128 or not 64 <= offset <= size
                or count * width > min(_MAX_HEADER, size - offset)):
            raise LocalInstallationError('Invalid original Linux Model crypto program table')
        commands = _read_exact(fd, offset, count * width)
        for index in range(0, len(commands), width):
            kind, = unpack_from('<I', commands, index)
            if kind == 1:  # PT_LOAD
                at, address, _, file, memory = unpack_from('<5Q', commands, index + 8)
                charge(address, memory, at, file)
    if not 0 < mapped <= _MODEL_CRYPTO_MAXIMUM:
        raise LocalInstallationError('Original Model crypto mapping exceeds its bounded profile')
    return mapped


class _OriginalPortableCrypto:
    """Retain one admitted mapped component and the original worker's arena."""

    def __init__(self, core: LocalCore, work: OriginalLocalWork | None) -> None:
        selected = getattr(core, '_installed_model_crypto', None)
        if selected is None:
            raise LocalInstallationError('Original Local crypto component is unavailable')
        if work is not None:
            work._nominal()
        scope = core._host_operation_scope if work is None else None
        if work is None and (scope is None or core._host_fuel_phase != 'operation'
                             or getattr(core, '_host_retained_work', None) is not None
                             or core._invoking):
            raise LocalInstallationError('Original Mock Review operation is unavailable')
        root, component = selected
        self._original = self
        self._core, self._work = core, work
        self._operation_scope = scope
        self._review_thread = current_thread() if work is None else None
        self._file = _OriginalComponentFile(
            root / component.file, expected=component.bytes, digest=component.sha256)
        self._workspace: _Workspace | None = None
        self._loader_workspace: _Workspace | None = None
        self._uncertain_ticket: int | None = None
        self._library: CDLL | None = None
        self._failed_reader: LocalComponentReadCleanupPending | None = None
        self._load_uncertain = False
        self._arena: Array[c_char] | None = None
        self._destination: Array[c_char] | None = None
        self._functions: tuple[_CFuncPtr, _CFuncPtr, _CFuncPtr] | None = None
        self._opened = self._has_custody = self._busy = False
        self._closing = self._close_attempted = self._unload_attempted = False
        self._inventory: tuple[int, ...] | None = None
        self._mapped = 0

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original Local crypto child')

    def _owner_thread(self) -> bool:
        thread = self._review_thread if self._work is None else self._work._thread
        return current_thread() is thread

    def _require_worker(self) -> None:
        self._nominal()
        if not self._owner_thread():
            raise ValueError('Foreign original evidence crypto thread')

    @contextmanager
    def _borrow_operation(self) -> Iterator[bool]:
        if self._work is not None:
            with self._core._borrow_work_operation(self._work) as retained:
                yield retained
            return
        core = self._core
        with core._lock:
            yield (self._operation_scope is not None and core._host_operation_scope is self._operation_scope
                   and core._host_fuel_phase == 'operation' and not core._invoking
                   and getattr(core, '_host_retained_work', None) is None
                   and not core._closing and not core._closed and not core._retired)

    def _reserve(self, amount: int, *, loader: bool = False) -> _Workspace:
        ticket = self._core._next_ticket
        try:
            return self._core.reserve_workspace(
                amount,
                stopped=(lambda: self._library is None and self._arena is None
                         if not loader else not self._busy),
                cleanup=lambda: True)
        except BaseException:
            if ticket in self._core._inputs or ticket in self._core._released:
                self._uncertain_ticket = ticket
            raise

    def _begin(self, *, profile: int, arena_bytes: int, output: int, retained: int,
               port: Callable[[CDLL], tuple[_CFuncPtr, _CFuncPtr]]) -> None:
        self._require_worker()
        core = self._core
        with self._borrow_operation() as retained:
            if not retained or self._opened or self._closing:
                raise LocalInstallationError('Original Local crypto acquisition is unavailable')
            self._opened = True
            # Two 64 KiB immutable read blocks may overlap during hashing.
            # Header/descriptor, ctypes control and geometry views are smaller.
            self._loader_workspace = self._reserve(2 * (_MAX_HEADER + sys.getsizeof(b'')) + 4096,
                                                   loader=True)
            try:
                self._file.read()
            except LocalComponentReadCleanupPending as failure:
                self._failed_reader = failure
                raise
            self._file.observe()
            source = self._file._source
            assert source is not None
            fd = source.value
            self._mapped = _mapped_extent(fd, self._file.expected)
            # The exact mapped image, cold allocator and one native output
            # overlap one immutable Python copy. Account for their controls.
            self._workspace = self._reserve(self._mapped + arena_bytes + 2 * output
                                            + sys.getsizeof(b'') + _crypto_control_bytes()
                                            + retained)
            name = f'/dev/fd/{fd}' if sys.platform == 'darwin' else f'/proc/self/fd/{fd}'
            # Keep this descriptor through dlclose. The loader never resolves
            # an independent path alias or an operator-supplied component.
            self._load_uncertain = True
            try:
                self._library = CDLL(name, mode=RTLD_LOCAL)
            except OSError:
                self._load_uncertain = False
                raise
            self._load_uncertain = False
            self._file.observe()
            self._arena = create_string_buffer(arena_bytes)
            self._destination = create_string_buffer(output)
            begin = self._library.actql_portable_crypto_begin
            first, second = port(self._library)
            close = self._library.actql_portable_crypto_close
            begin.argtypes = (c_void_p, c_size_t, c_uint, POINTER(c_uint))
            close.argtypes = (c_void_p, POINTER(c_size_t))
            self._functions = (first, second, close)
            custody = c_uint()
            try:
                code = begin(self._arena, arena_bytes, profile, byref(custody))
            finally:
                self._has_custody = custody.value == 1
            if code != 0 or not self._has_custody:
                raise LocalInstallationError('Original Local crypto allocator refused')
            if not core.close_workspace(self._loader_workspace):
                raise LocalInstallationError('Original Local crypto loader workspace is pending')
            self._loader_workspace = None

    def close(self) -> bool:
        self._nominal()
        core = self._core
        with core._lock:
            self._closing = True
            if (self._busy or self._load_uncertain
                    or self._failed_reader is not None):
                return False
            if self._has_custody:
                if not self._owner_thread() or self._close_attempted:
                    return False
                assert self._functions is not None and self._arena is not None
                observed = (c_size_t * 5)()
                self._close_attempted = True
                if self._functions[2](self._arena, observed) != 0:
                    return False
                self._inventory = tuple(observed)
                self._has_custody = False
            self._arena = self._destination = self._functions = None
            if self._library is not None:
                if self._unload_attempted:
                    return False
                self._unload_attempted = True
                _ctypes.dlclose(self._library._handle)
                self._library = None
            self._file.close()
            if self._uncertain_ticket is not None:
                if not core._retired or self._uncertain_ticket in core._inputs:
                    return False
                self._uncertain_ticket = None
            with core._host_cleanup():
                for name in ('_workspace', '_loader_workspace'):
                    loan = getattr(self, name)
                    if loan is None:
                        continue
                    if not core._retired and not core.close_workspace(loan):
                        return False
                    if core._retired and loan.ticket in core._inputs:
                        return False
                    setattr(self, name, None)
            return True


class _OriginalModelEvidenceCrypto(_OriginalPortableCrypto):
    """Use the admitted AES-GCM profile on the original physical Run worker."""

    def __init__(self, core: LocalCore, work: OriginalLocalWork | None, *,
                 policy: str, plaintext_limit: int) -> None:
        if (type(policy) is not str or policy != 'builtin-aes-256-gcm'
                or type(plaintext_limit) is not int or not 0 < plaintext_limit <= _MAX_PLAINTEXT):
            raise LocalInstallationError('Original Model crypto policy or component is unavailable')
        super().__init__(core, work)
        self._limit = plaintext_limit

    def begin(self) -> None:
        # The pre-Entry lease also includes the bounded Raw point key and digest
        # through this Call's settlement.
        self._begin(profile=1, arena_bytes=_ARENA_BYTES,
                    output=self._limit + _PACKET_OVERHEAD, retained=4096,
                    port=self._bind_aes_port)

    @staticmethod
    def _bind_aes_port(library: CDLL) -> tuple[_CFuncPtr, _CFuncPtr]:
        seal = library.actql_portable_crypto_seal
        open_ = library.actql_portable_crypto_open
        seal.argtypes = (c_void_p, c_void_p, c_size_t, c_void_p, c_size_t,
                         c_void_p, c_size_t, c_void_p, c_size_t)
        open_.argtypes = seal.argtypes
        return seal, open_

    def seal(self, key: bytes, aad: bytes, plaintext: bytes,
             consume: Callable[[bytes], None]) -> None:
        self._exchange(key, aad, plaintext, consume, authenticate=False)

    def authenticate(self, key: bytes, aad: bytes, ciphertext: bytes,
                     consume: Callable[[bytes], None]) -> None:
        self._exchange(key, aad, ciphertext, consume, authenticate=True)

    def _exchange(self, key: bytes, aad: bytes, data: bytes,
                  consume: Callable[[bytes], None], *, authenticate: bool) -> None:
        self._require_worker()
        count = len(data) if type(data) is bytes else 0
        result_bytes = count - _PACKET_OVERHEAD if authenticate else count + _PACKET_OVERHEAD
        plain_bytes = result_bytes if authenticate else count
        if (not self._has_custody or self._closing or self._busy or self._functions is None
                or self._arena is None or self._destination is None
                or type(key) is not bytes or len(key) != 32
                or type(aad) is not bytes or not 0 < len(aad) <= 512
                or not 0 < plain_bytes <= self._limit or not callable(consume)):
            raise ValueError('Original Model crypto input is unavailable or outside its bound')
        with self._borrow_operation() as retained:
            if not retained:
                raise ValueError('Original Model crypto operation is unavailable')
            self._file.observe()
            self._busy = True
            try:
                function = self._functions[int(authenticate)]
                if function(self._arena, key, len(key), aad, len(aad), data, count,
                            self._destination, result_bytes) != 0:
                    raise LocalInstallationError('Original Model evidence authentication failed')
                # The receiver must copy into its own admitted input if the
                # bytes outlive this call. No mutable buffer leaves the child.
                if consume(string_at(self._destination, result_bytes)) is not None:
                    raise ValueError('Invalid original Model crypto output consumer')
            finally:
                memset(self._destination, 0, result_bytes)
                self._busy = False


class _OriginalEffectSignatureCrypto(_OriginalPortableCrypto):
    """The bounded Ed25519 port for one original protected Effect decision."""

    def begin(self) -> None:
        self._begin(profile=3, arena_bytes=_APPROVAL_ARENA_BYTES,
                    output=_SIGNATURE_BYTES, retained=4096,
                    port=self._bind_signature_port)

    @staticmethod
    def _bind_signature_port(library: CDLL) -> tuple[_CFuncPtr, _CFuncPtr]:
        verify = library.actql_portable_crypto_verify_ed25519
        sign = library.actql_portable_crypto_sign_attestation
        verify.argtypes = (c_void_p, c_void_p, c_size_t, c_void_p, c_size_t,
                           c_void_p, c_size_t)
        sign.argtypes = verify.argtypes
        return verify, sign

    def verify_reviewer(self, public_key: bytes, cid: bytes, proof: bytes) -> bool:
        if type(proof) is not bytes or len(proof) != _SIGNATURE_BYTES:
            raise ValueError('Invalid original Reviewer proof extent')
        return self._exchange_signature(public_key, cid, proof, None)

    def sign_host_attestation(self, private_key: bytes, cid: bytes,
                              consume: Callable[[bytes], None]) -> None:
        if not callable(consume):
            raise TypeError('Invalid original Host attestation consumer')
        self._exchange_signature(private_key, cid, None, consume)

    def _exchange_signature(self, key: bytes, cid: bytes, proof: bytes | None,
                            consume: Callable[[bytes], None] | None) -> bool:
        self._require_worker()
        if (not self._has_custody or self._closing or self._busy or self._functions is None
                or self._arena is None or self._destination is None
                or type(key) is not bytes or len(key) != 32
                or type(cid) is not bytes or len(cid) != 71 or not cid.startswith(b'sha256:')
                or any(cid[index] not in b'0123456789abcdef' for index in range(7, 71))):
            raise ValueError('Invalid original Effect signature operation')
        signing = proof is None
        with self._borrow_operation() as retained:
            if not retained:
                raise ValueError('Original Effect signature operation is unavailable')
            self._file.observe()
            self._busy = True
            try:
                destination = self._destination if signing else proof
                function = self._functions[int(signing)]
                result = function(self._arena, key, len(key), cid, len(cid),
                                  destination, _SIGNATURE_BYTES)
                if result != 0 and (signing or result != _SIGNATURE_MISMATCH):
                    raise LocalInstallationError('Original Effect signature component failed')
                self._file.observe()
                if result == _SIGNATURE_MISMATCH:
                    return False
                if signing:
                    assert consume is not None
                    if consume(string_at(self._destination, _SIGNATURE_BYTES)) is not None:
                        raise ValueError('Invalid original Host attestation consumer')
                return True
            finally:
                if signing:
                    memset(self._destination, 0, _SIGNATURE_BYTES)
                self._busy = False
