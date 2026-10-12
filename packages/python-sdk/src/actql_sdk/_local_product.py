"""Installed Local assembly over the original Core/File/Store Owners.

This is the in-process Host's connection assembly, not a Run controller. The
public factory is connected only after its operation/Result ports are ready.
No bootstrap/profile/epoch result is an admission or execution permission.
"""
from __future__ import annotations

from collections.abc import Callable
from datetime import datetime, timezone
import hashlib
import os
from pathlib import Path
import stat
import time
from typing import Any, TypeVar

from . import _wire as wire
from ._local_core import LocalCore, LocalCoreInitializationError, LocalCoreResources, _Input, _Output
from ._local_distribution import installed_local_components, load_local_module
from ._local_installation import OriginalLocalInstallation, LocalInstallationCleanupPending, _object
from ._local_preparation import LocalPreparation
from ._local_run import LocalRunCustody, _RunConfiguration
from ._local_storage import ByteWrite, LocalStorageError
from ._values import wire_bytes

_T = TypeVar('_T')
_LOCAL_SELECTION = {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                    'consentRefs': [], 'runners': []}


class LocalProductCleanupPending(RuntimeError):
    def __init__(self, host: 'InstalledLocalHost') -> None:
        super().__init__('Installed Local Host cleanup is pending')
        self.cleanup_host = host


def _default_directory() -> Path:
    """Choose the private standard location, never a Program-supplied path."""
    # The installed resolver already rejects non-Darwin/arm64 profiles.
    directory = Path.home() / 'Library' / 'Application Support' / 'ActQL' / 'Python Local'
    parent = directory.parent
    parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    parent_info = parent.lstat()
    if not stat.S_ISDIR(parent_info.st_mode) or parent_info.st_uid != os.getuid():
        raise ValueError('Python Local state parent is unavailable')
    directory.mkdir(mode=0o700, exist_ok=True)
    info = directory.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise ValueError('Python Local requires a private owned state directory')
    return directory


class InstalledLocalHost:
    """Compose installed originals and typed current with existing SDK transport.

    The held fields are physical/Core loans, not copied Run/admission/recovery
    state. Reopen consumes the same saved originals; it does not renew Policy,
    recreate an epoch key, adopt another Store, or send any operation.
    """

    def __init__(self, core: LocalCore, directory: Path, *,
                 now: Callable[[], int], observed_at: str) -> None:
        if type(core) is not LocalCore or not callable(now):
            raise ValueError('Installed Local Host requires its original Core')
        self._original = self
        self._core = core
        self._now = now
        self._installation: OriginalLocalInstallation | None = None
        self._preparation = LocalPreparation(core)
        self._runs = LocalRunCustody(core, self._preparation)
        self._configuration: _RunConfiguration | None = None
        self._inputs: list[_Input] = []
        self._projections: list[_Output] = []
        self._uncertain_ticket: int | None = None
        self._closing = False
        try:
            self._installation = OriginalLocalInstallation(core, directory,
                observed_at=observed_at, now=now, project_epoch=self._project_epoch)
            # Exact original file bytes supply only a CID claim. Core validates
            # that claim and the policy body; it is not publisher authority.
            binding = self._installation.binding
            policy = next(value for value in binding._selected if value.name == 'result-policy.json')
            raw = binding._source.original_bytes(policy)
            setup = self._copy(wire_bytes({'namespace': 'local', 'source_free_result_policy': {  # type: ignore[no-untyped-call]
                'cid': 'sha256:' + hashlib.sha256(raw).hexdigest(), 'body': raw.decode('utf-8')}}))
            def configure(current: _Output) -> None:
                self._configuration = self._runs.install_current_configuration(current, setup)
            binding.inspect(configure)
        except BaseException as failure:
            if isinstance(failure, LocalInstallationCleanupPending):
                self._installation = failure.cleanup_installation
            raise LocalProductCleanupPending(self) from failure

    @classmethod
    def installed(cls, *, resources: LocalCoreResources) -> InstalledLocalHost:
        """Resolve the selected cohort with no endpoint/token/internal paths."""
        components = installed_local_components()
        # Product assembly supplies its reviewed finite Root profile. The old
        # minimal buffer fixture has no allowance for initialization workspace.
        core = LocalCore(load_local_module(components), digest=components.module_sha256,
            transfer_capacity=12 * 1024 * 1024, slots=64,
            resources=resources)
        try:
            directory = _default_directory()
            now = lambda: time.time_ns() // 1_000_000
            observed_at = datetime.now(timezone.utc).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
            return cls(core, directory, now=now, observed_at=observed_at)
        except LocalProductCleanupPending:
            raise
        except BaseException:
            # Construction has not returned a Host; preserve its same Core if
            # cleanup cannot finish, rather than replacing it with a new one.
            if not core.close():
                raise LocalCoreInitializationError(core) from None
            raise

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied installed Local Host')

    def _active(self) -> OriginalLocalInstallation:
        self._nominal()
        if self._closing or self._core._closing or self._installation is None:
            raise ValueError('Installed Local Host is unavailable')
        return self._installation

    def _reserve(self, acquire: Callable[[], _T]) -> _T:
        ticket = self._core._next_ticket
        self._uncertain_ticket = ticket
        try:
            value = acquire()
        except BaseException:
            if ticket not in self._core._inputs and ticket not in self._core._released:
                self._uncertain_ticket = None
            raise
        self._uncertain_ticket = None
        return value

    def _copy(self, raw: bytes) -> _Input:
        loan = self._reserve(lambda: self._core.reserve_input(raw,
            cleanup=lambda: True, stopped=lambda _: True))
        self._inputs.append(loan)
        for start in range(0, len(raw), 16384):
            self._core.fill_input(loan, start, min(16384, len(raw) - start))
        self._core.seal_input(loan)
        return loan

    def _project_epoch(self, kind: int, raw: bytes) -> bytes:
        """Forward the physical key/clock body through the same current Owner."""
        installation = self._active()
        if self._configuration is None:
            raise ValueError('Original Local Run configuration is unavailable')
        configuration = self._configuration
        with self._core._lock:
            source = self._copy(raw)
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, kind, cleanup=lambda: True))
            self._projections.append(output)
            captured: list[bytes] = []
            def project(_: _Output) -> None:
                self._core.produce_submission_projection(output)
                captured.append(self._core.read_submission_projection(output))
            installation.binding.inspect(project)
            if not self._core.close_submission_projection(output):
                raise LocalProductCleanupPending(self)
            self._projections.remove(output)
            if not self._core.close_input(source):
                raise LocalProductCleanupPending(self)
            self._inputs.remove(source)
            return captured[0]

    def profile(self) -> dict[str, Any]:
        """Read original Core scope and explicitly issue its authenticated epoch.

        No submitted input, Run, Source, Compute, Model or Effect is started.
        Scope metadata is not reused as an Allow or publisher grant.
        """
        installation = self._active()
        with self._core._lock:
            scopes: list[str] = []
            def original_scope(current: _Output) -> None:
                self._core.produce_host_current(current)
                body = _object(self._core.read_host_current(current), 65536)
                if set(body) != {'account', 'account_configuration_cid', 'authority_scope_cid'}:
                    raise ValueError('Invalid original Local current projection')
                scope = body['authority_scope_cid']
                if not wire.valid(scope, {'type': 'string', 'pattern': '^sha256:[0-9a-f]{64}$'}):  # type: ignore[no-untyped-call]
                    raise ValueError('Invalid original Local authority scope')
                scopes.append(scope)
            installation.binding.inspect(original_scope)
            if installation._epoch is None:
                raise ValueError('Original Local epoch custody is unavailable')
            epoch = installation._epoch.issue_epoch(scopes[0])
            profile = {'version': 'actql-client-host/0.1', 'mode': 'local', 'owner': 'local',
                'durability': 'durable', 'scopeRef': scopes[0], 'submissionEpoch': epoch,
                'capabilities': [], 'limits': {'maxReadWireBytes': 1048576,
                    'maxRowWireBytes': 65536, 'maxRowRetainedValueBytes': 262144,
                    'maxRetainedValueBytes': 1048576, 'maxRows': 1000,
                    'maxBatchRows': 32, 'maxBatchRetainedValueBytes': 1048576}}
            if not wire.negotiated(profile, 'profile', _LOCAL_SELECTION):  # type: ignore[no-untyped-call]
                raise ValueError('Invalid installed Local Host profile')
            return profile

    def _retain_intent(self, reference: object, intent: bytes) -> _Output:
        """Keep the original unchecked intent before invoking preparation.

        Core selects the same issued CAS and preparing row. Physical success
        acknowledges only those original rows, never a Run or execution. A
        failed or unknown COMMIT retains the same output/input loans; this
        method does not retry, reconstruct a reference or reissue an epoch.
        """
        installation = self._active()
        if installation._epoch is None or installation._store is None or self._configuration is None:
            raise ValueError('Original Local submission suppliers are unavailable')
        with self._core._lock:
            # Authentication is performed by the original physical epoch
            # supplier. Its Core projection checks current original scope.
            identity = installation._epoch.identity(reference)
            raw = wire_bytes({'reference': wire_bytes(reference).decode('utf-8'),  # type: ignore[no-untyped-call]
                              'intent': intent.decode('utf-8'),
                              'now': installation._epoch._observed_clock})
            source = self._copy(raw)
            configuration = self._configuration
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, 3, cleanup=lambda: True))
            self._projections.append(output)
            captured: list[dict[str, Any]] = []
            def observe(current: _Output) -> None:
                self._core.produce_submission_append(output, current)
                captured.append(_object(self._core.read_submission_append(output, current), 1048576))
            installation.binding.inspect(observe)
            candidate = captured[0]
            kind = candidate.get('kind')
            fields = ({'kind', 'key', 'body', 'issued_revision', 'issued_body'} if kind == 'append'
                      else {'kind', 'key', 'body', 'revision'} if kind == 'retained' else set())
            if (not fields or set(candidate) != fields or
                    any(type(candidate[name]) is not str for name in fields) or
                    candidate['key'] != identity.request_id):
                raise ValueError('Invalid original Core submitted intent projection')
            if kind == 'retained':
                # A retained preparing or ready record is observation only.
                # Run/phase explanation must come from its original Core Owner.
                return output
            revision = candidate['issued_revision']
            if (not revision.isascii() or not revision.isdecimal() or
                    (len(revision) > 1 and revision.startswith('0')) or
                    len(revision) > 19 or int(revision) > 2**63 - 1):
                raise ValueError('Invalid original Core issued generation')
            store = installation._store
            writes = (
                ByteWrite(store.namespaced_key('client_submitted_intent_custody', 'issued'),
                          int(revision), candidate['issued_body'].encode('utf-8')),
                ByteWrite(store.namespaced_key('client_submitted_intents', candidate['key']),
                          None, candidate['body'].encode('utf-8')),
            )
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    installation.binding.inspect_reader(reader, lambda current:
                        self._core.validate_submission_append(output, current))
                result = store.compare_exchange_many_inspected(
                    writes, fences, inspect=inspect, current=installation.binding.current)
            if result is None:
                raise LocalStorageError('Original Local submitted intent write conflicted; lookup is required')
            return output

    def close(self) -> bool:
        """Stop this Host's resources only; never cancel/replay/delete a Run."""
        self._nominal()
        with self._core._lock:
            self._closing = True
            if self._uncertain_ticket is not None and not self._core._closed:
                return False
            for output in tuple(reversed(self._projections)):
                closed = (self._core.close_submission_append(output) if output.family == 'submission_append'
                          else self._core.close_submission_projection(output))
                if not closed:
                    return False
                self._projections.remove(output)
            if self._configuration is not None:
                if not self._runs.close_configuration(self._configuration):
                    return False
                self._configuration = None
            for source in tuple(reversed(self._inputs)):
                if not self._core.close_input(source):
                    return False
                self._inputs.remove(source)
            if self._installation is not None:
                if not self._installation.close():
                    return False
                self._installation = None
            return self._core.close()
