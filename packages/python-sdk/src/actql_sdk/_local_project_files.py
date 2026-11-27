"""Bounded physical project inputs, separate from Core configuration meaning.

Responsibility: pin immutable project metadata, Mock seed evidence and discovery absences.
Inputs/outputs: original paths and exact immutable bytes, never interpreted JSON.
Identity: every read retains its original directory and file descriptors.
Ownership: the installed caller retains this child; Core owns its workspace loan.
Synchronization: all operations use the same Core lock and current file group.
Failure: failed acquisition keeps the same descriptors and refuses replacement.
Cancellation: synchronous input work ends before return; close is not a Run stop.
Resources: reserve bounded holding before opening directories or reading bytes.
Extension: Core-selected locators use this port without another profile parser.
Verification: actual discovery, replacement, bounded read and uncertain close.
"""
from dataclasses import dataclass
import os
from pathlib import Path
import stat
from typing import Callable, NoReturn

from ._local_core import LocalCore, _Workspace
from ._local_files import LocalFileRoot, PhysicalFileIdentity


@dataclass(slots=True, eq=False)
class _Descriptor:
    fd: int | None = None
    identity: PhysicalFileIdentity | None = None
    close_pending: bool = False


def _close_descriptors(descriptors: list[_Descriptor]) -> bool:
    for descriptor in reversed(descriptors):
        if descriptor.fd is None:
            continue
        if descriptor.close_pending:
            try:
                if LocalFileRoot._closed_after_uncertainty(
                        descriptor.fd, descriptor.identity) is not True:
                    return False
            except OSError:
                return False
        else:
            try:
                os.close(descriptor.fd)
            except OSError:
                descriptor.close_pending = True
                return False
        descriptor.fd = None
    return True


def _read_bounded_file(fd: int, size: int, changed: str, *, eof_probe: bool,
                       require_current: Callable[[], None] | None = None,
                       observe_bytes: Callable[[int], None] | None = None) -> bytes:
    # The caller charged the complete output and one read block. Project
    # metadata retains its EOF probe. A Source uses its generation fence and
    # never requests past its measured file size or paid transfer bound.
    destination = bytearray(size)
    offset = 0
    requested_end = size + int(eof_probe)
    while offset < requested_end:
        if require_current is not None:
            require_current()
        chunk = os.read(fd, min(16384, requested_end - offset))
        if not chunk:
            break
        if observe_bytes is not None:
            observe_bytes(len(chunk))
        if offset + len(chunk) > size:
            raise ValueError(changed)
        destination[offset:offset + len(chunk)] = chunk
        offset += len(chunk)
    if offset != size:
        raise ValueError(changed)
    return bytes(destination)


@dataclass(frozen=True, slots=True, eq=False)
class _ProjectFile:
    owner: object
    path: Path
    body: bytes
    _descriptor: _Descriptor
    _parent: _Descriptor
    _stamp: tuple[int, ...]


class LocalProjectFilesCleanupPending(RuntimeError):
    def __init__(self, original: 'OriginalLocalProjectFiles') -> None:
        super().__init__('Original project file acquisition requires same-child cleanup')
        self.cleanup_files = original


class _OriginalProjectSource:
    """One physical file read, retained by the already selected Whole Source."""

    def __init__(self, files: 'OriginalLocalProjectFiles', root: Path, relative: str, *,
                 max_bytes: int, max_path_bytes: int, max_depth: int,
                 require_current: Callable[[], None]) -> None:
        if (not isinstance(root, Path) or not root.is_absolute()
                or root != files._path(root) or type(relative) is not str
                or type(max_path_bytes) is not int or not 1 <= max_path_bytes <= 4096
                or type(max_depth) is not int or not 1 <= max_depth <= 128
                or type(max_bytes) is not int or not 1 <= max_bytes <= 2147483647
                or len(relative) > max_path_bytes or not callable(require_current)):
            raise ValueError('Invalid selected Local Source path or bounds')
        if '\x00' in relative or len(relative.encode('utf-8')) > max_path_bytes:
            raise ValueError('Invalid selected Local Source relative path')
        parts = relative.split('/')
        if len(parts) - 1 > max_depth or any(part in ('', '.', '..') for part in parts):
            raise ValueError('Invalid selected Local Source relative path')
        self._original, self._files, self._root = self, files, root
        self._parts, self._max_bytes, self._require_current = parts, max_bytes, require_current
        self._descriptors: list[_Descriptor] = []
        self._received_bytes = 0
        self._size_observed = False
        self._size_stamp: tuple[int, ...] | None = None
        self._attempted = self._reading = self._closing = False

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign or copied Local Source reader')

    def _current(self) -> None:
        if self._closing:
            raise ValueError('Original Local Source reader is closing')
        self._files.current()
        self._require_current()
        if self._closing:
            raise ValueError('Original Local Source reader is closing')
        self._files._active()

    def _open(self, path: Path | str, parent: int | None, directory: bool) -> os.stat_result:
        self._current()
        descriptor = _Descriptor()
        self._descriptors.append(descriptor)
        flags = os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK
        if directory:
            flags |= os.O_DIRECTORY
        descriptor.fd = os.open(path, flags, dir_fd=parent)
        info = os.fstat(descriptor.fd)
        descriptor.identity = PhysicalFileIdentity(info.st_dev, info.st_ino)
        return info

    def _member_current(self, stamp: tuple[int, ...]) -> None:
        self._current()
        parent = None
        for index, descriptor in enumerate(self._descriptors):
            assert descriptor.fd is not None
            path = self._root if index == 0 else self._parts[index - 1]
            named = os.stat(path, dir_fd=parent, follow_symlinks=False)
            if index < len(self._parts):
                if (not stat.S_ISDIR(named.st_mode)
                        or PhysicalFileIdentity(named.st_dev, named.st_ino) != descriptor.identity):
                    raise ValueError('Original Local Source directory generation changed')
            elif (self._files._stamp(named) != stamp
                    or self._files._stamp(os.fstat(descriptor.fd)) != stamp):
                raise ValueError('Original Local Source file generation changed')
            parent = descriptor.fd

    def _observe_bytes(self, count: int) -> None:
        self._received_bytes += count

    @property
    def received_bytes(self) -> int:
        """Actual physical bytes, including before a failed delivery."""
        with self._files._core._lock:
            self._nominal()
            return self._received_bytes

    def _open_parents(self) -> None:
        self._open(self._root, None, True)
        for component in self._parts[:-1]:
            self._open(component, self._descriptors[-1].fd, True)

    def observe_size(self) -> int:
        """Observe the exact file generation through the selected directories."""
        with self._files._core._lock:
            self._nominal()
            if self._size_observed or self._attempted or self._reading or self._closing:
                raise ValueError('Original Local Source extent is unavailable')
            self._size_observed = self._reading = True
            try:
                self._open_parents()
                self._current()
                info = os.stat(self._parts[-1], dir_fd=self._descriptors[-1].fd,
                               follow_symlinks=False)
                if not stat.S_ISREG(info.st_mode) or not 0 <= info.st_size <= self._max_bytes:
                    raise ValueError('Original Local Source file is not bounded regular input')
                self._current()
                self._size_stamp = self._files._stamp(info)
                return info.st_size
            finally:
                self._reading = False

    def read_into(self, receive: Callable[[bytes], None]) -> None:
        """Deliver one bounded body under the same Source currentness fences."""
        with self._files._core._lock:
            self._nominal()
            if self._attempted or self._closing or not callable(receive):
                raise ValueError('Original Local Source read is unavailable')
            self._attempted = self._reading = True
            try:
                if self._size_observed:
                    if self._size_stamp is None:
                        raise ValueError('Original Local Source extent observation failed')
                else:
                    self._open_parents()
                info = self._open(self._parts[-1], self._descriptors[-1].fd, False)
                if not stat.S_ISREG(info.st_mode) or not 0 <= info.st_size <= self._max_bytes:
                    raise ValueError('Original Local Source file is not bounded regular input')
                stamp = self._files._stamp(info)
                if self._size_stamp is not None and stamp != self._size_stamp:
                    raise ValueError('Original Local Source file generation changed')
                self._member_current(stamp)
                fd = self._descriptors[-1].fd
                assert fd is not None
                body = _read_bounded_file(fd, info.st_size,
                                          'Original Local Source file changed during read',
                                          eof_probe=False, require_current=self._current,
                                          observe_bytes=self._observe_bytes)
                self._member_current(stamp)
                receive(body)
                self._member_current(stamp)
            finally:
                self._reading = False

    def close(self) -> bool:
        with self._files._core._lock:
            self._nominal()
            self._closing = True
            if self._reading or not _close_descriptors(self._descriptors):
                return False
            self._descriptors.clear()
            return True


class OriginalLocalProjectFiles:
    """A read-only physical child, not an installation, permission or file cache.

    Ordinary project directories need neither private Store permissions nor an
    exclusive Store lock. No named bytes are created, repaired or removed here.
    The caller must keep this child under its existing Host until it closes.
    """

    def __init__(self, core: LocalCore, *, max_files: int, max_bytes: int) -> None:
        if (type(core) is not LocalCore or type(max_files) is not int
                or not 1 <= max_files <= 128 or type(max_bytes) is not int
                or not 1 <= max_bytes <= 8388608):
            raise ValueError('Invalid original project input bounds')
        self._original, self._identity = self, object()
        self._core = core
        self._max_files, self._max_bytes = max_files, max_bytes
        self._reserved = 0
        self._descriptors: list[_Descriptor] = []
        self._parents: dict[Path, _Descriptor] = {}
        self._files: dict[Path, _ProjectFile] = {}
        self._mock_data: _ProjectFile | None = None
        self._absent: dict[Path, _Descriptor] = {}
        self._attempts: set[Path] = set()
        self._failed = self._closing = self._closed = self._discovered = False
        self._workspace: _Workspace | None = None
        self._uncertain_ticket: int | None = None
        with core._lock:
            ticket = core._next_ticket
            self._uncertain_ticket = ticket
            try:
                # Raw/destination/decoded-text holdings and bounded descriptor/
                # path objects overlap the separate Core input/output loans.
                # The five-handle descriptor has a fixed 4 KiB prefix. The
                # selected installation also formats a bounded 4 KiB path:
                # allow simultaneous Path text, escaped JSON and UTF-8 bytes.
                self._workspace = core.reserve_workspace(
                    8 * max_bytes + 16384 * max_files + 65536 + 4096 + 131072,
                    stopped=lambda: True, cleanup=self._release_descriptors)
                self._uncertain_ticket = None
            except BaseException as failure:
                if ticket not in core._inputs and ticket not in core._released:
                    self._uncertain_ticket = None
                raise LocalProjectFilesCleanupPending(self) from failure

    def __copy__(self) -> NoReturn:
        raise TypeError('Original project files cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original project files cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original project files cannot be serialized')

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original project files')

    def _active(self) -> None:
        self._nominal()
        if (self._failed or self._closing or self._closed or self._core._closing
                or self._workspace is None):
            raise ValueError('Original project file input is failed or closing')
        self._core._owned(self._workspace)

    @staticmethod
    def _path(path: Path) -> Path:
        if not isinstance(path, Path):
            raise ValueError('Original project path is unavailable')
        text = str(path)
        if not text or '\x00' in text or len(text.encode('utf-8')) > 4096:
            raise ValueError('Original project path exceeds its bound')
        return Path(os.path.abspath(text))

    @staticmethod
    def _stamp(info: os.stat_result) -> tuple[int, ...]:
        return (info.st_dev, info.st_ino, info.st_mode, info.st_uid, info.st_gid,
                info.st_size, info.st_mtime_ns, info.st_ctime_ns)

    def _parent(self, path: Path) -> _Descriptor:
        if path in self._parents:
            return self._parents[path]
        descriptor = _Descriptor()
        self._descriptors.append(descriptor)
        descriptor.fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY |
                                os.O_CLOEXEC | os.O_NOFOLLOW)
        info = os.fstat(descriptor.fd)
        if not stat.S_ISDIR(info.st_mode):
            raise ValueError('Original project parent is not a directory')
        descriptor.identity = PhysicalFileIdentity(info.st_dev, info.st_ino)
        self._parents[path] = descriptor
        return descriptor

    def prepare_source(self, root: Path, relative: str, *, max_bytes: int,
                       max_path_bytes: int, max_depth: int,
                       require_current: Callable[[], None]) -> _OriginalProjectSource:
        """Build a closeable reader after the original Whole Source reservation.

        The Source caller retains this child before taking the physical attempt.
        The callback supplies that original Source's active scope and funding.
        No Project metadata read slot or new reservation is consumed here.
        """
        with self._core._lock:
            self._active()
            return _OriginalProjectSource(self, root, relative, max_bytes=max_bytes,
                max_path_bytes=max_path_bytes, max_depth=max_depth, require_current=require_current)

    def read_original(self, path: Path, *, max_bytes: int,
                      missing: bool = False) -> _ProjectFile | None:
        """Read once after reservation; only an observed ENOENT is absence."""
        return self._read_file(path, max_bytes=max_bytes, missing=missing, mock_data=False)

    def read_original_mock_data(self, path: Path, *, max_bytes: int) -> _ProjectFile:
        """Retain the selected Mock seed under its own read-current fence."""
        value = self._read_file(path, max_bytes=max_bytes, missing=False, mock_data=True)
        if value is None:
            raise ValueError('Original Mock Project data is unavailable')
        return value

    def _read_file(self, path: Path, *, max_bytes: int, missing: bool,
                   mock_data: bool) -> _ProjectFile | None:
        with self._core._lock:
            self._active()
            path = self._path(path)
            if (type(max_bytes) is not int or not 0 <= max_bytes <= 1048576
                    or type(missing) is not bool or path in self._attempts
                    or mock_data and self._mock_data is not None
                    or len(self._attempts) >= self._max_files):
                raise ValueError('Original project input bound or one-read limit exceeded')
            self.current()
            self._attempts.add(path)
            try:
                parent = self._parent(path.parent)
                descriptor = _Descriptor()
                self._descriptors.append(descriptor)
                try:
                    descriptor.fd = os.open(path.name, os.O_RDONLY | os.O_NONBLOCK |
                        os.O_CLOEXEC | os.O_NOFOLLOW, dir_fd=parent.fd)
                except FileNotFoundError:
                    if not missing:
                        raise
                    self._absent[path] = parent
                    self.current()
                    return None
                info = os.fstat(descriptor.fd)
                descriptor.identity = PhysicalFileIdentity(info.st_dev, info.st_ino)
                size = info.st_size
                if not stat.S_ISREG(info.st_mode) or not 0 <= size <= max_bytes:
                    raise ValueError('Original project file is not bounded regular input')
                if mock_data:
                    aliases = any(member._descriptor.identity == descriptor.identity
                                  for member in self._files.values())
                else:
                    aliases = (self._mock_data is not None
                               and self._mock_data._descriptor.identity == descriptor.identity)
                if aliases:
                    raise ValueError('Original Mock data aliases immutable project metadata')
                if size > self._max_bytes - self._reserved:
                    raise ValueError('Original project aggregate byte bound exceeded')
                # The precharged workspace covers this allocation and its copy.
                self._reserved += size
                body = _read_bounded_file(descriptor.fd, size, 'Original project file changed during read',
                                          eof_probe=True)
                value = _ProjectFile(self._identity, path, body,
                    descriptor, parent, self._stamp(info))
                if mock_data:
                    self._mock_data = value
                    self.mock_data_bytes(value)
                else:
                    self._files[path] = value
                    self.current()
                return value
            except BaseException as failure:
                self._failed = True
                raise LocalProjectFilesCleanupPending(self) from failure

    def discover(self, directory: Path) -> _ProjectFile | None:
        """Nearest project file; malformed/unreadable input cannot fall back."""
        with self._core._lock:
            self._active()
            if self._discovered:
                raise ValueError('Original project discovery was already attempted')
            self._discovered = True
            directory = self._path(directory)
            while True:
                value = self.read_original(directory / 'actql.config.json',
                    max_bytes=min(65536, self._max_bytes), missing=True)
                if value is not None or directory.parent == directory:
                    return value
                directory = directory.parent

    def current(self) -> None:
        """Observe immutable metadata and directory/absence originals."""
        with self._core._lock:
            self._active()
            for path, descriptor in self._parents.items():
                if descriptor.fd is None or descriptor.close_pending:
                    raise ValueError('Original project parent is closing')
                named = os.stat(path, follow_symlinks=False)
                opened = os.fstat(descriptor.fd)
                if (not stat.S_ISDIR(named.st_mode) or
                        PhysicalFileIdentity(named.st_dev, named.st_ino) != descriptor.identity or
                        PhysicalFileIdentity(opened.st_dev, opened.st_ino) != descriptor.identity):
                    raise ValueError('Original project directory generation changed')
            for path, parent in self._absent.items():
                try:
                    os.stat(path.name, dir_fd=parent.fd, follow_symlinks=False)
                except FileNotFoundError:
                    continue
                raise ValueError('Original project discovery absence changed')
            for value in self._files.values():
                self._require_file_current(value)

    def _require_file_current(self, value: _ProjectFile) -> None:
        descriptor = value._descriptor
        if descriptor.fd is None or descriptor.close_pending:
            raise ValueError('Original project file is closing')
        try:
            named = os.stat(value.path.name, dir_fd=value._parent.fd,
                            follow_symlinks=False)
        except FileNotFoundError as failure:
            raise ValueError('Original project file generation changed') from failure
        if (self._stamp(named) != value._stamp
                or self._stamp(os.fstat(descriptor.fd)) != value._stamp):
            raise ValueError('Original project file generation changed')

    def original_bytes(self, value: _ProjectFile) -> bytes:
        with self._core._lock:
            self._active()
            if (type(value) is not _ProjectFile or value.owner is not self._identity
                    or self._files.get(value.path) is not value):
                raise ValueError('Foreign original project file')
            self.current()
            return value.body

    def mock_data_bytes(self, value: _ProjectFile) -> bytes:
        """Check the selected predecision seed; no successor or write is admitted."""
        with self._core._lock:
            self._active()
            if (type(value) is not _ProjectFile or value.owner is not self._identity
                    or self._mock_data is not value):
                raise ValueError('Foreign original Mock Project data')
            self.current()
            self._require_file_current(value)
            return value.body

    def _release_descriptors(self) -> bool:
        self._closing = True
        return _close_descriptors(self._descriptors)

    def close(self) -> bool:
        with self._core._lock:
            self._nominal()
            self._closing = True
            if self._closed:
                return True
            if self._uncertain_ticket is not None and not self._core._closed:
                return False
            if self._core._closed:
                # The original Core's global cleanup has already called its
                # physical cleanup hooks. Never invoke a closed Core again or
                # infer descriptor retirement from that flag alone.
                if any(descriptor.fd is not None for descriptor in self._descriptors):
                    return False
                self._workspace = None
                self._uncertain_ticket = None
            elif self._workspace is not None:
                if not self._core.close_workspace(self._workspace):
                    return False
                self._workspace = None
            self._files.clear()
            self._mock_data = None
            self._absent.clear()
            self._parents.clear()
            self._descriptors.clear()
            self._closed = True
            return True
