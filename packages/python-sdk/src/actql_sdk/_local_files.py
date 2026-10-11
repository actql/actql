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


class _AllocationArea:
    __slots__ = ('parent', 'name', 'identity', 'creation_synced', 'directory', 'closing')

    def __init__(self, parent: 'LocalFileRoot', name: str) -> None:
        self.parent = parent
        self.name = name
        self.identity: PhysicalFileIdentity | None = None
        self.creation_synced = False
        self.directory: LocalFileRoot | None = None
        self.closing = False


class LocalAreaAcquisitionError(LocalFileError):
    def __init__(self, original_area: _AllocationArea) -> None:
        super().__init__('Local allocation area requires original custody or reconciliation')
        self.original_area = original_area


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
        self._areas: dict[int, _AllocationArea] = {}
        self._capacity_root: LocalFileRoot = self
        self._parent_area: _AllocationArea | None = None
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
        expected = PhysicalFileIdentity(metadata.st_dev, metadata.st_ino)
        self._identity: PhysicalFileIdentity | None = None
        self._descriptor = os.open(path.absolute(), os.O_RDONLY | os.O_DIRECTORY |
                                   os.O_CLOEXEC | os.O_NOFOLLOW)
        try:
            current = os.fstat(self._descriptor)
            self._identity = PhysicalFileIdentity(current.st_dev, current.st_ino)
            if (self._identity != expected
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

    def _nominal_root(self) -> None:
        if ((self._parent_area is None and self._capacity_root is not self)
                or (self._parent_area is not None and
                    (self._parent_area.directory is not self
                     or self._parent_area.parent is not self._capacity_root))):
            raise ValueError('Foreign or copied Local file root')

    def _open(self) -> int:
        self._nominal_root()
        if (not self._ready or self._closing or self._capacity_root._closing
                or self._descriptor is None):
            raise LocalFileError('Local file root is closing or unavailable')
        return self._descriptor

    def _owned(self, value: _PayloadFile) -> None:
        if (type(value) is not _PayloadFile or value.root is not self
                or self._files.get(id(value)) is not value):
            raise ValueError('Foreign, copied or retired Local file handle')

    def _observation_root(self) -> int:
        self._nominal_root()
        if not self._ready or self._descriptor is None or self._close_pending:
            raise LocalFileError('Original Local file root observation is unavailable')
        return self._descriptor

    def _used_slots(self) -> int:
        return len(self._files) + len(self._areas) + sum(
            len(area.directory._files) for area in self._areas.values()
            if area.directory is not None)

    def _owned_area(self, value: _AllocationArea) -> None:
        if (type(value) is not _AllocationArea or value.parent is not self
                or self._areas.get(id(value)) is not value):
            raise ValueError('Foreign, copied or retired Local allocation area')

    def create_area(self, name: str) -> _AllocationArea:
        """Exclusive private area after the Owner persisted its original intent.

        This port never chooses an ordinal or records a semantic allocation.
        Failed observation retains the original area without adopting a later
        pathname. Existing entries, including symlinks, are left untouched.
        """
        self._name(name)
        with self._lock:
            root = self._open()
            if self._parent_area is not None:
                raise LocalFileError('Nested Local allocation areas are unsupported')
            if self._used_slots() >= self._max_files:
                raise LocalFileError('Local file descriptor capacity exceeded')
            value = _AllocationArea(self, name)
            self._areas[id(value)] = value
            try:
                os.mkdir(name, 0o700, dir_fd=root)
            except FileExistsError:
                del self._areas[id(value)]
                raise
            except BaseException as original:
                # A lost acknowledgement is not permission to create again.
                raise LocalAreaAcquisitionError(value) from original
            try:
                current = os.stat(name, dir_fd=root, follow_symlinks=False)
                if (not stat.S_ISDIR(current.st_mode) or current.st_mode & 0o077
                        or current.st_uid != os.getuid()):
                    raise LocalFileError('Original Local allocation area facts changed')
                value.identity = PhysicalFileIdentity(current.st_dev, current.st_ino)
                self.sync_area_creation(value)
            except BaseException as original:
                raise LocalAreaAcquisitionError(value) from original
            return value

    def observe_area(self, value: _AllocationArea) -> PhysicalFileIdentity:
        """Recheck an already acquired identity; a name alone never supplies it."""
        with self._lock:
            self._owned_area(value)
            root = self._observation_root()
            if value.identity is None:
                raise LocalFileError('Original Local allocation identity is unknown')
            current = os.stat(value.name, dir_fd=root, follow_symlinks=False)
            if (not stat.S_ISDIR(current.st_mode) or current.st_mode & 0o077
                    or current.st_uid != os.getuid()
                    or PhysicalFileIdentity(current.st_dev, current.st_ino) != value.identity):
                raise LocalFileError('Original Local allocation name or identity changed')
            return value.identity

    def sync_area_creation(self, value: _AllocationArea) -> None:
        """Retry durability of the same acquired directory, without another mkdir."""
        with self._lock:
            self._owned_area(value)
            if value.closing:
                raise LocalFileError('Local allocation area is closing')
            self.observe_area(value)
            if not value.creation_synced:
                os.fsync(self._observation_root())
                value.creation_synced = True

    def open_area(self, value: _AllocationArea) -> 'LocalFileRoot':
        """Open the original area after its Owner durably recorded the identity.

        No Bool can stand in for that durable Owner confirmation. The assembly
        must enforce its original CAS before this physical operation.
        """
        with self._lock:
            root = self._open()
            self._owned_area(value)
            if value.closing or not value.creation_synced:
                raise LocalFileError('Original Local allocation area is pending or closing')
            self.observe_area(value)
            if value.directory is not None:
                # A failed first open remains this same handle; never reopen it.
                value.directory._open()
                if not value.directory._ready:
                    raise LocalFileError('Original Local allocation directory is pending')
                return value.directory
            child = LocalFileRoot.__new__(LocalFileRoot)
            child._lock = self._lock
            child._files = {}
            child._areas = {}
            child._capacity_root = self
            child._parent_area = value
            child._max_files = self._max_files
            child._max_chunk_bytes = self._max_chunk_bytes
            child._descriptor = None
            child._closing = False
            child._close_pending = False
            child._ready = False
            child._identity = None
            value.directory = child
            try:
                descriptor = os.open(value.name, os.O_RDONLY | os.O_DIRECTORY |
                                     os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=root)
                child._descriptor = descriptor
                current = os.fstat(descriptor)
                child._identity = PhysicalFileIdentity(current.st_dev, current.st_ino)
                if (not stat.S_ISDIR(current.st_mode) or current.st_mode & 0o077
                        or current.st_uid != os.getuid()
                        or PhysicalFileIdentity(current.st_dev, current.st_ino) != value.identity):
                    raise LocalFileError('Original Local allocation descriptor facts changed')
                fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
                child._ready = True
            except BaseException as original:
                raise LocalAreaAcquisitionError(value) from original
            return child

    def close_area(self, value: _AllocationArea) -> bool:
        """Retire physical handles only; never unlink or return disk capacity."""
        with self._lock:
            self._owned_area(value)
            value.closing = True
            # Unknown exclusive creation retains its original intent/custody.
            # A later pathname cannot repair the missing acquisition evidence.
            if value.identity is None:
                return False
            if value.directory is not None and not value.directory.close():
                return False
            del self._areas[id(value)]
            return True

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
            if self._capacity_root._used_slots() >= self._max_files:
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
            self._nominal_root()
            self._closing = True
            if self._files or self._areas:
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
