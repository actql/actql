"""Closed physical byte operations on one original Native SQLite Database.

This is not Run admission or a second transaction Owner. Native's existing
schema3, bounded key contract and original read child remain authoritative.
There is no stdlib/system SQLite fallback, schema migration or SQL-string port.
The installed Host still has to supply this original Database and its funding.
"""
from __future__ import annotations

from collections.abc import Callable
from typing import TypeVar

from ._local_native_sqlite_database import _OriginalDatabaseCustody, _OriginalDatabaseError
from ._local_native_sqlite_lookup import _OriginalLookupCustody, _OriginalLookupError
from ._local_storage import LocalStorageError
from ._local_storage_physical import (
    _PhysicalByteDatabase, _PhysicalCapacityCollision, _PhysicalCapacityExceeded)

_T = TypeVar('_T')
# A private physical table namespace, never a publication/Account authority.
# Keep the full existing physical key unchanged within it: no digest mapping,
# Unicode normalization, prefix stripping or legacy-schema reinterpretation.
_BYTES = 'actql-sdk-local-opaque-bytes'


def _missing(call: Callable[[], _T]) -> _T | None:
    try:
        return call()
    except (_OriginalDatabaseError, _OriginalLookupError) as error:
        if (not error.unknown and error.fact is not None
                and error.fact.issue_family == 15 and error.fact.after_issue_family == 0):
            return None
        raise


class _NativeByteDatabase:
    """Mechanical projection for LocalByteStore's existing physical port.

    The Database itself retains pending read custody before FFI. This adapter
    holds no independent active/committed flags or replacement cleanup handles.
    Complete reads use the Core child's finish; failed inspections use its
    cleanup only. Neither path acknowledges the original uncertain COMMIT.
    """
    __slots__ = ('_original',)

    def __init__(self, original: _OriginalDatabaseCustody) -> None:
        if type(original) is not _OriginalDatabaseCustody:
            raise ValueError('Original Native byte Database is required')
        original._local(allow_unconfirmed=True)
        self._original = original

    def __copy__(self) -> _NativeByteDatabase:
        raise TypeError('Original Native byte Database cannot be copied')

    def __deepcopy__(self, memo: dict[int, object]) -> _NativeByteDatabase:
        raise TypeError('Original Native byte Database cannot be copied')

    def _reader(self) -> _OriginalDatabaseCustody | _OriginalLookupCustody:
        # Only the same Database's already registered original can be selected.
        # Presence is transport custody, not a successful start/current fact.
        return self._original._lookup_original or self._original

    @property
    def in_transaction(self) -> bool:
        if self._original._lookup_original is not None:
            raise LocalStorageError('Original Native read cleanup is pending')
        fact = (self._original.lookup_unconfirmed_transaction_state()
                if self._original._write_unknown is not None
                else self._original.transaction_state())
        if fact.transaction_active is None:
            raise LocalStorageError('Original Native transaction observation is unavailable')
        return fact.transaction_active

    def begin_read(self) -> None:
        if self._original._lookup_original is not None:
            raise LocalStorageError('Original Native read cleanup is pending')
        if self._original._write_unknown is not None:
            # Unknown chooses reconciliation, never permission: the same Core
            # Owner still requires fenced + physical NoActive before lending.
            self._original.lookup_unconfirmed_snapshot()
        else:
            self._original.begin_read()

    def finish_read(self) -> None:
        read = self._original._lookup_original
        if read is not None:
            read.finish()
        else:
            self._original.transaction(9)

    def cleanup_read(self) -> None:
        read = self._original._lookup_original
        if read is not None:
            read.close()
        elif self._original._write_unknown is not None:
            # No blind rollback of an uncertain original operation.
            raise self._original._write_unknown
        elif self.in_transaction:
            self._original.transaction(9)

    def begin_immediate(self) -> None:
        self._original.transaction(7)

    def commit(self) -> None:
        self._original.transaction(8)

    def rollback(self) -> None:
        # The ordinary write selector cannot operate through a read child.
        self._original.transaction(9)

    def close(self) -> None:
        self._original.close()

    def has_records_or_capacity(self) -> bool:
        fact = self._reader().database_usage()
        if fact.record_count is None or fact.reservation_count is None:
            raise LocalStorageError('Original Native usage observation is unavailable')
        return bool(fact.record_count or fact.reservation_count)

    def read_row(self, key: str, max_bytes: int) -> tuple[object, object, object, object] | None:
        if type(max_bytes) is not int or not 0 <= max_bytes <= self._original._bound:
            raise ValueError('Original Native byte read bound is invalid')
        if max_bytes == 0:
            # Do not allocate one unreserved byte to discover an empty row.
            # The same TX's typed header validates the exact zero-length BLOB.
            header = self.read_header(key)
            if header is None:
                return None
            revision, header_size = header
            if header_size != 0:
                raise LocalStorageError('Original Native row exceeds the read bound')
            return revision, b'', 'blob', 0
        output = bytearray(max_bytes)
        result = _missing(lambda: self._reader().read_into(_BYTES, key, output))
        if result is None:
            return None
        fact, size = result
        if fact.revision is None or size is None:
            raise LocalStorageError('Original Native row observation is unavailable')
        return fact.revision, bytes(output[:size]), 'blob', size

    def read_header(self, key: str) -> tuple[int, int] | None:
        fact = _missing(lambda: self._reader().read_header(_BYTES, key))
        if fact is None:
            return None
        if not fact.has_header or fact.revision is None or fact.header_body_bytes is None:
            raise LocalStorageError('Original Native row header is unavailable')
        return fact.revision, fact.header_body_bytes

    def scan_range(self, lower: str, upper: str, max_bytes: int, *, inclusive: bool,
                   exact: bool) -> tuple[object, object, object, object, object] | None:
        if (type(lower) is not str or type(upper) is not str or not upper
                or type(exact) is not bool or type(inclusive) is not bool
                or type(max_bytes) is not int or not 0 <= max_bytes <= self._original._bound):
            raise ValueError('Original Native scan bounds are invalid')
        # Inspect the exact inclusive prefix first. A malformed empty logical
        # key at that address must not be skipped by Native's strict > cursor.
        if exact or inclusive:
            row = self.read_row(lower, max_bytes)
            if row is not None:
                return (lower, *row) if lower < upper else None
            if exact:
                return None
        key, body = bytearray(512), bytearray(max_bytes)
        result = _missing(lambda: self._reader().scan_after_into(_BYTES, lower, key, body))
        if result is None:
            return None
        fact, key_size, body_size = result
        actual = bytes(key[:key_size]).decode('utf-8', errors='strict')
        if fact.revision is None or not actual or actual <= lower:
            raise LocalStorageError('Original Native scan ordering is unavailable')
        if actual >= upper:
            return None
        return actual, fact.revision, bytes(body[:body_size]), 'blob', body_size

    def read_capacity(self, namespace: str, key: str) -> tuple[int, int] | None:
        fact = _missing(lambda: self._reader().read_capacity(namespace, key))
        if fact is None:
            return None
        if fact.reserved_bytes is None or fact.reserved_objects is None:
            raise LocalStorageError('Original Native reservation is unavailable')
        return fact.reserved_bytes, fact.reserved_objects

    def capacity_usage(self, namespace: str) -> tuple[int, int]:
        fact = self._reader().capacity_usage(namespace)
        if fact.reserved_bytes is None or fact.reserved_objects is None:
            raise LocalStorageError('Original Native reservation usage is unavailable')
        return fact.reserved_bytes, fact.reserved_objects

    def reservation_count(self) -> int:
        count = self._reader().database_usage().reservation_count
        if count is None:
            raise LocalStorageError('Original Native reservation count is unavailable')
        return count

    def record_usage(self) -> tuple[int, int]:
        fact = self._reader().database_usage()
        if fact.record_count is None or fact.record_body_bytes is None:
            raise LocalStorageError('Original Native record usage is unavailable')
        return fact.record_count, fact.record_body_bytes

    def reserve_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int, max_bytes: int, max_objects: int,
                                        max_reservations: int) -> bool:
        try:
            fact = self._original.reserve_bounded_capacity(namespace, key, reserved_bytes,
                reserved_objects, max_bytes, max_objects, max_reservations)
        except _OriginalDatabaseError as error:
            if not error.unknown and error.fact is not None and not error.fact.after_issue_family:
                if error.fact.issue_family == 16:
                    raise _PhysicalCapacityCollision() from error
                if error.fact.issue_family == 19:
                    raise _PhysicalCapacityExceeded() from error
            raise
        if fact.capacity_changed is None:
            raise LocalStorageError('Original Native reservation change is unavailable')
        return fact.capacity_changed

    def release_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int) -> bool:
        try:
            fact = self._original.release_capacity_in_transaction(namespace, key, reserved_bytes,
                                                                  reserved_objects)
        except _OriginalDatabaseError as error:
            if (not error.unknown and error.fact is not None and error.fact.issue_family == 16
                    and not error.fact.after_issue_family):
                raise _PhysicalCapacityCollision() from error
            raise
        if fact.capacity_changed is None:
            raise LocalStorageError('Original Native reservation release is unavailable')
        return fact.capacity_changed

    def write_record(self, key: str, expected_generation: int | None, payload: bytes) -> int:
        fact = (self._original.insert(_BYTES, key, payload) if expected_generation is None
                else self._original.compare_exchange(_BYTES, key, expected_generation, payload))
        if fact.revision is None:
            raise LocalStorageError('Original Native write revision is unavailable')
        return fact.revision


def _project_original_byte_database(original: _OriginalDatabaseCustody) -> _PhysicalByteDatabase:
    """Existing Host-supplied custody only; no acquisition or public factory."""
    return _NativeByteDatabase(original)
