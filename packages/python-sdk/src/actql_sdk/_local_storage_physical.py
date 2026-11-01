"""Mechanical operations on the existing LocalByteStore's one physical DB.

No SQL-string execution interface is offered to another backend. The existing
Store retains its original identity, transaction, fences, capacity decisions,
callback loans and failure custody. These observations issue none of those.
"""
from __future__ import annotations

import sqlite3
from typing import Protocol, cast


_APPLICATION_ID = 0x41514C42
_SCHEMA = '''CREATE TABLE core_bytes (
    key TEXT PRIMARY KEY COLLATE BINARY NOT NULL,
    generation INTEGER NOT NULL CHECK(generation >= 0),
    payload BLOB NOT NULL CHECK(typeof(payload) = 'blob')
) STRICT, WITHOUT ROWID'''
# Match the existing Native SQLite physical reservation fields. Core supplies
# the namespace, material key and amounts; this table carries no Run state.
_CAPACITY_SCHEMA = '''CREATE TABLE actql_capacity(namespace TEXT NOT NULL,reservation_key TEXT NOT NULL,reserved_bytes INTEGER NOT NULL CHECK(reserved_bytes >= 0),reserved_objects INTEGER NOT NULL CHECK(reserved_objects >= 0),PRIMARY KEY(namespace, reservation_key)) STRICT'''


# Same existing Native Run-Definition uniqueness domain, adapted only to this
# physical table/key representation. NULL is not typed Run admission.
_RUN_DEFINITION_INDEX = (
    "CREATE UNIQUE INDEX actql_client_run_definition_unique ON core_bytes("
    "json_extract(json_extract(CAST(payload AS TEXT),'$.run_definition'),"
    "'$.run_definition_cid')) WHERE key>='namespace:11:client_runs:' "
    "AND key<'namespace:11:client_runs;'")


_RUN_DEFINITION_PROBE = (
    "SELECT json_extract(json_extract('{\"run_definition\":\"{\\\"run_definition_cid\\\":\\\"probe\\\"}\"}',"
    "'$.run_definition'),'$.run_definition_cid')"
)

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
        application = self._connection.execute('PRAGMA main.application_id').fetchone()
        version = self._connection.execute('PRAGMA main.user_version').fetchone()
        # At most four bounded catalog rows distinguish the complete two/three
        # object formats from any extra/colliding schema without a payload scan.
        rows = self._connection.execute("""SELECT
            CASE WHEN length(name) <= 34 THEN name ELSE NULL END,
            type, CASE WHEN length(tbl_name) <= 16 THEN tbl_name ELSE NULL END,
            CASE WHEN length(sql) <= ? THEN sql ELSE NULL END
            FROM main.sqlite_schema WHERE name NOT LIKE 'sqlite_%'
            ORDER BY name LIMIT 4""",
            (max(len(_SCHEMA), len(_CAPACITY_SCHEMA), len(_RUN_DEFINITION_INDEX)),)).fetchall()
        shadow = self._connection.execute("""SELECT 1 FROM temp.sqlite_schema
            WHERE name COLLATE NOCASE IN ('core_bytes', 'actql_capacity') LIMIT 1""").fetchone()
        if self._snapshot_identity() != before or shadow is not None:
            raise ValueError('Original Journal physical schema changed or was shadowed')
        expected = [('actql_capacity', 'table', 'actql_capacity', _CAPACITY_SCHEMA),
                    ('core_bytes', 'table', 'core_bytes', _SCHEMA)]
        if application != (_APPLICATION_ID,):
            raise ValueError('Original Journal physical application identity changed')
        if version == (2,) and rows == expected:
            return 0
        expected.insert(1, ('actql_client_run_definition_unique', 'index',
                            'core_bytes', _RUN_DEFINITION_INDEX))
        if version == (3,) and rows == expected:
            probe = self._connection.execute(_RUN_DEFINITION_PROBE).fetchone()
            if probe != ('probe',) or self._snapshot_identity() != before:
                raise ValueError('Original Journal index expression changed during observation')
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

    def _match_rows(self, rows: tuple[tuple[str, int, bytes], ...]) -> bool:
        """Compare bounded original bytes in this transaction; no grant or write."""
        if type(rows) is not tuple or not 1 <= len(rows) <= 32:
            raise ValueError('Invalid original physical fence set')
        used = 0
        keys: set[str] = set()
        for row in rows:
            if (type(row) is not tuple or len(row) != 3
                    or type(row[0]) is not str or not row[0]
                    or type(row[1]) is not int or not 0 <= row[1] < 2**63
                    or type(row[2]) is not bytes):
                raise ValueError('Invalid original physical fence')
            key, generation, payload = row
            encoded = key.encode('utf-8')
            if len(encoded) > 4096 or key in keys:
                raise ValueError('Invalid original physical fence key')
            keys.add(key)
            used += len(encoded) + len(payload) + 8
            if used > 8192:
                raise ValueError('Original physical fence set exceeds its query holding')
        before = self._snapshot_identity()
        # Only the bounded row count selects SQL structure. Every actual key,
        # revision and exact byte body is a bound value, never SQL text.
        slots = ','.join('(?,?,?)' for _ in rows)
        parameters = tuple(value for row in rows for value in row)
        actual = self._connection.execute(
            'WITH expected(key,generation,payload) AS (VALUES ' + slots + ''')
            SELECT count(*) FROM core_bytes AS actual
            JOIN expected ON actual.key = expected.key COLLATE BINARY
            WHERE typeof(actual.key) = 'text'
            AND typeof(actual.generation) = 'integer'
            AND actual.generation = expected.generation
            AND CASE WHEN typeof(actual.payload) = 'blob'
                AND length(actual.payload) = length(expected.payload)
                THEN actual.payload ELSE NULL END = expected.payload''',
            parameters).fetchone()
        if self._snapshot_identity() != before:
            raise ValueError('Original physical fence snapshot changed')
        if (type(actual) is not tuple or len(actual) != 1
                or type(actual[0]) is not int or not 0 <= actual[0] <= len(rows)):
            raise ValueError('Original physical fence comparison is unavailable')
        return actual[0] == len(rows)

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
