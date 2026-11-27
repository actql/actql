"""Installed Local assembly over the original Core/File/Store Owners.

This is the in-process Host's connection assembly, not a Run controller. The
public factory is connected only after its operation/Result ports are ready.
No bootstrap/profile/epoch result is an admission or execution permission.
"""
from __future__ import annotations

from collections.abc import AsyncIterator, Callable, Iterable as _Iterable, Iterator as _Iterator
from contextlib import ExitStack, asynccontextmanager, contextmanager as _contextmanager, nullcontext
from dataclasses import dataclass
from datetime import datetime, timezone
from base64 import b64encode
from threading import current_thread as _current_thread
import asyncio
import hashlib
import os
import re as _re
from struct import Struct as _Struct
import secrets
from pathlib import Path
import stat
import sys
import time
from typing import TYPE_CHECKING, Any, Literal, TypeVar
from typing import NoReturn as _NoReturn

if TYPE_CHECKING:
    from ._local_effect_key_original import _OriginalEffectHostKey
    from ._local_initial_preparation import _OriginalPythonPreparation
    from ._local_mock_file_writer import _MockFileReplacementAck, _MockFileTarget, _MockFileWriter
    from ._local_model_crypto import _OriginalModelEvidenceCrypto, _OriginalEffectSignatureCrypto
    from ._local_model_http import _CompleteModelHttpResponse, _ModelHttpTransportFailure, _OriginalModelHttpRawTransfer

import httpx

from . import _wire as wire, _local_review_crypto
from ._local_core import (
    _INCREMENTAL_SAVED_RESULT_KIND, _NAMED_SUBMISSION_APPEND_KIND, _NAMED_SUBMISSION_KIND,
    _SAVED_RESULT_COORDINATES_BYTES,
    _LOCAL_CSV_OFFER_KIND, _LOCAL_CSV_RESPONSE_KIND,
    _MOCK_EFFECT_COMPUTE_KIND, _MOCK_EFFECT_REVIEW_READ_KIND, _MOCK_EFFECT_REVIEW_EXTENT_KIND,
    _MOCK_EFFECT_CHECKPOINT_CONFIRM_KIND, _MOCK_EFFECT_WAITING_KIND, _MOCK_EFFECT_WAITING_FIELD_KIND,
    _MOCK_EFFECT_SOURCE_CAPTURE_KIND, _MOCK_EFFECT_SOURCE_EVIDENCE_KIND,
    _SAVED_EFFECT_CHECKPOINT_PAGE_KIND, _SAVED_EFFECT_CHECKPOINT_REVIEW_KIND,
    _SAVED_EFFECT_RESOLUTION_PROOF_KIND, _SAVED_EFFECT_ATTESTATION_USE_KIND,
    _SAVED_EFFECT_DECISION_KIND, _SAVED_EFFECT_DECISION_FIELD_KIND, _SAVED_EFFECT_RESUME_KIND,
    _SAVED_EFFECT_APPLICATION_KIND, _SAVED_EFFECT_FILE_DISPATCH_KIND, _SAVED_EFFECT_FILE_DISPATCH_FIELD_KIND,
    _SAVED_EFFECT_FILE_OPERATION_KIND, _SAVED_EFFECT_FILE_REPLACEMENT_KIND,
    _SAVED_EFFECT_FILE_RESPONSE_KIND, _SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND,
    _SAVED_EFFECT_FILE_TERMINAL_KIND, _SAVED_EFFECT_FILE_COMPLETION_KIND,
    _SAVED_EFFECT_FILE_PUBLISHED_KIND,
    _original_metadata_cleanup, _original_metadata_stopped, _TaskDrive,
)
from ._local_core import LocalCore, LocalCoreError, LocalCoreInitializationError, LocalCoreResources, _Input, _Output, _Workspace, _PublisherFact, _Task, _ResultExport, LocalTaskProgress, LocalResultProgress
from ._local_distribution import installed_local_components, LocalInstallationError, LocalComponents
from ._local_files import (LocalFileRoot, _AllocationArea, _PayloadFile, _NameAdoption, _FileFinalization, _FileReader,
    LocalAreaAcquisitionError, LocalFileAcquisitionError, LocalReaderAcquisitionError)
from ._local_csv_transfer import _LocalCsvTransfer
from ._local_installation import OriginalLocalInstallation, LocalInstallationCleanupPending, _object
from ._local_preparation import LocalPreparation, LocalPreparationFailure, _Environment, _MockRequest, _Preparation
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
from ._local_saved_read import OriginalSavedResultRead, _SavedRunControl
from ._local_check import OriginalLocalCheck
from ._local_storage import (
    ByteFence, ByteWrite, CapacityReservation, LocalStorageError, StoredBytes,
    _ModelRawFence, _NamespaceReader, LocalRunDefinitionConflict,
)
from ._local_storage import LocalStorageCommitUnknown as _LocalStorageCommitUnknown
from ._local_native_store import _OriginalNativeStoreSelection
from ._values import canonical_bytes as _canonical_bytes, content_cid, wire_bytes

_T = TypeVar('_T')
_LOCAL_SELECTION = {'mode': 'local', 'owner': 'local', 'durability': 'durable',
                    'consentRefs': [], 'runners': []}
_PUBLICATION_WORK_QUANTUM = 256
_EXECUTION_WORK_QUANTUM = 256
_MOCK_REVIEW_HOLDINGS = (
    (0, 'effect_capture_custody', 'effect_capture', 'capture_key', 'capture_cid'),
    (1, 'effect_preview_custody', 'effect_preview', 'preview_key', 'preview_cid'),
    (2, 'effect_continuation_custody', 'continuation_record', 'checkpoint_cid', 'continuation_cid'),
    (3, 'effect_checkpoint_custody', 'checkpoint', 'checkpoint_cid', 'checkpoint_cid'),
    (6, 'effect_review_projection_custody', 'review_projection', 'checkpoint_cid', 'review_cid'),
)
_MOCK_REVIEW_COORDINATE_FIELDS = tuple(sorted({
    field for _, _, _, key, cid in _MOCK_REVIEW_HOLDINGS for field in (key, cid)
}))
_MOCK_REVIEW_COORDINATE_WIRE = _re.compile(rb'\{' + b','.join(
    b'"' + field.encode('ascii') + b'":"(sha256:[0-9a-f]{64})"'
    for field in _MOCK_REVIEW_COORDINATE_FIELDS) + rb'\}')
_SDK_RUN_STATE_HEADER = _Struct('<qIB71s')
_SDK_RUN_STATE_KEY = _re.compile(rb'sha256:[0-9a-f]{64}')
_MOCK_WAITING_HEADER = _Struct('<qIII')
_MOCK_WAITING_TABLES = ('client_runs', 'client_effect_custody', 'client_checkpoint_id_index')
_MOCK_WAITING_CID = _re.compile(rb'sha256:[0-9a-f]{64}')
_MOCK_WAITING_LOCATOR = _re.compile(rb'[0-9a-f]{64}')
_MOCK_WAITING_BODY_OFFSET = _MOCK_WAITING_HEADER.size + 71 + 64



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


@dataclass(slots=True, eq=False)
class _OriginalCsvCapture:
    start: _PhysicalStart
    capture: _Output | None = None
    transfer: _LocalCsvTransfer | None = None
    workspace: _Workspace | None = None
    metadata_workspace: _Workspace | None = None
    stopped: bool = False

    def stop(self, reader: int) -> bool:
        if self.capture is None:
            return self.transfer is None
        if reader != self.capture.handle:
            return False
        if not self.stopped:
            self.stopped = self.transfer is None or self.transfer.close()
        return self.stopped


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


@dataclass(frozen=True, slots=True, eq=False)
class _OriginalNamedSubmission:
    name: ByteFence
    preparing: ByteFence


@dataclass(eq=False)
class _RunStateCustody:
    # Same-Host pending input/output custody; counters always come from Store.
    run: _Run
    projection: OriginalCommitProjection | None
    source: _Input
    output: _Output | None = None
    prepared: bool = False
    write_attempted: bool = False
    first_failure: BaseException | None = None
    body_output: _Output | None = None
    metadata_confirmed: bool = False
    read_returned: bool = False


@dataclass(slots=True, eq=False)
class _OriginalEffectAttestationUse:
    proof: _Output
    offer: _Output
    key_generation: bytes
    checkpoint: str
    key_id: str
    public_key: str
    preimage: str
    sampled_at: int
    expires_at: int
    writes: tuple[ByteWrite, ...]
    write_attempted: bool = False
    confirmed: bool = False
    sign_attempted: bool = False
    key: '_OriginalEffectHostKey | None' = None
    signature: str | None = None
    decision: _Output | None = None
    transition_write: ByteWrite | None = None
    decision_attempted: bool = False
    decision_confirmed: bool = False
    resume_environment: _Output | None = None
    resume_claim: _Output | None = None
    resume_attempted: bool = False
    resume_confirmed: bool = False
    application: _Output | None = None
    application_attempted: bool = False
    file_rows: int = 0
    file_completed: int = 0
    file_active: int | None = None
    file_dispatch: _Output | None = None
    file_dispatch_cid: str | None = None
    file_dispatch_writes: tuple[ByteWrite, ...] = ()
    file_apply_attempted: bool = False
    file_operation: _Output | None = None
    file_replacement: _Output | None = None
    file_target: '_MockFileTarget | None' = None
    file_writer: '_MockFileWriter | None' = None
    file_hold: _Workspace | None = None
    file_ack: '_MockFileReplacementAck | None' = None
    file_response_attempted: bool = False
    file_response: _Output | None = None
    file_terminal_attempted: bool = False
    file_terminal: _Output | None = None
    file_completion_attempted: bool = False
    file_completion: _Output | None = None
    file_publication_attempted: bool = False
    file_publication_confirmed: bool = False
    file_publication_fences: tuple[ByteFence, ...] = ()
    file_journal_output: _Output | None = None
    file_journal_writes: tuple[ByteWrite, ...] = ()


@dataclass(slots=True, eq=False)
class _OriginalExecution:
    """Fixed invoke custody; every decision remains with the original Core.

    Replace the former partial/bound-method envelope, not its physical worker.
    Lists and the confirmed output are existing originals, never copies or
    success/permission caches. Fixed fields use the trusted Host overhead.
    """
    host: 'InstalledLocalHost'
    run: _Run
    reference: _OriginalRunReference | None = None
    compute: _SourceFreeCompute | None = None
    preflight: _Output | None = None
    publisher: _Output | None = None
    tasks: list[_Task] | None = None
    results: list[_ResultExport] | None = None
    publication: _Output | None = None
    state: _RunStateCustody | None = None
    submission: _Output | None = None
    rows_input: _Input | None = None
    physical_start: _PhysicalStart | None = None
    prepared_file: bool = False
    mock_file_source: _Output | None = None
    prepared_model: bool = False
    prepared_effect: bool = False
    mock_review_crypto: _OriginalModelEvidenceCrypto | None = None
    mock_review_write_attempted: bool = False
    mock_waiting_write_attempted: bool = False
    mock_waiting_confirmed: bool = False
    mock_waiting: _Output | None = None
    model_transfer: _OriginalModelHttpRawTransfer | None = None
    model_unknown_transport: _ModelHttpTransportFailure | None = None
    start_step: _Output | None = None
    file_dispatch_step: _Output | None = None
    # A consumed Core-derived physical stop request. This original association
    # is not business authority, current permission, cancellation state or ACK.
    stop_interest: _Output | None = None
    # One failed original attempt/cause association, not a resolution or grant.
    # The existing Core/Store readback must qualify the same publication anew.
    publication_reply_loss: tuple[OriginalCommitProjection, _Output,
        _LocalStorageCommitUnknown, BaseException] | None = None

    def __call__(self) -> None:
        if self.reference is None:
            raise ValueError('Original execution has no admitted reference')
        try:
            self.host._execute_original_admitted_run(self.run)
        except _OriginalCancellationStop as stop:
            if stop.original is not self:
                raise
            # Existing handlers have sealed this same DAG and attempted its
            # original child retirement. Pending/failed cleanup stays retained;
            # only the separate Core state Owner can determine cancellation.
            with self.host._core._lock:
                work = next(value for value in self.host._physical_work if value._invoke is self)
                if work._cleanup_error is not None:
                    raise work._cleanup_error
                if self.tasks is not None and any(
                        self.host._core._task_loans.get(task.handle) is task for task in self.tasks):
                    raise LocalProductCleanupPending(self.host)

    def input_cleanup(self) -> bool:
        # Only immutable in-memory input transport, exactly as the former
        # lambda: True. Buffer borrowers still own actual stop/return checks.
        # The bound receiver records construction association, not authority.
        return True


class LocalProductCleanupPending(RuntimeError):
    def __init__(self, host: 'InstalledLocalHost') -> None:
        super().__init__('Installed Local Host cleanup is pending')
        self.cleanup_host = host


class _OriginalCancellationStop(Exception):
    """Same invocation's physical control request, not a business failure/state."""
    def __init__(self, original: _OriginalExecution) -> None:
        super().__init__('Original cancellation requests physical retirement')
        self.original = original


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
                 _project_profile: str | None = None,
                 _project_runtime_cid: str | None = None,
                 _portable_model_directory: Path | None = None) -> None:
        if type(core) is not LocalCore or not callable(now):
            raise ValueError('Installed Local Host requires its original Core')
        self._original = self
        self._core = core
        self._now = now
        self._installation: OriginalLocalInstallation | None = None
        self._preparation = LocalPreparation(core)
        self._environment: _Environment | None = None
        self._prepared_inputs: list[_Preparation | _MockRequest] = []
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
        self._pending_cancellation_write: _Output | None = None
        # Bounded routing DATA for this same retained projection, never a
        # cancellation decision or permission to consume a different original.
        self._pending_cancellation_locator: bytes | None = None
        self._step_outputs: list[_Output] = []
        self._step_write_attempts: set[int] = set()
        self._pending_start_write: _Output | None = None
        self._publication_bindings: list[tuple[_Run, _Output]] = []
        self._binding_write_attempts: set[int] = set()
        self._pending_binding_write: _Output | None = None
        self._physical_starts: list[_PhysicalStart] = []
        self._mock_effect_sources: list[_Output] = []
        self._saved_mock_review_crypto: _OriginalModelEvidenceCrypto | _OriginalEffectSignatureCrypto | None = None
        self._effect_attestation_use: _OriginalEffectAttestationUse | None = None
        self._mock_review_workspaces: list[_Workspace] = []
        self._mock_review_reads: dict[_Output, list[_Input | _Output]] = {}
        self._local_csv_captures: list[_OriginalCsvCapture] = []
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
        self._project_runtime_cid = _project_runtime_cid
        self._project_files: OriginalLocalProjectFiles | None = None
        self._project_configuration: OriginalLocalProjectConfiguration | None = None
        self._project_locations: ProjectLocations | None = None
        self._project_members: list[tuple[str, str | None, _ProjectFile]] = []
        try:
            if _project_directory is not None:
                project_state = self._capture_project(
                    _project_directory, _project_profile,
                    portable_model=_portable_model_directory is not None)
                directory = _private_state_directory(
                    project_state if directory is None else
                    OriginalLocalProjectFiles._path(_project_directory / directory))
            elif _project_profile is not None or directory is None or _portable_model_directory is not None:
                raise ValueError('Original project directory is unavailable')
            assert directory is not None
            project = self._project_configuration
            local = self._original_local_project_input()
            portable_task = None
            if _portable_model_directory is not None:
                if (not sdk_finite or project is None
                        or project._mock_inputs is not None or len(project._model_tasks) != 1):
                    raise ValueError('Original selected Portable Chat Task is unavailable')
                portable_task = project._model_tasks[0]
            self._installation = OriginalLocalInstallation(core, directory,
                observed_at=observed_at, now=now, project_epoch=self._project_epoch,
                sdk_finite=sdk_finite, native_store=_native_store,
                project_bootstrap=(self._original_project_bootstrap
                    if project is not None and local is None and portable_task is None else None),
                local_project_bootstrap=(self._required_local_project_input if local is not None else None),
                portable_model_directory=_portable_model_directory)
            portable_configuration = None
            if portable_task is not None:
                files = self._project_files
                assert project is not None and files is not None
                files.current()
                portable_configuration = self._installation._prepare_portable_chat_task(portable_task)
                if project.prepare().connectors is not None:
                    connectors, = (member for role, _, member in self._project_members if role == 'connectors')
                    registry, = (member for role, _, member in self._project_members if role == 'model_tasks')
                    self._installation.binding.inspect(lambda _: project.prepare_local_inputs(
                        files, connectors=connectors, registry=registry, copy=self._copy,
                        reserve=self._reserve, model_configuration=portable_configuration))
                    local = self._required_local_project_input()
                files.current()
            # Exact original file bytes supply only a CID claim. Core validates
            # that claim and the policy body; it is not publisher authority.
            binding = self._installation.binding
            policy = next(value for value in binding._selected if value.name == 'result-policy.json')
            raw = binding._source.original_bytes(policy)
            setup_data: dict[str, Any] = {'namespace': 'local', 'source_free_result_policy': {
                'cid': 'sha256:' + hashlib.sha256(raw).hexdigest(), 'body': raw.decode('utf-8')}}
            project = self._project_configuration
            mock = (self._original_project_bootstrap() if project is not None
                    and project._mock_inputs is not None else None)
            if mock is not None:
                setup_data['mock_project'] = mock.handle
            if local is not None:
                setup_data['local_project'] = local.handle
            if portable_configuration is not None:
                setup_data['portable_model'] = portable_configuration.handle
            setup = self._copy(wire_bytes(setup_data))  # type: ignore[no-untyped-call]

            def configure(current: _Output) -> None:
                self._configuration = (self._runs.install_sdk_configuration(current, setup)
                    if sdk_finite else self._runs.install_current_configuration(current, setup))
                if mock is not None and self._original_project_bootstrap() is not mock:
                    raise ValueError('Original Mock Project changed during configuration')
                if local is not None and self._required_local_project_input() is not local:
                    raise ValueError('Original Local Project changed during configuration')

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
                  _project_profile: str | None = None,
                  _model_deployment: str | os.PathLike[str] | None = None) -> InstalledLocalHost:
        """Resolve the selected cohort and optional protected Model directory."""
        if (type(_discover_project) is not bool
                or _project_profile is not None and (
                    not _discover_project or type(_project_profile) is not str or len(_project_profile) > 65536)
                or _model_deployment is not None and not _discover_project):
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
        model_directory = None
        if _model_deployment is not None:
            try:
                model_directory = _state_directory_option(_model_deployment)
            except (TypeError, ValueError) as failure:
                raise LocalInstallationError('Invalid protected Local Model deployment directory') from failure
            if model_directory is None or not model_directory.is_absolute():
                raise LocalInstallationError('Invalid protected Local Model deployment directory')
        if resources is None:
            resources = _ordinary_core_limits()
        components = installed_local_components()
        model_crypto = components.model_crypto
        if model_directory is not None and model_crypto is None:
            raise LocalInstallationError('Installed Local Model crypto component is unavailable')
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
                if model_crypto is not None:
                    # Lend only the selected manifest member to this Core.
                    # The original Model worker owns its physical open.
                    core._installed_model_crypto = (components.module.parent, model_crypto)
                if _discover_project:
                    return cls(core, directory_option,
                        now=lambda: time.time_ns() // 1_000_000,
                        observed_at=datetime.now(timezone.utc).isoformat(
                            timespec='milliseconds').replace('+00:00', 'Z'), sdk_finite=True,
                        _project_directory=Path.cwd(), _project_profile=_project_profile,
                        _project_runtime_cid='sha256:' + components.artifact_sha256,
                        _portable_model_directory=model_directory)
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

    @asynccontextmanager
    async def _operation_lock(self, work: OriginalLocalWork | None = None) -> AsyncIterator[None]:
        """Wait before acquisition, then retain this thread's original RLock.

        No queued callback or executor can acquire custody after cancellation.
        The synchronous operation body never awaits while holding this lock.
        """
        with work._control_turn() if work is not None else nullcontext():
            lock = self._core._lock
            while not lock.acquire(blocking=False):
                await asyncio.sleep(0.001)
            try:
                self._active()
                yield
            finally:
                lock.release()

    async def open(self, operation: str, payload: bytes) -> httpx.Response:
        self._active()
        body = _object(payload, 1048576)
        if (type(operation) is not str or not wire.valid_body(operation, body)  # type: ignore[no-untyped-call]
                or body['connection'] != _LOCAL_SELECTION):
            raise ValueError('Invalid original Local Client operation')
        if operation == 'submit-named-intent':
            return await self._open_named_submission(body)
        active = next((work for work in self._physical_work if not work.stopped), None)
        if active is not None:
            # Reference equality locates the retained original only. Core still
            # checks this operation's actual Account, journal and Run originals.
            reference = _canonical_bytes(body.get('ref'), data_keys=True)  # type: ignore[no-untyped-call]
            async with self._operation_lock(active if operation in (
                    'status', 'cancel', 'lookup-cancellation') else None):
                original = self._find_original_run_reference(reference)
                if original is None or original.run is not active._owner:
                    raise ValueError('Original Local physical invocation is still active')
                if operation in ('status', 'cancel', 'lookup-cancellation'):
                    with self._core._borrow_work_operation(active) as borrowed:
                        if borrowed:
                            return self._open_operation_locked(operation, body)
            if operation in ('read', 'wait', 'delivery-attempt'):
                await active.wait_stopped()
            elif operation in ('status', 'cancel', 'lookup-cancellation'):
                await active.wait_stopped()
            else:
                raise ValueError('Original Local physical invocation is still active')
        if operation in ('read', 'delivery-attempt'):
            return await self._open_ordinary_saved(operation, body)
        async with self._operation_lock():
            if operation in ('status', 'wait'):
                self._resume_original_effect_waiting_return(body['ref'])
            with self._core._host_operation():
                return self._open_operation_locked(operation, body)

    async def _open_named_submission(self, body: dict[str, Any]) -> httpx.Response:
        """Wait for the existing physical allowance before observing a name."""
        while True:
            async with self._operation_lock():
                active = next((work for work in self._physical_work if not work.stopped), None)
                if active is None and self._core._host_fuel_phase is None:
                    with self._core._host_operation():
                        return self._open_operation_locked('submit-named-intent', body)
            if active is not None:
                await active.wait_stopped()
            else:
                await asyncio.sleep(0.001)

    async def _open_ordinary_saved(self, operation: str, body: dict[str, Any]) -> httpx.Response:
        # The operation context owns one allowance through all Saved prepare
        # turns. The lock and the original physical reader end before a yield.
        saved: OriginalSavedResultRead | None = None
        try:
            with ExitStack() as allowance:
                async with self._operation_lock():
                    allowance.enter_context(self._core._host_operation())
                    self._resume_original_file_state_return(body['ref'])
                    if operation == 'read':
                        self._finish_stopped_composed_model_state(body['ref'])
                    if self._has_live_original_run_reference(body['ref']):
                        response = self._open_operation_locked(operation, body)
                        if type(response.stream) is OriginalLocalSDKResponseStream:
                            response.stream._bind_operation()
                        return response
                    saved = OriginalSavedResultRead(self)
                    self._saved_result_reads.append(saved)
                if operation == 'delivery-attempt':
                    response = await saved.prepare_lookup_incremental(
                        body['ref'], body['resultName'], body['attemptId'])
                    self._saved_result_reads.remove(saved)
                    return response
                response = await saved.prepare_incremental(body['ref'], body['resultName'],
                                                           body['format'], body['attemptId'])
                if type(response.stream) is OriginalLocalSDKResponseStream:
                    response.stream._bind_operation()
                return response
        except asyncio.CancelledError as primary:
            if saved is not None:
                try:
                    with self._core._host_cleanup():
                        if saved.close():
                            self._saved_result_reads.remove(saved)
                except BaseException as cleanup:
                    raise primary from cleanup
            raise

    async def _open_operation(self, operation: str, body: dict[str, Any]) -> httpx.Response:
        async with self._operation_lock():
            return self._open_operation_locked(operation, body)

    def _open_operation_locked(self, operation: str, body: dict[str, Any]) -> httpx.Response:
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
            elif operation == 'checkpoints':
                raw = self._read_original_checkpoint_page(body)
            elif operation == 'checkpoint-review':
                raw = self._read_original_checkpoint_review(body)
            elif operation == 'resolve':
                raw = self._resolve_original_effect(body['items'])
            elif operation == 'lookup-submission':
                raw = self._lookup_original_submission(body['submissionRef'])
            elif operation == 'lookup-cancellation':
                raw = self._lookup_original_cancellation(body['ref'], body['cancelId'], body['expectedRevision'])
            elif operation == 'cancel':
                raw = self._cancel_original(body)
            elif operation == 'attach':
                raw = self._attach_original_run(body['ref'])
            elif operation == 'submit-named-intent':
                raw, work = self._submit_original_named(body)
            elif operation == 'submit-intent':
                intent = {key: body[key] for key in ('kind', 'input', 'parameters')}
                for key in ('stopBefore', 'readOnly'):
                    if key in body:
                        intent[key] = body[key]
                observation = _object(self._read_original_reference(
                    body['submissionRef'], kind=4, intent=wire_bytes(intent),
                    intent_cid=body['intentCid']), 1048576)  # type: ignore[no-untyped-call]
                identity = observation['intentCid']
                observed = observation['outcome']
                action = observation['action']
                if action == 'conflict':
                    value = {'kind': 'conflict', 'attemptRef': body['attemptRef'],
                        'submissionRef': body['submissionRef'], 'intentCid': identity, 'reason': 'intent'}
                    if not wire.submission_attempt(value, _LOCAL_SELECTION, body):  # type: ignore[no-untyped-call]
                        raise ValueError('Invalid original Local Submission conflict')
                    raw = wire_bytes(value)  # type: ignore[no-untyped-call]
                elif action in ('recorded', 'already_satisfied'):
                    # The saved admission is DATA, not a restored executable
                    # Run. Never prepare, dispatch or issue another Run here.
                    value = {'kind': action,
                        'attemptRef': body['attemptRef'],
                        'outcome': observed}
                    if not wire.submission_attempt(value, _LOCAL_SELECTION, body):  # type: ignore[no-untyped-call]
                        raise ValueError('Invalid original saved Local Submission response')
                    raw = wire_bytes(value)  # type: ignore[no-untyped-call]
                elif action == 'missing':
                    original, admission = self._accept_original(body['submissionRef'],
                        wire_bytes(intent), run_id='python-' + secrets.token_hex(16))  # type: ignore[no-untyped-call]
                    run = None if original is None else original.run
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
                        assert original is not None
                        reference = self._register_original_run_reference(run, admission)
                        original.reference = reference
                        work = OriginalLocalWork(original,
                            on_exit=self._core._finish_work_operation, owner=run)
                else:
                    raise ValueError('Invalid original Local Submission action')
            elif operation in ('status', 'wait'):
                if operation == 'wait' and (body['until'] not in (None, 'terminal')
                        or body['since'] is not None):
                    raise ValueError('Original Local wait condition supplier is unavailable')
                self._resume_original_file_state_return(body['ref'])
                waiting = self._find_original_run_reference(
                    _canonical_bytes(body['ref'], data_keys=True))  # type: ignore[no-untyped-call]
                held = None if waiting is None else self._execution_for_run(waiting.run)
                if (held is not None and held.mock_waiting_confirmed
                        or not self._has_live_original_run_reference(body['ref'])):
                    raw = self._read_original_reference(body['ref'], kind=7)
                    if (operation == 'wait' and body['until'] == 'terminal'
                            and _object(raw, 1048576)['status'] == 'waiting_checkpoint'):
                        raise ValueError('Original Local wait condition supplier is unavailable')
                    if operation == 'wait':
                        self._check_original_wait_state(raw)
                    stream = OriginalLocalResponseStream(self, raw, maximum=1048576)
                    response = httpx.Response(200, headers={'content-type': 'application/json',
                        'content-encoding': 'identity'}, stream=stream)
                    stream._attached = True
                    return response
                original = self._find_original_run_reference(
                    _canonical_bytes(body['ref'], data_keys=True))  # type: ignore[no-untyped-call]
                if original is not None:
                    execution = self._execution_for_run(original.run)
                    if execution is not None and execution.prepared_file and execution.publication is not None:
                        work = next(item for item in self._physical_work if item._invoke is execution)
                        if work.stopped:
                            if any(projection._publication is execution.publication
                                   for projection in self._commit_projections):
                                # The File Run's first-admission Plan has transferred.
                                # Reobserve the original in its managed current frame.
                                projection = self._original_run_projection(original.run)
                                return self._original_run_response(
                                    original.run, projection, wait=operation == 'wait')
                            if operation == 'wait' and self._original_work_failed(work):
                                self._observe_original_file_wait_failure(execution)
                run, _ = self._select_original_run(body['ref'])
                live = any(work._owner is run and not work.stopped for work in self._physical_work)
                publications = [publication for original, publication in self._run_publications if original is run]
                projections = [projection for projection in self._commit_projections
                    if any(projection._publication is publication for publication in publications)]
                if live or not projections:
                    try:
                        return self._unpublished_run_response(run, body['ref'], wait=operation == 'wait')
                    except LocalCoreError as error:
                        # Only a real observed publication may select the
                        # existing complete succeeded-observation path.
                        if error.code != -42 or not projections or run.handle in self._run_state_custody:
                            raise
                projection = self._original_run_projection(run)
                return self._original_run_response(run, projection, wait=operation == 'wait')
            elif operation == 'read':
                run, _ = self._select_original_run(body['ref'])
                projection = self._original_run_projection(run)
                return self._original_sdk_read_response(run, projection,
                    body['resultName'], body['format'], body['attemptId'])
            elif operation == 'delivery-attempt':
                run, _ = self._select_original_run(body['ref'])
                projection = self._original_run_projection(run)
                return self._original_delivery_lookup_response(run, projection,
                    body['resultName'], body['attemptId'])
            else:
                raise ValueError('Original Local operation supplier is unavailable')
            stream = OriginalLocalResponseStream(self, raw,
                maximum=1048576 if operation in ('check', 'checkpoints', 'checkpoint-review') else 8192)
        if work is not None:
            # Keep the accounted response and original invocation even if the
            # awaiting coroutine disappears. Host close observes actual worker
            # stop before touching its Core/File/Store loans; no automatic retry.
            self._physical_work.append(work)
            try:
                self._core._retain_work_operation(work)
            except BaseException:
                # Retain is atomic and never invokes this child. A rejected
                # handoff must not leave an uninvoked worker in Host cleanup.
                self._physical_work.remove(work)
                raise
            work.start()
        with self._core._lock:
            response = httpx.Response(200, headers={'content-type': 'application/json',
                'content-encoding': 'identity'}, stream=stream)
            stream._attached = True
            return response

    def _register_original_run_reference(self, run: _Run, admission: bytes) -> _OriginalRunReference:
        """Hold only a Core-issued reference for routing to its nominal Run loan."""
        with self._core._lock:
            self._runs._run(run)
            if not any(original is run for original in self._run_loans):
                raise ValueError('Foreign original Local Run')
            saved = _object(admission, 4096)
            if not wire.negotiated(saved, 'admission', _LOCAL_SELECTION):  # type: ignore[no-untyped-call]
                raise ValueError('Invalid original Local admission reference')
            raw = _canonical_bytes(saved['ref'], data_keys=True)  # type: ignore[no-untyped-call]
            if len(raw) > 4096:
                raise ValueError('Invalid bounded original Local reference')
            position = len(self._public_run_references)
            for index, original in enumerate(self._public_run_references):
                self._core._owned_input(original.source)
                held = self._core._inputs[original.source.ticket].payload
                if original.run is run:
                    if held != raw:
                        raise ValueError('Original Local Run reference changed')
                    return original
                if held == raw:
                    raise ValueError('Ambiguous original Local Run reference')
                if held > raw and position == len(self._public_run_references):
                    position = index
            # This is the existing vector and original accounted input, not a
            # parallel Map/key copy. Registration and cleanup retain all loans;
            # only this routing vector's internal order changes.
            original = _OriginalRunReference(run, self._copy(raw))
            self._public_run_references.insert(position, original)
            return original

    def _find_original_run_reference(self, captured: bytes) -> _OriginalRunReference | None:
        """Locate an original only; a hit never supplies saved/current authority.

        Keys are private canonical copies of Core-issued ref DATA, not wire
        serialization or authority. They are sealed immutable _Input bytes.
        Supported input
        methods never replace that payload (_read_output requires _Output).
        Registration inserts in order; removal preserves order before those
        input loans retire. No sortedness/permission cache or history scan is
        needed on lookup. Arbitrary private-state mutation is not supported.
        """
        if len(captured) > 4096:
            raise ValueError('Invalid original Local Run reference')
        with self._core._lock:
            low, high = 0, len(self._public_run_references)
            while low < high:
                middle = (low + high) // 2
                original = self._public_run_references[middle]
                self._core._owned_input(original.source)
                held = self._core._inputs[original.source.ticket].payload
                if held == captured:
                    return original
                if held < captured:
                    low = middle + 1
                else:
                    high = middle
            return None

    def _execution_for_run(self, run: _Run, publication: _Output | None = None) -> _OriginalExecution | None:
        for work in self._physical_work:
            original = work._invoke
            if (type(original) is _OriginalExecution and original.host is self
                    and original.run is run and work._owner is run
                    and (publication is None or original.publication is publication)):
                work._nominal()
                return original
        return None

    def _current_execution(self) -> _OriginalExecution | None:
        retained = getattr(self._core, '_host_retained_work', None)
        if retained is None:
            return None
        work = retained[0]
        if work._thread is not _current_thread():
            return None
        original = work._invoke
        if (type(original) is not _OriginalExecution or original.host is not self
                or original.run is not work._owner):
            return None
        return original if self._execution_for_run(original.run) is original else None

    @staticmethod
    def _original_work_failed(work: OriginalLocalWork) -> bool:
        """Physical invocation failure only, never a Run outcome or ACK."""
        work._nominal()
        return (work._exit_error is not None or work._cleanup_error is not None
                or work._future.done() and (work._future.cancelled()
                    or work._future.exception() is not None))

    def _resume_original_file_state_return(self, reference: object) -> None:
        """Finish a previously confirmed File transport before choosing Saved."""
        if not self._run_state_custody:
            return
        routed = self._find_original_run_reference(
            _canonical_bytes(reference, data_keys=True))  # type: ignore[no-untyped-call]
        if routed is None:
            return
        original = self._execution_for_run(routed.run)
        if (original is not None and original.prepared_file and original.state is not None
                and original.state.read_returned):
            if not self._retire_original_execution(original):
                raise LocalProductCleanupPending(self)

    def _finish_stopped_composed_model_state(self, reference: object) -> None:
        """Confirm the original stopped Run before its first Saved Result read."""
        routed = self._find_original_run_reference(
            _canonical_bytes(reference, data_keys=True))  # type: ignore[no-untyped-call]
        if routed is None:
            return
        execution = self._execution_for_run(routed.run)
        if (execution is None or not execution.prepared_model or execution.publication is None
                or execution.physical_start is None
                or not any(source.start is execution.physical_start
                           for source in self._local_csv_captures)):
            return
        work = next(value for value in self._physical_work if value._invoke is execution)
        if not work.stopped or self._original_work_failed(work):
            return
        projection = self._original_run_projection(routed.run)
        self._ensure_original_publication_observation(projection)

        def confirm(raw: bytes) -> None:
            self._core.validate_publication_run(
                projection._publication, routed.run.handle, projection._configuration)
            self._check_original_wait_state(raw)

        self._project_original_sdk_run_state(routed.run, projection, confirm)
        if self._has_live_original_run_reference(reference):
            raise LocalProductCleanupPending(self)

    def _resume_original_effect_waiting_return(self, reference: object) -> None:
        """Return the stopped capture before starting a separate Saved Read."""
        routed = self._find_original_run_reference(
            _canonical_bytes(reference, data_keys=True))  # type: ignore[no-untyped-call]
        if routed is None:
            return
        original = self._execution_for_run(routed.run)
        if (original is not None and original.prepared_effect and original.mock_waiting_confirmed
                and not self._retire_original_execution(original)):
            raise LocalProductCleanupPending(self)

    def _return_original_sdk_state_transport(self, held: _RunStateCustody) -> None:
        if not self._close_sdk_run_state_outputs(held):
            raise LocalProductCleanupPending(self)
        if not self._core.close_input(held.source):
            raise LocalProductCleanupPending(self)
        self._inputs.remove(held.source)
        del self._run_state_custody[held.run.handle]

    def _retire_original_publication_controls(self, original: _OriginalExecution) -> bool:
        if original.publisher is not None:
            if not self._core.close_publisher(original.publisher):
                return False
            self._publishers.remove(original.publisher)
            original.publisher = None
        if original.preflight is not None:
            if not self._core.close_publication_preflight(original.preflight):
                return False
            self._publication_preflights.remove(original.preflight)
            original.preflight = None
        if original.compute is not None:
            for index, (owner, invocation) in enumerate(self._source_free_invocations):
                if owner is original.compute:
                    if not self._core.close_source_free_invocation(invocation):
                        return False
                    self._source_free_invocations.pop(index)
                    break
        return True

    def _retire_original_execution(self, original: _OriginalExecution) -> bool:
        """Return one observed execution's children, not a Run outcome/Owner.

        Initial route cut follows the SAME Core confirmation/reader frame;
        later calls resume only the already selected cleanup originals.
        A pending child keeps this callable and its original inventories; the
        existing explicit Host close can retry them without another execution.
        """
        with self._core._lock:
            if self._execution_for_run(original.run) is not original:
                raise ValueError('Foreign original execution retirement')
            work = next(value for value in self._physical_work if value._invoke is original)
            if original.reference is None:
                raise ValueError('Original execution has no admitted reference')
            if (not work.stopped or self._state_observing
                    or getattr(self._core, '_host_retained_work', None) is not None):
                return False
            publication = original.publication
            held = original.state
            live = any(value is original.reference for value in self._public_run_references)
            if live and (original.run.handle in self._runs._run_restorations
                    or not any(value is original.run.preparation for value in self._prepared_inputs)
                    or any(value is not original.run and value.preparation is original.run.preparation
                           for value in self._runs._runs.values())):
                # Only this Host's fresh private preparation is selected.
                # Shared/explicit and restored originals keep their owners.
                return False
            if (self._uncertain_ticket is not None or self._pending_run_write is not None
                    or self._pending_start_write is not None or self._pending_binding_write is not None):
                return False
            if live and self._original_work_failed(work):
                # A confirmed business observation does not erase a physical
                # invocation/exit/cleanup failure. Its original whole-Host
                # cleanup remains available; this success-only path abstains.
                return False
            waiting = original.prepared_effect and original.mock_waiting_confirmed
            if waiting and (original.mock_waiting is not None or original.mock_review_crypto is not None):
                return False
            if live and not waiting and (
                    publication is None or held is None or held.run is not original.run
                         or held.projection is None or held.projection._publication is not publication
                         or not held.metadata_confirmed
                         or (not held.read_returned if original.prepared_file else held.output is None)
                         or self._run_state_custody.get(original.run.handle) is not held):
                return False
            projection = next((value for value in self._commit_projections
                if value._publication is publication), None) if publication is not None else None
            if (projection is not None and (projection._projecting or projection._outputs)
                    or self._pending_publication_write is not None
                    and self._pending_publication_write._publication is publication):
                return False
            key = None if publication is None else publication.ticket
            evidence = self._sdk_read_evidence.get(key) if key is not None else None
            delivery = self._sdk_deliveries.get(key) if key is not None else None
            if (evidence is not None and evidence._active
                    or delivery is not None and (delivery._active or delivery._payload_reader_borrows)):
                return False
            if live and original.prepared_file:
                # Read return and transport return are separate. A transient
                # transport refusal leaves this same File route and worker.
                assert held is not None and held.read_returned
                with self._core._host_cleanup():
                    self._return_original_sdk_state_transport(held)
                original.state = None
                held = None
            # Only routing is cut. The same Core-issued entry/input stays in
            # this callable through any partial close; Saved readers independently
            # validate current original state. Never forge a restored Run.
            if live and not waiting:
                self._public_run_references.remove(original.reference)
            try:
                with self._core._host_cleanup():
                    if held is not None:
                        self._return_original_sdk_state_transport(held)
                        original.state = None
                    if projection is not None:
                        if not projection.close():
                            raise LocalProductCleanupPending(self)
                        self._commit_projections.remove(projection)
                    if key is not None:
                        if evidence is not None:
                            if not evidence.close():
                                raise LocalProductCleanupPending(self)
                            del self._sdk_read_evidence[key]
                        if delivery is not None:
                            if not delivery.close():
                                raise LocalProductCleanupPending(self)
                            del self._sdk_deliveries[key]
                    if publication is not None:
                        if not self._close_original_publications((publication,)):
                            raise LocalProductCleanupPending(self)
                        original.publication = None
                    if original.results is not None:
                        while original.results:
                            result = original.results[-1]
                            if not self._core.close_result_export(result):
                                raise LocalProductCleanupPending(self)
                            self._result_exports.remove(result)
                            original.results.pop()
                    if original.prepared_model and not self._retire_original_publication_controls(original):
                        raise LocalProductCleanupPending(self)
                    if original.tasks is not None:
                        index = len(original.tasks) - 1
                        while index >= 0:
                            task = original.tasks[index]
                            if self._core._task_loans.get(task.handle) is task:
                                self._retire_original_tasks((task,))
                            if self._core._task_loans.get(task.handle) is not task:
                                if any(value is task for value in self._tasks):
                                    raise ValueError('Changed original task cleanup custody')
                                original.tasks.pop(index)
                            index -= 1
                        if original.tasks:
                            raise LocalProductCleanupPending(self)
                    if not original.prepared_model and not self._retire_original_publication_controls(original):
                        raise LocalProductCleanupPending(self)
                    compute = original.compute
                    if compute is not None:
                        if not self._runs.close_source_free_compute(compute):
                            raise LocalProductCleanupPending(self)
                        self._source_free_computes.remove(compute)
                        original.compute = None
                    if original.physical_start is not None:
                        csv = next((child for child in self._local_csv_captures
                                    if child.start is original.physical_start), None)
                        if csv is not None:
                            if csv.capture is not None:
                                if not self._core.close_original_metadata(csv.capture):
                                    raise LocalProductCleanupPending(self)
                                self._mock_effect_sources.remove(csv.capture)
                                csv.capture = None
                            self._retire_original_csv_workspace(csv)
                            self._local_csv_captures.remove(csv)
                        if original.mock_file_source is not None:
                            source = original.mock_file_source
                            if not self._core.close_original_metadata(source):
                                raise LocalProductCleanupPending(self)
                            self._mock_effect_sources.remove(source)
                            original.mock_file_source = None
                    # The input's existing cleanup callback was associated at
                    # construction. No ticket interval or global-input pruning.
                    index = len(self._inputs) - 1
                    while index >= 0:
                        source = self._inputs[index]
                        physical = self._core._inputs.get(source.ticket)
                        cleanup = None if physical is None else physical.cleanup
                        if (getattr(cleanup, '__self__', None) is original
                                and getattr(cleanup, '__func__', None) is _OriginalExecution.input_cleanup):
                            if not self._core.close_input(source):
                                raise LocalProductCleanupPending(self)
                            self._inputs.pop(index)
                        index -= 1
                    if not self._retire_original_execution_parents(original):
                        raise LocalProductCleanupPending(self)
                    if not self._core.close_input(original.reference.source):
                        raise LocalProductCleanupPending(self)
                    if live and waiting:
                        self._public_run_references.remove(original.reference)
                    self._inputs.remove(original.reference.source)
                    self._physical_work.remove(work)
                    return True
            except BaseException as error:
                if work._cleanup_error is None:
                    work._cleanup_error = error
                raise

    def _retire_original_execution_parents(self, original: _OriginalExecution) -> bool:
        """Same selected ACK chain, never a scan for supposedly obsolete work.

        The success reader selected this callable before child retirement.
        A partial return retains it, including originals whose parents have
        already acknowledged. Do not nominally reclose those retired handles.
        """
        run, prepared = original.run, original.run.preparation
        if original.physical_start is not None:
            start = original.physical_start
            if not self._runs.close_physical_start(start):
                return False
            self._physical_starts.remove(start)
            original.physical_start = None
        if original.start_step is not None:
            step = original.start_step
            if not self._core.close_material(step):
                return False
            self._step_outputs.remove(step)
            self._step_write_attempts.discard(step.ticket)
            original.start_step = None
        if original.file_dispatch_step is not None:
            dispatch = original.file_dispatch_step
            if not self._core.close_material(dispatch):
                return False
            self._step_outputs.remove(dispatch)
            self._step_write_attempts.discard(dispatch.ticket)
            original.file_dispatch_step = None
        binding = next((value for owner, value in self._publication_bindings if owner is run), None)
        if binding is not None:
            if not self._core.close_material(binding):
                return False
            self._publication_bindings.remove((run, binding))
            self._binding_write_attempts.discard(binding.ticket)
        journal = self._admission_observations.get(run.handle)
        if journal is not None:
            if not self._core.close_journal_observation(journal):
                return False
            self._journal_outputs.remove(journal)
            del self._admission_observations[run.handle]
        rows = next((value for owner, value in self._run_rows if owner is run), None)
        if rows is not None:
            if not self._core.close_material(rows):
                return False
            self._row_outputs.remove(rows)
            self._run_rows.remove((run, rows))
            self._row_write_attempts.discard(rows.ticket)
        if any(value is run for value in self._run_loans):
            if not self._runs.close_run(run):
                return False
            self._run_loans.remove(run)
        if any(value is prepared for value in self._prepared_inputs):
            if not self._preparation.close_preparation(prepared):
                return False
            self._prepared_inputs.remove(prepared)
        if original.submission is not None:
            if not self._close_projection(original.submission):
                return False
            original.submission = None
        if original.rows_input is not None:
            if not self._core.close_input(original.rows_input):
                return False
            self._inputs.remove(original.rows_input)
            original.rows_input = None
        for source in (run.input, prepared.input):
            if any(value is source for value in self._inputs):
                if not self._core.close_input(source):
                    return False
                self._inputs.remove(source)
        return True

    def _has_live_original_run_reference(self, reference: object) -> bool:
        """Locate existing live custody only; exact equality is not authority."""
        captured = _canonical_bytes(reference, data_keys=True)  # type: ignore[no-untyped-call]
        original = self._find_original_run_reference(captured)
        # A restored typed Run supplies no live publication/Result custody.
        # Its public reads retain the saved-reader path.
        return original is not None and original.run.handle not in self._runs._run_restorations

    def _select_original_run(self, reference: object) -> tuple[_Run, bytes]:
        """Route a reference, then reobserve its original actual saved admission.

        Exact field equality locates custody only. Current read/publisher and
        full stored-chain checks still precede any public Run state response.
        This performs no preparation, adoption, dispatch or new acceptance.
        """
        self._active()
        captured = _canonical_bytes(reference, data_keys=True)  # type: ignore[no-untyped-call]
        requested = _object(captured, 4096)
        if not wire.valid(requested, 'run_ref'):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original Local Run reference')
        original = self._find_original_run_reference(captured)
        if original is not None:
            held = self._core._inputs[original.source.ticket].payload
            if _object(held, 4096) != requested:
                raise ValueError('Original Local Run reference changed')
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

    def _raise_original_wait_failure(self, run: _Run, *,
                                     projection: OriginalCommitProjection | None = None) -> None:
        """Only after Common's protected Run-read/current observation returns.

        Saved admission/Activation and nominal publication binding alone are
        not read authority. Never select, format or replace this physical cause
        before the existing state supplier completes its actual read checks.
        """
        original = self._execution_for_run(run)
        if original is not None:
            work = next(value for value in self._physical_work if value._invoke is original)
            if not work.stopped:
                raise LocalProductCleanupPending(self)
            loss = original.publication_reply_loss
            observation = (None if projection is None or loss is None else
                self._store_observations.get(projection._publication.ticket))
            resolved_reply_loss = (projection is not None and loss is not None
                and loss[0] is projection and original.publication is projection._publication
                and original.publisher is loss[1] and observation is not None
                and observation._projection is projection and observation._publisher is loss[1]
                and self._pending_publication_write is not projection
                and loss[2].cleanup_store is self._active()._store
                and work._future.exception() is loss[2] and work._cleanup_error is loss[3])
            # Only the published caller supplies this exact projection AFTER
            # complete original index/state readback and protected Run-read.
            # Neither status DATA, action names nor pending disappearance is
            # sufficient. Keep the Future, marker and all loans unchanged.
            if not resolved_reply_loss:
                work._future.result()
            if work._exit_error is not None:
                raise work._exit_error
            if work._cleanup_error is not None and not resolved_reply_loss:
                raise work._cleanup_error

    def _observe_original_file_wait_failure(self, original: _OriginalExecution) -> _NoReturn:
        """Reobserve the same managed Run before selecting its stopped worker failure."""
        start, reference = original.physical_start, original.reference
        if (not original.prepared_file or start is None or start.run is not original.run
                or reference is None or reference.run is not original.run
                or not any(value is start for value in self._physical_starts)):
            raise ValueError('Original managed File Run observation is unavailable')
        self._core._owned_input(reference.source)
        retained = _object(self._core._inputs[reference.source.ticket].payload, 4096)
        self._read_original_reference(retained, kind=5, file_start=start)
        self._raise_original_wait_failure(original.run)
        raise ValueError('Original managed File failure is unavailable')

    def _check_original_wait_state(self, raw: bytes) -> None:
        """Readiness of exact Common DATA, never a physical-stop inference."""
        if not wire.valid_run_wait(_object(raw, 1048576), None):  # type: ignore[no-untyped-call]
            # There is no generic unpublished cleanup wakeup supplier here.
            # Keep its original owners for explicit close, rather than spin or
            # attach a valid status observation as a completed wait response.
            raise ValueError('Original Local wait condition supplier is unavailable')

    def _original_run_response(self, run: _Run,
                               projection: OriginalCommitProjection, *, wait: bool = False) -> httpx.Response:
        """Move original Core state into the existing accounted response stream."""
        installation = self._active()
        configuration = self._configuration
        self._runs._run(run)
        if configuration is None or projection._configuration != configuration.handle:
            raise ValueError('Foreign original Local Run observation')
        streams: list[OriginalLocalResponseStream] = []
        wait_states: list[bytes] = []
        def consume(raw: bytes) -> None:
            # The existing Core guard prevents a different Run's publication
            # being routed under this reference. Its zero is no read grant.
            self._core.validate_publication_run(projection._publication,
                run.handle, configuration.handle)
            if wait:
                if wait_states:
                    raise ValueError('Incomplete original Local Run observation')
                wait_states.append(raw)
            else:
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
            if wait:
                if len(wait_states) != 1:
                    raise ValueError('Incomplete original Local Run observation')
                # The actual Run-read supplier and its post-current checks
                # have returned; nominal publication binding is insufficient.
                self._raise_original_wait_failure(run, projection=projection)
                self._check_original_wait_state(wait_states[0])
                streams.append(OriginalLocalResponseStream(self, wait_states[0]))
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

    def _unpublished_run_response(self, run: _Run, reference: object, *, wait: bool = False) -> httpx.Response:
        """Expose only Common's exact same-Run, durably observed state."""
        streams: list[OriginalLocalResponseStream] = []
        wait_states: list[bytes] = []

        def consume(raw: bytes) -> None:
            if wait:
                wait_states.append(raw)
            else:
                streams.append(OriginalLocalResponseStream(self, raw))

        with self._core._lock:
            try:
                self._observe_unpublished_run_state(run, reference, consume)
                if wait:
                    # Confirmation completed the protected Run-read and
                    # post-current frame before the worker error is selected.
                    self._raise_original_wait_failure(run)
                    self._check_original_wait_state(wait_states[0])
                    streams.append(OriginalLocalResponseStream(self, wait_states[0]))
            except BaseException:
                for stream in streams:
                    if not stream._close():
                        raise LocalProductCleanupPending(self) from None
                raise
            response = httpx.Response(200, headers={'content-type': 'application/json',
                'content-encoding': 'identity'}, stream=streams[0])
            streams[0]._attached = True
            return response

    def _observe_unpublished_run_state(self, run: _Run, reference: object,
                                       consume: Callable[[bytes], None]) -> None:
        """Persist and confirm the original state before a synchronous consumer."""
        installation = self._active()
        configuration, store = self._configuration, installation._store
        if configuration is None or store is None or not configuration.sdk:
            raise ValueError('Original SDK state installation is unavailable')
        self._runs._run(run)
        with self._core._lock, ExitStack() as active:
            if self._state_observing:
                raise ValueError('Original SDK state observation is already active')
            held = self._run_state_custody.get(run.handle)
            if (held is not None and held.projection is None and held.output is not None
                    and self._core._loans.get(held.output.ticket) is None):
                # Only known same-row confirmation can leave this transport
                # retired while its original input still awaits physical close.
                # Finish that exact cleanup before observing any newer fact.
                if not held.metadata_confirmed or not self._close_projection(held.output):
                    raise LocalProductCleanupPending(self)
                held.output = None
                del self._run_state_custody[run.handle]
                held = None
            self._state_observing = True
            active.callback(setattr, self, '_state_observing', False)
            try:
                if held is None:
                    now = self._now()
                    if type(now) is not int or not 0 <= now <= 253402300799999:
                        raise ValueError('Invalid Local physical observation time')
                    seconds, milliseconds = divmod(now, 1000)
                    at = datetime.fromtimestamp(seconds, timezone.utc).replace(
                        microsecond=milliseconds * 1000).isoformat(timespec='milliseconds').replace('+00:00', 'Z')
                    selected = {**_object(wire_bytes(reference), 4096),  # type: ignore[no-untyped-call]
                                'run': run.handle, 'observed_at': at}
                    source = self._copy(wire_bytes(selected))  # type: ignore[no-untyped-call]
                    held = _RunStateCustody(run, None, source)
                    self._run_state_custody[run.handle] = held
                    output = self._reserve(lambda: self._core.reserve_submission_projection(
                        configuration.handle, source, 12, cleanup=lambda: True))
                    held.output = output
                    self._projections.append(output)
                    self._append_sources[output.ticket] = source
                    installation.binding.inspect(lambda current:
                        self._core.produce_unpublished_state(output, current))
                    held.prepared = True
                if held.run is not run or held.projection is not None or not held.prepared or held.output is None:
                    raise LocalProductCleanupPending(self)
                output = held.output
                packets: list[bytes] = []
                if held.write_attempted:
                    # The candidate transport remains original after COMMIT;
                    # a readback never invokes its producer again as preparation.
                    installation.binding.inspect(lambda current: packets.append(
                        self._core.read_unpublished_state_candidate(output, current)))
                    packet = _object(packets[0], 1048576)
                else:
                    installation.binding.inspect(lambda current: packets.append(
                        self._core.read_unpublished_state(output, current)))
                    packet = _object(packets[0], 1048576)
                fields = {'kind', 'key', 'revision', 'body', 'state'}
                if (set(packet) != fields or any(type(packet[key]) is not str for key in fields)
                        or packet['kind'] not in ('retained', 'replace')):
                    raise ValueError('Invalid original unpublished SDK state transport')
                revision = packet['revision']
                if (not revision.isascii() or not revision.isdecimal() or len(revision) > 19
                        or len(revision) > 1 and revision.startswith('0') or int(revision) > 2**63 - 1
                        or packet['kind'] == 'replace' and int(revision) == 2**63 - 1):
                    raise ValueError('Invalid original SDK state metadata generation')
                if packet['kind'] == 'replace' and not held.write_attempted:
                    writes = (ByteWrite(store.namespaced_key('client_submitted_intents', packet['key']),
                        int(revision), packet['body'].encode('utf-8')),)
                    with installation.binding.fenced() as fences:
                        def inspect(reader: Any) -> None:
                            installation.binding.inspect_reader(reader, lambda current:
                                self._core.validate_unpublished_state(output, current))
                        held.write_attempted = True
                        result = store.compare_exchange_many_inspected(writes, fences,
                            inspect=inspect, current=installation.binding._current_observer)
                    if result is None:
                        raise LocalStorageError('Original SDK state metadata conflict; lookup required')
                raw = packet['state'].encode('utf-8')
                def confirm(current: _Output) -> None:
                    self._core.confirm_unpublished_state(output, current)
                    held.metadata_confirmed = True
                    consume(raw)
                installation.binding.inspect(confirm)
                if not self._close_projection(output):
                    raise LocalProductCleanupPending(self)
                held.output = None
                del self._run_state_custody[run.handle]
            except BaseException as error:
                if held is not None:
                    if held.first_failure is None:
                        held.first_failure = error
                    if not held.write_attempted and held.output is not None:
                        try:
                            if self._close_projection(held.output):
                                held.output = None
                                self._run_state_custody.pop(run.handle, None)
                        except BaseException:
                            pass  # Same original carrier retains primary/cleanup custody.
                raise

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
        execution = self._execution_for_run(run, projection._publication)
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
                source = self._copy(wire_bytes({'observed_at': at, 'payloads': payloads}),  # type: ignore[no-untyped-call]
                    execution=execution)
                held = _RunStateCustody(run, projection, source)
                self._run_state_custody[run.handle] = held
                if execution is not None:
                    execution.state = held
                created_output = self._reserve(lambda: self._core.reserve_publication_commit_export(
                    projection._publication, cleanup=lambda: True, maximum=1))
                held.output = created_output

                def prepare_and_emit(_: _Output) -> None:
                    size = self._core.measure_publication_sdk_run_state(
                        created_output, run.handle, source, configuration.handle)
                    body = self._reserve(lambda: self._core.reserve_publication_commit_export(
                        projection._publication, cleanup=lambda: True, maximum=size))
                    held.body_output = body
                    self._core.emit_publication_sdk_run_state(body, created_output, configuration.handle)

                with observation._serialized_facts():
                    installation.binding.inspect(prepare_and_emit)
                held.prepared = True
            if held.run is not run or held.projection is not projection or not held.prepared:
                raise LocalProductCleanupPending(self)
            output, body = held.output, held.body_output
            if output is None or body is None:
                raise LocalProductCleanupPending(self)
            self._core._owned_output(output, 'publication_commit_export')
            raw_packet = self._core.read_publication_commit_material(body)
            if len(raw_packet) != body.limit or len(raw_packet) <= _SDK_RUN_STATE_HEADER.size:
                raise LocalCoreError('sdk_run_state_transport_extent', -33)
            revision, extent, replace, key = _SDK_RUN_STATE_HEADER.unpack_from(raw_packet)
            state_offset = _SDK_RUN_STATE_HEADER.size + extent
            if (extent == 0 or state_offset >= len(raw_packet) or replace not in (0, 1)
                    or revision < 0 or replace and revision == 2**63 - 1
                    or _SDK_RUN_STATE_KEY.fullmatch(key) is None):
                raise ValueError('Invalid original SDK state metadata projection')
            with observation._serialized_facts():
                if replace and not held.write_attempted:
                    writes = (ByteWrite(store.namespaced_key('client_submitted_intents', key.decode('ascii')),
                                        revision, raw_packet[_SDK_RUN_STATE_HEADER.size:state_offset]),)
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
                    del writes
                # Physical COMMIT and candidate fields are not confirmation.
                # This same output rechecks the exact saved successor under a
                # fresh original Store/current frame, including after reply loss.
                raw = raw_packet[state_offset:]
                def confirm_and_consume(_: _Output) -> None:
                    self._core.confirm_publication_sdk_run_state(output, configuration.handle)
                    held.metadata_confirmed = True
                    # The response's original Run guard and bounded transfer
                    # still need this same entered physical journal snapshot.
                    if consume(raw) is not None:
                        raise ValueError('Invalid synchronous original SDK state consumer')
                    observation._validate_facts()
                installation.binding.inspect(confirm_and_consume)
            if execution is not None and execution.prepared_file:
                held.read_returned = True
            retain_state = execution is not None and not self._original_work_failed(
                next(work for work in self._physical_work if work._invoke is execution))
            if not retain_state:
                # A failed physical invocation cannot take success-only child
                # retirement. After the SAME Core confirmation and reader
                # handoff, return this transport as before; keep its Run,
                # publication, original failure and Unknown/cleanup custody.
                # The candidate copies and synchronous Store callback have
                # returned. Drop the transport alias before closing its slot.
                del confirm_and_consume, raw, raw_packet
                if not self._close_sdk_run_state_outputs(held):
                    raise LocalProductCleanupPending(self)
                if not self._core.close_input(held.source):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(held.source)
                del self._run_state_custody[run.handle]
                if execution is not None and execution.state is held:
                    execution.state = None
        if execution is not None and retain_state:
            # The same prepared update and body stay owned through retries.
            # The synchronous candidate/transport aliases must unwind before
            # physical execution retirement closes either original.
            del confirm_and_consume, raw, raw_packet
            self._retire_original_execution(execution)

    def _close_sdk_run_state_outputs(self, held: _RunStateCustody) -> bool:
        if held.body_output is not None:
            if not self._core.close_publication_commit_export(held.body_output):
                return False
            held.body_output = None
        if held.output is not None:
            if not self._core.close_publication_commit_export(held.output):
                return False
            held.output = None
        return True

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
        clock = self._original_sdk_delivery_clock(
            execution=self._execution_for_run(run, projection._publication))
        # Reuse the physical clock projection only; its timestamp has no
        # independent expiry or authorization meaning outside the Core Owner.
        tick = _object(self._core._inputs[clock.ticket].payload, 256)
        request = self._copy(wire_bytes({'result_name': result_name, 'format': format,  # type: ignore[no-untyped-call]
            'attempt_id': attempt_id, 'observed_at': tick['observed_at']}),
            execution=self._execution_for_run(run, projection._publication))
        streams: list[OriginalLocalSDKResponseStream] = []
        try:
            delivery.persist(request, run.handle)
            fact, control_wire = delivery.prepare_live_payload(request, clock)
            control = _SavedRunControl.from_wire(control_wire)
            try:
                reader = OriginalSDKPayloadReader(delivery, request, clock, fact)
            except SDKPayloadReaderCleanupPending as failure:
                # Constructor custody precedes every fallible source callback.
                # Keep it in the Host cleanup inventory before attempting close.
                streams.append(OriginalLocalSDKResponseStream(self, failure.cleanup_reader))
                raise
            stream = OriginalLocalSDKResponseStream(self, reader, live_control=control)
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

    def _original_sdk_delivery_clock(self, *, execution: _OriginalExecution | None = None) -> _Input:
        """Reserve one physical clock input; this renews no grant or attempt."""
        observed_at = self._original_physical_observed_at()
        return self._copy(wire_bytes({'observed_at': observed_at}), execution=execution)  # type: ignore[no-untyped-call]

    def _original_physical_observed_at(self) -> str:
        self._active()
        now = self._now()
        if type(now) is not int or not 0 <= now <= 253402300799999:
            raise ValueError('Invalid Local physical observation time')
        seconds, milliseconds = divmod(now, 1000)
        return datetime.fromtimestamp(seconds, timezone.utc).replace(
            microsecond=milliseconds * 1000).isoformat(timespec='milliseconds').replace('+00:00', 'Z')

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
            'attempt_id': attempt_id, 'observed_at': observed_at}),
            execution=self._execution_for_run(run, projection._publication))
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

    def _copy(self, raw: bytes, *, execution: _OriginalExecution | None = None) -> _Input:
        loan = self._fill_original_input(raw, execution=execution)
        self._core.seal_input(loan)
        return loan

    def _fill_original_input(self, raw: bytes, *, execution: _OriginalExecution | None = None,
                             stopped: Callable[[int], bool] = _original_metadata_stopped) -> _Input:
        original = self._current_execution() if execution is None else execution
        if original is not None and self._execution_for_run(original.run) is not original:
            raise ValueError('Foreign original execution input')
        loan = self._reserve(lambda: self._core.reserve_input(raw,
            cleanup=(lambda: True) if original is None else original.input_cleanup,
            stopped=stopped))
        self._inputs.append(loan)
        for start in range(0, len(raw), 16384):
            self._core.fill_input(loan, start, min(16384, len(raw) - start))
        return loan

    def _capture_project(self, directory: Path, profile: str | None, *,
                         portable_model: bool = False) -> Path:
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
        if portable_model and (locations.profile == 'mock'
                or locations.lock is not None
                or locations.connectors is not None and locations.profile is not None
                or locations.model_tasks is None or locations.mock_catalog is not None
                or locations.mock_data is not None or locations.mock_answers):
            raise ValueError('Original Project has no selected Portable Chat registry')
        base = files._path(directory) if selected is None else selected.path.parent
        originals = {} if selected is None else {selected.path: selected}
        locators: list[tuple[str, str | None, str | None]] = [
            ('connectors', None, locations.connectors),
            ('model_tasks', None, locations.model_tasks),
            ('lock', None, locations.lock),
            ('mock_catalog', None, locations.mock_catalog)]
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
        if locations.mock_data is not None and files._path(base / locations.mock_data) in originals:
            raise ValueError('Original Mock data aliases immutable project metadata')
        files.current()
        if (locations.profile == 'mock' and locations.lock is None
                and locations.connectors is not None
                and locations.mock_catalog is not None and locations.mock_data is not None):
            registry = (None if locations.model_tasks is None
                        else originals[files._path(base / locations.model_tasks)])
            self._project_configuration.prepare_mock_inputs(files, base=base,
                connectors=originals[files._path(base / locations.connectors)],
                catalog=originals[files._path(base / locations.mock_catalog)],
                registry=registry, copy=self._copy, reserve=self._reserve)
        elif portable_model:
            assert locations.model_tasks is not None
            registry_path = files._path(base / locations.model_tasks)
            tasks = self._project_configuration.prepare_model_registry(files,
                base=base, registry=originals[registry_path], copy=self._copy, reserve=self._reserve)
            if len(tasks) != 1:
                raise ValueError('Protected Portable Chat selection requires one original Task')
            task, locator = tasks[0]
            path = files._path(registry_path.parent / locator)
            if path in originals:
                raise ValueError('Original Model Task aliases its Project metadata')
            member = files.read_original(path, max_bytes=65536)
            if member is None:
                raise ValueError('Original selected Model Task is unavailable')
            self._project_members.append(('model_task', task, member))
            self._project_configuration.prepare_model_task(files, index=0, task=member,
                copy=self._copy, copy_raw=self._fill_original_input, reserve=self._reserve)
            files.current()
        if (locations.profile is None and locations.lock is None
                and locations.connectors is not None and not portable_model):
            connectors = originals[files._path(base / locations.connectors)]
            registry = (None if locations.model_tasks is None
                        else originals[files._path(base / locations.model_tasks)])
            self._project_configuration.prepare_local_inputs(
                files, connectors=connectors, registry=registry,
                copy=self._copy, reserve=self._reserve)
        return files._path(base / locations.state_dir)

    def _original_local_project_input(self) -> _Output | None:
        original = self._project_configuration
        if original is None or original._local_inputs is None:
            return None
        if self._project_files is None:
            raise ValueError('Original selected Local Project files are unavailable')
        return original.local_inputs_original(self._project_files)

    def _required_local_project_input(self) -> _Output:
        original = self._original_local_project_input()
        if original is None:
            raise ValueError('Original selected Local Project is unavailable')
        return original

    def _original_project_bootstrap(self) -> _Output | None:
        original = self._project_configuration
        files = self._project_files
        if original is None or files is None:
            raise ValueError('Original project input custody is unavailable')
        if original.prepare().profile == 'mock' and original._mock_inputs is not None:
            return original.mock_bootstrap_input(files)
        self._require_project_execution_environment()
        return None

    def _require_project_execution_environment(self) -> None:
        if self._project_configuration is None:
            return
        if self._project_files is None:
            raise ValueError('Original project input custody is unavailable')
        self._project_files.current()
        locations = self._project_configuration.prepare()
        if self._original_local_project_input() is not None:
            return
        if (locations.profile is not None or self._project_members):
            # These originals still require the selected published/Mock
            # environment constructor. Never execute them against the old
            # source-free bootstrap as a substitute.
            raise ValueError('Original selected project execution environment is not installed')

    def _original_check_environment(self) -> _Environment:
        self._require_project_execution_environment()
        return self._base_check_environment()

    def _base_check_environment(self) -> _Environment:
        installation = self._active()
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

    def _observe_original_intent(self, reference: object, intent: bytes, *,
                                 existing: bool = False) -> tuple[_Output, dict[str, Any]]:
        installation = self._active()
        configuration = self._configuration
        if installation._epoch is None or installation._store is None or configuration is None:
            raise ValueError('Original Local submission suppliers are unavailable')
        # Authentication is performed by the original physical epoch
        # supplier. Its Core projection checks current original scope.
        identity = installation._epoch.identity(reference)
        packet = {'reference': wire_bytes(reference).decode('utf-8'),  # type: ignore[no-untyped-call]
                  'intent': intent.decode('utf-8'), 'now': installation._epoch._observed_clock}
        if existing:
            packet['observe_only'] = True
        source = self._copy(wire_bytes(packet))  # type: ignore[no-untyped-call]
        output = self._reserve(lambda: self._core.reserve_submission_projection(
            configuration.handle, source, 3, cleanup=lambda: True))
        self._projections.append(output)
        self._append_sources[output.ticket] = source
        captured: list[dict[str, Any]] = []
        def observe(current: _Output) -> None:
            captured.append(_object(self._core.produce_and_read_submission_append(output, current), 1048576))
        installation.binding.inspect(observe)
        candidate = captured[0]
        kind = candidate.get('kind')
        fields = ({'kind', 'key', 'body', 'issued_revision', 'issued_body'} if kind == 'append'
                  else {'kind', 'key', 'body', 'revision'} if kind == 'retained' else set())
        if kind == 'append' and (configuration.sdk or 'usage_revision' in candidate):
            fields |= {'usage_revision', 'usage_body'}
        if (not fields or set(candidate) != fields or
                any(type(candidate[name]) is not str for name in fields) or
                candidate['key'] != identity.request_id):
            raise ValueError('Invalid original Core submitted intent projection')
        return output, candidate

    def _original_intent_writes(self, candidate: dict[str, Any]) -> tuple[ByteWrite, ...]:
        store = self._active()._store
        if store is None or candidate['kind'] != 'append':
            raise ValueError('Original Local submitted intent append is unavailable')
        revision = candidate['issued_revision']
        if (not revision.isascii() or not revision.isdecimal() or
                (len(revision) > 1 and revision.startswith('0')) or
                len(revision) > 19 or int(revision) > 2**63 - 1):
            raise ValueError('Invalid original Core issued generation')
        generation = int(revision)
        writes = (
            ByteWrite(store.namespaced_key('client_submitted_intent_custody', 'issued'),
                      generation, candidate['issued_body'].encode('utf-8')),
            ByteWrite(store.namespaced_key('client_submitted_intents', candidate['key']),
                      None, candidate['body'].encode('utf-8')),
        )
        if 'usage_revision' not in candidate:
            if self._configuration is not None and self._configuration.sdk:
                raise ValueError('Missing original Core usage generation')
            return writes
        if candidate['usage_revision'] != revision:
            raise ValueError('Mismatched original Core usage generation')
        return (*writes, ByteWrite(store.namespaced_key('client_submitted_intent_usage', 'retained'),
                                  generation, candidate['usage_body'].encode('utf-8')))

    def _retain_intent(self, reference: object, intent: bytes, *,
                       observe_only: bool = False,
                       preparing: ByteFence | None = None) -> _Output:
        """Prepare or observe the original intent with its existing Core Owner."""
        installation = self._active()
        store = installation._store
        if store is None:
            raise ValueError('Original Local submission suppliers are unavailable')
        with self._core._lock:
            output, candidate = self._observe_original_intent(reference, intent,
                existing=observe_only or preparing is not None)
            if preparing is not None and (candidate['kind'] != 'retained'
                    or store.namespaced_key('client_submitted_intents', candidate['key']) != preparing.key
                    or candidate['revision'] != str(preparing.generation)
                    or candidate['body'].encode('utf-8') != preparing.payload):
                raise LocalStorageError('Original named preparing row changed')
            if candidate['kind'] == 'retained':
                return output
            if observe_only:
                raise LocalStorageError('Original Local submitted intent disappeared after write acknowledgement')
            writes = self._original_intent_writes(candidate)
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    installation.binding.inspect_reader(reader, lambda current:
                        self._core.validate_submission_append(output, current))
                result = store.compare_exchange_many_inspected(
                    writes, fences, inspect=inspect, current=installation.binding._current_observer)
            if result is None:
                raise LocalStorageError('Original Local submitted intent write conflicted; lookup is required')
            return output

    def _project_original_named_submission(self, kind: int, packet: dict[str, Any]) -> tuple[_Output, dict[str, Any]]:
        installation = self._active()
        configuration = self._configuration
        if configuration is None:
            raise ValueError('Original named submission configuration is unavailable')
        source = self._copy(wire_bytes(packet))  # type: ignore[no-untyped-call]
        output = self._reserve(lambda: self._core.reserve_submission_projection(
            configuration.handle, source, kind, cleanup=lambda: True))
        self._projections.append(output)
        self._append_sources[output.ticket] = source
        binding = installation.binding
        captured: list[dict[str, Any]] = []

        def observe(current: _Output) -> None:
            raw = self._core.read_named_submission(output, current, lambda preimage:
                binding._authenticate_submitted_name(current, preimage))
            captured.append(_object(raw, output.limit))

        binding.inspect(observe)
        return output, captured[0]

    def _inspect_named_preparing(self, named: _OriginalNamedSubmission, consume: Callable[[_Output], None]) -> None:
        installation = self._active()
        store = installation._store
        binding = installation.binding
        if store is None:
            raise ValueError('Original named submission Store is unavailable')
        with binding.fenced() as fences:
            store.inspect_namespaces((*fences, named.name, named.preparing),
                inspect=lambda reader: binding.inspect_reader(reader, consume),
                current=binding._current_observer)

    def _commit_original_named_submission(
            self, name: str, reference: object, intent: bytes, intent_cid: str
            ) -> tuple[_OriginalNamedSubmission, _Output, _Output]:
        installation = self._active()
        store, binding = installation._store, installation.binding
        if store is None:
            raise ValueError('Original named submission Store is unavailable')
        original, candidate = self._observe_original_intent(reference, intent)
        intent_writes = self._original_intent_writes(candidate)
        issued_intent, preparing = intent_writes[:2]
        output, name_row = self._project_original_named_submission(_NAMED_SUBMISSION_APPEND_KIND,
            {'name': name, 'append': original.handle, 'intent_cid': intent_cid})
        if (set(name_row) != {'index', 'body', 'issued_revision', 'issued_body'}
                or any(type(value) is not str for value in name_row.values())
                or not _re.fullmatch('[0-9a-f]{64}', name_row['index'])
                or not _re.fullmatch('0|[1-9][0-9]{0,3}', name_row['issued_revision'])
                or not _re.fullmatch('[1-9][0-9]{0,3}', name_row['issued_body'])):
            raise ValueError('Invalid original named submission append projection')
        revision = int(name_row['issued_revision'])
        if not revision < 1024 or int(name_row['issued_body']) != revision + 1:
            raise ValueError('Invalid original named submission issuance')
        name_key = store.namespaced_key('client_submission_names', name_row['index'])
        name_body = name_row['body'].encode('utf-8')
        writes = (*intent_writes,
            ByteWrite(store.namespaced_key('client_submission_name_custody', 'issued'),
                      revision, name_row['issued_body'].encode('ascii')),
            ByteWrite(name_key, None, name_body))
        with binding.fenced() as fences:
            def inspect(reader: _NamespaceReader) -> None:
                def confirm(current: _Output) -> None:
                    self._core.validate_submission_append(original, current)
                    self._core.validate_named_submission_append(output, current)
                binding.inspect_reader(reader, confirm)
            result = store.compare_exchange_many_inspected(
                writes, fences, inspect=inspect, current=binding._current_observer)
        intent_revision = issued_intent.expected_generation
        if intent_revision is None:
            raise LocalStorageError('Original named submission issuance is unavailable')
        steps = (intent_revision + 1, 0)
        if len(intent_writes) == 3:
            steps = (*steps, intent_revision + 1)
        if result != (*steps, revision + 1, 0):
            raise LocalStorageError('Original named submission write requires lookup')
        proof = _OriginalNamedSubmission(ByteFence(name_key, 0, name_body),
            ByteFence(preparing.key, 0, preparing.payload))
        self._inspect_named_preparing(proof, lambda _: None)
        return proof, output, original

    def _submit_original_named(self, body: dict[str, Any]) -> tuple[bytes, OriginalLocalWork | None]:
        """Resolve the durable name before considering the incoming candidate."""
        installation = self._active()
        if installation._epoch is None:
            raise ValueError('Original named submission epoch is unavailable')
        installation._epoch._clock()
        intent = wire_bytes({key: body[key] for key in (
            'kind', 'input', 'parameters', 'stopBefore', 'readOnly') if key in body})  # type: ignore[no-untyped-call]
        name, intent_cid = body['requestName'], body['intentCid']
        facts = {key: body[key] for key in ('requestName', 'intentCid', 'attemptRef')}
        output, selected = self._project_original_named_submission(
            _NAMED_SUBMISSION_KIND, {'name': name, 'intent': intent.decode('utf-8')})
        kind = selected.get('kind')
        if set(selected) != ({'kind', 'reference'} if kind == 'retained' else {'kind'}):
            raise ValueError('Invalid original named submission observation')
        if not self._close_projection(output):
            raise LocalProductCleanupPending(self)
        work = None
        if kind == 'conflict':
            value = {'kind': 'conflict', 'reason': 'intent', **facts}
        elif kind == 'retained':
            reference = _object(selected['reference'].encode('utf-8'), 4096)
            saved = _object(self._read_original_reference(reference, kind=4,
                intent=intent, intent_cid=intent_cid), 1048576)
            if saved.get('action') not in ('recorded', 'already_satisfied'):
                raise LocalStorageError('Original named submission history changed')
            value = {'kind': 'observed', 'outcome': saved['outcome'], **facts}
        elif kind == 'missing':
            reference = body['submissionRef']
            named, name_output, original_output = self._commit_original_named_submission(
                name, reference, intent, intent_cid)
            original, admission = self._accept_original(reference, intent,
                run_id='python-' + secrets.token_hex(16), named=named)
            if not self._close_projection(name_output) or not self._close_projection(original_output):
                raise LocalProductCleanupPending(self)
            saved = _object(admission, 1048576)
            if original is not None:
                outcome = {'kind': 'ready', 'submissionRef': reference,
                           'intentCid': intent_cid, 'admission': saved}
                run = original.run
                original.reference = self._register_original_run_reference(run, admission)
                work = OriginalLocalWork(original,
                    on_exit=self._core._finish_work_operation, owner=run)
            else:
                outcome = saved
            value = {'kind': 'observed', 'outcome': outcome, **facts}
        else:
            raise LocalStorageError('Original named submission history is unavailable')
        if not wire.named_submission_attempt(value, _LOCAL_SELECTION, body):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original Local named submission response')
        return wire_bytes(value), work  # type: ignore[no-untyped-call]

    def _lookup_original_submission(self, reference: object) -> bytes:
        """Observe authenticated saved history without preparing or resending.

        A missing original is unresolved history, never proof of nonexecution.
        Core validates the targeted Submission and its retained Run under
        the same physical snapshot before copying the view.
        """
        return self._read_original_reference(reference, kind=4)

    def _read_original_checkpoint_page(self, request: dict[str, Any]) -> bytes:
        """Return the original Core page only after its physical Read returns."""
        installation = self._active()
        configuration = self._configuration
        if configuration is None or installation._store is None:
            raise ValueError('Original Local checkpoint supplier is unavailable')
        selection = {'after': request['after'], 'limit': request['limit']}
        if 'checkpointId' in request:
            selection['checkpointId'] = request['checkpointId']
        source = self._copy(wire_bytes(selection))  # type: ignore[no-untyped-call]
        output = self._reserve(lambda: self._core.reserve_submission_projection(
            configuration.handle, source, _SAVED_EFFECT_CHECKPOINT_PAGE_KIND,
            cleanup=lambda: True))
        self._projections.append(output)
        self._append_sources[output.ticket] = source
        packet: list[bytes] = []

        def observe(current: _Output) -> None:
            packet.append(self._core.produce_and_read_submission_lookup(output, current))

        installation.binding.inspect(observe)
        if len(packet) != 1:
            raise ValueError('Incomplete original Local checkpoint observation')
        if not self._close_projection(output):
            raise LocalProductCleanupPending(self)
        return packet[0]

    def _close_saved_mock_review_crypto(self) -> bool:
        crypto = self._saved_mock_review_crypto
        if crypto is not None:
            if not crypto.close():
                return False
            self._saved_mock_review_crypto = None
        return True

    def _project_saved_mock_review(self, current: _Output, configuration: _RunConfiguration,
                                  selected: str, stage: int, extent: int, body: bytes,
                                  *, derive_key: bool = False) -> tuple[bytes, bytes | None]:
        source = self._fill_original_input(selected.encode('ascii') + _Struct('<BI').pack(stage, extent) + body)
        output = self._reserve(lambda: self._core.reserve_submission_projection(
            configuration.handle, source, _SAVED_EFFECT_CHECKPOINT_REVIEW_KIND, cleanup=lambda: True))
        self._projections.append(output)
        self._append_sources[output.ticket] = source
        raw = self._core.read_saved_mock_review_part(output, current)
        secret = None
        if derive_key:
            if len(raw) <= 142 or not all(_MOCK_WAITING_CID.fullmatch(raw[i:i + 71]) is not None
                                            for i in (0, 71)):
                raise ValueError('Invalid original Mock Review key coordinates')
            secret = self._active().binding._derive_mock_review_key(current, output, raw[142:])
        if not self._close_projection(output):
            raise LocalProductCleanupPending(self)
        return raw, secret

    def _read_original_checkpoint_review(self, request: dict[str, Any]) -> bytes:
        from ._local_model_crypto import _OriginalModelEvidenceCrypto

        installation = self._active()
        configuration, store, binding = self._configuration, installation._store, installation.binding
        if (configuration is None or store is None or self._saved_mock_review_crypto is not None):
            raise ValueError('Original Mock Checkpoint Review is unavailable')
        selected: str = request['checkpointCid']
        extent = min(request['maxBytes'], 65536)
        packet: list[tuple[str, bytes]] = []

        def observe(current: _Output) -> None:
            reader = binding._observed_reader
            binding._require_observation_frame(self._core, current, reader)
            if reader is None or reader.owner is not store:
                raise ValueError('Foreign original Mock Checkpoint reader')

            with self._mock_review_workspace(16384) as reserve:
                original, key = self._project_saved_mock_review(
                    current, configuration, selected, 0, extent, b'', derive_key=True)
                if key is None:
                    raise ValueError('Invalid original Mock Review key')
                review_cid = original[71:142].decode('ascii')
                crypto = _OriginalModelEvidenceCrypto(
                    self._core, None, policy='builtin-aes-256-gcm',
                    plaintext_limit=min(1048576, store._max_record_bytes))
                self._saved_mock_review_crypto = crypto
                crypto.begin()

                def read_cell(namespace: str, role: str, address: str, cid: str) -> bytes:
                    decoded: list[bytes] = []
                    with self._mock_review_workspace(store._max_record_bytes + 4096) as fund:
                        def authenticate(row: tuple[str, StoredBytes] | None) -> None:
                            if row is None or row[0] != address or row[1].generation != 0:
                                raise LocalStorageError('Original Mock Review holding changed')
                            raw = _local_review_crypto.open_review_evidence(
                                crypto, key, role, cid, row[1].payload,
                                maximum=store._max_record_bytes, reserve=fund)
                            reserve(len(raw) + 256)
                            decoded.append(raw)
                        reader.read(namespace, address, authenticate)
                    return decoded[0]

                stored_review = read_cell('effect_review_projection_custody', 'review_projection',
                                          selected, review_cid)
                reserve(len(stored_review) + 4096)
                review, _ = self._project_saved_mock_review(
                    current, configuration, selected, 3, extent, stored_review)
                if not 0 < len(review) <= extent:
                    raise ValueError('Invalid original Mock Checkpoint Review extent')
                binding._require_observation_frame(self._core, current, reader)
                packet.append((review_cid, review))

        try:
            binding.inspect(observe)
        except BaseException as primary:
            try:
                if not self._close_saved_mock_review_crypto():
                    raise LocalProductCleanupPending(self)
            except BaseException as cleanup:
                raise primary from cleanup
            raise
        if not self._close_saved_mock_review_crypto():
            raise LocalProductCleanupPending(self)
        cid, review = packet[0]
        with self._mock_review_workspace(6 * len(review) + 4096):
            return wire_bytes({'kind': 'review', 'checkpointCid': selected, 'artifactCid': cid,
                'byteLength': len(review), 'contentBase64': b64encode(review).decode('ascii')})  # type: ignore[no-untyped-call,no-any-return]

    def _resolve_original_effect(self, items: list[dict[str, Any]]) -> bytes:
        """Drive each original signed answer through its existing physical owner."""
        results: list[dict[str, Any]] = []
        for item in items:
            if self._effect_attestation_use is not None:
                raise LocalStorageError('Original Local Effect decision requires observation')
            before = (len(self._projections), len(self._mock_review_workspaces),
                      len(self._publications), len(self._publication_preflights), len(self._publishers))
            try:
                original = self._prepare_original_effect_attestation_use(item)
            except LocalCoreError as issue:
                if issue.code != -47:
                    raise
                self._retire_original_effect_answer(before)
                results.append({'checkpointCid': item['checkpointCid'], 'status': 'invalid',
                                'reason': 'AnswerPrincipalMismatch'})
                continue
            self._confirm_original_effect_attestation_use(original)
            self._sign_original_effect_attestation(original)
            result = _object(self._commit_original_effect_decision(original), 65536)
            if not original.decision_confirmed or result.get('checkpointCid') != item['checkpointCid']:
                raise ValueError('Invalid original Local Effect decision return')
            if result.get('decision') == 'approved':
                self._claim_original_effect_resume(original)
                _, rows = self._prepare_original_effect_application(original)
                for _ in range(rows):
                    self._record_original_effect_file_dispatch(original)
                    ack = self._apply_original_effect_file(original)
                    self._record_original_effect_file_response(original, ack)
                    self._settle_original_effect_file_response(original)
                count, _ = self._prepare_original_effect_file_completion(original)
                projection = self._publish_original_effect_results(original, count)
                self._settle_original_effect_publication(original, projection)
            elif result.get('decision') != 'rejected':
                raise ValueError('Invalid original Local Effect decision')
            self._retire_original_effect_answer(before)
            results.append(result)
        return wire_bytes({'results': results})  # type: ignore[no-untyped-call,no-any-return]

    def _retire_original_effect_answer(self, before: tuple[int, int, int, int, int]) -> None:
        projections, workspaces, publications, preflights, publishers = before
        original = self._effect_attestation_use
        with self._core._host_cleanup():
            if not self._close_original_publications(tuple(self._publications[publications:])):
                raise LocalProductCleanupPending(self)
            for publisher in reversed(self._publishers[publishers:]):
                if not self._core.close_publisher(publisher):
                    raise LocalProductCleanupPending(self)
                self._publishers.remove(publisher)
            for preflight in reversed(self._publication_preflights[preflights:]):
                if not self._core.close_publication_preflight(preflight):
                    raise LocalProductCleanupPending(self)
                self._publication_preflights.remove(preflight)
            for output in reversed(self._projections[projections:]):
                if not self._close_projection(output):
                    raise LocalProductCleanupPending(self)
            if original is not None:
                if original.file_writer is not None:
                    raise LocalProductCleanupPending(self)
                original.file_ack = None
                original.file_target = None
                original.file_publication_fences = ()
                if original.file_hold is not None:
                    if not self._core.close_workspace(original.file_hold):
                        raise LocalProductCleanupPending(self)
                    original.file_hold = None
                if original.key is not None:
                    if not original.key.close():
                        raise LocalProductCleanupPending(self)
                    original.key = None
            for workspace in reversed(self._mock_review_workspaces[workspaces:]):
                if not self._close_original_mock_review_workspace(workspace):
                    raise LocalProductCleanupPending(self)
        self._effect_attestation_use = None

    def _prepare_original_effect_resolution_proof(
            self, item: dict[str, Any], *,
            consume_verified: Callable[[_Output, bytes, _Output, _NamespaceReader], None] | None = None) -> _Output:
        """Verify the original reviewed answer with the selected Reviewer key."""
        from ._local_effect_approval_keys import _SelectedEffectApprovalKeys
        from ._local_effect_resolution_input import _with_original_effect_resolution_input
        from ._local_model_crypto import _OriginalEffectSignatureCrypto, _OriginalModelEvidenceCrypto

        installation = self._active()
        configuration, store, binding = self._configuration, installation._store, installation.binding
        if (configuration is None or store is None or self._saved_mock_review_crypto is not None):
            raise ValueError('Original Local Effect resolution is unavailable')
        selected: str = item['checkpointCid']
        resolution: str = item['resolutionWire']
        evidence: str | None = item['approvalEvidenceWire'] or None
        observed_at = self._original_physical_observed_at().encode('ascii')
        extent = 65536
        accepted: list[_Output] = []

        def observe(current: _Output) -> None:
            reader = binding._observed_reader
            if reader is None or reader.owner is not store:
                raise ValueError('Foreign original Effect resolution reader')

            def require_current() -> None:
                binding._require_observation_frame(self._core, current, reader)

            require_current()
            with self._mock_review_workspace(16384) as reserve:
                held = 0

                def fund(total: int) -> None:
                    nonlocal held
                    if total > held:
                        reserve(total - held)
                        held = total

                def select_key() -> tuple[bytes, bytes]:
                    opening, key = self._project_saved_mock_review(
                        current, configuration, selected, 4, extent, b'', derive_key=True)
                    if key is None:
                        raise ValueError('Original Effect Review key is unavailable')
                    return opening, key

                def select_holdings(prefix: bytes) -> bytes:
                    return self._project_saved_mock_review(
                        current, configuration, selected, 1, extent, prefix)[0]

                crypto: _OriginalModelEvidenceCrypto | None = None

                def authenticate(key: bytes, namespace: str, role: str, address: str,
                                 cid: str, consume: Callable[[bytes], None]) -> None:
                    nonlocal crypto
                    require_current()
                    if crypto is None:
                        crypto = _OriginalModelEvidenceCrypto(
                            self._core, None, policy='builtin-aes-256-gcm',
                            plaintext_limit=min(1048576, store._max_record_bytes))
                        self._saved_mock_review_crypto = crypto
                        crypto.begin()
                    original = crypto
                    with self._mock_review_workspace(store._max_record_bytes + 4096) as fund_cell:
                        def open_cell(row: tuple[str, StoredBytes] | None) -> None:
                            if row is None or row[0] != address or row[1].generation != 0:
                                raise LocalStorageError('Original Effect Review holding changed')
                            consume(_local_review_crypto.open_review_evidence(
                                original, key, role, cid, row[1].payload,
                                maximum=store._max_record_bytes, reserve=fund_cell))
                        reader.read(namespace, address, open_cell)
                    require_current()

                answer = resolution.encode('utf-8')
                approval = b'' if evidence is None else evidence.encode('utf-8')

                def prepare(saved: bytes) -> None:
                    require_current()
                    if not self._close_saved_mock_review_crypto():
                        raise LocalProductCleanupPending(self)
                    control = (_Struct('<III').pack(len(saved) + 76, len(answer), len(approval))
                               + observed_at + selected.encode('ascii') + _Struct('<BI').pack(2, extent))
                    with self._mock_review_workspace(
                            len(control) + len(saved) + len(answer) + len(approval) + 65536):
                        source = self._fill_original_input(b''.join((control, saved, answer, approval)))
                        output = self._reserve(lambda: self._core.reserve_submission_projection(
                            configuration.handle, source, _SAVED_EFFECT_RESOLUTION_PROOF_KIND,
                            cleanup=lambda: True))
                        self._projections.append(output)
                        self._append_sources[output.ticket] = source
                        raw = self._core.read_saved_mock_review_part(output, current)
                        proof = _object(raw, 16384)
                        if (set(proof) != {'actor', 'reviewerKey', 'publicKey', 'hostKey', 'hostPublicKey', 'proofs'}
                                or not all(type(proof[key]) is str for key in (
                                    'actor', 'reviewerKey', 'publicKey', 'hostKey', 'hostPublicKey'))
                                or type(proof['proofs']) is not list
                                or len(proof['proofs']) != (1 if evidence is None else 2)
                                or any(type(part) is not list or len(part) != 3
                                       or not all(type(field) is str for field in part)
                                       for part in proof['proofs'])):
                            raise ValueError('Invalid original Effect proof projection')
                        require_current()
                        roles = _SelectedEffectApprovalKeys.admit(
                            reviewer_id=proof['actor'], reviewer_key_id=proof['reviewerKey'],
                            reviewer_public=proof['publicKey'], host_key_id=proof['hostKey'],
                            host_public=proof['hostPublicKey'])
                        signatures = _OriginalEffectSignatureCrypto(self._core, None)
                        self._saved_mock_review_crypto = signatures
                        signatures.begin()
                        for key, preimage, signature in proof['proofs']:
                            if not roles.verify_reviewer(signatures, roles.reviewer_id, key, preimage, signature):
                                raise LocalCoreError('verify_original_effect_resolution_proof', -47)
                            require_current()
                        if not self._close_saved_mock_review_crypto():
                            raise LocalProductCleanupPending(self)
                        if consume_verified is not None:
                            consume_verified(output, raw, current, reader)
                        accepted.append(output)

                _with_original_effect_resolution_input(
                    selected, select_key=select_key, select_holdings=select_holdings,
                    authenticate=authenticate, reserve=fund, consume=prepare)
                require_current()

        try:
            binding.inspect(observe)
        except BaseException as primary:
            try:
                if not self._close_saved_mock_review_crypto():
                    raise LocalProductCleanupPending(self)
            except BaseException as cleanup:
                raise primary from cleanup
            raise
        output, = accepted
        return output

    def _prepare_original_effect_attestation_use(self, item: dict[str, Any]) -> _OriginalEffectAttestationUse:
        installation = self._active()
        configuration, store, binding = self._configuration, installation._store, installation.binding
        if configuration is None or store is None or self._effect_attestation_use is not None:
            raise ValueError('Original Local Effect attestation is unavailable')
        project = self._original_project_bootstrap()
        if project is None:
            raise ValueError('Original Local Effect Project is unavailable')
        environment = self._client_check._project_environment_original(
            project, configuration.handle, local=False, portable=False)
        candidates: list[_OriginalEffectAttestationUse] = []

        def prepare(proof: _Output, proof_wire: bytes, current: _Output, reader: _NamespaceReader) -> None:
            original_key = binding._original_effect_host_key_generation(current, reader)
            body = b''.join((proof.handle.to_bytes(4, 'little'), original_key, proof_wire))
            source = self._fill_original_input(body)
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, _SAVED_EFFECT_ATTESTATION_USE_KIND, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            raw = self._core.read_saved_mock_review_part(output, current)
            packet = _object(raw, 32768)
            keys = {'checkpointCid', 'grantCid', 'grant', 'useCid', 'use', 'preimage', 'keyId', 'publicKey',
                    'sampledAtMs', 'expiresAtMs'}
            if (set(packet) != keys or any(type(packet[k]) is not str for k in keys)
                    or packet['checkpointCid'] != item['checkpointCid']
                    or any(_MOCK_WAITING_CID.fullmatch(packet[k].encode('ascii')) is None
                           for k in ('checkpointCid', 'grantCid', 'useCid', 'preimage'))):
                raise ValueError('Invalid original Local Effect attestation transport')
            raw_times = (packet['sampledAtMs'], packet['expiresAtMs'])
            if any(not t.isascii() or not t.isdecimal() or len(t) > 15 or str(int(t)) != t for t in raw_times):
                raise ValueError('Invalid original Local Effect signing window')
            sampled_at, expires_at = (int(t) for t in raw_times)
            if expires_at <= sampled_at:
                raise ValueError('Invalid original Local Effect signing window')
            checkpoint = packet['checkpointCid']
            writes = (
                ByteWrite(store.namespaced_key('client_local_grant_originals', packet['grantCid']),
                          None, packet['grant'].encode('utf-8')),
                ByteWrite(store.namespaced_key('client_local_signing_use_originals', checkpoint),
                          None, packet['use'].encode('utf-8')),
            )
            original = _OriginalEffectAttestationUse(
                proof, output, original_key, checkpoint, packet['keyId'], packet['publicKey'],
                packet['preimage'], sampled_at, expires_at, writes, resume_environment=environment)
            self._effect_attestation_use = original
            candidates.append(original)

        self._prepare_original_effect_resolution_proof(item, consume_verified=prepare)
        original, = candidates
        return original

    def _confirm_original_effect_attestation_use(self, original: _OriginalEffectAttestationUse) -> None:
        installation = self._active()
        store, binding = installation._store, installation.binding
        if (original is not self._effect_attestation_use or store is None or original.write_attempted):
            raise ValueError('Foreign or attempted original Local Effect attestation')
        original.write_attempted = True

        def inspect(reader: _NamespaceReader) -> None:
            def confirm(current: _Output) -> None:
                if binding._original_effect_host_key_generation(current, reader) != original.key_generation:
                    raise ValueError('Original Local Effect Host key generation changed')
                self._core.validate_saved_effect_resolution(original.offer, current)
            binding.inspect_reader(reader, confirm)

        with binding.fenced() as fences:
            created = store.compare_exchange_many_inspected(
                original.writes, fences, inspect=inspect, current=binding._current_observer)
        if created != (0, 0):
            raise LocalStorageError('Original Local Effect signing use requires observation')
        try:
            with binding.fenced() as fences:
                returned = store.read_exchange_many_inspected(
                    original.writes, fences, inspect=inspect, current=binding._current_observer)
        except BaseException as primary:
            raise _LocalStorageCommitUnknown(store, commit_confirmed=True) from primary
        if returned is None:
            raise _LocalStorageCommitUnknown(store, commit_confirmed=True)
        original.confirmed = True

    def _sign_original_effect_attestation(self, original: _OriginalEffectAttestationUse) -> None:
        from ._local_effect_approval_keys import _canonical_pem_key, _ED25519_PKCS8, _ED25519_SPKI
        from ._local_effect_key_original import _OriginalEffectHostKey
        from ._local_model_crypto import _OriginalEffectSignatureCrypto

        installation = self._active()
        store, binding = installation._store, installation.binding
        root = installation._state
        if (original is not self._effect_attestation_use or not original.confirmed
                or root is None or store is None or original.key is not None
                or original.sign_attempted or self._saved_mock_review_crypto is not None):
            raise ValueError('Original Local Effect signing use is unavailable')
        original.sign_attempted = True
        successors = tuple(ByteFence(write.key, 0, write.payload) for write in original.writes)

        def inspect(reader: _NamespaceReader) -> None:
            def sign(current: _Output) -> None:
                def claimed() -> None:
                    now = self._now()
                    if type(now) is not int or not original.sampled_at <= now < original.expires_at:
                        raise ValueError('Original Local Effect signing use is outside its retained window')
                    binding._require_observation_frame(self._core, current, reader)
                    reader.check_fences(reader, successors)

                self._core.validate_saved_effect_resolution(original.offer, current)
                if binding._original_effect_host_key_generation(current, reader) != original.key_generation:
                    raise ValueError('Original Local Effect Host key generation changed')
                claimed()
                with self._mock_review_workspace(65536):
                    signatures = _OriginalEffectSignatureCrypto(self._core, None)
                    self._saved_mock_review_crypto = signatures
                    signatures.begin()
                    key = _OriginalEffectHostKey(root, original.key_generation, claimed)
                    original.key = key

                    def use(pem: bytes) -> str:
                        secret = _canonical_pem_key(pem, b'PRIVATE KEY', _ED25519_PKCS8)
                        public = _canonical_pem_key(original.public_key.encode('ascii'), b'PUBLIC KEY', _ED25519_SPKI)
                        cid = original.preimage.encode('ascii')
                        result: list[bytes] = []
                        signatures.sign_host_attestation(secret, cid, result.append)
                        signature, = result
                        if not signatures.verify_reviewer(public, cid, signature):
                            raise ValueError('Original Local Effect Host attestation key differs')
                        return b64encode(signature).decode('ascii')

                    original.signature = key.with_private_key(use)
                    if not key.close():
                        raise LocalProductCleanupPending(self)
                    if not self._close_saved_mock_review_crypto():
                        raise LocalProductCleanupPending(self)
            binding.inspect_reader(reader, sign)

        with binding.fenced() as fences:
            store.inspect_namespaces((*fences, *successors), inspect=inspect,
                                     current=binding._current_observer)
        if original.signature is None:
            raise ValueError('Original Local Effect Host did not sign its exact preimage')

    def _commit_original_effect_decision(self, original: _OriginalEffectAttestationUse) -> bytes:
        if (original is not self._effect_attestation_use or not original.confirmed
                or original.signature is None or original.decision_attempted):
            raise ValueError('Original Local Effect decision is unavailable')
        original.decision_attempted = True
        return self._write_original_effect_transition(original, _SAVED_EFFECT_DECISION_KIND,
            original.offer.handle.to_bytes(4, 'little') + original.signature.encode('ascii'))

    def _claim_original_effect_resume(self, original: _OriginalEffectAttestationUse) -> None:
        environment = original.resume_environment
        if (original is not self._effect_attestation_use or not original.decision_confirmed
                or original.decision is None or original.resume_attempted or self._configuration is None
                or environment is None or self._original_project_bootstrap() is None):
            raise ValueError('Original Local Effect resume claim is unavailable')
        original.resume_attempted = True
        control = (_Struct('<II').pack(original.decision.handle, environment.handle)
                   + self._original_physical_observed_at().encode('ascii') + original.preimage.encode('ascii'))
        self._write_original_effect_transition(original, _SAVED_EFFECT_RESUME_KIND, control)

    def _write_original_effect_transition(self, original: _OriginalEffectAttestationUse,
                                          kind: int, control: bytes) -> bytes:
        installation = self._active()
        configuration, store, binding = self._configuration, installation._store, installation.binding
        if (configuration is None or store is None or original.transition_write is not None
                or kind not in (_SAVED_EFFECT_DECISION_KIND, _SAVED_EFFECT_RESUME_KIND)):
            raise ValueError('Original Local Effect transition is unavailable')
        decision = kind == _SAVED_EFFECT_DECISION_KIND
        before = 3 if decision else 4
        successors = tuple(ByteFence(write.key, 0, write.payload) for write in original.writes)
        result: list[bytes] = []
        may_apply: list[bool] = []

        def project(kind: int, packet: bytes, current: _Output) -> tuple[_Output, bytes]:
            source = self._fill_original_input(packet)
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, kind, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            return output, self._core.read_saved_mock_review_part(output, current)

        def assemble(reader: _NamespaceReader) -> None:
            def observe(current: _Output) -> None:
                if not decision and self._original_project_bootstrap() is None:
                    raise ValueError('Original Local Effect Project changed')
                output, header = project(kind, control, current)
                if decision:
                    original.decision = output
                else:
                    original.resume_claim = output
                if len(header) != 226:
                    raise ValueError('Invalid original Local Effect decision header')
                generation, extent, approved = _Struct('<qIB').unpack_from(header)
                run, checkpoint, resolution = header[13:84], header[84:155], header[155:]
                if (generation != before or not 0 < extent <= min(store._max_record_bytes, 262144)
                        or approved not in (0, 1) or checkpoint != original.checkpoint.encode('ascii')
                        or _MOCK_WAITING_CID.fullmatch(run) is None
                        or _MOCK_WAITING_CID.fullmatch(resolution) is None):
                    raise ValueError('Invalid original Local Effect decision coordinates')
                with self._mock_review_workspace(3 * extent + 32768):
                    body = bytearray(extent)
                    for offset in range(0, extent, 8192):
                        count = min(8192, extent - offset)
                        field, data = project(_SAVED_EFFECT_DECISION_FIELD_KIND,
                            _Struct('<III').pack(output.handle, offset, count), current)
                        if len(data) != count:
                            raise ValueError('Invalid original Local Effect decision slice')
                        body[offset:offset + count] = data
                        del data
                        if not self._close_projection(field):
                            raise LocalProductCleanupPending(self)
                    self._core.validate_saved_effect_resolution(output, current)
                    original.transition_write = ByteWrite(
                        store.namespaced_key('client_runs', run.decode('ascii')), generation, bytes(body))
                    may_apply.append(bool(approved))
                    result.append(wire_bytes({'checkpointCid': original.checkpoint, 'status': 'committed',
                        'decision': 'approved' if approved else 'rejected',
                        'resolutionCid': resolution.decode('ascii')}))  # type: ignore[no-untyped-call]
            binding.inspect_reader(reader, observe)

        # Reserve the retained SQLite BLOB separately from the constructor's
        # actual big body transfer. The retained candidate stays on this use.
        with self._mock_review_workspace(262144 + 16384):
            with binding.fenced() as fences:
                store.inspect_namespaces((*fences, *successors), inspect=assemble,
                                         current=binding._current_observer)
            output = original.decision if decision else original.resume_claim
            write = original.transition_write
            if output is None or write is None:
                raise ValueError('Original Local Effect decision is incomplete')

            def current(reader: _NamespaceReader) -> None:
                binding.inspect_reader(reader, lambda observation:
                    self._core.validate_saved_effect_resolution(output, observation))
                if not decision and self._original_project_bootstrap() is None:
                    raise ValueError('Original Local Effect Project changed')

            with binding.fenced() as fences:
                wrote = store.compare_exchange_many_inspected((write,), (*fences, *successors),
                    inspect=current, current=binding._current_observer)
            if wrote != (before + 1,):
                raise LocalStorageError('Original Local Effect decision requires observation')
            try:
                with binding.fenced() as fences:
                    observed = store.read_exchange_many_inspected((write,), (*fences, *successors),
                        inspect=current, current=binding._current_observer)
            except BaseException as primary:
                raise _LocalStorageCommitUnknown(store, commit_confirmed=True) from primary
            if observed is None:
                raise _LocalStorageCommitUnknown(store, commit_confirmed=True)
            original.transition_write = None
            if decision:
                original.decision_confirmed = True
            else:
                allowed, = may_apply
                if not allowed:
                    raise LocalStorageError('Original Local Effect resume requires settlement')
                original.resume_confirmed = True
            raw, = result
            return raw

    def _prepare_original_effect_application(self, original: _OriginalEffectAttestationUse) -> tuple[int, int]:
        configuration = self._configuration
        claim = original.resume_claim
        if (original is not self._effect_attestation_use or not original.resume_confirmed
                or claim is None or configuration is None or original.application_attempted
                or self._original_project_bootstrap() is None):
            raise ValueError('Original Local Effect application is unavailable')
        original.application_attempted = True
        binding = self._active().binding
        control = claim.handle.to_bytes(4, 'little') + self._original_physical_observed_at().encode('ascii')
        result: list[tuple[int, int]] = []

        def prepare(current: _Output) -> None:
            if self._original_project_bootstrap() is None:
                raise ValueError('Original Local Effect Project changed at application')
            source = self._fill_original_input(control)
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, _SAVED_EFFECT_APPLICATION_KIND, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            original.application = output
            raw = self._core.read_saved_mock_review_part(output, current)
            if len(raw) != 8:
                raise ValueError('Invalid original Local Effect application inventory')
            members, rows = _Struct('<II').unpack(raw)
            if not 0 < members <= 128 or not 0 <= rows <= 10000:
                raise ValueError('Invalid original Local Effect application extent')
            if self._original_project_bootstrap() is None:
                raise ValueError('Original Local Effect Project changed at application')
            result.append((members, rows))

        binding.inspect(prepare)
        inventory, = result
        original.file_rows = inventory[1]
        return inventory

    def _record_original_effect_file_dispatch(self, original: _OriginalEffectAttestationUse) -> str:
        installation = self._active()
        binding, store = installation.binding, installation._store
        configuration, files = self._configuration, self._project_files
        index = original.file_completed
        previous = original.application if index == 0 else original.file_terminal
        if (original is not self._effect_attestation_use or configuration is None or files is None
                or previous is None or store is None or original.file_active == index
                or not 0 <= index < original.file_rows or original.file_journal_writes
                or original.file_dispatch_writes):
            raise ValueError('Original Local Effect file dispatch is unavailable')

        def require_target() -> None:
            files.current()
            if index == 0:
                if self._original_project_bootstrap() is None:
                    raise ValueError('Original Local Effect file Project changed')
            else:
                target, predecessor = original.file_target, original.file_ack
                if target is None or predecessor is None or target._latest is not predecessor:
                    raise ValueError('Original Local Effect replacement predecessor is unavailable')
                target._current()

        require_target()
        original.file_active = index
        original.file_dispatch = original.file_dispatch_cid = None
        original.file_apply_attempted = original.file_response_attempted = original.file_terminal_attempted = False
        original.file_operation = original.file_replacement = original.file_response = None
        expected_run, expected_witness = 5 + 3 * index, 3 * index
        guards = tuple(ByteFence(write.key, 0, write.payload) for write in original.writes)
        control = previous.handle.to_bytes(4, 'little') + self._original_physical_observed_at().encode('ascii')
        coordinate: list[str] = []

        def project(kind: int, packet: bytes, observation: _Output) -> tuple[_Output, bytes]:
            source = self._fill_original_input(packet)
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, kind, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            return output, self._core.read_saved_mock_review_part(output, observation)

        def plan(reader: _NamespaceReader) -> None:
            def read(observation: _Output) -> None:
                output, header = project(_SAVED_EFFECT_FILE_DISPATCH_KIND, control, observation)
                original.file_dispatch = output
                if len(header) != 237:
                    raise ValueError('Invalid original Local Effect file dispatch descriptor')
                run_generation, run_extent, witness_generation, witness_extent = _Struct('<qIqI').unpack_from(header)
                run, witness, dispatch = header[24:95], header[95:166], header[166:]
                maximum = min(store._max_record_bytes, 262144)
                if (run_generation != expected_run or witness_generation != expected_witness or not 0 < run_extent <= maximum
                        or not 0 < witness_extent <= 4096
                        or any(_MOCK_WAITING_CID.fullmatch(cid) is None for cid in (run, witness, dispatch))):
                    raise ValueError('Invalid original Local Effect file dispatch coordinates')
                writes: list[ByteWrite] = []
                for field, (table, key, generation, extent) in enumerate((
                        ('client_runs', run, run_generation, run_extent),
                        ('client_effect_custody', witness, witness_generation, witness_extent),
                )):
                    with self._mock_review_workspace(3 * extent + 32768):
                        body = bytearray(extent)
                        for offset in range(0, extent, 8192):
                            count = min(8192, extent - offset)
                            loan, data = project(_SAVED_EFFECT_FILE_DISPATCH_FIELD_KIND,
                                _Struct('<IIII').pack(output.handle, field, offset, count), observation)
                            if len(data) != count:
                                raise ValueError('Invalid original Local Effect file dispatch slice')
                            body[offset:offset + count] = data
                            del data
                            if not self._close_projection(loan):
                                raise LocalProductCleanupPending(self)
                        writes.append(ByteWrite(store.namespaced_key(table, key.decode('ascii')), generation, bytes(body)))
                self._core.validate_saved_effect_resolution(output, observation)
                original.file_dispatch_writes = tuple(writes)
                coordinate.append(dispatch.decode('ascii'))
            binding.inspect_reader(reader, read)

        with self._mock_review_workspace(262144 + 4096 + 32768):
            with binding.fenced() as fences:
                store.inspect_namespaces((*fences, *guards), inspect=plan, current=binding._current_observer)
            output = original.file_dispatch
            writes = original.file_dispatch_writes
            if output is None or len(writes) != 2 or len(coordinate) != 1:
                raise ValueError('Original Local Effect file dispatch is incomplete')

            def inspect(reader: _NamespaceReader) -> None:
                binding.inspect_reader(reader, lambda observation:
                    self._core.validate_saved_effect_resolution(output, observation))
                require_target()

            with binding.fenced() as fences:
                wrote = store.compare_exchange_many_inspected(
                    writes, (*fences, *guards), inspect=inspect, current=binding._current_observer)
            if wrote != (expected_run + 1, expected_witness + 1):
                raise LocalStorageError('Original Local Effect file dispatch requires observation')
            try:
                with binding.fenced() as fences:
                    observed = store.read_exchange_many_inspected(
                        writes, (*fences, *guards), inspect=inspect, current=binding._current_observer)
            except BaseException as primary:
                raise _LocalStorageCommitUnknown(store, commit_confirmed=True) from primary
            if observed is None:
                raise _LocalStorageCommitUnknown(store, commit_confirmed=True)
            original.file_dispatch_writes = ()
            original.file_dispatch_cid, = coordinate
            return original.file_dispatch_cid

    def _apply_original_effect_file(self, original: _OriginalEffectAttestationUse) -> '_MockFileReplacementAck':
        from ._local_mock_file_writer import _MockFileTarget, _MockFileUpdate, _MockFileUpdateUnknown

        installation = self._active()
        binding, store = installation.binding, installation._store
        configuration, project, files = self._configuration, self._project_configuration, self._project_files
        dispatch = original.file_dispatch
        dispatch_cid = original.file_dispatch_cid
        index = original.file_active
        if (original is not self._effect_attestation_use or original.file_apply_attempted
                or index != original.file_completed
                or dispatch is None or dispatch_cid is None or configuration is None
                or store is None or project is None or files is None):
            raise ValueError('Original Local Effect file operation is unavailable')
        original.file_apply_attempted = True
        selected = self._original_project_bootstrap() if index == 0 else None
        predecessor = original.file_ack
        guard_rows = tuple(ByteFence(write.key, 0, write.payload) for write in original.writes)
        ready: list[_MockFileReplacementAck] = []
        control = dispatch.handle.to_bytes(4, 'little') + self._original_physical_observed_at().encode('ascii')

        def transfer(kind: int, packet: bytes, current: _Output) -> tuple[_Output, bytes]:
            source = self._fill_original_input(packet)
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, kind, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            return output, self._core.read_saved_mock_review_part(output, current)

        def inspect(reader: _NamespaceReader) -> None:
            def apply(current: _Output) -> None:
                if index == 0 and (selected is None or self._original_project_bootstrap() is not selected
                        or original.file_target is not None or predecessor is not None):
                    raise ValueError('Original Local Effect file Project changed')
                operation, packet = transfer(_SAVED_EFFECT_FILE_OPERATION_KIND, control, current)
                original.file_operation = operation
                if not 151 <= len(packet) <= 65536:
                    raise ValueError('Invalid original Local Effect operation extent')
                lease, = _Struct('<q').unpack_from(packet)
                expected, version_wire = packet[8:79], packet[79:150]
                identity = packet[150:].decode('utf-8')
                if (expected != dispatch_cid.encode('ascii') or _MOCK_WAITING_CID.fullmatch(version_wire) is None
                        or not identity or '\x00' in identity):
                    raise ValueError('Invalid original Local Effect operation coordinates')
                version = version_wire.decode('ascii')
                def require_current() -> None:
                    now = self._now()
                    if type(now) is not int or not 0 <= now < lease:
                        raise ValueError('Original Local Effect lease expired')
                    files.current()
                    binding._require_observation_frame(self._core, current, reader)
                    self._core.validate_saved_effect_resolution(operation, current)

                require_current()
                target = original.file_target
                if selected is not None:
                    seed = project.acquire_mock_data(files, selected)
                    target = _MockFileTarget(files, seed,
                        max_bytes=min(1048576, store._max_record_bytes), max_operations=128)
                    extent = 4 * target.max_bytes + 32768
                    original.file_hold = self._reserve(lambda: self._core.reserve_workspace(
                        extent, stopped=lambda: True, cleanup=lambda: True))
                    original.file_target = target
                if target is None or target._latest is not predecessor:
                    raise ValueError('Original Local Effect replacement predecessor is unavailable')
                target._current()
                require_current()

                def project_replacement(body: bytes, row: str, expected_version: str) -> bytes:
                    if row != identity or expected_version != version:
                        raise ValueError('Foreign original Local Effect row projection')
                    require_current()
                    output, header = transfer(_SAVED_EFFECT_FILE_REPLACEMENT_KIND,
                        operation.handle.to_bytes(4, 'little') + body, current)
                    original.file_replacement = output
                    if len(header) != 4:
                        raise ValueError('Invalid original Local Effect replacement header')
                    extent, = _Struct('<I').unpack(header)
                    if not 0 < extent <= target.max_bytes:
                        raise ValueError('Invalid original Local Effect replacement extent')
                    projected = bytearray(extent)
                    for offset in range(0, extent, 8192):
                        count = min(8192, extent - offset)
                        field, chunk = transfer(_SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND,
                            _Struct('<IIII').pack(output.handle, 0, offset, count), current)
                        if len(chunk) != count:
                            raise ValueError('Invalid original Local Effect replacement slice')
                        projected[offset:offset + count] = chunk
                        del chunk
                        if not self._close_projection(field):
                            raise LocalProductCleanupPending(self)
                    return bytes(projected)

                writer = target.prepare_update(_MockFileUpdate(
                    dispatch_cid, identity, version, project_replacement, require_current), predecessor=predecessor)
                original.file_writer = writer
                ready.append(writer.apply())
                require_current()
            binding.inspect_reader(reader, apply)

        try:
            with binding.fenced() as fences:
                store.inspect_namespaces((*fences, *guard_rows), inspect=inspect,
                                         current=binding._current_observer)
        except BaseException as primary:
            writer = original.file_writer
            if writer is not None and writer._rename_entered and not isinstance(primary, _MockFileUpdateUnknown):
                raise _MockFileUpdateUnknown('Original Local Effect file needs observation') from primary
            raise
        ack, = ready
        writer = original.file_writer
        if writer is None or writer.ack is not ack or not writer.close():
            raise LocalProductCleanupPending(self)
        original.file_writer = None
        original.file_ack = ack
        return ack

    def _record_original_effect_file_response(
            self, original: _OriginalEffectAttestationUse, ack: '_MockFileReplacementAck') -> str:
        replacement, dispatch = original.file_replacement, original.file_dispatch_cid
        index = original.file_active
        if (original is not self._effect_attestation_use or original.file_response_attempted
                or original.file_writer is not None or original.file_ack is not ack
                or original.file_target is not ack.target or ack.target._latest is not ack
                or index is None or index != original.file_completed
                or replacement is None or dispatch is None or ack.operation.dispatch_cid != dispatch):
            raise ValueError('Original Local Effect file response is unavailable')
        original.file_response_attempted = True
        device, inode = ack.after_stamp[:2]
        control = _Struct('<Iqq').pack(replacement.handle, device, inode) + ack.after_sha256.encode('ascii')
        output, identity = self._record_original_effect_file_journal(original, control,
            kind=_SAVED_EFFECT_FILE_RESPONSE_KIND, field_kind=_SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND,
            rows=(('client_runs', 6 + 3 * index), ('client_effect_custody', 1 + 3 * index),
                  ('client_effect_response_meta', None), ('client_effect_response_bytes', None)),
            physical_body=(dispatch, ack.body))
        original.file_response = output
        return identity

    def _settle_original_effect_file_response(self, original: _OriginalEffectAttestationUse) -> str:
        response = original.file_response
        index = original.file_active
        if (original is not self._effect_attestation_use or original.file_terminal_attempted
                or index is None or index != original.file_completed
                or response is None or original.file_ack is None):
            raise ValueError('Original Local Effect file terminal transition is unavailable')
        original.file_terminal_attempted = True
        output, identity = self._record_original_effect_file_journal(original,
            response.handle.to_bytes(4, 'little'), kind=_SAVED_EFFECT_FILE_TERMINAL_KIND,
            field_kind=_SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND,
            rows=(('client_runs', 7 + 3 * index), ('client_effect_custody', 2 + 3 * index),
                  ('client_effect_row_receipt', None)))
        original.file_terminal = output
        original.file_completed = index + 1
        return identity

    def _record_original_effect_file_journal(
            self, original: _OriginalEffectAttestationUse, control: bytes, *,
            kind: int, field_kind: int, rows: tuple[tuple[str, int | None], ...],
            physical_body: tuple[str, bytes] | None = None,
            after_preparation: Callable[[], None] | None = None) -> tuple[_Output, str]:
        installation = self._active()
        configuration, files = self._configuration, self._project_files
        store, binding = installation._store, installation.binding
        if (original is not self._effect_attestation_use or configuration is None
                or store is None or files is None or original.file_journal_output is not None
                or original.file_journal_writes):
            raise ValueError('Original Local Effect file journal is unavailable')
        guards = tuple(ByteFence(write.key, 0, write.payload) for write in original.writes)
        identity: list[str] = []
        final_publication = kind == _SAVED_EFFECT_FILE_PUBLISHED_KIND
        if final_publication != (after_preparation is not None):
            raise ValueError('Foreign original Local Effect publication handoff')
        selected_header: list[bytes] = []

        def transfer(operation: int, packet: bytes, current: _Output) -> tuple[_Output, bytes]:
            source = self._fill_original_input(packet)
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, operation, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            return output, self._core.read_saved_mock_review_part(output, current)

        def assemble(reader: _NamespaceReader) -> None:
            def prepare(current: _Output) -> None:
                files.current()
                output = original.file_journal_output
                if output is None:
                    output, header = transfer(kind, control, current)
                    original.file_journal_output = output
                    if after_preparation is not None:
                        selected_header.append(header)
                        return
                else:
                    if after_preparation is None or len(selected_header) != 1:
                        raise ValueError('Original Local Effect journal projection already entered')
                    header = selected_header.pop()
                end = 83 * len(rows)
                if len(header) != end + 71 or _MOCK_WAITING_CID.fullmatch(header[end:]) is None:
                    raise ValueError('Invalid original Local Effect file journal descriptor')
                writes: list[ByteWrite] = []
                for field, (table, predecessor) in enumerate(rows):
                    offset = field * 83
                    generation, extent = _Struct('<qI').unpack_from(header, offset)
                    key = header[offset + 12:offset + 83]
                    if (generation != (-1 if predecessor is None else predecessor)
                            or not 0 < extent <= min(262144, store._max_record_bytes)
                            or _MOCK_WAITING_CID.fullmatch(key) is None):
                        raise ValueError('Invalid original Local Effect file journal coordinates')
                    name = key.decode('ascii')
                    if table.startswith('client_effect_response_') and (
                            physical_body is None or name != physical_body[0]):
                        raise ValueError('Foreign original Local Effect file response coordinate')
                    if table == 'client_effect_response_bytes':
                        assert physical_body is not None
                        body = physical_body[1]
                        if len(body) != extent:
                            raise ValueError('Original Local Effect file response extent changed')
                    else:
                        if final_publication:
                            # The outer loan covers the one retained exact
                            # immutable body and its mutable assembly together.
                            fund_journal(2 * extent + 32768)
                        with (nullcontext() if final_publication else
                              self._mock_review_workspace(3 * extent + 32768)):
                            assembled = bytearray(extent)
                            for start in range(0, extent, 8192):
                                count = min(8192, extent - start)
                                loan, chunk = transfer(field_kind,
                                    _Struct('<IIII').pack(output.handle, field, start, count), current)
                                if len(chunk) != count:
                                    raise ValueError('Invalid original Local Effect file journal slice')
                                assembled[start:start + count] = chunk
                                del chunk
                                if not self._close_projection(loan):
                                    raise LocalProductCleanupPending(self)
                            body = bytes(assembled)
                    writes.append(ByteWrite(store.namespaced_key(table, name), predecessor, body))
                self._core.validate_saved_effect_resolution(output, current)
                original.file_journal_writes = tuple(writes)
                identity.append(header[end:].decode('ascii'))
            binding.inspect_reader(reader, prepare)

        retained_reserve = 32768 if final_publication else (
            len(rows) * min(262144, store._max_record_bytes) + 32768)
        with self._mock_review_workspace(retained_reserve) as fund_journal:
            with binding.fenced() as fences:
                store.inspect_namespaces((*fences, *guards), inspect=assemble, current=binding._current_observer)
            if after_preparation is not None:
                after_preparation()
                with binding.fenced() as fences:
                    store.inspect_namespaces((*fences, *guards), inspect=assemble, current=binding._current_observer)
            output, writes = original.file_journal_output, original.file_journal_writes
            if output is None or len(writes) != len(rows) or len(identity) != 1:
                raise ValueError('Original Local Effect file journal candidate was not returned')

            def inspect(reader: _NamespaceReader) -> None:
                files.current()
                binding.inspect_reader(reader, lambda current:
                    self._core.validate_saved_effect_resolution(output, current))

            with binding.fenced() as fences:
                generation = store.compare_exchange_many_inspected(
                    writes, (*fences, *guards), inspect=inspect, current=binding._current_observer)
            if generation != tuple(0 if before is None else before + 1 for _, before in rows):
                raise LocalStorageError('Original Local Effect file journal requires observation')
            try:
                with binding.fenced() as fences:
                    seen = store.read_exchange_many_inspected(
                        writes, (*fences, *guards), inspect=inspect, current=binding._current_observer)
            except BaseException as primary:
                raise _LocalStorageCommitUnknown(store, commit_confirmed=True) from primary
            if seen is None:
                raise _LocalStorageCommitUnknown(store, commit_confirmed=True)
            if (kind == _SAVED_EFFECT_FILE_TERMINAL_KIND and original.file_active is not None
                    and original.file_active + 1 == original.file_rows):
                if original.file_publication_fences:
                    raise ValueError('Original Local Effect publication fences already selected')
                # These same paid successor bodies remain fenced by the
                # original Store until its publication or claim retirement.
                retained = sum(len(write.payload) for write in writes[:2]) + 4096
                loan = self._reserve(lambda: self._core.reserve_workspace(
                    retained, stopped=lambda: True, cleanup=lambda: True))
                self._mock_review_workspaces.append(loan)
                original.file_publication_fences = tuple(
                    ByteFence(write.key, before + 1, write.payload)
                    for write, (_, before) in zip(writes[:2], rows[:2]) if before is not None)
            original.file_journal_output = None
            original.file_journal_writes = ()
            record, = identity
            return output, record

    def _prepare_original_effect_file_completion(self, original: _OriginalEffectAttestationUse) -> tuple[int, str]:
        installation = self._active()
        configuration, files = self._configuration, self._project_files
        store, binding = installation._store, installation.binding
        terminal = original.file_terminal
        if (original is not self._effect_attestation_use or original.file_completion_attempted
                or original.file_completed != original.file_rows or terminal is None
                or configuration is None or files is None or store is None):
            raise ValueError('Original numbered Effect Results are unavailable')
        original.file_completion_attempted = True
        guards = tuple(ByteFence(write.key, 0, write.payload) for write in original.writes)
        result: list[tuple[int, str]] = []

        def observe(reader: _NamespaceReader) -> None:
            def prepare(current: _Output) -> None:
                files.current()
                source = self._fill_original_input(terminal.handle.to_bytes(4, 'little'))
                output = self._reserve(lambda: self._core.reserve_submission_projection(
                    configuration.handle, source, _SAVED_EFFECT_FILE_COMPLETION_KIND, cleanup=lambda: True))
                self._projections.append(output)
                self._append_sources[output.ticket] = source
                original.file_completion = output
                header = self._core.read_saved_mock_review_part(output, current)
                if len(header) != 75 or _MOCK_WAITING_CID.fullmatch(header[4:]) is None:
                    raise ValueError('Invalid original Local Effect completion descriptor')
                count, = _Struct('<I').unpack_from(header)
                if not 0 < count <= 128:
                    raise ValueError('Invalid original Local Effect Result count')
                result.append((count, header[4:].decode('ascii')))
            binding.inspect_reader(reader, prepare)

        with binding.fenced() as fences:
            store.inspect_namespaces((*fences, *guards), inspect=observe, current=binding._current_observer)
        original_result, = result
        return original_result

    def _publish_original_effect_results(
            self, original: _OriginalEffectAttestationUse, count: int) -> OriginalCommitProjection:
        installation = self._active()
        configuration, files = self._configuration, self._project_files
        completion = original.file_completion
        if (original is not self._effect_attestation_use or original.file_publication_attempted
                or completion is None or configuration is None or not configuration.sdk
                or files is None or len(original.file_publication_fences) != 2 or type(count) is not int or not 0 < count <= 128):
            raise ValueError('Original Local Effect publication is unavailable')
        original.file_publication_attempted = True
        binding = installation.binding

        def current(work: Callable[[], _T]) -> _T:
            observed: list[_T] = []
            def inspect(_: _Output) -> None:
                files.current()
                item = work()
                files.current()
                observed.append(item)
            binding.inspect(inspect)
            item, = observed
            return item

        with self._core._lock:
            from ._local_host_binding import _OriginalPublisherPort
            clock = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'now': self._now(),
                'attempt_id': os.urandom(32).hex(),
                'fence_cid': 'sha256:' + hashlib.sha256(os.urandom(32)).hexdigest(),
            }))
            preflight = self._reserve(lambda: self._core.reserve_publication_preflight(
                completion, clock, cleanup=lambda: True))
            self._publication_preflights.append(preflight)
            current(lambda: self._core.prepare_publication_preflight(preflight, configuration.handle))
            if current(lambda: self._core.publication_preflight_result_count(
                    preflight, configuration.handle)) != count:
                raise ValueError('Original Local Effect Result count changed')
            physical = _OriginalPublisherPort(binding)
            envelope = self._copy(b'{}')
            publisher = self._reserve(lambda: self._core.reserve_publisher(
                preflight, envelope, current=physical.current_callback,
                authorize=physical.authorize_callback, cleanup=lambda: True, original=physical))
            self._publishers.append(publisher)
            current(lambda: self._core.install_publisher(publisher, configuration.handle))
            current(lambda: self._core.authorize_publisher(publisher, configuration.handle, stage='request'))
            if not self._core.retire_publication_preflight_output(preflight):
                raise LocalProductCleanupPending(self)
            request = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'results': [], 'max_work': 1000000, 'max_workspace_slots': 100000,
            }))
            publication = self._reserve(lambda: self._core.reserve_publication(
                completion, request, cleanup=lambda: True))
            self._publications.append(publication)
            current(lambda: self._core.prepare_publication(publication, configuration.handle))
            if not self._core.retire_publication_output(publication):
                raise LocalProductCleanupPending(self)
        return self._drive_original_publication(
            publication, preflight, publisher, count, lambda: None,
            require_committed=True, effect_fences=original.file_publication_fences)

    def _settle_original_effect_publication(
            self, original: _OriginalEffectAttestationUse, projection: OriginalCommitProjection) -> str:
        if (original is not self._effect_attestation_use or not original.file_publication_attempted
                or original.file_publication_confirmed or projection._core is not self._core
                or self._store_observations.get(projection._publication.ticket) is None
                or self._pending_publication_write is projection
                or len(original.file_publication_fences) != 2):
            raise ValueError('Original observed Effect publication is unavailable')
        control = (projection._publication.handle.to_bytes(4, 'little')
                   + self._original_physical_observed_at().encode('ascii'))
        def retire_observed_publication() -> None:
            # The state candidate now owns exact Run and index identities.
            # The ordinary payload/commit readers have finished their last use.
            with self._core._host_cleanup():
                if not self._close_original_publications((projection._publication,)):
                    raise LocalProductCleanupPending(self)

        output, identity = self._record_original_effect_file_journal(
            original, control, kind=_SAVED_EFFECT_FILE_PUBLISHED_KIND,
            field_kind=_SAVED_EFFECT_FILE_RESPONSE_FIELD_KIND,
            rows=(('client_runs', original.file_publication_fences[0].generation),
                  ('client_effect_publication', None)),
            after_preparation=retire_observed_publication)
        original.file_publication_confirmed = True
        if not self._close_projection(output):
            raise LocalProductCleanupPending(self)
        return identity

    def _attach_original_run(self, reference: object) -> bytes:
        """Select one saved admission; never recreate an executable Run plan."""
        return self._read_original_reference(reference, kind=5)

    def _lookup_original_cancellation(self, reference: object, cancel_id: str,
                                      expected_revision: int) -> bytes:
        """Observe the original cancellation under the same current SQL reader.

        Core owns the complete Run/cancellation inventories and immutable
        operation result. Python transports that checked view only. Unknown
        history never requests another cancellation or acknowledges a stop.
        Keep both original loans reachable across query, transfer and close
        failure, as for the existing original Submission lookup.
        """
        installation = self._active()
        configuration = self._configuration
        selected = {**_object(wire_bytes(reference), 8192),  # type: ignore[no-untyped-call]
                    'cancelId': cancel_id, 'expectedRevision': expected_revision}
        if (configuration is None or installation._store is None
                or installation._epoch is None
                or not wire.valid(selected, 'cancellation_ref')):  # type: ignore[no-untyped-call]
            raise ValueError('Invalid original Local cancellation reference')
        with self._core._lock:
            source = self._copy(wire_bytes(selected))  # type: ignore[no-untyped-call]
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, 11, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            packets: list[bytes] = []
            installation.binding.inspect(lambda current: packets.append(
                self._core.produce_and_read_submission_lookup(output, current)))
            raw = packets[0]
            if not wire.cancellation_lookup(_object(raw, 8192), selected):  # type: ignore[no-untyped-call]
                raise ValueError('Invalid original Local cancellation lookup response')
            pending = self._pending_cancellation_write
            if (pending is not None and self._pending_cancellation_locator ==
                    _canonical_bytes(selected, data_keys=True)):  # type: ignore[no-untyped-call]
                confirmed: list[bool] = []
                def confirm(current: _Output) -> None:
                    value = self._core.confirm_cancellation_append(pending, current, allow_pending=True)
                    confirmed.append(value)
                    if value:
                        self._dispatch_original_cancellation_stop(pending, reference, current)
                installation.binding.inspect(confirm)
                if confirmed == [True]:
                    if not self._close_projection(pending):
                        raise LocalProductCleanupPending(self)
                    self._pending_cancellation_write = None
                    self._pending_cancellation_locator = None
            if not self._close_projection(output):
                raise LocalProductCleanupPending(self)
            return raw

    def _cancel_original(self, body: dict[str, Any]) -> bytes:
        """Transport one Core cancellation candidate and observe its original.

        The same current SQLite transaction reinspects the complete inventories
        and publication fences before any write. A lost COMMIT reply keeps the
        original projection and prevents another write attempt. Only an explicit
        original lookup can retire that pending carrier; no resend is inferred.
        This returns request admission only, never physical-stop/cleanup facts.
        """
        installation = self._active()
        configuration, store = self._configuration, installation._store
        captured = _object(wire_bytes(body), 8192)  # type: ignore[no-untyped-call]
        if (configuration is None or store is None or installation._epoch is None
                or not wire.valid_body('cancel', captured)  # type: ignore[no-untyped-call]
                or captured['connection'] != _LOCAL_SELECTION):
            raise ValueError('Invalid original Local cancellation operation')
        with self._core._lock:
            if self._pending_cancellation_write is not None:
                raise LocalStorageError('Original cancellation requires lookup; another write is unavailable')
            selection = {**captured['ref'], 'cancelId': captured['cancelId'],
                         'expectedRevision': captured['expectedRevision'],
                         'attemptId': captured['attemptRef']['attemptId']}
            source = self._copy(wire_bytes(selection))  # type: ignore[no-untyped-call]
            output = self._reserve(lambda: self._core.reserve_submission_projection(
                configuration.handle, source, 10, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            packets: list[dict[str, Any]] = []

            def prepare(current: _Output) -> None:
                self._core.produce_cancellation_append(output, current)
                packets.append(_object(self._core.read_cancellation_append(output, current), 1048576))

            installation.binding.inspect(prepare)
            packet = packets[0]
            if (set(packet) != {'response', 'writes'} or type(packet['response']) is not str
                    or type(packet['writes']) is not list or len(packet['writes']) > 4):
                raise ValueError('Invalid original Core cancellation transport')
            cancel_ref = {**captured['ref'], 'cancelId': captured['cancelId'],
                          'expectedRevision': captured['expectedRevision']}
            response = packet['response'].encode('utf-8')
            if not wire.cancellation_attempt(_object(response, 8192), cancel_ref, captured['attemptRef']):  # type: ignore[no-untyped-call]
                raise ValueError('Invalid original Core cancellation response')
            writes: list[ByteWrite] = []
            for row in packet['writes']:
                if (type(row) is not dict or set(row) != {'namespace', 'key', 'revision', 'body'}
                        or row['namespace'] not in ('client_runs', 'client_cancellations',
                                                   'client_cancel_originals', 'client_cancel_custody')
                        or type(row['key']) is not str or type(row['body']) is not str):
                    raise ValueError('Invalid original Core cancellation row transport')
                revision = row['revision']
                if revision is not None and (type(revision) is not str
                        or not revision.isascii() or not revision.isdecimal()
                        or len(revision) > 19 or (len(revision) > 1 and revision.startswith('0'))
                        or int(revision) >= 2**63 - 1):
                    raise ValueError('Invalid original Core cancellation CAS generation')
                payload = row['body'].encode('utf-8')
                if not 0 < len(payload) <= 262144:
                    raise ValueError('Invalid bounded Core cancellation row transport')
                writes.append(ByteWrite(store.namespaced_key(row['namespace'], row['key']),
                                        None if revision is None else int(revision), payload))
            self._pending_cancellation_locator = _canonical_bytes(
                cancel_ref, data_keys=True)  # type: ignore[no-untyped-call]
            self._pending_cancellation_write = output
            if writes:
                with installation.binding.fenced() as fences:
                    def inspect(reader: Any) -> None:
                        installation.binding.inspect_reader(reader, lambda current:
                            self._core.validate_cancellation_append(output, current))
                    result = store.compare_exchange_many_inspected(tuple(writes), fences,
                        inspect=inspect, current=installation.binding._current_observer)
                if result is None:
                    raise LocalStorageError('Original cancellation write conflicted; lookup is required')
            def confirm(current: _Output) -> None:
                self._core.confirm_cancellation_append(output, current)
                self._dispatch_original_cancellation_stop(output, captured['ref'], current)
            installation.binding.inspect(confirm)
            if not self._close_projection(output):
                raise LocalProductCleanupPending(self)
            self._pending_cancellation_write = None
            self._pending_cancellation_locator = None
            return response

    def _dispatch_original_cancellation_stop(self, output: _Output, reference: object,
                                             current: _Output) -> None:
        """Caller holds Core/control custody through the canonical confirmation."""
        selected = self._find_original_run_reference(
            _canonical_bytes(reference, data_keys=True))  # type: ignore[no-untyped-call]
        original = None if selected is None else self._execution_for_run(selected.run)
        if type(original) is _OriginalExecution:
            self._runs._run(original.run)
            if self._core.cancellation_stop_interest(output, original.run.handle, current):
                # Dispatch under the SAME lock as CAS/readback. This consumed
                # request is physical interest, never retained business authority.
                original.stop_interest = output

    def _read_original_reference(self, reference: object, *, kind: int,
                                 intent: bytes | None = None, intent_cid: str | None = None,
                                 file_start: _PhysicalStart | None = None) -> bytes:
        installation = self._active()
        configuration = self._configuration
        if (installation._epoch is None or installation._store is None
                or configuration is None):
            raise ValueError('Original Local submission suppliers are unavailable')
        if file_start is not None and (kind != 5 or file_start.current is not configuration):
            raise ValueError('Foreign original File Run reference observation')
        captured_reference = _object(wire_bytes(reference), 8192)  # type: ignore[no-untyped-call]
        if (intent is None) != (intent_cid is None) or intent is not None and kind != 4:
            raise ValueError('Invalid original Local Submission observation')
        with self._core._lock:
            if kind == 4:
                installation._epoch.identity(captured_reference)
                body = {'reference': wire_bytes(captured_reference).decode('utf-8')}  # type: ignore[no-untyped-call]
                if intent is not None and intent_cid is not None:
                    body['intent'] = intent.decode('utf-8')
                    body['intentCid'] = intent_cid
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
                raw = self._core.produce_and_read_submission_lookup(output, current)
                if file_start is not None:
                    # Run/read and the live File claim use this same Store snapshot.
                    self._runs.observe_sdk_file_start(file_start)
                captured.append(_object(raw, output.limit))
            installation.binding.inspect(observe)
            original = captured[0]
            action = None
            expected_identity = None
            if intent is not None:
                action = original.pop('observation', None)
                expected_identity = original.pop('expectedIntentCid', None)
                if (action not in ('missing', 'conflict', 'recorded', 'already_satisfied')
                        or expected_identity != intent_cid):
                    raise ValueError('Invalid original Local Submission observation')
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
            raw: bytes = wire_bytes(result if intent is None else {
                'action': action, 'intentCid': expected_identity, 'outcome': result})  # type: ignore[no-untyped-call]
            if not self._close_projection(output):
                raise LocalProductCleanupPending(self)
            return raw

    def _reserve_original_result_read(self, reference: object, result_name: str) -> tuple[_Output, str]:
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
                configuration.handle, source,
                _INCREMENTAL_SAVED_RESULT_KIND, cleanup=lambda: True))
            self._projections.append(output)
            self._append_sources[output.ticket] = source
            definition = selected['runDefinitionCid']
            assert isinstance(definition, str)
            return output, definition

    def _read_original_result_projection(self, output: _Output, definition: str,
                                         result_name: str) -> tuple[int, int, _SavedRunControl] | None:
        installation = self._active()
        with self._core._lock:
            packets: list[bytes | None] = []
            installation.binding.inspect(lambda current:
                packets.append(self._core.advance_and_read_saved_result(output, current)))
            if len(packets) != 1:
                raise ValueError('Incomplete original saved Local Result projection')
            packet = packets[0]
            if packet is None:
                return None
            name_digest = hashlib.sha256(result_name.encode('utf-8')).hexdigest().encode('ascii')
            if (len(packet) != _SAVED_RESULT_COORDINATES_BYTES or packet[0] != 2
                    or packet[1] > 7 or packet[2] > 7
                    or packet[3:74] != definition.encode('ascii') or packet[74:138] != name_digest):
                raise ValueError('Foreign original saved Local Result projection')
            control = _SavedRunControl.from_wire(packet[138:])
            return packet[1], packet[2], control

    def _close_projection(self, output: _Output) -> bool:
        """Release only original transport loans after successful cleanup."""
        if not any(original is output for original in self._projections):
            raise ValueError('Foreign original Local projection cleanup')
        original = self._core._loans.get(output.ticket)
        if original is not None and original is not output:
            raise ValueError('Original Local projection loan changed')
        closed = original is None or (self._core.close_submission_append(output) if output.family == 'submission_append'
                  else self._core.close_cancellation_append(output) if output.family == 'cancellation_append'
                  else self._core.close_unpublished_state(output) if output.family == 'run_state_append'
                  else self._core.close_submission_lookup(output) if output.family == 'submission_lookup'
                  else self._core.close_saved_mock_review(output) if output.family in (
                      'saved_mock_review_key', 'saved_mock_review', 'saved_mock_resolution_proof')
                  else self._core.close_submission_projection(output))
        if not closed:
            return False
        source = self._append_sources.get(output.ticket)
        if source is not None:
            if not self._core.close_input(source):
                # The output has closed, but its same input remains reachable
                # through _inputs for retry. No semantic record is deleted.
                return False
            del self._append_sources[output.ticket]
            self._inputs.remove(source)
        self._projections.remove(output)
        return True

    def _prepare_original(self, reference: object, intent: bytes, *,
                          named: _OriginalNamedSubmission | None = None
                          ) -> tuple[_Preparation | _MockRequest, _Output]:
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
            local = self._original_local_project_input()
            portable = installation._portable_chat_output is not None
            observe_project = (self._required_local_project_input if local is not None else
                               self._client_check._portable_project_original if portable else
                               self._original_project_bootstrap)
            project = observe_project() if self._project_configuration is not None else None
            configuration = self._configuration
            checker = None
            if project is not None:
                if configuration is None or configuration.current is None:
                    raise ValueError('Original Project Request configuration is unavailable')
                checker = self._client_check._project_environment_original(
                    project, configuration.handle, local=local is not None, portable=portable)
            if named is None:
                written = self._retain_intent(captured_reference, intent)
                if not self._close_projection(written):
                    raise LocalProductCleanupPending(self)
            observed = (self._retain_intent(captured_reference, intent, observe_only=True)
                        if named is None else self._retain_intent(captured_reference, intent,
                            observe_only=True, preparing=named.preparing))
            if checker is not None:
                assert configuration is not None
                reference_input = self._fill_original_input(observed.handle.to_bytes(4, 'little'))
                request = self._preparation.reserve_mock_request(checker, reference_input, observed)
                self._prepared_inputs.append(request)

                def check_project(current: _Output) -> None:
                    if current is not configuration.current or observe_project() is not project:
                        raise ValueError('Original Request current or Project changed')
                    if local is None and not portable:
                        original, files = self._project_configuration, self._project_files
                        if original is None or files is None or project is None:
                            raise ValueError('Original Mock Request Project is unavailable')
                        original.attach_mock_seed(files, project, configuration.handle,
                            current, fill=self._fill_original_input, reserve=self._reserve)
                        self._preparation.prepare_mock_request(request, current)
                        original.require_mock_seed(files)
                    else:
                        self._preparation.prepare_mock_request(request, current)
                    if observe_project() is not project:
                        raise ValueError('Original Request Project changed')

                if named is None:
                    installation.binding.inspect(check_project)
                else:
                    self._inspect_named_preparing(named, check_project)
                return request, observed
            document = self._copy(intent)
            prepared = self._preparation.reserve(self._base_check_environment(), document, format='submitted')
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
            if named is None:
                installation.binding.inspect(check)
            else:
                self._inspect_named_preparing(named, check)
            if failures:
                if not self._close_projection(observed):
                    raise LocalProductCleanupPending(self)
                raise failures[0]
            return prepared, observed

    def _commit_preparation_failure(self, reference: object, intent: bytes,
                                    failure: LocalPreparationFailure, *,
                                    named: _OriginalNamedSubmission | None = None) -> bytes:
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
        key = store.namespaced_key('client_submitted_intents', candidate['key'])
        if named is not None and (key != named.preparing.key
                or revision != str(named.preparing.generation)
                or candidate['before'].encode('utf-8') != named.preparing.payload):
            raise LocalStorageError('Original named preparing failure predecessor changed')
        with installation.binding.fenced() as fences:
            def inspect(reader: Any) -> None:
                installation.binding.inspect_reader(reader, lambda current:
                    self._core.validate_submission_append(output, current))
            result = store.compare_exchange_many_inspected((ByteWrite(
                key, int(revision), candidate['body'].encode('utf-8')),),
                fences if named is None else (*fences, named.name),
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

    def _accept_original(self, reference: object, intent: bytes, *, run_id: str,
                         named: _OriginalNamedSubmission | None = None
                         ) -> tuple[_OriginalExecution | None, bytes]:
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
                prepared, observed = self._prepare_original(captured_reference, intent, named=named)
            except LocalPreparationFailure as failure:
                return None, (self._commit_preparation_failure(captured_reference, intent, failure)
                              if named is None else self._commit_preparation_failure(
                                  captured_reference, intent, failure, named=named))
            source = self._copy(wire_bytes({'run_id': run_id, 'now': self._now()}))  # type: ignore[no-untyped-call]
            run = self._runs.reserve(configuration, prepared, source)
            self._run_loans.append(run)
            # Inert private custody, not a runnable Work or public reference.
            # The existing inventories retain every partial constructor if a
            # callback fails before this same callable reaches its worker.
            original = _OriginalExecution(self, run, submission=observed)
            decisions: list[str] = []
            def prepare(_: _Output) -> None:
                decisions.append(self._runs.prepare_sdk(run, observed))
            if named is None:
                installation.binding.inspect(prepare)
            else:
                self._inspect_named_preparing(named, prepare)
            if decisions not in (['prepared'], ['prepared_effect'], ['prepared_file'], ['prepared_model']):
                # Preserve the original loans. Restoration is not fresh accept,
                # a new issuance, or an implicit retry of an uncertain COMMIT.
                raise LocalCoreError('original_run_restore_required', -42)
            original.prepared_file = decisions == ['prepared_file']
            original.prepared_model = decisions == ['prepared_model']
            original.prepared_effect = decisions == ['prepared_effect']
            if original.prepared_model != (installation._portable_chat_output is not None):
                raise ValueError('Original Portable Model Run selection does not match its Project')
            if type(prepared) is _MockRequest and not (
                    original.prepared_file or original.prepared_model or original.prepared_effect):
                raise ValueError('Original Project did not select a supported physical Run')
            if original.prepared_effect:
                # The Effect Plan already retained its exact Submission.
                # Its first journal material borrows the same Run clock slot.
                row_input = source
            else:
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
                original.rows_input = row_input
            # Return the copy allowance. Core retains the same preparing
            # record/input for candidate validation in the physical write.
            if not self._core.retire_submission_append_output(observed):
                raise LocalProductCleanupPending(self)
            output = self._reserve(lambda: self._runs.reserve_submitted_rows(
                run, configuration, row_input, cleanup=lambda: True))
            self._row_outputs.append(output)
            self._run_rows.append((run, output))
            installation.binding.inspect(lambda _: self._core.produce_material(output))
            if named is None:
                self._commit_original_run_rows(output)
            else:
                self._commit_original_run_rows(output, named=named)
            # The immutable row Owner/input remain in Core. This consumed
            # transport need not overlap the fresh saved-admission lookup.
            # Neither retirement is the Store or admission acknowledgement.
            if not self._core.retire_material_output(output):
                raise LocalProductCleanupPending(self)
            admission = self._read_original_saved_admission(run, first_admission=True)
            self._pending_run_write = None
            return original, admission

    def _read_original_saved_admission(self, run: _Run, *, first_admission: bool = False) -> bytes:
        """Reobserve the retained original rows without preparation, acceptance or dispatch.

        The earlier transport may be retired; its nominal Plan/rows/input loan
        must still be live. Core checks the original saved admission revision
        against the current actual Run/submission snapshot, not a cached reply.
        This produces neither Store ACK nor a completed Run/Result.
        The original admission response still depends on its Mock seed.
        A later reference lookup only reobserves the admitted Project metadata.
        """
        installation = self._active()
        configuration = self._configuration
        store = installation._store
        if (configuration is None or not configuration.sdk or store is None
                or not any(original is run for original in self._run_loans)):
            raise ValueError('Foreign original saved Local Run')
        with self._core._lock:
            self._runs._run(run)
            local = self._original_local_project_input()
            portable = installation._portable_chat_output
            if type(run.preparation) is _MockRequest:
                files, project = self._project_files, self._project_configuration
                if files is None or project is None:
                    raise ValueError('Original selected Mock Project is unavailable')
            else:
                files = project = None

            def check_project_current() -> None:
                if files is None or project is None:
                    return
                if self._project_files is not files or self._project_configuration is not project:
                    raise ValueError('Original selected Mock Project changed')
                if local is not None:
                    if self._required_local_project_input() is not local:
                        raise ValueError('Original selected Local Project changed')
                if portable is not None:
                    if self._client_check._portable_project_original() is not portable:
                        raise ValueError('Original selected Portable Model changed')
                elif local is not None:
                    return
                elif first_admission:
                    project.require_mock_seed(files)
                else:
                    files.current()

            if run.handle in self._admission_observations:
                raise LocalProductCleanupPending(self)
            held = [output for original, output in self._run_rows if original is run]
            if len(held) != 1 or not any(original is held[0] for original in self._row_outputs):
                raise ValueError('Original saved Local rows are unavailable')
            if first_admission and self._pending_run_write is not held[0]:
                raise ValueError('Original first Local admission is unavailable')
            journal = self._reserve(lambda: self._core.reserve_journal_observation(
                held[0], configuration.handle, store=store,
                current=installation.binding._current_observer, cleanup=lambda: True))
            self._journal_outputs.append(journal)
            self._admission_observations[run.handle] = journal
            admission: list[bytes] = []
            with installation.binding.fenced() as fences:
                def inspect(reader: Any) -> None:
                    def consume(_: _Output) -> None:
                        check_project_current()
                        self._core.inspect_journal_observation(journal, reader)
                        wire = self._core.read_journal_admission(journal, reader)
                        check_project_current()
                        admission.append(wire)
                    installation.binding.inspect_reader(reader, consume)
                store.inspect_namespaces(fences, inspect=inspect, current=installation.binding._current_observer)
            if not self._core.close_journal_observation(journal):
                raise LocalProductCleanupPending(self)
            self._journal_outputs.remove(journal)
            del self._admission_observations[run.handle]
            if first_admission:
                # The old snapshot cannot vouch for the seed after the
                # physical Read returns. Keep the pending original Run write
                # until this last fence passes and the caller can attach it.
                check_project_current()
            return admission[0]

    def _commit_original_run_rows(self, output: _Output, *,
                                  named: _OriginalNamedSubmission | None = None) -> None:
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
                      'issued_revision', 'issued_body', 'preparing_revision'}
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
            for field in ('issued_revision', 'preparing_revision'):
                revision = candidate[field]
                if (not revision.isascii() or not revision.isdecimal() or
                        (len(revision) > 1 and revision.startswith('0')) or
                        len(revision) > 19 or int(revision) >= 2**63 - 1):
                    raise ValueError('Invalid original Core Run row generation')
            # Core revalidates the exact preparation bytes, revision and
            # selected original before any candidate write.
            submitted_key = store.namespaced_key('client_submitted_intents', candidate['submission_key'])
            if named is not None and (submitted_key != named.preparing.key
                    or candidate['preparing_revision'] != str(named.preparing.generation)
                    or candidate['preparing'].encode('utf-8') != named.preparing.payload):
                raise LocalStorageError('Original named preparing Run predecessor changed')
            writes = (
                ByteWrite(store.namespaced_key('client_run_custody', 'issued'),
                          int(candidate['issued_revision']), candidate['issued_body'].encode('utf-8')),
                ByteWrite(store.namespaced_key('client_runs', candidate['run_key']),
                          None, candidate['run'].encode('utf-8')),
                ByteWrite(submitted_key, int(candidate['preparing_revision']),
                          candidate['submitted'].encode('utf-8')),
            ) + tuple(material_writes) + (locator_write,)
            try:
                with installation.binding.fenced() as fences:
                    def inspect(reader: Any) -> None:
                        installation.binding.inspect_reader(reader, lambda current:
                            self._core.validate_submitted_run_rows(output, current))
                    self._row_write_attempts.add(output.ticket)
                    self._pending_run_write = output
                    result = store.compare_exchange_many_inspected(
                        writes, fences if named is None else (*fences, named.name),
                        inspect=inspect, current=installation.binding._current_observer)
            except LocalRunDefinitionConflict as failure:
                # The original write is rolled back. Only this typed SQLite
                # collision may select the same Definition in a fresh Read.
                self._inspect_original_run_definition_collision(output, candidate['run'], failure)
                raise
            if result is None:
                raise LocalStorageError('Original Local Run write conflicted; lookup is required')

    def _inspect_original_run_definition_collision(self, output: _Output, run: str,
                                                   failure: LocalRunDefinitionConflict) -> None:
        binding = self._active().binding
        outcomes: list[int] = []
        try:
            wire = _object(run.encode('utf-8'), 262144).get('run_definition')
            if type(wire) is not str:
                return
            definition = _object(wire.encode('utf-8'), 131072)
            if definition.get('run_definition_cid') != failure.definition:
                return
            binding.inspect(lambda current: outcomes.append(
                self._core.inspect_submitted_run_definition_collision(output, current)))
        except Exception as observation:
            # Keep the actual physical collision primary when owner readback
            # cannot classify it. No second append is selected.
            raise failure from observation
        [outcome] = outcomes
        if outcome == 1:
            raise LocalStorageError('Original Local Run is present; lookup is required') from failure
        if outcome == 3:
            raise LocalCoreError('inspect_run_definition_collision', -45) from failure
        raise LocalCoreError('inspect_run_definition_collision', -35) from failure

    def _close_original_mock_review_read(self, output: _Output) -> bool:
        loans = self._mock_review_reads[output]
        while loans:
            loan = loans[-1]
            if type(loan) is _Output:
                if not self._core.close_original_metadata(loan):
                    return False
            else:
                if not self._core.close_input(loan):
                    return False
                self._inputs.remove(loan)
            loans.pop()
        del self._mock_review_reads[output]
        return True

    def _with_original_mock_review_part(
        self, start: _PhysicalStart, current: _Output, part: int, consume: Callable[[bytes], None],
    ) -> None:
        """Borrow one Review part within the original adopted Store transaction."""
        installation = self._active()
        project, files = self._project_configuration, self._project_files
        binding = installation.binding
        with self._core._lock:
            original = self._current_execution()
            if (project is None or files is None or original is None
                    or original.physical_start is not start or start.current is not self._configuration
                    or type(part) is not int or not 0 <= part <= 6 or not callable(consume)):
                raise ValueError('Foreign original Mock Review')
            self._runs._start(start)
            binding._require_observation_frame(self._core, current, binding._observed_reader)
            descriptor = start.handle.to_bytes(4, 'little') + part.to_bytes(4, 'little')
            consuming = False

            def open_part(kind: int, extent: int | None = None, offset: int = 0) -> _Output:
                raw = descriptor if extent is None else descriptor + _Struct('<II').pack(offset, extent)
                packet = self._fill_original_input(raw)
                output = self._reserve(lambda: self._core.reserve_original_metadata(
                    packet, kind, cleanup=lambda: not consuming, review_bytes=extent))
                self._mock_review_reads[output] = [packet, output]
                return output

            project.require_mock_seed(files)
            if part in (4, 5):
                output = open_part(_MOCK_EFFECT_REVIEW_READ_KIND)
                consuming = True
                try:
                    raw = self._core.read_original_mock_review_part(output, current)
                    project.require_mock_seed(files)
                    if part == 4:
                        raw = binding._derive_mock_review_key(current, output, raw)
                    if consume(raw) is not None:
                        raise ValueError('Invalid original Mock Review consumer')
                    project.require_mock_seed(files)
                    binding._require_observation_frame(self._core, current, binding._observed_reader)
                finally:
                    raw = b''
                    consuming = False
                if not self._close_original_mock_review_read(output):
                    raise LocalProductCleanupPending(self)
                return

            quote = open_part(_MOCK_EFFECT_REVIEW_EXTENT_KIND)
            measured = self._core.read_original_mock_review_part(quote, current)
            extent = int.from_bytes(measured, 'little')
            if len(measured) != 4 or not 0 < extent <= 1048576:
                raise ValueError('Invalid original Mock Review part extent')
            if not self._close_original_mock_review_read(quote):
                raise LocalProductCleanupPending(self)
            with self._mock_review_workspace(2 * extent + 16384):
                assembled = bytearray(extent)
                for offset in range(0, extent, 8192):
                    size = min(8192, extent - offset)
                    output = open_part(_MOCK_EFFECT_REVIEW_READ_KIND, size, offset)
                    consuming = True
                    try:
                        raw = self._core.read_original_mock_review_part(output, current)
                        if len(raw) != size:
                            raise ValueError('Original Mock Review slice changed extent')
                        assembled[offset:offset + size] = raw
                        project.require_mock_seed(files)
                    finally:
                        raw = b''
                        consuming = False
                    if not self._close_original_mock_review_read(output):
                        raise LocalProductCleanupPending(self)
                if consume(bytes(assembled)) is not None:
                    raise ValueError('Invalid original Mock Review consumer')
                del assembled
                project.require_mock_seed(files)
                binding._require_observation_frame(self._core, current, binding._observed_reader)

    def _close_original_mock_review_workspace(self, workspace: _Workspace) -> bool:
        if not any(held is workspace for held in self._mock_review_workspaces):
            raise ValueError('Foreign original Mock Review workspace')
        if not self._core.close_workspace(workspace):
            return False
        self._mock_review_workspaces.remove(workspace)
        return True

    @_contextmanager
    def _mock_review_workspace(self, initial: int) -> _Iterator[Callable[[int], None]]:
        """Keep each temporary quote on its same Host until actual cleanup."""
        workspaces: list[_Workspace] = []

        def reserve(extent: int) -> None:
            original = self._reserve(lambda: self._core.reserve_workspace(
                extent, stopped=lambda: True, cleanup=lambda: True))
            self._mock_review_workspaces.append(original)
            workspaces.append(original)

        reserve(initial)
        # A refused Store/codec or interrupted physical return leaves the
        # exact named token on this Host until its worker/Read has unwound.
        yield reserve
        with self._core._host_cleanup():
            for original in reversed(workspaces):
                if not self._close_original_mock_review_workspace(original):
                    raise LocalProductCleanupPending(self)

    def _read_original_mock_review_coordinates(self, start: _PhysicalStart,
                                               current: _Output) -> tuple[bytes, dict[str, str]]:
        coordinates: list[dict[str, str]] = []
        key: list[bytes] = []

        def admit(raw: bytes) -> None:
            matched = _MOCK_REVIEW_COORDINATE_WIRE.fullmatch(raw)
            if matched is None:
                raise ValueError('Invalid original Mock Review holding coordinates')
            coordinates.append({field: cid.decode('ascii') for field, cid in
                                zip(_MOCK_REVIEW_COORDINATE_FIELDS, matched.groups(), strict=True)})

        self._with_original_mock_review_part(start, current, 5, admit)
        self._with_original_mock_review_part(start, current, 4, key.append)
        if len(key[0]) != 32:
            raise ValueError('Invalid original Mock Review key')
        return key[0], coordinates[0]

    def _persist_original_mock_review(self, start: _PhysicalStart,
                                      crypto: _OriginalModelEvidenceCrypto) -> None:
        """Stage the five protected holdings in one original, insert-only transaction."""
        installation = self._active()
        store, binding = installation._store, installation.binding
        with self._core._lock:
            execution = self._current_execution()
            files = self._project_files
            if store is None or files is None or execution is None or execution.physical_start is not start:
                raise ValueError('Foreign original Mock Review Store')
            if execution.mock_review_write_attempted:
                raise LocalStorageError('Original Mock Review requires observation after a write attempt')
            # The coordinate object, derived key and fixed physical controls
            # stay on this reservation until the transaction returns.
            with self._mock_review_workspace(16384):
                current: _Output
                key: bytes
                coordinates: dict[str, str]

                def inspect(reader: _NamespaceReader, stage: Callable[[], None]) -> None:
                    def observe(value: _Output) -> None:
                        nonlocal current, key, coordinates
                        current = value
                        key, coordinates = self._read_original_mock_review_coordinates(start, value)
                        try:
                            stage()
                        finally:
                            del key, coordinates
                    binding.inspect_reader(reader, observe)

                def project(ordinal: int, consume: Callable[[ByteWrite], None]) -> None:
                    part, namespace, role, address, identity = _MOCK_REVIEW_HOLDINGS[ordinal]

                    def encrypt(raw: bytes) -> None:
                        with self._mock_review_workspace(4096) as reserve:
                            envelope = _local_review_crypto.seal_review_evidence(
                                crypto, key, role, coordinates[identity], raw,
                                maximum=store._max_record_bytes, reserve=reserve)
                            # SQLite takes its own BLOB copy during binding.
                            reserve(len(envelope) + 4096)
                            consume(ByteWrite(store.namespaced_key(namespace, coordinates[address]),
                                              None, envelope))
                            del envelope

                    self._with_original_mock_review_part(start, current, part, encrypt)

                def before_commit() -> None:
                    # Reobserve the claimed Run and the current Project through
                    # the same actual Store reader after the last staged row.
                    self._with_original_mock_review_part(start, current, 5, lambda _: None)

                def physical_current() -> None:
                    binding._current_observer()
                    files.current()

                with binding.fenced() as fences:
                    execution.mock_review_write_attempted = True
                    generations = store.compare_exchange_journal_projected_inspected(
                        len(_MOCK_REVIEW_HOLDINGS), project, fences,
                        inspect=inspect, current=physical_current, before_commit=before_commit)
                if generations != (0,) * len(_MOCK_REVIEW_HOLDINGS):
                    raise LocalStorageError('Original Mock Review holding write was not confirmed')

    def _confirm_original_mock_review(self, start: _PhysicalStart, current: _Output,
                                      crypto: _OriginalModelEvidenceCrypto) -> None:
        """Authenticate the five actually stored bodies in the same protected Store reader."""
        installation = self._active()
        store, binding = installation._store, installation.binding
        with self._core._lock:
            execution = self._current_execution()
            if (store is None or execution is None or execution.physical_start is not start
                    or not execution.mock_review_write_attempted):
                raise ValueError('Foreign original Mock Review observation')
            with self._mock_review_workspace(16384):
                reader = binding._observed_reader
                binding._require_observation_frame(self._core, current, reader)
                if reader is None:
                    raise ValueError('Missing original Mock Review reader')
                key, coordinates = self._read_original_mock_review_coordinates(start, current)
                for part, namespace, role, address, identity in _MOCK_REVIEW_HOLDINGS:
                    holding, cid = coordinates[address], coordinates[identity]
                    # The corrupted-row copy limit is set by the existing
                    # Store. Keep authenticated Checkpoint backing until
                    # Core consumes it after the expected-wire loan closes.
                    with self._mock_review_workspace(store._max_record_bytes + 4096) as reserve:
                        actual_wire: bytes | None = None

                        def compare(expected: bytes) -> None:
                            def authenticate(row: tuple[str, StoredBytes] | None) -> None:
                                nonlocal actual_wire
                                if row is None or row[0] != holding or row[1].generation != 0:
                                    raise LocalStorageError('Original Mock Review holding changed')
                                actual = _local_review_crypto.open_review_evidence(
                                    crypto, key, role, cid, row[1].payload,
                                    maximum=store._max_record_bytes, reserve=reserve)
                                if actual != expected:
                                    raise LocalStorageError('Original Mock Review plaintext changed')
                                if role == 'checkpoint':
                                    actual_wire = actual

                            reader.read(namespace, holding, authenticate)

                        self._with_original_mock_review_part(start, current, part, compare)
                        if role == 'checkpoint':
                            if actual_wire is None:
                                raise LocalStorageError('Original Mock Checkpoint readback is incomplete')
                            self._confirm_original_mock_checkpoint(start, current, actual_wire, reserve)
                            actual_wire = None

    def _confirm_original_mock_checkpoint(self, start: _PhysicalStart, current: _Output,
                                          actual_wire: bytes,
                                          reserve: Callable[[int], None]) -> None:
        """Forward authenticated physical bytes within their original Read."""
        binding = self._active().binding
        original = self._current_execution()
        files = self._project_files
        if (original is None or original.physical_start is not start or files is None
                or start.current is not self._configuration
                or type(actual_wire) is not bytes or not 0 < len(actual_wire) <= 65536):
            raise ValueError('Foreign original persisted Mock Checkpoint')
        self._runs._start(start)
        reader = binding._observed_reader
        binding._require_observation_frame(self._core, current, reader)
        files.current()
        reserve(len(actual_wire) + 4096)
        packet = self._fill_original_input(start.handle.to_bytes(4, 'little') + actual_wire)
        output = self._reserve(lambda: self._core.reserve_original_metadata(
            packet, _MOCK_EFFECT_CHECKPOINT_CONFIRM_KIND, cleanup=lambda: True))
        self._mock_review_reads[output] = [packet, output]
        self._core.confirm_original_mock_checkpoint(output, current)
        files.current()
        binding._require_observation_frame(self._core, current, reader)
        if not self._close_original_mock_review_read(output):
            raise LocalProductCleanupPending(self)

    def _retire_original_mock_review_crypto(self, execution: _OriginalExecution,
                                          crypto: _OriginalModelEvidenceCrypto) -> None:
        if execution.mock_review_crypto is not crypto:
            raise ValueError('Foreign original Mock Review crypto owner')
        if not crypto.close():
            raise LocalProductCleanupPending(self)
        execution.mock_review_crypto = None

    def _save_original_mock_waiting(self, start: _PhysicalStart,
                                    crypto: _OriginalModelEvidenceCrypto,
                                    sources: list[_Output]) -> None:
        """Commit the original Checkpoint, empty Ledger witness and Run successor."""
        installation = self._active()
        store, binding = installation._store, installation.binding
        with self._core._lock:
            execution, files = self._current_execution(), self._project_files
            if (store is None or files is None or execution is None
                    or execution.physical_start is not start
                    or start.current is not self._configuration):
                raise ValueError('Foreign original Mock waiting transaction')
            self._runs._start(start)
            if execution.mock_waiting_write_attempted:
                raise LocalStorageError('Original Mock waiting transaction requires observation')
            if not execution.mock_review_write_attempted:
                raise ValueError('Original Mock Review must be saved before waiting')

            with self._mock_review_workspace(16384):
                current: _Output
                output: _Output
                bodies: list[bytearray]
                keys: tuple[str, str, str]
                sizes: tuple[int, int, int]
                revision: int

                def inspect(reader: _NamespaceReader, stage: Callable[[], None]) -> None:
                    def observe(value: _Output) -> None:
                        nonlocal current, output, bodies, keys, sizes, revision
                        current = value
                        self._confirm_original_mock_review(start, current, crypto)
                        # All five originals returned under this writer's
                        # observation. The remaining CAS compares only typed
                        # Journal rows and no longer borrows AEAD.
                        self._retire_original_mock_review_crypto(execution, crypto)
                        binding._require_observation_frame(self._core, current, reader)
                        files.current()
                        at = self._original_physical_observed_at().encode('ascii')
                        source = self._fill_original_input(start.handle.to_bytes(4, 'little') + at)
                        output = self._reserve(lambda: self._core.reserve_original_metadata(
                            source, _MOCK_EFFECT_WAITING_KIND, cleanup=lambda: True))
                        self._mock_review_reads[output] = [source, output]
                        self._core.prepare_original_mock_waiting(output, current)
                        with self._core._host_cleanup():
                            for source_output in reversed(sources):
                                if not any(source_output is held for held in self._mock_effect_sources):
                                    raise ValueError('Foreign original Mock Effect Source during stop')
                                if not self._core.close_original_metadata(source_output):
                                    raise LocalProductCleanupPending(self)
                                self._mock_effect_sources.remove(source_output)
                        binding._require_observation_frame(self._core, current, reader)
                        files.current()
                        raw = self._core.read_original_mock_waiting(output, current)
                        header = _MOCK_WAITING_HEADER.size
                        data = _MOCK_WAITING_BODY_OFFSET
                        if len(raw) != data:
                            raise ValueError('Incomplete original Mock waiting projection')
                        revision, run_size, witness_size, locator_size = _MOCK_WAITING_HEADER.unpack_from(raw)
                        sizes = run_size, witness_size, locator_size
                        run_key, locator_key = raw[header:header + 71], raw[header + 71:data]
                        if (not 0 <= revision < 2**63 - 1 or data + sum(sizes) > 1048576
                                or any(size <= 0 or size > store._max_record_bytes for size in sizes)
                                or _MOCK_WAITING_CID.fullmatch(run_key) is None
                                or _MOCK_WAITING_LOCATOR.fullmatch(locator_key) is None):
                            raise ValueError('Invalid original Mock waiting projection')
                        run, locator = run_key.decode('ascii'), locator_key.decode('ascii')
                        keys = run, run, locator
                        execution.mock_waiting = output
                        with self._mock_review_workspace(sum(sizes) + 2 * 8192 + 4096):
                            bodies = []
                            try:
                                for ordinal, extent in enumerate(sizes):
                                    body = bytearray(extent)
                                    for offset in range(0, extent, 8192):
                                        size = min(8192, extent - offset)
                                        packet = self._fill_original_input(
                                            _Struct('<IIII').pack(output.handle, ordinal, offset, size))
                                        field = self._reserve(lambda: self._core.reserve_original_metadata(
                                            packet, _MOCK_EFFECT_WAITING_FIELD_KIND, cleanup=lambda: True,
                                            review_bytes=size))
                                        self._mock_review_reads[field] = [packet, field]
                                        chunk = self._core.read_original_mock_waiting_field(field, current)
                                        if len(chunk) != size:
                                            raise ValueError('Invalid original Mock waiting field extent')
                                        body[offset:offset + size] = chunk
                                        del chunk
                                        if not self._close_original_mock_review_read(field):
                                            raise LocalProductCleanupPending(self)
                                    bodies.append(body)
                                del body
                                stage()
                            finally:
                                bodies.clear()
                    binding.inspect_reader(reader, observe)

                def project(ordinal: int, consume: Callable[[ByteWrite], None]) -> None:
                    size = sizes[ordinal]
                    # The original Core loan holds the plan. SQLite owns a
                    # separate BLOB binding while the exact body slice is live.
                    with self._mock_review_workspace(2 * size + 4096):
                        consume(ByteWrite(store.namespaced_key(_MOCK_WAITING_TABLES[ordinal],
                                                              keys[ordinal]),
                                          revision if ordinal == 0 else None,
                                          bytes(bodies[ordinal])))

                def before_commit() -> None:
                    self._core.confirm_original_mock_waiting(output, current)

                def physical_current() -> None:
                    binding._current_observer()
                    files.current()

                with binding.fenced() as fences:
                    execution.mock_waiting_write_attempted = True
                    generations = store.compare_exchange_journal_projected_inspected(
                        len(_MOCK_WAITING_TABLES), project, fences,
                        inspect=inspect, current=physical_current, before_commit=before_commit)
                if generations is None or generations != (revision + 1, 0, 0):
                    raise LocalStorageError('Original Mock waiting transaction was refused')
            self._observe_original_mock_waiting(start)

    def _observe_original_mock_waiting(self, start: _PhysicalStart) -> None:
        """Confirm the same waiting candidate under a new protected Read."""
        binding = self._active().binding
        with self._core._lock:
            execution, files = self._current_execution(), self._project_files
            if (execution is None or execution.physical_start is not start or files is None
                    or start.current is not self._configuration
                    or execution.mock_waiting is None or not execution.mock_waiting_write_attempted):
                raise ValueError('Original Mock waiting candidate is unavailable')
            self._runs._start(start)
            output = execution.mock_waiting
            loans = self._mock_review_reads.get(output)
            if not loans:
                raise ValueError('Original Mock waiting candidate custody is unavailable')

            def inspect(current: _Output) -> None:
                files.current()
                self._core.confirm_original_mock_waiting(output, current)
                files.current()

            # After an acknowledged output close, only the input return may
            # remain. The prior original readback has already completed.
            if loans[-1] is output:
                binding.inspect(inspect)
            if not self._close_original_mock_review_read(output):
                raise LocalProductCleanupPending(self)
            execution.mock_waiting = None
            execution.mock_waiting_confirmed = True

    def _reserve_mock_effect_source(self, start: _PhysicalStart, occurrence: int) -> _Output:
        """Retain the exact physical start and checked occurrence before Source work."""
        with self._core._lock:
            self._active()
            if (not any(start is original for original in self._physical_starts)
                    or type(start.run.preparation) is not _MockRequest
                    or type(occurrence) is not int or not 0 <= occurrence < 2**31):
                raise ValueError('Foreign original Mock Effect Source selection')
            at = self._original_physical_observed_at().encode('ascii')
            source = self._fill_original_input(
                start.handle.to_bytes(4, 'little') + occurrence.to_bytes(4, 'little') + at)
            output = self._reserve(lambda: self._core.reserve_original_metadata(
                source, _MOCK_EFFECT_SOURCE_CAPTURE_KIND, cleanup=_original_metadata_cleanup))
            self._mock_effect_sources.append(output)
            return output

    def _advance_mock_effect_source(self, output: _Output) -> bool:
        """Observe the original Project files around this Source step."""
        with self._core._lock:
            installation = self._active()
            files = self._project_files
            project = self._project_configuration
            if (files is None or project is None
                    or not any(output is original for original in self._mock_effect_sources)):
                raise ValueError('Foreign original Mock Effect Source capture')
            completed: list[bool] = []

            def advance(current: _Output) -> None:
                project.require_mock_seed(files)
                done = self._core.advance_mock_effect_step(output, current, operation='advance_mock_effect_source')
                project.require_mock_seed(files)
                completed.append(done)

            installation.binding.inspect(advance)
            return completed[0]

    def _capture_original_local_csv(self, start: _PhysicalStart) -> None:
        """Collect the exact claimed Whole Source on its existing Core Read."""
        with self._core._lock:
            self._check_original_stop_interest(start.run)
            installation = self._active()
            files = self._project_files
            project = self._required_local_project_input()
            if (files is None or start.current is not self._configuration
                    or not any(original is start for original in self._physical_starts)):
                raise ValueError('Foreign original Local CSV start')
            self._runs._start(start)
            if any(original.start is start for original in self._local_csv_captures):
                raise ValueError('Original Local CSV Source is already retained')
            custody = _OriginalCsvCapture(start)
            self._local_csv_captures.append(custody)
            at = self._original_physical_observed_at().encode('ascii')
            packet = self._fill_original_input(
                start.handle.to_bytes(4, 'little') + b'\0' * 4 + at, stopped=custody.stop)
            source = self._reserve(lambda: self._core.reserve_original_metadata(
                packet, _MOCK_EFFECT_SOURCE_CAPTURE_KIND, cleanup=_original_metadata_cleanup))
            self._mock_effect_sources.append(source)
            custody.capture = source

            def supply(current: _Output) -> None:
                def require_current() -> None:
                    if self._required_local_project_input() is not project:
                        raise ValueError('Original Local CSV Project changed')
                    self._core.validate_host_current(current)

                if self._core.advance_mock_effect_step(source, current, operation='open_local_csv_source'):
                    raise ValueError('Original Local CSV did not offer a physical Read')

                def open_child(raw: bytes, kind: int) -> tuple[_Input, _Output]:
                    child_input = self._fill_original_input(raw)
                    child = self._reserve(lambda: self._core.reserve_original_metadata(
                        child_input, kind, cleanup=_original_metadata_cleanup))
                    self._mock_effect_sources.append(child)
                    return child_input, child

                def close_child(child_input: _Input, child: _Output) -> None:
                    if not self._core.close_original_metadata(child):
                        raise LocalProductCleanupPending(self)
                    self._mock_effect_sources.remove(child)
                    if not self._core.close_input(child_input):
                        raise LocalProductCleanupPending(self)
                    self._inputs.remove(child_input)

                offer_input, offer = open_child(source.handle.to_bytes(4, 'little'), _LOCAL_CSV_OFFER_KIND)
                self._core.produce_original_metadata(offer, current=current)
                offer_wire = self._core.read_original_metadata(offer)
                # Reader controls and path/JSON conversion can overlap the
                # original offer. Fund them before building the reader.
                custody.metadata_workspace = self._reserve(lambda: self._core.reserve_workspace(
                    65536 + 8 * len(offer_wire), stopped=lambda: custody.stopped,
                    cleanup=lambda: custody.stopped))
                custody.transfer = _LocalCsvTransfer(files, offer.handle, offer_wire,
                    max_path_bytes=4096, max_depth=128, require_current=require_current)
                transfer = custody.transfer
                del offer_wire

                def respond(raw: bytes, primary: BaseException | None = None) -> None:
                    response_input, response = open_child(raw, _LOCAL_CSV_RESPONSE_KIND)
                    try:
                        self._core.produce_original_metadata(response, current=current)
                    except LocalCoreError as decision:
                        if primary is None or decision.code not in (-23, -36):
                            raise
                    close_child(response_input, response)

                try:
                    extent, extent_packet = transfer.extent_packet()
                except BaseException as failure:
                    try:
                        respond(transfer.failure_packet(), failure)
                    except BaseException as settlement_failure:
                        raise failure from settlement_failure
                    raise
                respond(extent_packet)
                del extent_packet

                # Body plus packed response and one bounded read block. The
                # Core input loan is independently sized by the exact packet.
                custody.workspace = self._reserve(lambda: self._core.reserve_workspace(
                    2 * extent + 12 + 16384,
                    stopped=lambda: custody.stopped, cleanup=lambda: custody.stopped))
                physical_failure: BaseException | None = None
                try:
                    raw = transfer.read_packet()
                except BaseException as failure:
                    physical_failure = failure
                    try:
                        raw = transfer.failure_packet()
                    except BaseException as settlement_failure:
                        raise failure from settlement_failure
                try:
                    respond(raw, physical_failure)
                    close_child(offer_input, offer)
                except BaseException as settlement_failure:
                    if physical_failure is not None:
                        raise physical_failure from settlement_failure
                    raise
                if physical_failure is not None:
                    raise physical_failure

            installation.binding.inspect(lambda current: self._checked_original_read(current, lambda: supply(current)))
            # The physical CSV read and both temporary transports have
            # returned. Keep the exact stop callback for the RowRun's later
            # borrow return, after stopping the original descriptors here.
            if not custody.stop(source.handle):
                raise LocalProductCleanupPending(self)
        while True:
            with self._core._lock:
                self._check_original_stop_interest(start.run)
                completed: list[bool] = []

                def read(current: _Output) -> None:
                    if self._required_local_project_input() is not project:
                        raise ValueError('Original Local CSV Project changed')
                    completed.append(self._core.advance_mock_effect_step(
                        source, current, operation='advance_local_csv_source'))
                    if self._required_local_project_input() is not project:
                        raise ValueError('Original Local CSV Project changed')

                installation.binding.inspect(lambda current: self._checked_original_read(current, lambda: read(current)))
                if completed[0]:
                    self._retire_original_csv_workspace(custody)
            if self._handoff_original_step(start.run, completed[0]):
                return

    def _retire_original_csv_workspace(self, custody: _OriginalCsvCapture) -> None:
        if custody.workspace is not None:
            if not self._core.close_workspace(custody.workspace):
                raise LocalProductCleanupPending(self)
            custody.workspace = None
        if custody.stopped:
            custody.transfer = None
        if custody.metadata_workspace is not None:
            if not self._core.close_workspace(custody.metadata_workspace):
                raise LocalProductCleanupPending(self)
            custody.metadata_workspace = None

    def _step_original_mock_effect(self, start: _PhysicalStart, kind: int, operation: str) -> bool:
        """Use one current Read and return its transport before the next quantum."""
        with self._core._lock:
            self._check_original_stop_interest(start.run)
            installation = self._active()
            files = self._project_files
            project = self._project_configuration
            request = start.run.preparation
            if (files is None or project is None
                    or not any(start is original for original in self._physical_starts)
                    or start.current is not self._configuration or type(request) is not _MockRequest):
                raise ValueError('Foreign original Mock Effect work')
            self._runs._start(start)
            completed: list[bool] = []

            local = self._original_local_project_input()
            def require_project() -> None:
                if local is None:
                    project.require_mock_seed(files)
                elif self._required_local_project_input() is not local:
                    raise ValueError('Original selected Local Project changed')

            def advance(current: _Output) -> None:
                require_project()
                at = self._original_physical_observed_at().encode('ascii')
                packet = self._fill_original_input(start.handle.to_bytes(4, 'little') + at)
                output = self._reserve(lambda: self._core.reserve_original_metadata(
                    packet, kind, cleanup=_original_metadata_cleanup))
                self._mock_effect_sources.append(output)
                completed.append(self._core.advance_mock_effect_step(output, current, operation=operation))
                require_project()
                if not self._core.close_original_metadata(output):
                    raise LocalProductCleanupPending(self)
                self._mock_effect_sources.remove(output)
                if not self._core.close_input(packet):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(packet)

            installation.binding.inspect(advance)
            if kind == _MOCK_EFFECT_SOURCE_EVIDENCE_KIND and completed[0]:
                # The sealed evidence and admitted Run keep the original
                # Submission record and input borrow. The consumed projection
                # output can return its buffer before the first Compute quote.
                if not self._core.retire_submission_append_output(request.submission):
                    raise LocalProductCleanupPending(self)
        return self._handoff_original_step(start.run, completed[0])

    def _seal_original_mock_effect_sources(self, start: _PhysicalStart) -> None:
        if not self._step_original_mock_effect(start, _MOCK_EFFECT_SOURCE_EVIDENCE_KIND,
                                               'seal_mock_effect_sources'):
            raise ValueError('Original Mock Source evidence did not complete')

    def _advance_original_mock_effect_tasks(self, start: _PhysicalStart) -> bool:
        return self._step_original_mock_effect(start, _MOCK_EFFECT_COMPUTE_KIND, 'advance_mock_effect_tasks')

    def _save_original_start_step(self, output: _Output, *, effect_claim: bool = False) -> int | None:
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
            fields = {'kind', 'key', 'revision', 'body'}
            if (set(candidate) != (fields | {'source_count'} if effect_claim else fields) or
                    any(type(candidate[key]) is not str for key in fields) or
                    candidate['kind'] not in ('dispatch', 'claim')):
                raise ValueError('Invalid original Core start step projection')
            count = candidate.get('source_count')
            if effect_claim and (candidate['kind'] != 'claim'
                                 or type(count) is not int or not 0 <= count < 2**31):
                raise ValueError('Invalid original Mock Effect Source count')
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
            return count

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

    def _capture_original_mock_effect(self, execution: _OriginalExecution) -> None:
        """Run the original Effect capture through its durable waiting observation."""
        from ._local_model_crypto import _OriginalModelEvidenceCrypto

        run = execution.run
        installation = self._active()
        store = installation._store
        with self._core._lock:
            self._runs._run(run)
            self._check_original_stop_interest(run)
            project, files = self._project_configuration, self._project_files
            if (type(run.preparation) is not _MockRequest or not execution.prepared_effect
                    or execution.submission is not run.preparation.submission
                    or execution.reference is None or store is None or project is None or files is None):
                raise ValueError('Foreign original Mock Effect execution')
            project.require_mock_seed(files)
            if (self._pending_start_write is not None or execution.start_step is not None
                    or execution.file_dispatch_step is not None or execution.physical_start is not None):
                raise LocalStorageError('Original Mock Effect start requires observation')
            work = next(value for value in self._physical_work if value._invoke is execution)
            crypto = _OriginalModelEvidenceCrypto(self._core, work, policy='builtin-aes-256-gcm',
                                                   plaintext_limit=min(1048576, store._max_record_bytes))
            execution.mock_review_crypto = crypto
        primary: BaseException | None = None
        try:
            crypto.begin()
            count: int | None = None
            start: _PhysicalStart | None = None
            with self._core._lock:
                for kind in (7, 8):
                    self._check_original_stop_interest(run)
                    output = self._reserve(lambda: self._core.reserve_material(run.handle, kind, cleanup=lambda: True))
                    self._step_outputs.append(output)
                    if kind == 7:
                        execution.file_dispatch_step = output
                    else:
                        execution.start_step = output
                    installation.binding.inspect(lambda _: self._core.produce_material(output))
                    count = self._save_original_start_step(output, effect_claim=kind == 8)
                    if kind == 8:
                        def retain_start(_: _Output) -> None:
                            selected = self._runs.reserve_sdk_physical_start(run, output)
                            execution.physical_start = selected
                            self._physical_starts.append(selected)
                        installation.binding.inspect(retain_start)
                        selected = execution.physical_start
                        if selected is None or count is None:
                            raise ValueError('Original Mock Effect claim did not retain its Source selection')
                        installation.binding.inspect(lambda _: self._runs.confirm_physical_start(selected))
                        start = selected
                    if not self._core.retire_material_output(output):
                        raise LocalProductCleanupPending(self)
            if start is None or count is None:
                raise ValueError('Original Mock Effect claim is incomplete')
            sources: list[_Output] = []
            for occurrence in range(count):
                with self._core._lock:
                    self._check_original_stop_interest(run)
                    source = self._reserve_mock_effect_source(start, occurrence)
                    sources.append(source)
                while True:
                    with self._core._lock:
                        self._check_original_stop_interest(run)
                        completed = self._advance_mock_effect_source(source)
                    if self._handoff_original_step(run, completed):
                        break
            self._seal_original_mock_effect_sources(start)
            while not self._advance_original_mock_effect_tasks(start):
                pass
            self._persist_original_mock_review(start, crypto)
            self._save_original_mock_waiting(start, crypto, sources)
        except BaseException as failure:
            primary = failure
            raise
        finally:
            try:
                if execution.mock_review_crypto is crypto and not crypto._closing:
                    self._retire_original_mock_review_crypto(execution, crypto)
            except BaseException as cleanup:
                if primary is not None:
                    raise primary from cleanup
                raise

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
        execution = self._current_execution()
        if execution is not None and execution.prepared_effect:
            self._capture_original_mock_effect(execution)
            return
        compute: _SourceFreeCompute | _PhysicalStart
        if execution is not None and execution.prepared_file:
            if execution.physical_start is not None:
                raise LocalStorageError('Original Local File execution is retained; replay is unavailable')
            start = self._configure_original_start(run, file=True)
            if self._original_local_project_input() is not None:
                self._capture_original_local_csv(start)
            else:
                if (type(run.preparation) is not _MockRequest
                        or self._original_project_bootstrap() is None
                        or execution.mock_file_source is not None):
                    raise ValueError('Original Mock Whole File Source is unavailable')
                with self._core._lock:
                    self._check_original_stop_interest(run)
                    source = self._reserve_mock_effect_source(start, occurrence=0)
                    execution.mock_file_source = source
                while True:
                    with self._core._lock:
                        self._check_original_stop_interest(run)
                        captured = self._advance_mock_effect_source(source)
                    if self._handoff_original_step(run, captured):
                        break
            self._seal_original_mock_effect_sources(start)
            compute = start
        else:
            compute = self._configure_original_compute(run)
        owned: list[_Task] = []
        if execution is not None:
            execution.tasks = owned
        if execution is not None and execution.prepared_model:
            if (type(compute) is not _SourceFreeCompute or execution.run is not run
                    or not isinstance(run.preparation, _MockRequest)
                    or execution.submission is not run.preparation.submission
                    or self._active()._portable_chat_output is None):
                raise ValueError('Original Portable Model execution is unavailable')
            work = next(value for value in self._physical_work if value._invoke is execution)
            from ._local_model_http import _ModelHttpTransportFailure

            try:
                results = self._execute_original_tasks(compute, None, None, retained_tasks=owned,
                    continue_model=lambda task, step:
                        self._continue_original_model_task(compute, task, work, execution, step))
            except _ModelHttpTransportFailure as primary:
                if (execution.model_unknown_transport is primary and work._cleanup_error is None
                        and execution.model_transfer is None):
                    # Core checks the same closed Call and confirmed Entry
                    # before the existing Submission CAS. Keep the initiating
                    # transport outcome even if state observation is uncertain.
                    try:
                        self._retain_original_model_unknown(execution, work)
                    except BaseException as observation:
                        raise primary from observation
                raise
            preflight, publisher = execution.preflight, execution.publisher
            if preflight is None or publisher is None:
                raise ValueError('Original Portable Model publication is unavailable')
        else:
            preflight, publisher = self._prepare_original_publication(compute)
            results = self._execute_original_tasks(compute, preflight, publisher, retained_tasks=owned)
        try:
            publication = self._capture_original_results(compute, preflight, results)
            self._drive_original_publication(
                publication, preflight, publisher, len(results),
                lambda: self._handoff_original_step(run, None))
        except BaseException as failure:
            try:
                # Sealing the SAME DAG is not an acknowledgment of its children.
                # Never discard a begun write's original Unknown/lookup custody.
                publications = tuple(publication for original, publication in self._run_publications
                                     if original is run)
                if (self._pending_publication_write is not None and any(
                        self._pending_publication_write._publication is original for original in publications)):
                    blocked = LocalProductCleanupPending(self)
                    if (execution is not None and execution.publication_reply_loss is None
                            and type(failure) is _LocalStorageCommitUnknown
                            and failure.cleanup_store is self._active()._store
                            and execution.publication is self._pending_publication_write._publication
                            and execution.publisher is publisher
                            and self._pending_publication_publisher is publisher):
                        execution.publication_reply_loss = (
                            self._pending_publication_write, publisher, failure, blocked)
                    raise blocked
                if type(compute) is _SourceFreeCompute and self._core.close_native_compute(compute.core):
                    raise ValueError('Original failed Compute was released before its invocation')
                if self._result_chunks or not self._close_original_publications(publications):
                    raise LocalProductCleanupPending(self)
                for result in reversed(results):
                    if any(original is result for original in self._result_exports):
                        if not self._core.close_result_export(result):
                            raise LocalProductCleanupPending(self)
                        self._result_exports.remove(result)
                self._retire_original_tasks(tuple(task for task in reversed(owned)
                    if any(original is task for original in self._tasks)))
            except BaseException as cleanup:
                work = next((work for work in self._physical_work if work._owner is run), None)
                if work is not None and work._cleanup_error is None:
                    work._cleanup_error = cleanup
            raise

    def _retain_original_model_unknown(self, execution: _OriginalExecution,
                                       work: OriginalLocalWork) -> None:
        core = self._core
        with core._borrow_work_operation(work) as retained:
            reference = execution.reference
            if (not retained or work._thread is not _current_thread()
                    or work._invoke is not execution or work._owner is not execution.run
                    or reference is None or reference.run is not execution.run):
                raise ValueError('Original stopped Model worker is unavailable')
            core._owned_input(reference.source)
            original = _object(core._inputs[reference.source.ticket].payload, 4096)
            self._observe_unpublished_run_state(execution.run, original, lambda _: None)

    def _configure_original_start(self, run: _Run, *, file: bool) -> _PhysicalStart:
        """Confirm dispatch and claim on the original durable Run."""
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk or
                not any(original is run for original in self._run_loans)):
            raise ValueError('Foreign original finite Local Run')
        with self._core._lock:
            if self._pending_start_write is not None:
                raise LocalStorageError('Original Local start requires lookup; new Compute is unavailable')
            self._bind_original_publication(run)
            execution = self._current_execution()
            # Material five asks the existing Owner to retain this Plan's
            # checked normalization. Its transport is not a durable write or
            # dispatch grant; the same Run keeps the original after close.
            for kind in ((7, 8) if file else (5, 7, 8)):
                output = self._reserve(lambda: self._core.reserve_material(
                    run.handle, kind, cleanup=lambda: True))
                self._step_outputs.append(output)
                if execution is not None:
                    if kind == 8:
                        execution.start_step = output
                    elif kind == 7 and file:
                        execution.file_dispatch_step = output
                installation.binding.inspect(lambda _: self._core.produce_material(output))
                if kind == 5:
                    if not self._core.close_material(output):
                        raise LocalProductCleanupPending(self)
                    self._step_outputs.remove(output)
                    continue
                self._save_original_start_step(output)
                if kind == 7:
                    if file:
                        # File claim borrows this confirmed dispatch. Only the
                        # now-consumed projection buffer can be returned here.
                        if not self._core.retire_material_output(output):
                            raise LocalProductCleanupPending(self)
                    else:
                        if not self._core.close_material(output):
                            raise LocalProductCleanupPending(self)
                        self._step_outputs.remove(output)
                        self._step_write_attempts.discard(output.ticket)
                else:
                    starts: list[_PhysicalStart] = []
                    def retain_start(_: _Output) -> None:
                        start = self._runs.reserve_sdk_physical_start(run, output)
                        self._physical_starts.append(start)
                        if execution is not None:
                            execution.physical_start = start
                        starts.append(start)
                    installation.binding.inspect(retain_start)
                    start = starts[0]
                    installation.binding.inspect(lambda _: self._runs.confirm_physical_start(start))
                    if not self._core.retire_material_output(output):
                        raise LocalProductCleanupPending(self)
                    return start
        raise ValueError('Original Local physical start is unavailable')

    def _configure_original_compute(self, run: _Run) -> _SourceFreeCompute:
        """Join the original saved Run/start/Compute Owners without executing tasks."""
        installation = self._active()
        configuration = self._configuration
        assert configuration is not None
        with self._core._lock:
            start = self._configure_original_start(run, file=False)
            selected = next(value for value in installation.binding._selected if value.name == 'compute.json')
            source = self._copy(installation.binding._source.original_bytes(selected))
            compute = self._runs.reserve_source_free_compute(start, source)
            self._source_free_computes.append(compute)
            execution = self._current_execution()
            if execution is not None:
                execution.compute = compute
            configured: list[bool] = []
            installation.binding.inspect(lambda _:
                configured.append(self._runs.configure_source_free_compute(compute, configuration)))
        if not configured[0]:
            if execution is None or execution.run is not run or not execution.prepared_model:
                raise ValueError('Original Local Model Source is unavailable')
            self._capture_original_local_csv(start)
            self._seal_original_mock_effect_sources(start)
            self._runs._require_source_free_compute_configured(compute)
        return compute

    def _prepare_original_publication(self, compute: _SourceFreeCompute | _PhysicalStart) -> tuple[_Output, _Output]:
        """Join original invocation/preflight/Account publisher before task activation.

        The callback fences physical custody and the six Core facts only. The
        existing Common port separately evaluates original/current run/publish
        and validates original Policy/target/request/index before and after it.
        Nothing here acknowledges Store, executes a task or grants Result read.
        """
        installation = self._active()
        configuration = self._configuration
        if configuration is None or not configuration.sdk:
            raise ValueError('Original Local publication configuration is unavailable')
        with self._core._lock:
            self._check_original_publication_compute(compute)
            invocation: _Output | _PhysicalStart
            if type(compute) is _PhysicalStart:
                invocation = compute
            else:
                if any(original is compute for original, _ in self._source_free_invocations):
                    raise LocalStorageError('Original Local invocation is retained; new preflight is unavailable')
                source = self._copy(b'{}')
                invocation = self._reserve(lambda: self._core.reserve_source_free_invocation(
                    compute.core, source, cleanup=lambda: True))
                self._source_free_invocations.append((compute, invocation))
        if type(invocation) is _Output:
            source_free_invocation = invocation
            while not self._original_compute_read_step(compute, lambda:
                    self._core.prepare_source_free_invocation(source_free_invocation, configuration.handle)):
                pass  # The original issuer advances one bounded step per returned Read.
        with self._core._lock:
            self._check_original_publication_compute(compute)
            # These are physical observations, not Run/Policy/scope issuers.
            request = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'now': self._now(),
                'attempt_id': os.urandom(32).hex(),
                'fence_cid': 'sha256:' + hashlib.sha256(os.urandom(32)).hexdigest(),
            }))
            execution = self._current_execution()
            preflight = self._reserve(lambda: self._core.reserve_publication_preflight(
                invocation, request, cleanup=lambda: True,
                model=execution is not None and execution.prepared_model))
            self._publication_preflights.append(preflight)
            if execution is not None:
                execution.preflight = preflight
            installation.binding.inspect(lambda _:
                self._core.prepare_publication_preflight(preflight, configuration.handle))
            # The original request/attempt remain nominal in Core. Installing
            # an SDK port needs no copied contract, target CID or permit input.
            publisher_input = self._copy(b'{}')

            from ._local_host_binding import _OriginalPublisherPort
            physical_publisher = _OriginalPublisherPort(installation.binding)
            publisher = self._reserve(lambda: self._core.reserve_publisher(
                preflight, publisher_input, current=physical_publisher.current_callback,
                authorize=physical_publisher.authorize_callback, cleanup=lambda: True,
                original=physical_publisher))
            self._publishers.append(publisher)
            if execution is not None:
                execution.publisher = publisher
            installation.binding.inspect(lambda _:
                self._core.install_publisher(publisher, configuration.handle))
            installation.binding.inspect(lambda _:
                self._core.authorize_publisher(publisher, configuration.handle, stage='request'))
            if not self._core.retire_publication_preflight_output(preflight):
                raise LocalProductCleanupPending(self)
            return preflight, publisher

    def _checked_original_read(self, current: _Output, work: Callable[[], _T]) -> _T:
        """Fence a write-free step inside one bounded original reader.

        Each step still observes physical originals before and after Core work.
        An unchanged SQLite transaction retains the inventory checked on entry;
        other adapters recheck it. No observer or permission spans this call.
        """
        installation = self._active()
        callbacks = self._core._host_current_ready(current)
        reader = callbacks.reader
        if reader is None:
            raise ValueError('Original Local read step has no reader')

        def unchanged() -> None:
            if callbacks.reader is not reader:
                raise ValueError('Original Local read step changed its reader')
            if reader.check_unchanged is not None:
                reader.check_unchanged(reader)
            else:
                installation.binding._adoption_inventory(reader)
                installation.binding._settings_inventory(reader)

        unchanged()
        result = work()
        if self._core._host_current_ready(current) is not callbacks:
            raise ValueError('Original Local read step changed its current callbacks')
        unchanged()
        return result

    def _execute_original_tasks(self, compute: _SourceFreeCompute | _PhysicalStart, preflight: _Output | None,
                                publisher: _Output | None, *,
                                retained_tasks: list[_Task] | None = None,
                                continue_model: Callable[[_Task, _TaskDrive], None] | None = None,
                                ) -> tuple[_ResultExport, ...]:
        """Drive existing task Owners; Python selects no task/transition/outcome."""
        installation = self._active()
        configuration = self._configuration
        if configuration is None or not configuration.sdk:
            raise ValueError('Foreign original Local task/publication custody')
        if continue_model is None:
            if (not any(original is preflight for original in self._publication_preflights)
                    or not any(original is publisher for original in self._publishers)):
                raise ValueError('Foreign original Local task/publication custody')
        elif (type(compute) is not _SourceFreeCompute or preflight is not None or publisher is not None
                or not any(original is compute for original in self._source_free_computes)
                or any(original is compute for original, _ in self._source_free_invocations)):
            raise ValueError('Foreign original Local Model task/publication custody')
        def step(work: Callable[[], _T]) -> _T:
            return self._original_compute_read_step(compute, work)

        owned: list[_Task] = [] if retained_tasks is None else retained_tasks
        execution = self._current_execution()
        if execution is not None:
            execution.tasks = owned
        results: list[_ResultExport] | None = None
        try:
            if type(compute) is _PhysicalStart:
                while not self._advance_original_mock_effect_tasks(compute):
                    pass
            else:
                while True:
                    def select_task() -> _Task | None:
                        task = self._core.reserve_next_sdk_task(compute.core, configuration.handle)
                        if task is not None:
                            # Retain before the original reader's post-current checks.
                            self._tasks.append(task)
                            owned.append(task)
                        return task
                    task = step(select_task)
                    if task is None:
                        break  # Explicit Core-checked end, never reserve's -2.
                    previous_pause: _TaskDrive | None = None
                    while True:
                        progress = step(lambda: self._core.drive_task_step(task, _EXECUTION_WORK_QUANTUM))
                        if progress is _TaskDrive.COMPLETE:
                            break
                        if progress is _TaskDrive.PROGRESSED:
                            previous_pause = None
                            continue
                        if (continue_model is None or progress is _TaskDrive.FINALIZATION_WAITING
                                or progress is previous_pause):
                            progress.refuse_unhandled_pause()
                        # The same bounded Store Read has returned before the
                        # authorized worker continuation can perform its I/O.
                        continue_model(task, progress)
                        previous_pause = progress
            if preflight is None:
                preflight, _ = self._prepare_original_publication(compute)
            prepared = preflight
            count = step(lambda: self._core.publication_preflight_result_count(prepared, configuration.handle))
            selected_results: list[_ResultExport] = []
            results = selected_results
            if execution is not None:
                execution.results = selected_results
            for index in range(count):
                def select_result() -> _ResultExport:
                    handle = compute if type(compute) is _PhysicalStart else compute.core
                    result = self._core.reserve_result_from_compute(handle, index, configuration.handle)
                    self._result_exports.append(result)
                    # Keep this SAME list's original before post-current can
                    # fail; a later constructor may also leave earlier exports.
                    selected_results.append(result)
                    return result
                step(select_result)
            return tuple(selected_results)

        except BaseException:
            # Same-original physical retirement never replaces the initiating
            # failure or interprets the request/worker Future as a stop ACK.
            try:
                # Existing Compute close seals this SAME DAG before child
                # retirement. Its invocation/preflight loan keeps the owner
                # present for actual stop/state observation and later cleanup.
                if type(compute) is _SourceFreeCompute and self._core.close_native_compute(compute.core):
                    raise ValueError('Original Compute observation custody disappeared before its child')
                if results is not None:
                    # An export pins its producer. Only an acknowledged return
                    # removes the original; refusal keeps both child and task.
                    for result in reversed(results):
                        if not self._core.close_result_export(result):
                            raise LocalProductCleanupPending(self)
                        self._result_exports.remove(result)
                self._retire_original_tasks(tuple(reversed(owned)))
            except BaseException as cleanup:
                work = next((work for work in self._physical_work
                    if work._owner is (compute.run if type(compute) is _PhysicalStart else compute.start.run)), None)
                if work is not None and work._cleanup_error is None:
                    work._cleanup_error = cleanup
            raise

    def _retire_original_tasks(self, tasks: _Iterable[_Task]) -> None:
        """Drive only observed local cleanup progress under the same allowance.

        A pending external stop returns immediately with its original loan.
        Finite continuation comes from the existing Core/provider cursor, not
        an arbitrary retry count, timer, new operation or instruction refill.
        """
        with self._core._lock:
            for task in tasks:
                self._core._owned_task(task)
                while True:
                    before = self._core.task_cleanup_continuation(task)
                    if self._core.close_task(task):
                        self._tasks.remove(task)
                        break
                    after = self._core.task_cleanup_continuation(task)
                    if after < 0 or before >= 0 and after <= before:
                        break

    def _check_original_publication_compute(self, compute: _SourceFreeCompute | _PhysicalStart) -> _Run:
        if type(compute) is _PhysicalStart:
            if not any(original is compute for original in self._physical_starts):
                raise ValueError('Foreign original Whole File physical start')
            self._runs._start(compute)
            return compute.run
        if not any(original is compute for original in self._source_free_computes):
            raise ValueError('Foreign original source-free Compute')
        self._runs._compute(compute)
        return compute.start.run

    def _save_original_model_call_entry(
            self, compute: _SourceFreeCompute, task: _Task, work: OriginalLocalWork,
            transfer: _OriginalModelHttpRawTransfer) -> tuple[str, ByteFence]:
        """Persist one pending Core Entry before any physical dispatch."""
        with self._core._lock:
            installation = self._active()
            self._runs._compute(compute)
            if task not in self._tasks:
                raise ValueError('Original Local Model task is unavailable')
            self._check_original_stop_interest(compute.start.run)
            clock = self._original_sdk_delivery_clock()
            prepared: _Output | None = None
            frame: list[tuple[bytes, bytes, bytes, bytes, bytes]] = []

            def project(current: _Output) -> None:
                def produce() -> None:
                    nonlocal prepared
                    output = self._core.reserve_task_model_entry(task, compute.core)
                    self._step_outputs.append(output)
                    self._core.produce_task_model_entry(task, clock, output)
                    prepared = output
                    scope, attempt, slot, count, name, digest, body = self._core.read_material(output).split(b'\n', 6)
                    frame.append((scope, attempt, slot, count, body))
                    selected = installation._portable_chat_ca
                    if selected is None and (name or digest):
                        raise ValueError('Original Portable Chat trust selection changed')
                    if selected is not None:
                        actual = (name.decode('ascii'), digest.decode('ascii'))
                        configuration = installation._portable_chat_output
                        if actual != selected or configuration is None:
                            raise ValueError('Original Portable Chat trust selection changed')
                        # Reserve the bounded original CA bytes and their live
                        # fd, PEM, conversion and SSL context before opening.
                        maximum = 65536
                        transfer._prepare_selected_trust(8 * maximum + 1048576, lambda load:
                            installation._with_portable_model_trust_body(
                                work, configuration, transfer, actual[0], actual[1], maximum, load))
                self._checked_original_read(current, produce)

            def return_entry_inputs(output: _Output) -> None:
                if not self._core.close_material(output):
                    raise LocalProductCleanupPending(self)
                self._step_outputs.remove(output)
                if not self._core.close_input(clock):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(clock)

            try:
                installation.binding.inspect(project)
                if prepared is None:
                    raise ValueError('Original Local Model Call Entry was not projected')
                output = prepared
                scope_wire, attempt, slot, count, body = frame[0]
                scope = scope_wire.decode('ascii')
            except BaseException as primary:
                if prepared is not None:
                    try:
                        # This operation has not offered its durable Entry.
                        self._core.finish_task_model_entry(task, prepared, confirmed=False)
                        return_entry_inputs(prepared)
                    except BaseException as cleanup:
                        raise primary from cleanup
                raise
            store = installation._store
            assert store is not None

            def inspect(reader: _NamespaceReader) -> None:
                installation.binding.inspect_reader(reader, lambda current:
                    self._checked_original_read(current, lambda:
                        self._core.inspect_task_model_entry(task, clock, output, saved=False)))

            def confirm(reader: _NamespaceReader, _saved: StoredBytes) -> None:
                installation.binding.inspect_reader(reader, lambda current:
                    self._checked_original_read(current, lambda:
                        self._core.inspect_task_model_entry(task, clock, output, saved=True)))

            try:
                with installation.binding.fenced() as fences:
                    saved = store._save_model_call_entry_inspected(
                        scope, attempt.decode('ascii'), int(slot), int(count),
                        body, store._max_payload_bytes, fences, inspect=inspect, confirm=confirm,
                        current=installation.binding._current_observer)
                    if saved is None:
                        raise LocalStorageError('Original Local Model Call Entry was not confirmed')
            except BaseException as primary:
                try:
                    self._core.finish_task_model_entry(task, output, confirmed=False)
                except BaseException as cleanup:
                    raise primary from cleanup
                raise
            # The exact SQLite snapshot has stopped. Only now can the existing
            # Core persistence poll observe a same-entry Saved acknowledgement.
            self._core.finish_task_model_entry(task, output, confirmed=True)
            return_entry_inputs(output)

            return scope, ByteFence(store.namespaced_key('client_model_call_originals', attempt.decode('ascii')),
                                    saved.generation, saved.payload)

    def _require_original_model_worker(self, compute: _SourceFreeCompute, task: _Task,
                                       work: OriginalLocalWork) -> None:
        core = self._core
        if core._lock._is_owned():
            raise ValueError('Original Model continuation requires a released Core read frame')
        with core._borrow_work_operation(work) as retained:
            self._runs._compute(compute)
            execution = self._current_execution()
            if (not retained or work._owner is not compute.start.run
                    or work._thread is not _current_thread()
                    or execution is None or execution.compute is not compute
                    or execution.tasks is None or not any(original is task for original in execution.tasks)
                    or not any(original is task for original in self._tasks)):
                raise ValueError('Original Local Model continuation worker is unavailable')
            self._check_original_stop_interest(compute.start.run)

    def _stage_original_model_dispatch(self, compute: _SourceFreeCompute, task: _Task,
                                       work: OriginalLocalWork) -> None:
        """Advance the exact waiting task through its existing authorization and Entry stage."""
        self._require_original_model_worker(compute, task, work)
        core = self._core
        self._observe_original_model_clock(compute, lambda clock:
            core.prepare_task_model_dispatch(task, clock))
        self._observe_original_model_clock(compute, lambda clock:
            core.stage_task_model_entry(task, clock))

    def _continue_original_model_task(self, compute: _SourceFreeCompute, task: _Task,
                                     work: OriginalLocalWork, execution: _OriginalExecution,
                                     state: _TaskDrive) -> None:
        if state is _TaskDrive.WAITING:
            self._stage_original_model_dispatch(compute, task, work)
            return
        if state is not _TaskDrive.AWAIT_IO:
            state.refuse_unhandled_pause()
        self._require_original_model_worker(compute, task, work)
        core = self._core
        installation = self._active()
        from ._local_model_crypto import _MAX_PLAINTEXT
        from ._local_model_http import _OriginalModelHttpRawTransfer, _OriginalModelHttpTransport
        with core._lock:
            if (self._current_execution() is not execution or not execution.prepared_model
                    or installation._portable_chat_output is None or execution.model_transfer is not None):
                raise ValueError('Original Portable Model exchange is unavailable')
            self._check_original_stop_interest(execution.run)
            transfer = _OriginalModelHttpRawTransfer(core, work, _OriginalModelHttpTransport(None))
            execution.model_transfer = transfer
        request: _Output | None = None

        def retire() -> None:
            with core._lock:
                if execution.model_transfer is not transfer:
                    raise LocalProductCleanupPending(self)
                transport_failure: BaseException | None = None
                try:
                    if not transfer.close():
                        raise LocalProductCleanupPending(self)
                except BaseException as failure:
                    transport_failure = failure
                else:
                    execution.model_transfer = None
                try:
                    # The native arena's first close needs this worker. The
                    # transport has its own pending resources and cannot use it.
                    if not installation._close_model_evidence_crypto(work):
                        raise LocalProductCleanupPending(self)
                except BaseException as crypto_failure:
                    if transport_failure is None:
                        raise
                    raise transport_failure from crypto_failure
                if transport_failure is not None:
                    raise transport_failure
                if request is not None:
                    if not core.close_material(request):
                        raise LocalProductCleanupPending(self)
                    self._step_outputs.remove(request)

        try:
            installation._begin_model_evidence_crypto(work, _MAX_PLAINTEXT)
            scope, entry, request = self._prepare_original_model_exchange(compute, task, work, transfer)
            self._exchange_original_model_request(compute, task, work, transfer, request, scope, entry)
        except BaseException as primary:
            try:
                retire()
            except BaseException as cleanup:
                work._cleanup_error = cleanup
                raise primary from cleanup
            raise
        retire()

    def _prepare_original_model_exchange(self, compute: _SourceFreeCompute, task: _Task,
                                         work: OriginalLocalWork, transfer: _OriginalModelHttpRawTransfer
                                         ) -> tuple[str, ByteFence, _Output]:
        """Keep Entry and request preparation on the same live worker before egress."""
        self._require_original_model_worker(compute, task, work)
        core = self._core
        scope, entry = self._save_original_model_call_entry(compute, task, work, transfer)

        def reserve() -> _Output:
            request = core.reserve_task_model_request(task, compute.core)
            self._step_outputs.append(request)
            return request

        request = self._original_compute_read_step(compute, reserve)
        self._observe_original_model_clock(compute, lambda clock:
            core.produce_task_model_request(task, clock, request))
        return scope, entry, request

    def _observe_original_model_clock(self, compute: _SourceFreeCompute,
                                      use: Callable[[_Input], _T]) -> _T:
        core = self._core
        clock = self._original_sdk_delivery_clock()

        def retire() -> None:
            with core._lock:
                if not core.close_input(clock):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(clock)

        try:
            result = self._original_compute_read_step(compute, lambda: use(clock))
        except BaseException as primary:
            try:
                retire()
            except BaseException as cleanup:
                raise primary from cleanup
            raise
        retire()
        return result

    def _exchange_original_model_request(
            self, compute: _SourceFreeCompute, task: _Task, work: OriginalLocalWork,
            transfer: _OriginalModelHttpRawTransfer, request: _Output,
            scope: str, entry: ByteFence) -> _CompleteModelHttpResponse:
        """Advance one entered Model worker through its confirmed Raw and settlement."""
        self._require_original_model_worker(compute, task, work)
        core = self._core
        with core._borrow_work_operation(work) as retained:
            installation = self._active()
            crypto = installation._portable_crypto
            if (not retained or transfer._work is not work or transfer._core is not core
                    or crypto is None or crypto._work is not work or crypto._closing
                    or not crypto._has_custody or crypto._loader_workspace is not None):
                raise ValueError('Original Local Model exchange worker is unavailable')

        def observe(use: Callable[[_Input], _T]) -> _T:
            return self._observe_original_model_clock(compute, use)

        def response_status() -> int:
            # Each zero advances the existing charged Core cursor. End this
            # read before allowing the same physical worker's control turn.
            while True:
                code = observe(lambda clock: core.advance_task_model_response(
                    task, clock, _EXECUTION_WORK_QUANTUM))
                if code != 0:
                    return code

        from ._local_model_http import _ModelHttpTransportFailure

        try:
            response, _ = transfer.run_entered(task, request, observe=observe,
                credential_for_entered_call=lambda: installation._read_portable_model_credential(
                    work, model_trust=transfer._trust_reader))
        except _ModelHttpTransportFailure as primary:
            if transfer._request_started and transfer._ready_to_retire():
                try:
                    code = response_status()
                    if code != -32:
                        raise LocalCoreError('observe_stopped_model_response', code)
                    execution = self._current_execution()
                    if execution is None or execution.model_transfer is not transfer:
                        raise ValueError('Original Model transport owner is unavailable')
                    execution.model_unknown_transport = primary
                except BaseException as observation:
                    raise primary from observation
            raise
        raw = self._save_original_model_raw(compute, task, work, scope, entry)
        waiting = response_status()
        if waiting != 3:
            raise LocalCoreError('advance_model_response', waiting)
        self._persist_original_model_settlement(compute, task, work, entry, raw)
        complete = response_status()
        if complete != 1:
            raise LocalCoreError('advance_model_response', complete)
        return response

    def _save_original_model_raw(self, compute: _SourceFreeCompute, task: _Task,
                                 work: OriginalLocalWork, scope: str,
                                 entry: ByteFence) -> _ModelRawFence:
        """Authenticate the original Raw readback before making it visible to Core."""
        with self._core._borrow_work_operation(work) as retained:
            installation = self._active()
            self._runs._compute(compute)
            crypto = installation._portable_crypto
            if (not retained or work._owner is not compute.start.run
                    or task not in self._tasks or crypto is None or crypto._work is not work):
                raise ValueError('Original Local Model Raw worker is unavailable')
            crypto._require_worker()
            core = self._core
            binding = installation.binding
            loans: list[_Input] = []
            outputs: list[_Output] = []
            sealed_output: _Output | None = None

            def with_clock(current: _Output, use: Callable[[_Input], _T]) -> _T:
                self._check_original_stop_interest(compute.start.run)
                clock = self._original_sdk_delivery_clock()
                try:
                    return self._checked_original_read(current, lambda: use(clock))
                finally:
                    if not core.close_input(clock):
                        raise LocalProductCleanupPending(self)
                    self._inputs.remove(clock)

            def hold_output(output: _Output) -> _Output:
                self._step_outputs.append(output)
                outputs.append(output)
                return output

            def fill(packet: bytes) -> _Input:
                loan = self._fill_original_input(packet)
                loans.append(loan)
                return loan

            def retire() -> None:
                for loan in reversed(loans):
                    if not core.close_input(loan):
                        raise LocalProductCleanupPending(self)
                    self._inputs.remove(loan)
                for output in reversed(outputs):
                    if not core.close_material(output):
                        raise LocalProductCleanupPending(self)
                    self._step_outputs.remove(output)

            def save() -> _ModelRawFence:
                nonlocal sealed_output
                raw_output: _Output | None = None

                def project(current: _Output) -> None:
                    def produce(clock: _Input) -> None:
                        nonlocal raw_output
                        raw_output = hold_output(core.reserve_task_model_raw(task, compute.core))
                        core.produce_task_model_raw(task, clock, raw_output)
                    with_clock(current, produce)

                binding.inspect(project)
                assert raw_output is not None
                holding_wire, attempt_wire, adoption_wire, store_wire, aad, plaintext = (
                    core.read_material(raw_output).split(b'\n', 5))
                holding, attempt, adoption, store_cid = (
                    source.decode('ascii') for source in (holding_wire, attempt_wire, adoption_wire, store_wire))
                packet: _Input | None = None

                def seal(current: _Output) -> None:
                    def retain(data: bytes) -> None:
                        nonlocal packet
                        packet = fill(data)
                    binding._with_model_evidence_key(current, adoption, store_cid,
                        lambda key: crypto.seal(key, aad, plaintext, retain))

                binding.inspect(seal)
                assert packet is not None
                original_packet = packet

                def encode(current: _Output) -> None:
                    def produce(clock: _Input) -> None:
                        nonlocal sealed_output
                        sealed_output = hold_output(core.reserve_task_model_raw_sealed(task, compute.core))
                        core.produce_task_model_raw_sealed(task, clock, sealed_output, original_packet)
                    with_clock(current, produce)

                binding.inspect(encode)
                assert sealed_output is not None
                output = sealed_output
                envelope = core.read_material(output)

                def open_write(current: _Output) -> None:
                    with_clock(current, lambda clock: core.inspect_task_model_raw_store(task, clock, output))

                def confirm(current: _Output, actual: StoredBytes) -> None:
                    if actual.generation != 0 or actual.payload != envelope:
                        raise LocalStorageError('Original Local Model Raw readback changed')

                    def accept(authenticated: bytes) -> None:
                        loan = fill(authenticated)
                        with_clock(current, lambda clock: core.inspect_task_model_raw_store(
                            task, clock, output, authenticated=loan))

                    # The inspected row byte-for-byte equals the envelope
                    # derived from this same packet by Core's canonical writer.
                    binding._with_model_evidence_key(current, adoption, store_cid,
                        lambda key: crypto.authenticate(key, aad,
                            core._inputs[original_packet.ticket].payload, accept))

                raw = installation._save_model_raw_capture(
                    work, scope, holding, attempt, entry, envelope, inspect=open_write, confirm=confirm)
                # The readback callback has returned and the original SQLite
                # reader has closed. Reobserve current before admitting it.
                binding.inspect(lambda current: with_clock(current,
                    lambda clock: core.finish_task_model_raw_store(task, output, clock=clock)))
                core.finish_task_model_raw_store(task, output, expose=True)
                return raw

            try:
                raw = save()
            except BaseException as primary:
                try:
                    if sealed_output is not None:
                        core.finish_task_model_raw_store(task, sealed_output)
                    retire()
                except BaseException as cleanup:
                    raise primary from cleanup
                raise
            retire()
            return raw

    def _persist_original_model_settlement(self, compute: _SourceFreeCompute, task: _Task,
                                           work: OriginalLocalWork, entry: ByteFence,
                                           raw: _ModelRawFence) -> None:
        """Save the original Call's closed evidence before releasing its Model pause."""
        with self._core._borrow_work_operation(work) as retained:
            installation = self._active()
            self._runs._compute(compute)
            crypto = installation._portable_crypto
            store = installation._store
            if (not retained or work._owner is not compute.start.run
                    or task not in self._tasks or crypto is None or crypto._work is not work
                    or store is None):
                raise ValueError('Original Local Model settlement worker is unavailable')
            crypto._require_worker()
            core = self._core
            binding = installation.binding
            outputs: list[_Output] = []
            sealed: _Output | None = None
            packet: _Input | None = None
            workspace: _Workspace | None = None

            def inspect_clock(current: _Output, observe: Callable[[_Input], _T]) -> _T:
                self._check_original_stop_interest(compute.start.run)
                clock = self._original_sdk_delivery_clock()
                try:
                    return self._checked_original_read(current, lambda: observe(clock))
                finally:
                    if not core.close_input(clock):
                        raise LocalProductCleanupPending(self)
                    self._inputs.remove(clock)

            def reserve(output: _Output) -> _Output:
                self._step_outputs.append(output)
                outputs.append(output)
                return output

            def retire() -> None:
                if packet is not None:
                    if not core.close_input(packet):
                        raise LocalProductCleanupPending(self)
                    self._inputs.remove(packet)
                if workspace is not None:
                    if not core.close_workspace(workspace):
                        raise LocalProductCleanupPending(self)
                for output in reversed(outputs):
                    if not core.close_material(output):
                        raise LocalProductCleanupPending(self)
                    self._step_outputs.remove(output)

            def save() -> None:
                nonlocal packet, sealed, workspace
                # Chunk export uses the original Call's own bounded writer and
                # retains no SQLite snapshot between quanta.
                while True:
                    complete: list[bool] = []
                    binding.inspect(lambda current: complete.append(inspect_clock(current,
                        lambda clock: core.advance_task_model_settlement(task, clock, 256))))
                    if complete == [True]:
                        break
                def project(current: _Output) -> None:
                    def produce(clock: _Input) -> None:
                        projection = reserve(core.reserve_task_model_settlement(task, compute.core))
                        core.produce_task_model_settlement(task, clock, projection)
                    inspect_clock(current, produce)

                binding.inspect(project)
                projection = outputs[-1]
                scope_wire, _, attempt_wire, ordinal, _, count, adoption_wire, store_wire, body = (
                    core.read_material(projection).split(b'\n', 8))
                scope, attempt, adoption, store_cid = (
                    value.decode('ascii') for value in (scope_wire, attempt_wire, adoption_wire, store_wire))
                total = int(count)
                if not 6 <= total <= 8:
                    raise ValueError('Invalid original Model evidence count')
                leaves: list[tuple[str, bytes, bytes]] = []
                for _ in range(total):
                    _, _, holding, aad, extent, rest = body.split(b'\n', 5)
                    length = int(extent)
                    if not 0 < length <= len(rest):
                        raise ValueError('Invalid original Model evidence extent')
                    leaves.append((holding.decode('ascii'), aad, rest[:length]))
                    body = rest[length:]
                if body:
                    raise ValueError('Trailing original Model evidence')

                encrypted: list[bytes] = []
                packet_bytes = sum(len(plain) + 28 for _, _, plain in leaves)
                # The same operation retains individual packets for exact
                # authentication and briefly a concatenated binary input.
                # One bounded SQLite BLOB and its Python copy may
                # overlap. The two transaction snapshots are sequential.
                allowance = (2 * packet_bytes + (total + 1) * sys.getsizeof(b'')
                             + sys.getsizeof([None] * (2 * total))
                             + 2 * raw.extent + sys.getsizeof(b''))
                workspace = self._reserve(lambda: core.reserve_workspace(
                    allowance, cleanup=lambda: True, stopped=lambda: True))

                def seal(current: _Output) -> None:
                    def all_leaves(key: bytes) -> None:
                        for _, aad, plain in leaves:
                            crypto.seal(key, aad, plain, encrypted.append)
                    binding._with_model_evidence_key(current, adoption, store_cid, all_leaves)

                binding.inspect(seal)
                packet = self._fill_original_input(b''.join(encrypted))
                binary_packet = packet
                def encode(current: _Output) -> None:
                    def produce(clock: _Input) -> None:
                        nonlocal sealed
                        sealed = reserve(core.reserve_task_model_settlement_store(task, compute.core))
                        core.produce_task_model_settlement_store(task, clock, sealed, binary_packet)
                    inspect_clock(current, produce)

                binding.inspect(encode)
                assert sealed is not None
                output = sealed
                index, *envelopes = core.read_material(output).split(b'\n')
                if len(envelopes) != total or not all(envelopes):
                    raise ValueError('Invalid original Model settlement envelope set')

                def offer(reader: _NamespaceReader) -> None:
                    binding.inspect_reader(reader, lambda current: inspect_clock(current,
                        lambda clock: core.inspect_task_model_settlement_store(
                            task, clock, output, readback=False)))

                def confirm(reader: _NamespaceReader) -> None:
                    def reobserve(current: _Output) -> None:
                        def all_leaves(key: bytes) -> None:
                            for (_, aad, plaintext), ciphertext in zip(leaves, encrypted, strict=True):
                                def compare(authenticated: bytes) -> None:
                                    if authenticated != plaintext:
                                        raise LocalStorageError('Original Model settlement evidence changed')
                                crypto.authenticate(key, aad, ciphertext, compare)
                        # The original reader has already compared every saved
                        # envelope to the wire made from these exact packets.
                        binding._with_model_evidence_key(current, adoption, store_cid, all_leaves)
                        inspect_clock(current, lambda clock:
                            core.inspect_task_model_settlement_store(task, clock, output, readback=True))
                    binding.inspect_reader(reader, reobserve)

                cells = tuple((leaf[0], envelope)
                              for leaf, envelope in zip(leaves, envelopes, strict=True))
                with binding.fenced() as fences:
                    store._save_model_settlement_inspected(scope, attempt, int(ordinal), entry,
                        raw, index, cells, fences, inspect=offer, confirm=confirm,
                        current=binding._current_observer)
                core.finish_task_model_settlement_store(task, output, confirmed=True)

            try:
                save()
            except BaseException as primary:
                try:
                    if sealed is not None:
                        core.finish_task_model_settlement_store(task, sealed, confirmed=False)
                    retire()
                except BaseException as cleanup:
                    raise primary from cleanup
                raise
            retire()

    def _original_compute_read_step(self, compute: _SourceFreeCompute | _PhysicalStart,
                                     work: Callable[[], _T]) -> _T:
        """One same-owner quantum; its current/Store reader ends before unlock.

        Original Compute/export/publication cursors remain owned between calls.
        No guest view, current frame or reusable permission leaves this unit.
        """
        with self._core._lock:
            run = self._check_original_publication_compute(compute)
            self._check_original_stop_interest(run)
            installation = self._active()
            values: list[_T] = []
            installation.binding.inspect(lambda current: values.append(
                self._checked_original_read(current, work)))
        return self._handoff_original_step(run, values[0])

    def _handoff_original_step(self, run: _Run, value: _T) -> _T:
        """Return the same completed unit after its actual worker's control turn.

        The caller has left Core/current/Store scopes; this never constructs,
        replaces or retires a cursor. This is scheduling interest only, not current permission,
        cancellation, Store acknowledgement or a wall-clock latency guarantee.
        """
        with self._core._lock:
            retained = getattr(self._core, '_host_retained_work', None)
            physical = retained[0] if retained is not None and retained[0]._owner is run else None
        if physical is not None:
            physical._yield_to_control()
            with self._core._lock:
                self._check_original_stop_interest(run)
        return value

    def _check_original_stop_interest(self, run: _Run) -> None:
        """Caller holds Core: no stale check may race a confirmed cancel CAS."""
        retained = getattr(self._core, '_host_retained_work', None)
        if retained is None:
            return
        work = retained[0]
        if work._thread is not _current_thread():
            return
        work._nominal()
        original = work._invoke
        if (type(original) is _OriginalExecution and original.host is self
                and original.run is run and work._owner is run
                and original.stop_interest is not None):
            raise _OriginalCancellationStop(original)

    def _capture_original_results(self, compute: _SourceFreeCompute | _PhysicalStart, preflight: _Output,
                                  results: tuple[_ResultExport, ...]) -> _Output:
        """Finish original exports and Receipt; Store commit/ACK is separate.

        Transient chunks need not copy rows into Python. Their original Core
        finish marker closes each stream. The later payload replay reads the
        retained completed output; it cannot restart Source or Compute.
        """
        installation = self._active()
        configuration = self._configuration
        if (configuration is None or not configuration.sdk or type(results) is not tuple or
                not any(original is preflight for original in self._publication_preflights) or
                any(not any(original is result for original in self._result_exports) for result in results)):
            raise ValueError('Foreign original Local Result/publication custody')
        def step(work: Callable[[], _T]) -> _T:
            return self._original_compute_read_step(compute, work)

        for result in results:
            step(lambda: self._core.start_result_export(result))
            while not step(lambda: self._core.feed_result_export(result, _EXECUTION_WORK_QUANTUM)):
                pass
            while not step(lambda: self._core.advance_result_export(
                    result, _EXECUTION_WORK_QUANTUM)).ready:
                pass
            step(lambda: self._core.finish_result_export_preparation(result))
            while True:
                def reserve_chunk() -> _Output:
                    chunk = self._reserve(lambda: self._core.reserve_result_chunk(result, cleanup=lambda: True))
                    self._result_chunks.append(chunk)
                    return chunk
                chunk = step(reserve_chunk)

                step(lambda: self._core.produce_result_chunk(chunk))
                final = step(lambda: self._core.result_chunk_finished(chunk))
                # Cleanup is a separate same-token boundary, not fresh normal
                # work/current admission. A declined return retains the chunk.
                with self._core._lock:
                    if not self._core.close_result_chunk(chunk):
                        raise LocalProductCleanupPending(self)
                    self._result_chunks.remove(chunk)
                if final:
                    break

        def reserve_publication() -> _Output:
            source = (compute if type(compute) is _PhysicalStart else next(
                original for owner, original in self._source_free_invocations if owner is compute))
            # Preserve the existing private export limits, not a new unlimited
            # scan or a broader admitted profile. Core shares this work budget
            # across snapshot, capture and later commit validation.
            request = self._copy(wire_bytes({  # type: ignore[no-untyped-call]
                'results': [result.handle for result in results],
                'max_work': 1000000, 'max_workspace_slots': 100000,
            }))
            execution = self._current_execution()
            publication = self._reserve(lambda: self._core.reserve_publication(
                source, request, cleanup=lambda: True,
                model=execution is not None and execution.prepared_model))
            self._publications.append(publication)
            self._run_publications.append((compute.run if type(compute) is _PhysicalStart else compute.start.run, publication))
            if execution is not None:
                execution.publication = publication
            return publication
        publication = step(reserve_publication)
        step(lambda: self._core.prepare_publication(publication, configuration.handle))
        while not step(lambda: self._core.advance_publication(
                publication, configuration.handle, _PUBLICATION_WORK_QUANTUM)).ready:
            pass
        step(lambda: self._core.finish_publication(publication, configuration.handle))
        with self._core._lock:
            if not self._core.retire_publication_output(publication):
                raise LocalProductCleanupPending(self)
            return publication

    def _drive_original_publication(
            self, publication: _Output, preflight: _Output, publisher: _Output,
            count: int, handoff: Callable[[], None], *,
            require_committed: bool = False,
            effect_fences: tuple[ByteFence, ...] = ()) -> OriginalCommitProjection:
        for index in range(count):
            held = self._prepare_original_payload(publication, index)
            self._save_original_payload_intent(held)
            self._reserve_original_payload_capacity(held)
            self._save_original_payload_reserved(held)
            self._prepare_original_payload_writing(held)
            self._acquire_original_payload_file(held)
            self._stage_original_payload_file(held)
            while True:
                ready = self._advance_original_payload_copy(held)
                handoff()
                if ready:
                    break  # Existing bounded Core/File cursor, same input and fuel.
            while True:
                ready = self._advance_original_payload_sealing(held)
                handoff()
                if ready:
                    break
            self._open_original_payload_reader(held)
            while True:
                ready = self._advance_original_payload_reader(held)
                handoff()
                if ready:
                    break
        self._prepare_original_commit_candidate(publication, preflight)
        while True:
            projection = self._advance_original_commit_candidate(publication)
            handoff()
            if projection is not None:
                break
        execution = self._current_execution()
        if (execution is not None and execution.prepared_model
                and execution.publication is publication):
            # Compute's finished commit has copied the checked binding. The
            # physical Record and hashed reader stay live through Store checks.
            with self._core._lock:
                request = self._commit_requests[publication.ticket]
                if not self._core.close_input(request):
                    raise LocalProductCleanupPending(self)
                self._inputs.remove(request)
                del self._commit_requests[publication.ticket]
                for held in self._payloads:
                    if held.publication is publication:
                        if held.binding is not None:
                            if not self._core.close_payload_binding(held.binding):
                                raise LocalProductCleanupPending(self)
                            held.binding = None
                        if held.names is not None:
                            if not self._core.close_payload_names(held.names):
                                raise LocalProductCleanupPending(self)
                            held.names = None
        facts = self._original_commit_reader_facts(projection)
        originals: list[tuple[ByteFence, CapacityReservation]] = []
        for fact in facts:
            held = next(value for value in self._payloads if value.record is fact._record)
            if held.row is None or held.capacity is None:
                raise ValueError('Original Local publication physical fences are unavailable')
            originals.append((held.row, held.capacity))
        self._store_original_commit(projection, facts, tuple(originals), publisher,
                                    effect_fences=effect_fences)
        self._prepare_original_store_observation(projection, publisher, effect_fences=effect_fences)
        while True:
            action = self._advance_original_store_observation(projection)
            handoff()
            if action is not None:
                break
        if require_committed and action != 'adopt_committed_index':
            raise LocalStorageError('Original Effect publication requires observation')
        return projection

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
                # Ordinary durable publications outlive the original File
                # descriptors. The Store owns the durable reservation count.
                # Neither inserted nor already-present is a Core transition.
                max_objects = store._max_reservations if store._ordinary else results._max_files
                store.reserve_capacity_inspected('publication_payload', held.row.key,
                    held.maximum, 1, store._max_payload_bytes, max_objects,
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
            def consume(actual: StoredBytes | None) -> None:
                # Common admits only the ASCII allocation name, digits and
                # separators. The ownership write can carry the original name
                # in both bodies, including any retained leading zeros.
                previous_bytes = 0 if actual is None else len(actual.payload)
                limit = min(65_536, 1024 + kind * previous_bytes)
                child = self._reserve(lambda: self._core.reserve_payload_allocation(
                    record, kind, limit, cleanup=lambda: True))
                held.allocation = child
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
                        self._core.reserve_payload_chunk(request, held.maximum, cleanup=lambda: True))
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
            # The returned Sealed observation owns the committed generation.
            # The transport children are now disposable, while the confirmed
            # record, replay and physical finalization still pin their originals.
            if not self._core.close_payload_writing(child):
                raise LocalProductCleanupPending(self)
            self._payload_transition_attempts.discard(child.ticket)
            held.writing = None
            if not self._core.close_payload_chunk(chunk):
                raise LocalProductCleanupPending(self)
            held.chunk = None
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
                self._core.validate_payload_binding(child, configuration.handle)
                packet = _object(self._core.read_payload_names(names, configuration.handle), 65536)
                if packet.get('object_name') != finalization.name:
                    raise ValueError('Original Core final name and actual file differ')
                try:
                    held.reader = physical.root.open_reader(finalization)
                except LocalReaderAcquisitionError as failure:
                    held.reader = failure.original_reader
                    raise
            installation.binding.inspect(acquire)

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
                self._core.validate_payload_binding(binding, configuration.handle)
                self._core.read_payload_names(names, configuration.handle)
                if not reader.eof:
                    chunk = reader.root.read_reader(reader)
                    self._core.validate_payload_binding(binding, configuration.handle)
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
            projection = OriginalCommitProjection(self._core, publication, configuration.handle,
                                                  cleanup=_original_metadata_cleanup)
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
                        cleanup=_original_metadata_cleanup, stopped=_original_metadata_stopped)
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

    def _prepare_original_store_observation(
            self, projection: OriginalCommitProjection, publisher: _Output, *,
            effect_fences: tuple[ByteFence, ...] = ()) -> None:
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
            original_run = next((run for run, publication in self._run_publications
                                 if publication is projection._publication), None)
            execution = (self._execution_for_run(original_run, projection._publication)
                         if original_run is not None else None)
            retains_task_points = execution is not None and execution.prepared_file
            transfers = []
            for ordinal in range(2):
                # The existing transfer quotes bounded original bytes. Six
                # octets per source octet plus the fixed envelope is its strict
                # worst case, charged before Store rows or encoding are copied.
                transfer = OriginalObservationTransfer(projection, publisher,
                    max_source_bytes=65536, max_packet_bytes=6 * 65536 + 256,
                    cleanup=_original_metadata_cleanup, stopped=_original_metadata_stopped,
                    workspace_cleanup=_original_metadata_cleanup,
                    workspace_stopped=_original_metadata_cleanup,
                    retain_task_points=ordinal == 0 and retains_task_points)
                self._observation_transfers.append(transfer)
                transfers.append(transfer)
                transfer.reserve()
            observation = OriginalStoreReconciliation(projection, facts, store, tuple(originals),
                publisher, transfers[0], transfers[1], effect_points=effect_fences)
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
            # Keep a bounded 256-unit quantum; the physical driver hands off
            # after this method releases its complete current/Store scopes.
            # Do not reopen the complete current transaction every 16 units.
            # Use the same original total work/fuel, without a larger quantum.
            # Each advance retains before/after physical checks, failure state
            # and the original observation owner.
            progress = observation.advance(256)
            if not progress.ready:
                return None
            action = observation.finish()
            if action == 'adopt_committed_index':
                pending = self._pending_publication_write is projection
                if pending:
                    publisher = self._pending_publication_publisher
                    if publisher is None or observation._publisher is not publisher:
                        raise ValueError('Foreign original publication attempt retirement')
                    # Re-export the admitted original Index through its actual
                    # File/Store/current and publisher checks before clearing
                    # this pending physical write.
                    observation.project_observed_index(lambda _identity, _body: None)
                if not observation.retire_exact_transports():
                    raise LocalProductCleanupPending(self)
                if pending:
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
                               publisher: _Output, *,
                               effect_fences: tuple[ByteFence, ...] = ()) -> None:
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
                    self._core.authorize_publisher(publisher, configuration.handle, stage='request')
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
                        counts[0], projection.project_storage_entry, originals, (*fences, *effect_fences),
                        inspect=lambda reader, consume:
                            installation.binding.inspect_reader(reader, lambda _: consume()),
                        current=installation.binding._current_observer, before_commit=before_commit,
                        _effect_points=effect_fences)
                if generations is None:
                    raise LocalStorageError('Original publication write conflicted; lookup is required')

    def _close_original_publications(self, originals: tuple[_Output, ...]) -> bool:
        """Retire only these original publication children, without a write/retry.

        This is the same physical close sequence used by whole-Host cleanup.
        A failed worker may return its unpublished children while keeping its
        original Run, invocation and first failure available to status/lookup.
        """
        with self._core._lock:
            if any(not any(held is original for held in self._publications) for original in originals):
                raise ValueError('Foreign original publication cleanup selection')
            def selected(publication: _Output) -> bool:
                return any(publication is original for original in originals)
            for projection in tuple(reversed(self._commit_projections)):
                if not selected(projection._publication):
                    continue
                if not projection.close():
                    return False
                self._commit_projections.remove(projection)
            for observation in tuple(self._store_observations.values()):
                publication = observation._projection._publication
                if not selected(publication):
                    continue
                if not self._core.retire_publication_observation(publication):
                    return False
                if not self._core.retire_publication_lookup(publication):
                    return False
            for transfer in tuple(reversed(self._observation_transfers)):
                if not selected(transfer._projection._publication):
                    continue
                if not transfer.close():
                    return False
                self._observation_transfers.remove(transfer)
            for key, observation in tuple(self._store_observations.items()):
                if selected(observation._projection._publication):
                    del self._store_observations[key]
            for fact in tuple(reversed(self._reader_facts)):
                if not selected(fact._projection._publication):
                    continue
                if not fact.close():
                    return False
                self._reader_facts.remove(fact)
            for held in tuple(reversed(self._payloads)):
                if not selected(held.publication):
                    continue
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
                if not selected(publication):
                    continue
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
            return True

    def close(self) -> bool:
        self._nominal()
        if (self._state_observing or any(not work.stopped for work in self._physical_work)
                or any(saved._preparing for saved in self._saved_result_reads)):
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
            # An interrupted constructor may have registered its physical
            # input without returning a named loan. Keep that exact ticket,
            # but still return the known children before asking the SAME
            # Root to close its pool. Only that Owner can retire the unnamed
            # buffer; uncertainty alone must not block reaching its cleanup.
            for saved_read in tuple(reversed(self._saved_result_reads)):
                if not saved_read.close():
                    return False
                self._saved_result_reads.remove(saved_read)
            for key, state_custody in tuple(self._run_state_custody.items()):
                if state_custody.output is not None:
                    if state_custody.output.family == 'run_state_append':
                        if not self._close_projection(state_custody.output):
                            return False
                        state_custody.output = None
                        del self._run_state_custody[key]
                        continue
                if not self._close_sdk_run_state_outputs(state_custody):
                    return False
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
            if not self._close_original_publications(tuple(reversed(self._publications))):
                return False
            for work in self._physical_work:
                original = work._invoke
                if (type(original) is _OriginalExecution and original.host is self
                        and original.run is work._owner and original.prepared_file
                        and original.publication is None and original.preflight is not None
                        and any(candidate is original.preflight for candidate in self._publication_preflights)):
                    work._nominal()
                    installation = self._installation
                    if installation is None or installation.binding._frame_epoch is not None:
                        return False
                    self._core.begin_file_prepublication_cleanup(original.preflight)
            for chunk in tuple(reversed(self._result_chunks)):
                if not self._core.close_result_chunk(chunk):
                    return False
                self._result_chunks.remove(chunk)
            for result in tuple(reversed(self._result_exports)):
                if not self._core.close_result_export(result):
                    return False
                self._result_exports.remove(result)
            for work in self._physical_work:
                original = work._invoke
                if (type(original) is _OriginalExecution and original.host is self
                        and original.run is work._owner and original.prepared_model):
                    work._nominal()
                    # The completed invocation still borrows this Model Task.
                    # Close only the barriers of this original after all its
                    # Result, payload and publication children have returned.
                    if not self._retire_original_publication_controls(original):
                        return False
                    if original.model_transfer is not None:
                        return False
            self._retire_original_tasks(tuple(reversed(self._tasks)))
            if self._tasks:
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
            for work in reversed(self._physical_work):
                execution = work._invoke
                if type(execution) is not _OriginalExecution or execution.mock_review_crypto is None:
                    continue
                work._nominal()
                if (not work.stopped or execution.host is not self
                        or execution.run is not work._owner):
                    return False
                # A worker-only native call must already have stopped. The same
                # child can return any remaining Wasm loans in this cleanup scope.
                if not execution.mock_review_crypto.close():
                    return False
                execution.mock_review_crypto = None
            use = self._effect_attestation_use
            if use is not None:
                if use.file_writer is not None:
                    if not use.file_writer.close():
                        return False
                    use.file_writer = None
                use.file_ack = None
                use.file_target = None
                if use.file_hold is not None:
                    if not self._core.close_workspace(use.file_hold):
                        return False
                    use.file_hold = None
            if use is not None and use.key is not None:
                if not use.key.close():
                    return False
                use.key = None
            if not self._close_saved_mock_review_crypto():
                return False
            for review in tuple(reversed(self._mock_review_reads)):
                if not self._close_original_mock_review_read(review):
                    return False
            for source in tuple(reversed(self._mock_effect_sources)):
                if not self._core.close_original_metadata(source):
                    return False
                self._mock_effect_sources.remove(source)
            for csv in tuple(reversed(self._local_csv_captures)):
                if csv.capture is not None and not csv.stop(csv.capture.handle):
                    return False
                try:
                    self._retire_original_csv_workspace(csv)
                except LocalProductCleanupPending:
                    return False
                self._local_csv_captures.remove(csv)
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
            if not self._client_check.close():
                return False
            for restored in tuple(reversed(tuple(self._runs._restorations.values()))):
                if not self._runs.close_restoration(restored):
                    return False
            for output in tuple(reversed(self._projections)):
                if not self._close_projection(output):
                    return False
                if self._pending_cancellation_write is output:
                    self._pending_cancellation_write = None
                    self._pending_cancellation_locator = None
            if self._configuration is not None:
                if not self._runs.close_configuration(self._configuration):
                    return False
                self._configuration = None
            if self._environment is not None:
                if not self._preparation.close_environment(self._environment):
                    return False
                self._environment = None
            if self._project_configuration is not None:
                # A failed fresh Mock bootstrap may still retain its original
                # Project child. Retire installation loans before that parent.
                if self._installation is not None:
                    if not self._installation.close():
                        return False
                    self._installation = None
                if not self._project_configuration.close():
                    return False
                self._project_configuration = None
            for workspace in tuple(reversed(self._mock_review_workspaces)):
                if not self._close_original_mock_review_workspace(workspace):
                    return False

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
            # Core has acknowledged its pool and actual physical retirement.
            # A refused/thrown close above retains this same constructor debt.
            self._uncertain_ticket = None
            self._physical_work.clear()
            self._run_restore_attempts.clear()
            return True
