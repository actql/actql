"""Owned POSIX spawn/wait observations; Common Owners retain all decisions.

No production launch selection or funding is supplied by this module. The
installed assembly must supply the original interpreter/environment/slot and
complete pre-spawn funding. A child PID, exit or EOF is not an execution ACK.
"""
from __future__ import annotations

from dataclasses import dataclass
import fcntl
import hashlib
import os
from pathlib import Path
import stat
from threading import RLock, current_thread
from typing import TYPE_CHECKING

if TYPE_CHECKING:
    from ._local_native_domain_custody import _OriginalDomainCustody, _OriginalDomainMaterial

from ._local_distribution import _hex
from ._local_worker_funding import OriginalWorkerFunding, LocalWorkerFundingUnavailable
from ._local_worker_slot import OriginalWorkerSlot, _OriginalDescriptor, _bounded_original_path_text


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
                 *, executable: str | None, executable_bytes: int | None,
                 executable_sha256: str | None,
                 executable_image: str | None, executable_link: str | None,
                 environment: tuple[tuple[str, str], ...] | None) -> None:
        if type(funding) is not OriginalWorkerFunding:
            raise LocalWorkerFundingUnavailable('Original worker physical funding is unavailable')
        if (type(slot) is not OriginalWorkerSlot or slot._funding is not funding
                or type(executable_bytes) is not int or not 0 < executable_bytes <= 2**63 - 1
                or not _hex(executable_sha256, 64) or type(environment) is not tuple or len(environment) > 4):
            raise ValueError('Original installed worker launch selection is unavailable')
        selected_executable = Path(_bounded_original_path_text(executable))
        selected_image = Path(_bounded_original_path_text(executable_image))
        selected_link = (None if executable_link is None
            else _bounded_original_path_text(executable_link))
        if (not selected_executable.is_absolute() or not selected_image.is_absolute()
                or selected_link is None and selected_executable != selected_image
                or selected_link is not None and
                    Path(os.path.abspath(selected_executable.parent / selected_link)) != selected_image):
            raise ValueError('Invalid original worker executable image selection')
        selected: dict[str, str] = {}
        for item in environment:
            if (type(item) is not tuple or len(item) != 2 or type(item[0]) is not str
                    or type(item[1]) is not str
                    or item[0] not in ('LANG', 'LC_ALL', 'LC_CTYPE', 'TMPDIR')
                    or item[0] in selected or len(item[1]) > 4096
                    or '\x00' in item[1] or len(item[1].encode('utf-8')) > 4096):
                raise ValueError('Invalid original selected worker environment')
            selected[item[0]] = item[1]
        self._original = self
        self._lock = RLock()
        self._funding, self._slot = funding, slot
        self._executable, self._executable_bytes = selected_executable, executable_bytes
        self._executable_image, self._executable_link = selected_image, selected_link
        self._launch_identity: tuple[int, int, int, int] | None = None
        self._executable_sha256 = executable_sha256
        self._environment = selected
        self._descriptors: list[_OriginalDescriptor] = []
        self._stdin: tuple[_OriginalDescriptor, _OriginalDescriptor] | None = None
        self._stdout: tuple[_OriginalDescriptor, _OriginalDescriptor] | None = None
        self._stderr: tuple[_OriginalDescriptor, _OriginalDescriptor] | None = None
        self._native_domain: _OriginalDomainCustody | None = None
        self._native_material: _OriginalDomainMaterial | None = None
        self._native_source: _OriginalDescriptor | None = None
        self._native_source_value: int | None = None
        self._native_funding_originals: tuple[object | None, object | None, object | None, object | None] | None = None
        self._native_duplicate: _OriginalDescriptor | None = None
        self._native_duplicate_value: int | None = None
        self._native_dup_unknown = False
        self._native_metadata_retired = False
        self._native_retirement_inflight = False
        self._native_retirement_unknown: BaseException | None = None
        self._descriptor_prepare_attempted = False
        self._descriptor_prepare_active = False
        self._descriptors_prepared = False
        self._spawn_syscall_attempted = False
        self._spawn_attempted = False
        self._spawn_active = False
        self._pid: int | None = None
        self._exit: _OriginalChildExit | None = None
        self._wait_unknown: BaseException | None = None
        self._closing = False
        self._parent_closed = False
        self._parent_close_inflight = False
        self._parent_pipe_consumer: object | None = None
        self._parent_pipe_borrowed = False
        slot._bind_process(self)
        # Exact Native funding has one original backing descriptor. Generic
        # syscall-only diagnostics have no such domain and cannot supply it.
        from ._local_native_domain_custody import _OriginalDomainCustody
        if type(funding._physical) is _OriginalDomainCustody:
            try:
                self._bind_original_native_domain()
            except BaseException as failure:
                raise LocalWorkerProcessPending(self) from failure

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

    def _bind_parent_pipe(self, consumer: object) -> None:
        with self._lock:
            self._launchable()
            if self._parent_pipe_consumer is not None:
                raise ValueError('Original worker parent pipes already have a consumer')
            self._parent_pipe_consumer = consumer

    def _borrow_parent_pipe(self, consumer: object, kind: str) -> _OriginalDescriptor:
        with self._lock:
            self._launchable()
            if (consumer is not self._parent_pipe_consumer or self._parent_pipe_borrowed
                    or type(self._pid) is not int or self._pid <= 0
                    or self._wait_unknown is not None):
                raise ValueError('Original worker parent pipe is unavailable')
            pair = {'stdin': self._stdin, 'stdout': self._stdout, 'stderr': self._stderr}.get(kind)
            if pair is None:
                raise ValueError('Original worker pipe is unavailable')
            descriptor = pair[1] if kind == 'stdin' else pair[0]
            if descriptor.closed or descriptor.close_attempted:
                raise ValueError('Original worker parent descriptor is unavailable')
            self._parent_pipe_borrowed = True
            return descriptor

    def _return_parent_pipe(self, consumer: object) -> None:
        with self._lock:
            self._nominal()
            if consumer is not self._parent_pipe_consumer or not self._parent_pipe_borrowed:
                raise ValueError('Foreign original worker pipe borrow')
            # Returning a stopped Python I/O invocation is not worker stop,
            # independent resource cleanup or execution-delegation settlement.
            self._parent_pipe_borrowed = False

    def _bind_original_native_domain(self) -> None:
        from ._local_native_domain_custody import _OriginalDomainCustody, _OriginalDomainMaterialFunctions
        domain, funding = self._funding._physical, self._funding
        if (type(domain) is not _OriginalDomainCustody or funding._delegation is not domain
                or funding._ledger is not domain._owner or domain._worker_process_original is not None):
            raise LocalWorkerFundingUnavailable('Original Native domain process binding is unavailable')
        # Publish the same partial process before any current/material callback.
        self._native_domain = domain
        self._native_source = domain._descriptor
        self._native_source_value = domain._descriptor.value
        self._native_funding_originals = (funding._physical, funding._ledger, funding._delegation, funding._durable)
        domain._worker_process_original = self
        self._funding.require_launch()
        self._launchable()
        self._require_native_identity()
        material = domain._project_original_material(
            _OriginalDomainMaterialFunctions(domain._functions.library))
        self._require_native_identity()
        self._native_material = material
        self._funding.require_launch()
        self._launchable()
        self._require_native_identity()

    def _require_native_identity(self) -> None:
        domain, funding, descriptor = self._native_domain, self._funding, self._native_source
        if domain is not None:
            if domain._unknown is not None: raise domain._unknown
            if domain._owner._unknown is not None: raise domain._owner._unknown
        if (domain is None or descriptor is None or self._native_metadata_retired
                or domain._worker_process_original is not self or domain._descriptor is not descriptor
                or domain._closed or domain._unknown is not None
                or domain._domain.value is None or domain._owner._closed
                or domain._owner._unknown is not None
                or domain._owner._process != os.getpid() or domain._owner._thread is not current_thread()
                or self._native_funding_originals is None
                or any(a is not b for a, b in zip(self._native_funding_originals,
                    (funding._physical, funding._ledger, funding._delegation, funding._durable)))
                or descriptor._original is not descriptor or descriptor.closed or descriptor.close_attempted
                or type(descriptor.value) is not int or descriptor.value != self._native_source_value
                or not 0 <= descriptor.value <= 2**31 - 1):
            raise ValueError('Original Native domain or descriptor changed')

    def _require_native_current(self) -> None:
        self._launchable()
        if self._native_domain is None:
            from ._local_native_domain_custody import _OriginalDomainCustody
            if type(self._funding._physical) is _OriginalDomainCustody:
                raise LocalWorkerFundingUnavailable('Unbound original Native domain cannot launch')
            return
        self._require_native_identity()
        if self._native_material is None:
            raise ValueError('Original Native domain material is unavailable')
        self._native_domain.current()
        self._require_native_identity()
        self._funding.require_launch()
        self._launchable()
        self._require_native_identity()
        duplicate = self._native_duplicate
        if duplicate is not None and not self._spawn_syscall_attempted:
            if (duplicate._original is not duplicate or duplicate.closed or duplicate.close_attempted
                    or self._native_dup_unknown or self._native_duplicate_value is None
                    or type(duplicate.value) is not int or duplicate.value != self._native_duplicate_value):
                raise ValueError('Original Native inherited descriptor changed before spawn')

    def _duplicate_original_domain(self) -> None:
        if self._native_domain is None:
            return
        self._require_native_current()
        if self._native_duplicate is not None or self._native_dup_unknown:
            raise ValueError('Original Native domain inheritance was already attempted')
        assert self._native_source is not None and self._native_material is not None
        descriptor = self._native_source
        material = self._native_material
        status = os.fstat(descriptor.value)
        if (not stat.S_ISREG(status.st_mode) or status.st_uid != os.geteuid()
                or status.st_mode & 0o077 or status.st_size != material.scalars[3]
                or status.st_dev != material.scalars[1] or status.st_ino != material.scalars[2]):
            raise ValueError('Original Native domain descriptor does not match the Owner material')
        # Register its Unknown before duplication. A lost result cannot permit
        # another FD acquisition or metadata retirement with a guessed close.
        # Allocate and retain the output carrier/list slot before the syscall.
        # Its closed -1 is confirmed unstarted until duplication is attempted;
        # a lost/malformed return remains Unknown and is never closed as fd0/1.
        duplicate = _OriginalDescriptor(-1)
        duplicate.closed = True
        self._native_duplicate = duplicate
        self._descriptors.append(duplicate)
        self._native_dup_unknown = True
        duplicate.closed = False
        value = fcntl.fcntl(descriptor.value, fcntl.F_DUPFD_CLOEXEC, 10)
        if type(value) is not int or not 10 <= value <= 2**31 - 1:
            raise RuntimeError('Original Native inherited descriptor is unknown')
        duplicate.value = value
        self._native_duplicate_value = value
        self._native_dup_unknown = False
        after = os.fstat(duplicate.value)
        if any(getattr(after, name) != getattr(status, name)
               for name in ('st_dev', 'st_ino', 'st_mode', 'st_uid', 'st_size')):
            raise ValueError('Original Native domain duplicate changed')
        self._require_native_current()

    def _retire_native_metadata(self, proof: object) -> None:
        from ._local_native_live_channel import _OriginalLiveChannelCustody
        if (type(proof) is not _OriginalLiveChannelCustody or proof._original is not proof
                or not proof._closed or proof._unknown is not None
                or proof._process is not self or proof._domain is not self._native_domain
                or proof._funding is not self._funding or not self._parent_closed
                or self._native_domain is None or self._native_domain._live_channel_original is not proof
                or proof._pipe._native_channel_original is not proof
                or any(slot.value is not None for slot in
                       (proof._host, proof._native_domain, proof._channel, proof._reply,
                        proof._frame_host, proof._frame_domain, proof._frame_channel,
                        proof._frame, proof._frame_reply))
                or self._native_dup_unknown):
            raise ValueError('Original Native channel retirement is unconfirmed')
        self._finish_native_metadata()

    def _retire_unstarted_native_after_owner_ack(self, observation: object) -> None:
        with self._lock:
            self._nominal()
            if self._native_retirement_unknown is not None:
                raise LocalWorkerProcessPending(self) from self._native_retirement_unknown
            if self._native_retirement_inflight:
                raise RuntimeError('Original Native unstarted cleanup cannot reenter')
            if (self._spawn_syscall_attempted or not self._parent_closed
                    or self._native_dup_unknown or not self._funding._opaque(observation)):
                raise ValueError('Original Native unstarted cleanup is unconfirmed')
            self._require_native_identity()
            self._funding._nominal()
            assert self._native_funding_originals is not None
            self._native_retirement_inflight = True
            try:
                self._funding._ack(self._funding._supplier.require_scoped_stop(
                    *self._native_funding_originals, observation))
                self._nominal()
                self._require_native_identity()
                if self._spawn_syscall_attempted or not self._parent_closed or self._native_dup_unknown:
                    raise ValueError('Original Native cleanup observation changed')
                self._finish_native_metadata()
            except BaseException as failure:
                # A lost/invalid Owner reply does not permit another adoption
                # attempt or release this same original domain/FD responsibility.
                self._native_retirement_unknown = failure
                raise LocalWorkerProcessPending(self) from failure
            finally:
                self._native_retirement_inflight = False

    def _finish_native_metadata(self) -> None:
        # This is metadata retirement after the existing Owner's separate ACKs,
        # not domain close, original FD close, delegation settlement or credit.
        self._require_native_identity()
        assert self._native_domain is not None
        self._native_metadata_retired = True

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

    def _verify_executable(self) -> None:
        # Keep this descriptor in the same process carrier before metadata,
        # reads or close can fail. A generic file context loses close Unknown.
        self._verify_launch_original()
        original = _OriginalDescriptor(os.open(self._executable_image,
            os.O_RDONLY | os.O_NOFOLLOW | os.O_CLOEXEC))
        self._descriptors.append(original)
        primary: BaseException | None = None
        try:
            before = os.fstat(original.value)
            if not stat.S_ISREG(before.st_mode) or before.st_size != self._executable_bytes:
                raise ValueError('Original installed worker executable size is invalid')
            remaining = self._executable_bytes
            checksum = hashlib.sha256()
            while remaining:
                block = os.read(original.value, min(65536, remaining))
                if not block or len(block) > remaining:
                    raise ValueError('Original installed worker executable is incomplete')
                checksum.update(block)
                remaining -= len(block)
            after = os.fstat(original.value)
            if (os.read(original.value, 1) or checksum.hexdigest() != self._executable_sha256
                    or (before.st_dev, before.st_ino, before.st_size, before.st_mtime_ns, before.st_ctime_ns)
                    != (after.st_dev, after.st_ino, after.st_size, after.st_mtime_ns, after.st_ctime_ns)):
                raise ValueError('Original installed worker executable changed')
        except BaseException as failure:
            primary = failure
            raise
        finally:
            try:
                original.close()
            except BaseException:
                # Preserve a prior digest/read failure as well as this FD's
                # independent sticky Unknown. Neither permits another launch.
                if primary is None:
                    raise

    def _verify_launch_original(self) -> None:
        """Keep the selected venv launch path; never replace it with realpath.

        The supplier explicitly selected this one link and readonly image.
        This necessary consistency check is not child startup attestation or
        an atomic pathname execution guarantee. No arbitrary link traversal.
        """
        if self._executable_link is None:
            return
        selected = os.lstat(self._executable)
        if not stat.S_ISLNK(selected.st_mode) or os.readlink(self._executable) != self._executable_link:
            raise ValueError('Original worker launch link changed')
        identity = (selected.st_dev, selected.st_ino, selected.st_mtime_ns, selected.st_ctime_ns)
        if self._launch_identity is None:
            self._launch_identity = identity
        elif identity != self._launch_identity:
            raise ValueError('Original worker launch link identity changed')

    def prepare_original_descriptors(self) -> None:
        """Same funded process: create/retain its original pipes before spawn.

        This is not launch or child/Host admission. The original supplier must
        already cover this process/FD/control phase. Partial pairs and a lost
        duplicate remain in this same process; another preparation is refused.
        """
        with self._lock:
            self._launchable()
            if self._spawn_attempted or self._spawn_active:
                raise RuntimeError('Original worker spawn was already attempted or is active')
            try:
                self._prepare_original_descriptors()
            except BaseException as failure:
                raise LocalWorkerProcessPending(self) from failure

    def _prepare_original_descriptors(self) -> None:
        self._launchable()
        if self._descriptor_prepare_attempted or self._descriptor_prepare_active:
            raise RuntimeError('Original worker descriptor preparation was already attempted or is active')
        # Busy before any current callback can reenter. This guards physical
        # custody only; the existing supplier remains the authority.
        self._descriptor_prepare_active = True
        try:
            self._funding.require_launch()
            self._launchable()
            self._require_native_current()
            self._descriptor_prepare_attempted = True
            self._verify_executable()
            self._duplicate_original_domain()
            self._stdin, self._stdout, self._stderr = self._pipe(), self._pipe(), self._pipe()
            self._funding.require_launch()
            self._launchable()
            self._require_native_current()
            self._descriptors_prepared = True
        finally:
            self._descriptor_prepare_active = False

    def spawn(self) -> None:
        with self._lock:
            self._launchable()
            if self._spawn_attempted or self._spawn_active or self._descriptor_prepare_active:
                raise RuntimeError('Original worker spawn was already attempted or descriptor preparation is active')
            # Scope guard precedes the first supplier/current callback. Keep
            # known pre-entry refusals separate from syscall Unknown below.
            self._spawn_active = True
            try:
                self._funding.require_launch()
                self._launchable()
                self._require_native_current()
                self._spawn_attempted = True
                try:
                    # Same-FD nofollow/size/digest check; no PATH search or system
                    # interpreter fallback. Startup attestation is still required.
                    if self._descriptors_prepared:
                        # A previously prepared interpreter is checked again at
                        # the original launch boundary; no stale pathname proof.
                        self._verify_executable()
                    else:
                        self._prepare_original_descriptors()
                    assert self._stdin is not None and self._stdout is not None and self._stderr is not None
                    slot_action = self._slot.inheritance_action()
                    actions: list[tuple[int, int] | tuple[int, int, int]] = [slot_action,
                        (os.POSIX_SPAWN_DUP2, self._stdin[0].value, 0),
                        (os.POSIX_SPAWN_DUP2, self._stdout[1].value, 1),
                        (os.POSIX_SPAWN_DUP2, self._stderr[1].value, 2)]
                    if self._native_duplicate is not None:
                        # Lift to >=10 before fd3/stdin/stdout/stderr rewrites: the
                        # original backing may itself occupy destination fd3/4.
                        actions.append((os.POSIX_SPAWN_DUP2, self._native_duplicate.value, 4))
                    actions.extend((os.POSIX_SPAWN_CLOSE, value.value) for value in self._descriptors if not value.closed)
                    actions.append((os.POSIX_SPAWN_CLOSE, slot_action[1]))
                    self._funding.require_launch()
                    self._launchable()
                    self._verify_launch_original()
                    self._require_native_current()
                    self._spawn_syscall_attempted = True
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
                    if self._native_duplicate is not None:
                        self._native_duplicate.close()
                    self._stdin[0].close()
                    self._stdout[1].close()
                    self._stderr[1].close()
                    self._slot.close()
                except BaseException as failure:
                    raise LocalWorkerProcessPending(self) from failure
            finally:
                self._spawn_active = False

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
            if self._parent_close_inflight:
                raise RuntimeError('Original worker parent close cannot reenter')
            self._closing = True
            if self._parent_pipe_borrowed:
                raise LocalWorkerProcessPending(self)
            self._parent_close_inflight = True
            try:
                failure: BaseException | None = None
                # Keep sticky Unknown descriptors, while retiring other original
                # ends exactly once. A failed end must not strand the rest forever.
                originals = list(reversed(self._descriptors))
                if (self._native_duplicate is not None
                        and not any(value is self._native_duplicate for value in originals)):
                    originals.insert(0, self._native_duplicate)
                for value in originals:
                    try:
                        if (value is self._native_duplicate and self._native_dup_unknown
                                and self._native_duplicate_value is None):
                            raise RuntimeError('Original Native descriptor acquisition remains unknown')
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
            finally:
                self._parent_close_inflight = False
