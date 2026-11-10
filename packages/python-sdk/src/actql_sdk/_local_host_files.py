"""Original Host file/Store physical pins; Core decides adoption and authority."""
from dataclasses import dataclass
from collections.abc import Callable
from threading import RLock
from typing import TYPE_CHECKING

from ._local_files import (
    LocalFileRoot, LocalOriginalAcquisitionError, PhysicalFileSnapshot, _OriginalFileReader,
)
from ._local_storage import LocalByteStore

if TYPE_CHECKING:
    from ._local_installation import OriginalLocalInstallation


@dataclass(frozen=True, slots=True, eq=False)
class _HostFile:
    owner: object
    name: str
    body: bytes
    snapshot: PhysicalFileSnapshot
    reader: _OriginalFileReader


class LocalHostFilesCleanupPending(RuntimeError):
    def __init__(self, cleanup_files: 'LocalHostFiles') -> None:
        super().__init__('Original Local Host file cleanup is pending')
        self.cleanup_files = cleanup_files


class LocalHostFiles:
    """Retain original saved descriptors and exact Store generation.

    The trusted installed assembly reserves simultaneous Python/Core transfer
    and retained-byte workspace before using this port. Limits below bound raw
    holding only; they are not a global memory guarantee. This object performs
    no initialization, JSON interpretation, CID construction, adoption, scope
    issuance, Account decision, Run execution or recovery transition.
    """

    def __init__(self, root: LocalFileRoot, store: LocalByteStore, *,
                 max_files: int, max_bytes: int,
                 observe_roots: Callable[[], None] | None = None,
                 _installation: 'OriginalLocalInstallation | None' = None) -> None:
        if (type(root) is not LocalFileRoot or type(store) is not LocalByteStore
                or type(max_files) is not int or not 1 <= max_files <= 9
                or type(max_bytes) is not int or not 1 <= max_bytes <= 2097152
                or observe_roots is not None and not callable(observe_roots)):
            raise ValueError('Invalid original Local Host physical pins')
        if _installation is not None:
            from ._local_installation import OriginalLocalInstallation
            if (type(_installation) is not OriginalLocalInstallation
                    or _installation._original is not _installation
                    or _installation._closing or observe_roots is not None):
                raise ValueError('Invalid original Local installation file provenance')
        root._open()
        self._lock = RLock()
        self._original = self
        self._identity = object()
        self._root = root
        self._store = store
        self._observe_roots = observe_roots
        self._installation = _installation
        self._generation = store.observe_generation()
        self._max_files = max_files
        self._max_bytes = max_bytes
        self._bytes = 0
        self._files: dict[str, _HostFile] = {}
        self._pending: dict[int, _OriginalFileReader] = {}
        self._closing = False

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied or foreign original Local Host file pins')

    def read_original(self, name: str, *, max_bytes: int) -> _HostFile:
        """Pin one Core-selected saved name without replacing or repairing it."""
        with self._lock:
            self._nominal()
            if (self._closing or self._pending or name in self._files
                    or len(self._files) >= self._max_files):
                raise ValueError('Original Local Host pins are pending, closing or exhausted')
            if (type(max_bytes) is not int or not 0 <= max_bytes <= 1048576
                    or max_bytes > self._max_bytes - self._bytes):
                raise ValueError('Original Local Host holding exceeds its reserved bound')
            try:
                reader = self._root.open_original(name, max_bytes=max_bytes)
            except LocalOriginalAcquisitionError as failure:
                self._pending[id(failure.original_reader)] = failure.original_reader
                raise LocalHostFilesCleanupPending(self) from failure
            self._pending[id(reader)] = reader
            try:
                # Reserve one finite destination before any chunk copy. The
                # Host's workspace includes this and the resulting exact bytes.
                destination = bytearray(max_bytes)
                offset = 0
                while True:
                    chunk = self._root.read_original(reader)
                    if offset + len(chunk.data) > max_bytes:
                        raise ValueError('Original Local Host read exceeds its bound')
                    destination[offset:offset + len(chunk.data)] = chunk.data
                    offset += len(chunk.data)
                    eof = chunk.eof
                    self._root.release_original_chunk(reader, chunk)
                    if eof:
                        break
                observed = self._root.observe_original(reader)
                body = bytes(memoryview(destination)[:offset])
                value = _HostFile(self._identity, name, body, observed, reader)
                self._files[name] = value
                self._bytes += len(body)
                del self._pending[id(reader)]
                self.current()
                return value
            except BaseException as failure:
                # Both pre-transfer failures and post-transfer current failures
                # retain the original descriptor/bytes for explicit cleanup.
                raise LocalHostFilesCleanupPending(self) from failure

    def original_bytes(self, value: _HostFile) -> bytes:
        with self._lock:
            self._nominal()
            self._require_original(value)
            self.current()
            return value.body

    def _require_original(self, value: _HostFile) -> None:
        if (type(value) is not _HostFile or value.owner is not self._identity
                or self._files.get(value.name) is not value):
            raise ValueError('Copied, foreign or retired original Local Host file')

    def _require_original_members(self, values: tuple[_HostFile, ...]) -> None:
        self._nominal()
        if len(values) > self._max_files:
            raise ValueError('Original Local Host member bound exceeded')
        for value in values:
            self._require_original(value)

    def require_current_originals(self, values: tuple[_HostFile, ...]) -> None:
        """Check the original members and observe the complete group once.

        This returns no bytes, permission or reusable currentness token. Every
        invocation still observes all retained files, Store and root originals.
        """
        with self._lock:
            self._require_original_members(values)
            self.current()

    def _require_current_lifetime(self) -> None:
        self._nominal()
        if self._closing or self._pending:
            raise ValueError('Original Local Host physical current is unavailable')
        self._root._open()

    def _observe_current_files(self) -> None:
        if self._store.observe_generation() != self._generation:
            raise ValueError('Original Local Host Store generation changed')
        originals = tuple(self._files.values())
        observed = self._root._observe_originals(tuple(value.reader for value in originals))
        for value, snapshot in zip(originals, observed, strict=True):
            if snapshot is not value.snapshot and snapshot != value.snapshot:
                raise ValueError('Original Local Host saved file changed')

    def current(self) -> None:
        """Observe physical originals only, never return a permission boolean."""
        with self._lock:
            self._require_current_lifetime()
            if self._installation is not None:
                self._installation._observe_roots()
            if self._observe_roots is not None and self._observe_roots() is not None:
                raise ValueError('Original Local root observation cannot return permission')
            self._observe_current_files()

    def close(self) -> bool:
        """Retire file pins only; preserve Store, named originals and Run custody."""
        with self._lock:
            self._nominal()
            self._closing = True
            for key, reader in tuple(self._pending.items()):
                if not self._root.close_original(reader):
                    return False
                del self._pending[key]
            for name, value in tuple(self._files.items()):
                if not self._root.close_original(value.reader):
                    return False
                self._bytes -= len(value.body)
                del self._files[name]
            return True


# Definition-time provenance for the fixed original reconciliation driver.
from ._local_prepare_provenance import _capture_prepare_methods
_PREPARE_METHODS = (
    _capture_prepare_methods(LocalHostFiles, (
        '_nominal', '_observe_current_files', '_require_current_lifetime',
        '_require_original', '_require_original_members', 'current',
        'require_current_originals',
    )),
)
