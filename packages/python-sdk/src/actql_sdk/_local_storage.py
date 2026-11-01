"""Physical opaque-byte persistence; Core owns every Run meaning and decision."""
from collections.abc import Callable
from dataclasses import dataclass
import os
from pathlib import Path
import sqlite3
import stat
from threading import RLock, get_ident

from ._local_files import LocalFileRoot, _PayloadFile
from ._local_storage_physical import (
    _PhysicalByteDatabase, _SQLiteByteDatabase,
    _PhysicalCapacityCollision, _PhysicalCapacityExceeded, _RUN_DEFINITION_INDEX,
    _APPLICATION_ID, _SCHEMA, _CAPACITY_SCHEMA, _RUN_DEFINITION_PROBE)




@dataclass(frozen=True)
class StoredBytes:
    # A physical CAS generation, never a Run or control revision.
    generation: int
    payload: bytes


_NamespaceConsumer = Callable[[tuple[str, StoredBytes] | None], object]


@dataclass(frozen=True, slots=True)
class _NamespaceReader:
    # One physical transaction loan, not completeness or admission proof.
    scan_after: Callable[[str, str, _NamespaceConsumer], None]
    read: Callable[[str, str, _NamespaceConsumer], None]
    owner: 'LocalByteStore'
    current: Callable[[], None]
    check_fences: Callable[['_NamespaceReader', tuple['ByteFence', ...]], None]
    check_fences_and_current: Callable[
        ['_NamespaceReader', tuple['ByteFence', ...], Callable[[], object]], None]
    # Only the actual Store supplies this live-thread/frame check. It is not
    # a current observation; queries and protected decisions keep their fences.
    check_frame: Callable[['_NamespaceReader'], None] | None = None
    # The closed journal transport returns only immutable physical row DATA.
    # Arbitrary consumers keep read/scan_after and their post-consumer fence.
    query_current: Callable[['_NamespaceReader', int, str, str,
                             Callable[[], object]], tuple[str, StoredBytes] | None] | None = None

    # Actual same-transaction catalog observation, not an indexed-custody proof.
    # Absence keeps existing private suppliers on their full legacy route.
    journal_schema: Callable[['_NamespaceReader', Callable[[], object]], int] | None = None


_InventoryInspection = Callable[[_NamespaceReader], object]


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


class LocalStorageCommitUnknown(LocalStorageError):
    """COMMIT was attempted; retain the same Store and inspect original bytes.

    This physical exception claims no Run outcome or retry permission. A
    current-port refusal after COMMIT cannot become a pre-write refusal.
    """

    def __init__(self, cleanup_store: 'LocalByteStore') -> None:
        super().__init__('Local physical COMMIT outcome is unknown')
        self.cleanup_store = cleanup_store


class LocalStorageInitializationError(LocalStorageError):
    def __init__(self, cleanup_store: 'LocalByteStore') -> None:
        super().__init__('Local storage initialization cleanup is pending')
        self.cleanup_store = cleanup_store


class _ProjectedWriteConflict(Exception):
    """Internal physical CAS refusal; not a Run or publication outcome."""


class LocalByteStore:
    """Store Core-issued bytes or trusted Host physical facts unchanged.

    This private physical adapter is not the public Run journal. Missing bytes
    and CAS conflicts must be returned to the existing Core Owners. This store
    does not interpret physical facts or turn them into Run decisions. The Host
    must reserve SQLite/Python workspace separately from the payload limits.
    """

    _physical: _PhysicalByteDatabase
    _physical_path: Path
    _physical_original: tuple[int, int] | None
    _opening_descriptor: int | None
    _native_file_root: LocalFileRoot | None

    def __init__(self, path: Path, *, max_records: int,
                 max_record_bytes: int, max_payload_bytes: int,
                 max_inspection_queries: int | None = None,
                 _new_file: tuple[LocalFileRoot, _PayloadFile] | None = None) -> None:
        self._prepare_physical_path(path, max_records=max_records,
                                    max_record_bytes=max_record_bytes,
                                    max_payload_bytes=max_payload_bytes,
                                    max_inspection_queries=max_inspection_queries)
        path = self._physical_path
        if _new_file is not None:
            if (type(_new_file) is not tuple or len(_new_file) != 2
                    or type(_new_file[0]) is not LocalFileRoot
                    or type(_new_file[1]) is not _PayloadFile):
                raise ValueError('Invalid original empty Local Store acquisition')
            observed = _new_file[0].claim_empty_store_file(_new_file[1], path)
            self._created = True
            self._physical_original = (observed.device, observed.inode)
        else:
            try:
                self._opening_descriptor = os.open(
                    path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            except FileExistsError:
                metadata = path.lstat()
                if (not stat.S_ISREG(metadata.st_mode)
                        or metadata.st_mode & 0o077
                        or metadata.st_uid != os.getuid()):
                    raise LocalStorageError('Local physical storage must be a private owned file')
                self._physical_original = self._file_generation(metadata)
            else:
                self._created = True
                try:
                    self._physical_original = self._file_generation(os.fstat(self._opening_descriptor))
                    self._close_descriptor()
                except BaseException as original:
                    raise LocalStorageInitializationError(self) from original
        self._connection = sqlite3.connect(path, isolation_level=None,
                                           timeout=1.0, check_same_thread=False)
        try:
            database = _SQLiteByteDatabase(self._connection)
            self._physical = database
            self._observe_generation()
            self._connection.execute('BEGIN IMMEDIATE')
            try:
                schema = self._connection.execute('''SELECT 1 FROM main.sqlite_schema
                    WHERE name NOT LIKE 'sqlite_%' LIMIT 1''').fetchone()
                application = self._connection.execute('PRAGMA application_id').fetchone()[0]
                version = self._connection.execute('PRAGMA user_version').fetchone()[0]
                if not schema and application == 0 and version == 0:
                    if not self._created:
                        raise LocalStorageError('Reopened empty Local Store has no initialization custody')
                    self._connection.execute(_SCHEMA)
                    self._connection.execute(_CAPACITY_SCHEMA)
                    self._connection.execute(f'PRAGMA application_id = {_APPLICATION_ID}')
                    version = 2
                    if _new_file is not None:
                        # Probe only the original library before index mutation.
                        # Missing optional JSON support keeps the existing full
                        # legacy route; unrelated failure is never a fallback.
                        try:
                            probe = self._connection.execute(_RUN_DEFINITION_PROBE).fetchone()
                        except sqlite3.OperationalError as error:
                            if (getattr(error, 'sqlite_errorcode', None) != sqlite3.SQLITE_ERROR
                                    or str(error) != 'no such function: json_extract'):
                                raise
                        else:
                            if probe != ('probe',):
                                raise LocalStorageError('Original index expression probe was inconsistent')
                            version = 3
                    if version == 3:
                        # Only the existing one-time original file acquisition
                        # creates this format. Reopen never installs or repairs it.
                        self._connection.execute(_RUN_DEFINITION_INDEX)
                    self._connection.execute(f'PRAGMA user_version = {version}')
                else:
                    try:
                        database._journal_schema()
                    except ValueError as error:
                        raise LocalStorageError('Unknown Local physical storage format') from error
                self._connection.execute('COMMIT')
            except BaseException:
                if self._physical.in_transaction:
                    self._connection.execute('ROLLBACK')
                raise
            self._connection.execute('PRAGMA journal_mode = DELETE')
            self._connection.execute('PRAGMA synchronous = FULL')
            self._connection.execute('PRAGMA cache_size = -64')
            self._connection.execute('PRAGMA mmap_size = 0')
            self._connection.execute('PRAGMA temp_store = FILE')
            self._observe_generation()
            self._ready = True
        except BaseException as original:
            try:
                self.close()
            except BaseException:
                raise LocalStorageInitializationError(self) from original
            raise

    def _prepare_physical_path(self, path: Path, *, max_records: int,
                               max_record_bytes: int, max_payload_bytes: int,
                               max_inspection_queries: int | None = None) -> None:
        # Shared physical metadata only. No file, SQL connection, adoption or
        # fresh-file claim is acquired by this helper.
        if (type(max_records) is not int or not 1 <= max_records <= 1024
                or type(max_record_bytes) is not int
                or not 1 <= max_record_bytes <= 1_048_576
                or type(max_payload_bytes) is not int
                or not max_record_bytes <= max_payload_bytes <= 16_777_216
                or max_inspection_queries is not None and (
                    type(max_inspection_queries) is not int
                    or not 1 <= max_inspection_queries <= 65536)):
            raise ValueError('Invalid Local physical storage limits')
        self._lock = RLock()
        self._closed = False
        self._ready = False
        self._created = False
        self._creation_claimed = False
        self._opening_descriptor = None
        self._max_records = max_records
        self._max_record_bytes = max_record_bytes
        self._max_payload_bytes = max_payload_bytes
        # Durable row capacity and repeated inspection work are independent.
        # Unselected callers retain the original query ceiling exactly.
        self._max_inspection_queries = (max_records if max_inspection_queries is None
                                        else max_inspection_queries)
        # The path is installed trusted Host configuration, never Program input.
        path = path.absolute()
        parent = path.parent.lstat()
        if (not stat.S_ISDIR(parent.st_mode) or parent.st_mode & 0o077
                or parent.st_uid != os.getuid()):
            raise LocalStorageError('Local storage requires a private owned directory')
        self._physical_path = path
        self._physical_parent = (parent.st_dev, parent.st_ino)
        self._physical_original = None
        self._physical_owner = self
        self._native_file_root = None

    @classmethod
    def initialize_owned_file(cls, path: Path, root: LocalFileRoot, original: _PayloadFile, *,
                              max_records: int, max_record_bytes: int,
                              max_payload_bytes: int,
                              max_inspection_queries: int | None = None) -> 'LocalByteStore':
        """Open the same newly acquired file after the Host's durable marker.

        The original File Owner supplies the one-time physical claim, never a
        caller boolean or a later pathname. The caller retains that writer until
        explicit stop and keeps partial files/marker on failure. This creates
        the existing physical schema only; original key/adoption rows and Core
        verification remain separate. Reopen cannot use this entry to repair
        missing custody or retry unknown initialization.
        """
        if type(root) is not LocalFileRoot:
            raise ValueError('Invalid original Local Store file root')
        with root._lock:
            return cls(path, max_records=max_records, max_record_bytes=max_record_bytes,
                       max_payload_bytes=max_payload_bytes,
                       max_inspection_queries=max_inspection_queries,
                       _new_file=(root, original))

    @staticmethod
    def _file_generation(metadata: os.stat_result) -> tuple[int, int]:
        if (not stat.S_ISREG(metadata.st_mode) or metadata.st_mode & 0o077
                or metadata.st_uid != os.getuid()
                or not 0 <= metadata.st_dev < 2**64 or not 0 <= metadata.st_ino < 2**64):
            raise LocalStorageError('Original Local Store file generation is unavailable')
        return (metadata.st_dev, metadata.st_ino)

    def _observe_generation(self) -> tuple[int, int]:
        if self._physical_owner is not self:
            raise ValueError('Copied or foreign Local physical Store generation')
        if self._native_file_root is not None:
            root = os.fstat(self._native_file_root._open())
            if (root.st_dev, root.st_ino) != self._physical_parent:
                raise LocalStorageError('Original Native Store file root changed')
        parent = self._physical_path.parent.lstat()
        if (not stat.S_ISDIR(parent.st_mode) or parent.st_mode & 0o077
                or parent.st_uid != os.getuid()
                or (parent.st_dev, parent.st_ino) != self._physical_parent):
            raise LocalStorageError('Original Local Store directory generation changed')
        current = self._file_generation(self._physical_path.lstat())
        if self._physical_original is None or current != self._physical_original:
            raise LocalStorageError('Original Local Store file generation changed')
        return current

    def observe_generation(self) -> tuple[int, int]:
        """Recheck this Store's original physical device/inode without SQL or writes.

        This is a path-generation observation under the trusted Host's existing
        exclusive root ownership, not an adoption, transaction or authority
        witness. The Host also retains original configuration bytes, intent and
        settings and supplies the actual same-transaction adoption row to Core.
        An active transaction is not certified by observing this generation.
        Failure retains this connection for original-owner cleanup/observation;
        a replacement pathname never initializes or repairs the original Store.
        """
        with self._lock:
            if self._physical_owner is not self:
                raise ValueError('Copied or foreign Local physical Store generation')
            if self._closed or not self._ready:
                raise LocalStorageError('Local physical storage is closed')
            return self._observe_generation()

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
            return not self._physical.has_records_or_capacity()

    def _open(self) -> None:
        if self._closed or not self._ready:
            raise LocalStorageError('Local physical storage is closed')
        if self._native_file_root is not None:
            self._observe_generation()
        if self._physical.in_transaction:
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
            return self._read_bytes_locked(key)

    def _read_bytes_locked(self, key: str, *, max_bytes: int | None = None) -> StoredBytes | None:
        # CASE bounds the Python allocation even for a corrupted/foreign
        # oversized row. SQLite length(BLOB) reads its size, not its value.
        row = self._physical.read_row(key, self._max_record_bytes if max_bytes is None else
                                      min(self._max_record_bytes, max_bytes))
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
            return self._read_capacity_locked(namespace, key)

    def _read_capacity_locked(self, namespace: str, key: str) -> CapacityReservation | None:
        row = self._physical.read_capacity(namespace, key)
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
        row = self._physical.capacity_usage(namespace)
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
        return self._reserve_capacity(namespace, key, reserved_bytes, reserved_objects, max_bytes, max_objects)

    def reserve_capacity_inspected(
            self, namespace: str, key: str, reserved_bytes: int,
            reserved_objects: int, max_bytes: int, max_objects: int,
            fences: tuple[ByteFence, ...], *, inspect: _InventoryInspection,
            current: Callable[[], object]) -> bool:
        """Use the existing reservation formula in the original current write TX.

        Metadata and the original payload record are fenced before/after the
        current Core inspection. The physical result is not Reserved or an ACK.
        Any attempted COMMIT failure remains this Store's Unknown, without retry.
        """
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid original Local capacity inspection')
        self._validate_metadata_fences(fences, ())
        return self._reserve_capacity(namespace, key, reserved_bytes, reserved_objects,
            max_bytes, max_objects, fences=fences, inspect=inspect, current=current)

    def _reserve_capacity(self, namespace: str, key: str, reserved_bytes: int,
                          reserved_objects: int, max_bytes: int, max_objects: int, *,
                          fences: tuple[ByteFence, ...] = (),
                          inspect: _InventoryInspection | None = None,
                          current: Callable[[], object] | None = None) -> bool:
        self._capacity_name(namespace)
        self._capacity_name(key)
        for amount in (reserved_bytes, reserved_objects, max_bytes, max_objects):
            self._capacity_amount(amount)
        if reserved_bytes > max_bytes or reserved_objects > max_objects:
            raise LocalStorageError('Local physical capacity exceeded')
        with self._lock:
            self._open()
            database = self._physical
            database.begin_immediate()
            commit_attempted = False
            try:
                self._fenced_current(current)
                if fences and not self._fences_match_locked(fences):
                    raise LocalStorageError('Original Local capacity fences changed')
                if inspect is not None:
                    self._inspect_namespace_locked(inspect, fences, current)
                try:
                    changed = database.reserve_capacity_in_transaction(
                        namespace, key, reserved_bytes, reserved_objects,
                        max_bytes, max_objects, self._max_records)
                except _PhysicalCapacityCollision as collision:
                    raise LocalStorageError('Local physical capacity reservation collision') from collision
                except _PhysicalCapacityExceeded as exceeded:
                    raise LocalStorageError('Local physical capacity exceeded') from exceeded
                self._fenced_current(current)
                if fences and not self._fences_match_locked(fences):
                    raise LocalStorageError('Original Local capacity fences changed')
                commit_attempted = True
                database.commit()
                self._fenced_current(current)
                return changed
            except BaseException as failure:
                try:
                    if database.in_transaction:
                        database.rollback()
                except BaseException as cleanup:
                    if current is not None and commit_attempted:
                        raise LocalStorageCommitUnknown(self) from cleanup
                    raise
                if current is not None and commit_attempted:
                    raise LocalStorageCommitUnknown(self) from failure
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
            database = self._physical
            database.begin_immediate()
            try:
                try:
                    changed = database.release_capacity_in_transaction(
                        namespace, key, reserved_bytes, reserved_objects)
                except _PhysicalCapacityCollision as collision:
                    raise LocalStorageError('Local physical capacity reservation collision') from collision
                database.commit()
                return changed
            except BaseException:
                if database.in_transaction:
                    database.rollback()
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

    def compare_exchange_reserved_inspected(
            self, write: ByteWrite, capacity: CapacityReservation,
            fences: tuple[ByteFence, ...], *, inspect: _InventoryInspection,
            current: Callable[[], object]) -> int | None:
        """Forward one original transition under exact capacity/current fences."""
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid original Local reserved CAS inspection')
        self._validate_fences(fences, (write,))
        result = self._compare_exchange_many((write,), capacity=capacity,
            fences=fences, inspect=inspect, current=current)
        return None if result is None else result[0]

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

    def compare_exchange_attached_inspected(
            self, write: ByteWrite, original: ByteFence,
            capacity: CapacityReservation, fences: tuple[ByteFence, ...], *,
            inspect: _InventoryInspection, current: Callable[[], object]) -> int | None:
        """CAS original allocation metadata under payload/capacity/current fences."""
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid original Local attached CAS inspection')
        self._validate_fences(fences, (write,))
        originals = ((original, capacity),)
        self._validate_originals(originals, {write.key})
        result = self._compare_exchange_many((write,), capacity=None,
            originals=originals, fences=fences, inspect=inspect, current=current)
        return None if result is None else result[0]

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

    def compare_exchange_many_fenced(
            self, writes: tuple[ByteWrite, ...], fences: tuple[ByteFence, ...], *,
            current: Callable[[], object]) -> tuple[int, ...] | None:
        """Persist original Core bytes under exact physical metadata fences.

        The installed Host holds Core before Store, reserves retained bytes and
        SQLite workspace, and checks its original typed current port. No caller
        permission boolean, phase, scope comparison or Run decision is created
        here. Fences bind the original epoch/configuration/count observations in
        the same write transaction. A count row may also be a CAS target; its
        old bytes and generation must match before replacement. No write or
        lookup is repeated automatically after a conflict or lost COMMIT reply.
        """
        if not callable(current):
            raise ValueError('Invalid Local physical current callback')
        self._validate_fences(fences, writes)
        return self._compare_exchange_many(writes, capacity=None,
                                           fences=fences, current=current)

    def read_exchange_many_fenced(
            self, writes: tuple[ByteWrite, ...], fences: tuple[ByteFence, ...], *,
            current: Callable[[], object]) -> tuple[StoredBytes, ...] | None:
        """Observe exact successors and untouched metadata in one snapshot.

        Overlapping count fences are checked against this original write's
        exact successor bytes/generation. Read-only epoch/configuration fences
        remain unchanged. This is a physical observation, never accepted Run
        state, confirmed nonexecution or permission to replay the transaction.
        The current typed port is checked before reads and before returning;
        query and transaction-cleanup failures remain exceptions with custody.
        """
        if not callable(current):
            raise ValueError('Invalid Local physical current callback')
        self._validate_fences(fences, writes)
        return self._read_exchange_many(writes, fences=fences, current=current)

    def compare_exchange_many_inspected(
            self, writes: tuple[ByteWrite, ...], fences: tuple[ByteFence, ...], *,
            inspect: _InventoryInspection,
            current: Callable[[], object]) -> tuple[int, ...] | None:
        """Forward original namespace rows to Core before CAS in one transaction.

        Installed Host assembly holds Core before Store and reserves retained
        inputs and SQLite workspace. Core supplies original namespaces/cursors,
        consumes raw rows or the observed physical end, and validates every
        required inventory/custody relationship. Count syntax, a partial scan,
        or returning None from this callback is not an admission proof. Python
        does not choose scope, completeness, accepted state or retry permission.

        scan_after and exact read share the same borrowed transaction and copy
        budget. An exact miss does not select a neighboring row or end a scan.
        One row is copied at a time under the existing count and cumulative
        byte bounds. The original epoch/configuration/count fences and typed
        current port stay checked in the same BEGIN IMMEDIATE transaction.
        Query, consumer and cleanup failures prevent exposure of a success;
        attempted-COMMIT uncertainty retains the same Store without replay.
        """
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid Local inventory inspection callback')
        self._validate_fences(fences, writes)
        return self._compare_exchange_many(writes, capacity=None, fences=fences,
                                           current=current, inspect=inspect)

    def read_exchange_many_inspected(
            self, writes: tuple[ByteWrite, ...], fences: tuple[ByteFence, ...], *,
            inspect: _InventoryInspection,
            current: Callable[[], object]) -> tuple[StoredBytes, ...] | None:
        """Observe original successors and inventories without repeating writes.

        Exact successor rows and unchanged metadata are inspected in this same
        read snapshot. The existing Core Owners must readmit the actual saved
        rows and their relationships, not the earlier candidate bytes. No
        accepted Run, nonexecution or resend permission is inferred here.
        """
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid Local inventory inspection callback')
        self._validate_fences(fences, writes)
        return self._read_exchange_many(writes, fences=fences, current=current,
                                        inspect=inspect)

    def read_exchange_many_attached(
            self, writes: tuple[ByteWrite, ...],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...]) -> tuple[StoredBytes, ...] | None:
        """Observe this exact batch's successors under one physical read snapshot.

        The original payload bytes/generations and reservations are checked in
        that same transaction. Missing, changed or later metadata is unmatched,
        never proof of absence or permission to replay the batch. Returned bytes
        remain physical observations for the existing Core/authorization Owners.
        A transaction cleanup failure keeps this Store handle pending and exposes
        no partial observation. The Host reserves input/output retention itself.
        """
        self._validate_originals(originals, self._exchange_write_keys(writes))
        return self._read_exchange_many(writes, originals=originals)

    def _read_exchange_many(
            self, writes: tuple[ByteWrite, ...], *,
            originals: tuple[tuple[ByteFence, CapacityReservation], ...] = (),
            fences: tuple[ByteFence, ...] = (),
            current: Callable[[], object] | None = None,
            inspect: _InventoryInspection | None = None) -> tuple[StoredBytes, ...] | None:
        keys = self._exchange_write_keys(writes)
        if originals:
            self._validate_originals(originals, keys)
        if fences:
            self._validate_fences(fences, writes)
        with self._lock:
            self._open()
            database = self._physical
            database.begin_read()
            try:
                self._fenced_current(current)
                result: tuple[StoredBytes, ...] | None = None
                if (self._originals_match_locked(originals)
                        and self._fences_match_locked(fences, writes)):
                    observed: list[StoredBytes] = []
                    for write in writes:
                        row = self._read_bytes_locked(write.key)
                        successor = 0 if write.expected_generation is None else write.expected_generation + 1
                        if row is None or row.generation != successor or row.payload != write.payload:
                            break
                        observed.append(row)
                    if len(observed) == len(writes):
                        result = tuple(observed)
                if result is not None and inspect is not None:
                    self._inspect_namespace_locked(inspect, fences, current,
                                                   successors=writes)
                self._fenced_current(current)
                if fences and not self._fences_match_locked(fences, writes):
                    result = None
            except BaseException:
                database.cleanup_read()
                raise
            else:
                # Do not publish observations or repeat cleanup if this fails.
                database.finish_read()
                return result

    def inspect_namespaces(self, fences: tuple[ByteFence, ...], *,
                           inspect: _InventoryInspection,
                           current: Callable[[], object]) -> None:
        """Supply original namespace queries in a fenced read-only transaction.

        Core chooses namespaces, keys and cursors and decides completeness and
        meaning. The existing reader enforces thread/lifetime, raw-byte bounds,
        failure latching and original physical fences. This path performs no
        write, adoption, COMMIT, repair, Run acceptance or retry.
        """
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid Local namespace inspection callback')
        self._validate_metadata_fences(fences, ())
        with self._lock:
            self._open()
            database = self._physical
            database.begin_read()
            try:
                self._fenced_current(current)
                if not self._fences_match_locked(fences, ()):
                    raise LocalStorageError('Original Local namespace fences changed')
                self._inspect_namespace_locked(inspect, fences, current)
                self._fenced_current(current)
                if not self._fences_match_locked(fences, ()):
                    raise LocalStorageError('Original Local namespace fences changed')
            except BaseException:
                database.cleanup_read()
                raise
            else:
                # A failed physical stop keeps this same connection pending.
                # No observation escapes and no cleanup is automatically repeated.
                database.finish_read()

    def inspect_capacity_inspected(
            self, namespace: str, key: str, fences: tuple[ByteFence, ...], *,
            inspect: Callable[[_NamespaceReader, Callable[[], None]], object],
            consume: Callable[[CapacityReservation | None], object],
            current: Callable[[], object]) -> None:
        """Supply actual reservation fields in the same original current snapshot.

        Missing/query failure is not physical reservation success, permission
        to re-reserve, or a Core payload transition. No amount is synthesized.
        """
        self._capacity_name(namespace)
        self._capacity_name(key)
        if not callable(inspect) or not callable(consume):
            raise ValueError('Invalid original Local capacity observation')
        def observe(reader: _NamespaceReader) -> None:
            attempts = 0
            complete = False
            failure: BaseException | None = None
            def take() -> None:
                nonlocal attempts, complete, failure
                try:
                    attempts += 1
                    if attempts != 1:
                        raise ValueError('Repeated original Local capacity consumption')
                    reader.current()
                    actual = self._read_capacity_locked(namespace, key)
                    if consume(actual) is not None:
                        raise ValueError('Invalid original Local capacity consumer result')
                    del actual
                    reader.current()
                    complete = True
                except BaseException as error:
                    failure = error
                    raise
            result = inspect(reader, take)
            if failure is not None:
                raise failure
            if result is not None or not complete:
                raise ValueError('Incomplete original Local capacity observation')
        self.inspect_namespaces(fences, inspect=observe, current=current)

    def inspect_bounded_record_inspected(
            self, key: str, max_bytes: int, fences: tuple[ByteFence, ...], *,
            inspect: Callable[[_NamespaceReader, Callable[[], None]], object],
            consume: Callable[[StoredBytes | None], object],
            current: Callable[[], object]) -> None:
        """Borrow one bounded physical row in the original current read snapshot.

        The key comes from the held original payload request. A missing row is
        merely an observation; only Core can confirm it or choose a next action.
        SQL bounds the copy before allocation, independently of the Store-wide
        record limit. The same namespace/current/fence and cleanup rules apply.
        This method performs no CAS, reservation, retry, publication or ACK.
        """
        self._key(key)
        if (type(max_bytes) is not int or not 0 < max_bytes <= self._max_record_bytes
                or not callable(inspect) or not callable(consume)):
            raise ValueError('Invalid original Local bounded record inspection')

        def observe(reader: _NamespaceReader) -> None:
            attempts = 0
            complete = False
            failure: BaseException | None = None

            def take() -> None:
                nonlocal attempts, complete, failure
                try:
                    attempts += 1
                    if attempts != 1:
                        raise ValueError('Repeated original Local record consumption')
                    reader.current()
                    actual = self._read_bytes_locked(key, max_bytes=max_bytes)
                    if consume(actual) is not None:
                        raise ValueError('Invalid original Local record consumer result')
                    del actual
                    reader.current()
                    complete = True
                except BaseException as error:
                    failure = error
                    raise

            result = inspect(reader, take)
            if failure is not None:
                raise failure
            if result is not None or not complete:
                raise ValueError('Incomplete original Local record inspection')

        self.inspect_namespaces(fences, inspect=observe, current=current)

    def _inspect_namespace_locked(
            self, inspect: _InventoryInspection, fences: tuple[ByteFence, ...],
            current: Callable[[], object] | None, *,
            successors: tuple[ByteWrite, ...] = ()) -> None:
        # This callback borrows the enclosing physical transaction. It cannot
        # commit, acknowledge Core adoption, repair metadata or survive cleanup.
        active = True
        reading = False
        thread = get_ident()
        reads = copied = 0
        failure: BaseException | None = None

        database = self._physical
        original_snapshot = (database._snapshot_identity()
                             if type(database) is _SQLiteByteDatabase else None)
        last_fenced_snapshot: tuple[object, int, int, tuple[int, int]] | None = None

        def metadata_fence(*, reuse_snapshot: bool) -> None:
            nonlocal last_fenced_snapshot
            if self._physical is not database:
                raise LocalStorageError('Original Local physical reader changed')
            # Only the exact stdlib adapter supplies SQLite's own mutation
            # counter. Other existing physical suppliers keep full SQL checks.
            snapshot = (database._snapshot_identity()
                        if type(database) is _SQLiteByteDatabase else None)
            if snapshot is not None and (original_snapshot is None
                    or snapshot[0] is not original_snapshot[0] or snapshot[1] != original_snapshot[1]
                    or snapshot[3] != original_snapshot[3]):
                raise LocalStorageError('Original Local transaction or schema snapshot was replaced')
            if not reuse_snapshot or snapshot is None or snapshot != last_fenced_snapshot:
                if not self._fences_match_locked(fences, successors):
                    raise LocalStorageError('Original Local inventory metadata changed')
                if (snapshot is not None and type(database) is _SQLiteByteDatabase
                        and database._snapshot_identity() != snapshot):
                    raise LocalStorageError('Original Local snapshot changed during metadata read')
                last_fenced_snapshot = snapshot

        def fence(required_current: Callable[[], object] | None = None, *,
                  reuse_snapshot: bool = False) -> None:
            metadata_fence(reuse_snapshot=reuse_snapshot)
            self._fenced_current(current)
            if required_current is not None and required_current is not current:
                self._fenced_current(required_current)
            metadata_fence(reuse_snapshot=reuse_snapshot)

        def check_frame(view: _NamespaceReader) -> None:
            nonlocal failure
            try:
                if (view is not reader or not active or reading
                        or get_ident() != thread or failure is not None):
                    raise ValueError('Local inventory reader is not active')
            except BaseException as error:
                failure = error
                raise

        def current_snapshot() -> None:
            nonlocal failure
            try:
                check_frame(reader)
                fence(reuse_snapshot=True)
            except BaseException as error:
                failure = error
                raise

        def check_fences(view: _NamespaceReader, required: tuple[ByteFence, ...]) -> None:
            nonlocal failure
            try:
                if view is not reader or type(required) is not tuple:
                    raise ValueError('Copied or foreign Local inventory snapshot')
                current_snapshot()
                if required:
                    self._validate_metadata_fences(required, ())
                if (any(value not in fences for value in required)
                        or any(write.key == value.key for write in successors for value in required)):
                    raise LocalStorageError('Original Local snapshot is missing required physical fences')
            except BaseException as error:
                failure = error
                raise

        def check_fences_and_current(
                view: _NamespaceReader, required: tuple[ByteFence, ...],
                required_current: Callable[[], object]) -> None:
            nonlocal failure
            try:
                # Each call completes both SQL fences and the original current
                # observation now. Only that exact observer is already covered.
                check_fences(view, required)
                if required_current is not current:
                    if required_current() is not None:
                        raise ValueError('Invalid Local physical current callback result')
            except BaseException as error:
                failure = error
                raise

        def observe(namespace: str, after: str, consume: _NamespaceConsumer | None, *,
                    scan: bool, required_current: Callable[[], object] | None = None
                    ) -> tuple[str, StoredBytes] | None:
            nonlocal reading, reads, copied, failure
            entered = False
            try:
                if (not active or reading or get_ident() != thread
                        or failure is not None):
                    raise ValueError('Local inventory reader is not active')
                self._capacity_name(namespace)
                if (type(after) is not str or not callable(consume)
                        and (consume is not None or required_current is None)):
                    raise ValueError('Invalid Local inventory cursor or consumer')
                # Use the same injective namespace/key encoding as physical
                # writes. Empty cursor means start, not an empty logical key.
                prefix = f'namespace:{len(namespace.encode("utf-8"))}:{namespace}:'
                lower = (self.namespaced_key(namespace, after)
                         if after or not scan else prefix)
                upper = prefix[:-1] + ';'
                if reads >= self._max_inspection_queries:
                    raise LocalStorageError('Local inventory inspection capacity exceeded')
                reading = entered = True
                fence(required_current, reuse_snapshot=required_current is not None)
                # A malformed empty logical key must be observed and refused,
                # not silently excluded from the original namespace inventory.
                row = self._physical.scan_range(lower, upper,
                    min(self._max_record_bytes, self._max_payload_bytes - copied),
                    inclusive=not after, exact=not scan)
                reads += 1
                observation: tuple[str, StoredBytes] | None = None
                if row is not None:
                    key, generation, payload, kind, length = row
                    if (type(key) is not str or not key.startswith(prefix)
                            or type(generation) is not int or generation < 0
                            or type(payload) is not bytes or kind != 'blob'
                            or type(length) is not int or length != len(payload)):
                        raise LocalStorageError('Invalid retained Local inventory row')
                    logical = key[len(prefix):]
                    self._key(logical)
                    copied += len(payload)
                    observation = (logical, StoredBytes(generation, payload))
                fence(required_current, reuse_snapshot=required_current is not None)
                if consume is None:
                    # No caller callback runs between the SQL read and return.
                    # The returned row is bounded immutable DATA, not current
                    # permission or a snapshot usable for a later operation.
                    return observation
                # The Host completes transfer into its reserved Core input and
                # returns the same input/output loan before requesting a row.
                if consume(observation) is not None:
                    raise ValueError('Invalid Local inventory consumer result')
                del observation, row
                fence(required_current, reuse_snapshot=required_current is not None)
                return None
            except BaseException as error:
                failure = error
                raise
            finally:
                if entered:
                    reading = False

        def query_current(view: _NamespaceReader, mode: int, namespace: str,
                          key: str, required_current: Callable[[], object]
                          ) -> tuple[str, StoredBytes] | None:
            nonlocal failure
            try:
                check_frame(view)
                if type(mode) is not int or mode not in (0, 1) or not callable(required_current):
                    raise ValueError('Invalid original Local current query')
                # One physical query, fenced before IO and before returning its
                # DATA. The arbitrary-consumer path retains all three fences.
                # Distinct current callbacks are still observed independently.
                return observe(namespace, key, None, scan=mode == 0,
                               required_current=required_current)
            except BaseException as error:
                failure = error
                raise

        def journal_schema(view: _NamespaceReader, required_current: Callable[[], object]) -> int:
            nonlocal failure, reading, reads
            entered = False
            try:
                check_frame(view)
                if not callable(required_current):
                    raise ValueError('Invalid original Journal schema current')
                if reads >= self._max_inspection_queries:
                    raise LocalStorageError('Local inventory inspection capacity exceeded')
                reading = entered = True
                fence(required_current, reuse_snapshot=True)
                value = database._journal_schema() if type(database) is _SQLiteByteDatabase else 0
                reads += 1
                fence(required_current, reuse_snapshot=True)
                if failure is not None:
                    raise failure
                if type(value) is not int or value not in (0, 1):
                    raise ValueError('Invalid original Journal physical schema observation')
                return value
            except BaseException as error:
                if failure is None:
                    failure = error
                raise failure
            finally:
                if entered:
                    reading = False

        def scan_after(namespace: str, after: str, consume: _NamespaceConsumer) -> None:
            observe(namespace, after, consume, scan=True)

        def read(namespace: str, key: str, consume: _NamespaceConsumer) -> None:
            observe(namespace, key, consume, scan=False)

        try:
            fence()
            reader = _NamespaceReader(
                scan_after=scan_after, read=read,
                owner=self, current=current_snapshot, check_fences=check_fences,
                check_fences_and_current=check_fences_and_current,
                check_frame=check_frame, query_current=query_current,
                journal_schema=journal_schema)
            result = inspect(reader)
            if failure is not None:
                raise failure
            if result is not None or reads == 0:
                raise ValueError('Incomplete Local physical inventory inspection')
            fence()
        finally:
            active = False

    def inspect_publication_projected_attached(
            self, inspect: Callable[[Callable[[str, Callable[[StoredBytes | None], object]], None]], object],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...], *,
            current: Callable[[], object]) -> None:
        self._inspect_publication_projected(inspect, originals, current=current)

    def inspect_publication_projected_inspected(
            self, inspect: Callable[[Callable[[str, Callable[[StoredBytes | None], object]], None]], object],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...],
            fences: tuple[ByteFence, ...], *,
            namespace: Callable[[_NamespaceReader, Callable[[], None]], object],
            current: Callable[[], object],
            before_lookup: Callable[[], object]) -> None:
        """Borrow typed current and raw Core-issued keys in the same read TX.

        The namespace supplier wraps the entire original index/request/attempt
        inspection, not a prior read or cached permission. Physical current and
        metadata/epoch fences are checked outside that borrowed Core frame as
        well. Query failure never becomes absence or a durable publication ACK.
        """
        if not callable(namespace) or not callable(current):
            raise ValueError('Invalid Local publication current namespace supplier')
        self._validate_metadata_fences(fences, ())
        self._inspect_publication_projected(
            inspect, originals, current=before_lookup, namespace=namespace,
            fences=fences, physical_current=current)

    def _inspect_publication_projected(
            self, inspect: Callable[[Callable[[str, Callable[[StoredBytes | None], object]], None]], object],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...], *,
            current: Callable[[], object],
            namespace: Callable[[_NamespaceReader, Callable[[], None]], object] | None = None,
            fences: tuple[ByteFence, ...] = (),
            physical_current: Callable[[], object] | None = None) -> None:
        """Transport bounded original-key reads under one physical snapshot.

        The trusted Host holds Core, then File, before this Store lock. It
        supplies each key from the original Core scope or stored-contract
        projection, and forwards the raw row synchronously to that Owner. No
        candidate-byte equality, scope parsing, content comparison or commit
        decision happens here. A missing row is only a physical observation;
        query/fence/cleanup failures raise instead of becoming NotFound.

        current must recheck the original six facts and independent publisher
        port, returning None only on success. It runs before lookup, before
        consumption and before returning from the snapshot. The callback is not
        an authorization supplier. Original fences/capacity are checked in this
        same snapshot; no replacement or replay follows a failure.

        Each consumer finishes the same output/input loan's required transfer
        and cleanup before returning None. It must not retain the borrowed row
        outside its reserved Core input. Failure retains that original loan in
        its caller. SQLite/Python workspace, original fences and simultaneously
        retained Core inputs are separately accounted by the Host. This method
        neither releases those resources nor acknowledges a publication.

        The selected inspection-work limit bounds queries, including repeats;
        the existing store byte limit bounds cumulative copies independently.
        Only one physical row is copied at a time.
        A captured reader cannot be used later, concurrently or recursively.
        """
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid Local publication inspection callback')
        self._validate_originals(originals, set())
        with self._lock:
            self._open()
            database = self._physical
            database.begin_read()
            active = True
            reading = False
            thread = get_ident()
            reads = copied = 0
            failure: BaseException | None = None

            def fence() -> None:
                if not self._originals_match_locked(originals):
                    raise LocalStorageError('Original Local publication observation changed')
                if current() is not None:
                    raise ValueError('Invalid Local publication current callback result')
                if not self._originals_match_locked(originals):
                    raise LocalStorageError('Original Local publication observation changed')

            def read(key: str, consume: Callable[[StoredBytes | None], object]) -> None:
                nonlocal reading, reads, copied, failure
                entered = False
                try:
                    if (not active or reading or get_ident() != thread
                            or failure is not None):
                        raise ValueError('Local publication snapshot reader is not active')
                    self._key(key)
                    if not callable(consume):
                        raise ValueError('Invalid Local publication observation consumer')
                    if reads >= self._max_inspection_queries:
                        raise LocalStorageError('Local publication inspection capacity exceeded')
                    reading = entered = True
                    fence()
                    # Bound the cumulative copy before SQLite fetches a BLOB.
                    row = self._read_bytes_locked(
                        key, max_bytes=self._max_payload_bytes - copied)
                    reads += 1
                    if row is not None:
                        copied += len(row.payload)
                    fence()
                    if consume(row) is not None:
                        raise ValueError('Invalid Local publication observation consumer result')
                    del row
                    fence()
                except BaseException as error:
                    failure = error
                    raise
                finally:
                    if entered:
                        reading = False

            try:
                consumed = complete = False
                consumption_failure: BaseException | None = None

                def consume_all() -> None:
                    nonlocal consumed, complete, consumption_failure
                    try:
                        if consumed:
                            raise ValueError('Original Local inspection was already consumed')
                        consumed = True
                        fence()
                        result = inspect(read)
                        # A caught query/consumer/permission failure stays failed.
                        if failure is not None:
                            raise failure
                        if result is not None or reads == 0:
                            raise ValueError('Incomplete Local publication inspection')
                        fence()
                        complete = True
                    except BaseException as error:
                        consumption_failure = error
                        raise

                if namespace is None:
                    consume_all()
                else:
                    self._inspect_namespace_locked(
                        lambda reader: namespace(reader, consume_all), fences, physical_current)
                if consumption_failure is not None:
                    raise consumption_failure
                if not complete:
                    raise ValueError('Incomplete original Local publication current inspection')
                self._fenced_current(physical_current)
                if fences and not self._fences_match_locked(fences, ()):
                    raise LocalStorageError('Original Local publication metadata changed')
            except BaseException:
                database.cleanup_read()
                raise
            else:
                # Read-only transaction end, never a Store commit or durable ACK.
                # Failure leaves this same connection pending; no automatic retry.
                database.finish_read()
            finally:
                active = False

    def compare_exchange_projected_attached(
            self, count: int,
            project: Callable[[int, Callable[[ByteWrite], None]], object],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...], *,
            before_commit: Callable[[], object]) -> tuple[int, ...] | None:
        """Consume one borrowed opaque projection at a time, in one transaction.

        The trusted Host supplies the original Core count and calls the consumer
        exactly once for each ordinal while its output loan is live. The
        consumer copies that one write into SQLite synchronously; the Host must
        finish the same loan's cleanup before project returns. Cleanup failure
        must raise, retaining the original handle/reservation outside this Store.

        The Host first obtains original full-chain validation/current authority.
        before_commit then calls the original current publisher Owner port after
        all projection cleanup, before COMMIT. It must return None only after
        that port succeeds; refusal/unknown raises. This callback is not itself
        authorization evidence. Core still owns ACK and uncertainty decisions.

        Original payload bytes/generations/capacity are fenced before production
        and again before COMMIT. Any prefix is uncommitted; conflict rolls it
        back, failure propagates without retry, and lost ACK is not replay
        permission. No metadata payload list is retained here. Per-record/store
        limits are unchanged; the Host separately accounts original fences,
        live projection bytes, key/generation descriptors and SQLite workspace.
        """
        return self._projected_attached(
            count, project, originals, before_commit=before_commit, reuse_identical=False)

    def store_publication_projected_attached(
            self, count: int,
            project: Callable[[int, Callable[[ByteWrite], None]], object],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...], *,
            before_commit: Callable[[], object]) -> tuple[int, ...] | None:
        """Insert original publication bytes, reusing only byte-identical records.

        The trusted Host supplies Core-issued immutable contract/schema addresses
        and the scoped index reference. Each original occurrence is consumed and
        cleaned up, even when an identity was already stored. Existing bytes are
        never overwritten or normalized; mismatch rolls back the entire prefix.
        No expected CAS generation is accepted on this insert-only path.

        An existing index with different bytes is a physical conflict. Core must
        inspect the actually stored index and validate its full chain separately;
        this adapter does not compare committed content or choose an index.
        Returned generations are physical observations, never a publication ACK.
        All original/current fences and cleanup rules of the projected transaction
        apply. The Host reserves the bounded equality copy and SQLite workspace.
        """
        return self._projected_attached(
            count, project, originals, before_commit=before_commit, reuse_identical=True)

    def compare_exchange_projected_inspected(
            self, count: int,
            project: Callable[[int, Callable[[ByteWrite], None]], object],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...],
            fences: tuple[ByteFence, ...], *,
            inspect: Callable[[_NamespaceReader, Callable[[], None]], object],
            current: Callable[[], object],
            before_commit: Callable[[], object]) -> tuple[int, ...] | None:
        """Apply Core's original CAS under this same write/current snapshot.

        This reuses the existing projected transaction and generation checks.
        Core selects each key/body/expected revision; the physical return is
        neither grant usage, delivery completion nor COMMIT acknowledgement.
        """
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid Local projected CAS inspection')
        self._validate_metadata_fences(fences, ())
        return self._projected_attached(
            count, project, originals, before_commit=before_commit,
            reuse_identical=False, fences=fences, inspect=inspect, current=current)

    def store_publication_projected_inspected(
            self, count: int,
            project: Callable[[int, Callable[[ByteWrite], None]], object],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...],
            fences: tuple[ByteFence, ...], *,
            inspect: Callable[[_NamespaceReader, Callable[[], None]], object],
            current: Callable[[], object],
            before_commit: Callable[[], object]) -> tuple[int, ...] | None:
        """Borrow this same write transaction for the existing current Owner.

        The trusted Host enters its original Core/File locks first and wraps
        consume() with its existing typed-current namespace supplier. Core
        projections and the independent publisher callback then use that exact
        SQLite snapshot, not a prior grant/Bool. No inspection or projection can
        acknowledge COMMIT. An attempted COMMIT failure keeps the same Store
        Unknown and is never retried here.
        """
        if not callable(inspect) or not callable(current):
            raise ValueError('Invalid Local projected current inspection')
        self._validate_metadata_fences(fences, ())
        return self._projected_attached(
            count, project, originals, before_commit=before_commit,
            reuse_identical=True, fences=fences, inspect=inspect, current=current)

    def _projected_attached(
            self, count: int,
            project: Callable[[int, Callable[[ByteWrite], None]], object],
            originals: tuple[tuple[ByteFence, CapacityReservation], ...], *,
            before_commit: Callable[[], object], reuse_identical: bool,
            fences: tuple[ByteFence, ...] = (),
            inspect: Callable[[_NamespaceReader, Callable[[], None]], object] | None = None,
            current: Callable[[], object] | None = None) -> tuple[int, ...] | None:
        if (type(count) is not int or not 1 <= count <= self._max_records
                or not callable(project) or not callable(before_commit)):
            raise ValueError('Invalid Local physical projection batch')
        self._validate_originals(originals, set())
        original_keys = {fence.key for fence, _ in originals} | {fence.key for fence in fences}
        with self._lock:
            self._open()
            database = self._physical
            database.begin_immediate()
            commit_attempted = False
            try:
                self._fenced_current(current)
                if fences and not self._fences_match_locked(fences, ()):
                    raise LocalStorageError('Original Local publication metadata changed')
                if not self._originals_match_locked(originals):
                    database.rollback()
                    return None
                record_count, payload_bytes = database.record_usage()
                generations: list[int] = []
                keys: set[str] = set()
                thread = get_ident()

                def consume_ordinal(ordinal: int) -> None:
                    nonlocal record_count, payload_bytes
                    active = True
                    delivered = False
                    failure: BaseException | None = None

                    def consume(write: ByteWrite) -> None:
                        nonlocal delivered, failure, record_count, payload_bytes
                        try:
                            if not active or get_ident() != thread or delivered:
                                raise ValueError('Local physical projection consumer is not active')
                            self._exchange_write_keys((write,))
                            if (write.key in original_keys
                                    or (not reuse_identical and write.key in keys)):
                                raise ValueError('Duplicate or original Local physical projection key')
                            if reuse_identical and write.expected_generation is not None:
                                raise ValueError('Publication physical projection is insert-only')
                            existing = database.read_header(write.key)
                            if reuse_identical and existing is not None:
                                # Bound the stored equality copy before fetching bytes.
                                # This does not validate any Core identity or chain.
                                if existing[1] > self._max_record_bytes:
                                    raise LocalStorageError('Local physical payload capacity exceeded')
                                if existing[1] != len(write.payload):
                                    raise _ProjectedWriteConflict()
                                stored = self._read_bytes_locked(write.key)
                                if stored is None or stored.payload != write.payload:
                                    raise _ProjectedWriteConflict()
                                del stored
                                keys.add(write.key)
                                generations.append(existing[0])
                                delivered = True
                                return
                            if ((existing is None) != (write.expected_generation is None)
                                    or (existing is not None
                                        and existing[0] != write.expected_generation)):
                                raise _ProjectedWriteConflict()
                            generation = 0 if existing is None else existing[0] + 1
                            next_count = record_count + (1 if existing is None else 0)
                            next_bytes = payload_bytes - (0 if existing is None else existing[1]) + len(write.payload)
                            if next_count > self._max_records or next_bytes > self._max_payload_bytes:
                                raise LocalStorageError('Local physical payload capacity exceeded')
                            actual = database.write_record(write.key, write.expected_generation, write.payload)
                            if actual != generation:
                                raise LocalStorageError('Original Local physical CAS generation changed')
                            keys.add(write.key)
                            generations.append(generation)
                            record_count, payload_bytes = next_count, next_bytes
                            delivered = True
                        except BaseException as error:
                            failure = error
                            raise

                    try:
                        result = project(ordinal, consume)
                    finally:
                        active = False
                    # A producer cannot swallow a consumer refusal, duplicate
                    # delivery or failed physical write and promote it to success.
                    if failure is not None:
                        raise failure
                    if result is not None or not delivered:
                        raise ValueError('Incomplete Local physical projection')

                consumed = complete = False
                consumption_failure: BaseException | None = None

                def consume_all() -> None:
                    nonlocal consumed, complete, consumption_failure
                    try:
                        if consumed:
                            raise ValueError('Original Local projection was already consumed')
                        consumed = True
                        for ordinal in range(count):
                            consume_ordinal(ordinal)
                        if before_commit() is not None:
                            raise ValueError('Invalid Local physical precommit callback result')
                        complete = True
                    except BaseException as error:
                        consumption_failure = error
                        raise

                if inspect is None:
                    consume_all()
                else:
                    self._inspect_namespace_locked(
                        lambda reader: inspect(reader, consume_all), fences, current)
                if consumption_failure is not None:
                    raise consumption_failure
                if not complete:
                    raise ValueError('Incomplete original Local projected inspection')
                self._fenced_current(current)
                if fences and not self._fences_match_locked(fences, ()):
                    raise LocalStorageError('Original Local publication metadata changed')
                if not self._originals_match_locked(originals):
                    database.rollback()
                    return None
                commit_attempted = True
                database.commit()
                self._fenced_current(current)
                if fences and not self._fences_match_locked(fences, ()):
                    raise LocalStorageError('Original Local publication metadata changed')
                return tuple(generations)
            except _ProjectedWriteConflict as original:
                try:
                    if database.in_transaction:
                        database.rollback()
                except BaseException as cleanup_failure:
                    if current is not None and commit_attempted:
                        raise LocalStorageCommitUnknown(self) from cleanup_failure
                    raise
                if current is not None and commit_attempted:
                    raise LocalStorageCommitUnknown(self) from original
                return None
            except BaseException as original:
                try:
                    if database.in_transaction:
                        database.rollback()
                except BaseException as cleanup_failure:
                    if current is not None and commit_attempted:
                        raise LocalStorageCommitUnknown(self) from cleanup_failure
                    raise
                if current is not None and commit_attempted:
                    raise LocalStorageCommitUnknown(self) from original
                raise

    def _exchange_write_keys(self, writes: tuple[ByteWrite, ...]) -> set[str]:
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
        return keys

    def _validate_originals(
            self, originals: tuple[tuple[ByteFence, CapacityReservation], ...],
            keys: set[str]) -> None:
        if type(originals) is not tuple or not 1 <= len(originals) <= self._max_records:
            raise ValueError('Invalid original Local physical metadata batch')
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

    def _originals_match_locked(
            self, originals: tuple[tuple[ByteFence, CapacityReservation], ...]) -> bool:
        database = self._physical
        for fence, reservation in originals:
            retained = database.read_capacity(reservation.namespace, reservation.key)
            if retained != (reservation.reserved_bytes, reservation.reserved_objects):
                return False
            original = self._read_bytes_locked(fence.key)
            if original != StoredBytes(fence.generation, fence.payload):
                return False
        return True

    def _validate_fences(self, fences: tuple[ByteFence, ...],
                         writes: tuple[ByteWrite, ...]) -> None:
        self._exchange_write_keys(writes)
        self._validate_metadata_fences(fences, writes)

    def _validate_metadata_fences(self, fences: tuple[ByteFence, ...],
                                  writes: tuple[ByteWrite, ...]) -> None:
        if type(fences) is not tuple or not 1 <= len(fences) <= self._max_records:
            raise ValueError('Invalid Local physical metadata fences')
        keys: set[str] = set()
        copied = 0
        for fence in fences:
            if type(fence) is not ByteFence:
                raise ValueError('Invalid Local physical metadata fence')
            self._key(fence.key)
            if (type(fence.generation) is not int
                    or not 0 <= fence.generation <= 2**63 - 1
                    or type(fence.payload) is not bytes
                    or len(fence.payload) > self._max_record_bytes
                    or fence.key in keys):
                raise ValueError('Invalid Local physical metadata fence')
            keys.add(fence.key)
            copied += len(fence.payload)
            if copied > self._max_payload_bytes:
                raise ValueError('Local physical metadata fences exceed their bound')
            for write in writes:
                if write.key == fence.key and write.expected_generation != fence.generation:
                    raise ValueError('Local physical write has another metadata generation')

    def _fences_match_locked(self, fences: tuple[ByteFence, ...],
                             successors: tuple[ByteWrite, ...] = ()) -> bool:
        for fence in fences:
            generation, payload = fence.generation, fence.payload
            for write in successors:
                if write.key == fence.key:
                    generation = fence.generation + 1
                    payload = write.payload
                    break
            original = self._read_bytes_locked(fence.key)
            if original != StoredBytes(generation, payload):
                return False
        return True

    @staticmethod
    def _fenced_current(current: Callable[[], object] | None) -> None:
        if current is not None and current() is not None:
            raise ValueError('Invalid Local physical current callback result')

    def _compare_exchange_many(self, writes: tuple[ByteWrite, ...], *,
                               capacity: CapacityReservation | None,
                               originals: tuple[tuple[ByteFence, CapacityReservation], ...] = (),
                               fences: tuple[ByteFence, ...] = (),
                               current: Callable[[], object] | None = None,
                               inspect: _InventoryInspection | None = None) -> tuple[int, ...] | None:
        keys = self._exchange_write_keys(writes)
        if capacity is not None:
            if type(capacity) is not CapacityReservation:
                raise ValueError('Invalid Local physical capacity observation')
            self._capacity_name(capacity.namespace)
            self._capacity_name(capacity.key)
            self._capacity_amount(capacity.reserved_bytes)
            self._capacity_amount(capacity.reserved_objects)
            if capacity.key not in keys or originals:
                raise ValueError('Local physical reservation names another record')
        if originals:
            self._validate_originals(originals, keys)
        if fences:
            self._validate_fences(fences, writes)
        with self._lock:
            self._open()
            database = self._physical
            database.begin_immediate()
            commit_attempted = False
            try:
                self._fenced_current(current)
                if capacity is not None:
                    retained = database.read_capacity(capacity.namespace, capacity.key)
                    if retained != (capacity.reserved_bytes, capacity.reserved_objects):
                        database.rollback()
                        return None
                if (not self._originals_match_locked(originals)
                        or not self._fences_match_locked(fences)):
                    database.rollback()
                    return None
                if inspect is not None:
                    self._inspect_namespace_locked(inspect, fences, current)
                generations: list[int] = []
                inserted = replaced = 0
                for write in writes:
                    existing = database.read_header(write.key)
                    if (existing is None) != (write.expected_generation is None) or (
                            existing is not None and existing[0] != write.expected_generation):
                        database.rollback()
                        return None
                    if existing is None:
                        inserted += 1
                        generations.append(0)
                    else:
                        replaced += existing[1]
                        generations.append(existing[0] + 1)
                count, total = database.record_usage()
                if (count + inserted > self._max_records or
                        total - replaced + sum(len(write.payload) for write in writes)
                        > self._max_payload_bytes):
                    raise LocalStorageError('Local physical payload capacity exceeded')
                for write, generation in zip(writes, generations):
                    actual = database.write_record(write.key, write.expected_generation, write.payload)
                    if actual != generation:
                        raise LocalStorageError('Original Local physical CAS generation changed')
                self._fenced_current(current)
                if fences and not self._fences_match_locked(fences, writes):
                    database.rollback()
                    return None
                commit_attempted = True
                database.commit()
                self._fenced_current(current)
                return tuple(generations)
            except BaseException as failure:
                # COMMIT failure is not a successful write or permission to
                # resend. Preserve the exception and the original store handle.
                try:
                    if database.in_transaction:
                        database.rollback()
                except BaseException as cleanup_failure:
                    if current is not None and commit_attempted:
                        raise LocalStorageCommitUnknown(self) from cleanup_failure
                    raise
                if current is not None and commit_attempted:
                    raise LocalStorageCommitUnknown(self) from failure
                raise

    def close(self) -> None:
        with self._lock:
            if not self._closed:
                self._close_descriptor()
                if hasattr(self, '_physical'):
                    self._physical.close()
                elif hasattr(self, '_connection'):
                    # Legacy acquisition may fail before the typed wrapper was
                    # constructed; keep cleanup on that same connection.
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
