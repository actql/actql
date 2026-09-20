#include "moonbit.h"
#include "../../../vendor/duckdb/1.4.3/duckdb.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef const char *(*actql_duckdb_library_version_fn)(void);
typedef duckdb_state (*actql_duckdb_open_fn)(
  const char *, duckdb_database *
);
typedef void (*actql_duckdb_close_fn)(duckdb_database *);
typedef duckdb_state (*actql_duckdb_connect_fn)(
  duckdb_database, duckdb_connection *
);
typedef void (*actql_duckdb_disconnect_fn)(duckdb_connection *);
typedef duckdb_state (*actql_duckdb_query_fn)(
  duckdb_connection, const char *, duckdb_result *
);
typedef duckdb_state (*actql_duckdb_prepare_fn)(
  duckdb_connection, const char *, duckdb_prepared_statement *
);
typedef void (*actql_duckdb_destroy_prepare_fn)(duckdb_prepared_statement *);
typedef const char *(*actql_duckdb_prepare_error_fn)(duckdb_prepared_statement);
typedef idx_t (*actql_duckdb_nparams_fn)(duckdb_prepared_statement);
typedef duckdb_state (*actql_duckdb_bind_null_fn)(
  duckdb_prepared_statement, idx_t
);
typedef duckdb_state (*actql_duckdb_bind_boolean_fn)(
  duckdb_prepared_statement, idx_t, bool
);
typedef duckdb_state (*actql_duckdb_bind_double_fn)(
  duckdb_prepared_statement, idx_t, double
);
typedef duckdb_state (*actql_duckdb_bind_varchar_length_fn)(
  duckdb_prepared_statement, idx_t, const char *, idx_t
);
typedef duckdb_state (*actql_duckdb_bind_date_fn)(
  duckdb_prepared_statement, idx_t, duckdb_date
);
typedef duckdb_state (*actql_duckdb_bind_timestamp_tz_fn)(
  duckdb_prepared_statement, idx_t, duckdb_timestamp
);
typedef duckdb_state (*actql_duckdb_bind_decimal_fn)(
  duckdb_prepared_statement, idx_t, duckdb_decimal
);
typedef duckdb_state (*actql_duckdb_execute_prepared_streaming_fn)(
  duckdb_prepared_statement, duckdb_result *
);
typedef void (*actql_duckdb_destroy_result_fn)(duckdb_result *);
typedef const char *(*actql_duckdb_result_error_fn)(duckdb_result *);
typedef idx_t (*actql_duckdb_row_count_fn)(duckdb_result *);
typedef idx_t (*actql_duckdb_column_count_fn)(duckdb_result *);
typedef const char *(*actql_duckdb_column_name_fn)(duckdb_result *, idx_t);
typedef duckdb_type (*actql_duckdb_column_type_fn)(duckdb_result *, idx_t);
typedef duckdb_logical_type (*actql_duckdb_column_logical_type_fn)(
  duckdb_result *, idx_t
);
typedef uint8_t (*actql_duckdb_decimal_width_fn)(duckdb_logical_type);
typedef uint8_t (*actql_duckdb_decimal_scale_fn)(duckdb_logical_type);
typedef duckdb_type (*actql_duckdb_decimal_internal_type_fn)(
  duckdb_logical_type
);
typedef void (*actql_duckdb_destroy_logical_type_fn)(duckdb_logical_type *);
typedef duckdb_data_chunk (*actql_duckdb_fetch_chunk_fn)(duckdb_result);
typedef void (*actql_duckdb_destroy_data_chunk_fn)(duckdb_data_chunk *);
typedef idx_t (*actql_duckdb_data_chunk_get_column_count_fn)(duckdb_data_chunk);
typedef duckdb_vector (*actql_duckdb_data_chunk_get_vector_fn)(
  duckdb_data_chunk, idx_t
);
typedef idx_t (*actql_duckdb_data_chunk_get_size_fn)(duckdb_data_chunk);
typedef void *(*actql_duckdb_vector_get_data_fn)(duckdb_vector);
typedef uint64_t *(*actql_duckdb_vector_get_validity_fn)(duckdb_vector);
typedef bool (*actql_duckdb_validity_row_is_valid_fn)(uint64_t *, idx_t);
typedef uint32_t (*actql_duckdb_string_t_length_fn)(duckdb_string_t);
typedef const char *(*actql_duckdb_string_t_data_fn)(duckdb_string_t *);
typedef bool (*actql_duckdb_value_is_null_fn)(duckdb_result *, idx_t, idx_t);
typedef int64_t (*actql_duckdb_value_int64_fn)(duckdb_result *, idx_t, idx_t);

typedef struct {
  void *dynamic_library;
  char *error;
  actql_duckdb_library_version_fn library_version;
  actql_duckdb_open_fn open;
  actql_duckdb_close_fn close;
  actql_duckdb_connect_fn connect;
  actql_duckdb_disconnect_fn disconnect;
  actql_duckdb_query_fn query;
  actql_duckdb_prepare_fn prepare;
  actql_duckdb_destroy_prepare_fn destroy_prepare;
  actql_duckdb_prepare_error_fn prepare_error;
  actql_duckdb_nparams_fn nparams;
  actql_duckdb_bind_null_fn bind_null;
  actql_duckdb_bind_boolean_fn bind_boolean;
  actql_duckdb_bind_double_fn bind_double;
  actql_duckdb_bind_varchar_length_fn bind_varchar_length;
  actql_duckdb_bind_date_fn bind_date;
  actql_duckdb_bind_timestamp_tz_fn bind_timestamp_tz;
  actql_duckdb_bind_decimal_fn bind_decimal;
  actql_duckdb_execute_prepared_streaming_fn execute_prepared_streaming;
  actql_duckdb_destroy_result_fn destroy_result;
  actql_duckdb_result_error_fn result_error;
  actql_duckdb_row_count_fn row_count;
  actql_duckdb_column_count_fn column_count;
  actql_duckdb_column_name_fn column_name;
  actql_duckdb_column_type_fn column_type;
  actql_duckdb_column_logical_type_fn column_logical_type;
  actql_duckdb_decimal_width_fn decimal_width;
  actql_duckdb_decimal_scale_fn decimal_scale;
  actql_duckdb_decimal_internal_type_fn decimal_internal_type;
  actql_duckdb_destroy_logical_type_fn destroy_logical_type;
  actql_duckdb_fetch_chunk_fn fetch_chunk;
  actql_duckdb_destroy_data_chunk_fn destroy_data_chunk;
  actql_duckdb_data_chunk_get_column_count_fn data_chunk_get_column_count;
  actql_duckdb_data_chunk_get_vector_fn data_chunk_get_vector;
  actql_duckdb_data_chunk_get_size_fn data_chunk_get_size;
  actql_duckdb_vector_get_data_fn vector_get_data;
  actql_duckdb_vector_get_validity_fn vector_get_validity;
  actql_duckdb_validity_row_is_valid_fn validity_row_is_valid;
  actql_duckdb_string_t_length_fn string_t_length;
  actql_duckdb_string_t_data_fn string_t_data;
  actql_duckdb_value_is_null_fn value_is_null;
  actql_duckdb_value_int64_fn value_int64;
} actql_native_duckdb_library;

typedef struct {
  actql_native_duckdb_library *library;
  duckdb_database database;
  duckdb_connection connection;
  char *error;
  bool opened;
  bool accepting;
  uint32_t active_queries;
  bool query_ok;
  bool transaction_open;
} actql_native_duckdb_database;

typedef struct {
  char *data;
  size_t length;
  size_t capacity;
  size_t maximum;
  bool failed;
} actql_bounded_text;

typedef struct {
  actql_native_duckdb_database *database;
  duckdb_prepared_statement statement;
  duckdb_result result;
  duckdb_data_chunk chunk;
  idx_t chunk_offset;
  duckdb_type *types;
  duckdb_type *storage_types;
  uint8_t *decimal_widths;
  uint8_t *decimal_scales;
  idx_t column_count;
  idx_t parameter_count;
  idx_t bound_parameters;
  int32_t max_columns;
  int64_t max_rows;
  int64_t rows;
  int32_t max_chunk_rows;
  int32_t max_chunk_bytes;
  int32_t last_rows;
  char *fields_json;
  char *error;
  int32_t status;
  bool result_created;
  bool executed;
  bool opened;
} actql_native_duckdb_stream;

static void actql_replace_error(char **target, const char *message) {
  free(*target);
  if (message == NULL) {
    *target = NULL;
    return;
  }
  size_t length = strlen(message);
  *target = malloc(length + 1);
  if (*target != NULL) memcpy(*target, message, length + 1);
}

static char *actql_copy_text(moonbit_bytes_t bytes, int32_t length) {
  if (length < 0) return NULL;
  char *text = malloc((size_t)length + 1);
  if (text == NULL) return NULL;
  memcpy(text, bytes, (size_t)length);
  text[length] = '\0';
  return text;
}

static moonbit_bytes_t actql_copy_bytes(const char *text) {
  size_t length = text == NULL ? 0 : strlen(text);
  if (length > INT32_MAX) length = INT32_MAX;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)length);
  if (length > 0) memcpy(bytes, text, length);
  return bytes;
}

static void actql_text_init(actql_bounded_text *text, size_t maximum) {
  memset(text, 0, sizeof(*text));
  text->maximum = maximum;
}

static bool actql_text_reserve(actql_bounded_text *text, size_t additional) {
  if (text->failed || additional > text->maximum - text->length) {
    text->failed = true;
    return false;
  }
  size_t needed = text->length + additional + 1;
  if (needed <= text->capacity) return true;
  size_t capacity = text->capacity == 0 ? 128 : text->capacity;
  while (capacity < needed) {
    if (capacity > (text->maximum + 1) / 2) {
      capacity = text->maximum + 1;
      break;
    }
    capacity *= 2;
  }
  char *data = realloc(text->data, capacity);
  if (data == NULL) {
    text->failed = true;
    return false;
  }
  text->data = data;
  text->capacity = capacity;
  return true;
}

static bool actql_text_bytes(
  actql_bounded_text *text,
  const char *value,
  size_t length
) {
  if (!actql_text_reserve(text, length)) return false;
  if (length > 0) memcpy(text->data + text->length, value, length);
  text->length += length;
  text->data[text->length] = '\0';
  return true;
}

static bool actql_text_literal(actql_bounded_text *text, const char *value) {
  return actql_text_bytes(text, value, strlen(value));
}

static bool actql_text_json_string(
  actql_bounded_text *text,
  const char *value,
  size_t length
) {
  if (!actql_text_literal(text, "\"")) return false;
  for (size_t index = 0; index < length; index++) {
    unsigned char byte = (unsigned char)value[index];
    if (byte == '"' || byte == '\\') {
      char escaped[2] = {'\\', (char)byte};
      if (!actql_text_bytes(text, escaped, 2)) return false;
    } else if (byte < 0x20) {
      char escaped[7];
      snprintf(escaped, sizeof(escaped), "\\u%04x", byte);
      if (!actql_text_bytes(text, escaped, 6)) return false;
    } else if (!actql_text_bytes(text, (const char *)&value[index], 1)) {
      return false;
    }
  }
  return actql_text_literal(text, "\"");
}

static bool actql_text_i64(actql_bounded_text *text, int64_t value) {
  char digits[32];
  int length = snprintf(digits, sizeof(digits), "%lld", (long long)value);
  return length > 0 && actql_text_bytes(text, digits, (size_t)length);
}

static bool actql_text_u64(actql_bounded_text *text, uint64_t value) {
  char digits[32];
  int length = snprintf(
    digits, sizeof(digits), "%llu", (unsigned long long)value
  );
  return length > 0 && actql_text_bytes(text, digits, (size_t)length);
}

static size_t actql_u128_decimal(
  uint64_t upper,
  uint64_t lower,
  char output[40]
) {
  uint32_t limbs[4] = {
    (uint32_t)(upper >> 32),
    (uint32_t)upper,
    (uint32_t)(lower >> 32),
    (uint32_t)lower,
  };
  char reversed[40];
  size_t count = 0;
  do {
    uint64_t remainder = 0;
    for (size_t index = 0; index < 4; index++) {
      uint64_t value = (remainder << 32) | limbs[index];
      limbs[index] = (uint32_t)(value / 10);
      remainder = value % 10;
    }
    reversed[count++] = (char)('0' + remainder);
  } while (limbs[0] != 0 || limbs[1] != 0 || limbs[2] != 0 || limbs[3] != 0);
  for (size_t index = 0; index < count; index++) {
    output[index] = reversed[count - index - 1];
  }
  return count;
}

static size_t actql_i128_decimal(duckdb_hugeint value, char output[41]) {
  bool negative = value.upper < 0;
  uint64_t upper = (uint64_t)value.upper;
  uint64_t lower = value.lower;
  size_t offset = 0;
  if (negative) {
    lower = ~lower + 1;
    upper = ~upper + (lower == 0 ? 1 : 0);
    output[offset++] = '-';
  }
  return offset + actql_u128_decimal(upper, lower, output + offset);
}

static const char *actql_type_name(duckdb_type type) {
  switch (type) {
    case DUCKDB_TYPE_BOOLEAN: return "BOOLEAN";
    case DUCKDB_TYPE_TINYINT: return "TINYINT";
    case DUCKDB_TYPE_SMALLINT: return "SMALLINT";
    case DUCKDB_TYPE_INTEGER: return "INTEGER";
    case DUCKDB_TYPE_BIGINT: return "BIGINT";
    case DUCKDB_TYPE_UTINYINT: return "UTINYINT";
    case DUCKDB_TYPE_USMALLINT: return "USMALLINT";
    case DUCKDB_TYPE_UINTEGER: return "UINTEGER";
    case DUCKDB_TYPE_UBIGINT: return "UBIGINT";
    case DUCKDB_TYPE_HUGEINT: return "HUGEINT";
    case DUCKDB_TYPE_UHUGEINT: return "UHUGEINT";
    case DUCKDB_TYPE_FLOAT: return "FLOAT";
    case DUCKDB_TYPE_DOUBLE: return "DOUBLE";
    case DUCKDB_TYPE_VARCHAR: return "VARCHAR";
    case DUCKDB_TYPE_DECIMAL: return "DECIMAL";
    case DUCKDB_TYPE_DATE: return "DATE";
    case DUCKDB_TYPE_TIMESTAMP: return "TIMESTAMP";
    case DUCKDB_TYPE_TIMESTAMP_S: return "TIMESTAMP_S";
    case DUCKDB_TYPE_TIMESTAMP_MS: return "TIMESTAMP_MS";
    case DUCKDB_TYPE_TIMESTAMP_NS: return "TIMESTAMP_NS";
    case DUCKDB_TYPE_TIMESTAMP_TZ: return "TIMESTAMP_TZ";
    default: return NULL;
  }
}

static void actql_native_duckdb_library_finalize(void *value) {
  actql_native_duckdb_library *library = value;
  if (library->dynamic_library != NULL) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  free(library->error);
  library->error = NULL;
}

static void actql_native_duckdb_database_close(
  actql_native_duckdb_database *database
) {
  database->accepting = false;
  if (database->active_queries != 0) return;
  if (!database->opened) return;
  if (database->transaction_open) {
    duckdb_result result;
    memset(&result, 0, sizeof(result));
    if (database->library->query(
          database->connection, "ROLLBACK", &result
        ) == DuckDBSuccess) {
      database->transaction_open = false;
    }
    database->library->destroy_result(&result);
  }
  database->library->disconnect(&database->connection);
  database->library->close(&database->database);
  database->opened = false;
}

static void actql_native_duckdb_database_finalize(void *value) {
  actql_native_duckdb_database *database = value;
  actql_native_duckdb_database_close(database);
  free(database->error);
  database->error = NULL;
  moonbit_decref(database->library);
  database->library = NULL;
}

static bool actql_native_duckdb_stream_query_close_internal(
  actql_native_duckdb_stream *query
) {
  bool was_open = query->opened;
  bool had_resources = query->chunk != NULL ||
    query->result_created ||
    query->statement != NULL;
  if (!was_open && !had_resources) return false;
  if (query->chunk != NULL) {
    query->database->library->destroy_data_chunk(&query->chunk);
    query->chunk = NULL;
  }
  if (query->result_created) {
    query->database->library->destroy_result(&query->result);
    query->result_created = false;
  }
  if (query->statement != NULL) {
    query->database->library->destroy_prepare(&query->statement);
    query->statement = NULL;
  }
  query->opened = false;
  if (was_open) query->status = 3;
  if (was_open && query->database->active_queries > 0) {
    query->database->active_queries--;
  }
  if (!query->database->accepting) {
    actql_native_duckdb_database_close(query->database);
  }
  return true;
}

static void actql_native_duckdb_stream_query_finalize(void *value) {
  actql_native_duckdb_stream *query = value;
  actql_native_duckdb_stream_query_close_internal(query);
  free(query->types);
  free(query->storage_types);
  free(query->decimal_widths);
  free(query->decimal_scales);
  free(query->fields_json);
  free(query->error);
  query->types = NULL;
  query->storage_types = NULL;
  query->decimal_widths = NULL;
  query->decimal_scales = NULL;
  query->fields_json = NULL;
  query->error = NULL;
  moonbit_decref(query->database);
  query->database = NULL;
}

static bool actql_load_symbol(
  actql_native_duckdb_library *library,
  void **target,
  const char *name
) {
  dlerror();
  *target = dlsym(library->dynamic_library, name);
  const char *error = dlerror();
  if (error == NULL && *target != NULL) return true;
  actql_replace_error(&library->error, error == NULL ? name : error);
  return false;
}

#define ACTQL_LOAD(library, field, symbol) \
  actql_load_symbol((library), (void **)&((library)->field), (symbol))

void *actql_native_duckdb_load_library(
  moonbit_bytes_t path,
  int32_t length
) {
  actql_native_duckdb_library *library = moonbit_make_external_object(
    actql_native_duckdb_library_finalize,
    sizeof(actql_native_duckdb_library)
  );
  memset(library, 0, sizeof(*library));
  char *path_text = actql_copy_text(path, length);
  if (path_text == NULL) {
    actql_replace_error(&library->error, "DuckDB library path allocation failed");
    return library;
  }
  library->dynamic_library = dlopen(path_text, RTLD_NOW | RTLD_LOCAL);
  free(path_text);
  if (library->dynamic_library == NULL) {
    actql_replace_error(&library->error, dlerror());
    return library;
  }
  if (!ACTQL_LOAD(library, library_version, "duckdb_library_version") ||
      !ACTQL_LOAD(library, open, "duckdb_open") ||
      !ACTQL_LOAD(library, close, "duckdb_close") ||
      !ACTQL_LOAD(library, connect, "duckdb_connect") ||
      !ACTQL_LOAD(library, disconnect, "duckdb_disconnect") ||
      !ACTQL_LOAD(library, query, "duckdb_query") ||
      !ACTQL_LOAD(library, prepare, "duckdb_prepare") ||
      !ACTQL_LOAD(library, destroy_prepare, "duckdb_destroy_prepare") ||
      !ACTQL_LOAD(library, prepare_error, "duckdb_prepare_error") ||
      !ACTQL_LOAD(library, nparams, "duckdb_nparams") ||
      !ACTQL_LOAD(library, bind_null, "duckdb_bind_null") ||
      !ACTQL_LOAD(library, bind_boolean, "duckdb_bind_boolean") ||
      !ACTQL_LOAD(library, bind_double, "duckdb_bind_double") ||
      !ACTQL_LOAD(
        library, bind_varchar_length, "duckdb_bind_varchar_length"
      ) ||
      !ACTQL_LOAD(library, bind_date, "duckdb_bind_date") ||
      !ACTQL_LOAD(
        library, bind_timestamp_tz, "duckdb_bind_timestamp_tz"
      ) ||
      !ACTQL_LOAD(library, bind_decimal, "duckdb_bind_decimal") ||
      !ACTQL_LOAD(
        library,
        execute_prepared_streaming,
        "duckdb_execute_prepared_streaming"
      ) ||
      !ACTQL_LOAD(library, destroy_result, "duckdb_destroy_result") ||
      !ACTQL_LOAD(library, result_error, "duckdb_result_error") ||
      !ACTQL_LOAD(library, row_count, "duckdb_row_count") ||
      !ACTQL_LOAD(library, column_count, "duckdb_column_count") ||
      !ACTQL_LOAD(library, column_name, "duckdb_column_name") ||
      !ACTQL_LOAD(library, column_type, "duckdb_column_type") ||
      !ACTQL_LOAD(
        library, column_logical_type, "duckdb_column_logical_type"
      ) ||
      !ACTQL_LOAD(library, decimal_width, "duckdb_decimal_width") ||
      !ACTQL_LOAD(library, decimal_scale, "duckdb_decimal_scale") ||
      !ACTQL_LOAD(
        library, decimal_internal_type, "duckdb_decimal_internal_type"
      ) ||
      !ACTQL_LOAD(
        library, destroy_logical_type, "duckdb_destroy_logical_type"
      ) ||
      !ACTQL_LOAD(library, fetch_chunk, "duckdb_fetch_chunk") ||
      !ACTQL_LOAD(
        library, destroy_data_chunk, "duckdb_destroy_data_chunk"
      ) ||
      !ACTQL_LOAD(
        library,
        data_chunk_get_column_count,
        "duckdb_data_chunk_get_column_count"
      ) ||
      !ACTQL_LOAD(
        library, data_chunk_get_vector, "duckdb_data_chunk_get_vector"
      ) ||
      !ACTQL_LOAD(
        library, data_chunk_get_size, "duckdb_data_chunk_get_size"
      ) ||
      !ACTQL_LOAD(library, vector_get_data, "duckdb_vector_get_data") ||
      !ACTQL_LOAD(
        library, vector_get_validity, "duckdb_vector_get_validity"
      ) ||
      !ACTQL_LOAD(
        library, validity_row_is_valid, "duckdb_validity_row_is_valid"
      ) ||
      !ACTQL_LOAD(library, string_t_length, "duckdb_string_t_length") ||
      !ACTQL_LOAD(library, string_t_data, "duckdb_string_t_data") ||
      !ACTQL_LOAD(library, value_is_null, "duckdb_value_is_null") ||
      !ACTQL_LOAD(library, value_int64, "duckdb_value_int64")) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  return library;
}

int32_t actql_native_duckdb_library_ready(
  actql_native_duckdb_library *library
) {
  return library->dynamic_library != NULL;
}

moonbit_bytes_t actql_native_duckdb_library_error(
  actql_native_duckdb_library *library
) {
  return actql_copy_bytes(library->error);
}

moonbit_bytes_t actql_native_duckdb_library_version(
  actql_native_duckdb_library *library
) {
  if (library->dynamic_library == NULL) return actql_copy_bytes("");
  return actql_copy_bytes(library->library_version());
}

void *actql_native_duckdb_open_database(
  actql_native_duckdb_library *library,
  moonbit_bytes_t path,
  int32_t length
) {
  actql_native_duckdb_database *database = moonbit_make_external_object(
    actql_native_duckdb_database_finalize,
    sizeof(actql_native_duckdb_database)
  );
  memset(database, 0, sizeof(*database));
  database->library = library;
  moonbit_incref(library);
  if (library->dynamic_library == NULL) {
    actql_replace_error(&database->error, "DuckDB library is unavailable");
    return database;
  }
  char *path_text = actql_copy_text(path, length);
  if (path_text == NULL) {
    actql_replace_error(&database->error, "Database path allocation failed");
    return database;
  }
  const char *database_path = length == 0 ? NULL : path_text;
  if (library->open(database_path, &database->database) != DuckDBSuccess) {
    actql_replace_error(&database->error, "DuckDB database open failed");
    free(path_text);
    return database;
  }
  free(path_text);
  if (library->connect(database->database, &database->connection) !=
      DuckDBSuccess) {
    library->close(&database->database);
    actql_replace_error(&database->error, "DuckDB connection failed");
    return database;
  }
  database->opened = true;
  database->accepting = true;
  return database;
}

int32_t actql_native_duckdb_database_ready(
  actql_native_duckdb_database *database
) {
  return database->opened && database->accepting;
}

moonbit_bytes_t actql_native_duckdb_database_error(
  actql_native_duckdb_database *database
) {
  return actql_copy_bytes(database->error);
}

int64_t actql_native_duckdb_query_i64(
  actql_native_duckdb_database *database,
  moonbit_bytes_t sql,
  int32_t length
) {
  database->query_ok = false;
  actql_replace_error(&database->error, NULL);
  if (!database->opened || !database->accepting) {
    actql_replace_error(&database->error, "DuckDB database is closed");
    return 0;
  }
  char *sql_text = actql_copy_text(sql, length);
  if (sql_text == NULL) {
    actql_replace_error(&database->error, "SQL allocation failed");
    return 0;
  }
  duckdb_result result;
  duckdb_state state = database->library->query(
    database->connection,
    sql_text,
    &result
  );
  free(sql_text);
  if (state != DuckDBSuccess) {
    actql_replace_error(
      &database->error,
      database->library->result_error(&result)
    );
    database->library->destroy_result(&result);
    return 0;
  }
  if (database->library->row_count(&result) != 1 ||
      database->library->column_count(&result) != 1 ||
      database->library->value_is_null(&result, 0, 0)) {
    database->library->destroy_result(&result);
    actql_replace_error(
      &database->error,
      "DuckDB scalar query did not return one non-null cell"
    );
    return 0;
  }
  int64_t value = database->library->value_int64(&result, 0, 0);
  database->library->destroy_result(&result);
  database->query_ok = true;
  return value;
}

int32_t actql_native_duckdb_transaction(
  actql_native_duckdb_database *database,
  int32_t action
) {
  database->query_ok = false;
  actql_replace_error(&database->error, NULL);
  if (!database->opened || !database->accepting ||
      database->active_queries != 0) {
    actql_replace_error(&database->error, "DuckDB database is busy or closed");
    return false;
  }
  const char *sql = NULL;
  if (action == 0 && !database->transaction_open) {
    sql = "BEGIN TRANSACTION";
  } else if (action == 1 && database->transaction_open) {
    sql = "COMMIT";
  } else if (action == 2 && database->transaction_open) {
    sql = "ROLLBACK";
  } else {
    actql_replace_error(&database->error, "Invalid DuckDB transaction state");
    return false;
  }
  duckdb_result result;
  memset(&result, 0, sizeof(result));
  duckdb_state state = database->library->query(
    database->connection, sql, &result
  );
  if (state != DuckDBSuccess) {
    actql_replace_error(
      &database->error,
      database->library->result_error(&result)
    );
    database->library->destroy_result(&result);
    return false;
  }
  database->library->destroy_result(&result);
  database->transaction_open = action == 0;
  database->query_ok = true;
  return true;
}

static bool actql_text_quoted_i64(
  actql_bounded_text *text,
  int64_t value
) {
  return actql_text_literal(text, "\"") &&
    actql_text_i64(text, value) &&
    actql_text_literal(text, "\"");
}

static bool actql_text_quoted_u64(
  actql_bounded_text *text,
  uint64_t value
) {
  return actql_text_literal(text, "\"") &&
    actql_text_u64(text, value) &&
    actql_text_literal(text, "\"");
}

static bool actql_text_quoted_hugeint(
  actql_bounded_text *text,
  duckdb_hugeint value
) {
  char digits[41];
  size_t length = actql_i128_decimal(value, digits);
  return actql_text_literal(text, "\"") &&
    actql_text_bytes(text, digits, length) &&
    actql_text_literal(text, "\"");
}

static bool actql_text_quoted_uhugeint(
  actql_bounded_text *text,
  duckdb_uhugeint value
) {
  char digits[40];
  size_t length = actql_u128_decimal(value.upper, value.lower, digits);
  return actql_text_literal(text, "\"") &&
    actql_text_bytes(text, digits, length) &&
    actql_text_literal(text, "\"");
}

static bool actql_stream_cell(
  actql_native_duckdb_stream *query,
  actql_bounded_text *text,
  idx_t column,
  idx_t row
) {
  actql_native_duckdb_library *library = query->database->library;
  duckdb_vector vector = library->data_chunk_get_vector(query->chunk, column);
  uint64_t *validity = library->vector_get_validity(vector);
  if (validity != NULL && !library->validity_row_is_valid(validity, row)) {
    return actql_text_literal(text, "null");
  }
  void *data = library->vector_get_data(vector);
  switch (query->types[column]) {
    case DUCKDB_TYPE_BOOLEAN:
      return actql_text_literal(text, ((bool *)data)[row] ? "true" : "false");
    case DUCKDB_TYPE_TINYINT:
      return actql_text_quoted_i64(text, ((int8_t *)data)[row]);
    case DUCKDB_TYPE_SMALLINT:
      return actql_text_quoted_i64(text, ((int16_t *)data)[row]);
    case DUCKDB_TYPE_INTEGER:
      return actql_text_quoted_i64(text, ((int32_t *)data)[row]);
    case DUCKDB_TYPE_BIGINT:
      return actql_text_quoted_i64(text, ((int64_t *)data)[row]);
    case DUCKDB_TYPE_UTINYINT:
      return actql_text_quoted_u64(text, ((uint8_t *)data)[row]);
    case DUCKDB_TYPE_USMALLINT:
      return actql_text_quoted_u64(text, ((uint16_t *)data)[row]);
    case DUCKDB_TYPE_UINTEGER:
      return actql_text_quoted_u64(text, ((uint32_t *)data)[row]);
    case DUCKDB_TYPE_UBIGINT:
      return actql_text_quoted_u64(text, ((uint64_t *)data)[row]);
    case DUCKDB_TYPE_HUGEINT:
      return actql_text_quoted_hugeint(text, ((duckdb_hugeint *)data)[row]);
    case DUCKDB_TYPE_UHUGEINT:
      return actql_text_quoted_uhugeint(text, ((duckdb_uhugeint *)data)[row]);
    case DUCKDB_TYPE_FLOAT: {
      uint32_t bits;
      memcpy(&bits, &((float *)data)[row], sizeof(bits));
      char value[9];
      snprintf(value, sizeof(value), "%08x", bits);
      return actql_text_json_string(text, value, 8);
    }
    case DUCKDB_TYPE_DOUBLE: {
      uint64_t bits;
      memcpy(&bits, &((double *)data)[row], sizeof(bits));
      char value[17];
      snprintf(value, sizeof(value), "%016llx", (unsigned long long)bits);
      return actql_text_json_string(text, value, 16);
    }
    case DUCKDB_TYPE_VARCHAR: {
      duckdb_string_t *value = &((duckdb_string_t *)data)[row];
      uint32_t length = library->string_t_length(*value);
      const char *bytes = library->string_t_data(value);
      return actql_text_json_string(text, bytes, length);
    }
    case DUCKDB_TYPE_DATE:
      return actql_text_quoted_i64(text, ((duckdb_date *)data)[row].days);
    case DUCKDB_TYPE_TIMESTAMP:
    case DUCKDB_TYPE_TIMESTAMP_TZ:
      return actql_text_quoted_i64(
        text, ((duckdb_timestamp *)data)[row].micros
      );
    case DUCKDB_TYPE_TIMESTAMP_S:
      return actql_text_quoted_i64(
        text, ((duckdb_timestamp_s *)data)[row].seconds
      );
    case DUCKDB_TYPE_TIMESTAMP_MS:
      return actql_text_quoted_i64(
        text, ((duckdb_timestamp_ms *)data)[row].millis
      );
    case DUCKDB_TYPE_TIMESTAMP_NS:
      return actql_text_quoted_i64(
        text, ((duckdb_timestamp_ns *)data)[row].nanos
      );
    case DUCKDB_TYPE_DECIMAL:
      switch (query->storage_types[column]) {
        case DUCKDB_TYPE_SMALLINT:
          return actql_text_quoted_i64(text, ((int16_t *)data)[row]);
        case DUCKDB_TYPE_INTEGER:
          return actql_text_quoted_i64(text, ((int32_t *)data)[row]);
        case DUCKDB_TYPE_BIGINT:
          return actql_text_quoted_i64(text, ((int64_t *)data)[row]);
        case DUCKDB_TYPE_HUGEINT:
          return actql_text_quoted_hugeint(
            text, ((duckdb_hugeint *)data)[row]
          );
        default:
          return false;
      }
    default:
      return false;
  }
}

static bool actql_stream_fields(
  actql_native_duckdb_stream *query,
  size_t maximum
) {
  actql_bounded_text text;
  actql_text_init(&text, maximum);
  if (!actql_text_literal(&text, "[")) goto failed;
  for (idx_t column = 0; column < query->column_count; column++) {
    const char *name = query->database->library->column_name(
      &query->result, column
    );
    const char *type = actql_type_name(query->types[column]);
    if (name == NULL || type == NULL ||
        (column > 0 && !actql_text_literal(&text, ",")) ||
        !actql_text_literal(&text, "[") ||
        !actql_text_json_string(&text, name, strlen(name)) ||
        !actql_text_literal(&text, ",") ||
        !actql_text_json_string(&text, type, strlen(type)) ||
        !actql_text_literal(&text, ",")) {
      goto failed;
    }
    if (query->types[column] == DUCKDB_TYPE_DECIMAL) {
      if (!actql_text_quoted_i64(&text, query->decimal_widths[column])) {
        goto failed;
      }
    } else if (!actql_text_literal(&text, "null")) {
      goto failed;
    }
    if (!actql_text_literal(&text, ",")) goto failed;
    if (query->types[column] == DUCKDB_TYPE_DECIMAL) {
      if (!actql_text_quoted_i64(&text, query->decimal_scales[column])) {
        goto failed;
      }
    } else if (!actql_text_literal(&text, "null")) {
      goto failed;
    }
    if (!actql_text_literal(&text, "]")) goto failed;
  }
  if (!actql_text_literal(&text, "]")) goto failed;
  query->fields_json = text.data;
  return true;
failed:
  free(text.data);
  return false;
}

static void actql_stream_fail(
  actql_native_duckdb_stream *query,
  int32_t status,
  const char *message
) {
  query->status = status;
  actql_replace_error(&query->error, message);
}

static actql_native_duckdb_stream *actql_native_duckdb_prepare_stream(
  actql_native_duckdb_database *database,
  moonbit_bytes_t sql,
  int32_t length,
  int32_t max_columns,
  int64_t max_rows,
  int32_t max_chunk_rows,
  int32_t max_chunk_bytes
) {
  actql_native_duckdb_stream *query = moonbit_make_external_object(
    actql_native_duckdb_stream_query_finalize,
    sizeof(actql_native_duckdb_stream)
  );
  memset(query, 0, sizeof(*query));
  query->database = database;
  moonbit_incref(database);
  query->status = 4;
  if (!database->opened || !database->accepting) {
    actql_stream_fail(query, 3, "DuckDB database is closed");
    return query;
  }
  if (length < 1 || max_columns < 0 || max_rows < 0 ||
      max_chunk_rows < 1 || max_chunk_bytes < 1) {
    actql_stream_fail(query, 4, "Invalid DuckDB stream limits");
    return query;
  }
  char *sql_text = actql_copy_text(sql, length);
  if (sql_text == NULL) {
    actql_stream_fail(query, 4, "SQL allocation failed");
    return query;
  }
  duckdb_state state = database->library->prepare(
    database->connection, sql_text, &query->statement
  );
  free(sql_text);
  if (state != DuckDBSuccess) {
    actql_stream_fail(
      query, 4, database->library->prepare_error(query->statement)
    );
    return query;
  }
  query->parameter_count = database->library->nparams(query->statement);
  query->max_columns = max_columns;
  query->max_rows = max_rows;
  query->max_chunk_rows = max_chunk_rows;
  query->max_chunk_bytes = max_chunk_bytes;
  query->opened = true;
  query->status = 0;
  database->active_queries++;
  return query;
}

static bool actql_native_duckdb_execute_stream(
  actql_native_duckdb_stream *query
) {
  if (!query->opened || !query->database->accepting) {
    actql_stream_fail(query, 3, "DuckDB stream is closed");
    return false;
  }
  if (query->executed) {
    actql_stream_fail(query, 4, "DuckDB stream is not ready to execute");
    return false;
  }
  if (query->bound_parameters != query->parameter_count) {
    actql_stream_fail(query, 4, "DuckDB stream parameters are incomplete");
    return false;
  }
  actql_native_duckdb_library *library = query->database->library;
  duckdb_state state = library->execute_prepared_streaming(
    query->statement, &query->result
  );
  query->result_created = true;
  if (state != DuckDBSuccess) {
    actql_stream_fail(
      query, 4, library->result_error(&query->result)
    );
    return false;
  }
  query->column_count = library->column_count(&query->result);
  if (query->column_count > (idx_t)query->max_columns) {
    actql_stream_fail(query, 2, "DuckDB column limit exceeded");
    return false;
  }
  size_t count = (size_t)query->column_count;
  query->types = calloc(count == 0 ? 1 : count, sizeof(duckdb_type));
  query->storage_types = calloc(count == 0 ? 1 : count, sizeof(duckdb_type));
  query->decimal_widths = calloc(count == 0 ? 1 : count, sizeof(uint8_t));
  query->decimal_scales = calloc(count == 0 ? 1 : count, sizeof(uint8_t));
  if (query->types == NULL || query->storage_types == NULL ||
      query->decimal_widths == NULL || query->decimal_scales == NULL) {
    actql_stream_fail(query, 2, "DuckDB metadata allocation failed");
    return false;
  }
  for (idx_t column = 0; column < query->column_count; column++) {
    duckdb_type type = library->column_type(&query->result, column);
    if (actql_type_name(type) == NULL) {
      actql_stream_fail(query, 4, "Unsupported DuckDB physical type");
      return false;
    }
    query->types[column] = type;
    query->storage_types[column] = type;
    if (type == DUCKDB_TYPE_DECIMAL) {
      duckdb_logical_type logical = library->column_logical_type(
        &query->result, column
      );
      if (logical == NULL) {
        actql_stream_fail(query, 4, "DuckDB decimal metadata unavailable");
        return false;
      }
      query->decimal_widths[column] = library->decimal_width(logical);
      query->decimal_scales[column] = library->decimal_scale(logical);
      query->storage_types[column] =
        library->decimal_internal_type(logical);
      library->destroy_logical_type(&logical);
    }
  }
  if (!actql_stream_fields(query, (size_t)query->max_chunk_bytes)) {
    actql_stream_fail(query, 2, "DuckDB metadata byte limit exceeded");
    return false;
  }
  query->executed = true;
  query->status = 0;
  return true;
}

void *actql_native_duckdb_prepare_stream_query(
  actql_native_duckdb_database *database,
  moonbit_bytes_t sql,
  int32_t length,
  int32_t max_columns,
  int64_t max_rows,
  int32_t max_chunk_rows,
  int32_t max_chunk_bytes
) {
  return actql_native_duckdb_prepare_stream(
    database,
    sql,
    length,
    max_columns,
    max_rows,
    max_chunk_rows,
    max_chunk_bytes
  );
}

static bool actql_native_duckdb_stream_bindable(
  actql_native_duckdb_stream *query,
  int32_t index
) {
  if (!query->opened || query->executed ||
      !query->database->accepting) {
    actql_stream_fail(query, 3, "DuckDB stream is closed");
    return false;
  }
  if (index < 0 || (idx_t)index != query->bound_parameters ||
      (idx_t)index >= query->parameter_count) {
    actql_stream_fail(query, 4, "DuckDB parameter binding is out of order");
    return false;
  }
  return true;
}

static bool actql_native_duckdb_stream_bound(
  actql_native_duckdb_stream *query,
  duckdb_state state
) {
  if (state != DuckDBSuccess) {
    actql_stream_fail(
      query, 4, query->database->library->prepare_error(query->statement)
    );
    return false;
  }
  query->bound_parameters++;
  return true;
}

int64_t actql_native_duckdb_stream_query_parameter_count(
  actql_native_duckdb_stream *query
) {
  return query->opened ? (int64_t)query->parameter_count : -1;
}

int32_t actql_native_duckdb_stream_query_bind_null(
  actql_native_duckdb_stream *query,
  int32_t index
) {
  if (!actql_native_duckdb_stream_bindable(query, index)) return false;
  return actql_native_duckdb_stream_bound(
    query,
    query->database->library->bind_null(query->statement, (idx_t)index + 1)
  );
}

int32_t actql_native_duckdb_stream_query_bind_boolean(
  actql_native_duckdb_stream *query,
  int32_t index,
  int32_t value
) {
  if (!actql_native_duckdb_stream_bindable(query, index)) return false;
  return actql_native_duckdb_stream_bound(
    query,
    query->database->library->bind_boolean(
      query->statement, (idx_t)index + 1, value != 0
    )
  );
}

int32_t actql_native_duckdb_stream_query_bind_double(
  actql_native_duckdb_stream *query,
  int32_t index,
  double value
) {
  if (!actql_native_duckdb_stream_bindable(query, index)) return false;
  return actql_native_duckdb_stream_bound(
    query,
    query->database->library->bind_double(
      query->statement, (idx_t)index + 1, value
    )
  );
}

int32_t actql_native_duckdb_stream_query_bind_text(
  actql_native_duckdb_stream *query,
  int32_t index,
  moonbit_bytes_t value,
  int32_t length
) {
  if (!actql_native_duckdb_stream_bindable(query, index)) return false;
  if (length < 0) {
    actql_stream_fail(query, 4, "DuckDB text parameter length is invalid");
    return false;
  }
  return actql_native_duckdb_stream_bound(
    query,
    query->database->library->bind_varchar_length(
      query->statement,
      (idx_t)index + 1,
      (const char *)value,
      (idx_t)length
    )
  );
}

int32_t actql_native_duckdb_stream_query_bind_date(
  actql_native_duckdb_stream *query,
  int32_t index,
  int32_t days
) {
  if (!actql_native_duckdb_stream_bindable(query, index)) return false;
  duckdb_date value = {.days = days};
  return actql_native_duckdb_stream_bound(
    query,
    query->database->library->bind_date(
      query->statement, (idx_t)index + 1, value
    )
  );
}

int32_t actql_native_duckdb_stream_query_bind_timestamp(
  actql_native_duckdb_stream *query,
  int32_t index,
  int64_t micros
) {
  if (!actql_native_duckdb_stream_bindable(query, index)) return false;
  duckdb_timestamp value = {.micros = micros};
  return actql_native_duckdb_stream_bound(
    query,
    query->database->library->bind_timestamp_tz(
      query->statement, (idx_t)index + 1, value
    )
  );
}

static bool actql_native_duckdb_decimal(
  moonbit_bytes_t coefficient,
  int32_t length,
  int32_t width,
  int32_t scale,
  duckdb_decimal *output
) {
  if (length < 1 || length > 39 || width < 1 || width > 38 ||
      scale < 0 || scale > width) {
    return false;
  }
  int32_t offset = coefficient[0] == '-' ? 1 : 0;
  bool negative = offset == 1;
  if (offset == length) return false;
  int32_t significant = 0;
  bool nonzero = false;
  unsigned __int128 magnitude = 0;
  const unsigned __int128 maximum =
    (((unsigned __int128)1 << 127) - 1);
  for (int32_t index = offset; index < length; index++) {
    uint8_t byte = coefficient[index];
    if (byte < '0' || byte > '9') return false;
    if (byte != '0' || nonzero) {
      nonzero = true;
      significant++;
    }
    uint8_t digit = byte - '0';
    if (magnitude > (maximum - digit) / 10) return false;
    magnitude = magnitude * 10 + digit;
  }
  if (!nonzero) significant = 1;
  if (significant > width) return false;
  unsigned __int128 encoded = negative && magnitude != 0
    ? (~magnitude) + 1
    : magnitude;
  output->width = (uint8_t)width;
  output->scale = (uint8_t)scale;
  output->value.lower = (uint64_t)encoded;
  output->value.upper = (int64_t)(encoded >> 64);
  return true;
}

int32_t actql_native_duckdb_stream_query_bind_decimal(
  actql_native_duckdb_stream *query,
  int32_t index,
  moonbit_bytes_t coefficient,
  int32_t length,
  int32_t width,
  int32_t scale
) {
  if (!actql_native_duckdb_stream_bindable(query, index)) return false;
  duckdb_decimal value;
  if (!actql_native_duckdb_decimal(
        coefficient, length, width, scale, &value
      )) {
    actql_stream_fail(query, 4, "DuckDB decimal parameter is invalid");
    return false;
  }
  return actql_native_duckdb_stream_bound(
    query,
    query->database->library->bind_decimal(
      query->statement, (idx_t)index + 1, value
    )
  );
}

int32_t actql_native_duckdb_stream_query_execute(
  actql_native_duckdb_stream *query
) {
  return actql_native_duckdb_execute_stream(query);
}

int32_t actql_native_duckdb_stream_query_ready(
  actql_native_duckdb_stream *query
) {
  return query->opened;
}

int32_t actql_native_duckdb_stream_query_executed(
  actql_native_duckdb_stream *query
) {
  return query->opened && query->executed;
}

moonbit_bytes_t actql_native_duckdb_stream_query_error(
  actql_native_duckdb_stream *query
) {
  return actql_copy_bytes(query->error);
}

moonbit_bytes_t actql_native_duckdb_stream_query_fields(
  actql_native_duckdb_stream *query
) {
  return actql_copy_bytes(query->fields_json);
}

moonbit_bytes_t actql_native_duckdb_stream_query_next(
  actql_native_duckdb_stream *query
) {
  query->last_rows = 0;
  if (!query->opened) {
    if (query->status != 2 && query->status != 4) query->status = 3;
    return actql_copy_bytes("");
  }
  if (!query->database->accepting) {
    actql_stream_fail(query, 3, "DuckDB database is closed");
    return actql_copy_bytes("");
  }
  if (query->status != 0) {
    return actql_copy_bytes("");
  }
  actql_native_duckdb_library *library = query->database->library;
  while (query->chunk == NULL) {
    query->chunk = library->fetch_chunk(query->result);
    query->chunk_offset = 0;
    if (query->chunk == NULL) {
      const char *error = library->result_error(&query->result);
      if (error != NULL && error[0] != '\0') {
        actql_stream_fail(query, 4, error);
      } else {
        query->status = 1;
      }
      return actql_copy_bytes("");
    }
    if (library->data_chunk_get_column_count(query->chunk) !=
        query->column_count) {
      actql_stream_fail(query, 4, "DuckDB chunk shape changed");
      return actql_copy_bytes("");
    }
    if (library->data_chunk_get_size(query->chunk) == 0) {
      library->destroy_data_chunk(&query->chunk);
      query->chunk = NULL;
    }
  }
  idx_t size = library->data_chunk_get_size(query->chunk);
  idx_t available = size - query->chunk_offset;
  idx_t rows = available < (idx_t)query->max_chunk_rows
    ? available
    : (idx_t)query->max_chunk_rows;
  if ((int64_t)rows > query->max_rows - query->rows) {
    actql_stream_fail(query, 2, "DuckDB row limit exceeded");
    return actql_copy_bytes("");
  }
  actql_bounded_text text;
  actql_text_init(&text, (size_t)query->max_chunk_bytes);
  if (!actql_text_literal(&text, "[")) goto capacity;
  for (idx_t column = 0; column < query->column_count; column++) {
    if ((column > 0 && !actql_text_literal(&text, ",")) ||
        !actql_text_literal(&text, "[")) {
      goto capacity;
    }
    for (idx_t offset = 0; offset < rows; offset++) {
      if ((offset > 0 && !actql_text_literal(&text, ",")) ||
          !actql_stream_cell(
            query, &text, column, query->chunk_offset + offset
          )) {
        goto capacity;
      }
    }
    if (!actql_text_literal(&text, "]")) goto capacity;
  }
  if (!actql_text_literal(&text, "]")) goto capacity;
  query->chunk_offset += rows;
  query->rows += (int64_t)rows;
  query->last_rows = (int32_t)rows;
  query->status = 0;
  if (query->chunk_offset == size) {
    library->destroy_data_chunk(&query->chunk);
    query->chunk = NULL;
    query->chunk_offset = 0;
  }
  moonbit_bytes_t output = moonbit_make_bytes_raw((int32_t)text.length);
  if (text.length > 0) memcpy(output, text.data, text.length);
  free(text.data);
  return output;
capacity:
  free(text.data);
  actql_stream_fail(query, 2, "DuckDB chunk byte limit exceeded");
  return actql_copy_bytes("");
}

int32_t actql_native_duckdb_stream_query_status(
  actql_native_duckdb_stream *query
) {
  return query->status;
}

int32_t actql_native_duckdb_stream_query_last_rows(
  actql_native_duckdb_stream *query
) {
  return query->last_rows;
}

int32_t actql_native_duckdb_close_stream_query(
  actql_native_duckdb_stream *query
) {
  return actql_native_duckdb_stream_query_close_internal(query);
}

int32_t actql_native_duckdb_query_ok(
  actql_native_duckdb_database *database
) {
  return database->query_ok;
}

void actql_native_duckdb_close_database(
  actql_native_duckdb_database *database
) {
  actql_native_duckdb_database_close(database);
}
