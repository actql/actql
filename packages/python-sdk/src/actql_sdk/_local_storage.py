"""Physical opaque-byte persistence; Core owns every Run meaning and decision."""
from dataclasses import dataclass
import os
from pathlib import Path
import sqlite3
import stat
from threading import RLock

_APPLICATION_ID = 0x41514C42
_SCHEMA = '''CREATE TABLE core_bytes (
    key TEXT PRIMARY KEY COLLATE BINARY NOT NULL,
    generation INTEGER NOT NULL CHECK(generation >= 0),
    payload BLOB NOT NULL CHECK(typeof(payload) = 'blob')
) STRICT, WITHOUT ROWID'''
# Match the existing Native SQLite physical reservation fields. Core supplies
# the namespace, material key and amounts; this table carries no Run state.
_CAPACITY_SCHEMA = '''CREATE TABLE actql_capacity(namespace TEXT NOT NULL,reservation_key TEXT NOT NULL,reserved_bytes INTEGER NOT NULL CHECK(reserved_bytes >= 0),reserved_objects INTEGER NOT NULL CHECK(reserved_objects >= 0),PRIMARY KEY(namespace, reservation_key)) STRICT'''


@dataclass(frozen=True)
class StoredBytes:
    # A physical CAS generation, never a Run or control revision.
    generation: int
    payload: bytes


@dataclass(frozen=True)
class ByteWrite:
    # These are physical keys/generations and opaque Core-issued bytes.
    key: str
    expected_generation: int | None
    payload: bytes


@dataclass(frozen=True)
class ByteFence:
    # Original physical record observation, not authority or a Run revision.
    key: str
    generation: int
    payload: bytes


@dataclass(frozen=True)
class CapacityReservation:
    namespace: str
    key: str
    reserved_bytes: int
    reserved_objects: int


@dataclass(frozen=True)
class CapacityUsage:
    reserved_bytes: int
    reserved_objects: int


class LocalStorageError(RuntimeError):
    """Physical storage failure; it grants no execution, retry or absence fact."""


class LocalStorageInitializationError(LocalStorageError):
    def __init__(self, cleanup_store: 'LocalByteStore') -> None:
        super().__init__('Local storage initialization cleanup is pending')
        self.cleanup_store = cleanup_store


class LocalByteStore:
    """Store Core-issued bytes or trusted Host physical facts unchanged.

    This private physical adapter is not the public Run journal. Missing bytes
    and CAS conflicts must be returned to the existing Core Owners. This store
    does not interpret physical facts or turn them into Run decisions. The Host
    must reserve SQLite/Python workspace separately from the payload limits.
    """

    def __init__(self, path: Path, *, max_records: int,
                 max_record_bytes: int, max_payload_bytes: int) -> None:
        if (type(max_records) is not int or not 1 <= max_records <= 1024
                or type(max_record_bytes) is not int
                or not 1 <= max_record_bytes <= 1_048_576
                or type(max_payload_bytes) is not int
                or not max_record_bytes <= max_payload_bytes <= 16_777_216):
            raise ValueError('Invalid Local physical storage limits')
        self._lock = RLock()
        self._closed = False
        self._ready = False
        self._created = False
        self._creation_claimed = False
        self._opening_descriptor: int | None = None
        self._max_records = max_records
        self._max_record_bytes = max_record_bytes
        self._max_payload_bytes = max_payload_bytes
        # The path is installed trusted Host configuration, never Program input.
        path = path.absolute()
        parent = path.parent.lstat()
        if (not stat.S_ISDIR(parent.st_mode) or parent.st_mode & 0o077
                or parent.st_uid != os.getuid()):
            raise LocalStorageError('Local storage requires a private owned directory')
        try:
            self._opening_descriptor = os.open(
                path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            metadata = path.lstat()
            if (not stat.S_ISREG(metadata.st_mode)
                    or metadata.st_mode & 0o077
                    or metadata.st_uid != os.getuid()):
                raise LocalStorageError('Local physical storage must be a private owned file')
        else:
            self._created = True
            try:
                self._close_descriptor()
            except BaseException as original:
                raise LocalStorageInitializationError(self) from original
        self._connection = sqlite3.connect(path, isolation_level=None,
                                           timeout=1.0, check_same_thread=False)
        try:
            self._connection.execute('BEGIN IMMEDIATE')
            try:
                schema = self._connection.execute('''SELECT name, sql FROM sqlite_schema
                    WHERE name NOT LIKE 'sqlite_%' ORDER BY name''').fetchall()
                application = self._connection.execute('PRAGMA application_id').fetchone()[0]
                version = self._connection.execute('PRAGMA user_version').fetchone()[0]
                if not schema and application == 0 and version == 0:
                    self._connection.execute(_SCHEMA)
                    self._connection.execute(_CAPACITY_SCHEMA)
                    self._connection.execute(f'PRAGMA application_id = {_APPLICATION_ID}')
                    self._connection.execute('PRAGMA user_version = 2')
                elif (schema != [('actql_capacity', _CAPACITY_SCHEMA), ('core_bytes', _SCHEMA)]
                      or application != _APPLICATION_ID or version != 2):
                    raise LocalStorageError('Unknown Local physical storage format')
                self._connection.execute('COMMIT')
            except BaseException:
                if self._connection.in_transaction:
                    self._connection.execute('ROLLBACK')
                raise
            self._connection.execute('PRAGMA journal_mode = DELETE')
            self._connection.execute('PRAGMA synchronous = FULL')
            self._connection.execute('PRAGMA cache_size = -64')
            self._connection.execute('PRAGMA mmap_size = 0')
            self._connection.execute('PRAGMA temp_store = FILE')
            self._ready = True
        except BaseException as original:
            try:
                self.close()
            except BaseException:
                raise LocalStorageInitializationError(self) from original
            raise

    def claim_creation(self) -> bool:
        """Consume this handle's exclusive new-file observation once.

        Missing credentials in a reopened or populated store are not a fresh
        Host. A failed bootstrap does not restore this physical observation.
        """
        with self._lock:
            self._open()
            if not self._created or self._creation_claimed:
                return False
            self._creation_claimed = True
            return bool(self._connection.execute('''SELECT
                EXISTS(SELECT 1 FROM core_bytes) OR
                EXISTS(SELECT 1 FROM actql_capacity)''').fetchone()[0] == 0)

    def _open(self) -> None:
        if self._closed or not self._ready:
            raise LocalStorageError('Local physical storage is closed')
        if self._connection.in_transaction:
            raise LocalStorageError('Local physical storage transaction cleanup is pending')

    @staticmethod
    def _key(key: str) -> None:
        if (type(key) is not str or not key
                or len(key.encode('utf-8')) > 4096):
            raise ValueError('Invalid Local physical storage key')

    @staticmethod
    def namespaced_key(namespace: str, key: str) -> str:
        """Encode Owner-issued namespace/key as one private physical address.

        The UTF-8 byte length makes this mapping injective without normalizing
        either value. Original bare Core records are not moved or reinterpreted.
        This selects storage only; it does not assert namespace completeness,
        absence, authority, a record's meaning, or permission to write it.
        Installed Host assembly keeps this prefix separate from its bare keys.
        """
        LocalByteStore._capacity_name(namespace)
        LocalByteStore._key(key)
        physical = f'namespace:{len(namespace.encode("utf-8"))}:{namespace}:{key}'
        LocalByteStore._key(physical)
        return physical

    def read(self, key: str) -> StoredBytes | None:
        self._key(key)
        with self._lock:
            self._open()
            # CASE bounds the Python allocation even for a corrupted/foreign
            # oversized row. SQLite length(BLOB) reads its size, not its value.
            row = self._connection.execute('''SELECT generation,
                CASE WHEN length(payload) <= ? THEN payload ELSE NULL END,
                typeof(payload), length(payload)
                FROM core_bytes WHERE key = ?''',
                (self._max_record_bytes, key)).fetchone()
            if row is None:
                return None
            generation, payload, kind, length = row
            if (type(generation) is not int or generation < 0
                    or type(payload) is not bytes or kind != 'blob'
                    or type(length) is not int or length != len(payload)
                    or length > self._max_record_bytes):
                raise LocalStorageError('Invalid retained Local physical bytes')
            return StoredBytes(generation, payload)

    def compare_exchange(self, key: str, expected_generation: int | None,
                         payload: bytes) -> int | None:
        """Atomic physical CAS; a conflict performs no replacement or resend."""
        generations = self.compare_exchange_many((ByteWrite(key, expected_generation, payload),))
        return None if generations is None else generations[0]

    def read_exchange(self, write: ByteWrite) -> StoredBytes | None:
        """Read the exact successor of an original physical CAS without writing.

        A lost acknowledgement is not permission to repeat the CAS. Missing,
        changed or later bytes remain unmatched observations for the Core Owner.
        This physical match is not publication authority or a Run outcome.
        Caller-held expected bytes and returned bytes need separate reservations.
        """
        if type(write) is not ByteWrite:
            raise ValueError('Invalid Local physical write')
        self._key(write.key)
        if (write.expected_generation is not None
                and (type(write.expected_generation) is not int
                     or not 0 <= write.expected_generation < 2**63 - 1)):
            raise ValueError('Invalid Local physical CAS generation')
        if type(write.payload) is not bytes or len(write.payload) > self._max_record_bytes:
            raise ValueError('Invalid Local physical payload')
        observed = self.read(write.key)
        successor = 0 if write.expected_generation is None else write.expected_generation + 1
        if (observed is None or observed.generation != successor
                or observed.payload != write.payload):
            return None
        return observed

    @staticmethod
    def _capacity_name(name: str) -> None:
        if type(name) is not str or not 1 <= len(name.encode('utf-8')) <= 512:
            raise ValueError('Invalid Local physical capacity name')

    @staticmethod
    def _capacity_amount(amount: int) -> None:
        if type(amount) is not int or not 0 <= amount <= 2**63 - 1:
            raise ValueError('Invalid Local physical capacity amount')

    def read_capacity(self, namespace: str, key: str) -> CapacityReservation | None:
        """Observe the original reservation without acquiring or releasing it.

        Missing rows and read failures are not permission to retry a write or
        acknowledge Core's Reserved transition. The Host binds this store to
        the original Store authority before passing any observation to Core.
        """
        self._capacity_name(namespace)
        self._capacity_name(key)
        with self._lock:
            self._open()
            row = self._connection.execute('''SELECT reserved_bytes, reserved_objects
                FROM actql_capacity WHERE namespace = ? AND reservation_key = ?''',
                (namespace, key)).fetchone()
            if row is None:
                return None
            if any(type(amount) is not int or not 0 <= amount <= 2**63 - 1 for amount in row):
                raise LocalStorageError('Invalid retained Local physical capacity')
            return CapacityReservation(namespace, key, row[0], row[1])

    def capacity_usage(self, namespace: str) -> CapacityUsage:
        self._capacity_name(namespace)
        with self._lock:
            self._open()
            return self._capacity_usage_locked(namespace)

    def _capacity_usage_locked(self, namespace: str) -> CapacityUsage:
        row = self._connection.execute('''SELECT coalesce(sum(reserved_bytes), 0),
            coalesce(sum(reserved_objects), 0) FROM actql_capacity WHERE namespace = ?''',
            (namespace,)).fetchone()
        if any(type(amount) is not int or not 0 <= amount <= 2**63 - 1 for amount in row):
            raise LocalStorageError('Invalid retained Local physical capacity usage')
        return CapacityUsage(row[0], row[1])

    def reserve_capacity(self, namespace: str, key: str, reserved_bytes: int,
                         reserved_objects: int, max_bytes: int, max_objects: int) -> bool:
        """Atomically reserve exact physical amounts using Native's contract.

        Limits come from trusted Host configuration, never Program input.
        True means inserted; False means the exact reservation already existed.
        Neither is publication authority, Run admission or a retry instruction.
        Commit errors remain unknown and are never automatically repeated.
        """
        self._capacity_name(namespace)
        self._capacity_name(key)
        for amount in (reserved_bytes, reserved_objects, max_bytes, max_objects):
            self._capacity_amount(amount)
        if reserved_bytes > max_bytes or reserved_objects > max_objects:
            raise LocalStorageError('Local physical capacity exceeded')
        with self._lock:
            self._open()
            database = self._connection
            database.execute('BEGIN IMMEDIATE')
            try:
                existing = database.execute('''SELECT reserved_bytes, reserved_objects
                    FROM actql_capacity WHERE namespace = ? AND reservation_key = ?''',
                    (namespace, key)).fetchone()
                if existing is not None:
                    if existing != (reserved_bytes, reserved_objects):
                        raise LocalStorageError('Local physical capacity reservation collision')
                    database.execute('COMMIT')
                    return False
                used = self._capacity_usage_locked(namespace)
                count = database.execute('SELECT count(*) FROM actql_capacity').fetchone()[0]
                if (count >= self._max_records or used.reserved_bytes > max_bytes
                        or used.reserved_objects > max_objects
                        or reserved_bytes > max_bytes - used.reserved_bytes
                        or reserved_objects > max_objects - used.reserved_objects):
                    raise LocalStorageError('Local physical capacity exceeded')
                database.execute('INSERT INTO actql_capacity VALUES (?, ?, ?, ?)',
                                 (namespace, key, reserved_bytes, reserved_objects))
                database.execute('COMMIT')
                return True
            except BaseException:
                if database.in_transaction:
                    database.execute('ROLLBACK')
                raise

    def release_capacity(self, namespace: str, key: str,
                         reserved_bytes: int, reserved_objects: int) -> bool:
        """Release only the original exact reservation after Owner cleanup.

        The adapter does not infer cleanup from close or from missing bytes.
        True means removed; False means absent. A mismatch leaves the row intact.
        """
        self._capacity_name(namespace)
        self._capacity_name(key)
        self._capacity_amount(reserved_bytes)
        self._capacity_amount(reserved_objects)
        with self._lock:
            self._open()
            database = self._connection
            database.execute('BEGIN IMMEDIATE')
            try:
                existing = database.execute('''SELECT reserved_bytes, reserved_objects
                    FROM actql_capacity WHERE namespace = ? AND reservation_key = ?''',
                    (namespace, key)).fetchone()
                if existing is None:
                    database.execute('COMMIT')
                    return False
                if existing != (reserved_bytes, reserved_objects):
                    raise LocalStorageError('Local physical capacity reservation collision')
                database.execute('''DELETE FROM actql_capacity
                    WHERE namespace = ? AND reservation_key = ?''', (namespace, key))
                database.execute('COMMIT')
                return True
            except BaseException:
                if database.in_transaction:
                    database.execute('ROLLBACK')
                raise

    def compare_exchange_reserved(self, write: ByteWrite,
                                  capacity: CapacityReservation) -> int | None:
        """CAS original bytes only while the exact reservation is still present.

        Capacity and record are checked under one SQLite write transaction.
        A prior read alone cannot supply this fence. Neither a conflict nor an
        exception acquires capacity or authorizes another physical write.
        """
        if type(capacity) is not CapacityReservation:
            raise ValueError('Invalid Local physical capacity observation')
        generations = self.compare_exchange_many((write,), capacity=capacity)
        return None if generations is None else generations[0]

    def compare_exchange_attached(self, write: ByteWrite, original: ByteFence,
                                  capacity: CapacityReservation) -> int | None:
        """CAS separate metadata while retaining the exact original record.

        The original bytes/generation and its capacity are checked in the same
        transaction. The original record is never written or advanced. These
        are trusted Host physical observations, not admission/publication proof.
        Lost acknowledgements still require lookup of this one metadata write.
        """
        if (type(write) is not ByteWrite or type(original) is not ByteFence
                or type(capacity) is not CapacityReservation
                or write.key == original.key or capacity.key != original.key):
            raise ValueError('Invalid original Local physical metadata binding')
        generations = self.compare_exchange_many_attached((write,), ((original, capacity),))
        return None if generations is None else generations[0]

    def compare_exchange_many(self, writes: tuple[ByteWrite, ...], *,
                              capacity: CapacityReservation | None = None) -> tuple[int, ...] | None:
        """Install all opaque writes in one physical transaction or none.

        The trusted Host must first obtain the Core's full-chain validation and
        current authority. Atomic bytes do not attest a Run or publication.
        An exception, including a lost commit acknowledgement, is returned to
        that Owner without repeating the transaction. Caller-held bytes and
        SQLite workspace remain separately reserved by the Host.

        When supplied, the original capacity observation must name a key in this
        batch. Its exact retained amounts are rechecked in the same transaction;
        a changed or missing reservation leaves every write untouched. The Host
        still supplies the original Store binding and Core-issued record bytes.
        """
        return self._compare_exchange_many(writes, capacity=capacity)

    def compare_exchange_many_attached(
            self, writes: tuple[ByteWrite, ...],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...]) -> tuple[int, ...] | None:
        """Atomically attach opaque metadata to all original payload records.

        Every exact bytes/generation and reservation is checked after the same
        BEGIN IMMEDIATE, before any metadata write. Original payloads and their
        reservations are never changed. Core full-chain validation and current
        publisher authority must precede this call; these physical fences grant
        neither. Lost acknowledgements require observation, never batch replay.
        The Host separately reserves retained input bytes and SQLite workspace.
        """
        if type(originals) is not tuple or not 1 <= len(originals) <= self._max_records:
            raise ValueError('Invalid original Local physical metadata batch')
        return self._compare_exchange_many(writes, capacity=None, originals=originals)

    def _compare_exchange_many(self, writes: tuple[ByteWrite, ...], *,
                               capacity: CapacityReservation | None,
                               originals: tuple[tuple[ByteFence, CapacityReservation], ...] = ()) -> tuple[int, ...] | None:
        if type(writes) is not tuple or not 1 <= len(writes) <= self._max_records:
            raise ValueError('Invalid Local physical write batch')
        keys: set[str] = set()
        for write in writes:
            if type(write) is not ByteWrite:
                raise ValueError('Invalid Local physical write')
            self._key(write.key)
            if write.key in keys:
                raise ValueError('Duplicate Local physical write key')
            keys.add(write.key)
            if (write.expected_generation is not None
                    and (type(write.expected_generation) is not int
                         or not 0 <= write.expected_generation < 2**63 - 1)):
                raise ValueError('Invalid Local physical CAS generation')
            if type(write.payload) is not bytes or len(write.payload) > self._max_record_bytes:
                raise ValueError('Invalid Local physical payload')
        if capacity is not None:
            if type(capacity) is not CapacityReservation:
                raise ValueError('Invalid Local physical capacity observation')
            self._capacity_name(capacity.namespace)
            self._capacity_name(capacity.key)
            self._capacity_amount(capacity.reserved_bytes)
            self._capacity_amount(capacity.reserved_objects)
            if capacity.key not in keys or originals:
                raise ValueError('Local physical reservation names another record')
        original_keys: set[str] = set()
        for pair in originals:
            if type(pair) is not tuple or len(pair) != 2:
                raise ValueError('Invalid original Local physical metadata binding')
            fence, reservation = pair
            if type(fence) is not ByteFence or type(reservation) is not CapacityReservation:
                raise ValueError('Invalid original Local physical metadata binding')
            self._key(fence.key)
            self._capacity_name(reservation.namespace)
            self._capacity_name(reservation.key)
            self._capacity_amount(reservation.reserved_bytes)
            self._capacity_amount(reservation.reserved_objects)
            if (type(fence.generation) is not int
                    or not 0 <= fence.generation <= 2**63 - 1
                    or type(fence.payload) is not bytes
                    or len(fence.payload) > self._max_record_bytes
                    or fence.key in keys or fence.key in original_keys
                    or reservation.key != fence.key):
                raise ValueError('Invalid original Local physical record fence')
            original_keys.add(fence.key)
        with self._lock:
            self._open()
            database = self._connection
            database.execute('BEGIN IMMEDIATE')
            try:
                if capacity is not None:
                    retained = database.execute('''SELECT reserved_bytes, reserved_objects
                        FROM actql_capacity WHERE namespace = ? AND reservation_key = ?''',
                        (capacity.namespace, capacity.key)).fetchone()
                    if retained != (capacity.reserved_bytes, capacity.reserved_objects):
                        database.execute('ROLLBACK')
                        return None
                for fence, reservation in originals:
                    retained = database.execute('''SELECT reserved_bytes, reserved_objects
                        FROM actql_capacity WHERE namespace = ? AND reservation_key = ?''',
                        (reservation.namespace, reservation.key)).fetchone()
                    if retained != (reservation.reserved_bytes, reservation.reserved_objects):
                        database.execute('ROLLBACK')
                        return None
                    original = database.execute('''SELECT generation,
                        CASE WHEN length(payload) <= ? THEN payload ELSE NULL END
                        FROM core_bytes WHERE key = ?''',
                        (self._max_record_bytes, fence.key)).fetchone()
                    if original != (fence.generation, fence.payload):
                        database.execute('ROLLBACK')
                        return None
                generations: list[int] = []
                inserted = replaced = 0
                for write in writes:
                    existing = database.execute(
                        'SELECT generation, length(payload) FROM core_bytes WHERE key = ?',
                        (write.key,)).fetchone()
                    if (existing is None) != (write.expected_generation is None) or (
                            existing is not None and existing[0] != write.expected_generation):
                        database.execute('ROLLBACK')
                        return None
                    if existing is None:
                        inserted += 1
                        generations.append(0)
                    else:
                        replaced += existing[1]
                        generations.append(existing[0] + 1)
                count, total = database.execute(
                    'SELECT count(*), coalesce(sum(length(payload)), 0) FROM core_bytes'
                ).fetchone()
                if (count + inserted > self._max_records or
                        total - replaced + sum(len(write.payload) for write in writes)
                        > self._max_payload_bytes):
                    raise LocalStorageError('Local physical payload capacity exceeded')
                for write, generation in zip(writes, generations):
                    if write.expected_generation is None:
                        database.execute('INSERT INTO core_bytes VALUES (?, ?, ?)',
                                         (write.key, generation, write.payload))
                    else:
                        database.execute('UPDATE core_bytes SET generation = ?, payload = ? WHERE key = ?',
                                         (generation, write.payload, write.key))
                database.execute('COMMIT')
                return tuple(generations)
            except BaseException:
                # COMMIT failure is not a successful write or permission to
                # resend. Preserve the exception and the original store handle.
                if database.in_transaction:
                    database.execute('ROLLBACK')
                raise

    def close(self) -> None:
        with self._lock:
            if not self._closed:
                self._close_descriptor()
                if hasattr(self, '_connection'):
                    self._connection.close()
                self._closed = True

    def _close_descriptor(self) -> None:
        if self._opening_descriptor is not None:
            os.close(self._opening_descriptor)
            self._opening_descriptor = None

    def __enter__(self) -> 'LocalByteStore':
        self._open()
        return self

    def __exit__(self, *_: object) -> None:
        self.close()
