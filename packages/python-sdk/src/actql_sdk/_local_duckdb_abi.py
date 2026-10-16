"""Generated selected DuckDB C declarations; do not edit."""
import ctypes as C

class _Result(C.Structure):
    _fields_ = [('deprecated_column_count', C.c_uint64), ('deprecated_row_count', C.c_uint64), ('deprecated_rows_changed', C.c_uint64), ('deprecated_columns', C.c_void_p), ('deprecated_error_message', C.c_void_p), ('internal_data', C.c_void_p)]

class _String_value_pointer(C.Structure):
    _fields_ = [('length', C.c_uint32), ('prefix', C.c_char * 4), ('ptr', C.c_void_p)]

class _String_value_inlined(C.Structure):
    _fields_ = [('length', C.c_uint32), ('inlined', C.c_char * 12)]

class _String_value(C.Union):
    _fields_ = [('pointer', _String_value_pointer), ('inlined', _String_value_inlined)]

class _String(C.Structure):
    _fields_ = [('value', _String_value)]

class _HugeInt(C.Structure):
    _fields_ = [('lower', C.c_uint64), ('upper', C.c_int64)]

class _UHugeInt(C.Structure):
    _fields_ = [('lower', C.c_uint64), ('upper', C.c_uint64)]

SIGNATURES = {
    'library_version': ([], C.c_char_p),
    'create_config': ([C.POINTER(C.c_void_p)], C.c_int),
    'set_config': ([C.c_void_p, C.c_char_p, C.c_char_p], C.c_int),
    'destroy_config': ([C.POINTER(C.c_void_p)], None),
    'open_ext': ([C.c_char_p, C.POINTER(C.c_void_p), C.c_void_p, C.POINTER(C.c_void_p)], C.c_int),
    'free': ([C.c_void_p], None),
    'connect': ([C.c_void_p, C.POINTER(C.c_void_p)], C.c_int),
    'disconnect': ([C.POINTER(C.c_void_p)], None),
    'close': ([C.POINTER(C.c_void_p)], None),
    'interrupt': ([C.c_void_p], None),
    'query': ([C.c_void_p, C.c_char_p, C.POINTER(_Result)], C.c_int),
    'prepare': ([C.c_void_p, C.c_char_p, C.POINTER(C.c_void_p)], C.c_int),
    'nparams': ([C.c_void_p], C.c_uint64),
    'bind_null': ([C.c_void_p, C.c_uint64], C.c_int),
    'bind_boolean': ([C.c_void_p, C.c_uint64, C.c_bool], C.c_int),
    'bind_double': ([C.c_void_p, C.c_uint64, C.c_double], C.c_int),
    'bind_varchar_length': ([C.c_void_p, C.c_uint64, C.c_char_p, C.c_uint64], C.c_int),
    'destroy_prepare': ([C.POINTER(C.c_void_p)], None),
    'execute_prepared_streaming': ([C.c_void_p, C.POINTER(_Result)], C.c_int),
    'destroy_result': ([C.POINTER(_Result)], None),
    'result_error': ([C.POINTER(_Result)], C.c_void_p),
    'column_count': ([C.POINTER(_Result)], C.c_uint64),
    'column_type': ([C.POINTER(_Result), C.c_uint64], C.c_int),
    'column_name': ([C.POINTER(_Result), C.c_uint64], C.c_void_p),
    'column_logical_type': ([C.POINTER(_Result), C.c_uint64], C.c_void_p),
    'decimal_width': ([C.c_void_p], C.c_uint8),
    'decimal_scale': ([C.c_void_p], C.c_uint8),
    'decimal_internal_type': ([C.c_void_p], C.c_int),
    'destroy_logical_type': ([C.POINTER(C.c_void_p)], None),
    'fetch_chunk': ([_Result], C.c_void_p),
    'destroy_data_chunk': ([C.POINTER(C.c_void_p)], None),
    'data_chunk_get_size': ([C.c_void_p], C.c_uint64),
    'data_chunk_get_column_count': ([C.c_void_p], C.c_uint64),
    'data_chunk_get_vector': ([C.c_void_p, C.c_uint64], C.c_void_p),
    'vector_get_validity': ([C.c_void_p], C.POINTER(C.c_uint64)),
    'validity_row_is_valid': ([C.POINTER(C.c_uint64), C.c_uint64], C.c_bool),
    'vector_get_data': ([C.c_void_p], C.c_void_p),
    'string_t_length': ([_String], C.c_uint32),
    'string_t_data': ([C.POINTER(_String)], C.c_void_p),
}

PARAMETERS = {
    'library_version': (),
    'create_config': (('out_config', 'duckdb_config *'),),
    'set_config': (('config', 'duckdb_config'), ('name', 'const char *'), ('option', 'const char *')),
    'destroy_config': (('config', 'duckdb_config *'),),
    'open_ext': (('path', 'const char *'), ('out_database', 'duckdb_database *'), ('config', 'duckdb_config'), ('out_error', 'char **')),
    'free': (('ptr', 'void *'),),
    'connect': (('database', 'duckdb_database'), ('out_connection', 'duckdb_connection *')),
    'disconnect': (('connection', 'duckdb_connection *'),),
    'close': (('database', 'duckdb_database *'),),
    'interrupt': (('connection', 'duckdb_connection'),),
    'query': (('connection', 'duckdb_connection'), ('query', 'const char *'), ('out_result', 'duckdb_result *')),
    'prepare': (('connection', 'duckdb_connection'), ('query', 'const char *'), ('out_prepared_statement', 'duckdb_prepared_statement *')),
    'nparams': (('prepared_statement', 'duckdb_prepared_statement'),),
    'bind_null': (('prepared_statement', 'duckdb_prepared_statement'), ('param_idx', 'idx_t')),
    'bind_boolean': (('prepared_statement', 'duckdb_prepared_statement'), ('param_idx', 'idx_t'), ('val', 'bool')),
    'bind_double': (('prepared_statement', 'duckdb_prepared_statement'), ('param_idx', 'idx_t'), ('val', 'double')),
    'bind_varchar_length': (('prepared_statement', 'duckdb_prepared_statement'), ('param_idx', 'idx_t'), ('val', 'const char *'), ('length', 'idx_t')),
    'destroy_prepare': (('prepared_statement', 'duckdb_prepared_statement *'),),
    'execute_prepared_streaming': (('prepared_statement', 'duckdb_prepared_statement'), ('out_result', 'duckdb_result *')),
    'destroy_result': (('result', 'duckdb_result *'),),
    'result_error': (('result', 'duckdb_result *'),),
    'column_count': (('result', 'duckdb_result *'),),
    'column_type': (('result', 'duckdb_result *'), ('col', 'idx_t')),
    'column_name': (('result', 'duckdb_result *'), ('col', 'idx_t')),
    'column_logical_type': (('result', 'duckdb_result *'), ('col', 'idx_t')),
    'decimal_width': (('type', 'duckdb_logical_type'),),
    'decimal_scale': (('type', 'duckdb_logical_type'),),
    'decimal_internal_type': (('type', 'duckdb_logical_type'),),
    'destroy_logical_type': (('type', 'duckdb_logical_type *'),),
    'fetch_chunk': (('result', 'duckdb_result'),),
    'destroy_data_chunk': (('chunk', 'duckdb_data_chunk *'),),
    'data_chunk_get_size': (('chunk', 'duckdb_data_chunk'),),
    'data_chunk_get_column_count': (('chunk', 'duckdb_data_chunk'),),
    'data_chunk_get_vector': (('chunk', 'duckdb_data_chunk'), ('col_idx', 'idx_t')),
    'vector_get_validity': (('vector', 'duckdb_vector'),),
    'validity_row_is_valid': (('validity', 'uint64_t *'), ('row', 'idx_t')),
    'vector_get_data': (('vector', 'duckdb_vector'),),
    'string_t_length': (('string', 'duckdb_string_t'),),
    'string_t_data': (('string', 'duckdb_string_t *'),),
}

LAYOUT_PATHS = {'duckdb_result': ['deprecated_column_count', 'deprecated_row_count', 'deprecated_rows_changed', 'deprecated_columns', 'deprecated_error_message', 'internal_data'], 'duckdb_string_t': ['value.pointer.length', 'value.pointer.prefix', 'value.pointer.ptr', 'value.inlined.length', 'value.inlined.inlined'], 'duckdb_hugeint': ['lower', 'upper'], 'duckdb_uhugeint': ['lower', 'upper']}

def bind(library):
    """Already digest-selected library only; no database or query operation."""
    for name, (arguments, result) in SIGNATURES.items():
        try:
            call = getattr(library, "duckdb_" + name)
        except AttributeError as error:
            raise ValueError("Installed DuckDB lacks the bounded C API") from error
        call.argtypes, call.restype = list(arguments), result
