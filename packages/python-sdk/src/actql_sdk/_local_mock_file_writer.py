"""Physical owner for an already selected, UPDATE-only Mock Project file.

Common owns the original Effect claim, row-version validation and complete
replacement bytes. This private owner spends one locked replacement from
that checked result and retains its actual acknowledgement. It issues no
approval, dispatch, or recovery authority.
"""
from dataclasses import dataclass
import hashlib
import os
import re
import stat
from typing import Callable

from ._local_core import _Workspace
from ._local_files import PhysicalFileIdentity
from ._local_project_files import (
    OriginalLocalProjectFiles, _Descriptor, _ProjectFile, _close_descriptors,
    _read_bounded_file,
)


class _MockFileUpdateRefused(ValueError):
    """Definite refusal before the replacement attempt."""


class _MockFileUpdateUnknown(RuntimeError):
    """No usable acknowledgement after entering original replacement."""


@dataclass(frozen=True, slots=True, eq=False)
class _MockFileUpdate:
    """The selected operation identity and Common's bounded locked projector."""

    dispatch_cid: str
    row_identity: str
    expected_version_cid: str
    project: Callable[[bytes, str, str], bytes]
    require_current: Callable[[], None]


@dataclass(frozen=True, slots=True, eq=False)
class _MockFileReplacementAck:
    target: '_MockFileTarget'
    operation: _MockFileUpdate
    before_stamp: tuple[int, ...]
    before_sha256: str
    after_stamp: tuple[int, ...]
    after_sha256: str
    body: bytes


class _MockFileTarget:
    """One already adopted Project seed and one original writer chain."""

    def __init__(self, files: OriginalLocalProjectFiles, seed: _ProjectFile, *,
                 max_bytes: int, max_operations: int) -> None:
        if type(files) is not OriginalLocalProjectFiles or type(seed) is not _ProjectFile:
            raise ValueError('Expected the original Mock Project file')
        if (type(max_bytes) is not int or not 1 <= max_bytes <= 1048576
                or type(max_operations) is not int or not 1 <= max_operations <= 128):
            raise ValueError('Invalid selected Mock file byte limit')
        selected = files.mock_data_bytes(seed)
        if not 0 < len(selected) <= max_bytes or len(seed.path.name.encode()) > 128:
            raise ValueError('Original Mock file is outside the selected bounds')
        self._original = self
        self.files, self.seed, self.max_bytes = files, seed, max_bytes
        self._latest: _MockFileReplacementAck | None = None
        self._writer: _MockFileWriter | None = None
        self._failed = False
        self._max_operations = max_operations
        self._entered: set[str] = set()

    def _current(self) -> None:
        if (self._original is not self or self.files._mock_data is not self.seed
                or self.seed._parent.fd is None or self.seed._parent.close_pending):
            raise _MockFileUpdateRefused('Original Mock file selection changed')
        self.files.current()

    def prepare_update(self, operation: _MockFileUpdate, *,
                       predecessor: _MockFileReplacementAck | None) -> '_MockFileWriter':
        with self.files._core._lock:
            self._current()
            if self._failed or self._writer is not None or predecessor is not self._latest:
                raise _MockFileUpdateRefused('Foreign or unsettled Mock file predecessor')
            if (type(operation) is not _MockFileUpdate
                    or type(operation.dispatch_cid) is not str
                    or re.fullmatch(r'sha256:[0-9a-f]{64}', operation.dispatch_cid) is None
                    or type(operation.expected_version_cid) is not str
                    or re.fullmatch(r'sha256:[0-9a-f]{64}', operation.expected_version_cid) is None
                    or type(operation.row_identity) is not str
                    or not 0 < len(operation.row_identity) <= self.max_bytes
                    or not callable(operation.project) or not callable(operation.require_current)
                    or len(self._entered) >= self._max_operations
                    or operation.dispatch_cid in self._entered):
                raise _MockFileUpdateRefused('Invalid original Mock file update')
            writer = _MockFileWriter(self, operation, predecessor)
            self._writer = writer
            return writer


@dataclass(slots=True, eq=False)
class _OwnedMockName:
    name: str
    descriptor: _Descriptor
    pending: bool = False


class _MockFileWriter:
    """Retain the same writer and lock through failure, unknown or first close."""

    def __init__(self, target: _MockFileTarget, operation: _MockFileUpdate,
                 predecessor: _MockFileReplacementAck | None) -> None:
        self.target, self.operation, self.predecessor = target, operation, predecessor
        self._original = self
        self._file = _Descriptor()
        self._lock = _OwnedMockName(target.seed.path.name + '.actql-write.lock', _Descriptor())
        self._stage = _OwnedMockName('.actql-mock-' + operation.dispatch_cid[7:] + '.tmp', _Descriptor())
        self._workspace: _Workspace | None = None
        self._uncertain_ticket: int | None = None
        self._started = self._running = self._closing = self._closed = False
        self._rename_entered = self._rename_returned = False
        self.ack: _MockFileReplacementAck | None = None

    def _current(self) -> int:
        if self._original is not self or self.target._writer is not self or self._closing:
            raise _MockFileUpdateRefused('Original Mock writer unavailable')
        self.target._current()
        if self.operation.require_current() is not None:
            raise _MockFileUpdateRefused('Original Mock current fence did not return normally')
        self.target._current()
        if self._closing:
            raise _MockFileUpdateRefused('Original Mock writer is closing')
        parent = self.target.seed._parent.fd
        assert parent is not None
        return parent

    @staticmethod
    def _observe(descriptor: _Descriptor) -> os.stat_result:
        assert descriptor.fd is not None
        info = os.fstat(descriptor.fd)
        identity = PhysicalFileIdentity(info.st_dev, info.st_ino)
        if descriptor.identity is not None and descriptor.identity != identity:
            raise _MockFileUpdateRefused('Original Mock descriptor changed')
        descriptor.identity = identity
        return info

    def _exclusive(self, root: int, member: _OwnedMockName) -> None:
        member.descriptor.fd = os.open(
            member.name, os.O_RDWR | os.O_CREAT | os.O_EXCL | os.O_CLOEXEC | os.O_NOFOLLOW,
            0o600, dir_fd=root)
        member.pending = True
        self._observe(member.descriptor)

    @staticmethod
    def _named(root: int, name: str) -> os.stat_result:
        return os.stat(name, dir_fd=root, follow_symlinks=False)

    def _same_named(self, root: int, member: _OwnedMockName) -> os.stat_result:
        info = self._named(root, member.name)
        if (not stat.S_ISREG(info.st_mode) or info.st_nlink != 1
                or PhysicalFileIdentity(info.st_dev, info.st_ino) != member.descriptor.identity):
            raise _MockFileUpdateRefused('Original Mock writer name changed')
        return info

    def apply(self) -> _MockFileReplacementAck:
        core = self.target.files._core
        with core._lock:
            if (self._started or self._closing or self._original is not self
                    or self.target._writer is not self):
                raise _MockFileUpdateRefused('Original Mock replacement already entered')
            self._started = self._running = True
            try:
                root = self._current()
                # Borrowed predecessor and projection output stay on their
                # existing owners. Cover the physical input and temporary read
                # copies, its read block, descriptor and fixed path controls.
                before = self.target.seed.body if self.predecessor is None else self.predecessor.body
                ticket = core._next_ticket
                self._uncertain_ticket = ticket
                try:
                    self._workspace = core.reserve_workspace(
                        3 * len(before) + 32768, stopped=lambda: not self._running,
                        cleanup=self._retire_physical)
                    self._uncertain_ticket = None
                except BaseException:
                    if ticket not in core._inputs and ticket not in core._released:
                        self._uncertain_ticket = None
                    raise
                self.target._entered.add(self.operation.dispatch_cid)
                return self._replace(root, before)
            except BaseException as failure:
                self.target._failed = True
                if self._rename_entered:
                    raise _MockFileUpdateUnknown('Original Mock replacement needs observation') from failure
                raise
            finally:
                self._running = False

    def _replace(self, root: int, expected: bytes) -> _MockFileReplacementAck:
        self._exclusive(root, self._lock)
        name = self.target.seed.path.name
        self._file.fd = os.open(name, os.O_RDONLY | os.O_CLOEXEC | os.O_NOFOLLOW | os.O_NONBLOCK,
                                dir_fd=root)
        original = self._observe(self._file)
        stamp = self.target.files._stamp
        expected_stamp = self.target.seed._stamp if self.predecessor is None else self.predecessor.after_stamp
        if (not stat.S_ISREG(original.st_mode) or original.st_nlink != 1
                or original.st_uid != os.geteuid() or not original.st_mode & stat.S_IWUSR
                or stamp(original) != expected_stamp or original.st_size != len(expected)):
            raise _MockFileUpdateRefused('Original Mock file generation changed')
        actual = _read_bounded_file(self._file.fd, original.st_size,
            'Original Mock file extent changed', eof_probe=True)
        if actual != expected:
            raise _MockFileUpdateRefused('Original Mock file contents changed')
        self._check_original(root, name, expected_stamp)
        self._current()
        output = self.operation.project(actual, self.operation.row_identity,
                                        self.operation.expected_version_cid)
        if type(output) is not bytes or not 0 < len(output) <= self.target.max_bytes:
            raise _MockFileUpdateRefused('Invalid Common Mock replacement bytes')
        self._current()
        self._exclusive(root, self._stage)
        fd = self._stage.descriptor.fd
        assert fd is not None
        pending = memoryview(output)
        offset = 0
        while offset < len(pending):
            count = os.pwrite(fd, pending[offset:offset + 16384], offset)
            if not 0 < count <= min(16384, len(pending) - offset):
                raise _MockFileUpdateRefused('Original Mock staging extent was not written')
            offset += count
        os.fchmod(fd, original.st_mode & 0o777)
        os.fsync(fd)
        sealed = stamp(os.fstat(fd))
        self._current()
        self._check_original(root, name, expected_stamp)
        staged = self._same_named(root, self._stage)
        if stamp(staged) != sealed or stamp(staged) != stamp(os.fstat(fd)) or staged.st_size != len(output):
            raise _MockFileUpdateRefused('Original Mock staging file changed')
        self._rename_entered = True
        os.replace(self._stage.name, name, src_dir_fd=root, dst_dir_fd=root)
        self._rename_returned = True
        self._stage.pending = False
        os.fsync(root)
        self._current()
        successor = self._named(root, name)
        if (not stat.S_ISREG(successor.st_mode) or successor.st_nlink != 1
                or stamp(successor) != stamp(os.fstat(fd))
                or PhysicalFileIdentity(successor.st_dev, successor.st_ino) != self._stage.descriptor.identity
                or successor.st_size != len(output)):
            raise _MockFileUpdateUnknown('Original Mock replacement acknowledgement changed')
        # Confirm the actual installed bytes through the same descriptor,
        # including same-size changes, without acquiring a second Reader.
        offset = 0
        while offset < len(pending):
            chunk = os.pread(fd, min(16384, len(pending) - offset), offset)
            if not chunk or chunk != pending[offset:offset + len(chunk)]:
                raise _MockFileUpdateUnknown('Original Mock replacement bytes changed')
            offset += len(chunk)
        if stamp(successor) != stamp(os.fstat(fd)) or stamp(successor) != stamp(self._named(root, name)):
            raise _MockFileUpdateUnknown('Original Mock replacement changed before acknowledgement')
        ack = _MockFileReplacementAck(self.target, self.operation, expected_stamp,
            hashlib.sha256(actual).hexdigest(), stamp(successor), hashlib.sha256(output).hexdigest(), output)
        self.ack = self.target._latest = ack
        return ack

    def _check_original(self, root: int, name: str, expected_stamp: tuple[int, ...]) -> None:
        assert self._file.fd is not None
        stamp = self.target.files._stamp
        if stamp(os.fstat(self._file.fd)) != expected_stamp or stamp(self._named(root, name)) != expected_stamp:
            raise _MockFileUpdateRefused('Original Mock file changed before replacement')
        self._same_named(root, self._lock)

    def _release_name(self, root: int, member: _OwnedMockName) -> bool:
        if not member.pending:
            return True
        try:
            self._same_named(root, member)
            os.unlink(member.name, dir_fd=root)
        except FileNotFoundError:
            pass
        except (OSError, _MockFileUpdateRefused):
            return False
        member.pending = False
        return True

    def _retire_physical(self) -> bool:
        if self._running:
            return False
        root = self.target.seed._parent.fd
        if root is None:
            return all(not member.pending and member.descriptor.fd is None
                       for member in (self._stage, self._lock)) and self._file.fd is None
        try:
            for member in (self._stage, self._lock):
                if member.pending and member.descriptor.identity is None:
                    self._observe(member.descriptor)
        except (OSError, _MockFileUpdateRefused):
            return False
        return (_close_descriptors([self._file, self._stage.descriptor])
                and self._release_name(root, self._stage)
                and _close_descriptors([self._lock.descriptor])
                and self._release_name(root, self._lock))

    def close(self) -> bool:
        core = self.target.files._core
        with core._lock:
            if self._original is not self:
                raise ValueError('Copied Mock writer cannot close the original')
            if self._closed:
                return True
            self._closing = True
            if self._running or self._uncertain_ticket is not None and not core._closed:
                return False
            if not core._closed and self._workspace is not None:
                if not core.close_workspace(self._workspace):
                    return False
            if not self._retire_physical():
                return False
            self._workspace = None
            self._uncertain_ticket = None
            if self.target._writer is self:
                self.target._writer = None
            self._closed = True
            return True
