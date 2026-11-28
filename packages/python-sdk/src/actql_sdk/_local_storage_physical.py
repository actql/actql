"""Mechanical operations on the existing LocalByteStore's one physical DB.

No SQL-string execution interface is offered to another backend. The existing
Store retains its original identity, transaction, fences, capacity decisions,
callback loans and failure custody. These observations issue none of those.
"""
from __future__ import annotations

import sqlite3
from collections.abc import Callable
from typing import Any, Protocol, cast


_SQLITE_STATEMENT_CACHE = 64
_TARGET_READ_KEYS = 8
_TARGET_READ_KEY_BYTES = 8192

_SCAN_RECORD_SQL = {
    relation: f"""SELECT
        CASE WHEN length(CAST(key AS BLOB)) <= 4096 THEN key ELSE NULL END,
        generation, CASE WHEN length(payload) <= ? THEN payload ELSE NULL END,
        typeof(payload), length(payload)
        FROM main.core_bytes WHERE key {relation} ? AND key < ?
        ORDER BY key COLLATE BINARY LIMIT 1"""
    for relation in ('=', '>=', '>')
}
_SCAN_NAME_SQL = {
    relation: f"""SELECT
        CASE WHEN length(CAST(key AS BLOB)) <= 4096 THEN key ELSE NULL END,
        generation, typeof(payload), length(payload)
        FROM main.core_bytes WHERE key {relation} ? AND key < ?
        ORDER BY key COLLATE BINARY LIMIT 1"""
    for relation in ('>=', '>')
}
_TARGET_HEADERS_SQL = tuple(
    """SELECT requested.ordinal, stored.key IS NOT NULL,
       CASE WHEN typeof(stored.generation) = 'integer' THEN stored.generation END,
       typeof(stored.payload),
       CASE WHEN typeof(stored.payload) = 'blob' THEN length(stored.payload) END
       FROM (WITH requested(ordinal, key) AS (VALUES """
    + ', '.join(f'({ordinal}, ?)' for ordinal in range(count))
    + """) SELECT ordinal, key FROM requested) AS requested
       LEFT JOIN main.core_bytes AS stored ON stored.key = requested.key COLLATE BINARY"""
    for count in range(1, _TARGET_READ_KEYS + 1)
)


class _TrackedSQLiteConnection(sqlite3.Connection):
    """Retain the owned SQLite transaction state without a SQL trace."""

    __slots__ = ('_transaction_epoch', '_observation_eligible', '_encoding_eligible',
                 '_closed_invocation')

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._transaction_epoch = 0
        self._closed_invocation: Any = None
        detect_types = kwargs.get('detect_types', args[2] if len(args) > 2 else 0)
        self._observation_eligible = detect_types == 0
        self._encoding_eligible = False

    @property
    def _closed_statement_epoch(self) -> int:
        return self._transaction_epoch + self.total_changes

    def _qualify_encoding(self) -> None:
        # Only the Store calls this after publishing connection cleanup
        # custody. Constructor acquisition adds no fallible SQL observation.
        self._encoding_eligible = self.execute('PRAGMA encoding').fetchone() == ('UTF-8',)

    def _closed_eligible(self) -> bool:
        return self._observation_eligible and self._encoding_eligible

    def execute(self, sql: str, parameters: Any = (), /) -> sqlite3.Cursor:
        span = self._closed_invocation
        if span is not None and not span.suspended:
            try:
                span._guard_sql()
                return super().execute(sql, parameters)
            except BaseException as error:
                span._fail(error)
                raise span.failure
        return super().execute(sql, parameters)



_APPLICATION_ID = 0x41514C42
_SCHEMA = '''CREATE TABLE core_bytes (
    key TEXT PRIMARY KEY COLLATE BINARY NOT NULL,
    generation INTEGER NOT NULL CHECK(generation >= 0),
    payload BLOB NOT NULL CHECK(typeof(payload) = 'blob')
) STRICT, WITHOUT ROWID'''
# Match the existing Native SQLite physical reservation fields. Core supplies
# the namespace, material key and amounts; this table carries no Run state.
_CAPACITY_SCHEMA = '''CREATE TABLE actql_capacity(namespace TEXT NOT NULL,reservation_key TEXT NOT NULL,reserved_bytes INTEGER NOT NULL CHECK(reserved_bytes >= 0),reserved_objects INTEGER NOT NULL CHECK(reserved_objects >= 0),PRIMARY KEY(namespace, reservation_key)) STRICT'''

# Total durable reservations always have custody. Retained record totals exist
# only when the original Store was explicitly created with a retained quota.
_STORE_USAGE_SCHEMA = '''CREATE TABLE actql_store_usage (
    singleton INTEGER PRIMARY KEY CHECK(singleton = 1),
    reservations INTEGER NOT NULL CHECK(reservations >= 0),
    records INTEGER CHECK(records >= 0),
    payload_bytes INTEGER CHECK(payload_bytes >= 0),
    CHECK((records IS NULL) = (payload_bytes IS NULL))
) STRICT'''
_CAPACITY_USAGE_SCHEMA = '''CREATE TABLE actql_capacity_usage (
    namespace TEXT PRIMARY KEY NOT NULL,
    reservations INTEGER NOT NULL CHECK(reservations > 0),
    reserved_bytes INTEGER NOT NULL CHECK(reserved_bytes >= 0),
    reserved_objects INTEGER NOT NULL CHECK(reserved_objects >= 0)
) STRICT, WITHOUT ROWID'''
_SQLITE_INTEGER_MAX = 2**63 - 1


# Same existing Native Run-Definition uniqueness domain, adapted only to this
# physical table/key representation. NULL is not typed Run admission.
_RUN_DEFINITION_EXPRESSION = (
    "json_extract(json_extract(CAST(payload AS TEXT),'$.run_definition'),'$.run_definition_cid')")
_RUN_DEFINITION_PREFIX = 'namespace:11:client_runs:'
_RUN_DEFINITION_RANGE = "key>='namespace:11:client_runs:' AND key<'namespace:11:client_runs;'"
_RUN_DEFINITION_INDEX = (
    f"CREATE UNIQUE INDEX actql_client_run_definition_unique ON core_bytes({_RUN_DEFINITION_EXPRESSION}) "
    f"WHERE {_RUN_DEFINITION_RANGE}")

_RUN_DEFINITION_READ_SQL = (
    'SELECT CASE WHEN length(CAST(key AS BLOB)) <= 4096 THEN key END, '
    'generation, CASE WHEN length(payload) <= ? THEN payload END, '
    'typeof(payload), length(payload) FROM main.core_bytes '
    'INDEXED BY actql_client_run_definition_unique '
    f'WHERE {_RUN_DEFINITION_RANGE} AND {_RUN_DEFINITION_EXPRESSION} = ?')
_RUN_DEFINITION_INPUT_SQL = f'SELECT {_RUN_DEFINITION_EXPRESSION} FROM (SELECT ? AS payload)'


_RUN_DEFINITION_PROBE = (
    "SELECT json_extract(json_extract('{\"run_definition\":\"{\\\"run_definition_cid\\\":\\\"probe\\\"}\"}',"
    "'$.run_definition'),'$.run_definition_cid')"
)

_MODEL_CALL_JOURNAL = 'client_model_call_originals'


class _PhysicalCapacityCollision(RuntimeError):
    """A different exact reservation is present; no row was removed/reissued."""


class _PhysicalCapacityExceeded(RuntimeError):
    """The selected physical Store limits refuse this reservation."""


class _PhysicalWriteNotApplied(RuntimeError):
    """The original SQLite mutation did not directly change one row."""


class _PhysicalWriteConflict(Exception):
    """The expected physical CAS generation did not match."""


class _PhysicalPrimaryKeyConflict(RuntimeError):
    """The physical INSERT primary key already exists."""


class _PhysicalRunDefinitionConflict(RuntimeError):
    """The current SQLite Run Definition unique index refused an INSERT."""

    def __init__(self, definition: str) -> None:
        super().__init__('Original Local Run Definition unique index refused the INSERT')
        self.definition = definition


def _require_write_applied(cursor: sqlite3.Cursor) -> None:
    if cursor.rowcount != 1:
        raise _PhysicalWriteNotApplied('Original Local SQLite write did not change exactly one row')


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
    def reserve_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int, max_bytes: int, max_objects: int,
                                        max_reservations: int) -> bool: ...
    def release_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int) -> bool: ...
    def write_record(self, key: str, expected_generation: int | None, payload: bytes) -> int: ...


class _SQLiteByteDatabase:
    """The original stdlib connection for the closed indexed Journal catalog.

    Only LocalByteStore owns the connection and closes it. No second connection,
    implicit transaction completion, schema conversion or fallback is created.
    """
    __slots__ = ('_connection', '_transaction_sequence', '_retained_limits', '_ordinary_catalog')

    def __init__(self, connection: sqlite3.Connection, *,
                 retained_limits: tuple[int, int] | None = None) -> None:
        self._connection = connection
        self._transaction_sequence = 0
        self._retained_limits = retained_limits
        self._ordinary_catalog = False

    def _snapshot_identity(self) -> tuple[sqlite3.Connection, int, int, tuple[int, int] | None]:
        """Same live transaction plus SQLite's actual mutation counter, DATA only."""
        connection = self._connection
        sequence = self._transaction_sequence
        epoch = (connection._transaction_epoch
                 if type(connection) is _TrackedSQLiteConnection else sequence)
        if not connection.in_transaction:
            raise ValueError('Original SQLite snapshot is not active')
        if self._ordinary_catalog:
            return connection, epoch, connection.total_changes, None
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
                or (type(connection) is _TrackedSQLiteConnection
                    and connection._transaction_epoch != epoch)
                or not connection.in_transaction):
            raise ValueError('Original SQLite snapshot changed during observation')
        return connection, epoch, connection.total_changes, (schema[0], temporary[0])

    def _require_index_expression(self) -> None:
        try:
            probe = self._connection.execute(_RUN_DEFINITION_PROBE).fetchone()
        except sqlite3.OperationalError as error:
            if (getattr(error, 'sqlite_errorcode', None) == sqlite3.SQLITE_ERROR
                    and str(error) == 'no such function: json_extract'):
                raise ValueError('Original Local Store index expression is unavailable') from error
            raise
        if probe != ('probe',):
            raise ValueError('Original Local Store index expression is inconsistent')

    def _journal_schema(self) -> None:
        """Check the exact catalog in the current physical transaction.

        The original application and exact catalog identify the indexed
        Journal. Missing and colliding entries both refuse.
        """
        before = self._snapshot_identity()
        if self._ordinary_catalog:
            return
        application = self._connection.execute('PRAGMA main.application_id').fetchone()
        # At most six bounded rows distinguish the exact five catalog
        # entries from an extra or colliding schema without a payload scan.
        rows = self._connection.execute("""SELECT
            CASE WHEN length(name) <= 34 THEN name ELSE NULL END,
            type, CASE WHEN length(tbl_name) <= 34 THEN tbl_name ELSE NULL END,
            CASE WHEN length(sql) <= ? THEN sql ELSE NULL END
            FROM main.sqlite_schema WHERE name NOT LIKE 'sqlite_%'
            ORDER BY name LIMIT 6""",
            (max(map(len, (_SCHEMA, _CAPACITY_SCHEMA, _CAPACITY_USAGE_SCHEMA,
                          _STORE_USAGE_SCHEMA, _RUN_DEFINITION_INDEX))),)).fetchall()
        shadow = self._connection.execute("""SELECT 1 FROM temp.sqlite_schema
            WHERE name COLLATE NOCASE IN ('core_bytes', 'actql_capacity', 'actql_capacity_usage', 'actql_store_usage') LIMIT 1""").fetchone()
        if self._snapshot_identity() != before or shadow is not None:
            raise ValueError('Original Journal physical schema changed or was shadowed')
        expected = [
            ('actql_capacity', 'table', 'actql_capacity', _CAPACITY_SCHEMA),
            ('actql_capacity_usage', 'table', 'actql_capacity_usage', _CAPACITY_USAGE_SCHEMA),
            ('actql_client_run_definition_unique', 'index', 'core_bytes', _RUN_DEFINITION_INDEX),
            ('actql_store_usage', 'table', 'actql_store_usage', _STORE_USAGE_SCHEMA),
            ('core_bytes', 'table', 'core_bytes', _SCHEMA),
        ]
        if application != (_APPLICATION_ID,):
            raise ValueError('Original Journal physical application identity changed')
        if rows != expected:
            raise ValueError('Original Journal physical format is missing or inconsistent')
        self._require_index_expression()
        if self._snapshot_identity() != before:
            raise ValueError('Original Journal index expression changed during observation')

    @property
    def in_transaction(self) -> bool:
        return self._connection.in_transaction

    def _control(self, sql: str) -> None:
        # Attempt identity changes before a potentially ambiguous physical reply.
        connection = self._connection
        self._transaction_sequence += 1
        if type(connection) is _TrackedSQLiteConnection:
            connection._transaction_epoch += 1
        connection.execute(sql)

    def begin_read(self) -> None:
        self._control('BEGIN')

    def finish_read(self) -> None:
        # Finish the actual borrowed reader before releasing any observation.
        self._control('ROLLBACK')

    def cleanup_read(self) -> None:
        if self._connection.in_transaction:
            self.finish_read()

    def begin_immediate(self) -> None:
        self._control('BEGIN IMMEDIATE')

    def commit(self) -> None:
        self._control('COMMIT')

    def rollback(self) -> None:
        self._control('ROLLBACK')

    def close(self) -> None:
        self._transaction_sequence += 1
        self._connection.close()

    def has_records_or_capacity(self) -> bool:
        return bool(self._connection.execute("""SELECT
            EXISTS(SELECT 1 FROM main.core_bytes) OR
            EXISTS(SELECT 1 FROM main.actql_capacity)""").fetchone()[0])

    def read_row(self, key: str, max_bytes: int) -> tuple[object, object, object, object] | None:
        # The same CASE bounds allocation before the row reaches Python.
        raw = self._connection.execute('''SELECT generation,
            CASE WHEN length(payload) <= ? THEN payload ELSE NULL END,
            typeof(payload), length(payload)
            FROM main.core_bytes WHERE key = ?''', (max_bytes, key)).fetchone()
        return cast(tuple[object, object, object, object] | None, raw)

    def read_header(self, key: str) -> tuple[int, int] | None:
        return cast(tuple[int, int] | None, self._connection.execute(
            'SELECT generation, length(payload) FROM main.core_bytes WHERE key = ?',
            (key,)).fetchone())

    def scan_range(self, lower: str, upper: str, max_bytes: int, *, inclusive: bool,
                   exact: bool) -> tuple[object, object, object, object, object] | None:
        relation = '=' if exact else '>=' if inclusive else '>'
        raw = self._connection.execute(
            _SCAN_RECORD_SQL[relation], (max_bytes, lower, upper)).fetchone()
        return cast(tuple[object, object, object, object, object] | None, raw)

    def read_run_definition_owner(
            self, definition: str, max_bytes: int) -> tuple[object, ...] | None:
        self._journal_schema()
        return cast(tuple[object, ...] | None, self._connection.execute(
            _RUN_DEFINITION_READ_SQL, (max_bytes, definition)).fetchone())

    def task_material_count_matches(self, lower: str, upper: str, expected: int) -> bool:
        """Count unique physical keys without fetching material BLOBs."""
        self._journal_schema()
        limit = expected + 1
        row = self._connection.execute(
            'SELECT count(*) FROM (SELECT key FROM main.core_bytes WHERE key >= ? AND key < ? LIMIT ?)',
            (lower, upper, limit)).fetchone()
        if type(row) is not tuple or len(row) != 1 or type(row[0]) is not int or not 0 <= row[0] <= limit:
            raise ValueError('Invalid original Local Task material count observation')
        return row[0] == expected

    def scan_name_key(self, lower: str, upper: str, *,
                      inclusive: bool) -> tuple[object, object, object, object] | None:
        relation = '>=' if inclusive else '>'
        row = self._connection.execute(_SCAN_NAME_SQL[relation], (lower, upper)).fetchone()
        return cast(tuple[object, object, object, object] | None, row)

    def read_target_headers(self, keys: tuple[str, ...]
                            ) -> list[tuple[object, object, object, object, object]]:
        # The only input relation is the small set of original primary keys.
        # Observe SQLite's BLOB extents without materializing their bodies.
        if not 0 < len(keys) <= _TARGET_READ_KEYS:
            raise ValueError('Invalid Local target read count')
        rows = self._connection.execute(_TARGET_HEADERS_SQL[len(keys) - 1], keys).fetchall()
        return cast(list[tuple[object, object, object, object, object]], rows)

    def read_capacity(self, namespace: str, key: str) -> tuple[int, int] | None:
        return cast(tuple[int, int] | None, self._connection.execute(
            '''SELECT reserved_bytes, reserved_objects
            FROM main.actql_capacity WHERE namespace = ? AND reservation_key = ?''',
            (namespace, key)).fetchone())

    def _store_usage(self) -> tuple[int, int | None, int | None]:
        row = self._connection.execute(
            'SELECT reservations, records, payload_bytes FROM main.actql_store_usage WHERE singleton = 1'
        ).fetchone()
        if (row is None or not self._counter(row[0])
                or (row[1] is None) != (row[2] is None)
                or row[1] is not None and not (self._counter(row[1]) and self._counter(row[2]))):
            raise ValueError('Original Local durable usage is missing or inconsistent')
        return cast(tuple[int, int | None, int | None], row)

    @staticmethod
    def _counter(value: object) -> bool:
        return type(value) is int and 0 <= value <= _SQLITE_INTEGER_MAX

    def require_usage_mode(self, retained: bool) -> None:
        _, records, _ = self._store_usage()
        if (records is not None) != retained:
            raise ValueError('Original Local retained quota configuration changed')

    def _namespace_usage(self, namespace: str) -> tuple[int, int, int]:
        row = self._connection.execute(
            'SELECT reservations, reserved_bytes, reserved_objects FROM main.actql_capacity_usage WHERE namespace = ?',
            (namespace,)).fetchone()
        if row is None:
            if self._connection.execute(
                    'SELECT 1 FROM main.actql_capacity WHERE namespace = ? LIMIT 1',
                    (namespace,)).fetchone() is not None:
                raise ValueError('Original Local reservation usage is missing')
            return (0, 0, 0)
        if not all(self._counter(value) for value in row) or row[0] == 0:
            raise ValueError('Original Local reservation usage is invalid')
        return cast(tuple[int, int, int], row)

    def capacity_usage(self, namespace: str) -> tuple[int, int]:
        _, used_bytes, used_objects = self._namespace_usage(namespace)
        return (used_bytes, used_objects)

    def _change_capacity_usage(self, namespace: str, usage: tuple[int, int, int],
                               delta: tuple[int, int, int], total: int) -> None:
        count, used_bytes, used_objects = usage
        records, bytes_delta, objects_delta = delta
        changed = (count + records, used_bytes + bytes_delta, used_objects + objects_delta)
        if (total < count or not all(self._counter(value) for value in changed)
                or changed[0] == 0 and changed[1:] != (0, 0) or not self._counter(total + records)):
            raise ValueError('Original Local reservation usage is inconsistent')
        if changed[0] == 0:
            cursor = self._connection.execute(
                'DELETE FROM main.actql_capacity_usage WHERE namespace = ?', (namespace,))
        elif count == 0:
            cursor = self._connection.execute(
                'INSERT INTO main.actql_capacity_usage VALUES (?, ?, ?, ?)', (namespace, *changed))
        else:
            cursor = self._connection.execute('''UPDATE main.actql_capacity_usage
                SET reservations = ?, reserved_bytes = ?, reserved_objects = ? WHERE namespace = ?''',
                (*changed, namespace))
        _require_write_applied(cursor)
        if records:
            _require_write_applied(self._connection.execute(
                'UPDATE main.actql_store_usage SET reservations = ? WHERE singleton = 1',
                (total + records,)))

    def reserve_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int, max_bytes: int, max_objects: int,
                                        max_reservations: int) -> bool:
        existing = self.read_capacity(namespace, key)
        usage = self._namespace_usage(namespace)
        count, used_bytes, used_objects = usage
        total, _, _ = self._store_usage()
        if existing is not None:
            if existing != (reserved_bytes, reserved_objects):
                raise _PhysicalCapacityCollision()
            if count == 0 or total < count or used_bytes < reserved_bytes or used_objects < reserved_objects:
                raise ValueError('Original Local reservation usage is inconsistent')
            return False
        if (total >= max_reservations or used_bytes > max_bytes
                or used_objects > max_objects or reserved_bytes > max_bytes - used_bytes
                or reserved_objects > max_objects - used_objects):
            raise _PhysicalCapacityExceeded()
        cursor = self._connection.execute(
            'INSERT INTO main.actql_capacity VALUES (?, ?, ?, ?)',
            (namespace, key, reserved_bytes, reserved_objects))
        _require_write_applied(cursor)
        self._change_capacity_usage(namespace, usage, (1, reserved_bytes, reserved_objects), total)
        return True

    def append_model_call_usage_in_transaction(
            self, scope: str, previous_objects: int, body_bytes: int, max_scope_bytes: int,
            max_reservations: int) -> bool:
        """Add one journal row's charge to the selected invocation's bucket."""
        existing = self.read_capacity(_MODEL_CALL_JOURNAL, scope)
        reserved_bytes, reserved_objects = (0, 0) if existing is None else existing
        if reserved_objects != previous_objects:
            return False
        if (reserved_bytes > max_scope_bytes or
                body_bytes > max_scope_bytes - reserved_bytes):
            raise _PhysicalCapacityExceeded()
        usage = self._namespace_usage(_MODEL_CALL_JOURNAL)
        total, _, _ = self._store_usage()
        if existing is None:
            if total >= max_reservations:
                raise _PhysicalCapacityExceeded()
            cursor = self._connection.execute(
                'INSERT INTO main.actql_capacity VALUES (?, ?, ?, ?)',
                (_MODEL_CALL_JOURNAL, scope, body_bytes, 1))
        else:
            cursor = self._connection.execute(
                '''UPDATE main.actql_capacity SET reserved_bytes = ?, reserved_objects = ?
                WHERE namespace = ? AND reservation_key = ?
                    AND reserved_bytes = ? AND reserved_objects = ?''',
                (reserved_bytes + body_bytes, reserved_objects + 1, _MODEL_CALL_JOURNAL, scope,
                 reserved_bytes, reserved_objects))
        _require_write_applied(cursor)
        self._change_capacity_usage(
            _MODEL_CALL_JOURNAL, usage, (int(existing is None), body_bytes, 1), total)
        return True

    def release_capacity_in_transaction(self, namespace: str, key: str, reserved_bytes: int,
                                        reserved_objects: int) -> bool:
        existing = self.read_capacity(namespace, key)
        if existing is None:
            return False
        if existing != (reserved_bytes, reserved_objects):
            raise _PhysicalCapacityCollision()
        usage = self._namespace_usage(namespace)
        total, _, _ = self._store_usage()
        cursor = self._connection.execute("""DELETE FROM main.actql_capacity
            WHERE namespace = ? AND reservation_key = ?
                AND reserved_bytes = ? AND reserved_objects = ?""",
            (namespace, key, reserved_bytes, reserved_objects))
        _require_write_applied(cursor)
        self._change_capacity_usage(namespace, usage, (-1, -reserved_bytes, -reserved_objects), total)
        return True

    def _write_retained_usage(self, key: str, payload_bytes: int,
                              expected_generation: int | None) -> tuple[int, int]:
        assert self._retained_limits is not None
        insert = expected_generation is None
        _, count, size = self._store_usage()
        old = None if insert else self.read_header(key)
        if not insert and (old is None or old[0] != expected_generation):
            raise _PhysicalWriteConflict()
        if count is None or size is None or (old is not None and (not count or size < old[1])):
            raise ValueError('Original Local retained usage is inconsistent')
        new_count = count + int(insert)
        new_size = size - (0 if old is None else old[1]) + payload_bytes
        if not self._counter(new_count) or not self._counter(new_size):
            raise ValueError('Original Local retained usage is inconsistent')
        max_records, max_bytes = self._retained_limits
        if new_count > max_records or new_size > max_bytes:
            raise _PhysicalCapacityExceeded()
        return new_count, new_size

    def write_record(self, key: str, expected_generation: int | None, payload: bytes) -> int:
        insert = expected_generation is None
        generation = 0 if expected_generation is None else expected_generation + 1
        usage = (None if self._retained_limits is None else
                 self._write_retained_usage(key, len(payload), expected_generation))
        if insert:
            try:
                cursor = self._connection.execute(
                    'INSERT INTO main.core_bytes VALUES (?, ?, ?)', (key, generation, payload))
            except sqlite3.IntegrityError as issue:
                if issue.sqlite_errorcode == sqlite3.SQLITE_CONSTRAINT_PRIMARYKEY:
                    raise _PhysicalPrimaryKeyConflict() from issue
                if (issue.sqlite_errorcode == sqlite3.SQLITE_CONSTRAINT_UNIQUE
                        and key.startswith(_RUN_DEFINITION_PREFIX)):
                    self._journal_schema()
                    # SQLite may check the index before the primary key.
                    # An occupied original address is still a key conflict.
                    if self.read_header(key) is not None:
                        raise _PhysicalPrimaryKeyConflict() from issue
                    result = self._connection.execute(_RUN_DEFINITION_INPUT_SQL, (payload,)).fetchone()
                    definition = result[0] if result is not None else None
                    if (type(definition) is str and len(definition) == 71
                            and definition.startswith('sha256:')
                            and all(value in '0123456789abcdef' for value in definition[7:])):
                        raise _PhysicalRunDefinitionConflict(definition) from issue
                raise
        else:
            cursor = self._connection.execute(
                '''UPDATE main.core_bytes SET generation = ?, payload = ?
                   WHERE generation = ? AND key = ?''',
                (generation, payload, expected_generation, key))
            if cursor.rowcount == 0:
                original = self.read_header(key)
                if original is None or original[0] != expected_generation:
                    raise _PhysicalWriteConflict()
        _require_write_applied(cursor)
        if usage is not None:
            _require_write_applied(self._connection.execute(
                'UPDATE main.actql_store_usage SET records = ?, payload_bytes = ? WHERE singleton = 1', usage))
        return generation
