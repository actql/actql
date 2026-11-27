"""Normal saved-Result caller over the existing Core, Store and File Owners."""
from __future__ import annotations

import asyncio as _asyncio
from collections.abc import Callable
from contextlib import AbstractContextManager
from dataclasses import dataclass
from typing import TYPE_CHECKING, TypeVar

import httpx

from ._local_commit_projection import OriginalCommitProjection
from ._local_core import _Input, _Output, _Workspace
from ._local_files import (LocalAreaAcquisitionError, LocalFileRoot,
    LocalOriginalAcquisitionError, PhysicalFileIdentity, PhysicalFileObservation,
    PhysicalFileSnapshot, _AllocationArea, _OriginalFileReader)
from ._local_installation import _object
from ._local_reader_facts import OriginalReaderFacts
from ._local_sdk_delivery_storage import OriginalSDKDeliveryStore, SDKDeliveryStorageCleanupPending
from ._local_sdk_payload_reader import OriginalSDKPayloadReader, SDKPayloadReaderCleanupPending
from ._local_sdk_response import OriginalLocalSDKResponseStream
from ._local_response import OriginalLocalResponseStream
from ._local_storage import ByteFence, CapacityReservation, StoredBytes, _NamespaceReader
from ._local_store_reconciliation import OriginalStoreReconciliation
from ._values import wire_bytes

if TYPE_CHECKING:
    from ._local_product import InstalledLocalHost

_T = TypeVar('_T')
_SavedPayloadSelection = tuple[ByteFence, CapacityReservation, str, str, int, int]


@dataclass(frozen=True, slots=True)
class _SavedRunControl:
    key: str
    generation: int
    extent: int
    expires_at: str

    @classmethod
    def from_wire(cls, wire: bytes) -> _SavedRunControl:
        if len(wire) != 107 or wire[:7] != b'sha256:' or any(
                byte not in b'0123456789abcdef' for byte in wire[7:71]):
            raise ValueError('Invalid original Local Run key')
        generation = int.from_bytes(wire[71:79], 'little', signed=True)
        extent = int.from_bytes(wire[79:83], 'little')
        if generation < 0 or not 0 < extent <= 262144:
            raise ValueError('Invalid original Local Run extent')
        return cls(wire[:71].decode('ascii'), generation, extent, wire[83:].decode('ascii'))


def _public_run_current(host: InstalledLocalHost, target: _SavedRunControl,
                        operation: Callable[[], AbstractContextManager[None]]) -> Callable[[], None]:
    installation, configuration = host._active(), host._configuration
    binding, store = installation.binding, installation._store
    if configuration is None or store is None:
        raise ValueError('Original Local Result return coordinates are unavailable')

    def check() -> None:
        # No response, stream, input ticket, FD or SQLite read is retained.
        # The existing owner opens a short current Read, including after cleanup.
        with host._core._lock, operation():
            if (host._active() is not installation or host._configuration is not configuration
                    or host._original_physical_observed_at() >= target.expires_at):
                raise ValueError('Original Local Result return context changed')

            def observe(reader: _NamespaceReader) -> None:
                if reader.query_current is None:
                    raise ValueError('Original Local Run point read is unavailable')

                def read(_: _Output) -> None:
                    actual = reader.query_current(
                        reader, 1, 'client_sqlite_saved_run_current', target.key,
                        binding._current_observer)
                    if actual != (target.key, StoredBytes(
                            target.generation, target.extent.to_bytes(4, 'little'))):
                        raise ValueError('Original Local Run control changed')

                binding.inspect_reader(reader, read)

            with binding.fenced() as fences:
                store.inspect_namespaces(fences, inspect=observe,
                                        current=binding._current_observer)
            if host._original_physical_observed_at() >= target.expires_at:
                raise ValueError('Original Local Result expired during its return observation')
    return check


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
        self._small_payload_workspace: _Workspace | None = None
        self._fact: OriginalReaderFacts | None = None
        self._observation: OriginalStoreReconciliation | None = None
        self._delivery: OriginalSDKDeliveryStore | None = None
        self._request: _Input | None = None
        self._clock: _Input | None = None
        self._payload_selection: _SavedPayloadSelection | None = None
        self._return_target: _SavedRunControl | None = None
        self._preparing = self._closing = self._closed = False

    def _current(self, action: Callable[[], _T],
                 selection: _SavedPayloadSelection | None = None) -> _T:
        host = self._host
        installation = host._active()
        source = self._source
        if self._closing or self._source_closed or source is None:
            raise ValueError('Original saved Result read is unavailable')
        result: list[_T] = []
        def inspect(current: _Output, take_capacity: Callable[[], None] | None = None) -> None:
            self._ensure_active()
            host._core.validate_submission_lookup(source, current)
            self._ensure_active()
            if take_capacity is not None:
                take_capacity()
            result.append(action())
            # The synchronous action returns to the same inspected SQLite
            # reader. Its original Host/files/Store checks run on exit.
            self._ensure_active()
        binding = installation.binding
        if selection is None:
            binding.inspect(inspect)
        else:
            row, capacity, _, _, _, _ = selection
            store = installation._store
            if store is None:
                raise ValueError('Original saved Result physical installation is unavailable')
            def confirm(actual: CapacityReservation | None) -> None:
                if actual != capacity:
                    raise ValueError('Changed original saved payload reservation')
            with binding.fenced() as fences:
                store.inspect_capacity_inspected(capacity.namespace, capacity.key, (*fences, row),
                    inspect=lambda reader, take: binding.inspect_reader(reader, lambda current: inspect(current, take)),
                    consume=confirm, current=binding._current_observer)
        if len(result) != 1:
            raise ValueError('Incomplete original saved Result current observation')
        return result[0]

    def _public_terminal_current(self, operation: Callable[[], AbstractContextManager[None]]
                                 ) -> Callable[[], None]:
        target = self._return_target
        if target is None:
            raise ValueError('Original saved Result return coordinates are unavailable')
        return _public_run_current(self._host, target, operation)

    def _check_transfer_current(self) -> None:
        host = self._host
        with host._core._lock:
            root, reader, selection = self._root, self._reader, self._payload_selection
            target = self._return_target
            if root is None or reader is None or selection is None or target is None:
                raise ValueError('Original saved Result transfer is unavailable')
            if host._original_physical_observed_at() >= target.expires_at:
                raise ValueError('Original saved Result return context expired')
            self._current(lambda: root.observe_original(reader), selection)
            if (self._return_target is not target
                    or host._original_physical_observed_at() >= target.expires_at):
                raise ValueError('Original saved Result expired during its return observation')

    def _ensure_active(self) -> None:
        self._host._active()
        if self._original is not self or self._closing or self._source_closed:
            raise ValueError('Copied, closing or retired original saved Result read')

    def _prepare_turn(self, scope: object) -> None:
        self._ensure_active()
        core = self._host._core
        if (not self._preparing or core._host_operation_scope is not scope
                or core._host_fuel_phase != 'operation' or core._host_cleanup_depth):
            raise ValueError('Original saved Result operation changed')

    def _ensure_physical_preparation(self) -> None:
        host = self._host
        installation, configuration = host._active(), host._configuration
        if configuration is None or not configuration.sdk:
            raise ValueError('Original saved Result configuration is unavailable')
        if installation._store is None or installation._results is None:
            raise ValueError('Original saved Result physical installation is unavailable')

    async def _prepare_incremental_metadata(
            self, scope: object, reference: object, name: str
            ) -> tuple[_Output, tuple[int, int, _SavedRunControl]]:
        host = self._host
        async with host._operation_lock():
            self._prepare_turn(scope)
            self._ensure_physical_preparation()
            source, definition = host._reserve_original_result_read(reference, name)
            self._source = source
            packet = host._read_original_result_projection(source, definition, name)
        while packet is None:
            await _asyncio.sleep(0)
            async with host._operation_lock():
                self._prepare_turn(scope)
                packet = host._read_original_result_projection(source, definition, name)
        return source, packet

    async def prepare_incremental(self, reference: object, name: str, format: str,
                                  attempt_id: str) -> httpx.Response:
        self._ensure_active()
        host, core = self._host, self._host._core
        scope = core._host_operation_scope
        if self._preparing or self._source is not None or scope is None:
            raise ValueError('Original saved Result incremental preparation is unavailable')
        self._preparing = True
        try:
            source, packet = await self._prepare_incremental_metadata(scope, reference, name)
            async with host._operation_lock():
                self._prepare_turn(scope)
                result, binding, self._return_target = packet
                selection = self._prepare_payload(source, (result, binding))
                del packet
                core.retire_saved_result_transport(source)
            reader = self._reader
            assert reader is not None
            while not reader.eof:
                async with host._operation_lock():
                    self._prepare_turn(scope)
                    self._hash_next_original_chunk(selection)
                await _asyncio.sleep(0)
            async with host._operation_lock():
                self._prepare_turn(scope)
                return self._finish_payload(source, selection, name, format, attempt_id)
        finally:
            self._preparing = False

    async def prepare_lookup_incremental(self, reference: object, name: str,
                                         attempt_id: str) -> httpx.Response:
        self._ensure_active()
        host = self._host
        scope = host._core._host_operation_scope
        if self._preparing or self._source is not None or scope is None:
            raise ValueError('Original saved delivery lookup preparation is unavailable')
        self._preparing = True
        try:
            source, metadata = await self._prepare_incremental_metadata(scope, reference, name)
            del metadata
            async with host._operation_lock():
                self._prepare_turn(scope)
                stream = self._lookup_response(source, name, attempt_id)
                self._preparing = False
                return self._finish_lookup(stream)
        finally:
            self._preparing = False

    def _lookup_response(self, source: _Output, name: str,
                         attempt_id: str) -> OriginalLocalResponseStream:
        # This only projects existing attempt metadata. No File Reader, grant,
        # attempt or Store write belongs to this continuation.
        host, core = self._host, self._host._core
        configuration = host._configuration
        if configuration is None or not configuration.sdk:
            raise ValueError('Original saved lookup configuration is unavailable')
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
        return streams[0]

    def _finish_lookup(self, stream: OriginalLocalResponseStream) -> httpx.Response:
        # The Read has returned. A failed close keeps the original response
        # registered but unavailable to the public caller.
        with self._host._core._host_cleanup():
            if not self.close():
                raise RuntimeError('Original saved delivery lookup cleanup is pending')
        response = httpx.Response(200, headers={'content-type': 'application/json',
            'content-encoding': 'identity'}, stream=stream)
        stream._attached = True
        return response

    def _prepare_payload(self, source: _Output, coordinates: tuple[int, int]) -> _SavedPayloadSelection:
        host, core = self._host, self._host._core
        installation, configuration = host._active(), host._configuration
        if configuration is None or not configuration.sdk:
            raise ValueError('Original saved Result configuration is unavailable')
        store, results = installation._store, installation._results
        if store is None or results is None:
            raise ValueError('Original saved Result physical installation is unavailable')
        result, binding = coordinates
        projection = OriginalCommitProjection.from_saved_read(core, source,
            configuration.handle, cleanup=lambda: True)
        self._projection = projection
        record = host._reserve(lambda: core.reserve_saved_payload_record(source,
            cleanup=lambda: True))
        self._record = record
        def project_record_and_names() -> tuple[bytes, PhysicalFileSnapshot, dict[str, object]]:
            core.produce_payload_record(record, configuration.handle)
            raw = core.read_payload_record(record, configuration.handle)
            saved = _object(raw, 65536)
            expected = PhysicalFileSnapshot(PhysicalFileObservation(PhysicalFileIdentity(
                _original_decimal(saved['device'], 2**64 - 1),
                _original_decimal(saved['inode'], 2**64 - 1)),
                _original_decimal(saved['actual_bytes'], store._max_payload_bytes)),
                saved['physical_digest'])
            names = host._reserve(lambda: core.reserve_payload_names(record,
                cleanup=lambda: True))
            self._names = names
            core.produce_payload_names(names, configuration.handle)
            packet = _object(core.read_payload_names(names, configuration.handle), 1024)
            return raw, expected, packet

        raw, expected, packet = self._current(project_record_and_names)
        names = self._names
        assert names is not None
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
        capacities: list[CapacityReservation] = []
        def take_capacity(capacity: CapacityReservation | None) -> None:
            if (capacity is None or capacity.namespace != 'publication_payload'
                    or capacity.key != key or capacity.reserved_bytes != expected.observation.size
                    or capacity.reserved_objects != 1):
                raise ValueError('Original saved payload reservation is unavailable')
            capacities.append(capacity)

        identity = PhysicalFileIdentity(_original_decimal(packet['allocation_device'], 2**64 - 1),
                                        _original_decimal(packet['allocation_inode'], 2**64 - 1))
        allocation_name, object_name = packet['allocation_name'], packet['object_name']
        assert isinstance(allocation_name, str) and isinstance(object_name, str)

        def inspect_selection(reader: _NamespaceReader, take: Callable[[], None]) -> None:
            def open_original(current: _Output) -> None:
                self._ensure_active()
                take()
                if len(rows) != 1 or len(capacities) != 1:
                    raise ValueError('Incomplete original saved payload observation')
                core.validate_submission_lookup(source, current)
                self._ensure_active()
                try:
                    self._area = results.restore_area(allocation_name, identity)
                except LocalAreaAcquisitionError as failure:
                    self._area = failure.original_area
                    raise
                # The allocation directory retains its own custody. The
                # finalized object belongs to the original results Root.
                self._root = results
                try:
                    extent = expected.observation.size
                    if extent <= results._max_chunk_bytes:
                        # Retain the admitted small buffer until reader close.
                        self._small_payload_workspace = host._reserve(lambda: core.reserve_workspace(
                            extent + 512, stopped=lambda: True, cleanup=lambda: True))
                    self._reader = results.open_saved_payload(object_name, expected)
                except LocalOriginalAcquisitionError as failure:
                    self._reader = failure.original_reader
                    raise
                self._ensure_active()

            installation.binding.inspect_reader(reader, open_original)

        with installation.binding.fenced() as fences:
            store.inspect_record_capacity_inspected('publication_payload', key, 65536, fences,
                inspect=inspect_selection, consume_record=take_row, consume_capacity=take_capacity,
                current=installation.binding._current_observer)
        return rows[0], capacities[0], authority, material, result, binding

    def _hash_next_original_chunk(self, selection: _SavedPayloadSelection | None = None) -> None:
        root, reader = self._root, self._reader
        assert root is not None and reader is not None
        if self._small_payload_workspace is not None:
            self._current(lambda: root.verify_small_saved_payload(reader), selection)
            return
        def hash_chunk() -> None:
            chunk = root.read_original(reader)
            root.release_original_chunk(reader, chunk)
        self._current(hash_chunk, selection)

    def _finish_payload(self, source: _Output, selection: _SavedPayloadSelection,
                        name: str, format: str, attempt_id: str) -> httpx.Response:
        host, core = self._host, self._host._core
        installation = host._active()
        store = installation._store
        projection, record = self._projection, self._record
        root, reader = self._root, self._reader
        assert store is not None and projection is not None and record is not None
        assert root is not None and reader is not None
        row, capacity, authority, material, result, binding = selection
        self._payload_selection = selection
        fact = OriginalReaderFacts(projection, record, root, reader, result, binding,
            authority, material, cleanup=lambda: True, stopped=lambda _: True)
        self._fact = fact
        self._current(fact.validate, selection)
        observation = OriginalStoreReconciliation.from_saved_read(projection, (fact,), store,
            ((row, capacity),), installation.binding, current=self._ensure_active)
        self._observation = observation
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
        self._delivery.persist(request, source.handle)
        if self._delivery.prepare_original_payload(request, clock) is not fact:
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

    def _begin_terminal_cleanup(self) -> bool:
        """Enter original Core retirement before attempting affected child loans."""
        if self._original is not self:
            raise ValueError('Copied original saved Result custody')
        if self._preparing:
            return False
        core = self._host._core
        if self._source is not None and not self._source_closed and core._closing:
            core.begin_saved_read_cleanup(self._source)
        return True

    def close(self) -> bool:
        if self._original is not self:
            raise ValueError('Copied original saved Result custody')
        if self._closed:
            return True
        self._closing = True
        if not self._begin_terminal_cleanup():
            return False
        host, core = self._host, self._host._core
        # These synchronous output loans belong to the projection. The Store
        # holders deliberately refuse workspace close while any loan remains.
        if self._projection is not None and not self._projection.close():
            return False
        if self._delivery is not None and not self._delivery.close():
            return False
        if self._fact is not None and not self._fact.close():
            return False
        if self._reader is not None:
            assert self._root is not None
            if not self._root.close_original(self._reader):
                return False
            self._reader = None
        if self._small_payload_workspace is not None:
            if not core.close_workspace(self._small_payload_workspace):
                return False
            self._small_payload_workspace = None
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
        if (clock := self._clock) is not None:
            if not core.close_input(clock):
                return False
            self._clock = None
            if clock in host._inputs:
                host._inputs.remove(clock)
        if (request := self._request) is not None:
            if not core.close_input(request):
                return False
            self._request = None
            if request in host._inputs:
                host._inputs.remove(request)
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
        self._payload_selection = None
        self._return_target = None
        self._closed = True
        return True
