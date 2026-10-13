"""Original native image extent custody; no image/allocator adoption or Run facts."""
from __future__ import annotations

from ctypes import byref, c_int, c_size_t, c_ubyte, c_uint8, c_void_p, cast, POINTER
import os
from typing import Any

from ._local_engine import _InstalledImageFileInput
from ._local_native_holding import _NativeHoldingLease


class NativeImageError(RuntimeError):
    """Original extent remains with its same Core for cleanup, never an ACK."""

    def __init__(self, operation: str, code: int | None) -> None:
        self.operation, self.code = operation, code
        super().__init__(f'Original native image {operation} failed or is unconfirmed')


class _NativeImageHolding:
    """An original lease child, registered by Core before native capture starts.

    Failed capture may publish a cleanup pointer. Retain that exact slot until
    native retirement succeeds. This object owns no Root, grants or capacity.
    """

    def __init__(self, lease: _NativeHoldingLease, image: _InstalledImageFileInput) -> None:
        if type(lease) is not _NativeHoldingLease or type(image) is not _InstalledImageFileInput:
            raise ValueError('Unavailable original native image custody')
        self._lease, self._image = lease, image
        self._pointer = c_void_p()
        self._attempted = False
        self._captured = False
        self._closing = False
        self._fd: int | None = None
        self._fd_close_failure: NativeImageError | None = None

    def __copy__(self) -> _NativeImageHolding:
        raise TypeError('Original native image cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _NativeImageHolding:
        raise TypeError('Original native image cannot be copied')

    def capture(self) -> None:
        if self._attempted or self._closing:
            raise ValueError('Original native image capture was already attempted')
        self._attempted = True
        image = self._image
        capture = self._lease._library.actql_owned_capture_image_fd
        capture.argtypes = [c_void_p, c_int, c_size_t, c_size_t,
                            POINTER(c_ubyte), POINTER(c_void_p)]
        capture.restype = c_int
        digest = (c_ubyte * 32).from_buffer_copy(bytes.fromhex(image.sha256))
        # The original native function checks readonly/regular/size/EOF/digest
        # and same-FD metadata. No Python whole-file read or ctypes image copy.
        self._fd = os.open(image.path, os.O_RDONLY | os.O_NOFOLLOW)
        primary: BaseException | None = None
        try:
            with self._lease._scope():
                code = capture(self._lease._pointer, self._fd, image.length,
                               image.recipe.image_bytes_limit, digest, byref(self._pointer))
            if type(code) is not int or code != 0 or self._pointer.value is None:
                raise NativeImageError('capture', code if type(code) is int else None)
        except BaseException as failure:
            primary = failure
            raise
        finally:
            try:
                self._close_original_fd()
            except BaseException:
                # Preserve the original capture failure. The same image still
                # retains its independent unconfirmed FD-close responsibility.
                if primary is None:
                    raise
        self._captured = True

    def _close_original_fd(self) -> None:
        if self._fd_close_failure is not None:
            # Unknown may already have consumed the descriptor. Its number can
            # name another file now; never close it again or infer retirement.
            # Reuse the same diagnostic without accumulating retry tracebacks.
            raise self._fd_close_failure.with_traceback(None)
        if self._fd is None:
            return
        # Publish Unknown before the physical call. Keep this same image/Core
        # and parent lease until the original FD close actually acknowledges.
        failure = NativeImageError('close_fd', None)
        self._fd_close_failure = failure
        try:
            os.close(self._fd)
        except BaseException as original:
            raise failure from original
        self._fd = None
        self._fd_close_failure = None

    def deserialize_into(self, engine: Any, module: Any, wasmtime: Any, ffi: Any) -> None:
        if not self._captured or self._closing or self._pointer.value is None:
            raise ValueError('Original native image is not available for deserialization')
        self._lease._verify_library(ffi.dll)
        pointer = POINTER(ffi.wasmtime_module_t)()
        # Core has already registered this original wrapper. Store the mutable
        # output slot before the C call, including an exceptional return/leave.
        # The pinned Managed wrapper owns that same slot, not a copied handle.
        module._set_ptr(pointer)
        try:
            with self._lease._scope():
                error = ffi.wasmtime_module_deserialize(engine.ptr(),
                    cast(self._pointer, POINTER(c_uint8)), self._image.length, byref(pointer))
        finally:
            if not pointer:
                # A null native output is not a module to delete. Preserve the
                # original wrapper but make its existing close a no-op.
                module._consume()
        if error:
            raise wasmtime.WasmtimeError._from_ptr(error)
        if not pointer:
            raise NativeImageError('deserialize', None)

    def close(self) -> None:
        self._closing = True
        self._close_original_fd()
        if self._pointer.value is None:
            return
        retire = self._lease._library.actql_owned_retire
        retire.argtypes = [c_void_p, c_void_p]
        retire.restype = c_int
        code = retire(self._lease._pointer, self._pointer)
        if type(code) is not int or code != 0:
            raise NativeImageError('retire', code if type(code) is int else None)
        self._pointer = c_void_p()
