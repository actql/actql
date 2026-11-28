"""Bounded physical query transport; original Core Owners decide inventory facts."""
from dataclasses import dataclass
from collections.abc import Callable, Iterator
from contextlib import ExitStack as _ExitStack
from contextlib import contextmanager
from typing import NamedTuple
from ._local_storage import (_JOURNAL_NAME_AUTHENTICATE, _JOURNAL_NAME_KEY_SCAN, _JOURNAL_NAME_TABLE,
                             _NamespaceReader, _TargetKey, _TargetRead, StoredBytes, LocalByteStore)

_QUERY_BYTES = 8192
_KEY_BYTES = 4096
_ROW_BYTES = 262144
# Cumulative copied bytes, with at most one Host row held at a time. Common
# must still see the first invalid row after a valid 256 KiB material prefix.
_TASK_MATERIAL_BATCH_COPY_BYTES = 2 * _ROW_BYTES
_TASK_MATERIAL_NAMESPACE = 'client_task_run_materials'


class _JournalRowTransfer(NamedTuple):
    # A true immutable tuple, including against object.__setattr__. Callback
    # mutations cannot rewrite the comparison baseline or retained originals.
    # These are physical aliases only, never a Store or permission owner.
    physical: object
    reader: _NamespaceReader
    memory: object
    row: tuple[bytes, StoredBytes]
    ticket: int
    store: LocalByteStore
    current: Callable[[], object]
    key: bytes
    body: bytes
    generation: int
    task_material_scope: object | None = None


@dataclass(slots=True)
class _JournalCallbacks:
    # Registered under an original Core buffer ticket before any callback I/O.
    # This is a transient physical loan, never Run/recovery/authorization state.
    current: Callable[[], object]
    store: LocalByteStore
    reader: _NamespaceReader | None = None
    failure: BaseException | None = None
    request: bytearray | None = None
    received: int = 0
    namespace_length: int = 0
    mode: int = -1
    row: tuple[bytes, StoredBytes] | None = None
    queried: bool = False
    transfer: _JournalRowTransfer | None = None
    transfer_ready: bool = False
    transfer_started: bool = False
    name_authenticate: Callable[[bytes], bytes] | None = None
    task_material_scope: object | None = None
    task_material_take: Callable[[int], int] | None = None
    task_material_frame: _ExitStack | None = None
    task_material_run_key: bytes | None = None
    saved_identity_request: tuple[bytes, int, int] | None = None
    saved_identity_child: _ExitStack | None = None
    saved_identity_final_copy: bool = False
    physical_reader_serial: int = 0

    def _fail(self, error: BaseException) -> int:
        if self.failure is None:
            self.failure = error
        return -41

    def check_current(self) -> int:
        if self.failure is not None:
            return -41
        try:
            if (self.reader is None or self.reader.owner is not self.store
                    or self.failure is not None):
                raise ValueError('Original Local journal snapshot is unavailable')
            self.reader.check_fences_and_current(self.reader, (), self.current)
            return 0
        except BaseException as error:
            return self._fail(error)

    def check_frame(self) -> int:
        """Borrow transport only; query/current checks still observe originals.

        Request blocks and the immutable returned row do not make a decision.
        They remain inside the same non-reentrant SQL reader and ticket. A
        private scalar reader without this actual port retains full checks.
        """
        if self.failure is not None:
            return -41
        try:
            reader = self.reader
            if reader is None or reader.owner is not self.store:
                raise ValueError('Original Local journal snapshot is unavailable')
            frame = getattr(reader, 'check_frame', None)
            if frame is None:
                return self.check_current()
            frame(reader)
            return 0
        except BaseException as error:
            return self._fail(error)

    def schema(self) -> int:
        """Observe only the actual borrowed catalog, never return an Allow."""
        if self.failure is not None:
            return -41
        try:
            reader = self.reader
            if reader is None or reader.owner is not self.store:
                raise ValueError('Original Local Journal schema reader is unavailable')
            observe = getattr(reader, 'journal_schema', None)
            if observe is None:
                raise ValueError('Original Local Journal catalog observation is unavailable')
            value = observe(reader, self.current)
            if self.reader is not reader or value is not None:
                raise ValueError('Invalid original Journal schema observation')
            return 1
        except BaseException as error:
            return self._fail(error)

    def begin(self, mode: int, namespace_length: int, key_length: int) -> int:
        try:
            # A released row leaves the same reader available for the original
            # current check between takes. A pending row still blocks entry.
            if (self.request is not None or self.queried or self.row is not None
                    or self.transfer is not None
                    or type(mode) is not int
                    or mode not in (0, 1, _JOURNAL_NAME_KEY_SCAN, _JOURNAL_NAME_AUTHENTICATE)
                    or type(namespace_length) is not int or not 0 < namespace_length <= _KEY_BYTES
                    or type(key_length) is not int or not 0 <= key_length <= _KEY_BYTES
                    or (mode in (1, _JOURNAL_NAME_AUTHENTICATE) and key_length == 0)
                    or namespace_length + key_length > _QUERY_BYTES):
                raise ValueError('Invalid original Local journal physical query')
            if self.check_frame() != 0:
                return -41
            # The Core buffer's prior reservation covers request/row copies.
            self.request = bytearray(namespace_length + key_length)
            self.received = 0
            self.namespace_length = namespace_length
            self.mode = mode
            return 0
        except BaseException as error:
            return self._fail(error)

    def byte(self, index: int, byte: int) -> int:
        try:
            if (self.request is None or self.failure is not None or self.queried
                    or type(index) is not int or index != self.received
                    or not 0 <= index < len(self.request)
                    or type(byte) is not int or not 0 <= byte <= 255):
                raise ValueError('Invalid original Local journal query byte')
            self.request[index] = byte
            self.received += 1
            return 0
        except BaseException as error:
            return self._fail(error)

    def query_copy(self, index: int, payload: bytes) -> int:
        try:
            original = self.request
            if (original is None or self.failure is not None or self.queried
                    or type(index) is not int or index != self.received
                    or type(payload) is not bytes or not 0 < len(payload) <= 16384
                    or index < 0 or index > len(original)
                    or len(payload) > len(original) - index):
                raise ValueError('Invalid original Local query block')
            if self.check_frame() != 0:
                return -41
            if self.request is not original or self.received != index or self.queried:
                raise ValueError('Original Local query changed during current check')
            original[index:index + len(payload)] = payload
            self.received += len(payload)
            return len(payload)
        except BaseException as error:
            return self._fail(error)

    def row_copy(self, field: int, index: int, length: int) -> bytes:
        original = self.row
        if (original is None or not self.queried or self.failure is not None
                or type(field) is not int or field not in (0, 1)
                or type(index) is not int or index < 0
                or type(length) is not int or not 0 < length <= 16384):
            raise ValueError('Invalid original Local row block')
        payload = original[0] if field == 0 else original[1].payload
        if index > len(payload) or length > len(payload) - index:
            raise ValueError('Original Local row block exceeds its field')
        if self.check_frame() != 0:
            raise ValueError('Original Local row current check failed')
        if self.row is not original or not self.queried:
            raise ValueError('Original Local row changed during current check')
        return payload[index:index + length]

    def _retain_row(self, row: tuple[str, StoredBytes] | None) -> None:
        if row is None:
            return
        if type(row) is not tuple or len(row) != 2:
            raise ValueError('Invalid original Local journal physical row')
        name, body = row
        if type(name) is not str:
            raise ValueError('Invalid original Local journal physical row')
        encoded = name.encode('utf-8')
        if (not 0 < len(encoded) <= _KEY_BYTES or type(body) is not StoredBytes
                or type(body.payload) is not bytes or len(body.payload) > _ROW_BYTES
                or type(body.generation) is not int or not 0 <= body.generation < 2**63):
            raise ValueError('Invalid original Local journal physical row')
        # This same reserved ticket owns the immutable row until copy/release.
        self.row = (encoded, body)

    def _check_returned_row(self, reader: _NamespaceReader, *, frame_only: bool) -> int:
        # Frozen StoredBytes can still be changed by an ill-behaved callback.
        original = self.row
        original_key = None if original is None else original[0]
        original_body = None if original is None else original[1].payload
        original_generation = None if original is None else original[1].generation
        if (self.check_frame() if frame_only else self.check_current()) != 0:
            return -41
        if (self.reader is not reader or self.row is not original
                or original is not None and (original[0] is not original_key
                    or original[1].payload is not original_body
                    or type(original[1].generation) is not int
                    or original[1].generation != original_generation)):
            raise ValueError('Original Local journal returned row changed')
        # Only a confirmed physical miss/end returns 1.
        return 1 if original is None else 0

    @contextmanager
    def task_material_rows(self, run_key: str, max_bytes: int) -> Iterator[Callable[[int], int]]:
        """Borrow four exact task-material slots from the current physical reader."""
        if (type(run_key) is not str or len(run_key) != 71 or not run_key.startswith('sha256:')
                or any(ch not in '0123456789abcdef' for ch in run_key[7:])):
            error = ValueError('Invalid original Local task-material loan')
            self._fail(error)
            assert self.failure is not None
            raise self.failure
        keys = tuple((_TASK_MATERIAL_NAMESPACE, f'{run_key}:{ordinal}') for ordinal in range(4))
        with self._target_rows(keys, max_bytes) as take:
            yield take

    @contextmanager
    def saved_identity_rows(self, submission: str, run: str,
                            sizes: tuple[int, int], max_bytes: int) -> Iterator[Callable[[int], int]]:
        """Use the same physical target port for the two retained identity rows."""
        for key in (submission, run):
            if (type(key) is not str or len(key) != 71 or not key.startswith('sha256:')
                    or any(ch not in '0123456789abcdef' for ch in key[7:])):
                error = ValueError('Invalid original Saved identity key')
                self._fail(error)
                assert self.failure is not None
                raise self.failure
        with self._target_rows((('client_submitted_intents', submission, sizes[0]),
                                ('client_runs', run, sizes[1])), max_bytes) as take:
            yield take

    @contextmanager
    def _target_rows(self, requests: tuple[_TargetKey, ...],
                     max_bytes: int) -> Iterator[Callable[[int], int]]:
        reader, current, store = self.reader, self.current, self.store
        scope = object()

        def require_scope(original_reader: _NamespaceReader, original_current: Callable[[], object],
                          original_store: LocalByteStore) -> None:
            if self.failure is not None:
                raise self.failure
            if (self.task_material_scope is not scope or self.reader is not original_reader
                    or self.current is not original_current or self.store is not original_store):
                raise ValueError('Original Local task-material loan expired or changed')

        try:
            if self.failure is not None:
                raise self.failure
            if (type(reader) is not _NamespaceReader or reader.owner is not store
                    or reader.get_many is None or self.task_material_scope is not None
                    or self.request is not None or self.queried or self.row is not None
                    or self.transfer is not None
                    or type(max_bytes) is not int or not 0 <= max_bytes <= _TASK_MATERIAL_BATCH_COPY_BYTES):
                raise ValueError('Invalid original Local task-material loan')
        except BaseException as error:
            self._fail(error)
            raise

        self.task_material_scope = scope
        active: tuple[_NamespaceReader, Callable[[], object], LocalByteStore, _TargetRead,
                      tuple[str, ...]] | None = None
        try:
            try:
                keys = tuple(request[1] for request in requests)
                take_body = reader.get_many(reader, requests, max_bytes, current)
                require_scope(reader, current, store)
            except BaseException as error:
                self._fail(error)
                if self.failure is not None and self.failure is not error:
                    raise self.failure from error
                raise

            active = (reader, current, store, take_body, keys)

            def take(ordinal: int) -> int:
                try:
                    if active is None:
                        raise ValueError('Original Local task-material loan expired or changed')
                    physical_reader, observer, owner, take_original_body, original_keys = active
                    require_scope(physical_reader, observer, owner)
                    if (type(ordinal) is not int or not 0 <= ordinal < len(original_keys)
                            or self.queried or self.row is not None or self.transfer is not None):
                        raise ValueError('Invalid original Local task-material take')
                    self.queried = True
                    body = take_original_body(physical_reader, ordinal)
                    require_scope(physical_reader, observer, owner)
                    if self.queried is not True or self.row is not None or self.transfer is not None:
                        raise ValueError('Original Local task-material row changed')
                    changed = body is False
                    self._retain_row(None if body is None or body is False else (original_keys[ordinal], body))
                    result = self._check_returned_row(physical_reader, frame_only=True)
                    require_scope(physical_reader, observer, owner)
                    if self.queried is not True:
                        raise ValueError('Original Local task-material row changed')
                    # Code 2 is an observed original mismatch, not missing data.
                    return 2 if changed and result == 1 else result
                except BaseException as error:
                    return self._fail(error)

            self.task_material_take = take
            yield take
        finally:
            active = None
            self.task_material_take = None
            self.task_material_scope = None

    def query(self) -> int:
        try:
            if (self.request is None or self.received != len(self.request)
                    or self.queried):
                raise ValueError('Incomplete original Local journal physical query')
            reader = self.reader
            if reader is None:
                raise ValueError('Original Local journal transaction loan expired')
            query_current = getattr(reader, 'query_current', None)
            if (self.check_current() if query_current is None else self.check_frame()) != 0:
                return -41
            self.queried = True
            namespace = self.request[:self.namespace_length].decode('utf-8')
            key = self.request[self.namespace_length:].decode('utf-8')
            self.request = None
            if self.reader is not reader:
                raise ValueError('Original Local journal transaction loan expired')

            if self.mode == _JOURNAL_NAME_KEY_SCAN and (
                    query_current is None or namespace != _JOURNAL_NAME_TABLE):
                raise ValueError('Original Local name key scan is unavailable')
            if self.mode == _JOURNAL_NAME_AUTHENTICATE:
                authenticate = self.name_authenticate
                if authenticate is None or namespace != _JOURNAL_NAME_TABLE:
                    raise ValueError('Original Local name authentication is unavailable')
                authenticator = authenticate(key.encode('utf-8'))
                if (self.reader is not reader or self.name_authenticate is not authenticate
                        or type(authenticator) is not bytes or len(authenticator) != 32):
                    raise ValueError('Original Local name authentication changed')
                self._retain_row(('authenticator', StoredBytes(0, authenticator)))
            elif query_current is not None:
                # The original Store has completed the query/current fences.
                # Only this closed bounded packaging runs before ABI transfer;
                # there is no external consumer callback to fence separately.
                self._retain_row(query_current(reader, self.mode, namespace, key, self.current))
            elif self.mode == 0:
                reader.scan_after(namespace, key, self._retain_row)
            else:
                reader.read(namespace, key, self._retain_row)
            return self._check_returned_row(reader, frame_only=query_current is not None)
        except BaseException as error:
            return self._fail(error)

    def length(self, field: int) -> int:
        if self.failure is not None or not self.queried or self.row is None:
            return -41
        if field == 0:
            return len(self.row[0])
        if field == 1:
            return len(self.row[1].payload)
        return -41

    def row_byte(self, field: int, index: int) -> int:
        if (type(index) is not int or self.failure is not None
                or self.row is None or not self.queried):
            return -41
        payload = self.row[0] if field == 0 else self.row[1].payload if field == 1 else b''
        return payload[index] if 0 <= index < len(payload) else -41

    def revision(self) -> int:
        return (-1 if self.failure is not None or not self.queried or self.row is None
                else self.row[1].generation)

    def release(self) -> int:
        # Release only the transient query copy. This is not transaction
        # cleanup, COMMIT, acknowledgement, Run completion or buffer retirement.
        self.transfer = None
        self.transfer_ready = False
        self.transfer_started = False
        self.row = None
        self.request = None
        self.received = 0
        self.namespace_length = 0
        self.mode = -1
        self.queried = False
        return 0 if self.failure is None else -41
