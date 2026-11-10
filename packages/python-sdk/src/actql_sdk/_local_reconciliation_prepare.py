"""The original nonsaved reconciliation's fixed synchronous read phase.

This receipt borrows physical DATA, never Account authority or a Store outcome.
It is unavailable to generic inspectors and is retired before the original read
transaction ends. Every semantic validator and publisher stage still executes.
"""
from __future__ import annotations

from collections.abc import Callable
from _thread import RLock
import hashlib
import sqlite3
import sys
from threading import get_ident
from types import MethodType
from typing import Any, cast

from ._local_core import (LocalCore, _ClosedWasmExports, _JournalCallbacks,
                         _PhysicalInput, _RECONCILIATION_PREPARE_BYTES,
                         _original_metadata_cleanup, _original_metadata_stopped)
from ._local_commit_projection import OriginalCommitProjection
from ._local_files import LocalFileRoot, _FileReader, PhysicalFileSnapshot
from ._local_host_binding import OriginalHostBinding, _OriginalPublisherPort
from ._local_host_files import LocalHostFiles
from ._local_installation import OriginalLocalInstallation
from ._local_observation_transfer import OriginalObservationTransfer
from ._local_reader_facts import OriginalReaderFacts
from ._local_storage import LocalByteStore, LocalStorageError, StoredBytes, _NamespaceReader
from ._local_storage_physical import _SQLiteByteDatabase, _TrackedSQLiteConnection
from ._local_store_reconciliation import OriginalStoreReconciliation
from ._local_submission import LocalSubmissionAuthority


# Each module captures only this fixed driver's relevant dispatch identities
# beside their original definitions, before an importer can customize them.
from ._local_prepare_provenance import _capture_prepare_methods, _capture_prepare_functions, _code
from ._local_core import _PREPARE_METHODS as _core_methods
from ._local_commit_projection import _PREPARE_METHODS as _commit_projection_methods
from ._local_files import _PREPARE_METHODS as _files_methods
from ._local_host_binding import _PREPARE_METHODS as _host_binding_methods
from ._local_host_files import _PREPARE_METHODS as _host_files_methods
from ._local_installation import _PREPARE_METHODS as _installation_methods
from ._local_observation_transfer import _PREPARE_METHODS as _observation_transfer_methods
from ._local_reader_facts import _PREPARE_METHODS as _reader_facts_methods
from ._local_storage import _PREPARE_METHODS as _storage_methods
from ._local_storage_physical import _PREPARE_METHODS as _storage_physical_methods
from ._local_store_reconciliation import _PREPARE_METHODS as _store_reconciliation_methods
from ._local_submission import _PREPARE_METHODS as _submission_methods
from ._local_journal_port import _PREPARE_METHODS as _journal_port_methods
from ._local_core import _PREPARE_FUNCTIONS as _core_functions

_METHODS = (*_core_methods, *_commit_projection_methods, *_files_methods,
            *_host_binding_methods, *_host_files_methods, *_installation_methods,
            *_observation_transfer_methods, *_reader_facts_methods, *_storage_methods,
            *_storage_physical_methods, *_store_reconciliation_methods,
            *_submission_methods, *_journal_port_methods)
_HASH_TYPE = type(hashlib.sha256())
_EXPORT_NAMES = (
    'actql_publication_commit_export_result_count',
    'actql_publication_commit_export_validate_payload_binding',
    'actql_payload_record_validate_snapshot', 'actql_publisher_authorize',
    'actql_publication_commit_export_reserve',
    'actql_publication_commit_export_produce_index_key',
    'actql_publication_commit_export_produce_lookup_reference',
    'actql_publication_commit_export_length', 'actql_publication_commit_export_close',
    'actql_buffer_read_block', 'actql_buffer_reserve', 'actql_buffer_fill_block',
    'actql_buffer_seal', 'actql_publication_prepare_lookup',
    'actql_publication_prepare_observation',
)


def _methods_original(objects: tuple[object, ...], *, reduced: bool = False) -> bool:
    for cls, members in (_REDUCED_METHODS if reduced else _METHODS):
        current = vars(cls)
        if cls.__getattribute__ is not object.__getattribute__:
            return False
        for name, method, code in members:
            if current.get(name) is not method or _code(method) is not code:
                return False
        for value in objects:
            if type(value) is cls and hasattr(value, '__dict__'):
                attributes = vars(value)
                if any(name in attributes for name, _, _ in members):
                    return False
    if reduced:
        return True
    for namespace, members in _FUNCTIONS:
        for name, method, code in members:
            if namespace.get(name) is not method or _code(method) is not code:
                return False
    return True


def _objects(owner: OriginalStoreReconciliation, binding: OriginalHostBinding) -> tuple[object, ...]:
    installation = binding._source._installation
    assert installation is not None
    return (owner, owner._projection, owner._lookup, owner._response, binding,
            binding._core, binding._store, binding._store._physical,
            binding._store._connection, binding._source, binding._state,
            binding._source._installation, binding._epoch,
            binding._source._root, binding._state._root,
            *installation._roots,
            *owner._facts, *(fact._root for fact in owner._facts))


def _original_shapes(owner: OriginalStoreReconciliation, binding: OriginalHostBinding) -> bool:
    core, store = binding._core, owner._store
    lookup, response = owner._lookup, owner._response
    if lookup is None or response is None:
        return False
    return (type(core._lock) is RLock and type(store._lock) is RLock
            and type(core._inputs) is dict and type(core._loans) is dict and type(core._released) is set
            and type(binding._selected) is tuple and type(binding._expected) is tuple
            and type(binding._fences) is tuple and type(owner._originals) is tuple
            and type(owner._projection._outputs) is list
            and all(type(transfer._sources) is list for transfer in (lookup, response))
            and all(type(fact._root._lock) is RLock and type(fact._root._readers) is dict
                    and type(fact._root._files) is dict and type(fact._root._finalizations) is dict
                    and type(fact._reader.hash) is _HASH_TYPE for fact in owner._facts))


def _prepare_supported(owner: OriginalStoreReconciliation, binding: OriginalHostBinding) -> bool:
    """Only unsupported pre-entry customization selects the existing legacy path."""
    if (type(owner) is not OriginalStoreReconciliation or type(binding) is not OriginalHostBinding
            or sys.gettrace() is not None or sys.getprofile() is not None
            or type(owner._facts) is not tuple or not 1 <= len(owner._facts) <= 8
            or any(type(fact) is not OriginalReaderFacts for fact in owner._facts)):
        return False
    core, store, projection = binding._core, owner._store, owner._projection
    # The original current reservation predates even the bounded candidate
    # tuples. Unsupported or unfunded physical suppliers stay on legacy.
    if type(core) is not LocalCore or binding._current is None:
        return False
    funded = core._inputs.get(binding._current.ticket)
    if (type(funded) is not _PhysicalInput
            or funded.prepare_bytes != _RECONCILIATION_PREPARE_BYTES
            or _PREPARE_MAX_METADATA_BYTES > _RECONCILIATION_PREPARE_BYTES):
        return False
    installation = binding._source._installation
    if (type(installation) is not OriginalLocalInstallation
            or type(installation._roots) is not list or len(installation._roots) != 4
            or any(type(root) is not LocalFileRoot for root in installation._roots)):
        return False
    if not _methods_original(_objects(owner, binding)) or not _original_shapes(owner, binding):
        return False
    if (type(core) is not LocalCore or type(store) is not LocalByteStore
            or type(projection) is not OriginalCommitProjection or projection._saved
            or projection._cleanup is not _original_metadata_cleanup
            or type(store._physical) is not _SQLiteByteDatabase
            or type(store._connection) is not _TrackedSQLiteConnection
            or not store._connection._closed_eligible()
            or store._connection._closed_prepare is not None
            or not getattr(core, '_ordinary_host', False) or core._host_fuel_phase != 'operation'
            or core._host_cleanup_depth or core._closing or core._closed or core._retired
            or core._invoking or getattr(core, '_reconciliation_prepare', None) is not None
            or getattr(core, '_invocation_observation', None) is not None
            or getattr(core, '_physical_holding', None) is not None
            or getattr(core, '_physical_child_control', None) is not None
            or getattr(core, '_physical_vm_observation', None) is not None
            or type(core._host_operation_id) is not int
            or not 0 < core._host_operation_id < 2**63
            or core._host_operation_id != core._host_operation_sequence
            or type(getattr(core, '_closed_wasm_exports', None)) is not _ClosedWasmExports
            or binding._current is None or binding._input is None):
        return False
    installation = binding._source._installation
    current = core._inputs.get(binding._current.ticket)
    if (type(installation) is not OriginalLocalInstallation or installation._binding is not binding
            or installation._core is not core or installation._store is not store
            or binding._state._installation is not installation
            or len(installation._root_names) != 4
            or any(not any(root is original for original in installation._roots)
                   for group in (installation._root_names, installation._readers) for root, _ in group)
            or binding._source._observe_roots is not None or binding._state._observe_roots is not None
            or type(current) is not _PhysicalInput
            or current.prepare_bytes != _RECONCILIATION_PREPARE_BYTES):
        return False
    for transfer in (owner._lookup, owner._response):
        if (type(transfer) is not OriginalObservationTransfer
                or transfer._projection is not projection or transfer._publisher is not owner._publisher
                or transfer._cleanup is not _original_metadata_cleanup
                or transfer._stopped is not _original_metadata_stopped
                or transfer._workspace_cleanup is not _original_metadata_cleanup
                or transfer._workspace_stopped is not _original_metadata_cleanup):
            return False
    for fact in owner._facts:
        if (fact._projection is not projection or fact._input is None or not fact._sealed
                or fact._acquisition_ticket is not None or fact._closing
                or fact._cleanup is not _original_metadata_cleanup
                or fact._stopped is not _original_metadata_stopped
                or type(fact._root) is not LocalFileRoot or type(fact._reader) is not _FileReader
                or not fact._reader.eof or fact._reader.chunk is not None
                or fact._reader.descriptor is None or fact._reader.invalid
                or fact._reader.closing or fact._reader.close_pending
                or fact._reader.finalization.result is None):
            return False
        physical = core._inputs.get(fact._input.ticket)
        if (type(physical) is not _PhysicalInput
                or physical.cleanup is not _original_metadata_cleanup
                or physical.stopped is not _original_metadata_stopped):
            return False
    callbacks = core._publisher_callbacks(owner._publisher.ticket) if owner._publisher is not None else None
    if callbacks is None or type(callbacks.original) is not _OriginalPublisherPort:
        return False
    publisher = callbacks.original
    if (publisher.binding is not binding or publisher.output is not owner._publisher
            or not _methods_original((publisher,))):
        return False
    # A customized later validator/cleanup export must select legacy BEFORE
    # admission, not turn a formerly supported preparation into a refusal.
    receipt = core._closed_wasm_exports
    if type(receipt) is not _ClosedWasmExports or type(receipt.mapping) is not dict:
        return False
    return all(receipt._qualify(name, receipt.mapping.get(name)) for name in _EXPORT_NAMES)


class _ReaderPin:
    __slots__ = ('fact', 'owners', 'values', 'input', 'physical', 'payload', 'root_descriptor',
                 'descriptor', 'finalization', 'file', 'snapshot', 'result', 'final_stamp',
                 'hash', 'offset', 'name', 'snapshot_result')

    def __init__(self, fact: OriginalReaderFacts) -> None:
        self.fact = fact
        self.owners, self.values = fact._material_originals()
        loan = fact._input
        assert loan is not None
        self.input = loan
        self.physical = fact._projection._core._inputs[self.input.ticket]
        self.payload = self.physical.payload
        root, reader = fact._root, fact._reader
        assert type(reader) is _FileReader
        self.root_descriptor, self.descriptor = root._descriptor, reader.descriptor
        self.finalization = reader.finalization
        self.file, self.snapshot = self.finalization.file, self.finalization.snapshot
        result = self.finalization.result
        assert result is not None
        self.result, self.final_stamp = result, self.finalization.final_stamp
        self.hash, self.offset, self.name = reader.hash, reader.offset, self.finalization.name
        self.snapshot_result = self.snapshot.result

    def check(self) -> None:
        fact, reader, root = self.fact, self.fact._reader, self.fact._root
        if type(reader) is not _FileReader:
            raise ValueError('Original completed reconciliation reader variant changed')
        core = fact._projection._core
        if (not fact._same_material_originals((self.owners, self.values))
                or not fact._active or fact._closing or fact._acquisition_ticket is not None
                or not fact._sealed or fact._input is not self.input
                or core._inputs.get(self.input.ticket) is not self.physical
                or self.physical.payload is not self.payload
                or self.physical.cleanup is not _original_metadata_cleanup
                or self.physical.stopped is not _original_metadata_stopped
                or root._descriptor != self.root_descriptor or not root._ready or root._close_pending
                or reader.descriptor != self.descriptor or reader.finalization is not self.finalization
                or self.finalization.file is not self.file or self.finalization.snapshot is not self.snapshot
                or self.finalization.result is not self.result
                or self.finalization.final_stamp is not self.final_stamp
                or self.finalization.name != self.name or self.snapshot.result is not self.snapshot_result
                or self.file.closing or reader.hash is not self.hash or reader.offset != self.offset
                or not reader.eof or reader.chunk is not None or reader.invalid or reader.closing
                or reader.close_pending or not reader.finish_ready
                or 'sha256:' + reader.hash.hexdigest() != self.result.physical_digest):
            raise ValueError('Original completed reconciliation reader changed or retired')
        root._open()
        root._owned_reader(reader)
        core._owned_input(self.input)
        core._owned_output(fact._record, 'payload_record')

    def retained_bytes(self) -> int:
        return sys.getsizeof(self) + sys.getsizeof(self.owners) + sys.getsizeof(self.values)


class _PrepareObservation:
    """One fixed Owner execution, separate from each genuine Wasmtime call."""
    __slots__ = ('original', 'owner', 'binding', 'core', 'store', 'reader', 'connection',
                 'database', 'installation', 'source', 'state', 'current', 'input', 'epoch',
                 'selected', 'expected', 'fences', 'facts', 'originals', 'projection',
                 'lookup', 'response', 'publisher', 'receipt', 'platform', 'thread', 'operation',
                 'transaction', 'outer', 'statement', 'changes', 'objects', 'pins',
                 'failure', 'active', 'suspended', 'checking', 'reads', 'copied', 'reading',
                 'checkpoints', 'snapshots', 'authorizations', 'exports',
                 'output_ticket', 'output_physical', 'input_pins')

    def __init__(self, owner: OriginalStoreReconciliation, binding: OriginalHostBinding,
                 reader: _NamespaceReader) -> None:
        self.original, self.owner, self.binding, self.core = self, owner, binding, binding._core
        self.store, self.reader = owner._store, reader
        self.database = cast(_SQLiteByteDatabase, self.store._physical)
        self.connection = cast(_TrackedSQLiteConnection, self.store._connection)
        installation = binding._source._installation
        assert type(installation) is OriginalLocalInstallation
        self.installation, self.source, self.state = installation, binding._source, binding._state
        assert binding._current is not None and binding._input is not None and binding._frame_epoch is not None
        self.current, self.input, self.epoch = binding._current, binding._input, binding._frame_epoch
        self.selected, self.expected, self.fences = binding._selected, binding._expected, binding._fences
        self.facts, self.originals = owner._facts, owner._originals
        assert owner._lookup is not None and owner._response is not None and owner._publisher is not None
        self.projection, self.lookup, self.response = owner._projection, owner._lookup, owner._response
        callbacks = self.core._publisher_callbacks(owner._publisher.ticket)
        assert callbacks is not None and type(callbacks.original) is _OriginalPublisherPort
        self.publisher = callbacks.original
        assert type(self.core._closed_wasm_exports) is _ClosedWasmExports
        self.receipt, self.platform = self.core._closed_wasm_exports, self.core._platform_vm_original
        self.exports = tuple((name, self.receipt.mapping[name]) for name in _EXPORT_NAMES)
        self.output_ticket: int | None = None
        self.output_physical: _PhysicalInput | None = None
        self.input_pins: list[tuple[int, _PhysicalInput, bytes]] = []
        self.thread, self.operation = get_ident(), self.core._host_operation_id
        self.transaction, self.outer = self.connection._transaction_epoch, self.connection._outer_transaction_epoch
        self.statement, self.changes = self.connection._closed_statement_epoch, self.connection.total_changes
        self.objects = (*_objects(owner, binding), self.publisher)
        self.pins = tuple(_ReaderPin(fact) for fact in owner._facts)
        self.failure: BaseException | None = None
        self.active, self.suspended, self.checking, self.reading = True, False, False, False
        self.reads = self.copied = self.checkpoints = self.snapshots = self.authorizations = 0
        if self.retained_bytes() + 8192 > _RECONCILIATION_PREPARE_BYTES:
            raise ValueError('Original reconciliation receipt exceeds its reservation')

    def retained_bytes(self) -> int:
        return (_METHOD_BYTES + sys.getsizeof(self) + sys.getsizeof(self.objects)
                + sys.getsizeof(self.pins) + sum(pin.retained_bytes() for pin in self.pins)
                + sys.getsizeof(self.exports) + sum(sys.getsizeof(pair) for pair in self.exports)
                # Seven original source/packet inputs at most, allocated only
                # after this fixed maximum was funded by the current Owner.
                + sys.getsizeof([None] * 8) + 7 * sys.getsizeof((None, None, None)))

    def _fail(self, error: BaseException) -> BaseException:
        if self.failure is None:
            self.failure = error
        return self.failure

    def _guard_sql(self) -> None:
        try:
            if self.failure is not None:
                raise self.failure
            core, connection = self.core, self.connection
            if (self.original is not self or not self.active or get_ident() != self.thread
                    or core._reconciliation_prepare is not self or connection._closed_prepare is not self
                    or core._closing or core._closed or core._retired or core._host_cleanup_depth
                    or core._host_fuel_phase != 'operation' or core._host_operation_id != self.operation
                    or core._host_operation_sequence != self.operation
                    or sys.gettrace() is not None or sys.getprofile() is not None
                    or self.store._connection is not connection or self.store._physical is not self.database
                    or self.database._connection is not connection or not _CONNECTION_ELIGIBLE(connection)
                    or not connection.in_transaction or connection._transaction_epoch != self.transaction
                    or connection._outer_transaction_epoch != self.outer
                    or connection._closed_statement_epoch != self.statement
                    or connection.total_changes != self.changes):
                raise LocalStorageError('Original reconciliation phase changed or retired')
        except BaseException as error:
            raise self._fail(error)

    def check(self) -> None:
        try:
            # Only this guard's own finite dispatch tree is checked here.
            # Full continuation provenance belongs to entry/effects/return and
            # the actual Core/Store dispatches, not every repeated current call.
            if not _methods_original(self.objects, reduced=True):
                raise ValueError('Original reconciliation observation implementation changed')
            self._guard_sql()
            if not _original_shapes(self.owner, self.binding):
                raise ValueError('Original reconciliation input shape changed')
            owner, binding, core, installation = self.owner, self.binding, self.core, self.installation
            if (owner._original is not owner or not owner._entered or not owner._active
                    or owner._binding is not binding or owner._store is not self.store
                    or owner._projection is not self.projection or self.projection._saved
                    or owner._facts is not self.facts or owner._originals is not self.originals
                    or owner._lookup is not self.lookup or owner._response is not self.response
                    or owner._publisher is not self.publisher.output
                    or binding._original is not binding or not binding._active or binding._closing
                    or binding._core is not core or binding._store is not self.store
                    or binding._current is not self.current or binding._input is not self.input
                    or binding._frame_epoch is not self.epoch or binding._observed_reader is not self.reader
                    or core._host_current_binding is not binding or binding._source is not self.source
                    or binding._state is not self.state or binding._selected is not self.selected
                    or binding._expected is not self.expected or binding._fences is not self.fences
                    or installation._original is not installation or installation._closing
                    or installation._binding is not binding or installation._store is not self.store
                    or len(installation._pins) != 2 or installation._pins[0] is not self.source
                    or installation._pins[1] is not self.state
                    or self.source._installation is not installation or self.state._installation is not installation
                    or self.source._root is not installation._source or self.state._root is not installation._state
                    or self.source._store is not self.store or self.state._store is not self.store
                    or self.source._observe_roots is not None or self.state._observe_roots is not None
                    or core._closed_wasm_exports is not self.receipt
                    or core._platform_vm_original is not self.platform
                    or self.projection._cleanup is not _original_metadata_cleanup):
                raise ValueError('Original reconciliation custody changed')
            core._owned_output(self.current, 'current')
            core._owned_input(self.input)
            for original in self.expected:
                core._owned_output(original, 'original')
            self.publisher._require_live()
            callbacks = core._journal_callbacks(self.current.ticket)
            if (callbacks is None or callbacks.reader is not self.reader
                    or callbacks.current is not binding._current_observer):
                raise ValueError('Original reconciliation current callback changed')
            if callbacks.failure is not None:
                raise callbacks.failure
            for transfer in (self.lookup, self.response):
                if (transfer._original is not transfer or transfer._projection is not self.projection
                        or transfer._publisher is not self.publisher.output
                        or transfer._cleanup is not _original_metadata_cleanup
                        or transfer._stopped is not _original_metadata_stopped
                        or transfer._workspace_cleanup is not _original_metadata_cleanup
                        or transfer._workspace_stopped is not _original_metadata_cleanup
                        or transfer._closing or transfer._failed or transfer._uncertain_ticket is not None):
                    raise ValueError('Original reconciliation transfer changed')
                if transfer._workspace is None:
                    raise ValueError('Original reconciliation transfer reservation retired')
                core._owned(transfer._workspace)
            self.source._require_original_members((binding._account, *self.selected))
            self.state._require_original_members((binding._staged_account, binding._initialization,
                                                 binding._configuration, binding._journal))
            for pins in (self.source, self.state):
                pins._require_current_lifetime()
                for value in pins._files.values():
                    pins._root._owned_original(value.reader)
                    if value.reader.closing or value.reader.invalid or value.reader.descriptor is None:
                        raise ValueError('Original reconciliation Host reader retired')
            for pin in self.pins:
                pin.check()
            self._check_issued_callbacks()
            check = self.reader._prepare_check
            if check is None:
                raise ValueError('Original reconciliation reader check is unavailable')
            check(self.reader, self, False)
        except BaseException as error:
            raise self._fail(error)

    def _check_provenance(self) -> None:
        if not _methods_original(self.objects):
            raise self._fail(ValueError('Original reconciliation implementation changed'))

    def full(self) -> None:
        try:
            if self.checking:
                raise ValueError('Reentrant reconciliation physical checkpoint')
            self._check_provenance()
            self.checking = True
            self.check()
            check = self.reader._prepare_check
            if check is None:
                raise ValueError('Original reconciliation physical reader check is unavailable')
            check(self.reader, self, True)
            self.binding._physical_current()
            for pin in self.pins:
                if pin.fact._observe_reader() is not pin.result:
                    raise ValueError('Original reconciliation completed snapshot replaced')
            check(self.reader, self, True)
            self._check_provenance()
            self.check()
            self.checkpoints += 1
        except BaseException as error:
            raise self._fail(error)
        finally:
            self.checking = False

    def snapshot(self, fact: OriginalReaderFacts) -> PhysicalFileSnapshot:
        self.check()
        for pin in self.pins:
            if pin.fact is fact:
                self.snapshots += 1
                return pin.result
        raise self._fail(ValueError('Foreign original reconciliation reader facts'))

    def before_export(self, name: str, export: Any) -> None:
        self._check_provenance()
        self.check()
        if (not any(name == expected and export is original for expected, original in self.exports)
                or not self.receipt._matches(name, export, full=True)):
            raise self._fail(ValueError('Original reconciliation Wasmtime export changed'))
        # _call also performs the existing native Wasmtime qualification before
        # dispatch, and requires that genuine per-export receipt to be present.

    def after_export(self, name: str, export: Any) -> None:
        if not self.receipt._matches(name, export, full=True):
            raise self._fail(ValueError('Original reconciliation Wasmtime methods changed'))
        self.check()

    def interrupt(self, callback: Callable[..., Any], *args: Any) -> Any:
        try:
            self.full()
            self._check_effect(callback, args)
            self.suspended = True
            result = callback(*args)
            self.full()
            self.suspended = False
            return result
        except BaseException as error:
            raise self._fail(error)

    def track_output(self, ticket: int, physical: _PhysicalInput) -> None:
        # The original allocator calls this immediately after registration,
        # before any reserve export can call out. No output loan is fabricated.
        self.check()
        if (self.output_ticket is not None and (
                self.output_ticket in self.core._inputs or self.output_ticket in self.core._loans)
                or type(physical) is not _PhysicalInput
                or self.core._inputs.get(ticket) is not physical
                or physical.cleanup is not _original_metadata_cleanup
                or physical.stopped is not _original_metadata_stopped):
            raise self._fail(ValueError('Original reconciliation output registration changed'))
        self.output_ticket, self.output_physical = ticket, physical

    def retire_output(self, ticket: int) -> None:
        # Only _close_output, after the actual successful Core retirement,
        # removes this pin. Physical callback success alone cannot retire it.
        self._guard_sql()
        if (ticket != self.output_ticket or ticket in self.core._inputs
                or ticket in self.core._loans or ticket in self.core._released):
            raise self._fail(ValueError('Original reconciliation output retirement changed'))
        self.output_ticket, self.output_physical = None, None

    def track_input(self, ticket: int, physical: _PhysicalInput) -> None:
        self.check()
        if (len(self.input_pins) >= 7 or type(physical) is not _PhysicalInput
                or self.core._inputs.get(ticket) is not physical
                or physical.cleanup is not _original_metadata_cleanup
                or physical.stopped is not _original_metadata_stopped):
            raise self._fail(ValueError('Original reconciliation input registration changed'))
        self.input_pins.append((ticket, physical, physical.payload))

    def _check_issued_callbacks(self) -> None:
        if self.output_ticket is not None:
            self._check_issued(self.output_ticket, self.output_physical)
        for ticket, physical, payload in self.input_pins:
            self._check_issued(ticket, physical)
            if physical.payload is not payload:
                raise ValueError('Original reconciliation input bytes changed')

    def _check_issued(self, ticket: int, physical: _PhysicalInput) -> None:
        actual = self.core._inputs.get(ticket)
        if (actual is not physical and (actual is not None or ticket not in self.core._released)
                or physical.cleanup is not _original_metadata_cleanup
                or physical.stopped is not _original_metadata_stopped):
            raise ValueError('Original reconciliation issued cleanup callback changed')

    def _check_effect(self, callback: Callable[..., Any], args: tuple[Any, ...]) -> None:
        if (type(callback) is MethodType and callback.__self__ is self.core
                and callback.__func__ in (_CLEANUP_METHOD, _STOPPED_METHOD)):
            if not args or type(args[0]) is not int:
                raise ValueError('Invalid original reconciliation cleanup ticket')
            ticket = args[0]
            original = (self.output_physical if ticket == self.output_ticket else
                        next((physical for key, physical, _ in self.input_pins if key == ticket), None))
            if original is None:
                original = next((pin.physical for pin in self.pins if pin.input.ticket == ticket), None)
            if original is None:
                # Missing tickets execute no callback. A different live loan's
                # cleanup is outside this exact preparation's ownership.
                if ticket in self.core._inputs:
                    raise ValueError('Foreign reconciliation cleanup loan')
            else:
                self._check_issued(ticket, original)

    def query_failed(self, owner: OriginalStoreReconciliation, error: sqlite3.Error) -> None:
        # A real row query's named QueryFailed report still runs with full
        # legacy observations. This is not a new successful continuation: the
        # same error remains latched and the driver can never resume or replay.
        if (self.original is not self or not self.active or self.owner is not owner
                or get_ident() != self.thread or self.failure is not error
                or self.core._reconciliation_prepare is not self):
            raise self._fail(ValueError('Foreign original reconciliation query failure'))
        self.suspended = True

    def fence(self) -> None:
        # Keep all fourteen original fence stages, including their forty-eight
        # validator pairs and sixteen publisher authorizations for one Result.
        self._check_provenance()
        self.check()
        self.owner._before_lookup()
        self.check()

    def read(self, key: str, consume: Callable[[StoredBytes | None], object]) -> None:
        entered = False
        try:
            self._check_provenance()
            self.check()
            if self.reading or not callable(consume):
                raise ValueError('Original reconciliation row reader is already borrowed')
            self.store._key(key)
            if self.reads >= self.store._max_inspection_queries:
                raise LocalStorageError('Local publication inspection capacity exceeded')
            self.reading = entered = True
            self.fence()
            row = self.store._read_bytes_locked(key, max_bytes=self.store._max_payload_bytes - self.copied)
            self.reads += 1
            if row is not None:
                self.copied += len(row.payload)
            self.fence()
            if consume(row) is not None:
                raise ValueError('Invalid original reconciliation row consumer result')
            del row
            self.fence()
        except BaseException as error:
            raise self._fail(error)
        finally:
            if entered:
                self.reading = False

    def run(self) -> None:
        try:
            self.full()
            self.fence()
            self.owner._inspect(self.read)
            self.check()
            if not self.reads:
                raise ValueError('Incomplete original reconciliation inspection')
            self.fence()
            self.full()
        except BaseException as error:
            raise self._fail(error)

    def leave(self) -> None:
        self.active, self.suspended = False, True
        if self.connection._closed_prepare is self:
            self.connection._closed_prepare = None
        if self.core._reconciliation_prepare is self:
            self.core._reconciliation_prepare = None


def _prepare_original_reader(owner: OriginalStoreReconciliation, binding: OriginalHostBinding,
                             reader: _NamespaceReader) -> None:
    """The original current-frame protocol, with one fixed owner continuation."""
    if (type(reader) is not _NamespaceReader or reader.owner is not owner._store
            or reader._prepare_check is None or not owner._active or not owner._entered
            or binding._observed_reader is not None or not binding._active
            or binding._current is None or binding._input is None or binding._frame_epoch is None):
        raise ValueError('Original reconciliation current reader is unavailable')
    core = binding._core
    prior = binding._bound_operation
    binding._bound_operation = None
    binding._nominal()
    core._owned_output(binding._current, 'current')
    core._owned_input(binding._input)
    binding._physical_current()
    required = (*binding._fences, binding._frame_epoch)
    reader.check_fences(reader, required)
    binding._adoption_inventory(reader)
    binding._settings_inventory(reader)
    operation = core._host_operation_id
    same = (prior is not None and prior[0] == operation
            and prior[1] is binding._current and prior[2] is binding._input)
    binding._observed_reader = reader
    try:
        with core.host_current_frame(binding._current, reader):
            if not same:
                core.bind_host_current(binding._current)
            phase = _PrepareObservation(owner, binding, reader)
            core._reconciliation_prepare = phase
            phase.connection._closed_prepare = phase
            try:
                phase.run()
            finally:
                phase.leave()
                owner._prepare_counts = (phase.checkpoints, phase.reads, phase.copied,
                                         phase.snapshots // 2, phase.authorizations)
            binding._physical_current()
            if not same:
                core.validate_host_current(binding._current)
            if core._host_operation_id != operation:
                raise ValueError('Original reconciliation Host operation changed')
        binding._settings_inventory(reader)
        binding._adoption_inventory(reader)
        reader.check_fences(reader, required)
    finally:
        binding._observed_reader = None
    binding._bound_operation = (operation, binding._current, binding._input)


_METHODS += (
    _capture_prepare_methods(_ReaderPin, ('__init__', 'check', 'retained_bytes')),
    _capture_prepare_methods(_PrepareObservation, (
        '__init__', 'retained_bytes', '_fail', '_guard_sql', 'check', '_check_provenance', 'full', 'snapshot',
        'before_export', 'after_export', 'interrupt', 'track_output', 'retire_output', 'track_input',
        '_check_issued_callbacks', '_check_issued', '_check_effect', 'query_failed',
        'fence', 'read', 'run', 'leave',
    )),
)
# Twenty-eight method records cover only the transitive nominal guards above.
# Their records refer to the definition-time originals already retained here.
_REDUCED_NAMES = (
    (LocalCore, ('_owned', '_owned_input', '_owned_output', '_journal_callbacks')),
    (_OriginalPublisherPort, ('_require_live', '_require_original')),
    (OriginalHostBinding, ('current', '_nominal')),
    (LocalHostFiles, ('_require_original_members', '_require_original', '_require_current_lifetime', '_nominal')),
    (LocalFileRoot, ('_owned_reader', '_owned_finalization', '_owned', '_owned_original', '_nominal_root', '_open')),
    (OriginalReaderFacts, ('_same_material_originals', '_material_originals')),
    (_TrackedSQLiteConnection, ('_closed_eligible',)),
    (_PrepareObservation, ('_guard_sql', '_fail', 'check', '_check_issued_callbacks', '_check_issued', '_check_provenance')),
    (_ReaderPin, ('check',)),
)
_REDUCED_METHODS = tuple((cls, tuple(record for owner, members in _METHODS if owner is cls
                                   for record in members if record[0] in names))
                         for cls, names in _REDUCED_NAMES)
_CONNECTION_ELIGIBLE = next(method for cls, members in _storage_physical_methods
    if cls is _TrackedSQLiteConnection for name, method, _ in members if name == '_closed_eligible')
_ENTRY_FUNCTIONS = (_prepare_supported, _prepare_original_reader)
_FUNCTIONS = (_core_functions, _capture_prepare_functions(globals(), (
    '_methods_original', '_objects', '_original_shapes', '_prepare_supported', '_prepare_original_reader',
)))
_CLEANUP_METHOD = next(method for cls, members in _core_methods if cls is LocalCore
                       for name, method, _ in members if name == '_cleanup')
_STOPPED_METHOD = next(method for cls, members in _core_methods if cls is LocalCore
                       for name, method, _ in members if name == '_stopped')
_METHOD_BYTES = (sys.getsizeof(_METHODS) + sum(
    sys.getsizeof(entry) + sys.getsizeof(entry[1])
    + sum(sys.getsizeof(method) for method in entry[1]) for entry in _METHODS)
    + sys.getsizeof(_REDUCED_METHODS) + sum(sys.getsizeof(entry) + sys.getsizeof(entry[1])
        for entry in _REDUCED_METHODS)
    + sys.getsizeof(_FUNCTIONS) + sum(sys.getsizeof(entry) + sys.getsizeof(entry[1])
    + sum(sys.getsizeof(method) for method in entry[1]) for entry in _FUNCTIONS))

# Pre-allocation bound for this fixed program: <=256 method records, eight
# fact pins, 15 export pairs, seven registered inputs, one output, at most 36
# borrowed object references, fixed counters and an 8 KiB construction overlap.
# Referenced files, bodies and Core loans retain their separate original charges.
_PREPARE_MAX_METADATA_BYTES = (
    _METHOD_BYTES + sys.getsizeof(object.__new__(_PrepareObservation))
    + sys.getsizeof((None,) * 36) + sys.getsizeof((None,) * 8)
    + 8 * (sys.getsizeof(object.__new__(_ReaderPin))
           + sys.getsizeof((None,) * 7) + sys.getsizeof((None,) * 6))
    + sys.getsizeof((None,) * len(_EXPORT_NAMES))
    + len(_EXPORT_NAMES) * sys.getsizeof((None, None))
    + sys.getsizeof([None] * 8) + 7 * sys.getsizeof((None, None, None))
    + sys.getsizeof((None,) * 5) + 1024 + 8192
)
