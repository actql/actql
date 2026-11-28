"""Physical response to one paid Local CSV offer from the original Core."""
from collections.abc import Callable
import json
from pathlib import Path
from struct import Struct

from ._local_project_files import OriginalLocalProjectFiles

_OFFER_BYTES = 65536
_RESPONSE = Struct('<iii')
_COMPLETE = 0
_FAILED_KNOWN = 1
_FAILED_UNKNOWN = 2
_EXTENT = 3


def _offer(wire: bytes) -> tuple[Path, str, int]:
    def fields(pairs: list[tuple[str, object]]) -> dict[str, object]:
        result: dict[str, object] = {}
        for key, value in pairs:
            if key in result:
                raise ValueError('Duplicate Local CSV offer field')
            result[key] = value
        return result

    if type(wire) is not bytes or not 0 < len(wire) <= _OFFER_BYTES:
        raise ValueError('Invalid Local CSV offer size')
    offer = json.loads(wire.decode('utf-8'), object_pairs_hook=fields)
    if type(offer) is not dict or set(offer) != {'root', 'path', 'max_bytes'}:
        raise ValueError('Invalid Local CSV offer fields')
    root, relative, maximum = offer['root'], offer['path'], offer['max_bytes']
    if (type(root) is not str or type(relative) is not str
            or type(maximum) is not int or not 0 < maximum < 2**31):
        raise ValueError('Invalid Local CSV offer path or bound')
    # Check the wire spelling before pathlib normalizes it.
    directory = Path(root)
    if not directory.is_absolute() or str(directory) != root:
        raise ValueError('Invalid Local CSV offer root')
    return directory, relative, maximum


class _LocalCsvTransfer:
    """Keep the single physical reader for the same kind-14 stop callback.

    The caller passes the held kind-20 output, retains this child before
    reading, and funds the physical buffers and kind-21 input on that Run.
    The reader uses the already adopted Project and the caller's current check.
    """

    def __init__(self, files: OriginalLocalProjectFiles, offer_handle: int, offer_wire: bytes,
                 *, max_path_bytes: int, max_depth: int, require_current: Callable[[], None]) -> None:
        if type(offer_handle) is not int or not 0 < offer_handle < 2**31:
            raise ValueError('Invalid original Local CSV offer handle')
        root, relative, self._max_bytes = _offer(offer_wire)
        self._lock = files._core._lock
        self._reader = files.prepare_source(root, relative, max_bytes=self._max_bytes,
            max_path_bytes=max_path_bytes, max_depth=max_depth, require_current=require_current)
        self._original, self._offer_handle = self, offer_handle
        self._extent_attempted = self._attempted = self._failed = self._stopping = False
        self._observed_bytes: int | None = None

    @property
    def max_bytes(self) -> int:
        return self._max_bytes

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign or copied Local CSV transfer')

    def extent_packet(self) -> tuple[int, bytes]:
        """Observe the selected file before reserving its raw transfer."""
        with self._lock:
            self._nominal()
            if self._extent_attempted or self._attempted or self._stopping:
                raise ValueError('Original Local CSV extent is unavailable')
            self._extent_attempted = True
            try:
                extent = self._reader.observe_size()
                return extent, _RESPONSE.pack(self._offer_handle, _EXTENT, extent)
            except Exception:
                self._observed_bytes = 0
                self._failed = True
                raise
            except BaseException:
                self._failed = True
                raise

    def read_packet(self) -> bytes:
        """Read once and return a complete packet after the file's final fence."""
        with self._lock:
            self._nominal()
            if self._attempted or self._stopping:
                raise ValueError('Original Local CSV transfer is unavailable')
            self._attempted = True
            body: bytes | None = None

            def retain(data: bytes) -> None:
                nonlocal body
                body = data

            try:
                self._reader.read_into(retain)
                if body is None:
                    raise RuntimeError('Original Local CSV reader returned no body')
                return _RESPONSE.pack(self._offer_handle, _COMPLETE, len(body)) + body
            except Exception:
                # The synchronous reader counts only bytes returned by OS reads.
                self._observed_bytes = self._reader.received_bytes
                self._failed = True
                raise
            except BaseException:
                # An asynchronous interruption can precede the byte observation.
                self._failed = True
                raise

    def failure_packet(self) -> bytes:
        """Account for the original failure without delivering bytes or retrying."""
        with self._lock:
            self._nominal()
            if not self._failed or self._stopping:
                raise ValueError('Original Local CSV failure is unavailable')
            self._failed = False
            count = self._observed_bytes
            if count is None:
                return _RESPONSE.pack(self._offer_handle, _FAILED_UNKNOWN, 0)
            return _RESPONSE.pack(self._offer_handle, _FAILED_KNOWN, count)

    def close(self) -> bool:
        with self._lock:
            self._nominal()
            self._stopping = True
            return self._reader.close()
