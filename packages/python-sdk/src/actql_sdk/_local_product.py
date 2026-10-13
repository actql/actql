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
from ._local_core import LocalCore, LocalCoreError, LocalCoreInitializationError, LocalCoreResources, _Input, _Output, _PublisherFact
from ._local_distribution import installed_local_components, load_local_module
from ._local_installation import OriginalLocalInstallation, LocalInstallationCleanupPending, _object
from ._local_preparation import LocalPreparation, _Environment, _Preparation
from ._local_run import LocalRunCustody, _RunConfiguration, _Run, _PhysicalStart, _SourceFreeCompute
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
                 now: Callable[[], int], observed_at: str, sdk_finite: bool = False) -> None:
        if type(core) is not LocalCore or not callable(now):
            raise ValueError('Installed Local Host requires its original Core')
        self._original = self
        self._core = core
        self._now = now
        self._installation: OriginalLocalInstallation | None = None
        self._preparation = LocalPreparation(core)
        self._environment: _Environment | None = None
        self._prepared_inputs: list[_Preparation] = []
        self._runs = LocalRunCustody(core, self._preparation)
        self._configuration: _RunConfiguration | None = None
        self._run_loans: list[_Run] = []
        self._row_outputs: list[_Output] = []
        self._journal_outputs: list[_Output] = []
        # Physical write-invocation custody, not Run/admission state. A retained
        # attempt cannot be reused as a transport retry or new acceptance.
        self._row_write_attempts: set[int] = set()
        self._pending_run_write: _Output | None = None
        self._step_outputs: list[_Output] = []
        self._step_write_attempts: set[int] = set()
        self._pending_start_write: _Output | None = None
        self._physical_starts: list[_PhysicalStart] = []
        self._source_free_computes: list[_SourceFreeCompute] = []
        self._source_free_invocations: list[tuple[_SourceFreeCompute, _Output]] = []
        self._publication_preflights: list[_Output] = []
        self._publishers: list[_Output] = []
        self._inputs: list[_Input] = []
        self._projections: list[_Output] = []
        self._append_sources: dict[int, _Input] = {}
        self._uncertain_ticket: int | None = None
        self._closing = False
        try:
            self._installation = OriginalLocalInstallation(core, directory,
                observed_at=observed_at, now=now, project_epoch=self._project_epoch, sdk_finite=sdk_finite)
            # Exact original file bytes supply only a CID claim. Core validates
            # that claim and the policy body; it is not publisher authority.
            binding = self._installation.binding
            policy = next(value for value in binding._selected if value.name == 'result-policy.json')
            raw = binding._source.original_bytes(policy)
            setup = self._copy(wire_bytes({'namespace': 'local', 'source_free_result_policy': {  # type: ignore[no-untyped-call]
                'cid': 'sha256:' + hashlib.sha256(raw).hexdigest(), 'body': raw.decode('utf-8')}}))
            def configure(current: _Output) -> None:
                self._configuration = (self._runs.install_sdk_configuration(current, setup)
                    if sdk_finite else self._runs.install_current_configuration(current, setup))
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
            return cls(core, directory, now=now, observed_at=observed_at, sdk_finite=True)
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
            self._append_sources[output.ticket] = source
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

    def _close_projection(self, output: _Output) -> bool:
        """Release only original transport loans after successful cleanup."""
        closed = (self._core.close_submission_append(output) if output.family == 'submission_append'
                  else self._core.close_submission_projection(output))
        if not closed:
            return False
        self._projections.remove(output)
        source = self._append_sources.get(output.ticket)
        if source is not None:
            if not self._core.close_input(source):
                # The output has closed, but its same input remains reachable
                # through _inputs for retry. No semantic record is deleted.
                return False
            del self._append_sources[output.ticket]
            self._inputs.remove(source)
        return True

    def _prepare_original(self, reference: object, intent: bytes) -> _Preparation:
        """Connect the retained original input to its existing Checker.

        The first write must acknowledge normally. Response loss exits before
        preparation and retains all original loans. A fresh same-Store lookup
        then confirms the original intent; it never supplies execution or retry
        permission. Both new and saved inputs use the same normal preparation
        Owner, including declarations, bindings and exact text bytes. Restoring
        a checked input here does not rerun Source, Compute, Model or Effect.
        """
        installation = self._active()
        if type(intent) is not bytes or not 0 < len(intent) <= 65536:
            raise ValueError('Invalid original Local submitted input transport')
        # Capture once before physical IO so a caller cannot change the request
        # identity between retention and the original lookup.
        captured_reference = _object(wire_bytes(reference), 8192)  # type: ignore[no-untyped-call]
        with self._core._lock:
            written = self._retain_intent(captured_reference, intent)
            if not self._close_projection(written):
                raise LocalProductCleanupPending(self)
            observed = self._retain_intent(captured_reference, intent)
            if self._environment is None:
                selected = next(value for value in installation.binding._selected
                                if value.name == 'environment.json')
                source = self._copy(installation.binding._source.original_bytes(selected))
                def install(_: _Output) -> None:
                    self._environment = self._preparation.install_environment(source, profile='source-free')
                installation.binding.inspect(install)
            assert self._environment is not None
            document = self._copy(intent)
            prepared = self._preparation.reserve(self._environment, document, format='submitted')
            self._prepared_inputs.append(prepared)
            def check(current: _Output) -> None:
                # The observed original is revalidated in the same borrowed
                # read snapshot before entering the existing parser/Checker.
                self._core.validate_submission_append(observed, current)
                self._preparation.prepare(prepared)
            installation.binding.inspect(check)
            if not self._close_projection(observed):
                raise LocalProductCleanupPending(self)
            return prepared

    def _accept_original(self, reference: object, intent: bytes, *, run_id: str) -> tuple[_Run, bytes]:
        """Join original preparation, finite issuance, same-TX write and lookup.

        Only Core supplies the Policy, row candidate and saved admission. The
        returned admission does not reserve dispatch or start physical work.
        Existing-ready restoration still requires its original saved materials;
        this entry must not replace them with a fresh Plan or Policy.
        """
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk or configuration.current is None
                or installation._store is None):
            raise ValueError('Original finite Local configuration is unavailable')
        store = installation._store
        captured_reference = _object(wire_bytes(reference), 8192)  # type: ignore[no-untyped-call]
        with self._core._lock:
            if self._pending_run_write is not None:
                raise LocalStorageError('Original Local Run write requires lookup; new acceptance is unavailable')
            prepared = self._prepare_original(captured_reference, intent)
            observed = self._retain_intent(captured_reference, intent)
            source = self._copy(wire_bytes({'run_id': run_id, 'now': self._now()}))  # type: ignore[no-untyped-call]
            run = self._runs.reserve(configuration, prepared, source)
            self._run_loans.append(run)
            decisions: list[str] = []
            installation.binding.inspect(lambda _: decisions.append(self._runs.prepare_sdk(run, observed)))
            if decisions != ['prepared']:
                # Preserve the original loans. Restoration is not fresh accept,
                # a new issuance, or an implicit retry of an uncertain COMMIT.
                raise LocalCoreError('original_run_restore_required', -42)
            captured: list[dict[str, Any]] = []
            installation.binding.inspect(lambda current: captured.append(_object(
                self._core.read_submission_append(observed, current), 1048576)))
            retained = captured[0]
            if (set(retained) != {'kind', 'key', 'body', 'revision'} or
                    retained['kind'] != 'retained' or type(retained['body']) is not str):
                raise ValueError('Invalid original retained submission projection')
            row_input = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'reference': wire_bytes(captured_reference).decode('utf-8'),  # type: ignore[no-untyped-call]
                'preparing': retained['body'], 'now': self._now()}))
            output = self._reserve(lambda: self._runs.reserve_submitted_rows(
                run, configuration, row_input, cleanup=lambda: True))
            self._row_outputs.append(output)
            installation.binding.inspect(lambda _: self._core.produce_material(output))
            self._commit_original_run_rows(output)
            # A fresh same-Store inspection supplies the original saved admission.
            # Neither the candidate nor the successful SQLite API response does.
            journal = self._reserve(lambda: self._core.reserve_journal_observation(
                output, configuration.handle, store=store,
                current=installation.binding.current, cleanup=lambda: True))
            self._journal_outputs.append(journal)
            admission: list[bytes] = []
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    def consume(_: _Output) -> None:
                        self._core.inspect_journal_observation(journal, reader)
                        admission.append(self._core.read_journal_admission(journal, reader))
                    installation.binding.inspect_reader(reader, consume)
                store.inspect_namespaces(
                    fences, inspect=inspect, current=installation.binding.current)
            # The immutable row Owner/input remain in Core. These consumed
            # buffers need not overlap the later dispatch/Compute/Result phase.
            if not self._core.close_journal_observation(journal):
                raise LocalProductCleanupPending(self)
            self._journal_outputs.remove(journal)
            if not self._core.retire_material_output(output):
                raise LocalProductCleanupPending(self)
            if not self._core.retire_submission_append_output(observed):
                raise LocalProductCleanupPending(self)
            self._pending_run_write = None
            return run, admission[0]

    def _commit_original_run_rows(self, output: _Output) -> None:
        """Forward the original Core candidate in one fenced SQLite transaction.

        The Core supplier chooses the Run/counter bytes. Python only transports
        its CAS/insert operations; acknowledged rows are not dispatch, Result,
        publication or cleanup. After attempted COMMIT an exception retains the
        same loans and never enters this write again automatically.
        """
        installation = self._active()
        configuration = self._configuration
        if configuration is None or not configuration.sdk or configuration.current is None:
            raise ValueError('Original finite Local configuration is unavailable')
        store = installation._store
        if store is None:
            raise ValueError('Original Local Store is unavailable')
        with self._core._lock:
            self._core._owned_output(output)
            if not any(original is output for original in self._row_outputs):
                raise ValueError('Foreign original Run row projection')
            if output.ticket in self._row_write_attempts or self._pending_run_write is not None:
                raise LocalStorageError('Original Local Run write requires lookup; transport replay is unavailable')
            captured: list[dict[str, Any]] = []
            installation.binding.inspect(lambda current: captured.append(_object(
                self._core.read_submitted_run_rows(output, current), 1048576)))
            candidate = captured[0]
            fields = {'run_key', 'submission_key', 'preparing', 'run', 'submitted',
                      'issued_revision', 'issued_body'}
            if set(candidate) != fields or any(type(candidate[key]) is not str for key in fields):
                raise ValueError('Invalid original Core Run row projection')
            revision = candidate['issued_revision']
            if (not revision.isascii() or not revision.isdecimal() or
                    (len(revision) > 1 and revision.startswith('0')) or
                    len(revision) > 19 or int(revision) > 2**63 - 1):
                raise ValueError('Invalid original Core Run issued generation')
            # Original preparing insertion has revision zero. Core revalidates
            # its exact bytes/reference/intent and candidate before these writes.
            writes = (
                ByteWrite(store.namespaced_key('client_run_custody', 'issued'),
                          int(revision), candidate['issued_body'].encode('utf-8')),
                ByteWrite(store.namespaced_key('client_runs', candidate['run_key']),
                          None, candidate['run'].encode('utf-8')),
                ByteWrite(store.namespaced_key('client_submitted_intents', candidate['submission_key']),
                          0, candidate['submitted'].encode('utf-8')),
            )
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    installation.binding.inspect_reader(reader, lambda current:
                        self._core.validate_submitted_run_rows(output, current))
                self._row_write_attempts.add(output.ticket)
                self._pending_run_write = output
                result = store.compare_exchange_many_inspected(
                    writes, fences, inspect=inspect, current=installation.binding.current)
            if result is None:
                raise LocalStorageError('Original Local Run write conflicted; lookup is required')

    def _save_original_start_step(self, output: _Output) -> None:
        """Forward one Core-produced Run-row CAS, then observe its original successor."""
        installation = self._active()
        store = installation._store
        if store is None:
            raise ValueError('Original Local Store is unavailable')
        with self._core._lock:
            self._core._owned_output(output)
            if not any(original is output for original in self._step_outputs):
                raise ValueError('Foreign original Local start step')
            if output.ticket in self._step_write_attempts or self._pending_start_write is not None:
                raise LocalStorageError('Original Local start write requires lookup; replay is unavailable')
            captured: list[dict[str, Any]] = []
            installation.binding.inspect(lambda current: captured.append(_object(
                self._core.read_sdk_start_step(output, current), 1048576)))
            candidate = captured[0]
            if (set(candidate) != {'kind', 'key', 'revision', 'body'} or
                    any(type(candidate[key]) is not str for key in candidate) or
                    candidate['kind'] not in ('dispatch', 'claim')):
                raise ValueError('Invalid original Core start step projection')
            revision = candidate['revision']
            if (not revision.isascii() or not revision.isdecimal() or
                    (len(revision) > 1 and revision.startswith('0')) or
                    len(revision) > 19 or int(revision) >= 2**63 - 1):
                raise ValueError('Invalid original Core start step generation')
            writes = (ByteWrite(store.namespaced_key('client_runs', candidate['key']),
                                int(revision), candidate['body'].encode('utf-8')),)
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    installation.binding.inspect_reader(reader, lambda current:
                        self._core.validate_sdk_start_step(output, current))
                self._step_write_attempts.add(output.ticket)
                self._pending_start_write = output
                result = store.compare_exchange_many_inspected(
                    writes, fences, inspect=inspect, current=installation.binding.current)
            if result is None:
                raise LocalStorageError('Original Local start write conflicted; lookup is required')
            # Owner confirmation is a separate same-Store observation. No
            # candidate, physical response or Bool can replace these facts.
            installation.binding.inspect(lambda current:
                self._core.confirm_sdk_start_step(output, current))
            self._pending_start_write = None

    def _configure_original_compute(self, run: _Run) -> _SourceFreeCompute:
        """Join the original saved Run/start/Compute Owners without executing tasks."""
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk or
                not any(original is run for original in self._run_loans)):
            raise ValueError('Foreign original finite Local Run')
        with self._core._lock:
            if self._pending_start_write is not None:
                raise LocalStorageError('Original Local start requires lookup; new Compute is unavailable')
            for kind in (7, 8):
                output = self._reserve(lambda: self._core.reserve_material(
                    run.handle, kind, cleanup=lambda: True))
                self._step_outputs.append(output)
                installation.binding.inspect(lambda _: self._core.produce_material(output))
                self._save_original_start_step(output)
                if kind == 7:
                    if not self._core.close_material(output):
                        raise LocalProductCleanupPending(self)
                    self._step_outputs.remove(output)
                    self._step_write_attempts.discard(output.ticket)
                else:
                    starts: list[_PhysicalStart] = []
                    installation.binding.inspect(lambda _: starts.append(
                        self._runs.reserve_sdk_physical_start(run, output)))
                    start = starts[0]
                    self._physical_starts.append(start)
                    installation.binding.inspect(lambda _: self._runs.confirm_physical_start(start))
                    if not self._core.retire_material_output(output):
                        raise LocalProductCleanupPending(self)
            selected = next(value for value in installation.binding._selected if value.name == 'compute.json')
            source = self._copy(installation.binding._source.original_bytes(selected))
            compute = self._runs.reserve_source_free_compute(self._physical_starts[-1], source)
            self._source_free_computes.append(compute)
            installation.binding.inspect(lambda _:
                self._runs.configure_source_free_compute(compute, configuration))
            return compute

    def _prepare_original_publication(self, compute: _SourceFreeCompute) -> tuple[_Output, _Output]:
        """Join original invocation/preflight/Account publisher before task activation.

        The callback fences physical custody and the six Core facts only. The
        existing Common port separately evaluates original/current run/publish
        and validates original Policy/target/request/index before and after it.
        Nothing here acknowledges Store, executes a task or grants Result read.
        """
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk or
                not any(original is compute for original in self._source_free_computes)):
            raise ValueError('Foreign original source-free Compute')
        with self._core._lock:
            self._runs._compute(compute)
            if any(original is compute for original, _ in self._source_free_invocations):
                raise LocalStorageError('Original Local invocation is retained; new preflight is unavailable')
            source = self._copy(b'{}')
            invocation = self._reserve(lambda: self._core.reserve_source_free_invocation(
                compute.core, source, cleanup=lambda: True))
            self._source_free_invocations.append((compute, invocation))
            installation.binding.inspect(lambda _:
                self._core.prepare_source_free_invocation(invocation, configuration.handle))
            # These are physical observations, not Run/Policy/scope issuers.
            request = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'now': self._now(),
                'attempt_id': os.urandom(32).hex(),
                'fence_cid': 'sha256:' + hashlib.sha256(os.urandom(32)).hexdigest(),
                'external_idempotency_key': None,
            }))
            preflight = self._reserve(lambda: self._core.reserve_publication_preflight(
                invocation, request, cleanup=lambda: True))
            self._publication_preflights.append(preflight)
            installation.binding.inspect(lambda _:
                self._core.prepare_publication_preflight(preflight, configuration.handle))
            # The original request/attempt remain nominal in Core. Installing
            # an SDK port needs no copied contract, target CID or permit input.
            publisher_input = self._copy(b'{}')

            def current() -> bool:
                installation.binding.current()
                return True

            def authorize(fact: _PublisherFact) -> bool:
                # This same-Store fence supplies physical custody only. The
                # nominal Common port checks all six facts, original/current
                # Account publish, Policy/target and the Core-validated index.
                installation.binding.current()
                return fact.namespace_id == 'local'

            publisher = self._reserve(lambda: self._core.reserve_publisher(
                preflight, publisher_input, current=current, authorize=authorize, cleanup=lambda: True))
            self._publishers.append(publisher)
            installation.binding.inspect(lambda _:
                self._core.install_publisher(publisher, configuration.handle))
            installation.binding.inspect(lambda _:
                self._core.authorize_publisher(publisher, configuration.handle, stage='request'))
            if not self._core.retire_publication_preflight_output(preflight):
                raise LocalProductCleanupPending(self)
            return preflight, publisher

    def close(self) -> bool:
        """Stop this Host's resources only; never cancel/replay/delete a Run."""
        self._nominal()
        with self._core._lock:
            self._closing = True
            if self._uncertain_ticket is not None and not self._core._closed:
                return False
            for publisher in tuple(reversed(self._publishers)):
                if not self._core.close_publisher(publisher):
                    return False
                self._publishers.remove(publisher)
            for preflight in tuple(reversed(self._publication_preflights)):
                if not self._core.close_publication_preflight(preflight):
                    return False
                self._publication_preflights.remove(preflight)
            for compute, invocation in tuple(reversed(self._source_free_invocations)):
                if not self._core.close_source_free_invocation(invocation):
                    return False
                self._source_free_invocations.remove((compute, invocation))
            for compute in tuple(reversed(self._source_free_computes)):
                if not self._runs.close_source_free_compute(compute):
                    return False
                self._source_free_computes.remove(compute)
            for start in tuple(reversed(self._physical_starts)):
                if not self._runs.close_physical_start(start):
                    return False
                self._physical_starts.remove(start)
            for output in tuple(reversed(self._step_outputs)):
                if not self._core.close_material(output):
                    return False
                self._step_outputs.remove(output)
                self._step_write_attempts.discard(output.ticket)
                if self._pending_start_write is output:
                    self._pending_start_write = None
            for output in tuple(reversed(self._journal_outputs)):
                if not self._core.close_journal_observation(output):
                    return False
                self._journal_outputs.remove(output)
            for output in tuple(reversed(self._row_outputs)):
                if not self._core.close_material(output):
                    return False
                self._row_outputs.remove(output)
                self._row_write_attempts.discard(output.ticket)
                if self._pending_run_write is output:
                    self._pending_run_write = None
            for run in tuple(reversed(self._run_loans)):
                if not self._runs.close_run(run):
                    return False
                self._run_loans.remove(run)
            for prepared in tuple(reversed(self._prepared_inputs)):
                if not self._preparation.close_preparation(prepared):
                    return False
                self._prepared_inputs.remove(prepared)
            for output in tuple(reversed(self._projections)):
                if not self._close_projection(output):
                    return False
            if self._configuration is not None:
                if not self._runs.close_configuration(self._configuration):
                    return False
                self._configuration = None
            if self._environment is not None:
                if not self._preparation.close_environment(self._environment):
                    return False
                self._environment = None
            for source in tuple(reversed(self._inputs)):
                if not self._core.close_input(source):
                    return False
                self._inputs.remove(source)
            self._append_sources.clear()
            if self._installation is not None:
                if not self._installation.close():
                    return False
                self._installation = None
            return self._core.close()
