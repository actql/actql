"""Bounded physical project inputs, separate from Core configuration meaning.

Responsibility: pin read-only project files and discovery absences.
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
from typing import NoReturn

from ._local_core import LocalCore, _Workspace
from ._local_files import LocalFileRoot, PhysicalFileIdentity


@dataclass(slots=True, eq=False)
class _Descriptor:
    fd: int | None = None
    identity: PhysicalFileIdentity | None = None
    close_pending: bool = False


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
                self._workspace = core.reserve_workspace(
                    8 * max_bytes + 16384 * max_files + 65536,
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

    def read_original(self, path: Path, *, max_bytes: int,
                      missing: bool = False) -> _ProjectFile | None:
        """Read once after reservation; only an observed ENOENT is absence."""
        with self._core._lock:
            self._active()
            path = self._path(path)
            if (type(max_bytes) is not int or not 0 <= max_bytes <= 1048576
                    or max_bytes > self._max_bytes - self._reserved
                    or type(missing) is not bool or path in self._attempts
                    or len(self._attempts) >= self._max_files):
                raise ValueError('Original project input bound or one-read limit exceeded')
            self.current()
            self._attempts.add(path)
            self._reserved += max_bytes
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
                    self._reserved -= max_bytes
                    self.current()
                    return None
                info = os.fstat(descriptor.fd)
                descriptor.identity = PhysicalFileIdentity(info.st_dev, info.st_ino)
                if not stat.S_ISREG(info.st_mode) or not 0 <= info.st_size <= max_bytes:
                    raise ValueError('Original project file is not bounded regular input')
                destination = bytearray(max_bytes)
                offset = 0
                while True:
                    chunk = os.read(descriptor.fd, min(16384, max_bytes - offset + 1))
                    if not chunk:
                        break
                    if offset + len(chunk) > max_bytes:
                        raise ValueError('Original project file exceeds its byte bound')
                    destination[offset:offset + len(chunk)] = chunk
                    offset += len(chunk)
                value = _ProjectFile(self._identity, path,
                    bytes(memoryview(destination)[:offset]), descriptor, parent, self._stamp(info))
                if offset != info.st_size:
                    raise ValueError('Original project file changed during read')
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
        """Observe this whole physical group; no permission/current token leaves."""
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

    def _release_descriptors(self) -> bool:
        self._closing = True
        for descriptor in reversed(self._descriptors):
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
            self._absent.clear()
            self._parents.clear()
            self._descriptors.clear()
            self._closed = True
            return True
