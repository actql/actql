"""One original Core/File/Store inspection; no independent recovery decisions."""
from collections.abc import Callable
import sqlite3
from typing import Literal

from ._local_commit_projection import OriginalCommitProjection
from ._local_core import LocalResultProgress, _Input, _Output
from ._local_observation_transfer import OriginalObservationTransfer
from ._local_reader_facts import OriginalReaderFacts
from ._local_storage import ByteFence, CapacityReservation, LocalByteStore, LocalStorageError, StoredBytes


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

    def __init__(self, projection: OriginalCommitProjection, facts: OriginalReaderFacts,
                 store: LocalByteStore,
                 originals: tuple[tuple[ByteFence, CapacityReservation], ...],
                 publisher: _Output, lookup: OriginalObservationTransfer,
                 response: OriginalObservationTransfer) -> None:
        if (type(projection) is not OriginalCommitProjection
                or type(facts) is not OriginalReaderFacts or facts._projection is not projection
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
        self._publisher = publisher
        self._lookup = lookup
        self._response = response
        self._entered = False
        self._active = False

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original Store reconciliation')

    def _query(self, read: Callable[[str, Callable[[StoredBytes | None], object]], None],
               key: str, consume: Callable[[StoredBytes | None], object]) -> None:
        try:
            read(key, consume)
        except sqlite3.Error:
            # Run this while the original projection loan is still live. Do not
            # erase the physical failure or let the Store's latched reader pass.
            self._facts.before_lookup(self._publisher)
            self._response.transfer_query_failure()
            raise

    def prepare(self) -> None:
        """Forward actual same-snapshot bytes; this performs no semantic finish."""
        core = self._projection._core
        with core._lock:
            self._nominal()
            if self._entered or self._active:
                raise RuntimeError('Original Store inspection cannot be repeated automatically')
            for transfer in (self._lookup, self._response):
                transfer._ready()
                if (transfer.pending_workspace is None or transfer.pending_input is not None
                        or transfer.pending_sources):
                    raise RuntimeError('Original Store inspection requires fresh reserved transfers')
            self._entered = self._active = True
            try:
                with self._facts.serialized():
                    self._store.inspect_publication_projected_attached(
                        self._inspect, self._originals,
                        current=lambda: self._facts.before_lookup(self._publisher))
            finally:
                self._active = False

    def _inspect(self, read: Callable[[str, Callable[[StoredBytes | None], object]], None]) -> None:
        reference: _Input | None = None
        index: _Input | None = None
        def reference_row(row: StoredBytes | None) -> None:
            nonlocal reference
            if row is None:
                self._response.transfer_not_found()
            else:
                reference = self._lookup.retain_source(row.payload)
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
        self._lookup.consume_source(reference, select_index)
        def index_row(row: StoredBytes | None) -> None:
            nonlocal index
            if row is None:
                raise LocalStorageError('Original stored index body is missing')
            index = self._lookup.retain_source(row.payload)
        self._query(read, index_key, index_row)
        if index is None:
            raise LocalStorageError('Original stored index transfer is incomplete')
        self._facts.before_lookup(self._publisher)
        self._lookup.transfer_lookup_inputs(reference, index)
        def retain_index(raw: bytes) -> None:
            self._response.retain_source(raw)
        self._lookup.consume_source(index, retain_index)
        actual_index = self._response.pending_sources[0]
        fields: tuple[Literal['request', 'attempt'], ...] = ('request', 'attempt')
        for field in fields:
            def contract_row(row: StoredBytes | None) -> None:
                if row is None:
                    raise LocalStorageError('Original stored publication contract is missing')
                self._response.retain_source(row.payload)
            self._projection.project_stored_contract_lookup_key(
                field, lambda key: self._query(read, key, contract_row))
        _, request, attempt = self._response.pending_sources
        self._facts.before_lookup(self._publisher)
        self._response.transfer_stored_inputs(request, attempt, actual_index)

    def advance(self, quantum: int) -> LocalResultProgress:
        """Advance the same Owner's total work budget under current physical facts."""
        core = self._projection._core
        with core._lock:
            self._nominal()
            if self._active or not self._entered:
                raise RuntimeError('Original Store observation transfer is not available')
            with self._facts.serialized():
                self._facts.before_lookup(self._publisher)
                progress = core.advance_publication_observation(
                    self._projection._publication, self._projection._configuration, quantum)
                self._facts.validate()
                return progress

    def finish(self) -> Literal['append_unknown', 'confirm_uncommitted_failure', 'adopt_committed_index']:
        """Read the Core action after complete original chain/current checks; no ACK."""
        core = self._projection._core
        with core._lock:
            self._nominal()
            if self._active or not self._entered:
                raise RuntimeError('Original Store observation transfer is not available')
            with self._facts.serialized():
                self._facts.before_lookup(self._publisher)
                action = core.finish_publication_observation(
                    self._projection._publication, self._projection._configuration)
                self._facts.validate()
                return action
