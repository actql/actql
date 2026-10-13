"""Original Core delivery CAS to physical SQLite; not a Read/Run Owner."""
from collections.abc import Callable
import json
from typing import Any

from ._local_core import _Input, _Workspace
from ._local_storage import ByteWrite, LocalByteStore, LocalStorageError, _NamespaceReader
from ._local_store_reconciliation import OriginalStoreReconciliation

_PLAN_BYTES = 1048576
_PLAN_WORKSPACE = 16 * _PLAN_BYTES + 8192
_TABLES = ('publication_contract', 'publication_contract', 'publication_contract',
           'delivery_attempt', 'result_read_grant_usage', 'delivery_record_head')


def _physical_plan(raw: bytes) -> tuple[ByteWrite, ...]:
    """Unwrap the closed Core packet, selecting no scope/comparison/Allow."""
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        value: dict[str, Any] = {}
        for key, body in items:
            if key in value:
                raise ValueError('Duplicate original SDK delivery projection field')
            value[key] = body
        return value
    if type(raw) is not bytes or len(raw) > _PLAN_BYTES:
        raise ValueError('Original SDK delivery projection exceeds its reservation')
    rows = json.loads(raw, object_pairs_hook=pairs)
    if type(rows) is not list or len(rows) != 6:
        raise ValueError('Incomplete original SDK delivery projection')
    writes: list[ByteWrite] = []
    for ordinal, row in enumerate(rows):
        if (type(row) is not dict or set(row) != {'body', 'key', 'revision', 'table'}
                or type(row['table']) is not str or row['table'] != _TABLES[ordinal]
                or type(row['key']) is not str or type(row['body']) is not str):
            raise ValueError('Invalid original SDK delivery physical row')
        revision = row['revision']
        if (revision is not None and (ordinal != 4 or type(revision) is not int
                                     or not 0 <= revision < 2**63)):
            raise ValueError('Invalid original SDK delivery physical revision')
        key = row['key']
        encoded_key = key if ordinal == 3 else key[7:]
        if ((ordinal != 3 and not key.startswith('sha256:')) or len(encoded_key) != 64
                or any(character not in '0123456789abcdef' for character in encoded_key)):
            raise ValueError('Invalid original SDK delivery physical key')
        body = row['body'].encode('utf-8')
        if len(body) > 65536:
            raise ValueError('Original SDK delivery metadata exceeds its original bound')
        writes.append(ByteWrite(LocalByteStore.namespaced_key(row['table'], key), revision, body))
    if len({write.key for write in writes}) != 6:
        raise ValueError('Duplicate original SDK delivery physical key')
    return tuple(writes)


class SDKDeliveryStorageCleanupPending(RuntimeError):
    def __init__(self, storage: 'OriginalSDKDeliveryStore') -> None:
        super().__init__('Original SDK delivery storage cleanup is pending')
        self.cleanup_storage = storage


class OriginalSDKDeliveryStore:
    """Keep original Store/current/reader/input/output loans during one CAS.

    Core prepares all first-installation writes before any ordinal is applied.
    Its output stays borrowed through all six writes and the final current
    check. Partial or unknown COMMIT is not replayed, acknowledged or converted
    into payload delivery. Inventory quota and durable usage adoption are
    separate original Owner obligations. This does not close the parent Run.
    """
    def __init__(self, original: OriginalStoreReconciliation, *,
                 cleanup: Callable[[], bool]) -> None:
        if type(original) is not OriginalStoreReconciliation or not callable(cleanup):
            raise ValueError('Invalid original SDK delivery Store custody')
        original._nominal()
        if (original._binding is None
                or original._binding._core is not original._projection._core
                or original._binding._store is not original._store):
            raise ValueError('Original SDK delivery requires its same Store binding')
        self._original, self._observation = self, original
        self._core = original._projection._core
        self._workspace: _Workspace | None = None
        self._uncertain_ticket: int | None = None
        self._active = self._closing = False
        self._attempted = original._sdk_delivery_request_attempts
        self._keys_attempted = original._sdk_delivery_key_attempts
        with self._core._lock:
            original._projection._ready()
            self._uncertain_ticket = self._core._next_ticket
            try:
                self._workspace = self._core.reserve_workspace(_PLAN_WORKSPACE,
                    stopped=lambda: not self._active, cleanup=cleanup)
            except BaseException as failure:
                if (self._uncertain_ticket not in self._core._inputs
                        and self._uncertain_ticket not in self._core._released):
                    self._uncertain_ticket = None
                raise SDKDeliveryStorageCleanupPending(self) from failure
            self._uncertain_ticket = None

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original SDK delivery Store custody')
        self._observation._nominal()

    def persist(self, request: _Input, original_run: int) -> tuple[int, ...]:
        with self._core._lock:
            self._nominal()
            self._core._owned_input(request)
            if (self._active or self._closing or self._workspace is None
                    or self._observation._active or not self._observation._entered):
                raise RuntimeError('Original SDK delivery storage is unavailable')
            if type(original_run) is not int or not 0 < original_run < 2**31:
                raise ValueError('Invalid original SDK delivery Run')
            self._core._owned(self._workspace)
            self._observation._projection._ready()
            if request.ticket in self._attempted:
                raise LocalStorageError('Original delivery write requires lookup; replay is unavailable')
            observation = self._observation
            binding = observation._binding
            assert binding is not None
            self._attempted.add(request.ticket)
            self._active = True
            writes: tuple[ByteWrite, ...] = ()
            try:
                with observation._serialized_facts(), binding.fenced() as fences:
                    def project(ordinal: int, consume: Callable[[ByteWrite], None]) -> None:
                        if len(writes) != 6 or not 0 <= ordinal < 6:
                            raise ValueError('Incomplete original SDK delivery write material')
                        observation._validate_facts()
                        consume(writes[ordinal])
                        observation._validate_facts()
                    def before_commit() -> None:
                        observation._before_lookup()
                        outputs = observation._projection.pending_outputs
                        if len(outputs) != 1:
                            raise ValueError('Lost original SDK delivery output borrow')
                        # A cached export rechecks current Account read, original
                        # Run/stored-chain and independent publisher; no issuance.
                        self._core.produce_publication_sdk_read_delivery_storage(
                            outputs[0], request, original_run, observation._projection._configuration)
                        observation._validate_facts()
                    def inspect(reader: _NamespaceReader, take: Callable[[], None]) -> None:
                        def prepare(_: object) -> None:
                            observation._before_lookup()
                            def transfer(raw: bytes) -> None:
                                nonlocal writes
                                writes = _physical_plan(raw)
                                attempt_key = writes[3].key
                                if attempt_key in self._keys_attempted:
                                    raise LocalStorageError('Original delivery key requires lookup; replay is unavailable')
                                self._keys_attempted.add(attempt_key)
                                take()
                            observation._projection.project_sdk_read_delivery_storage(
                                request, original_run, transfer)
                        binding.inspect_reader(reader, prepare)
                    generations = observation._store.compare_exchange_projected_inspected(
                        6, project, observation._originals, fences, inspect=inspect,
                        current=binding.current, before_commit=before_commit)
                if generations is None:
                    raise LocalStorageError('Original delivery physical CAS conflicted; lookup is required')
                return generations
            finally:
                writes = ()
                self._active = False

    def close(self) -> bool:
        with self._core._lock:
            self._nominal()
            self._closing = True
            if self._active or self._observation._projection.pending_outputs:
                return False
            if self._uncertain_ticket is not None and not self._core._closed:
                return False
            if self._workspace is not None:
                if not self._core.close_workspace(self._workspace):
                    return False
                self._workspace = None
            return True
