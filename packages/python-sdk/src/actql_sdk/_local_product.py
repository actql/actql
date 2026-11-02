"""Installed Local assembly over the original Core/File/Store Owners.

This is the in-process Host's connection assembly, not a Run controller. The
public factory is connected only after its operation/Result ports are ready.
No bootstrap/profile/epoch result is an admission or execution permission.
"""
from __future__ import annotations

from collections.abc import Callable
from contextlib import ExitStack
from dataclasses import dataclass
from datetime import datetime, timezone
from functools import partial
import hashlib
import os
import secrets
from pathlib import Path
import stat
import time
from typing import TYPE_CHECKING, Any, Literal, TypeVar

if TYPE_CHECKING:
    from ._local_initial_preparation import _OriginalPythonPreparation

import httpx

from . import _wire as wire
from ._local_core import LocalCore, LocalCoreError, LocalCoreInitializationError, LocalCoreResources, _Input, _Output, _Workspace, _PublisherFact, _Task, _ResultExport, LocalTaskProgress, LocalResultProgress
from ._local_distribution import installed_local_components, LocalInstallationError, LocalComponents
from ._local_files import (LocalFileRoot, _AllocationArea, _PayloadFile, _NameAdoption, _FileFinalization, _FileReader,
    LocalAreaAcquisitionError, LocalFileAcquisitionError, LocalReaderAcquisitionError)
from ._local_installation import OriginalLocalInstallation, LocalInstallationCleanupPending, _object
from ._local_preparation import LocalPreparation, LocalPreparationFailure, _Environment, _Preparation
from ._local_project import OriginalLocalProjectConfiguration, ProjectLocations
from ._local_project_files import OriginalLocalProjectFiles, LocalProjectFilesCleanupPending, _ProjectFile
from ._local_run import LocalRunCustody, _RunConfiguration, _Run, _PhysicalStart, _SourceFreeCompute
from ._local_commit_projection import OriginalCommitProjection
from ._local_reader_facts import OriginalReaderFacts
from ._local_observation_transfer import OriginalObservationTransfer
from ._local_store_reconciliation import OriginalStoreReconciliation
from ._local_sdk_read_storage import OriginalSDKReadEvidenceStore, SDKReadEvidenceCleanupPending
from ._local_sdk_delivery_storage import OriginalSDKDeliveryStore, SDKDeliveryStorageCleanupPending
from ._local_response import OriginalLocalResponseStream
from ._local_sdk_response import OriginalLocalSDKResponseStream
from ._local_sdk_payload_reader import OriginalSDKPayloadReader, SDKPayloadReaderCleanupPending
from ._local_work import OriginalLocalWork
from ._local_saved_read import OriginalSavedResultRead
from ._local_check import OriginalLocalCheck
from ._local_storage import ByteFence, ByteWrite, CapacityReservation, LocalStorageError, StoredBytes
from ._local_native_store import _OriginalNativeStoreSelection
from ._values import content_cid, wire_bytes

_T = TypeVar('_T')
_LOCAL_SELECTION = {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                    'consentRefs': [], 'runners': []}
_PUBLICATION_WORK_QUANTUM = 256


def _ordinary_core_limits() -> LocalCoreResources:
    """Managed work/copy allowances, not reserved heap or a hard RSS ceiling.

    Config/Engine/Store and their linear memory are actually acquired by Core.
    Python/runtime caches belong to the trusted platform. Native workers and
    shared zero-copy holdings, when selected, retain their separate originals.
    """
    return LocalCoreResources(planning_work=1_000_000, attempts=4096,
        holdings=4096, transfer_bytes=64 * 1024 * 1024,
        retained_bytes=512 * 1024 * 1024,
        # Existing Local Compute admits a 512 MiB execution envelope. Keep
        # the Core/transfer/setup allowances concurrent on this same Root.
        execution_bytes=(512 + 64) * 1024 * 1024)


def _state_directory_option(value: str | os.PathLike[str] | None) -> Path | None:
    """Capture the documented trusted PathLike once before acquisition."""
    if value is None:
        return None
    text = os.fspath(value)
    if not isinstance(text, str) or not text or '\x00' in text or len(text) > 4096:
        raise ValueError('Invalid Python Local state directory')
    # Preserve the filesystem spelling, including surrogateescaped Unix names.
    # This is the ordinary selected stdlib codec, not a provenance issuer.
    if len(os.fsencode(text)) > 4096:
        raise ValueError('Python Local state directory exceeds its encoded limit')
    return Path(text)


@dataclass(eq=False)
class _PayloadCustody:
    # Physical metadata and original Core loans only; no payload/Run state.
    publication: _Output
    index: int
    store_authority: str
    generation: str
    maximum: int
    workspace: _Workspace | None = None
    request: _Output | None = None
    record: _Output | None = None
    row: ByteFence | None = None
    capacity: CapacityReservation | None = None
    reservation: _Output | None = None
    writing: _Output | None = None
    allocation: _Output | None = None
    allocation_row: ByteFence | None = None
    allocation_attempts: set[int] | None = None
    area: _AllocationArea | None = None
    origin: LocalFileRoot | None = None
    physical: _PayloadFile | None = None
    names: _Output | None = None
    adoption: _NameAdoption | None = None
    chunk: _Output | None = None
    chunk_offset: int = 0
    chunk_file_offset: int = 0
    finalization: _FileFinalization | None = None
    binding: _Output | None = None
    reader: _FileReader | None = None


@dataclass(frozen=True, slots=True, eq=False)
class _OriginalRunReference:
    # Accounted routing metadata issued by Core, never Run state or authority.
    run: _Run
    source: _Input


@dataclass(eq=False)
class _RunStateCustody:
    # Same-Host pending input/output custody; counters always come from Store.
    run: _Run
    projection: OriginalCommitProjection
    source: _Input
    output: _Output | None = None
    prepared: bool = False
    write_attempted: bool = False


class LocalProductCleanupPending(RuntimeError):
    def __init__(self, host: 'InstalledLocalHost') -> None:
        super().__init__('Installed Local Host cleanup is pending')
        self.cleanup_host = host


def _default_directory() -> Path:
    """Choose the private standard location, never a Program-supplied path."""
    # The installed resolver already rejects non-Darwin/arm64 profiles.
    directory = Path.home() / 'Library' / 'Application Support' / 'ActQL' / 'Python Local'
    return _private_state_directory(directory)


def _private_state_directory(directory: Path) -> Path:
    """Prepare the caller's Store through the same owned-directory checks."""
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

    def __init__(self, core: LocalCore, directory: Path | None, *,
                 now: Callable[[], int], observed_at: str, sdk_finite: bool = False,
                 _native_store: _OriginalNativeStoreSelection | None = None,
                 _project_directory: Path | None = None,
                 _project_profile: str | None = None) -> None:
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
        self._run_restore_attempts: dict[bytes, _Input] = {}
        self._public_run_references: list[_OriginalRunReference] = []
        self._run_state_custody: dict[int, _RunStateCustody] = {}
        self._state_observing = False
        self._run_publications: list[tuple[_Run, _Output]] = []
        self._row_outputs: list[_Output] = []
        self._run_rows: list[tuple[_Run, _Output]] = []
        self._journal_outputs: list[_Output] = []
        self._admission_observations: dict[int, _Output] = {}
        # Physical write-invocation custody, not Run/admission state. A retained
        # attempt cannot be reused as a transport retry or new acceptance.
        self._row_write_attempts: set[int] = set()
        self._pending_run_write: _Output | None = None
        self._step_outputs: list[_Output] = []
        self._step_write_attempts: set[int] = set()
        self._pending_start_write: _Output | None = None
        self._publication_bindings: list[tuple[_Run, _Output]] = []
        self._binding_write_attempts: set[int] = set()
        self._pending_binding_write: _Output | None = None
        self._physical_starts: list[_PhysicalStart] = []
        self._source_free_computes: list[_SourceFreeCompute] = []
        self._source_free_invocations: list[tuple[_SourceFreeCompute, _Output]] = []
        self._publication_preflights: list[_Output] = []
        self._publishers: list[_Output] = []
        self._tasks: list[_Task] = []
        self._result_exports: list[_ResultExport] = []
        self._result_chunks: list[_Output] = []
        self._publications: list[_Output] = []
        self._commit_projections: list[OriginalCommitProjection] = []
        self._commit_requests: dict[int, _Input] = {}
        self._reader_facts: list[OriginalReaderFacts] = []
        self._observation_transfers: list[OriginalObservationTransfer] = []
        self._store_observations: dict[int, OriginalStoreReconciliation] = {}
        self._sdk_read_evidence: dict[int, OriginalSDKReadEvidenceStore] = {}
        self._sdk_deliveries: dict[int, OriginalSDKDeliveryStore] = {}
        self._observation_attempts: set[int] = set()
        self._publication_write_attempts: set[int] = set()
        self._pending_publication_write: OriginalCommitProjection | None = None
        # Routing alias to the same retained publisher loan, never a new grant.
        self._pending_publication_publisher: _Output | None = None
        self._saved_result_reads: list[OriginalSavedResultRead] = []
        self._client_check = OriginalLocalCheck(self)
        self._payloads: list[_PayloadCustody] = []
        self._payload_write_attempts: set[int] = set()
        self._payload_capacity_attempts: set[int] = set()
        self._payload_transition_attempts: set[int] = set()
        self._inputs: list[_Input] = []
        self._response_streams: set[OriginalLocalResponseStream | OriginalLocalSDKResponseStream] = set()
        self._projections: list[_Output] = []
        self._append_sources: dict[int, _Input] = {}
        self._uncertain_ticket: int | None = None
        self._closing = False
        self._physical_work: list[OriginalLocalWork] = []
        self._project_files: OriginalLocalProjectFiles | None = None
        self._project_configuration: OriginalLocalProjectConfiguration | None = None
        self._project_locations: ProjectLocations | None = None
        self._project_members: list[tuple[str, str | None, _ProjectFile]] = []
        try:
            if _project_directory is not None:
                project_state = self._capture_project(_project_directory, _project_profile)
                directory = _private_state_directory(
                    project_state if directory is None else
                    OriginalLocalProjectFiles._path(_project_directory / directory))
            elif _project_profile is not None or directory is None:
                raise ValueError('Original project directory is unavailable')
            assert directory is not None
            self._installation = OriginalLocalInstallation(core, directory,
                observed_at=observed_at, now=now, project_epoch=self._project_epoch,
                sdk_finite=sdk_finite, native_store=_native_store)
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
    def installed(cls, *, state_dir: str | os.PathLike[str] | None = None,
                  resources: LocalCoreResources | None = None,
                  _initial_preparation: _OriginalPythonPreparation | None = None,
                  _discover_project: bool = False,
                  _project_profile: str | None = None) -> InstalledLocalHost:
        """Resolve the selected cohort with no endpoint/token/internal paths."""
        if (type(_discover_project) is not bool or _project_profile is not None
                and (not _discover_project or type(_project_profile) is not str
                     or len(_project_profile) > 65536)):
            raise ValueError('Invalid original project factory selection')
        if resources is None and _initial_preparation is not None:
            from ._local_worker_funding import LocalWorkerFundingUnavailable
            from ._local_initial_preparation import _OriginalPythonPreparation, _capture_initial_preparation
            initial = _initial_preparation
            try:
                if initial is None:
                    initial = _capture_initial_preparation(state_dir)
                else:
                    if type(initial) is not _OriginalPythonPreparation:
                        raise ValueError('Foreign original Python preparation')
                initial.adopt_captured_state_dir(state_dir)
            except LocalWorkerFundingUnavailable:
                raise
            except Exception as failure:
                raise LocalWorkerFundingUnavailable(
                    'Original Python initial preparation is unavailable',
                    cleanup_preparation=initial) from failure
            # This actual initial input service supplies neither the absent
            # worker originals nor the larger discovery/import/loader envelope.
            # Keep the same initial carrier; never treat it as reserved bytes.
            raise LocalWorkerFundingUnavailable(
                'Original installed Local worker funding is unavailable',
                cleanup_preparation=initial)
        if _initial_preparation is not None:
            raise ValueError('Initial Python original cannot be transferred to diagnostic resources')
        directory_option = _state_directory_option(state_dir)
        if resources is None:
            resources = _ordinary_core_limits()
        components = installed_local_components()
        # The selected installed Core acquires real Config/Engine/Store/VM
        # resources. Limits do not stand in for those acquisitions, native
        # worker originals or any operation's current permission.
        core = LocalCore._from_installed_image(components,
            # Original setup, Run and Result slots remain concurrent with
            # each physical borrow. Keep their finite descriptor allowance
            # separate from the unchanged transfer-byte allowance.
            transfer_capacity=12 * 1024 * 1024, slots=128,
            resources=resources, _ordinary_host=True)
        try:
            with core._host_operation(initial=True):
                if _discover_project:
                    return cls(core, directory_option,
                        now=lambda: time.time_ns() // 1_000_000,
                        observed_at=datetime.now(timezone.utc).isoformat(
                            timespec='milliseconds').replace('+00:00', 'Z'), sdk_finite=True,
                        _project_directory=Path.cwd(), _project_profile=_project_profile)
                directory = (_default_directory() if directory_option is None
                             else _private_state_directory(directory_option))
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

    async def open(self, operation: str, payload: bytes) -> httpx.Response:
        self._active()
        if any(not work.stopped for work in self._physical_work):
            raise ValueError('Original Local physical invocation is still active')
        body = _object(payload, 1048576)
        if (type(operation) is not str or not wire.valid_body(operation, body)  # type: ignore[no-untyped-call]
                or body['connection'] != _LOCAL_SELECTION):
            raise ValueError('Invalid original Local Client operation')
        with self._core._host_operation():
            return await self._open_operation(operation, body)

    async def _open_operation(self, operation: str, body: dict[str, Any]) -> httpx.Response:
        """Use the existing SDK's closed operation wire without HTTP or a token.

        Profile/admission and completed original Run observations use their
        existing Owners. Other operations still need their own observations; no outcome
        is fabricated from a physical write, exception, or unsupported request.
        The public installed factory remains gated on Result/recovery assembly.
        """
        work: OriginalLocalWork | None = None
        with self._core._lock:
            if operation == 'connect':
                raw = wire_bytes(self._profile())  # type: ignore[no-untyped-call]
            elif operation == 'check':
                raw = self._client_check.report(body)
            elif operation == 'lookup-submission':
                raw = self._lookup_original_submission(body['submissionRef'])
            elif operation == 'attach':
                raw = self._attach_original_run(body['ref'])
            elif operation == 'submit-intent':
                intent = {key: body[key] for key in ('kind', 'input', 'parameters')}
                for key in ('stopBefore', 'readOnly'):
                    if key in body:
                        intent[key] = body[key]
                identity = content_cid({'version': 'actql-submitted-intent/0.1',
                    'intent': intent}, data_keys=True)  # type: ignore[no-untyped-call]
                if body['intentCid'] != identity:
                    raise ValueError('Invalid original Local submitted intent identity')
                observed = _object(self._lookup_original_submission(body['submissionRef']), 1048576)
                if observed.get('kind') in ('ready', 'preparing', 'preparation_failed') and observed.get('intentCid') != identity:
                    value = {'kind': 'conflict', 'attemptRef': body['attemptRef'],
                        'submissionRef': body['submissionRef'], 'intentCid': identity, 'reason': 'intent'}
                    if not wire.submission_attempt(value, _LOCAL_SELECTION, body):  # type: ignore[no-untyped-call]
                        raise ValueError('Invalid original Local Submission conflict')
                    raw = wire_bytes(value)  # type: ignore[no-untyped-call]
                elif observed.get('kind') in ('ready', 'preparing', 'preparation_failed'):
                    # The saved admission is DATA, not a restored executable
                    # Run. Never prepare, dispatch or issue another Run here.
                    value = {'kind': 'recorded' if observed['kind'] == 'preparing' else 'already_satisfied',
                        'attemptRef': body['attemptRef'],
                        'outcome': observed}
                    if not wire.submission_attempt(value, _LOCAL_SELECTION, body):  # type: ignore[no-untyped-call]
                        raise ValueError('Invalid original saved Local Submission response')
                    raw = wire_bytes(value)  # type: ignore[no-untyped-call]
                else:
                    run, admission = self._accept_original(body['submissionRef'],
                        wire_bytes(intent), run_id='python-' + secrets.token_hex(16))  # type: ignore[no-untyped-call]
                    saved = _object(admission, 1048576)
                    if run is None:
                        if (saved.get('kind') != 'preparation_failed'
                                or saved.get('intentCid') != identity
                                or not wire.submission_outcome(saved, _LOCAL_SELECTION,
                                    body['submissionRef'], lookup=True)):  # type: ignore[no-untyped-call]
                            raise ValueError('Invalid original Local preparation failure response')
                        outcome = saved
                    else:
                        if (not wire.negotiated(saved, 'admission', _LOCAL_SELECTION)  # type: ignore[no-untyped-call]
                                or saved['ref']['authorityScopeCid'] != body['submissionRef']['epoch']['authorityScopeCid']):
                            raise ValueError('Invalid original saved Local admission wire')
                        outcome = {'kind': 'ready', 'submissionRef': body['submissionRef'],
                            'intentCid': identity, 'admission': saved}
                    # The invocation envelope correlates this call with the saved
                    # Owner admission, as in the existing Host transport. It does
                    # not manufacture a Run terminal, dispatch or Result response.
                    value = {'kind': 'recorded', 'attemptRef': body['attemptRef'], 'outcome': outcome}
                    if not wire.submission_attempt(value, _LOCAL_SELECTION, body):  # type: ignore[no-untyped-call]
                        raise ValueError('Invalid original Local Submission response')
                    raw = wire_bytes(value)  # type: ignore[no-untyped-call]
                    if run is not None:
                        self._register_original_run_reference(run, admission)
                        work = OriginalLocalWork(partial(self._execute_original_admitted_run, run))
            elif operation in ('status', 'wait'):
                if operation == 'wait' and (body['until'] not in (None, 'terminal')
                        or body['since'] is not None):
                    raise ValueError('Original Local wait condition supplier is unavailable')
                if not self._has_live_original_run_reference(body['ref']):
                    raw = self._read_original_reference(body['ref'], kind=7)
                    stream = OriginalLocalResponseStream(self, raw, maximum=1048576)
                    response = httpx.Response(200, headers={'content-type': 'application/json',
                        'content-encoding': 'identity'}, stream=stream)
                    stream._attached = True
                    return response
                # Submission waits for its original physical work. Both forms
                # reobserve the same completed publication; the SDK's existing
                # wait validator still requires an actual stable Owner state.
                run, _ = self._select_original_run(body['ref'])
                projection = self._original_run_projection(run)
                return self._original_run_response(run, projection)
            elif operation == 'read':
                if not self._has_live_original_run_reference(body['ref']):
                    saved_read = OriginalSavedResultRead(self)
                    self._saved_result_reads.append(saved_read)
                    return saved_read.prepare(body['ref'], body['resultName'], body['format'], body['attemptId'])
                run, _ = self._select_original_run(body['ref'])
                projection = self._original_run_projection(run)
                return self._original_sdk_read_response(run, projection,
                    body['resultName'], body['format'], body['attemptId'])
            elif operation == 'delivery-attempt':
                if not self._has_live_original_run_reference(body['ref']):
                    saved_read = OriginalSavedResultRead(self)
                    self._saved_result_reads.append(saved_read)
                    return saved_read.prepare_lookup(body['ref'], body['resultName'], body['attemptId'])
                run, _ = self._select_original_run(body['ref'])
                projection = self._original_run_projection(run)
                return self._original_delivery_lookup_response(run, projection,
                    body['resultName'], body['attemptId'])
            else:
                raise ValueError('Original Local operation supplier is unavailable')
            stream = OriginalLocalResponseStream(self, raw,
                maximum=1048576 if operation == 'check' else 8192)
        if work is not None:
            # Keep the accounted response and original invocation even if the
            # awaiting coroutine disappears. Host close observes actual worker
            # stop before touching its Core/File/Store loans; no automatic retry.
            self._physical_work.append(work)
            work.start()
            await work.wait()
        with self._core._lock:
            response = httpx.Response(200, headers={'content-type': 'application/json',
                'content-encoding': 'identity'}, stream=stream)
            stream._attached = True
            return response

    def _register_original_run_reference(self, run: _Run, admission: bytes) -> None:
        """Hold only a Core-issued reference for routing to its nominal Run loan."""
        self._runs._run(run)
        if not any(original is run for original in self._run_loans):
            raise ValueError('Foreign original Local Run')
        saved = _object(admission, 4096)
        if not wire.negotiated(saved, 'admission', _LOCAL_SELECTION):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original Local admission reference')
        raw = wire_bytes(saved['ref'])  # type: ignore[no-untyped-call]
        if len(raw) > 4096:
            raise ValueError('Invalid bounded original Local reference')
        for original in self._public_run_references:
            self._core._owned_input(original.source)
            held = self._core._inputs[original.source.ticket].payload
            if original.run is run:
                if held != raw:
                    raise ValueError('Original Local Run reference changed')
                return
            if held == raw:
                raise ValueError('Ambiguous original Local Run reference')
        self._public_run_references.append(_OriginalRunReference(run, self._copy(raw)))

    def _has_live_original_run_reference(self, reference: object) -> bool:
        """Locate existing live custody only; exact equality is not authority."""
        captured = wire_bytes(reference)  # type: ignore[no-untyped-call]
        if len(captured) > 4096:
            raise ValueError('Invalid original Local Run reference')
        for original in self._public_run_references:
            self._core._owned_input(original.source)
            if self._core._inputs[original.source.ticket].payload == captured:
                # A restored typed Run supplies no live publication/Result
                # custody. Its public reads retain the saved-reader path.
                return original.run.handle not in self._runs._run_restorations
        return False

    def _select_original_run(self, reference: object) -> tuple[_Run, bytes]:
        """Route a reference, then reobserve its original actual saved admission.

        Exact field equality locates custody only. Current read/publisher and
        full stored-chain checks still precede any public Run state response.
        This performs no preparation, adoption, dispatch or new acceptance.
        """
        self._active()
        requested = _object(wire_bytes(reference), 4096)  # type: ignore[no-untyped-call]
        if not wire.valid(requested, 'run_ref'):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original Local Run reference')
        for original in self._public_run_references:
            self._core._owned_input(original.source)
            held = self._core._inputs[original.source.ticket].payload
            if _object(held, 4096) != requested:
                continue
            saved = (self._attach_original_run(requested)
                     if original.run.handle in self._runs._run_restorations
                     else self._read_original_saved_admission(original.run))
            admission = _object(saved, 4096)
            if (not wire.negotiated(admission, 'admission', _LOCAL_SELECTION)  # type: ignore[no-untyped-call]
                    or admission['ref'] != requested):
                raise ValueError('Original Local Run is unavailable')
            return original.run, saved
        return self._restore_original_run(requested)

    def _restore_original_run(self, reference: object) -> tuple[_Run, bytes]:
        """Restore an executable original only through its admitted saved material.

        Public reference-only reads do not need this Activation-purpose path.
        It performs no dispatch, task start, replacement acceptance or write.
        Every partial child remains on its existing owner for explicit cleanup.
        """
        installation = self._active()
        configuration = self._configuration
        if configuration is None or not configuration.sdk:
            raise ValueError('Original SDK restoration is unavailable')
        raw_reference = wire_bytes(reference)  # type: ignore[no-untyped-call]
        if not wire.valid(_object(raw_reference, 4096), 'run_ref'):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original restoration reference')
        with self._core._lock:
            if raw_reference in self._run_restore_attempts:
                raise LocalStorageError('Original restoration requires lookup; invocation replay is unavailable')
            source = self._copy(raw_reference)
            self._run_restore_attempts[raw_reference] = source
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, 8, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            captured: list[dict[str, Any]] = []
            def observe(current: _Output) -> None:
                captured.append(_object(self._core.produce_and_read_submission_lookup(output, current), 1048576))
            installation.binding.inspect(observe)
            original = captured[0]
            if (set(original) != {'intent', 'admission', 'materials_available'}
                    or type(original['intent']) is not str or type(original['admission']) is not str
                    or type(original['materials_available']) is not bool):
                raise ValueError('Invalid original restoration input descriptor')
            if not original['materials_available']:
                raise LocalCoreError('original_run_materials_unavailable', -42)
            admission = original['admission'].encode('utf-8')
            saved = _object(admission, 4096)
            if (not wire.negotiated(saved, 'admission', _LOCAL_SELECTION)  # type: ignore[no-untyped-call]
                    or saved['ref'] != _object(raw_reference, 4096)):
                raise ValueError('Foreign original restoration admission')
            # Retain before decoding; positive descriptor DATA is no grant.
            restored = self._runs.reserve_restoration(configuration, source, output)
            installation.binding.inspect(lambda _: self._runs.restore_materials(restored))
            if self._environment is None:
                selected = next(value for value in installation.binding._selected
                                if value.name == 'environment.json')
                environment_input = self._copy(installation.binding._source.original_bytes(selected))
                def install(_: _Output) -> None:
                    self._environment = self._preparation.install_environment(environment_input, profile='source-free')
                installation.binding.inspect(install)
            assert self._environment is not None
            intent = self._copy(original['intent'].encode('utf-8'))
            prepared = self._preparation.reserve(self._environment, intent, format='submitted')
            self._prepared_inputs.append(prepared)
            installation.binding.inspect(lambda _: self._runs.bind_restored_preparation(restored, prepared))
            run = self._runs.reserve(configuration, prepared, source)
            self._run_loans.append(run)
            installation.binding.inspect(lambda _: self._runs.restore_run(run, restored))
            self._register_original_run_reference(run, admission)
            return run, admission

    def _original_run_projection(self, run: _Run) -> OriginalCommitProjection:
        self._runs._run(run)
        held = [publication for original, publication in self._run_publications if original is run]
        projections = [projection for projection in self._commit_projections
                       if any(projection._publication is publication for publication in held)]
        if len(projections) != 1:
            raise ValueError('Original Local Run observation is unavailable')
        return projections[0]

    def _original_run_response(self, run: _Run,
                               projection: OriginalCommitProjection) -> httpx.Response:
        """Move original Core state into the existing accounted response stream."""
        installation = self._active()
        configuration = self._configuration
        self._runs._run(run)
        if configuration is None or projection._configuration != configuration.handle:
            raise ValueError('Foreign original Local Run observation')
        streams: list[OriginalLocalResponseStream] = []
        def consume(raw: bytes) -> None:
            # The existing Core guard prevents a different Run's publication
            # being routed under this reference. Its zero is no read grant.
            self._core.validate_publication_run(projection._publication,
                run.handle, configuration.handle)
            streams.append(OriginalLocalResponseStream(self, raw))
        try:
            installation.binding.inspect(lambda _:
                self._core.validate_publication_run(projection._publication,
                    run.handle, configuration.handle))
            self._ensure_original_publication_observation(projection)
            if configuration.sdk:
                self._project_original_sdk_run_state(run, projection, consume)
            else:
                self._project_original_run_state(projection, consume)
        except BaseException:
            # Unattached transport never reaches the Client. The original
            # buffer Owner decides cleanup; failure retains this same stream.
            for stream in streams:
                if not stream._close():
                    raise LocalProductCleanupPending(self) from None
            raise
        if len(streams) != 1:
            raise ValueError('Incomplete original Local Run observation')
        stream = streams[0]
        response = httpx.Response(200, headers={'content-type': 'application/json',
            'content-encoding': 'identity'}, stream=stream)
        stream._attached = True
        return response

    def _project_original_sdk_run_state(self, run: _Run,
                                         projection: OriginalCommitProjection,
                                         consume: Callable[[bytes], object]) -> None:
        """Persist and confirm original observation metadata before public wire.

        The Core owns the actual submitted-row counter/key, state and physical
        availability relation. This caller forwards one original CAS only; a
        lost response permits same-output lookup, never another write or Run.
        """
        installation = self._active()
        configuration = self._configuration
        store = installation._store
        if store is None or configuration is None or not configuration.sdk:
            raise ValueError('Original SDK state installation is unavailable')
        if self._state_observing:
            raise ValueError('Original SDK state observation is already active')
        with self._core._lock, ExitStack() as active:
            self._state_observing = True
            active.callback(setattr, self, '_state_observing', False)
            observation = self._original_sdk_read_observation(run, projection)
            held = self._run_state_custody.get(run.handle)
            if held is None:
                now = self._now()
                if type(now) is not int or not 0 <= now <= 253402300799999:
                    raise ValueError('Invalid Local physical observation time')
                seconds, milliseconds = divmod(now, 1000)
                at = datetime.fromtimestamp(seconds, timezone.utc).replace(
                    microsecond=milliseconds * 1000).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
                payloads = [{'record': fact._record.handle, 'result': fact._result,
                             'binding': fact._binding_index} for fact in observation._facts]
                source = self._copy(wire_bytes({'observed_at': at, 'payloads': payloads}))  # type: ignore[no-untyped-call]
                held = _RunStateCustody(run, projection, source)
                self._run_state_custody[run.handle] = held
                created_output = self._reserve(lambda: self._core.reserve_publication_commit_export(
                    projection._publication, cleanup=lambda: True))
                held.output = created_output
                with observation._serialized_facts():
                    installation.binding.inspect(lambda _:
                        self._core.produce_publication_sdk_run_state(
                            created_output, run.handle, source, configuration.handle))
                held.prepared = True
            if held.run is not run or held.projection is not projection or not held.prepared:
                raise LocalProductCleanupPending(self)
            output = held.output
            if output is None:
                raise LocalProductCleanupPending(self)
            self._core._owned_output(output, 'publication_commit_export')
            candidate = _object(self._core.read_publication_commit_material(output), 1048576)
            fields = {'kind', 'key', 'revision', 'body', 'state'}
            if (set(candidate) != fields or any(type(candidate[key]) is not str for key in fields)
                    or candidate['kind'] not in ('retained', 'replace')):
                raise ValueError('Invalid original SDK state metadata projection')
            revision = candidate['revision']
            if (not revision.isascii() or not revision.isdecimal()
                    or len(revision) > 19 or len(revision) > 1 and revision.startswith('0')
                    or int(revision) > 2**63 - 1
                    or candidate['kind'] == 'replace' and int(revision) == 2**63 - 1):
                raise ValueError('Invalid original SDK state metadata generation')
            with observation._serialized_facts():
                if candidate['kind'] == 'replace' and not held.write_attempted:
                    writes = (ByteWrite(store.namespaced_key('client_submitted_intents', candidate['key']),
                                        int(revision), candidate['body'].encode('utf-8')),)
                    with installation.binding.fenced() as fences:
                        def inspect(reader: Any) -> None:
                            def validate(_: _Output) -> None:
                                observation._before_lookup()
                                self._core.validate_publication_sdk_run_state(output, configuration.handle)
                                observation._validate_facts()
                            installation.binding.inspect_reader(reader, validate)
                        held.write_attempted = True
                        result = store.compare_exchange_many_inspected(
                            writes, (*fences, *(row for row, _ in observation._originals)),
                            inspect=inspect, current=installation.binding._current_observer)
                    if result is None:
                        raise LocalStorageError('Original SDK state metadata conflict; lookup is required')
                # Physical COMMIT and candidate fields are not confirmation.
                # This same output rechecks the exact saved successor under a
                # fresh original Store/current frame, including after reply loss.
                raw = candidate['state'].encode('utf-8')
                def confirm_and_consume(_: _Output) -> None:
                    self._core.confirm_publication_sdk_run_state(output, configuration.handle)
                    # The response's original Run guard and bounded transfer
                    # still need this same entered physical journal snapshot.
                    if consume(raw) is not None:
                        raise ValueError('Invalid synchronous original SDK state consumer')
                    observation._validate_facts()
                installation.binding.inspect(confirm_and_consume)
            if not self._core.close_publication_commit_export(output):
                raise LocalProductCleanupPending(self)
            held.output = None
            if not self._core.close_input(held.source):
                raise LocalProductCleanupPending(self)
            self._inputs.remove(held.source)
            del self._run_state_custody[run.handle]

    def _original_sdk_read_response(self, run: _Run,
                                    projection: OriginalCommitProjection,
                                    result_name: str, format: str,
                                    attempt_id: str) -> httpx.Response:
        """Connect the existing read/usage/codec/Store Owners to SDK transport.

        Core chooses the original grant, attempt, Result/binding ordinals and
        terminal evidence. No descriptor is selected from an SDK-supplied path,
        JSON state or success boolean. First-write loss requires original lookup.
        """
        self._ensure_original_publication_observation(projection)
        delivery = self._original_sdk_delivery_store(run, projection)
        clock = self._original_sdk_delivery_clock()
        # Reuse the physical clock projection only; its timestamp has no
        # independent expiry or authorization meaning outside the Core Owner.
        tick = _object(self._core._inputs[clock.ticket].payload, 256)
        request = self._copy(wire_bytes({'result_name': result_name, 'format': format,  # type: ignore[no-untyped-call]
            'attempt_id': attempt_id, 'observed_at': tick['observed_at']}))
        streams: list[OriginalLocalSDKResponseStream] = []
        try:
            self._persist_original_sdk_read_evidence(run, projection, request)
            delivery.persist(request, run.handle)
            fact = delivery.prepare_original_payload(request, clock)
            try:
                reader = OriginalSDKPayloadReader(delivery, request, clock, fact)
            except SDKPayloadReaderCleanupPending as failure:
                # Constructor custody precedes every fallible source callback.
                # Keep it in the Host cleanup inventory before attempting close.
                streams.append(OriginalLocalSDKResponseStream(self, failure.cleanup_reader))
                raise
            stream = OriginalLocalSDKResponseStream(self, reader)
            streams.append(stream)
            if not self._core.close_input(clock):
                raise LocalProductCleanupPending(self)
            self._inputs.remove(clock)
        except BaseException:
            for original in streams:
                if not original._close():
                    raise LocalProductCleanupPending(self) from None
            # Unattached requests/first outputs remain under their original
            # Host/Store custody; no new grant/write/reader is tried on failure.
            raise
        response = httpx.Response(200, headers={'content-type': 'application/x-ndjson',
            'content-encoding': 'identity'}, stream=stream)
        stream._attached = True
        return response

    def _original_sdk_delivery_clock(self) -> _Input:
        """Reserve one physical clock input; this renews no grant or attempt."""
        self._active()
        now = self._now()
        if type(now) is not int or not 0 <= now <= 253402300799999:
            raise ValueError('Invalid Local physical observation time')
        seconds, milliseconds = divmod(now, 1000)
        observed_at = datetime.fromtimestamp(seconds, timezone.utc).replace(
            microsecond=milliseconds * 1000).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        return self._copy(wire_bytes({'observed_at': observed_at}))  # type: ignore[no-untyped-call]

    def _original_delivery_lookup_response(self, run: _Run,
                                            projection: OriginalCommitProjection,
                                            result_name: str, attempt_id: str) -> httpx.Response:
        """Same-Store original lookup; no new attempt, write or payload access."""
        self._ensure_original_publication_observation(projection)
        observation = self._original_sdk_read_observation(run, projection)
        projection._ready()
        now = self._now()
        if type(now) is not int or not 0 <= now <= 253402300799999:
            raise ValueError('Invalid Local physical observation time')
        seconds, milliseconds = divmod(now, 1000)
        observed_at = datetime.fromtimestamp(seconds, timezone.utc).replace(
            microsecond=milliseconds * 1000).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
        # The existing private request shape remains opaque to Python. Core
        # selects/validates the original format and saved metadata scope. The
        # supplied current clock never renews the old attempt or grant.
        source = self._copy(wire_bytes({'result_name': result_name, 'format': 'jsonl',  # type: ignore[no-untyped-call]
            'attempt_id': attempt_id, 'observed_at': observed_at}))
        streams: list[OriginalLocalResponseStream] = []
        try:
            observation.project_sdk_delivery_lookup(source, run.handle,
                lambda raw: streams.append(OriginalLocalResponseStream(self, raw)))
            if not self._core.close_input(source):
                raise LocalProductCleanupPending(self)
            self._inputs.remove(source)
        except BaseException:
            for stream in streams:
                if not stream._close():
                    raise LocalProductCleanupPending(self) from None
            if (not projection.pending_outputs and not self._core._closing
                    and any(original is source for original in self._inputs)):
                if not self._core.close_input(source):
                    raise LocalProductCleanupPending(self) from None
                self._inputs.remove(source)
            raise
        if len(streams) != 1:
            raise ValueError('Incomplete original Local delivery lookup')
        stream = streams[0]
        response = httpx.Response(200, headers={'content-type': 'application/json',
            'content-encoding': 'identity'}, stream=stream)
        stream._attached = True
        return response

    async def aclose(self) -> None:
        self._nominal()
        for work in self._physical_work:
            await work.wait_stopped()
        if not self.close():
            raise LocalProductCleanupPending(self)

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

    def _capture_project(self, directory: Path, profile: str | None) -> Path:
        """Retain configuration and selected physical originals before Store IO.

        The Core selects profile/locators. This method neither interprets their
        bodies nor installs an environment from equal serialized locator DATA.
        """
        if (self._project_files is not None or self._project_configuration is not None
                or profile is not None and (type(profile) is not str or len(profile) > 65536)):
            raise ValueError('Invalid or repeated original project selection')
        try:
            self._project_files = self._reserve(lambda: OriginalLocalProjectFiles(
                self._core, max_files=128, max_bytes=8388608))
        except LocalProjectFilesCleanupPending as failure:
            self._project_files = failure.cleanup_files
            raise
        files = self._project_files
        selected = files.discover(directory)
        configuration = None if selected is None else files.original_bytes(selected).decode('utf-8')
        source = self._copy(wire_bytes({'configuration': configuration, 'profile': profile}))  # type: ignore[no-untyped-call]
        self._project_configuration = self._reserve(
            lambda: OriginalLocalProjectConfiguration(self._core, source))
        self._project_locations = self._project_configuration.prepare()
        locations = self._project_locations
        base = files._path(directory) if selected is None else selected.path.parent
        originals = {} if selected is None else {selected.path: selected}
        locators: list[tuple[str, str | None, str | None]] = [
            ('connectors', None, locations.connectors),
            ('model_tasks', None, locations.model_tasks),
            ('lock', None, locations.lock), ('mock_data', None, locations.mock_data)]
        locators.extend(('mock_answer', task, path) for task, path in locations.mock_answers)
        for role, task, locator in locators:
            if locator is None:
                continue
            path = files._path(base / locator)
            member = originals.get(path)
            if member is None:
                member = files.read_original(path, max_bytes=1048576)
                if member is None:
                    raise ValueError('Original selected project input is unavailable')
                originals[path] = member
            files.original_bytes(member)
            self._project_members.append((role, task, member))
        files.current()
        return files._path(base / locations.state_dir)

    def _require_project_execution_environment(self) -> None:
        if self._project_configuration is None:
            return
        if self._project_files is None:
            raise ValueError('Original project input custody is unavailable')
        self._project_files.current()
        locations = self._project_configuration.prepare()
        if (locations.profile is not None or self._project_members):
            # These originals still require the selected published/Mock
            # environment constructor. Never execute them against the old
            # source-free bootstrap as a substitute.
            raise ValueError('Original selected project execution environment is not installed')

    def _original_check_environment(self) -> _Environment:
        installation = self._active()
        self._require_project_execution_environment()
        if self._environment is None:
            selected = next(value for value in installation.binding._selected
                            if value.name == 'environment.json')
            source = self._copy(installation.binding._source.original_bytes(selected))
            def install(_: _Output) -> None:
                self._environment = self._preparation.install_environment(source, profile='source-free')
            installation.binding.inspect(install)
        assert self._environment is not None
        self._preparation._environment(self._environment)
        return self._environment

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
        self._active()
        with self._core._host_operation():
            return self._profile()

    def _profile(self) -> dict[str, Any]:
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
                    writes, fences, inspect=inspect, current=installation.binding._current_observer)
            if result is None:
                raise LocalStorageError('Original Local submitted intent write conflicted; lookup is required')
            return output

    def _lookup_original_submission(self, reference: object) -> bytes:
        """Observe authenticated saved history without preparing or resending.

        A missing original is unresolved history, never proof of nonexecution.
        The Core's full inventories and retained Run validator remain inside
        the same current physical snapshot before and after copying the view.
        """
        return self._read_original_reference(reference, kind=4)

    def _attach_original_run(self, reference: object) -> bytes:
        """Select one saved admission; never recreate an executable Run plan."""
        return self._read_original_reference(reference, kind=5)

    def _read_original_reference(self, reference: object, *, kind: int) -> bytes:
        installation = self._active()
        configuration = self._configuration
        if (installation._epoch is None or installation._store is None
                or configuration is None):
            raise ValueError('Original Local submission suppliers are unavailable')
        captured_reference = _object(wire_bytes(reference), 8192)  # type: ignore[no-untyped-call]
        with self._core._lock:
            if kind == 4:
                installation._epoch.identity(captured_reference)
                body = {'reference': wire_bytes(captured_reference).decode('utf-8')}  # type: ignore[no-untyped-call]
            elif kind in (5, 7) and wire.valid(captured_reference, 'run_ref'):  # type: ignore[no-untyped-call]
                body = captured_reference
            else:
                raise ValueError('Invalid original Local reference selection')
            source = self._copy(wire_bytes(body))  # type: ignore[no-untyped-call]
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, kind, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            captured: list[dict[str, Any]] = []
            def observe(current: _Output) -> None:
                captured.append(_object(self._core.produce_and_read_submission_lookup(output, current), 1048576))
            installation.binding.inspect(observe)
            original = captured[0]
            if kind == 7:
                # Core selects the same saved original state, observation key
                # and revision under the full current snapshot. This branch
                # neither refreshes availability nor reconstructs a Run.
                if not wire.valid(original, 'run_state'):  # type: ignore[no-untyped-call]
                    raise ValueError('Invalid original saved Local RunState')
                state_raw: bytes = wire_bytes(original)  # type: ignore[no-untyped-call]
                if not self._close_projection(output):
                    raise LocalProductCleanupPending(self)
                return state_raw
            observed_kind = original.get('kind')
            fields = ({'kind'} if observed_kind == 'missing' else {'kind', 'intentCid'}
                      if observed_kind == 'preparing' else {'kind', 'intentCid', 'admission'}
                      if observed_kind == 'ready' else {'kind', 'intentCid', 'problemCode', 'problemClassification'}
                      if observed_kind == 'preparation_failed' else set())
            if not fields or set(original) != fields:
                raise ValueError('Invalid original Local submission lookup')
            if kind == 5:
                if original['kind'] != 'ready' or type(original.get('admission')) is not str:
                    raise ValueError('Original Local Run is unavailable')
                saved = _object(original['admission'].encode('utf-8'), 4096)
                if (not wire.negotiated(saved, 'admission', _LOCAL_SELECTION)  # type: ignore[no-untyped-call]
                        or saved['ref'] != captured_reference):
                    raise ValueError('Foreign original Local Run admission')
                admission: bytes = wire_bytes(saved)  # type: ignore[no-untyped-call]
                if not self._close_projection(output):
                    raise LocalProductCleanupPending(self)
                return admission
            if observed_kind == 'missing':
                result: dict[str, Any] = {'kind': 'unresolvable',
                    'submissionRef': captured_reference,
                    'problem': {'code': 'submission_history_unresolvable'}}
            else:
                result = {'kind': observed_kind, 'submissionRef': captured_reference,
                          'intentCid': original['intentCid']}
                if observed_kind == 'ready':
                    if type(original['admission']) is not str:
                        raise ValueError('Invalid original saved Local admission')
                    result['admission'] = _object(original['admission'].encode('utf-8'), 4096)
                elif observed_kind == 'preparation_failed':
                    result['problem'] = {'code': original['problemCode'],
                                         'classification': original['problemClassification']}
            if not wire.submission_outcome(result, _LOCAL_SELECTION, captured_reference, lookup=True):  # type: ignore[no-untyped-call]
                raise ValueError('Invalid original Local submission lookup response')
            raw: bytes = wire_bytes(result)  # type: ignore[no-untyped-call]
            if not self._close_projection(output):
                raise LocalProductCleanupPending(self)
            return raw

    def _retain_original_result_read(self, reference: object, result_name: str) -> tuple[_Output, dict[str, Any]]:
        """Retain Core's actual stored-chain reader, never an executable plan.

        Its private wire carries metadata only. A later Result delivery must
        still use this nominal Core output, recheck its original Store/current
        fences and acquire the actual generation/grant/usage through their
        existing Owners. No reconstruction from these strings is authorized.
        Partial preparation, changed history or output close keeps the original
        input/output reachable for same-handle cleanup.

        Return the same bounded, checked metadata with its original output so
        the private caller need not parse it again. The data is not currentness.
        """
        installation = self._active()
        configuration = self._configuration
        selected = _object(wire_bytes(reference), 8192)  # type: ignore[no-untyped-call]
        if (configuration is None or not configuration.sdk
                or installation._store is None or installation._epoch is None
                or not wire.valid(selected, 'run_ref')  # type: ignore[no-untyped-call]
                or not wire.bounded_text(result_name)):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original saved Local Result selection')
        with self._core._lock:
            source = self._copy(wire_bytes({**selected, 'resultName': result_name}))  # type: ignore[no-untyped-call]
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, 6, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            packets: list[dict[str, Any]] = []
            def inspect(current: _Output) -> None:
                packets.append(_object(self._core.produce_and_read_submission_lookup(output, current), 1048576))
            installation.binding.inspect(inspect)
            packet = packets[0]
            fields = {'kind', 'resultName', 'runDefinitionCid', 'index', 'manifest',
                      'definition', 'artifact', 'retention', 'binding', 'resultOrdinal', 'bindingOrdinal'}
            if (set(packet) != fields or any(type(packet[key]) is not str for key in fields)
                    or packet['kind'] != 'result-originals' or packet['resultName'] != result_name
                    or packet['runDefinitionCid'] != selected['runDefinitionCid']
                    or any(packet[key] not in tuple(str(i) for i in range(8))
                           for key in ('resultOrdinal', 'bindingOrdinal'))):
                raise ValueError('Foreign original saved Local Result projection')
            return output, packet

    def _close_projection(self, output: _Output) -> bool:
        """Release only original transport loans after successful cleanup."""
        closed = (self._core.close_submission_append(output) if output.family == 'submission_append'
                  else self._core.close_submission_lookup(output) if output.family == 'submission_lookup'
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
        self._require_project_execution_environment()
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
            failures: list[LocalPreparationFailure] = []
            def check(current: _Output) -> None:
                # The observed original is revalidated in the same borrowed
                # read snapshot before entering the existing parser/Checker.
                self._core.validate_submission_append(observed, current)
                try:
                    self._preparation.prepare(prepared)
                except LocalPreparationFailure as failure:
                    if self._preparation.failed_original(failure) is not prepared:
                        raise ValueError('Foreign original Local preparation failure')
                    failures.append(failure)
            installation.binding.inspect(check)
            if not self._close_projection(observed):
                raise LocalProductCleanupPending(self)
            if failures:
                raise failures[0]
            return prepared

    def _commit_preparation_failure(self, reference: object, intent: bytes,
                                    failure: LocalPreparationFailure) -> bytes:
        """Commit one original terminal candidate, then independently look it up.

        A failed COMMIT exits with the same loans retained. It is never retried
        or translated into a known failure. No Run, dispatch or replacement
        preparation is issued by this path.
        """
        installation = self._active()
        configuration = self._configuration
        if configuration is None or installation._store is None or installation._epoch is None:
            raise ValueError('Original Local failure suppliers are unavailable')
        prepared = self._preparation.failed_original(failure)
        if not any(original is prepared for original in self._prepared_inputs):
            raise ValueError('Foreign original Local failed preparation')
        identity = installation._epoch.identity(reference)
        source = self._copy(wire_bytes({'reference': wire_bytes(reference).decode('utf-8')}))  # type: ignore[no-untyped-call]
        output = self._reserve(lambda: self._core.reserve_submission_preparation_failure(
            configuration.handle, prepared.handle, source, cleanup=lambda: True))
        self._projections.append(output)
        self._append_sources[output.ticket] = source
        candidates: list[dict[str, Any]] = []
        def observe(current: _Output) -> None:
            self._core.produce_submission_append(output, current)
            candidates.append(_object(self._core.read_submission_append(output, current), 1048576))
        installation.binding.inspect(observe)
        candidate = candidates[0]
        if (set(candidate) != {'key', 'revision', 'before', 'body'}
                or any(type(value) is not str for value in candidate.values())
                or candidate['key'] != identity.request_id):
            raise ValueError('Invalid original Local preparation failure candidate')
        revision = candidate['revision']
        if (not revision.isascii() or not revision.isdecimal()
                or len(revision) > 19 or (len(revision) > 1 and revision.startswith('0'))
                or int(revision) > 2**63 - 1):
            raise ValueError('Invalid original Local preparation failure revision')
        terminal = _object(candidate['body'].encode('utf-8'), 262144)
        problem = {'code': terminal.get('preparation_problem_code'),
                   'classification': terminal.get('preparation_problem_classification')}
        store = installation._store
        with installation.binding.fenced() as fences:
            def inspect(reader: Any) -> None:
                installation.binding.inspect_reader(reader, lambda current:
                    self._core.validate_submission_append(output, current))
            result = store.compare_exchange_many_inspected((ByteWrite(
                store.namespaced_key('client_submitted_intents', candidate['key']),
                int(revision), candidate['body'].encode('utf-8')),), fences,
                inspect=inspect, current=installation.binding._current_observer)
        if result is None:
            raise LocalStorageError('Original Local preparation failure write conflicted; lookup is required')
        if not self._close_projection(output):
            raise LocalProductCleanupPending(self)
        saved = self._lookup_original_submission(reference)
        observed = _object(saved, 1048576)
        intent_cid = content_cid({'version': 'actql-submitted-intent/0.1',
            'intent': _object(intent, 65536)}, data_keys=True)  # type: ignore[no-untyped-call]
        if (observed.get('kind') != 'preparation_failed' or observed.get('intentCid') != intent_cid
                or observed.get('problem') != problem):
            raise ValueError('Changed original Local preparation failure readback')
        if not self._preparation.close_preparation(prepared):
            raise LocalProductCleanupPending(self)
        self._prepared_inputs.remove(prepared)
        if not self._core.close_input(prepared.input):
            raise LocalProductCleanupPending(self)
        self._inputs.remove(prepared.input)
        return saved

    def _accept_original(self, reference: object, intent: bytes, *, run_id: str) -> tuple[_Run | None, bytes]:
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
            try:
                prepared = self._prepare_original(captured_reference, intent)
            except LocalPreparationFailure as failure:
                return None, self._commit_preparation_failure(captured_reference, intent, failure)
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
            self._run_rows.append((run, output))
            installation.binding.inspect(lambda _: self._core.produce_material(output))
            self._commit_original_run_rows(output)
            # The immutable row Owner/input remain in Core. These consumed
            # transports need not overlap the fresh saved-admission lookup.
            # Neither retirement is the Store or admission acknowledgement.
            if not self._core.retire_material_output(output):
                raise LocalProductCleanupPending(self)
            if not self._core.retire_submission_append_output(observed):
                raise LocalProductCleanupPending(self)
            admission = self._read_original_saved_admission(run)
            self._pending_run_write = None
            return run, admission

    def _read_original_saved_admission(self, run: _Run) -> bytes:
        """Reobserve the retained original rows without preparation, acceptance or dispatch.

        The earlier transport may be retired; its nominal Plan/rows/input loan
        must still be live. Core checks the original saved admission revision
        against the current actual Run/submission snapshot, not a cached reply.
        This produces neither Store ACK nor a completed Run/Result.
        """
        installation = self._active()
        configuration = self._configuration
        store = installation._store
        if (configuration is None or not configuration.sdk or store is None
                or not any(original is run for original in self._run_loans)):
            raise ValueError('Foreign original saved Local Run')
        with self._core._lock:
            self._runs._run(run)
            if run.handle in self._admission_observations:
                raise LocalProductCleanupPending(self)
            held = [output for original, output in self._run_rows if original is run]
            if len(held) != 1 or not any(original is held[0] for original in self._row_outputs):
                raise ValueError('Original saved Local rows are unavailable')
            journal = self._reserve(lambda: self._core.reserve_journal_observation(
                held[0], configuration.handle, store=store,
                current=installation.binding._current_observer, cleanup=lambda: True))
            self._journal_outputs.append(journal)
            self._admission_observations[run.handle] = journal
            admission: list[bytes] = []
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    def consume(_: _Output) -> None:
                        self._core.inspect_journal_observation(journal, reader)
                        admission.append(self._core.read_journal_admission(journal, reader))
                    installation.binding.inspect_reader(reader, consume)
                store.inspect_namespaces(fences, inspect=inspect, current=installation.binding._current_observer)
            if not self._core.close_journal_observation(journal):
                raise LocalProductCleanupPending(self)
            self._journal_outputs.remove(journal)
            del self._admission_observations[run.handle]
            return admission[0]

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
            if (not fields | {'reference_locator'} <= set(candidate) <= fields | {'task_materials', 'reference_locator'}
                    or any(type(candidate[key]) is not str for key in fields)):
                raise ValueError('Invalid original Core Run row projection')
            locator = candidate['reference_locator']
            if (type(locator) is not dict or set(locator) != {'key', 'body'}
                    or type(locator['key']) is not str or len(locator['key']) != 64
                    or any(ch not in '0123456789abcdef' for ch in locator['key'])
                    or type(locator['body']) is not str):
                raise ValueError('Invalid original Core Run reference locator')
            locator_body = locator['body'].encode('utf-8')
            if not 0 < len(locator_body) <= 4096:
                raise ValueError('Invalid bounded original Run reference locator')
            # Core owns the exact original tuple/key/wire. This subordinate
            # DATA shares the original ready transaction, never a Run grant.
            locator_write = ByteWrite(store.namespaced_key('client_run_reference_index',
                                         locator['key']), None, locator_body)
            material_writes: list[ByteWrite] = []
            if 'task_materials' in candidate:
                chunks = candidate['task_materials']
                if type(chunks) is not list or not 1 <= len(chunks) <= 3:
                    raise ValueError('Invalid original task material chunks')
                total = 0
                for index, chunk in enumerate(chunks):
                    if (type(chunk) is not dict or set(chunk) != {'key', 'body'}
                            or chunk['key'] != candidate['run_key'] + ':' + str(index)
                            or type(chunk['body']) is not str):
                        raise ValueError('Foreign original task material chunk')
                    raw_chunk = chunk['body'].encode('utf-8')
                    if not 0 < len(raw_chunk) <= 131072:
                        raise ValueError('Invalid bounded original task material chunk')
                    total += len(raw_chunk)
                    if total > 262144:
                        raise ValueError('Original task material capacity exceeded')
                    material_writes.append(ByteWrite(
                        store.namespaced_key('client_task_run_materials', chunk['key']),
                        None, raw_chunk))
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
            ) + tuple(material_writes) + (locator_write,)
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    installation.binding.inspect_reader(reader, lambda current:
                        self._core.validate_submitted_run_rows(output, current))
                self._row_write_attempts.add(output.ticket)
                self._pending_run_write = output
                result = store.compare_exchange_many_inspected(
                    writes, fences, inspect=inspect, current=installation.binding._current_observer)
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
                    writes, fences, inspect=inspect, current=installation.binding._current_observer)
            if result is None:
                raise LocalStorageError('Original Local start write conflicted; lookup is required')
            # Owner confirmation is a separate same-Store observation. No
            # candidate, physical response or Bool can replace these facts.
            installation.binding.inspect(lambda current:
                self._core.confirm_sdk_start_step(output, current))
            self._pending_start_write = None

    def _bind_original_publication(self, run: _Run) -> _Output:
        """Forward original Common row binding before dispatch; never a Store ACK."""
        installation = self._active()
        store = installation._store
        if (store is None or self._configuration is None or not self._configuration.sdk
                or not any(original is run for original in self._run_loans)):
            raise ValueError('Foreign original Local publication Run')
        with self._core._lock:
            if self._pending_binding_write is not None:
                raise LocalStorageError('Original publication binding requires lookup; replay is unavailable')
            for original, output in self._publication_bindings:
                if original is run:
                    installation.binding.inspect(lambda current:
                        self._core.confirm_sdk_publication_binding(output, current))
                    if not self._core.retire_material_output(output):
                        raise LocalProductCleanupPending(self)
                    return output
            output = self._reserve(lambda: self._core.reserve_material(
                run.handle, 9, cleanup=lambda: True))
            # Keep the same child before any fallible production/validation.
            self._publication_bindings.append((run, output))
            captured: list[dict[str, Any]] = []
            def produce(current: _Output) -> None:
                self._core.produce_material(output)
                captured.append(_object(self._core.read_sdk_publication_binding(output, current), 1048576))
            installation.binding.inspect(produce)
            candidate = captured[0]
            if (set(candidate) != {'kind', 'key', 'revision', 'body'}
                    or any(type(candidate[key]) is not str for key in candidate)
                    or candidate['kind'] not in ('publication', 'retained')):
                raise ValueError('Invalid original Core publication binding projection')
            revision = candidate['revision']
            if (not revision.isascii() or not revision.isdecimal()
                    or (len(revision) > 1 and revision.startswith('0'))
                    or len(revision) > 19 or int(revision) > 2**63 - 1):
                raise ValueError('Invalid original Core publication binding generation')
            if candidate['kind'] == 'publication':
                writes = (ByteWrite(store.namespaced_key('client_runs', candidate['key']),
                                    int(revision), candidate['body'].encode('utf-8')),)
                with installation.binding.fenced() as fences:
                    def inspect(reader: Any) -> None:
                        installation.binding.inspect_reader(reader, lambda current:
                            self._core.validate_sdk_publication_binding(output, current))
                    self._binding_write_attempts.add(output.ticket)
                    self._pending_binding_write = output
                    result = store.compare_exchange_many_inspected(
                        writes, fences, inspect=inspect, current=installation.binding._current_observer)
                if result is None:
                    raise LocalStorageError('Original publication binding conflicted; lookup is required')
            # The physical response is not sufficient. Core reads and adopts
            # the actual same-Store successor (or retained original) separately.
            installation.binding.inspect(lambda current:
                self._core.confirm_sdk_publication_binding(output, current))
            self._pending_binding_write = None
            if not self._core.retire_material_output(output):
                raise LocalProductCleanupPending(self)
            return output

    def _execute_original_admitted_run(self, run: _Run) -> None:
        """Drive one explicit start through existing task, payload and Store ports.

        The common Owners choose every task, transition, binding, key and full
        chain. This method selects no Run outcome, does not issue ACK, and never
        repeats uncertain work. Failure leaves the same retained loans for the
        original lookup/cleanup path. Status and wait do not call this method.
        """
        self._active()
        self._runs._run(run)
        if any(compute.start.run is run for compute in self._source_free_computes):
            raise LocalStorageError('Original Local execution is retained; replay is unavailable')
        compute = self._configure_original_compute(run)
        preflight, publisher = self._prepare_original_publication(compute)
        results = self._execute_original_tasks(compute, preflight, publisher)
        publication = self._capture_original_results(compute, preflight, results)
        for index in range(len(results)):
            held = self._prepare_original_payload(publication, index)
            self._save_original_payload_intent(held)
            self._reserve_original_payload_capacity(held)
            self._save_original_payload_reserved(held)
            self._prepare_original_payload_writing(held)
            self._acquire_original_payload_file(held)
            self._stage_original_payload_file(held)
            while not self._advance_original_payload_copy(held):
                pass  # Existing bounded Core/File cursor, same input and fuel.
            while not self._advance_original_payload_sealing(held):
                pass
            self._open_original_payload_reader(held)
            while not self._advance_original_payload_reader(held):
                pass
        self._prepare_original_commit_candidate(publication, preflight)
        projection = self._advance_original_commit_candidate(publication)
        while projection is None:
            projection = self._advance_original_commit_candidate(publication)
        facts = self._original_commit_reader_facts(projection)
        originals: list[tuple[ByteFence, CapacityReservation]] = []
        for fact in facts:
            held = next(value for value in self._payloads if value.record is fact._record)
            if held.row is None or held.capacity is None:
                raise ValueError('Original Local publication physical fences are unavailable')
            originals.append((held.row, held.capacity))
        self._store_original_commit(projection, facts, tuple(originals), publisher)
        self._prepare_original_store_observation(projection, publisher)
        while self._advance_original_store_observation(projection) is None:
            pass
        # An action is not ACK or terminal. Public observation must still copy
        # the actual stored chain through the original RunState/read Owners.

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
            self._bind_original_publication(run)
            # Material five asks the existing Owner to retain this Plan's
            # checked normalization. Its transport is not a durable write or
            # dispatch grant; the same Run keeps the original after close.
            for kind in (5, 7, 8):
                output = self._reserve(lambda: self._core.reserve_material(
                    run.handle, kind, cleanup=lambda: True))
                self._step_outputs.append(output)
                installation.binding.inspect(lambda _: self._core.produce_material(output))
                if kind == 5:
                    if not self._core.close_material(output):
                        raise LocalProductCleanupPending(self)
                    self._step_outputs.remove(output)
                    continue
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

    def _execute_original_tasks(self, compute: _SourceFreeCompute, preflight: _Output,
                                publisher: _Output) -> tuple[_ResultExport, ...]:
        """Drive existing task Owners; Python selects no task/transition/outcome."""
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk or
                not any(original is compute for original in self._source_free_computes) or
                not any(original is preflight for original in self._publication_preflights) or
                not any(original is publisher for original in self._publishers)):
            raise ValueError('Foreign original Local task/publication custody')
        with self._core._lock:
            self._runs._compute(compute)
            while True:
                selected: list[_Task | None] = []
                def select_task(_: _Output) -> None:
                    task = self._core.reserve_next_sdk_task(compute.core, configuration.handle)
                    # Retain the original loan before the enclosing snapshot's
                    # post-current checks can refuse its use.
                    if task is not None:
                        self._tasks.append(task)
                    selected.append(task)
                installation.binding.inspect(select_task)
                task = selected[0]
                if task is None:
                    break  # Explicit Core-checked end, never reserve's -2.
                installation.binding.inspect(lambda _: self._core.start_task(task))
                while True:
                    fed: list[bool] = []
                    installation.binding.inspect(lambda _: fed.append(self._core.feed_task(task, 16)))
                    if fed[0]: break
                while True:
                    progress: list[LocalTaskProgress] = []
                    installation.binding.inspect(lambda _: progress.append(self._core.advance_task(task, 16)))
                    if progress[0].waiting:
                        raise LocalCoreError('original_task_waiting', -7)
                    if progress[0].complete: break
                installation.binding.inspect(lambda _: self._core.prepare_task_finalization(task))
                while True:
                    final: list[LocalTaskProgress] = []
                    installation.binding.inspect(lambda _: final.append(
                        self._core.advance_task(task, 16, finalization=True)))
                    if final[0].waiting:
                        raise LocalCoreError('original_task_finalization_waiting', -7)
                    if final[0].complete: break
                installation.binding.inspect(lambda _: self._core.complete_task(task))
            counts: list[int] = []
            installation.binding.inspect(lambda _: counts.append(
                self._core.publication_preflight_result_count(preflight, configuration.handle)))
            results: list[_ResultExport] = []
            for index in range(counts[0]):
                selected_results: list[_ResultExport] = []
                def select_result(_: _Output) -> None:
                    result = self._core.reserve_result_from_compute(compute.core, index, configuration.handle)
                    # The same Result remains reachable for cleanup even when
                    # the original snapshot's post-current fence fails.
                    self._result_exports.append(result)
                    selected_results.append(result)
                installation.binding.inspect(select_result)
                result = selected_results[0]
                results.append(result)
            return tuple(results)

    def _capture_original_results(self, compute: _SourceFreeCompute, preflight: _Output,
                                  results: tuple[_ResultExport, ...]) -> _Output:
        """Finish original exports and Receipt; Store commit/ACK is separate.

        Transient chunks need not copy rows into Python. Their original Core
        finish marker closes each stream. The later payload replay reads the
        retained completed output; it cannot restart Source or Compute.
        """
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk or type(results) is not tuple or
                not any(original is compute for original in self._source_free_computes) or
                not any(original is preflight for original in self._publication_preflights) or
                any(not any(original is result for original in self._result_exports) for result in results)):
            raise ValueError('Foreign original Local Result/publication custody')
        with self._core._lock:
            self._runs._compute(compute)
            for result in results:
                installation.binding.inspect(lambda _: self._core.start_result_export(result))
                while True:
                    fed: list[bool] = []
                    installation.binding.inspect(lambda _: fed.append(self._core.feed_result_export(result, 16)))
                    if fed[0]: break
                while True:
                    progress: list[LocalResultProgress] = []
                    installation.binding.inspect(lambda _: progress.append(
                        self._core.advance_result_export(result, 16)))
                    if progress[0].ready: break
                installation.binding.inspect(lambda _:
                    self._core.finish_result_export_preparation(result))
                while True:
                    chunk = self._reserve(lambda: self._core.reserve_result_chunk(result, cleanup=lambda: True))
                    self._result_chunks.append(chunk)
                    installation.binding.inspect(lambda _: self._core.produce_result_chunk(chunk))
                    final: list[bool] = []
                    installation.binding.inspect(lambda _: final.append(self._core.result_chunk_finished(chunk)))
                    if not self._core.close_result_chunk(chunk):
                        raise LocalProductCleanupPending(self)
                    self._result_chunks.remove(chunk)
                    if final[0]: break
            source = next(original for owner, original in self._source_free_invocations if owner is compute)
            # Preserve the existing private export limits, not a new unlimited
            # scan or a broader admitted profile. Core shares this work budget
            # across snapshot, capture and later commit validation.
            request = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'results': [result.handle for result in results],
                'max_work': 1000000, 'max_workspace_slots': 100000,
            }))
            publication = self._reserve(lambda: self._core.reserve_publication(
                source, request, cleanup=lambda: True))
            self._publications.append(publication)
            self._run_publications.append((compute.start.run, publication))
            installation.binding.inspect(lambda _:
                self._core.prepare_publication(publication, configuration.handle))
            while True:
                captured: list[LocalResultProgress] = []
                installation.binding.inspect(lambda _: captured.append(
                    self._core.advance_publication(publication, configuration.handle,
                                                   _PUBLICATION_WORK_QUANTUM)))
                if captured[0].ready: break
            installation.binding.inspect(lambda _:
                self._core.finish_publication(publication, configuration.handle))
            if not self._core.retire_publication_output(publication):
                raise LocalProductCleanupPending(self)
            return publication

    def _prepare_original_payload(self, publication: _Output, index: int) -> _PayloadCustody:
        """Bind the retained Result to one existing Core payload Intent.

        An opaque generation is allocated once, as in the existing Native
        supplier. It is neither a content digest nor an execution permission.
        Store authority comes from the adopted original; limits are unchanged
        physical Store bounds. Core selects Result/attempt/schema/ordering.
        """
        installation = self._active()
        configuration = self._configuration
        store = installation._store
        if (configuration is None or not configuration.sdk or store is None
                or type(index) is not int or not 0 <= index < 2**31
                or not any(original is publication for original in self._publications)):
            raise ValueError('Foreign original Local payload Result')
        with self._core._lock:
            for held in self._payloads:
                if held.publication is publication and held.index == index:
                    raise LocalStorageError('Original payload custody is retained; use its observation path')
            selected = next(value for value in installation.binding._selected if value.name == 'store.json')
            store_body = installation.binding._source.original_bytes(selected)
            held = _PayloadCustody(publication, index,
                'sha256:' + hashlib.sha256(store_body).hexdigest(),
                'sha256:' + hashlib.sha256(secrets.token_bytes(32)).hexdigest(),
                0)
            self._payloads.append(held)
            # Bound simultaneous physical row, decoded text and outer JSON
            # encoding before making those copies. Core output/copy loans and
            # original Source metadata holdings remain separately reserved.
            held.workspace = self._reserve(lambda: self._core.reserve_workspace(
                8 * 65536 + 512, stopped=lambda: True, cleanup=lambda: True))
            source = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'store_authority_cid': held.store_authority,
                'material_generation_cid': held.generation,
                'max_payload_bytes': store._max_record_bytes,
            }))
            request = self._reserve(lambda: self._core.reserve_payload_request(
                publication, index, source, cleanup=lambda: True))
            held.request = request
            installation.binding.inspect(lambda _:
                self._core.produce_payload_request(request, configuration.handle))
            # The physical limit is an upper bound. Core's original request
            # selects the exact completed payload amount; reserve that amount,
            # never the enclosing Store limit or a Python row-size estimate.
            selected_request = _object(self._core.read_payload_request(request), 32768)
            fields = {'durable_codec_cid', 'logical_relation_cid',
                      'material_generation_cid', 'max_bytes', 'ordering_evidence_cid',
                      'publication_attempt_cid', 'result_definition_cid',
                      'result_schema_cid', 'row_count', 'store_authority_cid', 'version'}
            if (set(selected_request) != fields
                    or any(type(selected_request[key]) is not str for key in fields)
                    or selected_request['version'] != 'actql-publication-payload-request/0.1'
                    or selected_request['store_authority_cid'] != held.store_authority
                    or selected_request['material_generation_cid'] != held.generation):
                raise ValueError('Foreign original Core payload request')
            maximum = selected_request['max_bytes']
            if (not maximum.isascii() or not maximum.isdecimal()
                    or not 1 <= len(maximum) <= 10 or maximum.startswith('0')
                    or not 0 < int(maximum) <= min(store._max_record_bytes, 2**31 - 1)):
                raise ValueError('Invalid original Core payload amount')
            held.maximum = int(maximum)
            record = self._reserve(lambda: self._core.reserve_payload_record(
                request, cleanup=lambda: True))
            held.record = record
            installation.binding.inspect(lambda _:
                self._core.produce_payload_record(record, configuration.handle))
            return held

    def _payload_original(self, held: _PayloadCustody, *, pending_confirmation: bool = False) -> tuple[OriginalLocalInstallation, _RunConfiguration, _Output]:
        self._nominal()
        installation = self._installation if pending_confirmation else self._active()
        if installation is None or self._core._closed:
            raise ValueError('Original Local payload installation is unavailable')
        configuration = self._configuration
        if (type(held) is not _PayloadCustody or configuration is None
                or not any(original is held for original in self._payloads)
                or held.record is None):
            raise ValueError('Foreign original Local payload custody')
        self._core._owned_output(held.record, 'payload_record')
        return installation, configuration, held.record

    def _save_original_payload_intent(self, held: _PayloadCustody) -> None:
        """Forward one Core-produced Intent CAS, then inspect actual saved bytes."""
        with self._core._lock:
            installation, configuration, record = self._payload_original(held)
            store = installation._store
            if store is None:
                raise ValueError('Original Local payload Store is unavailable')
            if record.ticket in self._payload_write_attempts:
                raise LocalStorageError('Original payload write requires lookup; replay is unavailable')
            captured: list[bytes] = []
            installation.binding.inspect(lambda _: captured.append(
                self._core.read_payload_record(record, configuration.handle)))
            write = ByteWrite(store.namespaced_key('payload_record', held.generation), None, captured[0])
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    installation.binding.inspect_reader(reader, lambda _:
                        self._core.begin_payload_record(record, configuration.handle))
                self._payload_write_attempts.add(record.ticket)
                result = store.compare_exchange_many_inspected(
                    (write,), fences, inspect=inspect, current=installation.binding._current_observer)
            if result is None:
                raise LocalStorageError('Original payload Intent conflicted; lookup is required')
            self._observe_original_payload_intent(held)

    def _observe_original_payload_intent(self, held: _PayloadCustody) -> None:
        """Read the same key without replay; Core confirms only actual Store bytes."""
        with self._core._lock:
            installation, configuration, record = self._payload_original(held, pending_confirmation=True)
            store = installation._store
            if store is None or record.ticket not in self._payload_write_attempts:
                raise ValueError('Original Local payload write observation is unavailable')
            observed: list[ByteFence] = []
            def consume(actual: StoredBytes | None) -> None:
                if actual is None:
                    raise LocalStorageError('Original Local payload row is unavailable; custody remains pending')
                # No candidate equality or payload state is decided here.
                raw = wire_bytes({  # type: ignore[no-untyped-call]
                    'store_authority_cid': held.store_authority,
                    'material_generation_cid': held.generation,
                    'physical_revision': actual.generation,
                    'record_json': actual.payload.decode('utf-8'),
                })
                source = self._copy(raw)
                self._core.confirm_payload_record(record, source, configuration.handle)
                if not self._core.close_input(source):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(source)
                observed.append(ByteFence(store.namespaced_key('payload_record', held.generation),
                                          actual.generation, actual.payload))
            with installation.binding.fenced() as fences:
                store.inspect_bounded_record_inspected(
                    store.namespaced_key('payload_record', held.generation), 65536, fences,
                    inspect=lambda reader, take:
                        installation.binding.inspect_reader(reader, lambda _: take()),
                    consume=consume, current=installation.binding._current_observer)

            held.row = observed[0]

    def _reserve_original_payload_capacity(self, held: _PayloadCustody) -> None:
        """Reserve physical capacity once; only Core can prepare Reserved."""
        with self._core._lock:
            installation, configuration, record = self._payload_original(held)
            store = installation._store
            results = installation._results
            if store is None or results is None:
                raise ValueError('Original Local payload capacity supplier is unavailable')
            if record.ticket in self._payload_capacity_attempts:
                raise LocalStorageError('Original capacity reservation requires lookup; replay is unavailable')
            self._observe_original_payload_intent(held)
            assert held.row is not None
            with installation.binding.fenced() as metadata:
                def inspect(reader: Any) -> None:
                    def validate(_: _Output) -> None:
                        self._core.read_payload_record(record, configuration.handle)
                    installation.binding.inspect_reader(reader, validate)
                self._payload_capacity_attempts.add(record.ticket)
                # Physical maximums remain the installed Store/File limits.
                # Neither inserted nor already-present is a Core transition.
                store.reserve_capacity_inspected('publication_payload', held.row.key,
                    held.maximum, 1, store._max_payload_bytes, results._max_files,
                    (*metadata, held.row), inspect=inspect, current=installation.binding._current_observer)
            self._observe_original_payload_capacity(held)

    def _observe_original_payload_capacity(self, held: _PayloadCustody) -> None:
        """Observe the original reservation, without reserving or writing again."""
        with self._core._lock:
            installation, configuration, record = self._payload_original(held, pending_confirmation=True)
            store = installation._store
            if store is None or held.row is None or record.ticket not in self._payload_capacity_attempts:
                raise ValueError('Original Local capacity observation is unavailable')
            observed: list[CapacityReservation] = []
            def consume(actual: CapacityReservation | None) -> None:
                if actual is None:
                    raise LocalStorageError('Original capacity observation is unavailable; custody remains pending')
                if held.reservation is None:
                    held.reservation = self._reserve(lambda: self._core.reserve_payload_reservation(
                        record, cleanup=lambda: True))
                source = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                    'store_authority_cid': held.store_authority,
                    'material_generation_cid': held.generation,
                    'capacity_namespace': actual.namespace,
                    'reserved_bytes': actual.reserved_bytes,
                    'reserved_objects': actual.reserved_objects,
                }))
                self._core.produce_payload_reservation(held.reservation, source, configuration.handle)
                if not self._core.close_input(source):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(source)
                observed.append(actual)
            with installation.binding.fenced() as metadata:
                store.inspect_capacity_inspected('publication_payload', held.row.key, (*metadata, held.row),
                    inspect=lambda reader, take:
                        installation.binding.inspect_reader(reader, lambda _: take()),
                    consume=consume, current=installation.binding._current_observer)
            held.capacity = observed[0]

    def _save_original_payload_reserved(self, held: _PayloadCustody) -> None:
        """Forward Core's original Reserved bytes and exact capacity-fenced CAS."""
        with self._core._lock:
            installation, configuration, _ = self._payload_original(held)
            child = held.reservation
            if child is None:
                raise ValueError('Original Reserved transition is unavailable')
            self._save_original_payload_transition(held, child,
                lambda: self._core.read_payload_reservation(child, configuration.handle),
                lambda: self._core.begin_payload_reservation(child, configuration.handle))
            self._observe_original_payload_reserved(held)

    def _save_original_payload_transition(self, held: _PayloadCustody, child: _Output,
                                         read: Callable[[], bytes], begin: Callable[[], None]) -> None:
        installation, _, _ = self._payload_original(held)
        if child is not held.reservation and child is not held.writing:
            raise ValueError('Foreign original payload transition child')
        store = installation._store
        if store is None or held.row is None or held.capacity is None:
            raise ValueError('Original payload physical fences are unavailable')
        if child.ticket in self._payload_transition_attempts:
            raise LocalStorageError('Original payload transition requires lookup; replay is unavailable')
        wire: list[bytes] = []
        installation.binding.inspect(lambda _: wire.append(read()))
        write = ByteWrite(held.row.key, held.row.generation, wire[0])
        with installation.binding.fenced() as metadata:
            self._payload_transition_attempts.add(child.ticket)
            result = store.compare_exchange_reserved_inspected(write, held.capacity,
                (*metadata, held.row), inspect=lambda reader:
                    installation.binding.inspect_reader(reader, lambda _: begin()),
                current=installation.binding._current_observer)
        if result is None:
            raise LocalStorageError('Original payload transition conflicted; lookup is required')

    def _observe_original_payload_transition(self, held: _PayloadCustody, child: _Output,
                                            confirm: Callable[[_Input], None]) -> None:
        installation, _, _ = self._payload_original(held, pending_confirmation=True)
        if child is not held.reservation and child is not held.writing:
            raise ValueError('Foreign original payload transition observation')
        store = installation._store
        if store is None or child.ticket not in self._payload_transition_attempts:
            raise ValueError('Original payload transition observation is unavailable')
        observed: list[ByteFence] = []
        def consume(actual: StoredBytes | None) -> None:
            if actual is None:
                raise LocalStorageError('Original payload transition row is unavailable; custody remains pending')
            source = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'store_authority_cid': held.store_authority,
                'material_generation_cid': held.generation,
                'physical_revision': actual.generation,
                'record_json': actual.payload.decode('utf-8'),
            }))
            confirm(source)
            if not self._core.close_input(source):
                raise LocalProductCleanupPending(self)
            self._inputs.remove(source)
            observed.append(ByteFence(store.namespaced_key('payload_record', held.generation),
                                      actual.generation, actual.payload))
        with installation.binding.fenced() as metadata:
            store.inspect_bounded_record_inspected(store.namespaced_key('payload_record', held.generation),
                65536, metadata, inspect=lambda reader, take:
                    installation.binding.inspect_reader(reader, lambda _: take()),
                consume=consume, current=installation.binding._current_observer)
        held.row = observed[0]

    def _observe_original_payload_reserved(self, held: _PayloadCustody) -> None:
        """Readmit the actual Reserved row through its original Core child."""
        with self._core._lock:
            _, configuration, _ = self._payload_original(held, pending_confirmation=True)
            child = held.reservation
            if child is None:
                raise ValueError('Original Reserved transition is unavailable')
            self._observe_original_payload_transition(held, child,
                lambda source: self._core.confirm_payload_reservation(child, source, configuration.handle))

    def _prepare_original_payload_writing(self, held: _PayloadCustody) -> None:
        """Ask the original Core record for Writing; do not allocate a File here."""
        with self._core._lock:
            installation, configuration, record = self._payload_original(held)
            if held.reservation is not None:
                if not self._core.close_payload_reservation(held.reservation):
                    raise LocalProductCleanupPending(self)
                self._payload_transition_attempts.discard(held.reservation.ticket)
                held.reservation = None
            if held.writing is not None:
                raise LocalStorageError('Original Writing custody is retained; use its observation path')
            child = self._reserve(lambda: self._core.reserve_payload_writing(record, 1, cleanup=lambda: True))
            held.writing = child
            installation.binding.inspect(lambda _:
                self._core.produce_payload_writing(child, None, configuration.handle))
            self._save_original_payload_transition(held, child,
                lambda: self._core.read_payload_writing(child, configuration.handle),
                lambda: self._core.begin_payload_writing(child, configuration.handle))
            self._observe_original_payload_writing(held)

    def _observe_original_payload_writing(self, held: _PayloadCustody) -> None:
        """Readmit the actual Writing row; pending close does not authorize replay."""
        with self._core._lock:
            _, configuration, _ = self._payload_original(held, pending_confirmation=True)
            child = held.writing
            if child is None:
                raise ValueError('Original Writing transition is unavailable')
            self._observe_original_payload_transition(held, child,
                lambda source: self._core.confirm_payload_writing(child, source, configuration.handle))

    def _prepare_original_allocation(self, held: _PayloadCustody, kind: int) -> None:
        """Supply actual allocation row/identity to the original Core child."""
        with self._core._lock:
            installation, configuration, record = self._payload_original(held)
            store = installation._store
            if store is None or held.row is None or held.capacity is None:
                raise ValueError('Original allocation physical fences are unavailable')
            if held.allocation is not None:
                raise LocalStorageError('Original allocation child is retained; observe it before continuing')
            if held.writing is not None:
                if not self._core.close_payload_writing(held.writing):
                    raise LocalProductCleanupPending(self)
                self._payload_transition_attempts.discard(held.writing.ticket)
                held.writing = None
            child = self._reserve(lambda: self._core.reserve_payload_allocation(record, kind, cleanup=lambda: True))
            held.allocation = child
            def consume(actual: StoredBytes | None) -> None:
                packet: dict[str, Any] = {
                    'store_authority_cid': held.store_authority,
                    'namespace': 'publication_payload_allocation',
                    'material_generation_cid': held.generation,
                    'physical_revision': None if actual is None else str(actual.generation),
                    'allocation_body': None if actual is None else actual.payload.decode('utf-8'),
                }
                if kind == 2:
                    if held.area is None or installation._results is None:
                        raise ValueError('Original allocation area acquisition is unavailable')
                    identity = installation._results.observe_area(held.area)
                    packet.update(device=str(identity.device), inode=str(identity.inode))
                source = self._copy(wire_bytes(packet))  # type: ignore[no-untyped-call]
                self._core.produce_payload_allocation(child, source, configuration.handle)
                if not self._core.close_input(source):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(source)
            with installation.binding.fenced() as metadata:
                store.inspect_bounded_record_inspected(
                    store.namespaced_key('publication_payload_allocation', held.generation), 65536,
                    (*metadata, held.row), inspect=lambda reader, take:
                        installation.binding.inspect_reader(reader, lambda _: take()),
                    consume=consume, current=installation.binding._current_observer)

    def _save_original_allocation(self, held: _PayloadCustody) -> None:
        """Forward the original Core allocation CAS under original capacity/current."""
        with self._core._lock:
            installation, configuration, _ = self._payload_original(held)
            store = installation._store
            child = held.allocation
            if store is None or child is None or held.row is None or held.capacity is None:
                raise ValueError('Original allocation CAS custody is unavailable')
            if held.allocation_attempts is None:
                held.allocation_attempts = set()
            if child.ticket in held.allocation_attempts:
                raise LocalStorageError('Original allocation CAS requires lookup; replay is unavailable')
            projected: list[dict[str, Any]] = []
            installation.binding.inspect(lambda _: projected.append(_object(
                self._core.read_payload_allocation(child, configuration.handle), 65536)))
            packet = projected[0]
            fields = {'store_authority_cid', 'namespace', 'material_generation_cid',
                      'expected_revision', 'previous_body', 'allocation_body'}
            if (set(packet) != fields or any(type(packet[key]) is not str for key in
                    ('store_authority_cid', 'namespace', 'material_generation_cid', 'allocation_body'))):
                raise ValueError('Invalid original Core allocation transport')
            generation = packet['expected_revision']
            previous = packet['previous_body']
            if (previous is not None and type(previous) is not str
                    or (generation is None) != (previous is None)):
                raise ValueError('Invalid original nullable allocation transport')
            if generation is not None:
                if (type(generation) is not str or not generation.isascii() or not generation.isdecimal()
                        or len(generation) > 19 or str(int(generation)) != generation
                        or int(generation) >= 2**63 - 1):
                    raise ValueError('Invalid original physical allocation generation')
            write = ByteWrite(store.namespaced_key(packet['namespace'], packet['material_generation_cid']),
                              None if generation is None else int(generation), packet['allocation_body'].encode('utf-8'))
            with installation.binding.fenced() as metadata:
                def inspect(reader: Any) -> None:
                    installation.binding.inspect_reader(reader, lambda _:
                        self._core.begin_payload_allocation(child, configuration.handle))
                held.allocation_attempts.add(child.ticket)
                result = store.compare_exchange_attached_inspected(write, held.row, held.capacity,
                    metadata, inspect=inspect, current=installation.binding._current_observer)
            if result is None:
                raise LocalStorageError('Original allocation CAS conflicted; lookup is required')
            self._observe_original_allocation(held)

    def _observe_original_allocation(self, held: _PayloadCustody) -> None:
        """Core revalidates actual same-Store allocation bytes, including pending close."""
        with self._core._lock:
            installation, configuration, _ = self._payload_original(held, pending_confirmation=True)
            store = installation._store
            child = held.allocation
            if (store is None or child is None or held.allocation_attempts is None
                    or child.ticket not in held.allocation_attempts or held.row is None):
                raise ValueError('Original allocation observation is unavailable')
            observed: list[ByteFence] = []
            key = store.namespaced_key('publication_payload_allocation', held.generation)
            def consume(actual: StoredBytes | None) -> None:
                if actual is None:
                    raise LocalStorageError('Original allocation row is unavailable; custody remains pending')
                source = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                    'store_authority_cid': held.store_authority,
                    'namespace': 'publication_payload_allocation',
                    'material_generation_cid': held.generation,
                    'physical_revision': str(actual.generation),
                    'allocation_body': actual.payload.decode('utf-8'),
                }))
                self._core.confirm_payload_allocation(child, source, configuration.handle)
                if not self._core.close_input(source):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(source)
                observed.append(ByteFence(key, actual.generation, actual.payload))
            with installation.binding.fenced() as metadata:
                store.inspect_bounded_record_inspected(key, 65536, (*metadata, held.row),
                    inspect=lambda reader, take:
                        installation.binding.inspect_reader(reader, lambda _: take()),
                    consume=consume, current=installation.binding._current_observer)
            held.allocation_row = observed[0]

    def _close_original_allocation_child(self, held: _PayloadCustody) -> None:
        if held.allocation is not None:
            if not self._core.close_payload_allocation(held.allocation):
                raise LocalProductCleanupPending(self)
            if held.allocation_attempts is not None:
                held.allocation_attempts.discard(held.allocation.ticket)
            held.allocation = None

    def _acquire_original_payload_file(self, held: _PayloadCustody) -> None:
        """Persist/confirm allocation before exclusive physical acquisition.

        Failure retains the original area/writer and never repeats mkdir/open.
        Current permission is rechecked around physical IO; failed cleanup keeps
        the same handles and durable capacity. No Source/Compute is reexecuted.
        """
        with self._core._lock:
            installation, configuration, record = self._payload_original(held)
            root = installation._results
            if root is None or held.area is not None or held.physical is not None:
                raise ValueError('Original payload physical acquisition is unavailable')
            self._prepare_original_allocation(held, 1)
            self._save_original_allocation(held)
            assert held.allocation_row is not None
            name = held.allocation_row.payload.decode('utf-8')
            def acquire(_: _Output) -> None:
                try:
                    held.area = root.create_area(name)
                except LocalAreaAcquisitionError as failure:
                    held.area = failure.original_area
                    raise
            installation.binding.inspect(acquire)
            self._close_original_allocation_child(held)
            self._prepare_original_allocation(held, 2)
            self._save_original_allocation(held)
            self._close_original_allocation_child(held)
            assert held.area is not None
            installation.binding.inspect(lambda _: self._open_original_payload_area(held, root))
            assert held.origin is not None
            origin = held.origin
            def writer(_: _Output) -> None:
                try:
                    held.physical = origin.create_writer('payload', held.maximum)
                except LocalFileAcquisitionError as failure:
                    held.physical = failure.original_file
                    raise
            installation.binding.inspect(writer)
            assert held.physical is not None
            identity = origin.observe(held.physical).identity
            child = self._reserve(lambda: self._core.reserve_payload_writing(record, 2, cleanup=lambda: True))
            held.writing = child
            source = self._copy(wire_bytes({
                'store_authority_cid': held.store_authority, 'material_generation_cid': held.generation,
                'device': str(identity.device), 'inode': str(identity.inode),
            }))
            installation.binding.inspect(lambda _:
                self._core.produce_payload_writing(child, source, configuration.handle))
            if not self._core.close_input(source):
                raise LocalProductCleanupPending(self)
            self._inputs.remove(source)
            self._save_original_payload_transition(held, child,
                lambda: self._core.read_payload_writing(child, configuration.handle),
                lambda: self._core.begin_payload_writing(child, configuration.handle))
            self._observe_original_payload_writing(held)

    def _retry_original_area_sync(self, held: _PayloadCustody) -> None:
        """Finish durability of the same acquired area, never create another."""
        with self._core._lock:
            installation, configuration, _ = self._payload_original(held)
            root = installation._results
            child = held.allocation
            if root is None or held.area is None or child is None:
                raise ValueError('Original pending area custody is unavailable')
            area = held.area
            def sync(_: _Output) -> None:
                self._core.read_payload_allocation(child, configuration.handle)
                root.sync_area_creation(area)
            installation.binding.inspect(sync)

    def _stage_original_payload_file(self, held: _PayloadCustody) -> None:
        """Use original Core names and the existing same-handle link cursor."""
        with self._core._lock:
            installation, configuration, record = self._payload_original(held)
            root = installation._results
            origin, physical = held.origin, held.physical
            if root is None or origin is None or physical is None or held.names is not None:
                raise ValueError('Original Owned payload staging custody is unavailable')
            child = self._reserve(lambda: self._core.reserve_payload_names(record, cleanup=lambda: True))
            held.names = child
            names: list[dict[str, Any]] = []
            def prepare(_: _Output) -> None:
                self._core.produce_payload_names(child, configuration.handle)
                names.append(_object(self._core.read_payload_names(child, configuration.handle), 1024))
            installation.binding.inspect(prepare)
            packet = names[0]
            if (set(packet) != {'staging_name', 'object_name', 'material_generation_cid',
                               'store_authority_cid', 'record_revision', 'request_cid'}
                    or any(type(value) is not str for value in packet.values())):
                raise ValueError('Invalid original Core payload names transport')
            def adopt(_: _Output) -> None:
                self._core.read_payload_names(child, configuration.handle)
                held.adoption = origin.begin_adoption(physical, root, packet['staging_name'])
            installation.binding.inspect(adopt)
            self._advance_original_payload_staging(held)

    def _advance_original_payload_staging(self, held: _PayloadCustody) -> None:
        """Retry only the original name cursor under freshly checked current."""
        with self._core._lock:
            installation, configuration, _ = self._payload_original(held)
            origin, child, cursor = held.origin, held.names, held.adoption
            if origin is None or child is None or cursor is None:
                raise ValueError('Original staging cursor is unavailable')
            def advance(_: _Output) -> None:
                self._core.read_payload_names(child, configuration.handle)
                origin.advance_adoption(cursor)
                self._core.read_payload_names(child, configuration.handle)
            installation.binding.inspect(advance)
            if not origin.close_adoption(cursor):
                raise LocalProductCleanupPending(self)
            held.adoption = None

    def _open_original_payload_area(self, held: _PayloadCustody, root: LocalFileRoot) -> None:
        assert held.area is not None
        held.origin = root.open_area(held.area)

    def _advance_original_payload_copy(self, held: _PayloadCustody) -> bool:
        """Copy at most one physical chunk from the original Core Result replay.

        The original loan and physical byte offset survive short writes, current
        refusal and cleanup failure. Unknown writes are rejected by the existing
        File Owner; no Source/Compute replay or second payload is started. True
        denotes only the copied Core EOF, never publication or a Store ACK.
        """
        with self._core._lock:
            installation, configuration, _ = self._payload_original(held)
            physical, request, names = held.physical, held.request, held.names
            if (physical is None or request is None or names is None
                    or held.adoption is not None or held.row is None):
                raise ValueError('Original staged payload copy custody is unavailable')
            if held.writing is not None:
                if not self._core.close_payload_writing(held.writing):
                    raise LocalProductCleanupPending(self)
                self._payload_transition_attempts.discard(held.writing.ticket)
                held.writing = None
            completed: list[bool] = []
            def copy(_: _Output) -> None:
                self._core.read_payload_names(names, configuration.handle)
                self._core.start_payload_replay(request, configuration.handle)
                if held.chunk is None:
                    held.chunk = self._reserve(lambda:
                        self._core.reserve_payload_chunk(request, cleanup=lambda: True))
                    held.chunk_offset = 0
                    held.chunk_file_offset = physical.written
                chunk = held.chunk
                self._core.produce_payload_chunk(chunk, configuration.handle)
                data, final = self._core.read_payload_chunk(chunk, configuration.handle)
                if held.chunk_offset < len(data):
                    part = data[held.chunk_offset:held.chunk_offset + physical.root._max_chunk_bytes]
                    count = physical.root.append(physical,
                        held.chunk_file_offset + held.chunk_offset, part)
                    # Record actual progress before the post-I/O current check;
                    # a later refusal cannot repeat a completed physical write.
                    held.chunk_offset += count
                if held.chunk_offset != len(data):
                    completed.append(False)
                    return
                if final:
                    # Keep the original typed EOF loan through physical seal,
                    # including a post-I/O current refusal. No Python EOF flag
                    # can replace this Core evidence or authorize publication.
                    completed.append(True)
                    return
                if not self._core.close_payload_chunk(chunk):
                    raise LocalProductCleanupPending(self)
                held.chunk = None
                held.chunk_offset = 0
                completed.append(final)
            installation.binding.inspect(copy)
            return completed[0]

    def _advance_original_payload_sealing(self, held: _PayloadCustody) -> bool:
        """Bounded original snapshot/final-name work followed by Core Sealed CAS.

        The original Core EOF loan, file identity and name cursor remain held
        across flush/stop/link failures. Physical completion alone never seals
        the Core record or supplies a Store commit/Run ACK. An uncertain CAS is
        reconciled through the existing actual-row observation, not reissued.
        """
        with self._core._lock:
            installation, configuration, record = self._payload_original(held)
            physical, chunk, names = held.physical, held.chunk, held.names
            if (physical is None or chunk is None or names is None
                    or held.adoption is not None or held.row is None
                    or held.writing is not None):
                raise ValueError('Original payload sealing custody is unavailable')
            ready: list[bool] = []
            def advance(_: _Output) -> None:
                data, final = self._core.read_payload_chunk(chunk, configuration.handle)
                if not final or held.chunk_offset != len(data):
                    raise ValueError('Original Core payload EOF has not been physically copied')
                packet = _object(self._core.read_payload_names(names, configuration.handle), 65536)
                if type(packet.get('object_name')) is not str:
                    raise ValueError('Original Core final name is unavailable')
                root = physical.root
                if held.finalization is None:
                    cursor = root.begin_snapshot(physical)
                    snapshot = root.advance_snapshot(cursor)
                    if snapshot is None:
                        ready.append(False)
                        return
                    held.finalization = root.begin_finalization(physical, cursor, packet['object_name'])
                # Existing File Owner resolves the original physical stop and
                # known-name work; no replacement writer, link or digest exists.
                snapshot = root.advance_finalization(held.finalization)
                self._core.read_payload_chunk(chunk, configuration.handle)
                self._core.read_payload_names(names, configuration.handle)
                child = self._reserve(lambda:
                    self._core.reserve_payload_writing(record, 3, cleanup=lambda: True))
                held.writing = child
                identity = snapshot.observation.identity
                source = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                    'store_authority_cid': held.store_authority,
                    'material_generation_cid': held.generation,
                    'device': str(identity.device), 'inode': str(identity.inode),
                    'size': str(snapshot.observation.size),
                    'physical_digest': snapshot.physical_digest,
                }))
                self._core.produce_payload_writing(child, source, configuration.handle)
                if not self._core.close_input(source):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(source)
                ready.append(True)
            installation.binding.inspect(advance)
            if not ready[0]:
                return False
            child = held.writing
            assert child is not None
            # The name loan is revision-bound. Retire it before the Core record
            # adopts the next original revision; it cannot authorize final read.
            if not self._core.close_payload_names(names):
                raise LocalProductCleanupPending(self)
            held.names = None
            self._save_original_payload_transition(held, child,
                lambda: self._core.read_payload_writing(child, configuration.handle),
                lambda: self._core.begin_payload_writing(child, configuration.handle))
            self._observe_original_payload_writing(held)
            return True

    def _open_original_payload_reader(self, held: _PayloadCustody) -> None:
        """Open the same final file only after fresh Core Sealed binding/names.

        The actual reader/finalization, reservation and original record stay
        retained for full-chain validation and physical commit. An acquisition
        failure keeps its original reader; it never opens a replacement file.
        """
        with self._core._lock:
            installation, configuration, record = self._payload_original(held)
            physical, finalization = held.physical, held.finalization
            if (physical is None or finalization is None or held.reader is not None
                    or held.binding is not None or held.names is not None):
                raise ValueError('Original Sealed reader custody is unavailable')
            child = self._reserve(lambda:
                self._core.reserve_payload_binding(record, cleanup=lambda: True))
            held.binding = child
            installation.binding.inspect(lambda _:
                self._core.produce_payload_binding(child, configuration.handle))
            names = self._reserve(lambda:
                self._core.reserve_payload_names(record, cleanup=lambda: True))
            held.names = names
            installation.binding.inspect(lambda _:
                self._core.produce_payload_names(names, configuration.handle))
            def acquire(_: _Output) -> None:
                self._core.read_payload_binding(child, configuration.handle)
                packet = _object(self._core.read_payload_names(names, configuration.handle), 65536)
                if packet.get('object_name') != finalization.name:
                    raise ValueError('Original Core final name and actual file differ')
                try:
                    held.reader = physical.root.open_reader(finalization)
                except LocalReaderAcquisitionError as failure:
                    held.reader = failure.original_reader
                    raise
            installation.binding.inspect(acquire)
            # Fresh nominal Sealed binding, not a physical completion flag,
            # permits retirement of the old EOF/transition transport loans.
            if held.writing is not None:
                if not self._core.close_payload_writing(held.writing):
                    raise LocalProductCleanupPending(self)
                self._payload_transition_attempts.discard(held.writing.ticket)
                held.writing = None
            if held.chunk is not None:
                if not self._core.close_payload_chunk(held.chunk):
                    raise LocalProductCleanupPending(self)
                held.chunk = None

    def _advance_original_payload_reader(self, held: _PayloadCustody) -> bool:
        """Hash one bounded original File chunk, retaining its completed reader.

        No external borrower receives these bytes. The existing File Owner
        retires its exact chunk after current Core binding/names revalidation;
        its physical EOF/digest is separate from value/chain and publisher
        validation. The same live descriptor is retained for Store fencing.
        """
        with self._core._lock:
            installation, configuration, _ = self._payload_original(held)
            reader, binding, names = held.reader, held.binding, held.names
            if reader is None or binding is None or names is None:
                raise ValueError('Original Sealed physical reader is unavailable')
            completed: list[bool] = []
            def advance(_: _Output) -> None:
                self._core.read_payload_binding(binding, configuration.handle)
                self._core.read_payload_names(names, configuration.handle)
                if not reader.eof:
                    chunk = reader.root.read_reader(reader)
                    self._core.read_payload_binding(binding, configuration.handle)
                    self._core.read_payload_names(names, configuration.handle)
                    reader.root.release_reader_chunk(reader, chunk)
                if reader.eof:
                    reader.root.observe_completed_reader(reader)
                completed.append(reader.eof)
            installation.binding.inspect(advance)
            return completed[0]

    def _prepare_original_commit_candidate(self, publication: _Output, preflight: _Output) -> None:
        """Pass the complete original Sealed binding inventory to Core once.

        The retained input/time is physical request custody, not publication
        permission or a Run state. Core checks the original Manifest, Receipt,
        Captured Run, normalization and binding chain under its existing work
        budget. A failed preparation never receives a replacement request.
        """
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk
                or not any(value is publication for value in self._publications)
                or not any(value is preflight for value in self._publication_preflights)):
            raise ValueError('Foreign original commit candidate custody')
        with self._core._lock:
            request = self._commit_requests.get(publication.ticket)
            if request is None:
                bindings: list[str] = []
                def project(_: _Output) -> None:
                    count = self._core.publication_preflight_result_count(preflight, configuration.handle)
                    selected = [held for held in self._payloads if held.publication is publication]
                    if len(selected) != count:
                        raise ValueError('Incomplete original Local payload binding inventory')
                    for index in range(count):
                        matches = [held for held in selected if held.index == index]
                        if len(matches) != 1:
                            raise ValueError('Ambiguous original Local payload binding ordinal')
                        held = matches[0]
                        self._payload_original(held)
                        if held.binding is None or held.reader is None:
                            raise ValueError('Original Sealed binding/reader is unavailable')
                        held.reader.root.observe_completed_reader(held.reader)
                        bindings.append(self._core.read_payload_binding(
                            held.binding, configuration.handle).decode('utf-8'))
                installation.binding.inspect(project)
                seconds, milliseconds = divmod(self._now(), 1000)
                committed_at = datetime.fromtimestamp(seconds, timezone.utc).replace(
                    microsecond=milliseconds * 1000).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
                request = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                    'bindings': bindings, 'committed_at': committed_at,
                }))
                self._commit_requests[publication.ticket] = request
            installation.binding.inspect(lambda _:
                self._core.prepare_publication_commit(publication, request, configuration.handle))

    def _advance_original_commit_candidate(self, publication: _Output) -> OriginalCommitProjection | None:
        """Advance the original Core budget once; Done yields a readonly view.

        A view/finish Unit is not Store installation, durable ACK or Run success.
        It keeps the original preparation/index/cursor for the physical Store
        and full-chain observed-index adoption, with independent publisher checks.
        """
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk
                or not any(value is publication for value in self._publications)
                or publication.ticket not in self._commit_requests):
            raise ValueError('Original commit preparation is unavailable')
        with self._core._lock:
            for projection in self._commit_projections:
                if projection._publication is publication:
                    installation.binding.inspect(lambda _: projection.count())
                    return projection
            progress = []
            installation.binding.inspect(lambda _:
                progress.append(self._core.advance_publication_commit(publication, configuration.handle,
                                                                      _PUBLICATION_WORK_QUANTUM)))
            if not progress[0].ready:
                return None
            installation.binding.inspect(lambda _:
                self._core.finish_publication_commit(publication, configuration.handle))
            projection = OriginalCommitProjection(self._core, publication, configuration.handle, cleanup=lambda: True)
            self._commit_projections.append(projection)
            return projection

    def _original_commit_reader_facts(self, projection: OriginalCommitProjection) -> tuple[OriginalReaderFacts, ...]:
        """Borrow the complete original record/reader inventory for one view."""
        installation = self._active()
        if not any(value is projection for value in self._commit_projections):
            raise ValueError('Foreign original Local commit view')
        collected: list[OriginalReaderFacts] = []
        def select(_: _Output) -> None:
            count = self._core.publication_commit_result_count(
                projection._publication, projection._configuration)
            selected = [held for held in self._payloads if held.publication is projection._publication]
            if not count or len(selected) != count:
                raise ValueError('Incomplete original Local Result reader inventory')
            for index in range(count):
                matches = [held for held in selected if held.index == index]
                if len(matches) != 1:
                    raise ValueError('Ambiguous original Local Result reader ordinal')
                held = matches[0]
                self._payload_original(held)
                if held.reader is None or held.record is None or held.capacity is None or held.row is None:
                    raise ValueError('Original Sealed reader/fences are unavailable')
                facts = [fact for fact in self._reader_facts
                         if fact._projection is projection and fact._record is held.record]
                if len(facts) > 1:
                    raise ValueError('Ambiguous original Local reader metadata loan')
                if facts:
                    fact = facts[0]
                else:
                    fact = OriginalReaderFacts(projection, held.record, held.reader.root, held.reader,
                        index, index, held.store_authority, held.generation,
                        cleanup=lambda: True, stopped=lambda _: True)
                    # Retain before the first fallible metadata allocation.
                    self._reader_facts.append(fact)
                if fact._reader is not held.reader or fact._result != index:
                    raise ValueError('Foreign original Local completed reader')
                collected.append(fact)
        with self._core._lock:
            installation.binding.inspect(select)
            return tuple(collected)

    def _ensure_original_publication_observation(self, projection: OriginalCommitProjection) -> None:
        """Observe this attempted original write when an explicit status arrives.

        A lost COMMIT response can stop the original worker before lookup. This
        retains the same pending write/publisher and asks the existing Owner to
        inspect the same Store once. It starts no write, acceptance or execution,
        and does not turn the resulting action into ACK or a Run terminal.
        Failed lookup keeps the same observation holder for cleanup, not replay.
        """
        self._active()
        with self._core._lock:
            key = projection._publication.ticket
            if key in self._store_observations:
                if self._store_observations[key]._projection is not projection:
                    raise ValueError('Foreign original Local publication observation')
                return
            publisher = self._pending_publication_publisher
            if (self._pending_publication_write is not projection
                    or key not in self._publication_write_attempts
                    or publisher is None
                    or not any(original is projection for original in self._commit_projections)
                    or not any(original is publisher for original in self._publishers)):
                raise ValueError('Original attempted publication observation is unavailable')
            self._prepare_original_store_observation(projection, publisher)
            while self._advance_original_store_observation(projection) is None:
                pass  # Existing finite observation Owner and shared work/fuel.

    def _prepare_original_store_observation(self, projection: OriginalCommitProjection, publisher: _Output) -> None:
        """Forward actual same-key lookup without a write, resend or ACK.

        All original readers/fences and both transfer workspaces are retained
        before querying. Query failure remains the original Core Unknown action;
        it never becomes NotFound or a new operation. Failed transfer/cleanup
        keeps the same holders and does not allocate another lookup attempt.
        """
        installation = self._active()
        store = installation._store
        if (store is None or not any(value is projection for value in self._commit_projections)
                or not any(value is publisher for value in self._publishers)):
            raise ValueError('Foreign original Local Store observation')
        with self._core._lock:
            key = projection._publication.ticket
            if key in self._observation_attempts:
                raise LocalStorageError('Original Store observation is retained; advance or clean the same handles')
            self._observation_attempts.add(key)
            facts = self._original_commit_reader_facts(projection)
            originals: list[tuple[ByteFence, CapacityReservation]] = []
            for fact in facts:
                held = next(value for value in self._payloads if value.record is fact._record)
                assert held.row is not None and held.capacity is not None
                originals.append((held.row, held.capacity))
            transfers = []
            for _ in range(2):
                # The existing transfer quotes bounded original bytes. Six
                # octets per source octet plus the fixed envelope is its strict
                # worst case, charged before Store rows or encoding are copied.
                transfer = OriginalObservationTransfer(projection, publisher,
                    max_source_bytes=65536, max_packet_bytes=6 * 65536 + 256,
                    cleanup=lambda: True, stopped=lambda _: True,
                    workspace_cleanup=lambda: True, workspace_stopped=lambda: True)
                self._observation_transfers.append(transfer)
                transfers.append(transfer)
                transfer.reserve()
            observation = OriginalStoreReconciliation(projection, facts, store, tuple(originals),
                publisher, transfers[0], transfers[1])
            self._store_observations[key] = observation
            observation.prepare(binding=installation.binding)

    def _advance_original_store_observation(self, projection: OriginalCommitProjection
            ) -> Literal['append_unknown', 'confirm_uncommitted_failure', 'adopt_committed_index'] | None:
        """Return only the original Owner's complete, current full-chain action."""
        self._active()
        with self._core._lock:
            observation = self._store_observations.get(projection._publication.ticket)
            if observation is None or observation._projection is not projection:
                raise ValueError('Original Local Store observation is unavailable')
            progress = observation.advance(16)
            if not progress.ready:
                return None
            action = observation.finish()
            if (action == 'adopt_committed_index'
                    and self._pending_publication_write is projection):
                publisher = self._pending_publication_publisher
                if publisher is None or observation._publisher is not publisher:
                    raise ValueError('Foreign original publication attempt retirement')
                # The action alone is not acknowledgement. Re-export the full
                # admitted original index under its actual File/Store/current
                # and publisher checks before retiring this transient blocker.
                # The observation, publisher and attempted ticket stay owned;
                # this never permits replay of the original publication.
                observation.project_observed_index(lambda _identity, _body: None)
                self._pending_publication_write = None
                self._pending_publication_publisher = None
            return action

    def _project_original_observed_index(self, projection: OriginalCommitProjection,
                                         consume: Callable[[bytes, bytes], object]) -> None:
        """Forward the actual stored index to the original publication caller only.

        The index export itself checks the full-chain observation and publisher;
        action codes and physical write returns cannot supply these bytes.
        """
        self._active()
        with self._core._lock:
            observation = self._store_observations.get(projection._publication.ticket)
            if observation is None or observation._projection is not projection:
                raise ValueError('Original Local Store observation is unavailable')
            observation.project_observed_index(consume)

    def _original_sdk_read_observation(self, run: _Run,
                                    projection: OriginalCommitProjection) -> OriginalStoreReconciliation:
        """Recheck the original Run/current/Store for both private read holders."""
        installation = self._active()
        configuration = self._configuration
        self._runs._run(run)
        if (configuration is None or not configuration.sdk
                or not any(original is run for original in self._run_loans)
                or not any(original is projection for original in self._commit_projections)):
            raise ValueError('Foreign original SDK read evidence')
        with self._core._lock:
            installation.binding.inspect(lambda _:
                self._core.validate_publication_run(projection._publication,
                    run.handle, configuration.handle))
            # Current callbacks may reenter close. Recheck original custody
            # after the callback before returning a cached holder or reserving.
            if self._active() is not installation:
                raise ValueError('Changed original SDK read installation')
            self._runs._run(run)
            projection._ready()
            if (self._configuration is not configuration
                    or not any(original is run for original in self._run_loans)
                    or not any(original is projection for original in self._commit_projections)):
                raise ValueError('Released original SDK read custody')
            key = projection._publication.ticket
            observation = self._store_observations.get(key)
            if observation is None or observation._projection is not projection:
                raise ValueError('Original SDK read Store observation is unavailable')
            return observation

    def _original_sdk_read_evidence(self, run: _Run,
                                    projection: OriginalCommitProjection) -> OriginalSDKReadEvidenceStore:
        with self._core._lock:
            observation = self._original_sdk_read_observation(run, projection)
            key = projection._publication.ticket
            original = self._sdk_read_evidence.get(key)
            if original is not None:
                if original._observation is not observation:
                    raise ValueError('Foreign original SDK read Store holder')
                return original
            try:
                original = OriginalSDKReadEvidenceStore(observation, cleanup=lambda: True)
            except SDKReadEvidenceCleanupPending as failure:
                # Retain before returning/trapping; do not construct a second
                # workspace or repair a failed original holder on the next read.
                self._sdk_read_evidence[key] = failure.cleanup_evidence
                raise
            self._sdk_read_evidence[key] = original
            return original

    def _original_sdk_delivery_store(self, run: _Run,
                                     projection: OriginalCommitProjection) -> OriginalSDKDeliveryStore:
        """One original delivery workspace; no repair or replacement on refusal."""
        with self._core._lock:
            observation = self._original_sdk_read_observation(run, projection)
            key = projection._publication.ticket
            original = self._sdk_deliveries.get(key)
            if original is not None:
                if original._observation is not observation:
                    raise ValueError('Foreign original SDK delivery Store holder')
                return original
            try:
                original = OriginalSDKDeliveryStore(observation, cleanup=lambda: True)
            except SDKDeliveryStorageCleanupPending as failure:
                self._sdk_deliveries[key] = failure.cleanup_storage
                raise
            self._sdk_deliveries[key] = original
            return original

    def _persist_original_sdk_delivery(self, run: _Run,
                                       projection: OriginalCommitProjection,
                                       request: _Input) -> None:
        """Original physical first CAS only; no use adoption or public read."""
        with self._core._lock:
            self._core._owned_input(request)
            self._original_sdk_delivery_store(run, projection).persist(request, run.handle)

    def _persist_original_sdk_read_evidence(self, run: _Run,
                                           projection: OriginalCommitProjection,
                                           request: _Input) -> None:
        """Same-Store physical evidence only; not grant usage, delivery or ACK."""
        with self._core._lock:
            self._core._owned_input(request)
            self._original_sdk_read_evidence(run, projection).persist(request, run.handle)

    def _project_original_sdk_read_grant(self, run: _Run,
                                         projection: OriginalCommitProjection,
                                         request: _Input,
                                         consume: Callable[[ByteWrite], object]) -> None:
        """Lookup the original evidence through Core without repeating a write."""
        with self._core._lock:
            self._core._owned_input(request)
            self._original_sdk_read_evidence(run, projection).project_grant(request, run.handle, consume)

    def _project_original_run_state(self, projection: OriginalCommitProjection,
                                    consume: Callable[[bytes], object]) -> None:
        """Forward Core RunState bytes under the original File/Store/current frame.

        Only the physical observation clock is supplied here. Cleanup retains
        its same input if output retirement or physical stop is incomplete.
        This neither marks ACK nor infers availability or grants Result read.
        """
        self._active()
        if not callable(consume):
            raise ValueError('Invalid original Run observation consumer')
        with self._core._lock:
            observation = self._store_observations.get(projection._publication.ticket)
            if observation is None or observation._projection is not projection:
                raise ValueError('Original Local Store observation is unavailable')
            # A pending output must not allocate another clock loan on a poll.
            projection._ready()
            now = self._now()
            if type(now) is not int or not 0 <= now <= 253402300799999:
                raise ValueError('Invalid Local physical observation time')
            seconds, milliseconds = divmod(now, 1000)
            observed_at = datetime.fromtimestamp(seconds, timezone.utc).replace(
                microsecond=milliseconds * 1000).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
            source = self._copy(wire_bytes({'observed_at': observed_at}))  # type: ignore[no-untyped-call]
            try:
                observation.project_run_state(source, consume)
            except BaseException:
                # No output means the current File/Store fence refused before
                # Core acquired the dependent output. Only the buffer Owner
                # may confirm that this physical clock loan can be reclaimed.
                # A trap or live output retains it for same-handle cleanup.
                if not projection.pending_outputs and not self._core._closing:
                    if not self._core.close_input(source):
                        raise LocalProductCleanupPending(self) from None
                    self._inputs.remove(source)
                raise
            if not self._core.close_input(source):
                raise LocalProductCleanupPending(self)
            self._inputs.remove(source)

    def _store_original_commit(self, projection: OriginalCommitProjection,
                               facts: tuple[OriginalReaderFacts, ...],
                               originals: tuple[tuple[ByteFence, CapacityReservation], ...],
                               publisher: _Output) -> None:
        """Physically project the original Done chain once; no Run ACK occurs.

        Payload production retains these original File/record/fact loans and
        their separately reserved workspace. The same Core/File/current frame
        spans every projected field and publisher stage inside the write TX.
        Physical generations do not clear pending custody: only later original
        full-chain lookup/adoption can acknowledge publication. A conflict or
        Unknown never selects a new request, index, task or write attempt here.
        """
        installation = self._active()
        configuration = self._configuration
        store = installation._store
        if (configuration is None or not configuration.sdk or store is None
                or type(projection) is not OriginalCommitProjection
                or projection._core is not self._core
                or projection._configuration != configuration.handle
                or not any(original is projection._publication for original in self._publications)
                or not any(original is publisher for original in self._publishers)
                or type(facts) is not tuple or not facts
                or any(type(fact) is not OriginalReaderFacts or fact._projection is not projection
                       for fact in facts)):
            raise ValueError('Foreign original Local publication commit custody')
        with self._core._lock:
            if (projection._publication.ticket in self._publication_write_attempts
                    or self._pending_publication_write is not None):
                raise LocalStorageError('Original publication write requires lookup; replay is unavailable')
            # Retain children before the first fallible validation/transfer.
            # A failed count or metadata fill can already hold an original loan.
            if not any(original is projection for original in self._commit_projections):
                self._commit_projections.append(projection)
            for fact in facts:
                if not any(original is fact for original in self._reader_facts):
                    self._reader_facts.append(fact)
            with ExitStack() as loans:
                for fact in facts: loans.enter_context(fact.serialized())
                counts: list[int] = []
                def inspect_count(_: _Output) -> None:
                    if (projection._storage_counts()[1] != len(facts)
                            or any(fact._result != index for index, fact in enumerate(facts))):
                        raise ValueError('Incomplete original Local Result fact inventory')
                    for fact in facts: fact.validate()
                    counts.append(projection.storage_count())
                installation.binding.inspect(inspect_count)
                def before_commit() -> None:
                    for fact in facts: fact.before_commit(publisher)
                with installation.binding.fenced() as fences:
                    self._publication_write_attempts.add(projection._publication.ticket)
                    self._pending_publication_write = projection
                    self._pending_publication_publisher = publisher
                    generations = store.store_publication_projected_inspected(
                        counts[0], projection.project_storage_entry, originals, fences,
                        inspect=lambda reader, consume:
                            installation.binding.inspect_reader(reader, lambda _: consume()),
                        current=installation.binding._current_observer, before_commit=before_commit)
                if generations is None:
                    raise LocalStorageError('Original publication write conflicted; lookup is required')

    def close(self) -> bool:
        self._nominal()
        if self._state_observing or any(not work.stopped for work in self._physical_work):
            return False
        with self._core._host_cleanup():
            return self._close_originals()

    def _close_originals(self) -> bool:
        """Stop this Host's resources only; never cancel/replay/delete a Run."""
        self._nominal()
        if self._state_observing or any(not work.stopped for work in self._physical_work):
            return False
        with self._core._lock:
            self._closing = True
            for stream in tuple(self._response_streams):
                if stream._attached or not stream._close():
                    return False
            if self._uncertain_ticket is not None and not self._core._closed:
                return False
            if not self._client_check.close():
                return False
            for saved_read in tuple(reversed(self._saved_result_reads)):
                if not saved_read.close():
                    return False
                self._saved_result_reads.remove(saved_read)
            for key, state_custody in tuple(self._run_state_custody.items()):
                if state_custody.output is not None:
                    if not self._core.close_publication_commit_export(state_custody.output):
                        return False
                    state_custody.output = None
                if not self._core.close_input(state_custody.source):
                    return False
                self._inputs.remove(state_custody.source)
                del self._run_state_custody[key]
            for projection in tuple(reversed(self._commit_projections)):
                if not projection.close():
                    return False
                self._commit_projections.remove(projection)
            for key, evidence in tuple(self._sdk_read_evidence.items()):
                if not evidence.close():
                    return False
                del self._sdk_read_evidence[key]
            for key, delivery in tuple(self._sdk_deliveries.items()):
                if not delivery.close():
                    return False
                del self._sdk_deliveries[key]
            for observation in tuple(self._store_observations.values()):
                publication = observation._projection._publication
                if not self._core.retire_publication_observation(publication):
                    return False
                if not self._core.retire_publication_lookup(publication):
                    return False
            for transfer in tuple(reversed(self._observation_transfers)):
                if not transfer.close():
                    return False
                self._observation_transfers.remove(transfer)
            self._store_observations.clear()
            for fact in tuple(reversed(self._reader_facts)):
                if not fact.close():
                    return False
                self._reader_facts.remove(fact)
            for held in tuple(reversed(self._payloads)):
                if (held.record is not None and held.record.ticket in self._payload_capacity_attempts
                        and held.capacity is None):
                    return False
                if held.chunk is not None:
                    if not self._core.close_payload_chunk(held.chunk):
                        return False
                    held.chunk = None
                if held.binding is not None:
                    if not self._core.close_payload_binding(held.binding):
                        return False
                    held.binding = None
                if held.names is not None:
                    if not self._core.close_payload_names(held.names):
                        return False
                    held.names = None
                if held.allocation is not None:
                    if not self._core.close_payload_allocation(held.allocation):
                        return False
                    if held.allocation_attempts is not None:
                        held.allocation_attempts.discard(held.allocation.ticket)
                    held.allocation = None
                if held.writing is not None:
                    if not self._core.close_payload_writing(held.writing):
                        return False
                    self._payload_transition_attempts.discard(held.writing.ticket)
                    held.writing = None
                if held.reservation is not None:
                    if not self._core.close_payload_reservation(held.reservation):
                        return False
                    self._payload_transition_attempts.discard(held.reservation.ticket)
                    held.reservation = None
                if held.adoption is not None:
                    if held.physical is not None:
                        # Name work pins the writer after physical stop. Stop
                        # its original descriptor before retiring that cursor.
                        held.physical.root.close_writer(held.physical)
                        if held.physical.descriptor is not None:
                            return False
                    if held.origin is None or not held.origin.close_adoption(held.adoption):
                        return False
                    held.adoption = None
                if held.reader is not None:
                    if not held.reader.root.close_reader(held.reader):
                        return False
                    held.reader = None
                if held.finalization is not None:
                    if held.physical is None:
                        return False
                    held.physical.root.close_writer(held.physical)
                    if not held.physical.root.close_finalization(held.finalization):
                        return False
                    held.finalization = None
                if held.physical is not None:
                    if not held.physical.root.close_writer(held.physical):
                        return False
                    held.physical = None
                if held.origin is not None:
                    if not held.origin.close():
                        return False
                    held.origin = None
                if held.area is not None:
                    if self._installation is None or self._installation._results is None:
                        return False
                    if not self._installation._results.close_area(held.area):
                        return False
                    held.area = None
                if held.record is not None:
                    if not self._core.close_payload_record(held.record):
                        return False
                    self._payload_write_attempts.discard(held.record.ticket)
                    self._payload_capacity_attempts.discard(held.record.ticket)
                    held.record = None
                if held.request is not None:
                    if not self._core.close_payload_request(held.request):
                        return False
                    held.request = None
                if held.workspace is not None:
                    if not self._core.close_workspace(held.workspace):
                        return False
                    held.workspace = None
                self._payloads.remove(held)
            for publication in tuple(reversed(self._publications)):
                if not self._core.close_publication(publication):
                    return False
                self._publications.remove(publication)
                self._run_publications[:] = [(run, original) for run, original in self._run_publications
                                            if original is not publication]
                self._commit_requests.pop(publication.ticket, None)
                self._publication_write_attempts.discard(publication.ticket)
                if (self._pending_publication_write is not None
                        and self._pending_publication_write._publication is publication):
                    self._pending_publication_write = None
                    self._pending_publication_publisher = None
            for chunk in tuple(reversed(self._result_chunks)):
                if not self._core.close_result_chunk(chunk):
                    return False
                self._result_chunks.remove(chunk)
            for result in tuple(reversed(self._result_exports)):
                if not self._core.close_result_export(result):
                    return False
                self._result_exports.remove(result)
            for task in tuple(reversed(self._tasks)):
                if not self._core.close_task(task):
                    return False
                self._tasks.remove(task)
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
            for run, output in tuple(reversed(self._publication_bindings)):
                if not self._core.close_material(output):
                    return False
                self._publication_bindings.remove((run, output))
                self._binding_write_attempts.discard(output.ticket)
                if self._pending_binding_write is output:
                    self._pending_binding_write = None
            for output in tuple(reversed(self._journal_outputs)):
                if not self._core.close_journal_observation(output):
                    return False
                self._journal_outputs.remove(output)
                self._admission_observations = {run: original
                    for run, original in self._admission_observations.items()
                    if original is not output}
            for output in tuple(reversed(self._row_outputs)):
                if not self._core.close_material(output):
                    return False
                self._row_outputs.remove(output)
                self._run_rows[:] = [(run, original) for run, original in self._run_rows
                                     if original is not output]
                self._row_write_attempts.discard(output.ticket)
                if self._pending_run_write is output:
                    self._pending_run_write = None
            for run in tuple(reversed(self._run_loans)):
                if not self._runs.close_run(run):
                    return False
                self._run_loans.remove(run)
                self._public_run_references[:] = [original for original in self._public_run_references
                                                  if original.run is not run]
            for prepared in tuple(reversed(self._prepared_inputs)):
                if not self._preparation.close_preparation(prepared):
                    return False
                self._prepared_inputs.remove(prepared)
            for restored in tuple(reversed(tuple(self._runs._restorations.values()))):
                if not self._runs.close_restoration(restored):
                    return False
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
            if self._project_configuration is not None:
                if not self._project_configuration.close():
                    return False
                self._project_configuration = None
            for source in tuple(reversed(self._inputs)):
                if not self._core.close_input(source):
                    return False
                self._inputs.remove(source)
            self._append_sources.clear()
            if self._installation is not None:
                if not self._installation.close():
                    return False
                self._installation = None
            if self._project_files is not None:
                if not self._project_files.close():
                    return False
                self._project_files = None
                self._project_locations = None
                self._project_members.clear()
            if not self._core.close():
                return False
            self._physical_work.clear()
            self._run_restore_attempts.clear()
            return True
