"""Borrow original Core fields for a synchronous physical Store consumer."""
from collections.abc import Callable, Iterator
from contextlib import contextmanager
from typing import Literal

from ._local_core import LocalCore, LocalCoreError, _Input, _Output
from ._local_storage import ByteWrite, LocalByteStore


class OriginalCommitProjection:
    """Transport holder of at most two original Core output loans.

    This neither commits nor interprets a Run. The trusted Host uses this caller
    under its Core-to-Store lock order, with separately reserved SQLite/descriptor
    workspace, original payload fences, schema/facts validation, and the original
    current publisher port. Those responsibilities are not provided by this view.

    Success retires each pair only after synchronous consumption completes and
    temporary field references are gone. The physical consumer must not retain
    the borrowed write or its bytes after return. Any failure leaves the exact loans here
    and in Core. Finish physical transaction/consumer cleanup and discard retained
    failure tracebacks before close(); close releases only these original outputs,
    never the publication, its Source/Result parents, or the Run. No automatic
    replacement projection or physical write is attempted after failure.
    """

    def __init__(self, core: LocalCore, publication: _Output,
                 current_configuration: int, *, cleanup: Callable[[], bool]) -> None:
        if type(core) is not LocalCore or not callable(cleanup):
            raise ValueError('Invalid original Local commit projection')
        with core._lock:
            core._publication_configuration(publication, current_configuration)
        self._saved = False
        self._core = core
        self._publication = publication
        self._configuration = current_configuration
        self._cleanup = cleanup
        self._outputs: list[_Output] = []
        self._projecting = False
        self._closing = False

    @classmethod
    def from_saved_read(cls, core: LocalCore, original: _Output,
                        current_configuration: int, *,
                        cleanup: Callable[[], bool]) -> 'OriginalCommitProjection':
        """Borrow the same nominal saved-read parent; create no live publication.

        Construction is nominal only. Every use still enters the actual Host
        Store frame and Core's current/snapshot checks. This variant cannot
        project publication writes or authorize a publisher.
        """
        if (cls is not OriginalCommitProjection or type(core) is not LocalCore
                or not callable(cleanup) or type(current_configuration) is not int
                or not 0 < current_configuration < 2**31):
            raise ValueError('Invalid original saved read projection')
        with core._lock:
            core._owned_output(original, 'submission_lookup')
            value = cls.__new__(cls)
            value._saved = True
            value._core, value._publication = core, original
            value._configuration, value._cleanup = current_configuration, cleanup
            value._outputs = []
            value._projecting = value._closing = False
            return value

    def _require_live(self) -> None:
        if self._saved:
            raise ValueError('Saved read cannot issue a live publication operation')

    @property
    def pending_outputs(self) -> tuple[_Output, ...]:
        """Exact cleanup handles, not serialized authority or replay permission."""
        with self._core._lock:
            return tuple(self._outputs)

    def retain_sdk_delivery_custody(self, output: _Output) -> None:
        """Move one exact active loan to its already registered Store holder.

        This changes physical cleanup custody only. The Core export validates
        its genuine first preparation when its transport is retired; neither
        this move nor the caller's physical COMMIT creates read permission.
        """
        with self._core._lock:
            self._core._owned_output(output, 'publication_commit_export')
            if (not self._projecting or self._closing or len(self._outputs) != 1
                    or self._outputs[0] is not output):
                raise ValueError('Foreign original SDK delivery output custody')
            self._outputs.pop()

    def count(self) -> int:
        self._require_live()
        with self._core._lock:
            self._ready()
            return self._core.publication_commit_material_count(
                self._publication, self._configuration)

    def storage_count(self) -> int:
        """Count original inventory, Result schemas and one scoped index reference.

        This is the number of physical projection operations, including reused
        identities, not a count of newly written records or a publication ACK.
        """
        with self._core._lock:
            self._ready()
            return sum(self._storage_counts()) + 1

    def _storage_counts(self) -> tuple[int, int]:
        self._require_live()
        materials = self._core.publication_commit_material_count(
            self._publication, self._configuration)
        results = self._core.publication_commit_result_count(
            self._publication, self._configuration)
        if materials + results + 1 >= 2**31:
            raise LocalCoreError('original_commit_storage_count', -33)
        return materials, results

    def project_storage_entry(self, ordinal: int, consume: Callable[[ByteWrite], object], *,
                              expected_generation: int | None = None) -> None:
        """Consume exactly one original field pair in physical storage order.

        Inventory uses its original Owner ordinal, then each original Result's
        schema, then the Owner's scoped index key and index CID. No contract list
        or schema deduplication is built here. The physical Store retains exact
        byte-reuse/conflict decisions, and every binding/fence/current publisher
        must still be checked separately by the trusted Host before COMMIT.
        """
        if type(ordinal) is not int or not 0 <= ordinal < 2**31:
            raise ValueError('Invalid original Local storage projection ordinal')
        with self._core._lock:
            self._ready()
            materials, results = self._storage_counts()
            if ordinal < materials:
                self.project_contract(ordinal, consume, expected_generation=expected_generation)
            elif ordinal < materials + results:
                self.project_schema(ordinal - materials, consume,
                                    expected_generation=expected_generation)
            elif ordinal == materials + results:
                self.project_index_reference(consume, expected_generation=expected_generation)
            else:
                raise ValueError('Original Local storage projection ordinal is out of range')

    @contextmanager
    def serialized(self) -> Iterator[None]:
        """Hold Core before entering the physical Store transaction/lock.

        This changes no Owner fact. It prevents a Store-to-Core callback from
        competing with a Core-to-Store operation in another Host thread.
        """
        with self._core._lock:
            self._ready()
            yield

    def authorize_commit(self, publisher: _Output) -> None:
        """Call the original publisher stage; no grant, write or ACK is made."""
        self._require_live()
        with self._core._lock:
            self._ready()
            self._core.authorize_publisher(
                publisher, self._configuration, stage='commit',
                publication=self._publication)

    def validate_payload_binding(self, record: _Output, result: int,
                                 binding_index: int) -> None:
        """Read original Core binding facts, without Store I/O or an ACK.

        This must not replace the Host's current physical-generation fence or
        current publisher stage. Failure keeps the same original handles.
        """
        with self._core._lock:
            self._current()
            if self._saved:
                self._core.validate_saved_payload_binding(
                    self._publication, record, self._configuration, result, binding_index)
            else:
                self._core.validate_publication_commit_payload_binding(
                    self._publication, record, self._configuration, result, binding_index)

    def project_contract(self, ordinal: int, consume: Callable[[ByteWrite], object], *,
                         expected_generation: int | None = None) -> None:
        """Consume original identity/body without recreating or parsing a contract."""
        self._project(ordinal, False, consume, expected_generation)

    def validate_reader_facts(self, record: _Output, observation: _Input,
                              result: int, binding_index: int) -> None:
        """Compose the two existing complete public validators in order.

        The caller retains the same sealed input and physical fences. This
        ABI78 path is not the private combined guest export: snapshot current
        and binding checks remain in their original Core implementations.
        """
        with self._core._lock:
            self.validate_payload_binding(record, result, binding_index)
            self._core.validate_payload_snapshot(
                record, observation, self._configuration)

    def project_index_reference(self, consume: Callable[[ByteWrite], object], *,
                                expected_generation: int | None = None) -> None:
        """Consume the Owner's scoped key and original index CID, not JSON body."""
        self._project(7, True, consume, expected_generation)

    def project_index_lookup_key(self, consume: Callable[[str], object]) -> None:
        """Borrow only the Core-issued scoped key for a read-only inspection.

        No candidate index CID/body or CAS expectation is delivered. The trusted
        Host checks original File/six facts/current publisher, then uses this
        key in the same Store read snapshot. It forwards actual stored bytes to
        Core; an older valid stored attempt must not be replaced by the candidate.
        The synchronous consumer must not retain this projection loan or key.
        Any failure retains the same original output for explicit cleanup.
        """
        self._lookup_key(consume, None)

    def project_stored_contract_lookup_key(
            self, field: Literal['request', 'attempt'], consume: Callable[[str], object]) -> None:
        """Borrow a Core-selected actual stored request/attempt lookup key.

        The same original index input/current publisher is retained by Core.
        Python supplies no scope or candidate identity and does not parse the
        stored index. Consume this key synchronously under the original File
        fences and Store snapshot; raw row adoption still belongs to Core.
        """
        if type(field) is not str or field not in ('request', 'attempt'):
            raise ValueError('Invalid original stored publication reference field')
        self._lookup_key(consume, field)

    def _lookup_key(self, consume: Callable[[str], object],
                    field: Literal['request', 'attempt'] | None) -> None:
        if not callable(consume):
            raise ValueError('Invalid original Local index lookup consumer')
        self._require_live()
        with self._core._lock:
            self._ready()
            self._projecting = True
            try:
                output = self._output()
                if field is None:
                    self._core.produce_publication_commit_index_key(output, self._configuration)
                else:
                    self._core.produce_publication_lookup_reference(
                        output, self._configuration, field=field)
                raw = self._core.read_publication_commit_material(output)
                key = LocalByteStore.namespaced_key(
                    'public_index' if field is None else 'publication_contract',
                    self._address(raw, index_key=field is None))
                if consume(key) is not None:
                    raise ValueError('Invalid synchronous Local index lookup consumer result')
                del key, raw
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_commit_projection_cleanup', -9)
            finally:
                self._projecting = False

    def project_schema(self, result: int, consume: Callable[[ByteWrite], object], *,
                       expected_generation: int | None = None) -> None:
        """Consume original receipt identity/wire into the schema namespace.

        This transports the schema. The original physical binding validation
        and current publisher/commit ACK remain separate Host/Owner obligations.
        """
        self._project(result, False, consume, expected_generation, schema=True)

    def project_observed_index(self, consume: Callable[[bytes, bytes], object]) -> None:
        """Borrow the actual Core-validated stored identity/body, never the candidate.

        The original observation/publisher must remain live. The caller retains
        all File/current facts around this synchronous transport. These bytes
        are not a durable ACK or a completed Run/Result wire response.
        """
        if not callable(consume):
            raise ValueError('Invalid original observed index consumer')
        self._require_live()
        with self._core._lock:
            self._ready()
            self._projecting = True
            try:
                self._consume_observed_index(consume)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_observed_index_cleanup', -9)
            finally:
                self._projecting = False

    def project_run_state(self, observed_at: _Input,
                          consume: Callable[[bytes], object]) -> None:
        """Borrow original Core RunState bytes under the caller's current frame.

        The original clock input remains owned separately and is borrowed by
        Core until output cleanup. The consumer must move bytes to its own
        accounted response before returning; it cannot retain this loan.
        """
        if not callable(consume):
            raise ValueError('Invalid original Run observation consumer')
        self._require_live()
        with self._core._lock:
            self._core._owned_input(observed_at)
            self._ready()
            self._projecting = True
            try:
                self._consume_run_state(observed_at, consume)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_run_state_cleanup', -9)
            finally:
                self._projecting = False

    def project_sdk_read_original(self, request: _Input, original_run: int,
                                  ordinal: int,
                                  consume: Callable[[bytes, bytes], object]) -> None:
        """Borrow one Core-issued SDK original pair, not a grant or ACK.

        The caller holds the actual same File/Store/current observation and
        original Run custody. Failed projection/consumer/cleanup keeps these
        same output loans; the request remains borrowed by Core until cleanup.
        """
        if (not callable(consume) or type(original_run) is not int
                or not 0 < original_run < 2**31
                or type(ordinal) is not int or not 0 <= ordinal <= 2):
            raise ValueError('Invalid original SDK read consumer')
        with self._core._lock:
            self._core._owned_input(request)
            self._ready()
            self._projecting = True
            try:
                self._consume_sdk_read_original(request, original_run, ordinal, consume)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_sdk_read_cleanup', -9)
            finally:
                self._projecting = False

    def _consume_sdk_read_original(self, request: _Input, original_run: int,
                                   ordinal: int,
                                   consume: Callable[[bytes, bytes], object]) -> None:
        identity = self._output()
        self._core.produce_publication_sdk_read_original(
            identity, request, original_run, self._configuration, ordinal, field='identity')
        raw_identity = self._core.read_publication_commit_material(identity)
        self._address(raw_identity, index_key=False)
        body = self._output()
        self._core.produce_publication_sdk_read_original(
            body, request, original_run, self._configuration, ordinal, field='wire')
        raw_body = self._core.read_publication_commit_material(body)
        if consume(raw_identity, raw_body) is not None:
            raise ValueError('Invalid synchronous SDK original consumer result')

    def project_sdk_read_evidence_decision(self, request: _Input, original_run: int,
                                          consume: Callable[[bytes], object]) -> None:
        """Transport Core's closed same-Store append/retained proposal only."""
        if (not callable(consume) or type(original_run) is not int
                or not 0 < original_run < 2**31):
            raise ValueError('Invalid original SDK evidence decision consumer')
        with self._core._lock:
            self._core._owned_input(request)
            self._ready()
            self._projecting = True
            try:
                self._consume_sdk_read_decision(request, original_run, consume)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_sdk_evidence_decision_cleanup', -9)
            finally:
                self._projecting = False

    def _consume_sdk_read_decision(self, request: _Input, original_run: int,
                                   consume: Callable[[bytes], object]) -> None:
        output = self._output()
        self._core.produce_publication_sdk_read_evidence_decision(
            output, request, original_run, self._configuration)
        raw = self._core.read_publication_commit_material(output)
        if consume(raw) is not None:
            raise ValueError('Invalid synchronous SDK evidence decision consumer result')

    def project_sdk_delivery_lookup(self, request: _Input, original_run: int,
                                    consume: Callable[[bytes], object]) -> None:
        """Borrow an existing delivery response, never retry or payload authority."""
        if (not callable(consume) or type(original_run) is not int
                or not 0 < original_run < 2**31):
            raise ValueError('Invalid original SDK delivery lookup consumer')
        with self._core._lock:
            self._core._owned_input(request)
            self._ready()
            self._projecting = True
            try:
                self._consume_sdk_delivery_lookup(request, original_run, consume)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_sdk_delivery_lookup_cleanup', -9)
            finally:
                self._projecting = False

    def _consume_sdk_delivery_lookup(self, request: _Input, original_run: int,
                                     consume: Callable[[bytes], object]) -> None:
        output = self._output()
        self._core.produce_publication_sdk_delivery_lookup(
            output, request, original_run, self._configuration)
        raw = self._core.read_publication_commit_material(output)
        if consume(raw) is not None:
            raise ValueError('Invalid synchronous SDK delivery lookup consumer result')

    def project_sdk_read_delivery_storage(self, request: _Input, original_run: int,
                                         consume: Callable[[bytes], object]) -> None:
        """Borrow original closed CAS materials; not a use/ACK or read stream."""
        if (not callable(consume) or type(original_run) is not int
                or not 0 < original_run < 2**31):
            raise ValueError('Invalid original SDK delivery storage consumer')
        with self._core._lock:
            self._core._owned_input(request)
            self._ready()
            self._projecting = True
            try:
                self._consume_sdk_delivery_storage(request, original_run, consume)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_sdk_delivery_storage_cleanup', -9)
            finally:
                self._projecting = False

    def _consume_sdk_delivery_storage(self, request: _Input, original_run: int,
                                      consume: Callable[[bytes], object]) -> None:
        output = self._output()
        self._core.produce_publication_sdk_read_delivery_storage(
            output, request, original_run, self._configuration)
        raw = self._core.read_publication_commit_material(output)
        if consume(raw) is not None:
            raise ValueError('Invalid synchronous SDK delivery storage consumer result')

    def project_sdk_read_evidence(self, request: _Input, original_run: int,
                                  consume: Callable[[ByteWrite], object]) -> None:
        """Project the original evidence packet to its Core-selected key."""
        self._project_sdk_read_entry(request, original_run, 'evidence', consume)

    def project_sdk_read_grant(self, request: _Input, original_run: int,
                               consume: Callable[[ByteWrite], object]) -> None:
        """Project an issued grant after Core's same-Store evidence validation.

        Persisting this grant, usage, delivery and terminal receipts remain
        separate existing Owner operations, never inferred from these bytes.
        """
        self._project_sdk_read_entry(request, original_run, 'grant', consume)

    def _project_sdk_read_entry(self, request: _Input, original_run: int,
                                kind: Literal['evidence', 'grant'],
                                consume: Callable[[ByteWrite], object]) -> None:
        if (not callable(consume) or type(original_run) is not int
                or not 0 < original_run < 2**31):
            raise ValueError('Invalid original SDK read entry consumer')
        with self._core._lock:
            self._core._owned_input(request)
            self._ready()
            self._projecting = True
            try:
                self._consume_sdk_read_entry(request, original_run, kind, consume)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_sdk_read_entry_cleanup', -9)
            finally:
                self._projecting = False

    def _consume_sdk_read_entry(self, request: _Input, original_run: int,
                                kind: Literal['evidence', 'grant'],
                                consume: Callable[[ByteWrite], object]) -> None:
        producer = (self._core.produce_publication_sdk_read_evidence if kind == 'evidence'
                    else self._core.produce_publication_sdk_read_grant)
        identity = self._output(maximum=71)
        producer(identity, request, original_run, self._configuration, field='identity')
        address = self._address(self._core.read_publication_commit_material(identity), index_key=False)
        payload = self._output()
        producer(payload, request, original_run, self._configuration, field='wire')
        raw = self._core.read_publication_commit_material(payload)
        key = LocalByteStore.namespaced_key(
            'client_local_read_evidence' if kind == 'evidence' else 'publication_contract', address)
        if consume(ByteWrite(key, None, raw)) is not None:
            raise ValueError('Invalid synchronous SDK read entry consumer result')

    def _consume_run_state(self, observed_at: _Input,
                           consume: Callable[[bytes], object]) -> None:
        output = self._output()
        self._core.produce_publication_observed_run_state(
            output, observed_at, self._configuration)
        raw = self._core.read_publication_commit_material(output)
        if consume(raw) is not None:
            raise ValueError('Invalid synchronous Run observation consumer result')

    def _consume_observed_index(self, consume: Callable[[bytes, bytes], object]) -> None:
        # Drop temporary field references before retiring their reservations,
        # matching the existing synchronous original-material projection.
        identity = self._output(maximum=71)
        self._core.produce_publication_observed_index(
            identity, self._configuration, field='identity')
        raw_identity = self._core.read_publication_commit_material(identity)
        self._address(raw_identity, index_key=False)
        body = self._output()
        self._core.produce_publication_observed_index(
            body, self._configuration, field='wire')
        raw_body = self._core.read_publication_commit_material(body)
        if consume(raw_identity, raw_body) is not None:
            raise ValueError('Invalid synchronous observed index consumer result')

    def _ready(self) -> None:
        self._current()
        if self._projecting or self._outputs:
            raise RuntimeError('Local commit projection is closing or cleanup is pending')

    def _current(self) -> None:
        """Read-only nominal check even while original projection loans are live.

        This starts no new projection or cleanup. The caller holds Core/File
        locks, and existing Core checks still decide current binding facts.
        """
        if self._closing or (self._outputs and not self._projecting):
            raise RuntimeError('Local commit projection is closing or cleanup is pending')
        if self._saved:
            self._core._owned_output(self._publication, 'submission_lookup')
        else:
            self._core._publication_configuration(self._publication, self._configuration)
        for output in self._outputs:
            self._core._owned_output(output, 'publication_commit_export')

    def _project(self, ordinal: int, index_reference: bool,
                 consume: Callable[[ByteWrite], object], generation: int | None, *,
                 schema: bool = False) -> None:
        if (type(ordinal) is not int or not 0 <= ordinal < 2**31
                or not callable(consume)
                or (generation is not None and (type(generation) is not int
                                                or not 0 <= generation < 2**63 - 1))):
            raise ValueError('Invalid original Local commit projection controls')
        self._require_live()
        with self._core._lock:
            self._ready()
            self._projecting = True
            try:
                # _consume returns without retaining field bytes or descriptors.
                # On failure its traceback can retain them; keep their reservations
                # until the Host resolves that physical failure and explicitly closes.
                self._consume(ordinal, index_reference, consume, generation, schema=schema)
                self._retire_outputs()
                if self._outputs:
                    raise LocalCoreError('original_commit_projection_cleanup', -9)
            finally:
                self._projecting = False

    def _output(self, *, maximum: int = 1_048_576) -> _Output:
        value = (self._core.reserve_saved_result_export(self._publication, cleanup=self._cleanup,
                                                      maximum=maximum)
                 if self._saved else self._core.reserve_publication_commit_export(
                     self._publication, cleanup=self._cleanup, maximum=maximum))
        self._outputs.append(value)
        return value

    @staticmethod
    def _address(raw: bytes, *, index_key: bool) -> str:
        # Closed physical address fields only. Their identity/preimage comes
        # from the original Owner; Python does not compute or certify a CID.
        suffix = raw if index_key else raw[7:]
        if (len(raw) != (64 if index_key else 71)
                or (not index_key and raw[:7] != b'sha256:')
                or any(byte not in b'0123456789abcdef' for byte in suffix)):
            raise LocalCoreError('original_commit_projection_address', -33)
        return raw.decode('ascii')

    def _consume(self, ordinal: int, index_reference: bool,
                 consume: Callable[[ByteWrite], object], generation: int | None, *,
                 schema: bool = False) -> None:
        core = self._core
        address_output = self._output(maximum=64 if index_reference else 71)
        if schema:
            core.produce_publication_commit_schema(
                address_output, self._configuration, ordinal, field='identity')
        elif index_reference:
            core.produce_publication_commit_index_key(address_output, self._configuration)
        else:
            core.produce_publication_commit_material(
                address_output, self._configuration, ordinal, field='identity')
        raw_address = core.read_publication_commit_material(address_output)
        address = self._address(raw_address, index_key=index_reference)
        key = LocalByteStore.namespaced_key(
            ('result_schema' if schema else
             'public_index' if index_reference else 'publication_contract'), address)
        payload_output = self._output()
        if schema:
            core.produce_publication_commit_schema(
                payload_output, self._configuration, ordinal, field='wire')
        else:
            core.produce_publication_commit_material(
                payload_output, self._configuration, ordinal,
                field='identity' if index_reference else 'wire')
        payload = core.read_publication_commit_material(payload_output)
        if index_reference:
            self._address(payload, index_key=False)
        if consume(ByteWrite(key, generation, payload)) is not None:
            raise ValueError('Invalid synchronous Local commit consumer result')

    def _retire_outputs(self) -> None:
        for value in tuple(reversed(self._outputs)):
            if self._core.close_publication_commit_export(value):
                self._outputs.remove(value)

    def retire_outputs(self) -> bool:
        """Explicit same-loan cleanup after physical failure, retaining the view.

        The trusted caller first resolves transaction/consumer cleanup and drops
        retained byte references/tracebacks. A failure keeps these exact outputs
        and reservations. Success reclaims no Source/Result parent and grants no
        lookup, retry, submit or commit permission; the next Owner call still
        checks its original identity and current authority. This does not reopen
        a projection whose terminal close has already begun.
        """
        with self._core._lock:
            if self._projecting:
                raise RuntimeError('Local commit projection is still in use')
            self._retire_outputs()
            return not self._outputs

    def close(self) -> bool:
        """Retry original output cleanup only; never cancel, submit or commit."""
        with self._core._lock:
            if self._projecting:
                raise RuntimeError('Local commit projection is still in use')
            self._closing = True
            self._retire_outputs()
            return not self._outputs


# Definition-time provenance for the fixed original reconciliation driver.
from ._local_prepare_provenance import _capture_prepare_methods
_PREPARE_METHODS = (
    _capture_prepare_methods(OriginalCommitProjection, (
        '_address', '_current', '_lookup_key',
        '_output', '_ready', '_require_live',
        '_retire_outputs', 'project_index_lookup_key', 'project_stored_contract_lookup_key',
        'validate_payload_binding', 'validate_reader_facts',
    )),
)
