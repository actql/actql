"""Bounded physical query transport; original Core Owners decide inventory facts."""
from dataclasses import dataclass
from collections.abc import Callable
import json
from ._local_storage import _NamespaceReader, StoredBytes, LocalByteStore

_QUERY_BYTES = 8192
_KEY_BYTES = 4096
_ROW_BYTES = 262144


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
                # An older private supplier keeps the complete original path.
                # A failed observation never falls through to this branch.
                return 0 if self.check_current() == 0 else -41
            value = observe(reader, self.current)
            if self.reader is not reader or type(value) is not int or value not in (0, 1):
                raise ValueError('Invalid original Journal schema observation')
            return value
        except BaseException as error:
            return self._fail(error)

    def begin(self, mode: int, namespace_length: int, key_length: int) -> int:
        try:
            if (self.request is not None or self.queried or self.row is not None
                    or type(mode) is not int or mode not in (0, 1, 2)
                    or type(namespace_length) is not int or not 0 < namespace_length <= _KEY_BYTES
                    or type(key_length) is not int or not 0 <= key_length <= _KEY_BYTES
                    or (mode in (1, 2) and key_length == 0)
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

            if self.mode == 2:
                # This mode compares only immutable stored publication fences.
                # It returns DATA equality, never an Allow or current token.
                if namespace != 'publication_contract':
                    raise ValueError('Invalid original publication fence namespace')
                match_rows = getattr(reader, 'match_rows_current', None)
                if match_rows is None:
                    # No row I/O occurred. An independent physical adapter's
                    # absent batch primitive selects its existing scalar path.
                    return 2
                packet = json.loads(key)
                if type(packet) is not list or not 1 <= len(packet) <= 32:
                    raise ValueError('Invalid original publication fence packet')
                rows = []
                for item in packet:
                    if (type(item) is not list or len(item) != 3
                            or any(type(value) is not str for value in item)):
                        raise ValueError('Invalid original publication fence fields')
                    name, revision, body = item
                    if (not revision or len(revision) > 19
                            or any(c < '0' or c > '9' for c in revision)
                            or len(revision) > 1 and revision[0] == '0'
                            or int(revision) >= 2**63):
                        raise ValueError('Invalid original publication fence revision')
                    rows.append((name, int(revision), body.encode('utf-8')))
                matched = match_rows(reader, namespace, tuple(rows), self.current)
                if self.reader is not reader or type(matched) is not bool:
                    raise ValueError('Original publication fence observation changed')
                if self.check_frame() != 0:
                    return -41
                return 0 if matched else 1

            def consume(row: tuple[str, StoredBytes] | None) -> None:
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
                # The exact borrowed immutable payload stays under this reserved
                # ticket until Core finishes copying/consuming and releases it.
                self.row = (encoded, body)

            if query_current is not None:
                # The original Store has completed the query/current fences.
                # Only this closed bounded packaging runs before ABI transfer;
                # there is no external consumer callback to fence separately.
                consume(query_current(reader, self.mode, namespace, key, self.current))
            elif self.mode == 0:
                reader.scan_after(namespace, key, consume)
            else:
                reader.read(namespace, key, consume)
            if (self.check_current() if query_current is None else self.check_frame()) != 0:
                return -41
            # Only the actual physical reader's confirmed miss/end yields 1.
            return 1 if self.row is None else 0
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
        self.row = None
        self.request = None
        self.received = 0
        self.namespace_length = 0
        self.mode = -1
        self.queried = False
        return 0 if self.failure is None else -41
