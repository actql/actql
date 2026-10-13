"""Owned POSIX spawn/wait observations; Common Owners retain all decisions.

No production launch selection or funding is supplied by this module. The
installed assembly must supply the original interpreter/environment/slot and
complete pre-spawn funding. A child PID, exit or EOF is not an execution ACK.
"""
from __future__ import annotations

from dataclasses import dataclass
import fcntl
import os
from pathlib import Path
from threading import RLock

from ._local_distribution import _hex, _read_file
from ._local_worker_funding import OriginalWorkerFunding, LocalWorkerFundingUnavailable
from ._local_worker_slot import OriginalWorkerSlot, _OriginalDescriptor


class LocalWorkerProcessPending(RuntimeError):
    """Retain this original process/descriptors; do not spawn again."""

    def __init__(self, process: OriginalWorkerProcess) -> None:
        self.cleanup_process = process
        super().__init__('Original Local worker physical process is unconfirmed')


@dataclass(frozen=True, slots=True, eq=False)
class _OriginalChildExit:
    owner: object
    status: int

    def __copy__(self) -> _OriginalChildExit:
        raise TypeError('Original worker child observation cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _OriginalChildExit:
        raise TypeError('Original worker child observation cannot be copied')


class OriginalWorkerProcess:
    """One physical child, not a scheduler, Run or recovery controller.

    The child entry must await the Owner-issued bootstrap frame before DLL,
    Config or Engine work. This port does not send that frame or admit a Run.
    None environment/interpreter originals never select the caller environment.
    """

    def __init__(self, funding: OriginalWorkerFunding | None, slot: OriginalWorkerSlot,
                 *, executable: Path | None, executable_bytes: int | None,
                 executable_sha256: str | None,
                 environment: tuple[tuple[str, str], ...] | None) -> None:
        if type(funding) is not OriginalWorkerFunding:
            raise LocalWorkerFundingUnavailable('Original worker physical funding is unavailable')
        if (type(slot) is not OriginalWorkerSlot or slot._funding is not funding
                or not isinstance(executable, Path) or not executable.is_absolute()
                or type(executable_bytes) is not int or not 0 < executable_bytes <= 2**63 - 1
                or not _hex(executable_sha256, 64) or type(environment) is not tuple):
            raise ValueError('Original installed worker launch selection is unavailable')
        selected: dict[str, str] = {}
        for item in environment:
            if (type(item) is not tuple or len(item) != 2 or type(item[0]) is not str
                    or type(item[1]) is not str or item[0] in selected
                    or item[0] not in ('LANG', 'LC_ALL', 'LC_CTYPE', 'TMPDIR')
                    or '\x00' in item[1] or len(item[1].encode('utf-8')) > 4096):
                raise ValueError('Invalid original selected worker environment')
            selected[item[0]] = item[1]
        self._original = self
        self._lock = RLock()
        self._funding, self._slot = funding, slot
        self._executable, self._executable_bytes = executable, executable_bytes
        self._executable_sha256 = executable_sha256
        self._environment = selected
        self._descriptors: list[_OriginalDescriptor] = []
        self._stdin: tuple[_OriginalDescriptor, _OriginalDescriptor] | None = None
        self._stdout: tuple[_OriginalDescriptor, _OriginalDescriptor] | None = None
        self._stderr: tuple[_OriginalDescriptor, _OriginalDescriptor] | None = None
        self._spawn_attempted = False
        self._pid: int | None = None
        self._exit: _OriginalChildExit | None = None
        self._wait_unknown: BaseException | None = None
        self._closing = False
        self._parent_closed = False
        slot._bind_process(self)

    def __copy__(self) -> OriginalWorkerProcess:
        raise TypeError('Original Local worker process cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> OriginalWorkerProcess:
        raise TypeError('Original Local worker process cannot be copied')

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Foreign original worker process')

    def _launchable(self) -> None:
        self._nominal()
        if self._closing:
            raise ValueError('Original worker process descriptors are closing')

    def _pipe(self) -> tuple[_OriginalDescriptor, _OriginalDescriptor]:
        read, write = os.pipe()
        originals = (_OriginalDescriptor(read), _OriginalDescriptor(write))
        # Register the complete original pair before duplication can fail.
        self._descriptors.extend(originals)
        moved = []
        for original in originals:
            value = _OriginalDescriptor(fcntl.fcntl(original.value, fcntl.F_DUPFD_CLOEXEC, 10))
            self._descriptors.append(value)
            moved.append(value)
            original.close()
        return moved[0], moved[1]

    def spawn(self) -> None:
        with self._lock:
            self._launchable()
            if self._spawn_attempted:
                raise RuntimeError('Original worker spawn was already attempted')
            self._funding.require_launch()
            self._launchable()
            self._spawn_attempted = True
            try:
                # Same-FD nofollow/size/digest check; no PATH search or system
                # interpreter fallback. Startup attestation is still required.
                _read_file(self._executable, maximum=self._executable_bytes,
                           expected=self._executable_bytes, digest=self._executable_sha256)
                slot_action = self._slot.inheritance_action()
                self._stdin, self._stdout, self._stderr = self._pipe(), self._pipe(), self._pipe()
                actions = [slot_action,
                    (os.POSIX_SPAWN_DUP2, self._stdin[0].value, 0),
                    (os.POSIX_SPAWN_DUP2, self._stdout[1].value, 1),
                    (os.POSIX_SPAWN_DUP2, self._stderr[1].value, 2)]
                actions.extend((os.POSIX_SPAWN_CLOSE, value.value) for value in self._descriptors if not value.closed)
                actions.append((os.POSIX_SPAWN_CLOSE, slot_action[1]))
                self._funding.require_launch()
                self._launchable()
                pid = os.posix_spawn(str(self._executable),
                    (str(self._executable), '-I', '-m', 'actql_sdk._local_worker_entry'),
                    dict(self._environment), file_actions=actions, setpgroup=0)
                # Capture the actual child before parent descriptor closes or
                # any postcheck can fail. Exec failure after spawn is not a
                # known-unstarted admission result.
                self._pid = pid
                if type(pid) is not int or pid <= 0:
                    self._wait_unknown = RuntimeError('Original child identity is unavailable')
                    raise RuntimeError('Original child identity is unavailable')
                self._stdin[0].close()
                self._stdout[1].close()
                self._stderr[1].close()
                self._slot.close()
            except BaseException as failure:
                raise LocalWorkerProcessPending(self) from failure

    def observe_child_exit(self) -> _OriginalChildExit | None:
        """Reap only this original direct child. Descendant/slot stop is separate."""
        with self._lock:
            self._nominal()
            if self._pid is None or not self._spawn_attempted:
                raise ValueError('Original worker child is unavailable')
            if self._wait_unknown is not None:
                raise LocalWorkerProcessPending(self) from self._wait_unknown
            if self._exit is not None:
                return self._exit
            try:
                pid, status = os.waitpid(self._pid, os.WNOHANG)
                if pid == 0:
                    return None
                if pid != self._pid or not (os.WIFEXITED(status) or os.WIFSIGNALED(status)):
                    raise RuntimeError('Original worker wait observation is unavailable')
                self._exit = _OriginalChildExit(self, status)
                return self._exit
            except BaseException as failure:
                # Another reaper/error may have consumed the original child.
                # Do not signal a guessed/reused PID or turn this into stop.
                self._wait_unknown = failure
                raise LocalWorkerProcessPending(self) from failure

    def close_parent_descriptors(self) -> None:
        """One physical close pass, never process stop or delegated settlement."""
        with self._lock:
            self._nominal()
            if self._parent_closed:
                return
            self._closing = True
            failure: BaseException | None = None
            # Keep sticky Unknown descriptors, while retiring other original
            # ends exactly once. A failed end must not strand the rest forever.
            for value in reversed(self._descriptors):
                try:
                    value.close()
                except BaseException as caught:
                    if failure is None:
                        failure = caught
            try:
                self._slot.close()
            except BaseException as caught:
                if failure is None:
                    failure = caught
            if failure is not None:
                raise LocalWorkerProcessPending(self) from failure
            self._parent_closed = True
