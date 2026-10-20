"""Native executor-slot physical primitives for an originally funded worker.

Same private-file/flock/inherited-description rules as platform_native's slot.
This does not issue Run/current authority, interpret process exit or settle a
delegation. The installer supplies the original slot path; no SDK path option.
"""
from __future__ import annotations

import fcntl
import os
from pathlib import Path
import stat
from typing import NoReturn

from ._local_files import PhysicalFileIdentity
from ._local_worker_funding import OriginalWorkerFunding, LocalWorkerFundingUnavailable


def _bounded_original_path_text(value: object) -> str:
    """Bound selected path bytes before constructing paths or invoking callbacks."""
    if type(value) is not str or not 0 < len(value) <= 4096 or '\x00' in value:
        raise ValueError('Invalid bounded original worker path text')
    if not 0 < len(os.fsencode(value)) <= 4096:
        raise ValueError('Invalid bounded original worker path bytes')
    return value


class LocalWorkerSlotPending(RuntimeError):
    """Keep the same original descriptors; never a close or process-stop ACK."""

    def __init__(self, slot: OriginalWorkerSlot) -> None:
        self.cleanup_slot = slot
        super().__init__('Original Local worker slot is unconfirmed')


class _OriginalDescriptor:
    """One physical descriptor and its one-shot close observation."""

    def __init__(self, descriptor: int) -> None:
        self._original = self
        self.value = descriptor
        self.closed = False
        self.close_attempted = False
        self.close_failure: BaseException | None = None

    def __copy__(self) -> NoReturn:
        raise TypeError('Original physical descriptor cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> NoReturn:
        raise TypeError('Original physical descriptor cannot be copied')

    def __reduce__(self) -> NoReturn:
        raise TypeError('Original physical descriptor cannot be serialized')

    def close(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original physical descriptor')
        if self.closed:
            return
        if self.close_attempted:
            raise RuntimeError('Original worker descriptor close remains unknown') from self.close_failure
        self.close_attempted = True
        try:
            os.close(self.value)
        except BaseException as failure:
            self.close_failure = failure
            raise
        self.closed = True


class OriginalWorkerSlot:
    """Retain an original slot without unlinking, replacing or unlocking it."""

    def __init__(self, funding: OriginalWorkerFunding | None, path: str) -> None:
        if type(funding) is not OriginalWorkerFunding:
            raise LocalWorkerFundingUnavailable('Original Local worker funding is unavailable')
        selected_path = Path(_bounded_original_path_text(path))
        if not selected_path.is_absolute():
            raise ValueError('Invalid installed original worker slot path')
        self._original = self
        self._funding = funding
        self._path = selected_path
        self._descriptors: list[_OriginalDescriptor] = []
        self._slot: _OriginalDescriptor | None = None
        self._identity: PhysicalFileIdentity | None = None
        self._open_attempted = False
        self._acquired = False
        self._closing = False
        self._closed = False
        self._process_consumer: object | None = None

    def __copy__(self) -> OriginalWorkerSlot:
        raise TypeError('Original Local worker slot cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> OriginalWorkerSlot:
        raise TypeError('Original Local worker slot cannot be copied')

    def _nominal(self) -> None:
        if self._original is not self or self._closing or self._closed:
            raise ValueError('Foreign or closing original worker slot')

    def _bind_process(self, consumer: object) -> None:
        self._nominal()
        if self._process_consumer is not None:
            raise ValueError('Original worker slot already has a process')
        self._process_consumer = consumer

    @staticmethod
    def _private(status: os.stat_result) -> bool:
        return stat.S_ISREG(status.st_mode) and status.st_uid == os.geteuid() and status.st_mode & 0o077 == 0

    def open(self) -> None:
        self._nominal()
        if self._open_attempted:
            raise RuntimeError('Original worker slot open was already attempted')
        self._funding.require_launch()
        self._nominal()
        self._open_attempted = True
        try:
            # Register each descriptor before any later operation can fail.
            original = _OriginalDescriptor(os.open(self._path,
                os.O_RDWR | os.O_CREAT | os.O_CLOEXEC | os.O_NOFOLLOW, 0o600))
            self._descriptors.append(original)
            status = os.fstat(original.value)
            if not self._private(status):
                raise ValueError('Original worker slot is not a private regular file')
            moved = _OriginalDescriptor(fcntl.fcntl(original.value, fcntl.F_DUPFD_CLOEXEC, 10))
            self._descriptors.append(moved)
            self._slot = moved
            self._identity = PhysicalFileIdentity(status.st_dev, status.st_ino)
            original.close()
        except BaseException as failure:
            self._closing = True
            raise LocalWorkerSlotPending(self) from failure

    def _verify_named(self) -> None:
        if (self._slot is None or self._slot.closed or self._slot.close_attempted
                or self._identity is None):
            raise ValueError('Original worker slot descriptor is unavailable')
        opened = os.fstat(self._slot.value)
        named = os.lstat(self._path)
        if (not self._private(opened) or not stat.S_ISREG(named.st_mode)
                or PhysicalFileIdentity(opened.st_dev, opened.st_ino) != self._identity
                or PhysicalFileIdentity(named.st_dev, named.st_ino) != self._identity):
            raise ValueError('Original worker slot was replaced or is unavailable')

    def try_acquire(self) -> bool:
        """Physical lock only; false is busy, not absence or execution refusal."""
        self._nominal()
        self._funding.require_launch()
        self._nominal()
        self._verify_named()
        assert self._slot is not None
        try:
            fcntl.flock(self._slot.value, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError:
            self._acquired = False
            return False
        self._acquired = True
        return True

    def inheritance_action(self) -> tuple[int, int, int]:
        """Borrow fd3's same open description for the existing spawn port.

        This is an OS file action, never a serialized lease or a start permit.
        Keep the original parent slot until spawn returns its actual child.
        """
        self._nominal()
        self._funding.require_launch()
        self._nominal()
        if not self._acquired:
            raise ValueError('Original worker slot is not held')
        self._verify_named()
        assert self._slot is not None
        fcntl.flock(self._slot.value, fcntl.LOCK_EX | fcntl.LOCK_NB)
        return os.POSIX_SPAWN_DUP2, self._slot.value, 3

    def close(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original worker slot')
        if self._closed:
            return
        self._closing = True
        try:
            for descriptor in reversed(self._descriptors):
                descriptor.close()
        except BaseException as failure:
            # A failed close may consume/reuse the raw number. Preserve this
            # same slot; never reclose it, unlink the file or infer lock release.
            raise LocalWorkerSlotPending(self) from failure
        self._closed = True
