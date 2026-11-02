"""Normal saved-Result caller over the existing Core, Store and File Owners."""
from __future__ import annotations

from collections.abc import Callable
from typing import TYPE_CHECKING, TypeVar

import httpx

from ._local_commit_projection import OriginalCommitProjection
from ._local_core import _Input, _Output
from ._local_files import (LocalAreaAcquisitionError, LocalFileRoot,
    LocalOriginalAcquisitionError, PhysicalFileIdentity, PhysicalFileObservation,
    PhysicalFileSnapshot, _AllocationArea, _OriginalFileReader)
from ._local_installation import _object
from ._local_reader_facts import OriginalReaderFacts
from ._local_sdk_delivery_storage import OriginalSDKDeliveryStore, SDKDeliveryStorageCleanupPending
from ._local_sdk_payload_reader import OriginalSDKPayloadReader, SDKPayloadReaderCleanupPending
from ._local_sdk_read_storage import OriginalSDKReadEvidenceStore, SDKReadEvidenceCleanupPending
from ._local_sdk_response import OriginalLocalSDKResponseStream
from ._local_response import OriginalLocalResponseStream
from ._local_storage import ByteFence, CapacityReservation, StoredBytes
from ._local_store_reconciliation import OriginalStoreReconciliation
from ._values import wire_bytes

if TYPE_CHECKING:
    from ._local_product import InstalledLocalHost

_T = TypeVar('_T')


def _original_decimal(text: object, maximum: int) -> int:
    if type(text) is not str or not 1 <= len(text) <= 20 or not text.isascii() or not text.isdecimal():
        raise ValueError('Invalid original saved physical decimal')
    value = int(text)
    if not 0 <= value <= maximum or str(value) != text:
        raise ValueError('Invalid original saved physical range')
    return value


class OriginalSavedResultRead:
    """One operation's actual acquired children, never a replacement Run/plan.

    Register this carrier before prepare. Partial callbacks keep the same
    handles through explicit child-first cleanup; no acquisition or Store write
    is repeated after failure. Durable record/capacity facts are reobserved from
    the same installation; copied metadata alone supplies no authority or ACK.
    """
    def __init__(self, host: InstalledLocalHost) -> None:
        self._host, self._original = host, self
        self._source: _Output | None = None
        self._source_closed = False
        self._projection: OriginalCommitProjection | None = None
        self._record: _Output | None = None
        self._names: _Output | None = None
        self._area: _AllocationArea | None = None
        self._root: LocalFileRoot | None = None
        self._reader: _OriginalFileReader | None = None
        self._fact: OriginalReaderFacts | None = None
        self._observation: OriginalStoreReconciliation | None = None
        self._evidence: OriginalSDKReadEvidenceStore | None = None
        self._delivery: OriginalSDKDeliveryStore | None = None
        self._request: _Input | None = None
        self._clock: _Input | None = None
        self._preparing = self._closing = self._closed = False

    def _current(self, action: Callable[[], _T]) -> _T:
        host = self._host
        installation = host._active()
        source = self._source
        if self._closing or self._source_closed or source is None:
            raise ValueError('Original saved Result read is unavailable')
        result: list[_T] = []
        def inspect(current: _Output) -> None:
            self._ensure_active()
            host._core.validate_submission_lookup(source, current)
            self._ensure_active()
            result.append(action())
            host._core.validate_submission_lookup(source, current)
            self._ensure_active()
        installation.binding.inspect(inspect)
        if len(result) != 1:
            raise ValueError('Incomplete original saved Result current observation')
        return result[0]

    def _ensure_active(self) -> None:
        self._host._active()
        if self._original is not self or self._closing or self._source_closed:
            raise ValueError('Copied, closing or retired original saved Result read')

    def prepare(self, reference: object, name: str, format: str,
                attempt_id: str) -> httpx.Response:
        self._ensure_active()
        if self._preparing or self._source is not None:
            raise ValueError('Original saved Result read cannot be prepared again')
        self._preparing = True
        try:
            return self._prepare(reference, name, format, attempt_id)
        finally:
            self._preparing = False

    def prepare_lookup(self, reference: object, name: str,
                       attempt_id: str) -> httpx.Response:
        """Look up the saved original attempt without grant/write/payload work.

        The same Core source validates the current Account and stored chain.
        This intentionally opens no File Reader, re-reserves no payload and
        creates no first delivery; response loss retains the same output loans.
        """
        self._ensure_active()
        if self._preparing or self._source is not None:
            raise ValueError('Original saved delivery lookup cannot be prepared again')
        self._preparing = True
        try:
            host, core = self._host, self._host._core
            configuration = host._configuration
            if configuration is None or not configuration.sdk:
                raise ValueError('Original saved lookup configuration is unavailable')
            source, _ = host._retain_original_result_read(reference, name)
            self._source = source
            projection = OriginalCommitProjection.from_saved_read(core, source,
                configuration.handle, cleanup=lambda: True)
            self._projection = projection
            clock = host._original_sdk_delivery_clock()
            self._clock = clock
            tick = _object(core._inputs[clock.ticket].payload, 256)
            request = host._copy(wire_bytes({'result_name': name, 'format': 'jsonl',  # type: ignore[no-untyped-call]
                'attempt_id': attempt_id, 'observed_at': tick['observed_at']}))
            self._request = request
            streams: list[OriginalLocalResponseStream] = []
            self._current(lambda: projection.project_sdk_delivery_lookup(request,
                source.handle, lambda raw: streams.append(OriginalLocalResponseStream(host, raw))))
            if len(streams) != 1:
                raise ValueError('Incomplete original saved delivery lookup')
            stream = streams[0]
            response = httpx.Response(200, headers={'content-type': 'application/json',
                'content-encoding': 'identity'}, stream=stream)
            stream._attached = True
            return response
        finally:
            self._preparing = False

    def _prepare(self, reference: object, name: str, format: str,
                 attempt_id: str) -> httpx.Response:
        host, core = self._host, self._host._core
        installation, configuration = host._active(), host._configuration
        if configuration is None or not configuration.sdk:
            raise ValueError('Original saved Result configuration is unavailable')
        store, results = installation._store, installation._results
        if store is None or results is None:
            raise ValueError('Original saved Result physical installation is unavailable')
        source, metadata = host._retain_original_result_read(reference, name)
        self._source = source
        result = _original_decimal(metadata['resultOrdinal'], 7)
        binding = _original_decimal(metadata['bindingOrdinal'], 7)
        projection = OriginalCommitProjection.from_saved_read(core, source,
            configuration.handle, cleanup=lambda: True)
        self._projection = projection
        record = host._reserve(lambda: core.reserve_saved_payload_record(source,
            cleanup=lambda: True))
        self._record = record
        self._current(lambda: core.produce_payload_record(record, configuration.handle))
        raw = self._current(lambda: core.read_payload_record(record, configuration.handle))
        saved = _object(raw, 65536)
        expected = PhysicalFileSnapshot(PhysicalFileObservation(PhysicalFileIdentity(
            _original_decimal(saved['device'], 2**64 - 1),
            _original_decimal(saved['inode'], 2**64 - 1)),
            _original_decimal(saved['actual_bytes'], store._max_payload_bytes)),
            saved['physical_digest'])
        names = host._reserve(lambda: core.reserve_payload_names(record,
            cleanup=lambda: True))
        self._names = names
        def project_names() -> dict[str, object]:
            core.produce_payload_names(names, configuration.handle)
            return _object(core.read_payload_names(names, configuration.handle), 1024)
        packet = self._current(project_names)
        fields = {'staging_name', 'object_name', 'material_generation_cid', 'store_authority_cid',
                  'record_revision', 'request_cid', 'allocation_name', 'allocation_device', 'allocation_inode'}
        if set(packet) != fields or any(type(packet[key]) is not str for key in fields):
            raise ValueError('Invalid original saved payload name projection')
        if not core.close_payload_names(names):
            raise RuntimeError('Original saved payload names cleanup pending')
        self._names = None
        material, authority = packet['material_generation_cid'], packet['store_authority_cid']
        # Exact-str checks above are transport validation, not an Owner grant.
        assert isinstance(material, str) and isinstance(authority, str)
        key = store.namespaced_key('payload_record', material)
        rows: list[ByteFence] = []
        def take_row(row: StoredBytes | None) -> None:
            if row is None or row.payload != raw:
                raise ValueError('Changed original saved payload row')
            rows.append(ByteFence(key, row.generation, row.payload))
        with installation.binding.fenced() as fences:
            store.inspect_bounded_record_inspected(key, 65536, fences,
                inspect=lambda reader, take: installation.binding.inspect_reader(reader, lambda _: take()),
                consume=take_row, current=installation.binding._current_observer)
            if len(rows) != 1:
                raise ValueError('Incomplete original saved payload row')
            capacities: list[CapacityReservation] = []
            def take_capacity(capacity: CapacityReservation | None) -> None:
                if (capacity is None or capacity.namespace != 'publication_payload'
                        or capacity.key != key or capacity.reserved_bytes != expected.observation.size
                        or capacity.reserved_objects != 1):
                    raise ValueError('Original saved payload reservation is unavailable')
                capacities.append(capacity)
            store.inspect_capacity_inspected('publication_payload', key, (*fences, rows[0]),
                inspect=lambda reader, take: installation.binding.inspect_reader(reader, lambda _: take()),
                consume=take_capacity, current=installation.binding._current_observer)
        if len(capacities) != 1:
            raise ValueError('Incomplete original saved payload capacity observation')
        identity = PhysicalFileIdentity(_original_decimal(packet['allocation_device'], 2**64 - 1),
                                        _original_decimal(packet['allocation_inode'], 2**64 - 1))
        allocation_name, object_name = packet['allocation_name'], packet['object_name']
        assert isinstance(allocation_name, str) and isinstance(object_name, str)
        def open_area() -> None:
            try:
                self._area = results.restore_area(allocation_name, identity)
            except LocalAreaAcquisitionError as failure:
                self._area = failure.original_area
                raise
        self._current(open_area)
        assert self._area is not None and self._area.directory is not None
        # The original allocation directory retains its own custody. The live
        # writer adopted/finalized the object in the same results Root; do not
        # reconstruct a Writer or look for the final object inside that area.
        root = results
        self._root = root
        def open_reader() -> None:
            try:
                self._reader = root.open_saved_payload(object_name, expected)
            except LocalOriginalAcquisitionError as failure:
                self._reader = failure.original_reader
                raise
        self._current(open_reader)
        reader = self._reader
        assert reader is not None
        while not reader.eof:
            def hash_chunk() -> None:
                chunk = root.read_original(reader)
                root.release_original_chunk(reader, chunk)
            self._current(hash_chunk)
        self._current(lambda: root.observe_original(reader))
        fact = OriginalReaderFacts(projection, record, root, reader, result, binding,
            authority, material, cleanup=lambda: True, stopped=lambda _: True)
        self._fact = fact
        self._current(fact.validate)
        observation = OriginalStoreReconciliation.from_saved_read(projection, (fact,), store,
            ((rows[0], capacities[0]),), installation.binding, current=self._ensure_active)
        self._observation = observation
        try:
            self._evidence = OriginalSDKReadEvidenceStore(observation, cleanup=lambda: True)
        except SDKReadEvidenceCleanupPending as failure:
            self._evidence = failure.cleanup_evidence
            raise
        try:
            self._delivery = OriginalSDKDeliveryStore(observation, cleanup=lambda: True)
        except SDKDeliveryStorageCleanupPending as failure:
            self._delivery = failure.cleanup_storage
            raise
        clock = host._original_sdk_delivery_clock()
        self._clock = clock
        tick = _object(core._inputs[clock.ticket].payload, 256)
        request = host._copy(wire_bytes({'result_name': name, 'format': format,  # type: ignore[no-untyped-call]
            'attempt_id': attempt_id, 'observed_at': tick['observed_at']}))
        self._request = request
        self._evidence.persist(request, source.handle)
        self._delivery.persist(request, source.handle)
        self._delivery.prepare_original_codecs(request, clock)
        if self._delivery.selected_original_payload(request, clock) is not fact:
            raise ValueError('Foreign original saved payload selection')
        try:
            payload = OriginalSDKPayloadReader(self._delivery, request, clock, fact)
        except SDKPayloadReaderCleanupPending as failure:
            OriginalLocalSDKResponseStream(host, failure.cleanup_reader, saved_read=self)
            raise
        stream = OriginalLocalSDKResponseStream(host, payload, saved_read=self)
        if not core.close_input(clock):
            raise RuntimeError('Original saved Result clock cleanup pending')
        host._inputs.remove(clock)
        self._clock = None
        response = httpx.Response(200, headers={'content-type': 'application/x-ndjson',
            'content-encoding': 'identity'}, stream=stream)
        stream._attached = True
        return response

    def close(self) -> bool:
        if self._original is not self:
            raise ValueError('Copied original saved Result custody')
        if self._closed:
            return True
        self._closing = True
        if self._preparing:
            return False
        host, core = self._host, self._host._core
        if self._source is not None and not self._source_closed and core._closing:
            core.begin_saved_read_cleanup(self._source)
        # These synchronous output loans belong to the projection. The Store
        # holders deliberately refuse workspace close while any loan remains.
        if self._projection is not None and not self._projection.close():
            return False
        for holder in (self._delivery, self._evidence):
            if holder is not None and not holder.close():
                return False
        if self._fact is not None and not self._fact.close():
            return False
        if self._reader is not None:
            assert self._root is not None
            if not self._root.close_original(self._reader):
                return False
            self._reader = None
        if self._area is not None:
            installation = host._installation
            assert installation is not None and installation._results is not None
            if not installation._results.close_area(self._area):
                return False
            self._area = None
        if self._names is not None:
            if not core.close_payload_names(self._names):
                return False
            self._names = None
        if self._record is not None:
            if not core.close_payload_record(self._record):
                return False
            self._record = None
        for source in (self._clock, self._request):
            if source is not None:
                if not core.close_input(source):
                    return False
                if source in host._inputs:
                    host._inputs.remove(source)
        self._clock = self._request = None
        if self._source is not None:
            if not self._source_closed:
                if not core.close_submission_lookup(self._source):
                    return False
                self._source_closed = True
                host._projections.remove(self._source)
            source_input = host._append_sources.get(self._source.ticket)
            if source_input is not None:
                if not core.close_input(source_input):
                    return False
                del host._append_sources[self._source.ticket]
                host._inputs.remove(source_input)
            self._source = None
        self._closed = True
        return True
