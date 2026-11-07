"""Mechanical operations on the existing LocalByteStore's one physical DB.

No SQL-string execution interface is offered to another backend. The existing
Store retains its original identity, transaction, fences, capacity decisions,
callback loans and failure custody. These observations issue none of those.
"""
from __future__ import annotations

import sqlite3
from collections.abc import Callable
from typing import Any, Protocol, cast


_CLOSED_SQL_BYTES = 65536


class _TrackedSQLiteConnection(sqlite3.Connection):
    """Keep transaction identity even for SQL issued through the raw connection.

    SQLite invokes its trace for every execution, including cached statements.
    The installed hook remains present when a diagnostic trace is replaced or
    removed. User trace exceptions retain SQLite's normal callback handling.
    """
    __slots__ = ('_transaction_epoch', '_outer_transaction_epoch', '_user_trace', '_trace_depth',
                 '_observation_eligible', '_encoding_eligible', '_closed_invocation')

    def __init__(self, *args: Any, **kwargs: Any) -> None:
        super().__init__(*args, **kwargs)
        self._transaction_epoch = 0
        self._outer_transaction_epoch = 0
        self._trace_depth = 0
        self._user_trace: Callable[[str], object] | None = None
        self._closed_invocation: Any = None
        detect_types = kwargs.get('detect_types', args[2] if len(args) > 2 else 0)
        self._observation_eligible = detect_types == 0
        self._encoding_eligible = False
        super().set_trace_callback(self._trace_transaction)

    def _qualify_encoding(self) -> None:
        # Only the Store calls this after publishing connection cleanup
        # custody. Constructor acquisition adds no fallible SQL observation.
        self._encoding_eligible = self.execute('PRAGMA encoding').fetchone() == ('UTF-8',)

    def _closed_eligible(self) -> bool:
        if (not self._observation_eligible or not self._encoding_eligible or self.row_factory is not None
                or self.text_factory is not str or type(sqlite3.adapters) is not dict):
            return False
        # Converters are disabled at construction. Relevant global adapters
        # may change independently of this connection, so inspect them now.
        return not any((kind, sqlite3.PrepareProtocol) in sqlite3.adapters
                       for kind in (str, int, float, bytes, type(None)))

    def _customize(self) -> None:
        self._observation_eligible = False
        span = self._closed_invocation
        if span is not None:
            error = RuntimeError('SQLite customization during closed observation')
            span._fail(error)
            raise error

    def __setattr__(self, name: str, value: object) -> None:
        if name in ('row_factory', 'text_factory') and hasattr(self, '_observation_eligible'):
            self._customize()
        super().__setattr__(name, value)

    def execute(self, sql: str, parameters: Any = (), /) -> sqlite3.Cursor:
        span = self._closed_invocation
        if span is not None and not span.suspended:
            try:
                span._guard_sql()
                # Only the audited physical read methods below construct
                # bounded literals. Never dispatch global adapters here,
                # including adapters registered concurrently for private types.
                if type(parameters) is not tuple or parameters:
                    raise ValueError('Closed SQLite reads require original literal transport')
                return super().execute(sql)
            except BaseException as error:
                span._fail(error)
                raise span.failure
        return super().execute(sql, parameters)

    def deserialize(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().deserialize(*args, **kwargs)

    def backup(self, *args: Any, **kwargs: Any) -> None:
        if kwargs.get('progress') is not None:
            self._customize()
        return super().backup(*args, **kwargs)

    def set_progress_handler(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().set_progress_handler(*args, **kwargs)

    def set_authorizer(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().set_authorizer(*args, **kwargs)

    def create_function(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().create_function(*args, **kwargs)

    def create_aggregate(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().create_aggregate(*args, **kwargs)

    def create_window_function(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().create_window_function(*args, **kwargs)

    def create_collation(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().create_collation(*args, **kwargs)

    def enable_load_extension(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().enable_load_extension(*args, **kwargs)

    def load_extension(self, *args: Any, **kwargs: Any) -> None:
        self._customize()
        return super().load_extension(*args, **kwargs)

    @staticmethod
    def _transaction_tokens(statement: str) -> tuple[str, ...]:
        # Only the first three unquoted words matter: ROLLBACK [TRANSACTION]
        # TO preserves the outer transaction. Skip comments between words,
        # but never interpret quoted strings/identifiers as control keywords.
        offset = 0
        words: list[str] = []
        while len(words) < 3:
            while offset < len(statement):
                if statement[offset] in ' \t\r\n\v\f\ufeff' or (
                        not words and statement[offset] == ';'):
                    offset += 1
                elif statement.startswith('--', offset):
                    end = statement.find('\n', offset + 2)
                    if end < 0:
                        return tuple(words)
                    offset = end + 1
                elif statement.startswith('/*', offset):
                    end = statement.find('*/', offset + 2)
                    if end < 0:
                        return tuple(words)
                    offset = end + 2
                else:
                    break
            end = offset
            while (end < len(statement) and statement[end].isascii()
                   and (statement[end].isalnum() or statement[end] == '_')):
                end += 1
            if end == offset:
                break
            words.append(statement[offset:end].upper())
            offset = end
        return tuple(words)

    def _trace_transaction(self, statement: str) -> None:
        # SQLite marks SQL executed recursively by a trace callback with a
        # diagnostic '-- ' prefix. That prefix is not part of the executed SQL.
        actual = (statement[3:] if self._trace_depth and statement.startswith('-- ')
                  else statement)
        words = self._transaction_tokens(actual)
        command = words[0] if words else ''
        if command in {'BEGIN', 'COMMIT', 'END', 'ROLLBACK', 'SAVEPOINT', 'RELEASE'}:
            self._transaction_epoch += 1
            rollback_to = (command == 'ROLLBACK' and (
                words[1:2] == ('TO',) or words[1:3] == ('TRANSACTION', 'TO')))
            # Nested savepoints preserve the reader's outer SQLite snapshot.
            # The stricter write-free port separately observes every control.
            if (command in {'BEGIN', 'COMMIT', 'END'}
                    or command == 'ROLLBACK' and not rollback_to
                    or command == 'SAVEPOINT' and not self.in_transaction):
                self._outer_transaction_epoch += 1
        callback = self._user_trace
        if callback is not None:
            self._trace_depth += 1
            try:
                callback(statement)
            finally:
                self._trace_depth -= 1

    def set_trace_callback(self, trace_callback: Callable[[str], object] | None) -> None:
        self._customize()
        if trace_callback is not None and not callable(trace_callback):
            raise TypeError('SQLite trace callback must be callable or None')
        # Retain sqlite3's closed-connection/registration checks and leave the
        # previous callback untouched if registration itself fails.
        super().set_trace_callback(self._trace_transaction)
        self._user_trace = trace_callback


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

    def _read_sql(self, fragments: tuple[str, ...], values: tuple[object, ...]) -> sqlite3.Cursor:
        """Execute only an owned read template, without adapter dispatch in a span.

        Call sites supply literal SQL fragments, not an interpolated arbitrary
        statement. Hex text preserves quotes, NUL and Unicode on the admitted
        UTF-8 database. The legacy path retains ordinary parameter semantics.
        """
        connection = self._connection
        span = (connection._closed_invocation
                if type(connection) is _TrackedSQLiteConnection else None)
        if span is None or span.suspended:
            return connection.execute('?'.join(fragments), values)
        try:
            span._guard_sql()
            if len(values) > 3 or len(fragments) != len(values) + 1:
                raise ValueError('Invalid original closed SQLite read shape')
            parts = [fragments[0]]
            for value, suffix in zip(values, fragments[1:]):
                if type(value) is str:
                    encoded = value.encode('utf-8')
                    if len(encoded) > 4096:
                        raise ValueError('Closed SQLite text exceeds original key bound')
                    literal = "CAST(X'" + encoded.hex() + "' AS TEXT)"
                elif type(value) is int and -(2**63) <= value < 2**63:
                    literal = str(value)
                else:
                    raise ValueError('Non-original closed SQLite read value')
                parts.extend((literal, suffix))
            statement = ''.join(parts)
            if len(statement) > _CLOSED_SQL_BYTES:
                raise ValueError('Closed SQLite statement exceeds its reservation')
            return connection.execute(statement)
        except BaseException as error:
            span._fail(error)
            raise span.failure

    def _snapshot_identity(self) -> tuple[sqlite3.Connection, int, int, tuple[int, int]]:
        """Same live transaction plus SQLite's actual mutation counter, DATA only."""
        connection = self._connection
        sequence = self._transaction_sequence
        epoch = (connection._outer_transaction_epoch
                 if type(connection) is _TrackedSQLiteConnection else sequence)
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
                or (type(connection) is _TrackedSQLiteConnection
                    and connection._outer_transaction_epoch != epoch)
                or not connection.in_transaction):
            raise ValueError('Original SQLite snapshot changed during observation')
        return connection, epoch, connection.total_changes, (schema[0], temporary[0])

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
        rows = self._read_sql(("""SELECT
            CASE WHEN length(name) <= 34 THEN name ELSE NULL END,
            type, CASE WHEN length(tbl_name) <= 16 THEN tbl_name ELSE NULL END,
            CASE WHEN length(sql) <= """, """ THEN sql ELSE NULL END
            FROM main.sqlite_schema WHERE name NOT LIKE 'sqlite_%'
            ORDER BY name LIMIT 4"""),
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
        raw = self._read_sql(('''SELECT generation,
            CASE WHEN length(payload) <= ''', ''' THEN payload ELSE NULL END,
            typeof(payload), length(payload)
            FROM core_bytes WHERE key = ''', ''), (max_bytes, key)).fetchone()
        return cast(tuple[object, object, object, object] | None, raw)

    def read_header(self, key: str) -> tuple[int, int] | None:
        return cast(tuple[int, int] | None, self._read_sql((
            'SELECT generation, length(payload) FROM core_bytes WHERE key = ', ''),
            (key,)).fetchone())

    def scan_range(self, lower: str, upper: str, max_bytes: int, *, inclusive: bool,
                   exact: bool) -> tuple[object, object, object, object, object] | None:
        relation = '=' if exact else '>=' if inclusive else '>'
        raw = self._read_sql(('''SELECT
            CASE WHEN length(CAST(key AS BLOB)) <= 4096 THEN key ELSE NULL END,
            generation,
            CASE WHEN length(payload) <= ''', f''' THEN payload ELSE NULL END,
            typeof(payload), length(payload)
            FROM core_bytes WHERE key {relation} ''', ' AND key < ', '''
            ORDER BY key COLLATE BINARY LIMIT 1'''), (max_bytes, lower, upper)).fetchone()
        return cast(tuple[object, object, object, object, object] | None, raw)

    def read_capacity(self, namespace: str, key: str) -> tuple[int, int] | None:
        return cast(tuple[int, int] | None, self._read_sql((
            '''SELECT reserved_bytes, reserved_objects
            FROM actql_capacity WHERE namespace = ''', ' AND reservation_key = ', ''),
            (namespace, key)).fetchone())

    def capacity_usage(self, namespace: str) -> tuple[int, int]:
        return cast(tuple[int, int], self._read_sql((
            '''SELECT coalesce(sum(reserved_bytes), 0),
            coalesce(sum(reserved_objects), 0) FROM actql_capacity WHERE namespace = ''', ''),
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
