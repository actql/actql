"""Physical same-Store persistence of Core's original SDK read evidence.

This is neither a Read/Run Owner nor a replacement for durable delivery usage.
"""
from collections.abc import Callable
import json
from typing import Any

from ._local_core import _Input, _Workspace
from ._local_storage import ByteWrite, LocalByteStore, LocalStorageError
from ._local_store_reconciliation import OriginalStoreReconciliation

_PACKET_BYTES = 65536
_DECISION_BYTES = 6 * _PACKET_BYTES + 256
# Charge the bounded decode/key/body representation before acquiring its bytes.
_DECISION_WORKSPACE = 16 * _DECISION_BYTES + 8192


class SDKReadEvidenceCleanupPending(RuntimeError):
    def __init__(self, evidence: 'OriginalSDKReadEvidenceStore') -> None:
        super().__init__('Original SDK read evidence cleanup is pending')
        self.cleanup_evidence = evidence


def _physical_write(raw: bytes) -> ByteWrite:
    """Unwrap the closed Core projection; choose no identity, scope or Allow.

    Only the nominal producer caller below supplies this packet. Parsing one
    copied/edited packet outside that caller cannot acquire its original loans.
    """
    def pairs(items: list[tuple[str, Any]]) -> dict[str, Any]:
        result: dict[str, Any] = {}
        for key, value in items:
            if key in result:
                raise ValueError('Duplicate original SDK evidence projection field')
            result[key] = value
        return result
    if type(raw) is not bytes or len(raw) > _DECISION_BYTES:
        raise ValueError('Original SDK evidence projection exceeds its reserved transfer')
    value = json.loads(raw, object_pairs_hook=pairs)
    if (type(value) is not dict or set(value) != {'body', 'key', 'kind', 'revision', 'table'}
            or value['kind'] not in ('append', 'retained')
            or type(value['kind']) is not str
            or value['table'] != 'client_local_read_evidence'
            or type(value['revision']) is not int or value['revision'] != 0
            or type(value['body']) is not str or type(value['key']) is not str
            or len(value['key']) != 71 or not value['key'].startswith('sha256:')
            or any(character not in '0123456789abcdef' for character in value['key'][7:])):
        raise ValueError('Invalid original SDK evidence physical projection')
    body = value['body'].encode('utf-8')
    if len(body) > _PACKET_BYTES:
        raise ValueError('Original SDK evidence packet exceeds its original bound')
    # Existing insert-only Store reuse is a physical byte check. It does not
    # validate/admit the packet or grant; Core must reread it independently.
    return ByteWrite(LocalByteStore.namespaced_key('client_local_read_evidence', value['key']), None, body)


class OriginalSDKReadEvidenceStore:
    """Private synchronous transport using the original Core/File/Store frame.

    The installed assembly owns this holder and the original reconciliation,
    input and publisher. Its workspace is reserved on the same Core root before
    decoding/copying. Existing Store limits bound its physical metadata write;
    this does not supply Native's full read-custody inventory/per-Run quota proof.
    That inventory, grant persistence/usage and delivery remain separate existing
    Owner obligations, not implied by a physical generation or this helper.

    An attempted transaction is never replayed. Explicit grant projection only
    rereads the original key through Core; missing/query/changed/current failures
    retain their original meaning and all original request/output custody.
    After a failed consumer, discard its borrowed values/tracebacks and finish
    physical cleanup before explicitly retiring projection outputs and close().
    """
    def __init__(self, original: OriginalStoreReconciliation, *,
                 cleanup: Callable[[], bool]) -> None:
        if type(original) is not OriginalStoreReconciliation or not callable(cleanup):
            raise ValueError('Invalid original SDK read evidence custody')
        original._nominal()
        binding = original._binding
        if binding is None or binding._core is not original._projection._core or binding._store is not original._store:
            raise ValueError('Original SDK read evidence requires the same current Store binding')
        self._original = self
        self._observation = original
        self._core = original._projection._core
        self._cleanup = cleanup
        self._workspace: _Workspace | None = None
        self._uncertain_ticket: int | None = None
        self._attempted = original._sdk_evidence_request_attempts
        self._keys_attempted = original._sdk_evidence_key_attempts
        self._active = self._closing = False
        with self._core._lock:
            original._projection._ready()
            self._uncertain_ticket = self._core._next_ticket
            try:
                self._workspace = self._core.reserve_workspace(_DECISION_WORKSPACE,
                    stopped=lambda: not self._active, cleanup=cleanup)
            except BaseException as failure:
                if (self._uncertain_ticket not in self._core._inputs
                        and self._uncertain_ticket not in self._core._released):
                    self._uncertain_ticket = None
                raise SDKReadEvidenceCleanupPending(self) from failure
            self._uncertain_ticket = None

    def _nominal(self) -> None:
        if self._original is not self:
            raise ValueError('Copied original SDK read evidence custody')

    def _ready(self, request: _Input) -> None:
        self._nominal()
        self._observation._nominal()
        self._core._owned_input(request)
        if self._closing or self._active or self._workspace is None:
            raise RuntimeError('Original SDK read evidence transfer is unavailable')
        self._core._owned(self._workspace)
        if self._observation._active or not self._observation._entered:
            raise RuntimeError('Original SDK read Store observation is unavailable')
        self._observation._projection._ready()

    def persist(self, request: _Input, original_run: int) -> tuple[int, ...]:
        """Physically store the Core proposal once, returning no ACK or grant."""
        with self._core._lock:
            self._ready(request)
            if type(original_run) is not int or not 0 < original_run < 2**31:
                raise ValueError('Invalid original SDK read Run')
            if request.ticket in self._attempted:
                raise LocalStorageError('Original SDK evidence write requires lookup; replay is unavailable')
            observation = self._observation
            binding = observation._binding
            assert binding is not None
            with observation._serialized_facts():
                with binding.fenced() as fences:
                    # Retain the original attempt before entering any fallible
                    # transaction. Unknown never permits another insert.
                    self._attempted.add(request.ticket)
                    self._active = True
                    try:
                        def project(ordinal: int, consume: Callable[[ByteWrite], None]) -> None:
                            if ordinal != 0:
                                raise ValueError('Invalid original SDK evidence physical ordinal')
                            def transfer(raw: bytes) -> None:
                                observation._validate_facts()
                                write = _physical_write(raw)
                                # Core chooses this identity. A new transport
                                # or copied request bytes cannot replay an
                                # attempted original key after a lost reply.
                                if write.key in self._keys_attempted:
                                    raise LocalStorageError('Original SDK evidence key requires lookup; replay is unavailable')
                                self._keys_attempted.add(write.key)
                                consume(write)
                                observation._validate_facts()
                            observation._projection.project_sdk_read_evidence_decision(
                                request, original_run, transfer)
                        result = observation._store.store_publication_projected_inspected(
                            1, project, observation._originals, fences,
                            inspect=lambda reader, consume: binding.inspect_reader(reader,
                                lambda _: self._consume_current(consume)),
                            current=binding._current_observer, before_commit=observation._before_lookup)
                    finally:
                        self._active = False
                if result is None:
                    raise LocalStorageError('Original SDK evidence physical conflict; lookup is required')
                return result

    def _consume_current(self, consume: Callable[[], None]) -> None:
        # Run the original lookup/publisher checks only inside this borrowed
        # current namespace frame, not in a previous read transaction.
        self._observation._before_lookup()
        consume()

    def project_grant(self, request: _Input, original_run: int,
                      consume: Callable[[ByteWrite], object]) -> None:
        """Core rereads this same Store; no write retry or usage claim occurs."""
        with self._core._lock:
            self._ready(request)
            if not callable(consume):
                raise ValueError('Invalid original SDK grant consumer')
            self._active = True
            try:
                self._observation.project_sdk_read_grant(request, original_run, consume)
            finally:
                self._active = False

    def close(self) -> bool:
        """Return only this workspace after actual consumer/output cleanup."""
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
