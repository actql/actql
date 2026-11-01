"""One original Core/File/Store inspection; no independent recovery decisions."""
from collections.abc import Callable, Iterator
from contextlib import ExitStack, contextmanager
import sqlite3
from typing import Literal, TypeVar

from ._local_commit_projection import OriginalCommitProjection
from ._local_core import LocalResultProgress, _Input, _Output
from ._local_host_binding import OriginalHostBinding
from ._local_observation_transfer import OriginalObservationTransfer
from ._local_reader_facts import OriginalReaderFacts
from ._local_storage import ByteFence, ByteWrite, CapacityReservation, LocalByteStore, LocalStorageError, StoredBytes

_T = TypeVar('_T')


class OriginalStoreReconciliation:
    """Private transport of the original trusted Store's physical observation.

    The Host installs this Store under the original authority and supplies the
    genuine completed preparation, current publisher and original reader facts.
    This does not install trust, synthesize permission, compare scope/content or
    issue an index. The two original transfer workspaces must be reserved before
    prepare copies any rows. Core owns index/reference/full-chain admission and
    all work accounting. The existing SQLite reader enforces snapshot/read caps.

    A failed SQL query transports QueryFailed and then preserves the exception,
    original inputs and failed projection output through physical rollback. It
    is not NotFound. Missing dependent contracts are a broken stored chain, not
    absence of the original scoped key. Other failures retain their original
    classification and never become a successful or uncommitted publication.

    advance/finish expose only the existing Core progress/action, never Store
    ACK. AppendUnknown needs the original durable record; Adopt needs the actual
    stored index and original publication flow. The caller returns original Core
    borrows and explicitly cleans physical inputs/outputs after Store cleanup.
    No Source, Compute, Run, write, automatic lookup retry or replay is started.
    """

    def __init__(self, projection: OriginalCommitProjection, facts: tuple[OriginalReaderFacts, ...],
                 store: LocalByteStore,
                 originals: tuple[tuple[ByteFence, CapacityReservation], ...],
                 publisher: _Output, lookup: OriginalObservationTransfer,
                 response: OriginalObservationTransfer) -> None:
        if (type(projection) is not OriginalCommitProjection
                or type(facts) is not tuple or not facts
                or any(type(fact) is not OriginalReaderFacts or fact._projection is not projection
                       or fact._result != index
                       for index, fact in enumerate(facts))
                or len({id(fact) for fact in facts}) != len(facts)
                or type(store) is not LocalByteStore
                or type(lookup) is not OriginalObservationTransfer
                or type(response) is not OriginalObservationTransfer or lookup is response
                or lookup._projection is not projection or response._projection is not projection
                or lookup._publisher is not publisher or response._publisher is not publisher):
            raise ValueError('Invalid original Store reconciliation custody')
        with projection._core._lock:
            projection._ready()
            projection._core._owned_output(publisher, 'publisher')
            lookup._nominal()
            response._nominal()
            store._validate_originals(originals, set())
        self._original = self
        self._projection = projection
        self._facts = facts
        self._store = store
        self._originals = originals
        self._publisher: _Output | None = publisher
        self._lookup: OriginalObservationTransfer | None = lookup
        self._response: OriginalObservationTransfer | None = response
        self._entered = False
        self._active = False
        self._binding: OriginalHostBinding | None = None
        self._saved_current: Callable[[], None] | None = None
        # Physical write-attempt guards belong to this original Store custody,
        # not a replaceable transport wrapper or a Run/Read state machine.
        self._sdk_evidence_request_attempts: set[int] = set()
        self._sdk_evidence_key_attempts: set[str] = set()
        self._sdk_delivery_request_attempts: set[int] = set()
        self._sdk_delivery_key_attempts: set[str] = set()
        self._sdk_terminal_request_attempts: set[int] = set()
        self._sdk_terminal_key_attempts: set[str] = set()

    @classmethod
    def from_saved_read(cls, projection: OriginalCommitProjection,
                        facts: tuple[OriginalReaderFacts, ...], store: LocalByteStore,
                        originals: tuple[tuple[ByteFence, CapacityReservation], ...],
                        binding: OriginalHostBinding, *, current: Callable[[], None]) -> 'OriginalStoreReconciliation':
        """Use the already observed saved commit with its real current Store/FDs.

        No publisher, candidate validation transfer or executable Run is
        manufactured. Original physical reservation rows are reobserved by the
        same Store; the actual Core saved source still checks all semantics.
        """
        if (cls is not OriginalStoreReconciliation
                or type(projection) is not OriginalCommitProjection or not projection._saved
                or not callable(current)
                or type(store) is not LocalByteStore or type(binding) is not OriginalHostBinding
                or binding._core is not projection._core or binding._store is not store
                or type(facts) is not tuple or len(facts) != 1
                or any(type(fact) is not OriginalReaderFacts or fact._projection is not projection
                       for fact in facts)):
            raise ValueError('Invalid original saved Store read')
        with projection._core._lock:
            projection._ready()
            store._validate_originals(originals, set())
            value = cls.__new__(cls)
            value._original = value
            value._projection, value._facts = projection, facts
            value._store, value._originals = store, originals
            value._publisher = value._lookup = value._response = None
            value._entered, value._active, value._binding = True, False, binding
            value._saved_current = current
            value._sdk_evidence_request_attempts = set()
            value._sdk_evidence_key_attempts = set()
            value._sdk_delivery_request_attempts = set()
            value._sdk_delivery_key_attempts = set()
            value._sdk_terminal_request_attempts = set()
            value._sdk_terminal_key_attempts = set()
            return value

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Store reconciliation')

    @contextmanager
    def _serialized_facts(self) -> Iterator[None]:
        # Every original descriptor remains locked/pinned through the same
        # current Store snapshot and Owner adoption, including later ordinals.
        with ExitStack() as loans:
            for fact in self._facts:
                loans.enter_context(fact.serialized())
            yield

    def _before_lookup(self) -> None:
        if self._projection._saved:
            # The original saved source, record and all physical facts remain
            # independently current through this same Host/Store frame.
            if self._saved_current is None:
                raise ValueError('Original saved Host current port is unavailable')
            self._saved_current()
            self._projection._current()
            # Reobserve the already admitted immutable material here. The
            # selected Core action and post-consumer validators still perform
            # their complete original Source/Account/current checks.
            for fact in self._facts:
                fact.observe_original_material()
            self._saved_current()
            return
        if self._publisher is None:
            raise ValueError('Original live publisher is unavailable')
        if self._projection._core.publication_commit_result_count(
                self._projection._publication, self._projection._configuration) != len(self._facts):
            raise ValueError('Incomplete original Store reader inventory')
        for fact in self._facts:
            fact.before_lookup(self._publisher)
        self._validate_facts()

    def _validate_facts(self) -> None:
        for fact in self._facts:
            fact.validate()

    def _query(self, read: Callable[[str, Callable[[StoredBytes | None], object]], None],
               key: str, consume: Callable[[StoredBytes | None], object]) -> None:
        try:
            read(key, consume)
        except sqlite3.Error:
            # Run this while the original projection loan is still live. Do not
            # erase the physical failure or let the Store's latched reader pass.
            self._before_lookup()
            if self._response is not None:
                self._response.transfer_query_failure()
            raise

    def prepare(self, *, binding: OriginalHostBinding | None = None) -> None:
        """Forward actual same-snapshot bytes; this performs no semantic finish."""
        core = self._projection._core
        with core._lock:
            self._nominal()
            if self._lookup is None or self._response is None or self._publisher is None:
                raise ValueError('Saved read cannot prepare a live publication observation')
            if self._entered or self._active:
                raise RuntimeError('Original Store inspection cannot be repeated automatically')
            if binding is not None and (type(binding) is not OriginalHostBinding
                    or binding._core is not core or binding._store is not self._store):
                raise ValueError('Foreign original Store current binding')
            for transfer in (self._lookup, self._response):
                transfer._ready()
                if (transfer.pending_workspace is None or transfer.pending_input is not None
                        or transfer.pending_sources):
                    raise RuntimeError('Original Store inspection requires fresh reserved transfers')
            self._binding = binding
            self._entered = self._active = True
            try:
                with self._serialized_facts():
                    if binding is None:
                        self._store.inspect_publication_projected_attached(
                            self._inspect, self._originals,
                            current=lambda: self._before_lookup())
                    else:
                        with binding.fenced() as fences:
                            self._store.inspect_publication_projected_inspected(
                                self._inspect, self._originals, fences,
                                namespace=lambda reader, consume:
                                    binding.inspect_reader(reader, lambda _: consume()),
                                current=binding._current_observer,
                                before_lookup=lambda: self._before_lookup())
            finally:
                self._active = False

    def _inspect(self, read: Callable[[str, Callable[[StoredBytes | None], object]], None]) -> None:
        lookup, response = self._lookup, self._response
        if lookup is None or response is None:
            raise ValueError('Saved read has no live publication lookup transfer')
        reference: _Input | None = None
        index: _Input | None = None
        def reference_row(row: StoredBytes | None) -> None:
            nonlocal reference
            if row is None:
                response.transfer_not_found()
            else:
                reference = lookup.retain_source(row.payload)
        self._projection.project_index_lookup_key(
            lambda key: self._query(read, key, reference_row))
        if reference is None:
            return
        index_key = ''
        def select_index(raw: bytes) -> None:
            nonlocal index_key
            # Closed physical CID address only; no scope/key preimage or stored
            # index parsing. Core still verifies the actual body/self reference.
            index_key = LocalByteStore.namespaced_key(
                'publication_contract', self._projection._address(raw, index_key=False))
        lookup.consume_source(reference, select_index)
        def index_row(row: StoredBytes | None) -> None:
            nonlocal index
            if row is None:
                raise LocalStorageError('Original stored index body is missing')
            index = lookup.retain_source(row.payload)
        self._query(read, index_key, index_row)
        if index is None:
            raise LocalStorageError('Original stored index transfer is incomplete')
        self._before_lookup()
        lookup.transfer_lookup_inputs(reference, index)
        def retain_index(raw: bytes) -> None:
            response.retain_source(raw)
        lookup.consume_source(index, retain_index)
        actual_index = response.pending_sources[0]
        fields: tuple[Literal['request', 'attempt'], ...] = ('request', 'attempt')
        for field in fields:
            def contract_row(row: StoredBytes | None) -> None:
                if row is None:
                    raise LocalStorageError('Original stored publication contract is missing')
                response.retain_source(row.payload)
            self._projection.project_stored_contract_lookup_key(
                field, lambda key: self._query(read, key, contract_row))
        _, request, attempt = response.pending_sources
        self._before_lookup()
        response.transfer_stored_inputs(request, attempt, actual_index)

    def advance(self, quantum: int) -> LocalResultProgress:
        """Advance the same Owner's total work budget under current physical facts."""
        self._projection._require_live()
        core = self._projection._core
        with core._lock:
            self._nominal()
            if self._active or not self._entered:
                raise RuntimeError('Original Store observation transfer is not available')
            with self._serialized_facts():
                def consume() -> LocalResultProgress:
                    self._before_lookup()
                    progress = core.advance_publication_observation(
                        self._projection._publication, self._projection._configuration, quantum)
                    self._validate_facts()
                    return progress
                return self._current_call(consume)

    def finish(self) -> Literal['append_unknown', 'confirm_uncommitted_failure', 'adopt_committed_index']:
        """Read the Core action after complete original chain/current checks; no ACK."""
        self._projection._require_live()
        core = self._projection._core
        with core._lock:
            self._nominal()
            if self._active or not self._entered:
                raise RuntimeError('Original Store observation transfer is not available')
            with self._serialized_facts():
                def consume() -> Literal['append_unknown', 'confirm_uncommitted_failure', 'adopt_committed_index']:
                    self._before_lookup()
                    action = core.finish_publication_observation(
                        self._projection._publication, self._projection._configuration)
                    self._validate_facts()
                    return action
                return self._current_call(consume)

    def project_observed_index(self, consume: Callable[[bytes, bytes], object]) -> None:
        """Transport the actual admitted index under the same complete File/current frame.

        The existing Core export refuses unfinished, absent, failed or retired
        observations and independently rechecks the original publisher. No action
        code or Python comparison is elevated to admission, ACK or Run success.
        """
        if not callable(consume):
            raise ValueError('Invalid original observed index consumer')
        self._projection._require_live()
        core = self._projection._core
        with core._lock:
            self._nominal()
            if self._active or not self._entered:
                raise RuntimeError('Original Store observation transfer is not available')
            with self._serialized_facts():
                def project() -> None:
                    self._before_lookup()
                    def transfer(identity: bytes, body: bytes) -> None:
                        self._validate_facts()
                        if consume(identity, body) is not None:
                            raise ValueError('Invalid synchronous observed index consumer result')
                        # Failed consumers/current checks retain the same output
                        # reservations until explicit original-loan cleanup.
                        self._validate_facts()
                    self._projection.project_observed_index(transfer)
                self._current_call(project)

    def project_run_state(self, observed_at: _Input,
                          consume: Callable[[bytes], object]) -> None:
        """Keep all original File facts/current Store through Core observation.

        Core independently checks the completed stored chain and Account read.
        No action, physical COMMIT return or Python comparison supplies status.
        """
        if not callable(consume):
            raise ValueError('Invalid original Run observation consumer')
        self._projection._require_live()
        core = self._projection._core
        with core._lock:
            self._nominal()
            core._owned_input(observed_at)
            if self._active or not self._entered:
                raise RuntimeError('Original Store observation transfer is not available')
            with self._serialized_facts():
                def project() -> None:
                    self._before_lookup()
                    def transfer(raw: bytes) -> None:
                        self._validate_facts()
                        if consume(raw) is not None:
                            raise ValueError('Invalid synchronous Run observation consumer result')
                        self._validate_facts()
                    self._projection.project_run_state(observed_at, transfer)
                self._current_call(project)

    def project_sdk_read_original(self, request: _Input, original_run: int,
                                  ordinal: int,
                                  consume: Callable[[bytes, bytes], object]) -> None:
        """Use the same original six File facts and actual current Store frame.

        Core chooses the saved finite packet/selection and checks its current
        independent publisher and Account permissions. This physical holder
        creates no scope, Allow, grant, Run state or Store acknowledgement.
        """
        if not callable(consume):
            raise ValueError('Invalid original SDK read consumer')
        core = self._projection._core
        with core._lock:
            self._nominal()
            core._owned_input(request)
            if self._active or not self._entered:
                raise RuntimeError('Original Store observation transfer is not available')
            with self._serialized_facts():
                def project() -> None:
                    self._before_lookup()
                    def transfer(identity: bytes, body: bytes) -> None:
                        self._validate_facts()
                        if consume(identity, body) is not None:
                            raise ValueError('Invalid synchronous SDK original consumer result')
                        self._validate_facts()
                    self._projection.project_sdk_read_original(request, original_run, ordinal, transfer)
                self._current_call(project)

    def project_sdk_read_evidence_decision(self, request: _Input, original_run: int,
                                          consume: Callable[[bytes], object]) -> None:
        self._project_sdk_read_store(request, lambda transfer:
            self._projection.project_sdk_read_evidence_decision(request, original_run, transfer), consume)

    def project_sdk_read_evidence(self, request: _Input, original_run: int,
                                  consume: Callable[[ByteWrite], object]) -> None:
        self._project_sdk_read_store(request, lambda transfer:
            self._projection.project_sdk_read_evidence(request, original_run, transfer), consume)

    def project_sdk_read_grant(self, request: _Input, original_run: int,
                               consume: Callable[[ByteWrite], object]) -> None:
        self._project_sdk_read_store(request, lambda transfer:
            self._projection.project_sdk_read_grant(request, original_run, transfer), consume)

    def project_sdk_delivery_lookup(self, request: _Input, original_run: int,
                                    consume: Callable[[bytes], object]) -> None:
        self._project_sdk_read_store(request, lambda transfer:
            self._projection.project_sdk_delivery_lookup(request, original_run, transfer), consume)

    def _project_sdk_read_store(self, request: _Input,
                                produce: Callable[[Callable[[_T], None]], None],
                                consume: Callable[[_T], object]) -> None:
        """Keep all original reader facts and current Store around each projection.

        The physical consumer does not choose scope, authority, comparison or
        acceptance. Failures retain exact output/request/reader custody.
        """
        if not callable(consume):
            raise ValueError('Invalid original SDK read Store consumer')
        core = self._projection._core
        with core._lock:
            self._nominal()
            core._owned_input(request)
            if self._active or not self._entered:
                raise RuntimeError('Original Store observation transfer is not available')
            with self._serialized_facts():
                def project() -> None:
                    self._before_lookup()
                    def transfer(value: _T) -> None:
                        self._validate_facts()
                        if consume(value) is not None:
                            raise ValueError('Invalid synchronous SDK read Store consumer result')
                        self._validate_facts()
                    produce(transfer)
                self._current_call(project)

    def _current_call(self, consume: Callable[[], _T]) -> _T:
        # File/Core locks are held by the caller before the fresh Store frame.
        # Reuse the original binding after prepare; never manufacture a grant
        # from its earlier read or from physical COMMIT success.
        if self._binding is None:
            return consume()
        captured: list[_T] = []
        self._binding.inspect(lambda _: captured.append(consume()))
        if len(captured) != 1:
            raise RuntimeError('Incomplete original Store current observation')
        return captured[0]
