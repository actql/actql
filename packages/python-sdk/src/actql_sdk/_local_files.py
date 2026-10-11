"""Private physical payload descriptors; Core owns publication and reclaim."""
from dataclasses import dataclass
import errno
import fcntl
import os
from pathlib import Path
import stat
from threading import RLock


@dataclass(frozen=True)
class PhysicalFileIdentity:
    device: int
    inode: int


@dataclass(frozen=True)
class PhysicalFileObservation:
    identity: PhysicalFileIdentity
    size: int


class LocalFileError(RuntimeError):
    """Physical failure, never Run outcome or permission to repeat I/O."""


class _PayloadFile:
    __slots__ = ('root', 'name', 'descriptor', 'identity', 'max_bytes', 'written',
                 'creation_synced', 'write_unknown', 'closing', 'close_pending')

    def __init__(self, root: object, name: str, descriptor: int, max_bytes: int) -> None:
        self.root = root
        self.name = name
        self.descriptor: int | None = descriptor
        self.identity: PhysicalFileIdentity | None = None
        self.max_bytes = max_bytes
        self.written = 0
        self.creation_synced = False
        self.write_unknown = False
        self.closing = False
        self.close_pending = False


class LocalFileAcquisitionError(LocalFileError):
    def __init__(self, original_file: _PayloadFile) -> None:
        super().__init__('Local file acquisition requires original handle observation or cleanup')
        self.original_file = original_file


class LocalFileInitializationError(LocalFileError):
    def __init__(self, original_root: 'LocalFileRoot') -> None:
        super().__init__('Local file root initialization cleanup is pending')
        self.original_root = original_root


class LocalFileRoot:
    """Exclusive private root and bounded descriptors for Core-selected names.

    The trusted Host reserves its Python/OS workspace and disk capacity before
    calling this port. No method grants publication, seals a Core payload or
    deletes a file. Closing descriptors preserves all named bytes and durable
    reservations for the original Store Owner's separate reconciliation/reclaim.
    """

    def __init__(self, path: Path, *, max_files: int, max_chunk_bytes: int) -> None:
        if (type(max_files) is not int or not 1 <= max_files <= 1024
                or type(max_chunk_bytes) is not int or not 1 <= max_chunk_bytes <= 65536):
            raise ValueError('Invalid Local file descriptor limits')
        self._lock = RLock()
        self._files: dict[int, _PayloadFile] = {}
        self._max_files = max_files
        self._max_chunk_bytes = max_chunk_bytes
        self._descriptor: int | None = None
        self._closing = False
        self._close_pending = False
        self._ready = False
        metadata = path.absolute().lstat()
        if (not stat.S_ISDIR(metadata.st_mode) or metadata.st_mode & 0o077
                or metadata.st_uid != os.getuid()):
            raise LocalFileError('Local file root requires a private owned directory')
        self._identity = PhysicalFileIdentity(metadata.st_dev, metadata.st_ino)
        self._descriptor = os.open(path.absolute(), os.O_RDONLY | os.O_DIRECTORY |
                                   os.O_CLOEXEC | os.O_NOFOLLOW)
        try:
            current = os.fstat(self._descriptor)
            if (PhysicalFileIdentity(current.st_dev, current.st_ino) != self._identity
                    or not stat.S_ISDIR(current.st_mode) or current.st_mode & 0o077
                    or current.st_uid != os.getuid()):
                raise LocalFileError('Local file root identity changed')
            # Match the existing Store's exclusive physical ownership boundary.
            # This lock is not a credential, namespace publication or Core authority.
            fcntl.flock(self._descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
            self._ready = True
        except BaseException as original:
            if not self.close():
                raise LocalFileInitializationError(self) from original
            raise

    @staticmethod
    def _name(name: str) -> None:
        if (type(name) is not str or not 1 <= len(name) <= 128
                or name in ('.', '..')
                or any(c not in 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._'
                       for c in name)):
            raise ValueError('Invalid Core-selected Local payload name')

    def _open(self) -> int:
        if not self._ready or self._closing or self._descriptor is None:
            raise LocalFileError('Local file root is closing or unavailable')
        return self._descriptor

    def _owned(self, value: _PayloadFile) -> None:
        if (type(value) is not _PayloadFile or value.root is not self
                or self._files.get(id(value)) is not value):
            raise ValueError('Foreign, copied or retired Local file handle')

    def _observation_root(self) -> int:
        if not self._ready or self._descriptor is None or self._close_pending:
            raise LocalFileError('Original Local file root observation is unavailable')
        return self._descriptor

    def create_writer(self, name: str, max_bytes: int) -> _PayloadFile:
        """One exclusive acquisition, registered before any fallible observation.

        After an error the caller keeps the attached original handle; inspecting
        a pathname or repeating creation cannot replace its acquisition fact.
        """
        self._name(name)
        if type(max_bytes) is not int or not 0 <= max_bytes < 2**63:
            raise ValueError('Invalid original Local payload byte limit')
        with self._lock:
            root = self._open()
            if len(self._files) >= self._max_files:
                raise LocalFileError('Local file descriptor capacity exceeded')
            descriptor = os.open(name, os.O_RDWR | os.O_CREAT | os.O_EXCL |
                                 os.O_CLOEXEC | os.O_NOFOLLOW, 0o600, dir_fd=root)
            value = _PayloadFile(self, name, descriptor, max_bytes)
            self._files[id(value)] = value
            try:
                self.observe(value)
                self.sync_creation(value)
            except BaseException as original:
                raise LocalFileAcquisitionError(value) from original
            return value

    def observe(self, value: _PayloadFile) -> PhysicalFileObservation:
        """Actual original descriptor facts; neither persistence nor a retry grant."""
        with self._lock:
            self._owned(value)
            if value.descriptor is None or value.close_pending:
                raise LocalFileError('Local file descriptor observation is unavailable')
            current = os.fstat(value.descriptor)
            identity = PhysicalFileIdentity(current.st_dev, current.st_ino)
            if (not stat.S_ISREG(current.st_mode) or current.st_uid != os.getuid()
                    or current.st_mode & 0o077 or current.st_size > value.max_bytes
                    or value.identity is not None and identity != value.identity):
                raise LocalFileError('Original Local file descriptor facts changed')
            if value.identity is None:
                if current.st_size != 0:
                    raise LocalFileError('New Local payload file is not empty')
                value.identity = identity
            return PhysicalFileObservation(identity, current.st_size)

    def sync_creation(self, value: _PayloadFile) -> None:
        """Retry directory durability on the same acquired handle, without create."""
        with self._lock:
            self._owned(value)
            root = self._observation_root()
            if value.closing or value.descriptor is None or value.identity is None:
                raise LocalFileError('Original Local file acquisition is pending')
            if value.creation_synced:
                return
            current = os.stat(value.name, dir_fd=root, follow_symlinks=False)
            if (not stat.S_ISREG(current.st_mode)
                    or PhysicalFileIdentity(current.st_dev, current.st_ino) != value.identity):
                raise LocalFileError('Original Local file name changed before durability')
            os.fsync(root)
            value.creation_synced = True

    def append(self, value: _PayloadFile, expected_offset: int, data: bytes) -> int:
        """One bounded physical write; return a short write without repeating it."""
        if (type(expected_offset) is not int or expected_offset < 0 or type(data) is not bytes
                or not 1 <= len(data) <= self._max_chunk_bytes):
            raise ValueError('Invalid bounded Local file write')
        with self._lock:
            self._owned(value)
            self._open()
            if (value.closing or value.write_unknown or not value.creation_synced
                    or value.descriptor is None):
                raise LocalFileError('Original Local file write is unavailable or unknown')
            observed = self.observe(value)
            if (expected_offset != value.written or observed.size != expected_offset
                    or expected_offset + len(data) > value.max_bytes
                    or os.lseek(value.descriptor, 0, os.SEEK_CUR) != expected_offset):
                raise LocalFileError('Original Local file offset or byte capacity changed')
            try:
                written = os.write(value.descriptor, data)
                if not 0 <= written <= len(data):
                    raise LocalFileError('Invalid Local physical write count')
            except BaseException:
                value.write_unknown = True
                raise
            value.written += written
            return written

    def sync(self, value: _PayloadFile) -> PhysicalFileObservation:
        """Flush original bytes; the existing Core Owner must still seal them."""
        with self._lock:
            self._owned(value)
            self._observation_root()
            if value.closing or value.write_unknown or value.descriptor is None:
                raise LocalFileError('Original Local file cannot be confirmed from an unknown write')
            observed = self.observe(value)
            if observed.size != value.written:
                raise LocalFileError('Original Local file physical size changed')
            os.fsync(value.descriptor)
            return self.observe(value)

    @staticmethod
    def _closed_after_uncertainty(descriptor: int, identity: PhysicalFileIdentity | None) -> bool | None:
        try:
            current = os.fstat(descriptor)
        except OSError as error:
            if error.errno == errno.EBADF:
                return True
            raise
        # A recycled descriptor is not the original handle. Never close it.
        if identity is not None and PhysicalFileIdentity(current.st_dev, current.st_ino) != identity:
            return True
        # Equal device/inode does not prove the same open-file description: a
        # recycled descriptor can reopen the original file. Keep it unknown.
        return None

    def close_writer(self, value: _PayloadFile) -> bool:
        """Stop this descriptor only; retain bytes/capacity for the Store Owner."""
        with self._lock:
            self._owned(value)
            value.closing = True
            if value.descriptor is not None:
                if value.close_pending:
                    try:
                        closed = self._closed_after_uncertainty(value.descriptor, value.identity)
                    except OSError:
                        return False
                    if closed is None:
                        return False
                    if closed:
                        value.descriptor = None
                if value.descriptor is not None:
                    try:
                        os.close(value.descriptor)
                    except OSError:
                        value.close_pending = True
                        return False
                    value.descriptor = None
            del self._files[id(value)]
            return True

    def close(self) -> bool:
        """Close the root only after every original descriptor has retired."""
        with self._lock:
            self._closing = True
            if self._files:
                return False
            if self._descriptor is None:
                return True
            if self._close_pending:
                try:
                    closed = self._closed_after_uncertainty(self._descriptor, self._identity)
                    if closed is None:
                        return False
                    if closed:
                        self._descriptor = None
                        return True
                except OSError:
                    return False
            try:
                os.close(self._descriptor)
            except OSError:
                self._close_pending = True
                return False
            self._descriptor = None
            return True
