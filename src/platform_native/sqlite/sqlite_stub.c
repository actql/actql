#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"

#include <dlfcn.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

typedef const char *(*actql_sqlite_libversion_fn)(void);
typedef int (*actql_sqlite_libversion_number_fn)(void);
typedef int (*actql_sqlite_open_v2_fn)(
  const char *, sqlite3 **, int, const char *
);
typedef int (*actql_sqlite_close_v2_fn)(sqlite3 *);
typedef const char *(*actql_sqlite_errmsg_fn)(sqlite3 *);
typedef int (*actql_sqlite_exec_fn)(
  sqlite3 *, const char *, int (*)(void *, int, char **, char **),
  void *, char **
);
typedef void (*actql_sqlite_free_fn)(void *);
typedef int (*actql_sqlite_prepare_v2_fn)(
  sqlite3 *, const char *, int, sqlite3_stmt **, const char **
);
typedef int (*actql_sqlite_bind_text_fn)(
  sqlite3_stmt *, int, const char *, int, void (*)(void *)
);
typedef int (*actql_sqlite_bind_blob_fn)(
  sqlite3_stmt *, int, const void *, int, void (*)(void *)
);
typedef int (*actql_sqlite_bind_int64_fn)(sqlite3_stmt *, int, sqlite3_int64);
typedef int (*actql_sqlite_step_fn)(sqlite3_stmt *);
typedef sqlite3_int64 (*actql_sqlite_column_int64_fn)(sqlite3_stmt *, int);
typedef const void *(*actql_sqlite_column_blob_fn)(sqlite3_stmt *, int);
typedef int (*actql_sqlite_column_bytes_fn)(sqlite3_stmt *, int);
typedef int (*actql_sqlite_finalize_fn)(sqlite3_stmt *);
typedef sqlite3_int64 (*actql_sqlite_changes64_fn)(sqlite3 *);
typedef int (*actql_sqlite_busy_timeout_fn)(sqlite3 *, int);

typedef struct {
  void *dynamic_library;
  char *error;
  actql_sqlite_libversion_fn libversion;
  actql_sqlite_libversion_number_fn libversion_number;
  actql_sqlite_open_v2_fn open_v2;
  actql_sqlite_close_v2_fn close_v2;
  actql_sqlite_errmsg_fn errmsg;
  actql_sqlite_exec_fn exec;
  actql_sqlite_free_fn free_memory;
  actql_sqlite_prepare_v2_fn prepare_v2;
  actql_sqlite_bind_text_fn bind_text;
  actql_sqlite_bind_blob_fn bind_blob;
  actql_sqlite_bind_int64_fn bind_int64;
  actql_sqlite_step_fn step;
  actql_sqlite_column_int64_fn column_int64;
  actql_sqlite_column_blob_fn column_blob;
  actql_sqlite_column_bytes_fn column_bytes;
  actql_sqlite_finalize_fn finalize;
  actql_sqlite_changes64_fn changes64;
  actql_sqlite_busy_timeout_fn busy_timeout;
} actql_native_sqlite_library;

typedef struct {
  actql_native_sqlite_library *library;
  sqlite3 *database;
  char *error;
  unsigned char *result_body;
  int32_t result_body_length;
  unsigned char *result_key;
  int32_t result_key_length;
  int64_t result_revision;
  int64_t result_capacity_bytes;
  int64_t result_capacity_objects;
  int64_t max_body_bytes;
  bool opened;
} actql_native_sqlite_database;

static void actql_replace_error(char **target, const char *message) {
  free(*target);
  *target = NULL;
  if (message == NULL) return;
  size_t length = strlen(message);
  char *copy = malloc(length + 1);
  if (copy == NULL) return;
  memcpy(copy, message, length + 1);
  *target = copy;
}

static char *actql_copy_text(moonbit_bytes_t bytes, int32_t length) {
  if (length < 0) return NULL;
  char *text = malloc((size_t)length + 1);
  if (text == NULL) return NULL;
  if (length > 0) memcpy(text, bytes, (size_t)length);
  text[length] = '\0';
  return text;
}

static moonbit_bytes_t actql_copy_bytes(const void *source, int32_t length) {
  if (length < 0) length = 0;
  moonbit_bytes_t bytes = moonbit_make_bytes_raw(length);
  if (length > 0 && source != NULL) memcpy(bytes, source, (size_t)length);
  return bytes;
}

static moonbit_bytes_t actql_copy_message(const char *text) {
  size_t length = text == NULL ? 0 : strlen(text);
  if (length > INT32_MAX) length = INT32_MAX;
  return actql_copy_bytes(text, (int32_t)length);
}

static void actql_clear_result(actql_native_sqlite_database *database) {
  free(database->result_body);
  free(database->result_key);
  database->result_body = NULL;
  database->result_key = NULL;
  database->result_body_length = 0;
  database->result_key_length = 0;
  database->result_revision = 0;
  database->result_capacity_bytes = 0;
  database->result_capacity_objects = 0;
  actql_replace_error(&database->error, NULL);
}

static void actql_database_error(
  actql_native_sqlite_database *database,
  const char *fallback
) {
  const char *message = fallback;
  if (database->database != NULL) {
    const char *sqlite_message = database->library->errmsg(database->database);
    if (sqlite_message != NULL) message = sqlite_message;
  }
  actql_replace_error(&database->error, message);
}

static int32_t actql_operation_code(int sqlite_code) {
  int primary = sqlite_code & 0xff;
  if (primary == SQLITE_BUSY || primary == SQLITE_LOCKED) return 3;
  return -1;
}

static void actql_native_sqlite_library_finalize(void *value) {
  actql_native_sqlite_library *library = value;
  if (library->dynamic_library != NULL) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  free(library->error);
  library->error = NULL;
}

static void actql_native_sqlite_database_close(
  actql_native_sqlite_database *database
) {
  if (!database->opened) return;
  database->library->close_v2(database->database);
  database->database = NULL;
  database->opened = false;
}

static void actql_native_sqlite_database_finalize(void *value) {
  actql_native_sqlite_database *database = value;
  actql_native_sqlite_database_close(database);
  free(database->error);
  free(database->result_body);
  free(database->result_key);
  database->error = NULL;
  database->result_body = NULL;
  database->result_key = NULL;
  if (database->library != NULL) {
    moonbit_decref(database->library);
    database->library = NULL;
  }
}

static bool actql_load_symbol(
  actql_native_sqlite_library *library,
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

static int actql_exec(
  actql_native_sqlite_database *database,
  const char *sql
) {
  char *message = NULL;
  int code = database->library->exec(
    database->database,
    sql,
    NULL,
    NULL,
    &message
  );
  if (code != SQLITE_OK) {
    actql_replace_error(
      &database->error,
      message == NULL ? "SQLite execution failed" : message
    );
  }
  if (message != NULL) database->library->free_memory(message);
  return code;
}

static int actql_user_version(actql_native_sqlite_database *database) {
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "PRAGMA user_version",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare user_version failed");
    return -1;
  }
  code = database->library->step(statement);
  int version = code == SQLITE_ROW
    ? (int)database->library->column_int64(statement, 0)
    : -1;
  int finalize_code = database->library->finalize(statement);
  if (code != SQLITE_ROW || finalize_code != SQLITE_OK) {
    actql_database_error(database, "read user_version failed");
    return -1;
  }
  return version;
}

static bool actql_initialize_schema(
  actql_native_sqlite_database *database
) {
  if (actql_exec(database, "PRAGMA journal_mode=WAL") != SQLITE_OK ||
      actql_exec(database, "PRAGMA synchronous=FULL") != SQLITE_OK ||
      actql_exec(database, "PRAGMA foreign_keys=ON") != SQLITE_OK) {
    return false;
  }
  int version = actql_user_version(database);
  if (version < 0) return false;
  if (version > 2) {
    actql_replace_error(&database->error, "unsupported SQLite schema version");
    return false;
  }
  const char *schema =
    "BEGIN IMMEDIATE;"
    "CREATE TABLE IF NOT EXISTS actql_records("
    "namespace TEXT NOT NULL,"
    "record_key TEXT NOT NULL,"
    "revision INTEGER NOT NULL CHECK(revision >= 0),"
    "body BLOB NOT NULL,"
    "PRIMARY KEY(namespace, record_key)"
    ") STRICT;"
    "CREATE TABLE IF NOT EXISTS actql_capacity("
    "namespace TEXT NOT NULL,"
    "reservation_key TEXT NOT NULL,"
    "reserved_bytes INTEGER NOT NULL CHECK(reserved_bytes >= 0),"
    "reserved_objects INTEGER NOT NULL CHECK(reserved_objects >= 0),"
    "PRIMARY KEY(namespace, reservation_key)"
    ") STRICT;"
    "PRAGMA user_version=2;"
    "COMMIT;";
  if (actql_exec(database, schema) != SQLITE_OK) {
    database->library->exec(database->database, "ROLLBACK", NULL, NULL, NULL);
    return false;
  }
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "SELECT revision, body FROM actql_records WHERE 0",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "validate SQLite schema failed");
    return false;
  }
  code = database->library->finalize(statement);
  if (code != SQLITE_OK) {
    actql_database_error(database, "finalize SQLite schema check failed");
    return false;
  }
  return true;
}

static int32_t actql_bind_key(
  actql_native_sqlite_database *database,
  sqlite3_stmt *statement,
  int namespace_index,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  int key_index,
  moonbit_bytes_t key,
  int32_t key_length
) {
  int code = database->library->bind_text(
    statement,
    namespace_index,
    (const char *)namespace_bytes,
    namespace_length,
    SQLITE_TRANSIENT
  );
  if (code == SQLITE_OK) {
    code = database->library->bind_text(
      statement,
      key_index,
      (const char *)key,
      key_length,
      SQLITE_TRANSIENT
    );
  }
  if (code == SQLITE_OK) return 0;
  actql_database_error(database, "bind journal key failed");
  return actql_operation_code(code);
}

void *actql_native_sqlite_load_library(
  moonbit_bytes_t path,
  int32_t length
) {
  actql_native_sqlite_library *library = moonbit_make_external_object(
    actql_native_sqlite_library_finalize,
    sizeof(actql_native_sqlite_library)
  );
  memset(library, 0, sizeof(*library));
  char *path_text = actql_copy_text(path, length);
  if (path_text == NULL) {
    actql_replace_error(&library->error, "SQLite library path allocation failed");
    return library;
  }
  library->dynamic_library = dlopen(path_text, RTLD_NOW | RTLD_LOCAL);
  free(path_text);
  if (library->dynamic_library == NULL) {
    actql_replace_error(&library->error, dlerror());
    return library;
  }
  if (!ACTQL_LOAD(library, libversion, "sqlite3_libversion") ||
      !ACTQL_LOAD(library, libversion_number, "sqlite3_libversion_number") ||
      !ACTQL_LOAD(library, open_v2, "sqlite3_open_v2") ||
      !ACTQL_LOAD(library, close_v2, "sqlite3_close_v2") ||
      !ACTQL_LOAD(library, errmsg, "sqlite3_errmsg") ||
      !ACTQL_LOAD(library, exec, "sqlite3_exec") ||
      !ACTQL_LOAD(library, free_memory, "sqlite3_free") ||
      !ACTQL_LOAD(library, prepare_v2, "sqlite3_prepare_v2") ||
      !ACTQL_LOAD(library, bind_text, "sqlite3_bind_text") ||
      !ACTQL_LOAD(library, bind_blob, "sqlite3_bind_blob") ||
      !ACTQL_LOAD(library, bind_int64, "sqlite3_bind_int64") ||
      !ACTQL_LOAD(library, step, "sqlite3_step") ||
      !ACTQL_LOAD(library, column_int64, "sqlite3_column_int64") ||
      !ACTQL_LOAD(library, column_blob, "sqlite3_column_blob") ||
      !ACTQL_LOAD(library, column_bytes, "sqlite3_column_bytes") ||
      !ACTQL_LOAD(library, finalize, "sqlite3_finalize") ||
      !ACTQL_LOAD(library, changes64, "sqlite3_changes64") ||
      !ACTQL_LOAD(library, busy_timeout, "sqlite3_busy_timeout")) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
    return library;
  }
  if (library->libversion_number() < 3037000) {
    actql_replace_error(&library->error, "SQLite 3.37.0 or later is required");
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  return library;
}

int32_t actql_native_sqlite_library_ready(
  actql_native_sqlite_library *library
) {
  return library != NULL && library->dynamic_library != NULL;
}

moonbit_bytes_t actql_native_sqlite_library_error(
  actql_native_sqlite_library *library
) {
  return actql_copy_message(
    library == NULL ? "invalid SQLite library" : library->error
  );
}

moonbit_bytes_t actql_native_sqlite_library_version(
  actql_native_sqlite_library *library
) {
  if (library == NULL || library->dynamic_library == NULL) {
    return actql_copy_message("");
  }
  return actql_copy_message(library->libversion());
}

void *actql_native_sqlite_open_database(
  actql_native_sqlite_library *library,
  moonbit_bytes_t path,
  int32_t length,
  int64_t max_body_bytes
) {
  actql_native_sqlite_database *database = moonbit_make_external_object(
    actql_native_sqlite_database_finalize,
    sizeof(actql_native_sqlite_database)
  );
  memset(database, 0, sizeof(*database));
  database->library = library;
  if (library != NULL) moonbit_incref(library);
  database->max_body_bytes = max_body_bytes;
  if (library == NULL || library->dynamic_library == NULL) {
    actql_replace_error(&database->error, "SQLite library is unavailable");
    return database;
  }
  char *path_text = actql_copy_text(path, length);
  if (path_text == NULL) {
    actql_replace_error(&database->error, "database path allocation failed");
    return database;
  }
  int code = library->open_v2(
    path_text,
    &database->database,
    SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
    NULL
  );
  free(path_text);
  if (code != SQLITE_OK) {
    actql_database_error(database, "open SQLite database failed");
    if (database->database != NULL) {
      library->close_v2(database->database);
      database->database = NULL;
    }
    return database;
  }
  code = library->busy_timeout(database->database, 5000);
  if (code != SQLITE_OK) {
    actql_database_error(database, "configure SQLite busy timeout failed");
    library->close_v2(database->database);
    database->database = NULL;
    return database;
  }
  if (!actql_initialize_schema(database)) {
    library->close_v2(database->database);
    database->database = NULL;
    return database;
  }
  database->opened = true;
  return database;
}

int32_t actql_native_sqlite_database_ready(
  actql_native_sqlite_database *database
) {
  return database != NULL && database->opened;
}

moonbit_bytes_t actql_native_sqlite_database_error(
  actql_native_sqlite_database *database
) {
  return actql_copy_message(
    database == NULL ? "invalid SQLite database" : database->error
  );
}

int32_t actql_native_sqlite_database_read(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length
) {
  if (database == NULL || !database->opened) return 5;
  actql_clear_result(database);
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "SELECT revision, body FROM actql_records "
    "WHERE namespace = ?1 AND record_key = ?2",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare journal read failed");
    return actql_operation_code(code);
  }
  int32_t result = actql_bind_key(
    database,
    statement,
    1,
    namespace_bytes,
    namespace_length,
    2,
    key,
    key_length
  );
  if (result == 0) {
    code = database->library->step(statement);
    if (code == SQLITE_DONE) {
      result = 1;
    } else if (code != SQLITE_ROW) {
      actql_database_error(database, "read journal record failed");
      result = actql_operation_code(code);
    } else {
      int length = database->library->column_bytes(statement, 1);
      const void *body = database->library->column_blob(statement, 1);
      sqlite3_int64 revision = database->library->column_int64(statement, 0);
      if (revision < 0 || length < 0 || length > database->max_body_bytes ||
          length > INT32_MAX) {
        actql_replace_error(&database->error, "invalid stored journal record");
        result = -1;
      } else {
        unsigned char *copy = length == 0 ? NULL : malloc((size_t)length);
        if (length > 0 && copy == NULL) {
          actql_replace_error(&database->error, "journal body allocation failed");
          result = -1;
        } else {
          if (length > 0) memcpy(copy, body, (size_t)length);
          database->result_body = copy;
          database->result_body_length = length;
          database->result_revision = (int64_t)revision;
        }
      }
    }
  }
  int finalize_code = database->library->finalize(statement);
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize journal read failed");
    return actql_operation_code(finalize_code);
  }
  return result;
}

int32_t actql_native_sqlite_database_scan_after(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t after_key,
  int32_t after_key_length
) {
  if (database == NULL || !database->opened) return 5;
  actql_clear_result(database);
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "SELECT record_key, revision, body FROM actql_records "
    "WHERE namespace = ?1 AND record_key > ?2 "
    "ORDER BY record_key COLLATE BINARY LIMIT 1",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare journal scan failed");
    return actql_operation_code(code);
  }
  int code_namespace = database->library->bind_text(
    statement,
    1,
    (const char *)namespace_bytes,
    namespace_length,
    SQLITE_TRANSIENT
  );
  int code_key = code_namespace == SQLITE_OK
    ? database->library->bind_text(
        statement,
        2,
        (const char *)after_key,
        after_key_length,
        SQLITE_TRANSIENT
      )
    : code_namespace;
  int32_t result = 0;
  if (code_key != SQLITE_OK) {
    actql_database_error(database, "bind journal scan cursor failed");
    result = actql_operation_code(code_key);
  }
  if (result == 0) {
    code = database->library->step(statement);
    if (code == SQLITE_DONE) {
      result = 1;
    } else if (code != SQLITE_ROW) {
      actql_database_error(database, "scan journal records failed");
      result = actql_operation_code(code);
    } else {
      int key_length = database->library->column_bytes(statement, 0);
      const void *key = database->library->column_blob(statement, 0);
      sqlite3_int64 revision = database->library->column_int64(statement, 1);
      int body_length = database->library->column_bytes(statement, 2);
      const void *body = database->library->column_blob(statement, 2);
      if (key_length <= 0 || key_length > 512 || revision < 0 ||
          body_length < 0 || body_length > database->max_body_bytes ||
          body_length > INT32_MAX) {
        actql_replace_error(&database->error, "invalid stored journal record");
        result = -1;
      } else {
        unsigned char *key_copy = malloc((size_t)key_length);
        unsigned char *body_copy = body_length == 0
          ? NULL
          : malloc((size_t)body_length);
        if (key_copy == NULL || (body_length > 0 && body_copy == NULL)) {
          free(key_copy);
          free(body_copy);
          actql_replace_error(&database->error, "journal scan allocation failed");
          result = -1;
        } else {
          memcpy(key_copy, key, (size_t)key_length);
          if (body_length > 0) {
            memcpy(body_copy, body, (size_t)body_length);
          }
          database->result_key = key_copy;
          database->result_key_length = key_length;
          database->result_body = body_copy;
          database->result_body_length = body_length;
          database->result_revision = (int64_t)revision;
        }
      }
    }
  }
  int finalize_code = database->library->finalize(statement);
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize journal scan failed");
    return actql_operation_code(finalize_code);
  }
  return result;
}

int32_t actql_native_sqlite_database_insert(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  moonbit_bytes_t body,
  int32_t body_length
) {
  if (database == NULL || !database->opened) return 5;
  actql_clear_result(database);
  if (body_length < 0 || (int64_t)body_length > database->max_body_bytes) {
    return 4;
  }
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "INSERT INTO actql_records(namespace, record_key, revision, body) "
    "VALUES(?1, ?2, 0, ?3)",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare journal insert failed");
    return actql_operation_code(code);
  }
  int32_t result = actql_bind_key(
    database,
    statement,
    1,
    namespace_bytes,
    namespace_length,
    2,
    key,
    key_length
  );
  if (result == 0) {
    code = database->library->bind_blob(
      statement,
      3,
      body,
      body_length,
      SQLITE_TRANSIENT
    );
    if (code != SQLITE_OK) {
      actql_database_error(database, "bind journal body failed");
      result = actql_operation_code(code);
    }
  }
  if (result == 0) {
    code = database->library->step(statement);
    if ((code & 0xff) == SQLITE_CONSTRAINT) {
      result = 2;
    } else if (code != SQLITE_DONE) {
      actql_database_error(database, "insert journal record failed");
      result = actql_operation_code(code);
    } else {
      database->result_revision = 0;
    }
  }
  int finalize_code = database->library->finalize(statement);
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize journal insert failed");
    return actql_operation_code(finalize_code);
  }
  return result;
}

int32_t actql_native_sqlite_database_compare_exchange(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t expected_revision,
  moonbit_bytes_t body,
  int32_t body_length
) {
  if (database == NULL || !database->opened) return 5;
  actql_clear_result(database);
  if (body_length < 0 || (int64_t)body_length > database->max_body_bytes) {
    return 4;
  }
  if (expected_revision < 0 || expected_revision == INT64_MAX) return 2;
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "UPDATE actql_records SET revision = revision + 1, body = ?3 "
    "WHERE namespace = ?1 AND record_key = ?2 AND revision = ?4",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare journal update failed");
    return actql_operation_code(code);
  }
  int32_t result = actql_bind_key(
    database,
    statement,
    1,
    namespace_bytes,
    namespace_length,
    2,
    key,
    key_length
  );
  if (result == 0) {
    code = database->library->bind_blob(
      statement,
      3,
      body,
      body_length,
      SQLITE_TRANSIENT
    );
    if (code == SQLITE_OK) {
      code = database->library->bind_int64(
        statement,
        4,
        (sqlite3_int64)expected_revision
      );
    }
    if (code != SQLITE_OK) {
      actql_database_error(database, "bind journal update failed");
      result = actql_operation_code(code);
    }
  }
  if (result == 0) {
    code = database->library->step(statement);
    if (code != SQLITE_DONE) {
      actql_database_error(database, "update journal record failed");
      result = actql_operation_code(code);
    } else if (database->library->changes64(database->database) != 1) {
      result = 2;
    } else {
      database->result_revision = expected_revision + 1;
    }
  }
  int finalize_code = database->library->finalize(statement);
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize journal update failed");
    return actql_operation_code(finalize_code);
  }
  return result;
}

static void actql_capacity_rollback(
  actql_native_sqlite_database *database
) {
  database->library->exec(database->database, "ROLLBACK", NULL, NULL, NULL);
}

static int32_t actql_capacity_begin(
  actql_native_sqlite_database *database
) {
  int code = actql_exec(database, "BEGIN IMMEDIATE");
  return code == SQLITE_OK ? 0 : actql_operation_code(code);
}

static int32_t actql_capacity_commit(
  actql_native_sqlite_database *database
) {
  int code = actql_exec(database, "COMMIT");
  if (code == SQLITE_OK) return 0;
  actql_capacity_rollback(database);
  return actql_operation_code(code);
}

static int32_t actql_capacity_existing(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t *reserved_bytes,
  int64_t *reserved_objects
) {
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "SELECT reserved_bytes, reserved_objects FROM actql_capacity "
    "WHERE namespace = ?1 AND reservation_key = ?2",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare capacity lookup failed");
    return actql_operation_code(code);
  }
  int32_t result = actql_bind_key(
    database,
    statement,
    1,
    namespace_bytes,
    namespace_length,
    2,
    key,
    key_length
  );
  if (result == 0) {
    code = database->library->step(statement);
    if (code == SQLITE_ROW) {
      *reserved_bytes = (int64_t)database->library->column_int64(statement, 0);
      *reserved_objects = (int64_t)database->library->column_int64(statement, 1);
      result = 0;
    } else if (code == SQLITE_DONE) {
      result = 1;
    } else {
      actql_database_error(database, "read capacity reservation failed");
      result = actql_operation_code(code);
    }
  }
  int finalize_code = database->library->finalize(statement);
  if (result >= 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize capacity lookup failed");
    return actql_operation_code(finalize_code);
  }
  return result;
}

static int32_t actql_capacity_sum(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  int64_t *reserved_bytes,
  int64_t *reserved_objects
) {
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "SELECT COALESCE(SUM(reserved_bytes), 0), "
    "COALESCE(SUM(reserved_objects), 0) FROM actql_capacity "
    "WHERE namespace = ?1",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare capacity sum failed");
    return actql_operation_code(code);
  }
  code = database->library->bind_text(
    statement,
    1,
    (const char *)namespace_bytes,
    namespace_length,
    SQLITE_TRANSIENT
  );
  int32_t result = 0;
  if (code != SQLITE_OK) {
    actql_database_error(database, "bind capacity scope failed");
    result = actql_operation_code(code);
  } else {
    code = database->library->step(statement);
    if (code == SQLITE_ROW) {
      *reserved_bytes = (int64_t)database->library->column_int64(statement, 0);
      *reserved_objects = (int64_t)database->library->column_int64(statement, 1);
    } else {
      actql_database_error(database, "read capacity sum failed");
      result = actql_operation_code(code);
    }
  }
  int finalize_code = database->library->finalize(statement);
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize capacity sum failed");
    return actql_operation_code(finalize_code);
  }
  return result;
}

int32_t actql_native_sqlite_database_reserve_capacity(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t reserved_bytes,
  int64_t reserved_objects,
  int64_t max_bytes,
  int64_t max_objects
) {
  if (database == NULL || !database->opened) return 5;
  actql_clear_result(database);
  if (reserved_bytes < 0 || reserved_objects < 0 || max_bytes < 0 ||
      max_objects < 0 || reserved_bytes > max_bytes ||
      reserved_objects > max_objects) {
    return 6;
  }
  int32_t result = actql_capacity_begin(database);
  if (result != 0) return result;
  int64_t existing_bytes = 0;
  int64_t existing_objects = 0;
  result = actql_capacity_existing(
    database,
    namespace_bytes,
    namespace_length,
    key,
    key_length,
    &existing_bytes,
    &existing_objects
  );
  if (result == 0) {
    if (existing_bytes != reserved_bytes ||
        existing_objects != reserved_objects) {
      actql_capacity_rollback(database);
      return 2;
    }
    result = actql_capacity_commit(database);
    return result == 0 ? 7 : result;
  }
  if (result != 1) {
    actql_capacity_rollback(database);
    return result;
  }
  int64_t used_bytes = 0;
  int64_t used_objects = 0;
  result = actql_capacity_sum(
    database,
    namespace_bytes,
    namespace_length,
    &used_bytes,
    &used_objects
  );
  if (result != 0) {
    actql_capacity_rollback(database);
    return result;
  }
  if (used_bytes < 0 || used_objects < 0 || used_bytes > max_bytes ||
      used_objects > max_objects || reserved_bytes > max_bytes - used_bytes ||
      reserved_objects > max_objects - used_objects) {
    actql_capacity_rollback(database);
    return 6;
  }
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "INSERT INTO actql_capacity("
    "namespace, reservation_key, reserved_bytes, reserved_objects"
    ") VALUES(?1, ?2, ?3, ?4)",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare capacity reservation failed");
    actql_capacity_rollback(database);
    return actql_operation_code(code);
  }
  result = actql_bind_key(
    database,
    statement,
    1,
    namespace_bytes,
    namespace_length,
    2,
    key,
    key_length
  );
  if (result == 0) {
    code = database->library->bind_int64(statement, 3, reserved_bytes);
    if (code == SQLITE_OK) {
      code = database->library->bind_int64(statement, 4, reserved_objects);
    }
    if (code != SQLITE_OK) {
      actql_database_error(database, "bind capacity reservation failed");
      result = actql_operation_code(code);
    }
  }
  if (result == 0) {
    code = database->library->step(statement);
    if (code != SQLITE_DONE) {
      actql_database_error(database, "insert capacity reservation failed");
      result = actql_operation_code(code);
    }
  }
  int finalize_code = database->library->finalize(statement);
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize capacity reservation failed");
    result = actql_operation_code(finalize_code);
  }
  if (result != 0) {
    actql_capacity_rollback(database);
    return result;
  }
  return actql_capacity_commit(database);
}

int32_t actql_native_sqlite_database_release_capacity(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t reserved_bytes,
  int64_t reserved_objects
) {
  if (database == NULL || !database->opened) return 5;
  actql_clear_result(database);
  if (reserved_bytes < 0 || reserved_objects < 0) return 2;
  int32_t result = actql_capacity_begin(database);
  if (result != 0) return result;
  int64_t existing_bytes = 0;
  int64_t existing_objects = 0;
  result = actql_capacity_existing(
    database,
    namespace_bytes,
    namespace_length,
    key,
    key_length,
    &existing_bytes,
    &existing_objects
  );
  if (result == 1) {
    result = actql_capacity_commit(database);
    return result == 0 ? 7 : result;
  }
  if (result != 0 || existing_bytes != reserved_bytes ||
      existing_objects != reserved_objects) {
    actql_capacity_rollback(database);
    return result == 0 ? 2 : result;
  }
  sqlite3_stmt *statement = NULL;
  int code = database->library->prepare_v2(
    database->database,
    "DELETE FROM actql_capacity WHERE namespace = ?1 "
    "AND reservation_key = ?2",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare capacity release failed");
    actql_capacity_rollback(database);
    return actql_operation_code(code);
  }
  result = actql_bind_key(
    database,
    statement,
    1,
    namespace_bytes,
    namespace_length,
    2,
    key,
    key_length
  );
  if (result == 0) {
    code = database->library->step(statement);
    if (code != SQLITE_DONE ||
        database->library->changes64(database->database) != 1) {
      if (code != SQLITE_DONE) {
        actql_database_error(database, "release capacity reservation failed");
      }
      result = code == SQLITE_DONE ? 2 : actql_operation_code(code);
    }
  }
  int finalize_code = database->library->finalize(statement);
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize capacity release failed");
    result = actql_operation_code(finalize_code);
  }
  if (result != 0) {
    actql_capacity_rollback(database);
    return result;
  }
  return actql_capacity_commit(database);
}

int32_t actql_native_sqlite_database_capacity_usage(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length
) {
  if (database == NULL || !database->opened) return 5;
  actql_clear_result(database);
  int64_t reserved_bytes = 0;
  int64_t reserved_objects = 0;
  int32_t result = actql_capacity_sum(
    database,
    namespace_bytes,
    namespace_length,
    &reserved_bytes,
    &reserved_objects
  );
  if (result == 0) {
    database->result_capacity_bytes = reserved_bytes;
    database->result_capacity_objects = reserved_objects;
  }
  return result;
}

int64_t actql_native_sqlite_database_result_capacity_bytes(
  actql_native_sqlite_database *database
) {
  return database == NULL ? 0 : database->result_capacity_bytes;
}

int64_t actql_native_sqlite_database_result_capacity_objects(
  actql_native_sqlite_database *database
) {
  return database == NULL ? 0 : database->result_capacity_objects;
}

int64_t actql_native_sqlite_database_result_revision(
  actql_native_sqlite_database *database
) {
  return database == NULL ? 0 : database->result_revision;
}

moonbit_bytes_t actql_native_sqlite_database_result_body(
  actql_native_sqlite_database *database
) {
  if (database == NULL) return actql_copy_bytes(NULL, 0);
  return actql_copy_bytes(database->result_body, database->result_body_length);
}

moonbit_bytes_t actql_native_sqlite_database_result_key(
  actql_native_sqlite_database *database
) {
  if (database == NULL) return actql_copy_bytes(NULL, 0);
  return actql_copy_bytes(database->result_key, database->result_key_length);
}

void actql_native_sqlite_close_database(
  actql_native_sqlite_database *database
) {
  if (database != NULL) actql_native_sqlite_database_close(database);
}
