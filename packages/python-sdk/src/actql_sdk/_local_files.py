"""Private physical payload descriptors; Core owns publication and reclaim."""
from dataclasses import dataclass
import errno
import fcntl
import hashlib
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


@dataclass(frozen=True)
class PhysicalFileSnapshot:
    observation: PhysicalFileObservation
    physical_digest: str


class LocalFileError(RuntimeError):
    """Physical failure, never Run outcome or permission to repeat I/O."""


class _PayloadFile:
    __slots__ = ('root', 'name', 'descriptor', 'identity', 'max_bytes', 'written',
                 'creation_synced', 'write_unknown', 'closing', 'close_pending',
                 'write_stopped', 'snapshot', 'adoption', 'finalization')

    def __init__(self, root: 'LocalFileRoot', name: str, descriptor: int, max_bytes: int) -> None:
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
        self.write_stopped = False
        self.snapshot: _FileSnapshot | None = None
        self.adoption: _NameAdoption | None = None
        self.finalization: _FileFinalization | None = None


class _NameAdoption:
    """Original physical link/unlink work; never a Run or Recovery outcome."""

    __slots__ = ('origin', 'target', 'file', 'original_name', 'name', 'identity',
                 'size', 'linked', 'link_unknown', 'refused', 'source_removed',
                 'remove_unknown', 'complete')

    def __init__(self, origin: 'LocalFileRoot', target: 'LocalFileRoot',
                 value: _PayloadFile, name: str, observed: PhysicalFileObservation) -> None:
        self.origin = origin
        self.target = target
        self.file = value
        self.original_name = value.name
        self.name = name
        self.identity = observed.identity
        self.size = observed.size
        self.linked = False
        self.link_unknown = False
        self.refused = False
        self.source_removed = False
        self.remove_unknown = False
        self.complete = False


class _FileFinalization:
    """Original stopped-file name work; not a Core Sealed or Commit witness."""

    __slots__ = ('root', 'file', 'snapshot', 'original_name', 'name', 'stopped',
                 'linked', 'link_unknown', 'refused', 'source_removed',
                 'remove_unknown', 'final_stamp', 'result')

    def __init__(self, root: 'LocalFileRoot', value: _PayloadFile,
                 snapshot: '_FileSnapshot', name: str) -> None:
        self.root = root
        self.file = value
        self.snapshot = snapshot
        self.original_name = value.name
        self.name = name
        self.stopped = False
        self.linked = False
        self.link_unknown = False
        self.refused = False
        self.source_removed = False
        self.remove_unknown = False
        self.final_stamp: tuple[int, ...] | None = None
        self.result: PhysicalFileSnapshot | None = None


class _FileSnapshot:
    """One bounded observation of an original stopped physical descriptor."""

    __slots__ = ('file', 'stamp', 'offset', 'hash', 'invalid', 'result')

    def __init__(self, value: _PayloadFile, stamp: tuple[int, ...]) -> None:
        self.file = value
        self.stamp = stamp
        self.offset = 0
        self.hash = hashlib.sha256()
        self.invalid = False
        self.result: PhysicalFileSnapshot | None = None


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
        self._name_transfers: dict[int, _NameAdoption] = {}
        self._finalizations: dict[int, _FileFinalization] = {}
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
            child._name_transfers = {}
            child._finalizations = {}
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

    @staticmethod
    def _match_name(root: int, name: str, identity: PhysicalFileIdentity, size: int) -> None:
        named = os.stat(name, dir_fd=root, follow_symlinks=False)
        if (not stat.S_ISREG(named.st_mode) or named.st_uid != os.getuid()
                or named.st_mode & 0o077
                or PhysicalFileIdentity(named.st_dev, named.st_ino) != identity
                or named.st_size != size):
            raise LocalFileError('Original Local payload name generation changed')

    def _transfer_root(self) -> int:
        root = self._observation_root()
        if self._parent_area is not None:
            self._parent_area.parent.observe_area(self._parent_area)
        current = os.fstat(root)
        if (not stat.S_ISDIR(current.st_mode) or current.st_uid != os.getuid()
                or current.st_mode & 0o077
                or PhysicalFileIdentity(current.st_dev, current.st_ino) != self._identity):
            raise LocalFileError('Original Local name-transfer root changed')
        return root

    def begin_adoption(self, value: _PayloadFile, target: 'LocalFileRoot',
                       name: str) -> _NameAdoption:
        """Retain original name work before exclusive link I/O.

        The trusted Host must first persist original Core file ownership and
        select this name from that record, reserving cursor/OS workspace. Only
        roots under the same physical capacity/lock family participate. This
        method cannot select a Source, grant publisher permission or seal Core.
        """
        self._name(name)
        with self._lock:
            self._owned(value)
            self._open()
            if type(target) is not LocalFileRoot:
                raise ValueError('Invalid Local adoption target')
            target._nominal_root()
            if target._capacity_root is not self._capacity_root or target._lock is not self._lock:
                raise ValueError('Foreign Local adoption capacity family')
            target._open()
            if (value.closing or value.adoption is not None or value.finalization is not None
                    or value.write_unknown
                    or value.write_stopped or value.snapshot is not None
                    or not value.creation_synced or value.descriptor is None
                    or target is self and name == value.name):
                raise LocalFileError('Original Local staging-name adoption is unavailable')
            observed = self.observe(value)
            if observed.size != value.written:
                raise LocalFileError('Original Local adoption size changed')
            self._match_name(self._transfer_root(), value.name, observed.identity, observed.size)
            cursor = _NameAdoption(self, target, value, name, observed)
            value.adoption = cursor
            self._name_transfers[id(cursor)] = cursor
            target._name_transfers[id(cursor)] = cursor
            return cursor

    def _owned_adoption(self, cursor: _NameAdoption) -> _PayloadFile:
        if (type(cursor) is not _NameAdoption or cursor.origin is not self
                or self._name_transfers.get(id(cursor)) is not cursor
                or cursor.target._name_transfers.get(id(cursor)) is not cursor
                or cursor.file.adoption is not cursor):
            raise ValueError('Foreign, copied or retired Local name cursor')
        value = cursor.file
        value.root._owned(value)
        return value

    def advance_adoption(self, cursor: _NameAdoption) -> PhysicalFileObservation:
        """Exclusive acquisition once; retries confirm the same known link.

        Unknown link acquisition never becomes ownership from pathname equality
        or another link attempt. A known link is flushed before dropping only
        the exact original name. Failed unlink/sync retains this cursor, both
        roots and the same descriptor. The Host still owns durable uncertainty.
        """
        with self._lock:
            value = self._owned_adoption(cursor)
            if (value.closing or value.descriptor is None or cursor.link_unknown
                    or cursor.refused or self._closing or cursor.target._closing
                    or self._capacity_root._closing):
                raise LocalFileError('Original Local name acquisition is unavailable or unknown')
            origin = self._transfer_root()
            target = cursor.target._transfer_root()
            observed = value.root.observe(value)
            if observed != PhysicalFileObservation(cursor.identity, cursor.size):
                raise LocalFileError('Original Local name-transfer descriptor changed')
            if cursor.complete:
                self._match_name(target, cursor.name, cursor.identity, cursor.size)
                return observed
            if not cursor.linked:
                self._match_name(origin, cursor.original_name, cursor.identity, cursor.size)
                try:
                    os.link(cursor.original_name, cursor.name, src_dir_fd=origin,
                            dst_dir_fd=target, follow_symlinks=False)
                except FileExistsError:
                    cursor.refused = True
                    raise
                except BaseException:
                    cursor.link_unknown = True
                    raise
                cursor.linked = True
            self._match_name(target, cursor.name, cursor.identity, cursor.size)
            # Persist the known acquired target before retiring the original
            # name. Directory-sync retry never repeats exclusive acquisition.
            os.fsync(target)
            os.fsync(origin)
            if not cursor.source_removed:
                try:
                    self._match_name(origin, cursor.original_name, cursor.identity, cursor.size)
                except FileNotFoundError:
                    if not cursor.remove_unknown:
                        raise LocalFileError('Original Local name disappeared outside unlink work')
                    cursor.source_removed = True
                if not cursor.source_removed:
                    try:
                        os.unlink(cursor.original_name, dir_fd=origin)
                    except BaseException:
                        cursor.remove_unknown = True
                        raise
                    cursor.source_removed = True
            os.fsync(origin)
            os.fsync(target)
            self._match_name(target, cursor.name, cursor.identity, cursor.size)
            if value.root.observe(value) != observed:
                raise LocalFileError('Original Local adoption descriptor changed during I/O')
            del self._files[id(value)]
            cursor.target._files[id(value)] = value
            value.root = cursor.target
            value.name = cursor.name
            cursor.complete = True
            return observed

    def close_adoption(self, cursor: _NameAdoption) -> bool:
        """Retire transport only; never unlink aliases or release Store capacity.

        Incomplete work can retire only after the original file descriptor is
        physically stopped. Its named bytes and unknown acquisition remain the
        existing Store Owner's responsibility, including after process exit.
        A definite exclusive-name refusal acquired nothing and may retire while
        the original writer stays usable under its old name.
        """
        with self._lock:
            value = self._owned_adoption(cursor)
            if (not cursor.complete and not cursor.refused
                    and (cursor.linked or cursor.link_unknown)
                    and value.descriptor is not None):
                return False
            del self._name_transfers[id(cursor)]
            if cursor.target is not self:
                del cursor.target._name_transfers[id(cursor)]
            value.adoption = None
            return True

    def append(self, value: _PayloadFile, expected_offset: int, data: bytes) -> int:
        """One bounded physical write; return a short write without repeating it."""
        if (type(expected_offset) is not int or expected_offset < 0 or type(data) is not bytes
                or not 1 <= len(data) <= self._max_chunk_bytes):
            raise ValueError('Invalid bounded Local file write')
        with self._lock:
            self._owned(value)
            self._open()
            if (value.closing or value.adoption is not None or value.finalization is not None
                    or value.write_unknown
                    or value.write_stopped or not value.creation_synced
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
            if (value.closing or value.adoption is not None or value.finalization is not None
                    or value.write_unknown
                    or value.descriptor is None):
                raise LocalFileError('Original Local file cannot be confirmed from an unknown write')
            observed = self.observe(value)
            if observed.size != value.written:
                raise LocalFileError('Original Local file physical size changed')
            os.fsync(value.descriptor)
            return self.observe(value)

    def _snapshot_stamp(self, value: _PayloadFile) -> tuple[int, ...]:
        observed = self.observe(value)
        root = self._observation_root()
        if value.closing or value.descriptor is None:
            raise LocalFileError('Original Local snapshot descriptor is closing')
        current = os.fstat(value.descriptor)
        named = os.stat(value.name, dir_fd=root, follow_symlinks=False)
        stamp = (current.st_dev, current.st_ino, current.st_size,
                 current.st_mtime_ns, current.st_ctime_ns)
        if (not stat.S_ISREG(named.st_mode)
                or PhysicalFileIdentity(current.st_dev, current.st_ino) != observed.identity
                or current.st_size != observed.size or current.st_size != value.written
                or stamp != (named.st_dev, named.st_ino, named.st_size,
                             named.st_mtime_ns, named.st_ctime_ns)):
            raise LocalFileError('Original Local snapshot name or generation changed')
        return stamp

    def begin_snapshot(self, value: _PayloadFile) -> _FileSnapshot:
        """Stop append and flush this same descriptor before bounded hashing.

        This is a physical fact, not a Core Sealed transition. The trusted Host
        must first confirm original file ownership and reserve hash/chunk
        workspace. No whole-file buffer is retained; a scheduler can yield
        between calls to advance_snapshot. A failed flush keeps append stopped
        and allows flushing the same descriptor again without another write.
        """
        with self._lock:
            self._owned(value)
            self._open()
            if (value.closing or value.adoption is not None or value.finalization is not None
                    or value.write_unknown
                    or not value.creation_synced
                    or value.descriptor is None):
                raise LocalFileError('Original Local snapshot is pending or unknown')
            if value.snapshot is not None:
                self._validate_snapshot(value.snapshot)
                return value.snapshot
            value.write_stopped = True
            self.sync(value)
            cursor = _FileSnapshot(value, self._snapshot_stamp(value))
            value.snapshot = cursor
            return cursor

    def _validate_snapshot(self, cursor: _FileSnapshot) -> _PayloadFile:
        if type(cursor) is not _FileSnapshot:
            raise ValueError('Foreign Local snapshot cursor')
        value = cursor.file
        self._owned(value)
        if value.snapshot is not cursor:
            raise ValueError('Copied or foreign Local snapshot cursor')
        if cursor.invalid or not value.write_stopped:
            raise LocalFileError('Original Local snapshot is invalid')
        try:
            if self._snapshot_stamp(value) != cursor.stamp:
                raise LocalFileError('Original Local snapshot generation changed')
        except BaseException:
            cursor.invalid = True
            raise
        return value

    def advance_snapshot(self, cursor: _FileSnapshot) -> PhysicalFileSnapshot | None:
        """Read at most one original bounded chunk; never restart or rewrite it.

        The final facts are rechecked on reuse. Unknown writes, changed names,
        changed bytes and retired handles cannot yield an accepted snapshot.
        Closing the writer retires this cursor and keeps all named bytes and
        disk reservations for the existing Store Owner.
        """
        with self._lock:
            if (type(cursor) is _FileSnapshot and cursor.file.root is self
                    and cursor.file.snapshot is cursor and cursor.file.finalization is not None):
                raise LocalFileError('Original Local snapshot has final-name work')
            value = self._validate_snapshot(cursor)
            if cursor.result is not None:
                return cursor.result
            size = cursor.stamp[2]
            count = min(self._max_chunk_bytes, size - cursor.offset)
            if count:
                assert value.descriptor is not None
                data = os.pread(value.descriptor, count, cursor.offset)
                self._validate_snapshot(cursor)
                if len(data) != count:
                    cursor.invalid = True
                    raise LocalFileError('Original Local snapshot read was incomplete')
                try:
                    cursor.hash.update(data)
                except BaseException:
                    cursor.invalid = True
                    raise
                cursor.offset += count
            if cursor.offset < size:
                return None
            cursor.result = PhysicalFileSnapshot(
                PhysicalFileObservation(PhysicalFileIdentity(cursor.stamp[0], cursor.stamp[1]), size),
                'sha256:' + cursor.hash.hexdigest())
            return cursor.result

    def begin_finalization(self, value: _PayloadFile, snapshot: _FileSnapshot,
                           name: str) -> _FileFinalization:
        """Retain original stopped bytes and Core-selected final-name work.

        The trusted Host first confirms original Core ownership, validates the
        original name projection/current context, and reserves cursor workspace.
        The completed nominal bounded snapshot belongs to this exact file. No
        names are acquired and no Core or Store transition happens here.
        """
        self._name(name)
        with self._lock:
            self._owned(value)
            self._open()
            if self._validate_snapshot(snapshot) is not value:
                raise ValueError('Foreign Local final-name snapshot')
            if (value.closing or value.write_unknown or value.adoption is not None
                    or value.finalization is not None or value.close_pending
                    or value.descriptor is None or snapshot.result is None
                    or name == value.name):
                raise LocalFileError('Original Local final-name work is unavailable or incomplete')
            cursor = _FileFinalization(self, value, snapshot, name)
            value.finalization = cursor
            self._finalizations[id(cursor)] = cursor
            return cursor

    def _owned_finalization(self, cursor: _FileFinalization) -> _PayloadFile:
        if (type(cursor) is not _FileFinalization or cursor.root is not self
                or self._finalizations.get(id(cursor)) is not cursor
                or cursor.file.finalization is not cursor):
            raise ValueError('Foreign, copied or retired Local final-name cursor')
        value = cursor.file
        self._owned(value)
        return value

    def _final_name_stamp(self, root: int, name: str, cursor: _FileFinalization) -> tuple[int, ...]:
        expected = cursor.snapshot.stamp
        self._match_name(root, name, PhysicalFileIdentity(expected[0], expected[1]), expected[2])
        named = os.stat(name, dir_fd=root, follow_symlinks=False)
        stamp = (named.st_dev, named.st_ino, named.st_size, named.st_mtime_ns, named.st_ctime_ns)
        # Original byte generation/mtime must survive our own link/unlink. ctime
        # changes with those owned metadata operations; cached final reuse checks
        # the complete new stamp after those operations finish.
        if (not stat.S_ISREG(named.st_mode) or named.st_uid != os.getuid()
                or named.st_mode & 0o077 or stamp[:4] != expected[:4]):
            raise LocalFileError('Original Local stopped byte generation changed')
        return stamp

    def advance_finalization(self, cursor: _FileFinalization) -> PhysicalFileSnapshot:
        """Physically stop the original writer before exclusive final linking.

        Stop uncertainty observes the same original descriptor without another
        close. Unknown link acquisition never becomes a retry grant. Known-link
        sync/unlink failures retain the same cursor and only original owned-name
        cleanup. Returning physical facts is not Core Sealed/Commit/publication.
        """
        with self._lock:
            value = self._owned_finalization(cursor)
            self._open()
            if value.closing or cursor.link_unknown or cursor.refused:
                raise LocalFileError('Original Local final-name work is unavailable or unknown')
            root = self._transfer_root()
            if cursor.result is not None:
                if self._final_name_stamp(root, cursor.name, cursor) != cursor.final_stamp:
                    raise LocalFileError('Original Local final-name generation changed')
                return cursor.result
            if not cursor.stopped:
                if not value.close_pending:
                    self._validate_snapshot(cursor.snapshot)
                    assert value.descriptor is not None
                    os.fsync(value.descriptor)
                    self._validate_snapshot(cursor.snapshot)
                if not self._stop_writer_descriptor(value):
                    raise LocalFileError('Original Local writer physical stop remains unknown')
                cursor.stopped = True
            if not cursor.linked:
                if self._final_name_stamp(root, cursor.original_name, cursor) != cursor.snapshot.stamp:
                    raise LocalFileError('Original Local staging generation changed before final link')
                try:
                    os.link(cursor.original_name, cursor.name, src_dir_fd=root,
                            dst_dir_fd=root, follow_symlinks=False)
                except FileExistsError:
                    cursor.refused = True
                    raise
                except BaseException:
                    cursor.link_unknown = True
                    raise
                cursor.linked = True
            self._final_name_stamp(root, cursor.name, cursor)
            os.fsync(root)
            if not cursor.source_removed:
                try:
                    self._final_name_stamp(root, cursor.original_name, cursor)
                except FileNotFoundError:
                    if not cursor.remove_unknown:
                        raise LocalFileError('Original Local stage disappeared outside unlink work')
                    cursor.source_removed = True
                if not cursor.source_removed:
                    try:
                        os.unlink(cursor.original_name, dir_fd=root)
                    except BaseException:
                        cursor.remove_unknown = True
                        raise
                    cursor.source_removed = True
            os.fsync(root)
            cursor.final_stamp = self._final_name_stamp(root, cursor.name, cursor)
            cursor.result = cursor.snapshot.result
            assert cursor.result is not None
            value.name = cursor.name
            return cursor.result

    def close_finalization(self, cursor: _FileFinalization) -> bool:
        """Retire transport only after actual original writer stop.

        This neither unlinks remaining aliases nor settles unknown acquisition,
        releases durable Store capacity or supplies a Run cleanup/Sealed fact.
        The original Store/file custody remains for separate Owner reconciliation.
        """
        with self._lock:
            value = self._owned_finalization(cursor)
            if value.descriptor is not None:
                return False
            del self._finalizations[id(cursor)]
            value.finalization = None
            return True

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

    def _stop_writer_descriptor(self, value: _PayloadFile) -> bool:
        """Existing original-descriptor stop rule shared by close and final IO."""
        if value.descriptor is None:
            return True
        if value.close_pending:
            try:
                closed = self._closed_after_uncertainty(value.descriptor, value.identity)
            except OSError:
                return False
            if closed is not True:
                return False
            value.descriptor = None
            value.close_pending = False
            return True
        try:
            os.close(value.descriptor)
        except OSError:
            value.close_pending = True
            return False
        value.descriptor = None
        return True

    def close_writer(self, value: _PayloadFile) -> bool:
        """Stop this descriptor only; retain bytes/capacity for the Store Owner."""
        with self._lock:
            self._owned(value)
            value.closing = True
            if not self._stop_writer_descriptor(value):
                return False
            if value.adoption is not None or value.finalization is not None:
                # The descriptor is physically stopped, but original name work
                # still pins both roots. No unlink or capacity return occurs.
                return False
            del self._files[id(value)]
            return True

    def close(self) -> bool:
        """Close the root only after every original descriptor has retired."""
        with self._lock:
            self._nominal_root()
            self._closing = True
            if self._files or self._areas or self._name_transfers or self._finalizations:
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
