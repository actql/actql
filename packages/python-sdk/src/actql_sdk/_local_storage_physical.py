"""Mechanical operations on the existing LocalByteStore's one physical DB.

No SQL-string execution interface is offered to another backend. The existing
Store retains its original identity, transaction, fences, capacity decisions,
callback loans and failure custody. These observations issue none of those.
"""
from __future__ import annotations

import sqlite3
from collections.abc import Generator
from typing import Protocol, cast


class _PhysicalCapacityCollision(RuntimeError):
    """A different exact reservation is present; no row was removed/reissued."""


class _PhysicalCapacityExceeded(RuntimeError):
    """The selected physical Store limits refuse this reservation."""


class _PhysicalByteDatabase(Protocol):
    @property
    def in_transaction(self) -> bool: ...
    def begin_read(self) -> None: ...
    def finish_read(self) -> None: ...
    def cleanup_read(self) -> None: ...
    def begin_immediate(self) -> None: ...
    def commit(self) -> None: ...
    def rollback(self) -> None: ...
    def close(self) -> None: ...
    def has_records_or_capacity(self) -> bool: ...
    def read_row(self, key: str, max_bytes: int) -> tuple[object, object, object, object] | None: ...
    def read_header(self, key: str) -> tuple[int, int] | None: ...
    def scan_range(self, lower: str, upper: str, max_bytes: int, *, inclusive: bool,
                   exact: bool) -> tuple[object, object, object, object, object] | None: ...
    def read_capacity(self, namespace: str, key: str) -> tuple[int, int] | None: ...
    def capacity_usage(self, namespace: str) -> tuple[int, int]: ...
    def reservation_count(self) -> int: ...
    def record_usage(self) -> tuple[int, int]: ...
    def reserve_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int, max_bytes: int, max_objects: int,
                                        max_reservations: int) -> bool: ...
    def release_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int) -> bool: ...
    def write_record(self, key: str, expected_generation: int | None, payload: bytes) -> int: ...


class _SQLiteByteDatabase:
    """The existing legacy schema2/stdlib connection, unchanged SQL semantics.

    Only LocalByteStore owns the connection and closes it. No second connection,
    implicit transaction completion, schema conversion or fallback is created.
    """
    __slots__ = ('_connection', '_transaction_sequence')

    def __init__(self, connection: sqlite3.Connection) -> None:
        self._connection = connection
        self._transaction_sequence = 0

    def _snapshot_identity(self) -> tuple[sqlite3.Connection, int, int, int]:
        """Same live transaction plus SQLite's actual mutation counter, DATA only."""
        if not self._connection.in_transaction:
            raise ValueError('Original SQLite snapshot is not active')
        # DDL does not advance total_changes. Read the actual bounded schema
        # counter too; a row-mutation counter alone cannot fence that boundary.
        schema = self._connection.execute('PRAGMA schema_version').fetchone()
        if type(schema) is not tuple or len(schema) != 1 or type(schema[0]) is not int:
            raise ValueError('Original SQLite schema snapshot is unavailable')
        return self._connection, self._transaction_sequence, self._connection.total_changes, schema[0]

    @property
    def in_transaction(self) -> bool:
        return self._connection.in_transaction

    def begin_read(self) -> None:
        self._transaction_sequence += 1
        self._connection.execute('BEGIN')

    def finish_read(self) -> None:
        # The original read must stop before any complete observation escapes.
        # This never acknowledges a previous write or issues another BEGIN.
        self._transaction_sequence += 1
        self._connection.execute('ROLLBACK')

    def cleanup_read(self) -> None:
        if self._connection.in_transaction:
            self._transaction_sequence += 1
            self._connection.execute('ROLLBACK')

    def begin_immediate(self) -> None:
        self._transaction_sequence += 1
        self._connection.execute('BEGIN IMMEDIATE')

    def commit(self) -> None:
        self._transaction_sequence += 1
        self._connection.execute('COMMIT')

    def rollback(self) -> None:
        self._transaction_sequence += 1
        self._connection.execute('ROLLBACK')

    def close(self) -> None:
        self._transaction_sequence += 1
        self._connection.close()

    def has_records_or_capacity(self) -> bool:
        return bool(self._connection.execute("""SELECT
            EXISTS(SELECT 1 FROM core_bytes) OR
            EXISTS(SELECT 1 FROM actql_capacity)""").fetchone()[0])

    def read_row(self, key: str, max_bytes: int) -> tuple[object, object, object, object] | None:
        # The same CASE bounds allocation before the row reaches Python.
        raw = self._connection.execute('''SELECT generation,
            CASE WHEN length(payload) <= ? THEN payload ELSE NULL END,
            typeof(payload), length(payload)
            FROM core_bytes WHERE key = ?''', (max_bytes, key)).fetchone()
        return cast(tuple[object, object, object, object] | None, raw)

    def read_fence_rows(self, keys: tuple[str, ...], max_bytes: int
                        ) -> Generator[tuple[object, object, object, object, object, object], None, None]:
        """Fresh complete observations, one bounded row at a time in this TX.

        The key values plus SQL text fit the existing 4096-byte key-input
        envelope. A full-length individual key keeps the original scalar read.
        There is no payload sort, fetchall, retained row table or second DB.
        """
        if not self._connection.in_transaction:
            raise ValueError('Original SQLite fence transaction is unavailable')
        prefix = 'WITH requested(position,key) AS (VALUES '
        suffix = ''') SELECT requested.position, actual.key IS NOT NULL,
            actual.generation,
            CASE WHEN length(actual.payload) <= ? THEN actual.payload ELSE NULL END,
            typeof(actual.payload), length(actual.payload)
            FROM requested LEFT JOIN core_bytes AS actual ON actual.key = requested.key'''

        def read_group(start: int, group: list[str]
                       ) -> Generator[tuple[object, object, object, object, object, object], None, None]:
            values = ','.join('(' + str(start + index) + ',?)' for index in range(len(group)))
            query = prefix + values + suffix
            if len(query.encode()) + sum(len(key.encode()) for key in group) > 4096:
                raise ValueError('Original SQLite key-input envelope exceeded')
            cursor = self._connection.execute(query, (*group, max_bytes))
            try:
                for row in cursor:
                    yield cast(tuple[object, object, object, object, object, object], row)
            finally:
                cursor.close()

        pending: list[str] = []
        start = 0
        key_bytes = 0
        values_bytes = 0
        framing_bytes = len((prefix + suffix).encode())
        for index, key in enumerate(keys):
            # Include actual SQL framing and ordinal text, not an object-size
            # estimate or a new capacity allowance. No key is normalized.
            item_bytes = len(('(' + str(index) + ',?)').encode())
            size = framing_bytes + values_bytes + (1 if pending else 0) + item_bytes + key_bytes + len(key.encode())
            if pending and size > 4096:
                yield from read_group(start, pending)
                pending = []
                start = index
                key_bytes = 0
                values_bytes = 0
                size = framing_bytes + item_bytes + len(key.encode())
            if size > 4096:
                row = self.read_row(key, max_bytes)
                yield (index, 0, None, None, 'null', None) if row is None else (index, 1, *row)
                start = index + 1
                continue
            values_bytes += (1 if pending else 0) + item_bytes
            pending.append(key)
            key_bytes += len(key.encode())
        if pending:
            yield from read_group(start, pending)

    def read_header(self, key: str) -> tuple[int, int] | None:
        return cast(tuple[int, int] | None, self._connection.execute(
            'SELECT generation, length(payload) FROM core_bytes WHERE key = ?',
            (key,)).fetchone())

    def scan_range(self, lower: str, upper: str, max_bytes: int, *, inclusive: bool,
                   exact: bool) -> tuple[object, object, object, object, object] | None:
        relation = '=' if exact else '>=' if inclusive else '>'
        raw = self._connection.execute(f'''SELECT
            CASE WHEN length(CAST(key AS BLOB)) <= 4096 THEN key ELSE NULL END,
            generation,
            CASE WHEN length(payload) <= ? THEN payload ELSE NULL END,
            typeof(payload), length(payload)
            FROM core_bytes WHERE key {relation} ? AND key < ?
            ORDER BY key COLLATE BINARY LIMIT 1''', (max_bytes, lower, upper)).fetchone()
        return cast(tuple[object, object, object, object, object] | None, raw)

    def read_capacity(self, namespace: str, key: str) -> tuple[int, int] | None:
        return cast(tuple[int, int] | None, self._connection.execute(
            '''SELECT reserved_bytes, reserved_objects
            FROM actql_capacity WHERE namespace = ? AND reservation_key = ?''',
            (namespace, key)).fetchone())

    def capacity_usage(self, namespace: str) -> tuple[int, int]:
        return cast(tuple[int, int], self._connection.execute(
            '''SELECT coalesce(sum(reserved_bytes), 0),
            coalesce(sum(reserved_objects), 0) FROM actql_capacity WHERE namespace = ?''',
            (namespace,)).fetchone())

    def reservation_count(self) -> int:
        return cast(int, self._connection.execute('SELECT count(*) FROM actql_capacity').fetchone()[0])

    def record_usage(self) -> tuple[int, int]:
        return cast(tuple[int, int], self._connection.execute(
            'SELECT count(*), coalesce(sum(length(payload)), 0) FROM core_bytes').fetchone())

    def reserve_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int, max_bytes: int, max_objects: int,
                                        max_reservations: int) -> bool:
        existing = self.read_capacity(namespace, key)
        if existing is not None:
            if existing != (reserved_bytes, reserved_objects):
                raise _PhysicalCapacityCollision()
            return False
        used_bytes, used_objects = self.capacity_usage(namespace)
        if (self.reservation_count() >= max_reservations or used_bytes > max_bytes
                or used_objects > max_objects or reserved_bytes > max_bytes - used_bytes
                or reserved_objects > max_objects - used_objects):
            raise _PhysicalCapacityExceeded()
        self._connection.execute('INSERT INTO actql_capacity VALUES (?, ?, ?, ?)',
                                 (namespace, key, reserved_bytes, reserved_objects))
        return True

    def release_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int) -> bool:
        existing = self.read_capacity(namespace, key)
        if existing is None:
            return False
        if existing != (reserved_bytes, reserved_objects):
            raise _PhysicalCapacityCollision()
        self._connection.execute("""DELETE FROM actql_capacity
            WHERE namespace = ? AND reservation_key = ?""", (namespace, key))
        return True

    def write_record(self, key: str, expected_generation: int | None, payload: bytes) -> int:
        generation = 0 if expected_generation is None else expected_generation + 1
        if expected_generation is None:
            self._connection.execute('INSERT INTO core_bytes VALUES (?, ?, ?)',
                                     (key, generation, payload))
        else:
            self._connection.execute('UPDATE core_bytes SET generation = ?, payload = ? WHERE key = ?',
                                     (generation, payload, key))
        return generation
