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
                    self._connection.execute(f'PRAGMA application_id = {_APPLICATION_ID}')
                    self._connection.execute('PRAGMA user_version = 1')
                elif (schema != [('core_bytes', _SCHEMA)]
                      or application != _APPLICATION_ID or version != 1):
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
            return bool(self._connection.execute('SELECT EXISTS(SELECT 1 FROM core_bytes)').fetchone()[0] == 0)

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

    def compare_exchange_many(self, writes: tuple[ByteWrite, ...]) -> tuple[int, ...] | None:
        """Install all opaque writes in one physical transaction or none.

        The trusted Host must first obtain the Core's full-chain validation and
        current authority. Atomic bytes do not attest a Run or publication.
        An exception, including a lost commit acknowledgement, is returned to
        that Owner without repeating the transaction. Caller-held bytes and
        SQLite workspace remain separately reserved by the Host.
        """
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
        with self._lock:
            self._open()
            database = self._connection
            database.execute('BEGIN IMMEDIATE')
            try:
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
