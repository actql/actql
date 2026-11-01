"""Mechanical operations on the existing LocalByteStore's one physical DB.

No SQL-string execution interface is offered to another backend. The existing
Store retains its original identity, transaction, fences, capacity decisions,
callback loans and failure custody. These observations issue none of those.
"""
from __future__ import annotations

import sqlite3
from typing import Protocol, cast


# Same existing Native Run-Definition uniqueness domain, adapted only to this
# physical table/key representation. NULL is not typed Run admission.
_RUN_DEFINITION_INDEX = (
    "CREATE UNIQUE INDEX actql_client_run_definition_unique ON core_bytes("
    "json_extract(json_extract(CAST(payload AS TEXT),'$.run_definition'),"
    "'$.run_definition_cid')) WHERE key>='namespace:11:client_runs:' "
    "AND key<'namespace:11:client_runs;'")


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
    """The same stdlib connection for legacy2 and owned indexed Journal3.

    Only LocalByteStore owns the connection and closes it. No second connection,
    implicit transaction completion, schema conversion or fallback is created.
    """
    __slots__ = ('_connection', '_transaction_sequence')

    def __init__(self, connection: sqlite3.Connection) -> None:
        self._connection = connection
        self._transaction_sequence = 0

    def _snapshot_identity(self) -> tuple[sqlite3.Connection, int, int, tuple[int, int]]:
        """Same live transaction plus SQLite's actual mutation counter, DATA only."""
        connection = self._connection
        sequence = self._transaction_sequence
        if not connection.in_transaction:
            raise ValueError('Original SQLite snapshot is not active')
        # DDL does not advance total_changes. Read the actual bounded schema
        # counters too. TEMP can shadow core_bytes without changing main's
        # counter or any row. Both schemas belong to this SAME connection.
        schema = connection.execute('PRAGMA schema_version').fetchone()
        temporary = connection.execute('PRAGMA temp.schema_version').fetchone()
        if type(schema) is not tuple or len(schema) != 1 or type(schema[0]) is not int:
            raise ValueError('Original SQLite schema snapshot is unavailable')
        if type(temporary) is not tuple or len(temporary) != 1 or type(temporary[0]) is not int:
            raise ValueError('Original SQLite TEMP schema snapshot is unavailable')
        if (self._connection is not connection or self._transaction_sequence != sequence
                or not connection.in_transaction):
            raise ValueError('Original SQLite snapshot changed during observation')
        return connection, sequence, connection.total_changes, (schema[0], temporary[0])

    def _journal_schema(self) -> int:
        """Observe the actual same-TX physical format; no authority is returned.

        The closed index distinguishes legacy absence from metadata lost after
        format3 initialization. No open, schema repair, migration or cache runs.
        """
        before = self._snapshot_identity()
        version = self._connection.execute('PRAGMA main.user_version').fetchone()
        row = self._connection.execute("""SELECT type,
            CASE WHEN length(tbl_name) <= 10 THEN tbl_name ELSE NULL END,
            CASE WHEN length(sql) <= ? THEN sql ELSE NULL END
            FROM main.sqlite_schema
            WHERE name='actql_client_run_definition_unique' COLLATE NOCASE""",
            (len(_RUN_DEFINITION_INDEX),)).fetchone()
        shadow = self._connection.execute("""SELECT 1 FROM temp.sqlite_schema
            WHERE name='core_bytes' COLLATE NOCASE LIMIT 1""").fetchone()
        if self._snapshot_identity() != before or shadow is not None:
            raise ValueError('Original Journal physical schema changed or was shadowed')
        if version == (2,) and row is None:
            return 0
        if version == (3,) and row == ('index', 'core_bytes', _RUN_DEFINITION_INDEX):
            return 1
        raise ValueError('Original Journal physical format is missing or inconsistent')

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
