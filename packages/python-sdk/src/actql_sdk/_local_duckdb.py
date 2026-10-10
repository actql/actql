"""Private physical DuckDB handles; no query, Run or recovery authority.

The calling Core Host must reserve native workspace and output retention first.
This adapter bounds individual transfers, not aggregate Local memory. SQL is
supplied by the checked Core acquisition Owner, never interpreted here.
"""
from __future__ import annotations

import ctypes as C
from dataclasses import dataclass
import hashlib
from pathlib import Path
from threading import Lock
from typing import Any

from ._duckdb_environment import SETTINGS


class DuckDBPhysicalError(RuntimeError):
    """A physical failure, not a public Run outcome or permission to retry."""


def _bounded_utf8(value: str, maximum: int) -> bytes:
    # Count raw UTF-8 before allocating a foreign-call copy. Never normalize.
    if len(value) > maximum:
        raise ValueError('DuckDB text transfer capacity exceeded')
    size = 0
    for character in value:
        code = ord(character)
        if 0xD800 <= code <= 0xDFFF:
            raise ValueError('Invalid DuckDB text transfer')
        size += 1 if code < 128 else 2 if code < 2048 else 3 if code < 65536 else 4
        if size > maximum:
            raise ValueError('DuckDB text transfer capacity exceeded')
    return value.encode('utf8')


# Layouts match vendor/duckdb/1.4.3/duckdb.h and the existing native adapter.
class _Result(C.Structure):
    _fields_ = [('columns', C.c_uint64), ('rows', C.c_uint64),
                ('changed', C.c_uint64), ('column_data', C.c_void_p),
                ('error', C.c_void_p), ('internal', C.c_void_p)]


class _StringPointer(C.Structure):
    _fields_ = [('length', C.c_uint32), ('prefix', C.c_char * 4),
                ('pointer', C.c_void_p)]


class _StringInline(C.Structure):
    _fields_ = [('length', C.c_uint32), ('bytes', C.c_char * 12)]


class _StringValue(C.Union):
    _fields_ = [('pointer', _StringPointer), ('inline', _StringInline)]


class _String(C.Structure):
    _fields_ = [('value', _StringValue)]


class _HugeInt(C.Structure):
    _fields_ = [('lower', C.c_uint64), ('upper', C.c_int64)]


class _UHugeInt(C.Structure):
    _fields_ = [('lower', C.c_uint64), ('upper', C.c_uint64)]


@dataclass(frozen=True, slots=True)
class DuckDBTransferLimits:
    max_columns: int = 64
    max_rows: int = 100_000
    max_cell_bytes: int = 65_536
    max_row_bytes: int = 1_048_576

    def __post_init__(self) -> None:
        for value, maximum in ((self.max_columns, 1024),
                               (self.max_rows, 2**63 - 1),
                               (self.max_cell_bytes, 1_048_576),
                               (self.max_row_bytes, 1_048_576)):
            if type(value) is not int or not 0 <= value <= maximum:
                raise ValueError('Invalid DuckDB transfer limit')
        if self.max_row_bytes < 2:
            raise ValueError('Invalid DuckDB row capacity')


class DuckDBLibrary:
    """Explicit installed component, with no package discovery or download."""

    def __init__(self, path: Path, *, digest: str, version: str) -> None:
        actual = hashlib.sha256()
        with path.open('rb') as source:
            for block in iter(lambda: source.read(65_536), b''):
                actual.update(block)
        if actual.hexdigest() != digest:
            raise ValueError('Invalid installed DuckDB component digest')
        self.api = C.CDLL(str(path))
        p = C.c_void_p
        pp = C.POINTER(p)
        rp = C.POINTER(_Result)
        signatures: dict[str, tuple[list[Any], Any]] = {
            'library_version': ([], C.c_char_p),
            'create_config': ([pp], C.c_int),
            'set_config': ([p, C.c_char_p, C.c_char_p], C.c_int),
            'destroy_config': ([pp], None),
            'open_ext': ([C.c_char_p, pp, p, pp], C.c_int),
            'free': ([p], None),
            'connect': ([p, pp], C.c_int),
            'disconnect': ([pp], None),
            'close': ([pp], None),
            'interrupt': ([p], None),
            'prepare': ([p, C.c_char_p, pp], C.c_int),
            'nparams': ([p], C.c_uint64),
            'destroy_prepare': ([pp], None),
            'execute_prepared_streaming': ([p, rp], C.c_int),
            'destroy_result': ([rp], None),
            'result_error': ([rp], p),
            'column_count': ([rp], C.c_uint64),
            'column_type': ([rp, C.c_uint64], C.c_int),
            'column_name': ([rp, C.c_uint64], p),
            'column_logical_type': ([rp, C.c_uint64], p),
            'decimal_width': ([p], C.c_uint8),
            'decimal_scale': ([p], C.c_uint8),
            'decimal_internal_type': ([p], C.c_int),
            'destroy_logical_type': ([pp], None),
            'fetch_chunk': ([_Result], p),
            'destroy_data_chunk': ([pp], None),
            'data_chunk_get_size': ([p], C.c_uint64),
            'data_chunk_get_column_count': ([p], C.c_uint64),
            'data_chunk_get_vector': ([p, C.c_uint64], p),
            'vector_get_validity': ([p], C.POINTER(C.c_uint64)),
            'validity_row_is_valid': ([C.POINTER(C.c_uint64), C.c_uint64], C.c_bool),
            'vector_get_data': ([p], p),
            'string_t_length': ([_String], C.c_uint32),
            'string_t_data': ([C.POINTER(_String)], p),
        }
        for name, (arguments, result) in signatures.items():
            try:
                function = getattr(self.api, 'duckdb_' + name)
            except AttributeError as error:
                raise ValueError('Installed DuckDB lacks the bounded C API') from error
            function.argtypes = arguments
            function.restype = result
        if self.api.duckdb_library_version() != version.encode('ascii'):
            raise ValueError('Unexpected installed DuckDB component version')


class DuckDBConnection:
    """One physical connection; close never cancels or reruns a Run."""

    def __init__(self, library: DuckDBLibrary, path: str, *, memory_bytes: int,
                 readonly: bool = True) -> None:
        if (type(memory_bytes) is not int or not 0 < memory_bytes <= 2**63 - 1
                or type(readonly) is not bool or type(path) is not str
                or '\0' in path or len(path) > 4096
                or (readonly and not path)):
            raise ValueError('Invalid physical DuckDB configuration')
        encoded_path = _bounded_utf8(path, 4096)
        self._api = library.api
        self._identity = self
        self._database = C.c_void_p()
        self._connection = C.c_void_p()
        self._config = C.c_void_p()
        self._open_error = C.c_void_p()
        self._io = Lock()
        self._lifetime = Lock()
        self._streams: set[DuckDBStream] = set()
        self._closing = False
        self._closed = False
        try:
            if self._api.duckdb_create_config(C.byref(self._config)) != 0:
                raise DuckDBPhysicalError('DuckDB configuration creation failed')
            settings = (('access_mode', 'READ_ONLY' if readonly else 'READ_WRITE'),
                        ('enable_external_access', 'false'), ('threads', '1'),
                        ('memory_limit', f'{memory_bytes}B'), *SETTINGS)
            for name, value in settings:
                if self._api.duckdb_set_config(self._config, name.encode('ascii'),
                                              value.encode('ascii')) != 0:
                    raise DuckDBPhysicalError('DuckDB configuration was rejected')
            if self._api.duckdb_open_ext(encoded_path or None,
                    C.byref(self._database), self._config,
                    C.byref(self._open_error)) != 0:
                # Native error text can contain private paths or query values.
                raise DuckDBPhysicalError('DuckDB database open failed')
            if self._api.duckdb_connect(self._database,
                                        C.byref(self._connection)) != 0:
                raise DuckDBPhysicalError('DuckDB connection failed')
            self._dispose_configuration()
        except BaseException as error:
            try:
                self.close()
            except BaseException:
                pass
            # Preserve cleanup custody if a foreign destructor fails.
            if not self._closed:
                setattr(error, 'physical_cleanup', self)
            raise

    def _dispose_configuration(self) -> None:
        if self._open_error.value:
            self._api.duckdb_free(self._open_error)
            self._open_error = C.c_void_p()
        if self._config.value:
            self._api.duckdb_destroy_config(C.byref(self._config))

    def prepare(self, checked_sql: str, limits: DuckDBTransferLimits) -> DuckDBStream:
        self._owned()
        if (type(checked_sql) is not str or not checked_sql or '\0' in checked_sql
                or len(checked_sql) > 1_048_576
                or type(limits) is not DuckDBTransferLimits):
            raise ValueError('Invalid checked DuckDB transfer')
        encoded_sql = _bounded_utf8(checked_sql, 1_048_576)
        with self._io:
            if self._closing or self._closed or self._streams:
                raise DuckDBPhysicalError('DuckDB connection is unavailable')
            stream = DuckDBStream(self, limits)
            # Register custody before the native prepare call can fail.
            self._streams.add(stream)
            try:
                if self._api.duckdb_prepare(self._connection,
                        encoded_sql, C.byref(stream._statement)) != 0:
                    raise DuckDBPhysicalError('DuckDB checked query preparation failed')
                if self._api.duckdb_nparams(stream._statement) != 0:
                    raise DuckDBPhysicalError('DuckDB query parameters are not bound')
                return stream
            except BaseException as error:
                try:
                    stream._dispose()
                except BaseException:
                    pass
                if stream in self._streams:
                    setattr(error, 'physical_cleanup', stream)
                raise

    def interrupt(self) -> None:
        self._owned()
        # Cancellation delivery can overlap execution; only Core decides the
        # terminal Run state after physical completion has been observed.
        with self._lifetime:
            if self._connection.value:
                self._api.duckdb_interrupt(self._connection)

    def close(self) -> bool:
        self._owned()
        if self._closed:
            return True
        self._closing = True
        if not self._io.acquire(blocking=False):
            return False
        try:
            if self._streams:
                return False
            with self._lifetime:
                if self._connection.value:
                    self._api.duckdb_disconnect(C.byref(self._connection))
                if self._database.value:
                    self._api.duckdb_close(C.byref(self._database))
                self._dispose_configuration()
                self._closed = True
                return True
        finally:
            self._io.release()

    def _owned(self) -> None:
        if self._identity is not self:
            raise ValueError('Foreign DuckDB connection handle')


_INTEGER_TYPES: dict[int, Any] = {
    2: C.c_int8, 3: C.c_int16, 4: C.c_int32, 5: C.c_int64,
    6: C.c_uint8, 7: C.c_uint16, 8: C.c_uint32, 9: C.c_uint64,
    12: C.c_int64, 13: C.c_int32, 20: C.c_int64, 21: C.c_int64,
    22: C.c_int64, 31: C.c_int64,
}
_TYPE_NAMES = {
    1: b'BOOLEAN', 2: b'TINYINT', 3: b'SMALLINT', 4: b'INTEGER',
    5: b'BIGINT', 6: b'UTINYINT', 7: b'USMALLINT', 8: b'UINTEGER',
    9: b'UBIGINT', 10: b'FLOAT', 11: b'DOUBLE', 12: b'TIMESTAMP',
    13: b'DATE', 16: b'HUGEINT', 17: b'VARCHAR', 19: b'DECIMAL',
    20: b'TIMESTAMP_S', 21: b'TIMESTAMP_MS', 22: b'TIMESTAMP_NS',
    31: b'TIMESTAMP_TZ', 32: b'UHUGEINT',
}
_SUPPORTED = frozenset(_TYPE_NAMES)


class _RowWriter:
    def __init__(self, destination: bytearray, maximum: int) -> None:
        if type(destination) is not bytearray or not 2 <= len(destination) <= maximum:
            raise ValueError('DuckDB row requires a reserved bounded destination')
        self.destination = destination
        self.position = 0

    def put(self, data: bytes) -> None:
        end = self.position + len(data)
        if end > len(self.destination):
            raise DuckDBPhysicalError('DuckDB row capacity exceeded')
        self.destination[self.position:end] = data
        self.position = end

    def string(self, address: int, length: int, maximum: int) -> None:
        # Inspect native length before creating any Python string/bytes copy.
        if length > maximum or (not address and length):
            raise DuckDBPhysicalError('DuckDB cell capacity exceeded')
        # The worst case can expand to six JSON bytes per raw byte. Check each
        # byte while writing into the already reserved destination, without
        # allocating an unbounded escaped copy.
        self.put(b'"')
        for index in range(length):
            byte = C.c_ubyte.from_address(address + index).value
            if byte == 34:
                self.put(b'\\"')
            elif byte == 92:
                self.put(b'\\\\')
            elif byte < 32:
                self.put(f'\\u{byte:04x}'.encode('ascii'))
            else:
                self.put(bytes((byte,)))
        self.put(b'"')


class DuckDBStream:
    """Native statement/result/chunk custody, not a public Result reader."""

    def __init__(self, connection: DuckDBConnection,
                 limits: DuckDBTransferLimits) -> None:
        self._owner = connection
        self._identity = self
        self._api = connection._api
        self._limits = limits
        self._statement = C.c_void_p()
        self._result = _Result()
        self._result_created = False
        self._chunk = C.c_void_p()
        self._chunk_rows = 0
        self._row = 0
        self._read_rows = 0
        self._types: tuple[int, ...] = ()
        self._decimals: dict[int, tuple[int, int, int]] = {}
        self._logical = C.c_void_p()
        self._executed = False
        self._failed = False
        self._ended = False
        self._closed = False

    def execute(self) -> None:
        self._owned()
        with self._owner._io:
            if self._closed or self._executed or self._owner._closing:
                raise DuckDBPhysicalError('DuckDB stream cannot execute')
            self._executed = True
            self._result_created = True
            try:
                if self._api.duckdb_execute_prepared_streaming(self._statement,
                        C.byref(self._result)) != 0:
                    raise DuckDBPhysicalError('DuckDB physical execution failed')
                count = self._api.duckdb_column_count(C.byref(self._result))
                if count > self._limits.max_columns:
                    raise DuckDBPhysicalError('DuckDB column capacity exceeded')
                types = tuple(self._api.duckdb_column_type(C.byref(self._result), i)
                              for i in range(count))
                if any(kind not in _SUPPORTED for kind in types):
                    raise DuckDBPhysicalError('Unsupported DuckDB physical type')
                for index, kind in enumerate(types):
                    if kind == 19:
                        self._logical = C.c_void_p(self._api.duckdb_column_logical_type(
                            C.byref(self._result), index))
                        if not self._logical.value:
                            raise DuckDBPhysicalError('Invalid DuckDB decimal metadata')
                        storage = self._api.duckdb_decimal_internal_type(self._logical)
                        width = self._api.duckdb_decimal_width(self._logical)
                        scale = self._api.duckdb_decimal_scale(self._logical)
                        if storage not in (3, 4, 5, 16) or not 1 <= width <= 38 or not 0 <= scale <= width:
                            raise DuckDBPhysicalError('Invalid DuckDB decimal metadata')
                        self._decimals[index] = (width, scale, storage)
                        self._api.duckdb_destroy_logical_type(C.byref(self._logical))
                self._types = types
            except BaseException:
                self._failed = True
                raise

    def write_fields(self, destination: bytearray) -> int:
        """Existing native field codec, into a caller-reserved output buffer."""
        self._owned()
        writer = _RowWriter(destination, self._limits.max_row_bytes)
        with self._owner._io:
            if self._closed or not self._executed or self._failed:
                raise DuckDBPhysicalError('DuckDB metadata is unavailable')
            writer.put(b'[')
            for column, kind in enumerate(self._types):
                if column:
                    writer.put(b',')
                address = self._api.duckdb_column_name(C.byref(self._result), column)
                if not address:
                    raise DuckDBPhysicalError('Missing DuckDB column name')
                length = 0
                while length <= self._limits.max_cell_bytes:
                    if not C.c_ubyte.from_address(address + length).value:
                        break
                    length += 1
                writer.put(b'[')
                writer.string(address, length, self._limits.max_cell_bytes)
                writer.put(b',"' + _TYPE_NAMES[kind] + b'",')
                decimal = self._decimals.get(column)
                if decimal is None:
                    writer.put(b'null,null]')
                else:
                    writer.put(f'"{decimal[0]}","{decimal[1]}"]'.encode('ascii'))
            writer.put(b']')
            return writer.position

    def read_row(self, destination: bytearray) -> int | None:
        self._owned()
        writer = _RowWriter(destination, self._limits.max_row_bytes)
        with self._owner._io:
            if (self._closed or not self._executed or self._failed
                    or self._owner._closing):
                raise DuckDBPhysicalError('DuckDB stream cannot read')
            if self._ended:
                return None
            try:
                while self._row >= self._chunk_rows:
                    if self._chunk.value:
                        self._api.duckdb_destroy_data_chunk(C.byref(self._chunk))
                    self._chunk = C.c_void_p(self._api.duckdb_fetch_chunk(self._result))
                    if not self._chunk.value:
                        if self._api.duckdb_result_error(C.byref(self._result)):
                            raise DuckDBPhysicalError('DuckDB physical read failed')
                        self._ended = True
                        return None
                    self._chunk_rows = self._api.duckdb_data_chunk_get_size(self._chunk)
                    self._row = 0
                    if (self._chunk_rows > 2048 or
                        self._api.duckdb_data_chunk_get_column_count(self._chunk)
                            != len(self._types)):
                        raise DuckDBPhysicalError('Invalid DuckDB physical chunk')
                if self._read_rows >= self._limits.max_rows:
                    raise DuckDBPhysicalError('DuckDB row count capacity exceeded')
                writer.put(b'[')
                for column, kind in enumerate(self._types):
                    if column:
                        writer.put(b',')
                    self._cell(writer, column, kind)
                writer.put(b']')
                self._row += 1
                self._read_rows += 1
                return writer.position
            except BaseException:
                # A partial row is not delivered and is never retried as a
                # completed row. Keep every native handle until explicit close.
                self._failed = True
                raise

    def _cell(self, writer: _RowWriter, column: int, kind: int) -> None:
        vector = self._api.duckdb_data_chunk_get_vector(self._chunk, column)
        if not vector:
            raise DuckDBPhysicalError('Invalid DuckDB physical vector')
        validity = self._api.duckdb_vector_get_validity(vector)
        if validity and not self._api.duckdb_validity_row_is_valid(validity, self._row):
            writer.put(b'null')
            return
        data = self._api.duckdb_vector_get_data(vector)
        if not data:
            raise DuckDBPhysicalError('Missing DuckDB physical cell data')
        if kind == 17:
            value = C.cast(data, C.POINTER(_String))[self._row]
            length = self._api.duckdb_string_t_length(value)
            if length > self._limits.max_cell_bytes:
                raise DuckDBPhysicalError('DuckDB cell capacity exceeded')
            writer.string(self._api.duckdb_string_t_data(C.byref(value)), length,
                          self._limits.max_cell_bytes)
        elif kind == 1:
            writer.put(b'true' if C.cast(data, C.POINTER(C.c_bool))[self._row] else b'false')
        elif kind in (10, 11):
            # Existing native row codec preserves IEEE bits, including -0/NaN.
            scalar = C.c_uint32 if kind == 10 else C.c_uint64
            bits = C.cast(data, C.POINTER(scalar))[self._row]
            width = 8 if kind == 10 else 16
            writer.put(f'"{bits:0{width}x}"'.encode('ascii'))
        else:
            if kind == 19:
                kind = self._decimals[column][2]
            if kind in (16, 32):
                huge_type = _HugeInt if kind == 16 else _UHugeInt
                huge = C.cast(data, C.POINTER(huge_type))[self._row]
                value = (huge.upper << 64) + huge.lower
            else:
                value = C.cast(data, C.POINTER(_INTEGER_TYPES[kind]))[self._row]
            writer.put(f'"{value}"'.encode('ascii'))

    def _dispose(self) -> None:
        if self._closed:
            return
        if self._logical.value:
            self._api.duckdb_destroy_logical_type(C.byref(self._logical))
        if self._chunk.value:
            self._api.duckdb_destroy_data_chunk(C.byref(self._chunk))
        if self._result_created:
            self._api.duckdb_destroy_result(C.byref(self._result))
            self._result_created = False
        if self._statement.value:
            self._api.duckdb_destroy_prepare(C.byref(self._statement))
        self._closed = True
        self._owner._streams.discard(self)

    def close(self) -> bool:
        self._owned()
        if self._closed:
            return True
        if not self._owner._io.acquire(blocking=False):
            return False
        try:
            self._dispose()
            return True
        finally:
            self._owner._io.release()

    def _owned(self) -> None:
        self._owner._owned()
        if self._identity is not self or (not self._closed and self not in self._owner._streams):
            raise ValueError('Foreign DuckDB stream handle')
