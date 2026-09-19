#include "moonbit.h"
#include "../../../vendor/duckdb/1.4.3/duckdb.h"

#include <dlfcn.h>
#include <stdbool.h>
#include <stdint.h>
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
typedef void (*actql_duckdb_destroy_result_fn)(duckdb_result *);
typedef const char *(*actql_duckdb_result_error_fn)(duckdb_result *);
typedef idx_t (*actql_duckdb_row_count_fn)(duckdb_result *);
typedef idx_t (*actql_duckdb_column_count_fn)(duckdb_result *);
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
  actql_duckdb_destroy_result_fn destroy_result;
  actql_duckdb_result_error_fn result_error;
  actql_duckdb_row_count_fn row_count;
  actql_duckdb_column_count_fn column_count;
  actql_duckdb_value_is_null_fn value_is_null;
  actql_duckdb_value_int64_fn value_int64;
} actql_native_duckdb_library;

typedef struct {
  actql_native_duckdb_library *library;
  duckdb_database database;
  duckdb_connection connection;
  char *error;
  bool opened;
  bool query_ok;
} actql_native_duckdb_database;

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
  if (!database->opened) return;
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
      !ACTQL_LOAD(library, destroy_result, "duckdb_destroy_result") ||
      !ACTQL_LOAD(library, result_error, "duckdb_result_error") ||
      !ACTQL_LOAD(library, row_count, "duckdb_row_count") ||
      !ACTQL_LOAD(library, column_count, "duckdb_column_count") ||
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
  return database;
}

int32_t actql_native_duckdb_database_ready(
  actql_native_duckdb_database *database
) {
  return database->opened;
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
  if (!database->opened) {
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
