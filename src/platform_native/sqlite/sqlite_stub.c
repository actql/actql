#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

#include "moonbit.h"
#include "../filesystem/native_timings.h"

#include <dlfcn.h>
#include "../filesystem/observed_component_member.h"
#include "../host_bootstrap/component_domain_minimum.h"
#include <errno.h>
#include <limits.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>
#include "../../../packages/python-local-runtime/native/sqlite-component/api.h"
#include <fcntl.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <spawn.h>
#include <unistd.h>

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
typedef int (*actql_sqlite_get_autocommit_fn)(sqlite3 *);

typedef int (*actql_heap_wal_fn)(void *);

typedef struct {
  void *dynamic_library;
  actql_native_command_platform_load *command_load;
  actql_native_observed_component_member *command_member;
  char *error;
  int32_t diagnostic_ceiling;
  bool selected_component, closing, selected_ready, selected_context_user;
  pid_t selected_process;
  int module_close_result;
  size_t database_children;
  actql_read_context *selected_context;
  const actql_sqlite_component_api *selected_api;
  int (*component_close)(void);
  int (*component_release_api)(const actql_sqlite_component_api *);
  bool component_owned;
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
  actql_sqlite_get_autocommit_fn get_autocommit;
  /* Immutable successful selection, not available capacity or permission. */
  int64_t selected_heap_bytes;
} actql_native_sqlite_library;

typedef struct actql_native_store_operation actql_native_store_operation;

typedef struct {
  actql_native_sqlite_library *library;
  sqlite3 *database;
  actql_native_store_operation *store_operation;
  char *error;
  unsigned char *result_body;
  int32_t result_body_length;
  unsigned char *result_key;
  int32_t result_key_length;
  int64_t result_revision;
  int64_t result_header_body_bytes;
  int64_t result_capacity_bytes;
  int64_t result_capacity_objects;
  int64_t result_record_count;
  int64_t result_record_body_bytes;
  int64_t result_reservation_count;
  int64_t max_body_bytes;
  int32_t diagnostic_ceiling;
  bool opened;
  /* Same Database physical close and descriptor ACK, obtained while current.
   * A later managed-shell return must not call that physical port again. */
  bool checked_close_ack;
  bool library_child;
  int test_close_failures;
  int test_commit_failures;
  int test_commit_reply_failures;
  int test_commit_skip;
  int transaction_fenced;
  // The same Database retains its read child before BEGIN and after a lost
  // response. This is not the earlier write's outcome or a second ledger.
  pid_t process;
  int64_t lookup_sequence, lookup_generation;
  bool lookup_start_attempted, lookup_begin_attempted;
  bool lookup_ready, lookup_stop_attempted;
  int test_lookup_start_reply, test_lookup_stop_reply, test_lookup_stop_failure;
  int test_lookup_current_failure, test_lookup_before_begin, test_lookup_poststop;
  int test_lookup_begin_count, test_lookup_stop_count;
  int test_checked_close_count;
  bool test_name_scan_refusal;
  actql_heap_wal_fn journal_inspection_observer;
  actql_heap_wal_fn journal_descriptor_ack;
  bool journal_pin_close_unknown;
  int journal_pin_descriptor;
} actql_native_sqlite_database;

/* Read-only necessary subset for the selected command's actual compiled
 * receiver ABI. Later SQL/cache/graph demand and all outside-domain holdings
 * remain separate; a positive result supplies no domain or claim. */
MOONBIT_FFI_EXPORT int64_t actql_native_sqlite_command_domain_necessary_bytes(
    int64_t domain_bytes, int64_t heap_bytes) {
#if defined(ACTQL_SCOPED_READ_ALLOCATOR)
  return actql_bootstrap_component_domain_necessary_bytes(domain_bytes, heap_bytes,
    sizeof(actql_native_sqlite_library), sizeof(actql_native_sqlite_database), 4097);
#else
  (void)domain_bytes; (void)heap_bytes;
  return -1;
#endif
}

#ifdef ACTQL_SCOPED_READ_ALLOCATOR
static bool actql_component_origin(const void *, void *);
#endif

static actql_heap_wal_fn actql_original_journal_wal_port(
  actql_native_sqlite_library *, const char *);

#ifdef ACTQL_SCOPED_READ_ALLOCATOR
#include "../../../packages/python-local-runtime/native/pre-root/owned_capacity.h"
extern actql_read_context *actql_bootstrap_current_read_context(void);
extern void *actql_native_file_scoped_allocate(size_t);
extern void actql_native_file_scoped_free(void *);
extern int actql_read_context_retain(actql_read_context *);
extern int actql_read_context_release_after_owner_ack(actql_read_context *);
#endif

/* The existing selected Library carries physical provenance, never Account
 * permission. The Host still validates its nominal Store/current before entry. */
static bool actql_library_current(actql_native_sqlite_library *library) {
  if (library == NULL || !library->selected_component) return true;
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  return library->selected_process == getpid() && library->selected_context != NULL &&
    actql_bootstrap_current_read_context() == library->selected_context;
#else
  return false;
#endif
}
static bool actql_library_available(actql_native_sqlite_library *library) {
  return library != NULL && library->dynamic_library != NULL &&
    !library->closing && (!library->selected_component || library->selected_ready) &&
    actql_library_current(library)
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
    && (!library->command_load || actql_native_command_platform_load_current(library->command_load))
#endif
    ;
}
static bool actql_database_library_available(actql_native_sqlite_library *library) {
  return library == NULL || !library->selected_component || actql_library_available(library);
}
/* Whitebox lifetime observation only. A count acknowledges no physical owner. */
int32_t actql_native_sqlite_test_library_database_children(
    actql_native_sqlite_library *library) {
  if (library == NULL || library->database_children > INT_MAX) return -1;
  return (int32_t)library->database_children;
}
#include "store_operation_original.inc"

/* A lifecycle observation, not a transition, normal-current proof or child ACK.
 * A sticky old failure alone does not imply a pending physical scope. */
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_pending_scope(
    actql_native_store_operation *value) {
  if (!actql_store_operation_thread(value) || value->closed) return -1;
  return value->calling || value->flight || value->sql ? 1 : 0;
}


static void *actql_adapter_allocate(actql_native_sqlite_library *library, size_t bytes) {
  if (library == NULL || !library->selected_component) return malloc(bytes);
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (library->closing || !actql_library_current(library)) return NULL;
  return library->selected_api != NULL
    ? library->selected_api->allocate_memory(bytes)
    : actql_native_file_scoped_allocate(bytes); /* Pre-bind loader text only. */
#else
  return NULL;
#endif
}
static void actql_adapter_free(actql_native_sqlite_library *library, void *pointer) {
  if (pointer == NULL) return;
  if (library == NULL || !library->selected_component) { free(pointer); return; }
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  /* The provider routes the original allocation, not the current thread's heap.
   * Unconfirmed retirement stays in that SAME provider's existing extent table. */
  if (library->selected_ready && library->component_owned) library->free_memory(pointer);
  else actql_native_file_scoped_free(pointer);
#endif
}
int32_t actql_native_sqlite_library_close_checked(actql_native_sqlite_library *);

// A positive ceiling is selected by the trusted installer, independently of
// SQL row limits. Zero preserves legacy callers and is not funded-profile proof.
// Never return a bounded prefix as a complete diagnostic. NULL also represents
// allocation/diagnostic failure; the MoonBit boundary supplies fixed omitted text.
static bool actql_diagnostic_length(
  const char *message, int32_t ceiling, size_t *length
) {
  if (message == NULL) return false;
  if (ceiling <= 0) { *length = strlen(message); return true; }
  for (size_t i = 0; i <= (size_t)ceiling; i++) {
    if (message[i] == '\0') { *length = i; return true; }
  }
  return false;
}

static void actql_replace_error_for(
  actql_native_sqlite_library *library, char **target, int32_t ceiling, const char *message
) {
  actql_adapter_free(library, *target);
  *target = NULL;
  size_t length;
  if (!actql_diagnostic_length(message, ceiling, &length)) return;
  char *copy = actql_adapter_allocate(library, length + 1);
  if (copy == NULL) return;
  memcpy(copy, message, length);
  copy[length] = '\0';
  *target = copy;
}

static char *actql_copy_text_for(actql_native_sqlite_library *library, moonbit_bytes_t bytes, int32_t length) {
  if (length < 0) return NULL;
  char *text = actql_adapter_allocate(library, (size_t)length + 1);
  if (text == NULL) return NULL;
  if (length > 0) memcpy(text, bytes, (size_t)length);
  text[length] = '\0';
  return text;
}

static char *actql_copy_text(moonbit_bytes_t bytes, int32_t length) {
  return actql_copy_text_for(NULL, bytes, length);
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

// Returned MoonBytes are independent copies. Retire only the C readback
// storage; diagnostic lifetime and durable rows are separate responsibilities.
static void actql_retire_result_storage(actql_native_sqlite_database *database) {
  actql_adapter_free(database->library, database->result_body);
  actql_adapter_free(database->library, database->result_key);
  database->result_body = NULL;
  database->result_key = NULL;
  database->result_body_length = 0;
  database->result_key_length = 0;
  database->result_revision = 0;
  database->result_header_body_bytes = 0;
  database->result_capacity_bytes = 0;
  database->result_capacity_objects = 0;
  database->result_record_count = 0;
  database->result_record_body_bytes = 0;
  database->result_reservation_count = 0;
}

static void actql_clear_result(actql_native_sqlite_database *database) {
  actql_retire_result_storage(database);
  actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, NULL);
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
  actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, message);
}

static int32_t actql_operation_code(int sqlite_code) {
  int primary = sqlite_code & 0xff;
  if (primary == SQLITE_BUSY || primary == SQLITE_LOCKED) return 3;
  return -1;
}

static void actql_native_sqlite_library_finalize(void *value) {
  actql_native_sqlite_library *library = value;
  if (library->selected_component) {
    /* Legitimate callers retain this original in their failed-open/Host carrier
     * until checked close acknowledges it. Finalization is not that ACK. */
    (void)actql_native_sqlite_library_close_checked(library);
    return;
  }
  if (library->dynamic_library != NULL) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  actql_adapter_free(library, library->error);
  library->error = NULL;
}

static void actql_native_sqlite_database_close(
  actql_native_sqlite_database *database
) {
  if (database->database == NULL) {
    actql_retire_result_storage(database);
    return;
  }
  if (!actql_library_current(database->library) ||
      database->library->close_v2(database->database) != SQLITE_OK) return;
  database->database = NULL;
  database->opened = false;
  actql_retire_result_storage(database);
}

// Inspection callers retain this database even if open failed, and close it
// explicitly through the retryable cleanup boundary. Only the private copy is
// opened. No schema creation, WAL mode change or migration is performed here.
static void actql_native_sqlite_database_finalize(void *value);

static char *actql_journal_copy_uri(actql_native_sqlite_library *library,
    moonbit_bytes_t path, int32_t length) {
  if (length < 2 || length > 4096 || path[0] != '/' ||
      memchr(path, 0, (size_t)length) != NULL) return NULL;
  char *name = actql_adapter_allocate(library, (size_t)length + 5);
  if (name == NULL) return NULL;
  memcpy(name, path, (size_t)length); memcpy(name + length, "-shm", 5);
  struct stat original;
  bool empty = lstat(name, &original) == 0 &&
    S_ISREG(original.st_mode) && original.st_size == 0 && original.st_uid == getuid();
  actql_adapter_free(library, name);
  if (!empty) return NULL;
  /* The existing inspection Owner created and retains this unique empty SHM.
   * URI bytes neither acquire that ownership nor grant access to another DB. */
  const char suffix[] = "?mode=ro&readonly_shm=1";
  char *uri = actql_adapter_allocate(library, 5 + (size_t)length * 3 + sizeof(suffix));
  if (uri == NULL) return NULL;
  const char hex[] = "0123456789ABCDEF";
  memcpy(uri, "file:", 5); size_t written = 5;
  for (int32_t i = 0; i < length; i++) {
    unsigned char c = path[i];
    if (c == '/' || (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
        (c >= '0' && c <= '9') || c == '-' || c == '.' || c == '_' || c == '~') {
      uri[written++] = (char)c;
    } else {
      uri[written++] = '%'; uri[written++] = hex[c >> 4]; uri[written++] = hex[c & 15];
    }
  }
  memcpy(uri + written, suffix, sizeof(suffix));
  return uri;
}

static void *actql_open_inspection_database(
  actql_native_sqlite_library *library,
  moonbit_bytes_t path,
  int32_t length,
  int64_t max_body_bytes,
  bool journal_copy
) {
  if (!actql_library_current(library) || (library != NULL && library->selected_component &&
      !actql_library_available(library))) return NULL;
  actql_native_sqlite_database *database = moonbit_make_external_object(
    actql_native_sqlite_database_finalize,
    sizeof(actql_native_sqlite_database)
  );
  memset(database, 0, sizeof(*database));
  database->library = library;
  database->process = getpid();
  if (library != NULL) {
    moonbit_incref(library);
    library->database_children++;
    database->library_child = true;
  }
  database->max_body_bytes = max_body_bytes;
  database->diagnostic_ceiling = library == NULL ? 0 : library->diagnostic_ceiling;
  if (!actql_library_available(library)) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "SQLite library is unavailable");
    return database;
  }
  if (journal_copy) {
    database->journal_descriptor_ack = actql_original_journal_wal_port(
      library, "actql_sqlite_component_descriptor_ack");
    database->journal_inspection_observer = actql_original_journal_wal_port(
      library, "actql_sqlite_component_readonly_heap_wal");
    if (database->journal_inspection_observer == NULL || database->journal_descriptor_ack == NULL) {
      actql_replace_error_for(library, &database->error, database->diagnostic_ceiling,
        "selected read-only Journal WAL observation is unavailable");
      return database;
    }
  }
  char *text = journal_copy ? actql_journal_copy_uri(library, path, length)
    : actql_copy_text_for(library, path, length);
  if (text == NULL) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "inspection path allocation failed");
    return database;
  }
  int flags = SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX;
  /* The pinned unix VFS opens DB/WAL/SHM with O_NOFOLLOW. Unlike the generic
   * inspection route, SQLITE_OPEN_NOFOLLOW additionally rejects ancestor
   * aliases such as the platform temporary directory; do not impose that
   * unrelated restriction on the same original isolated copy. */
  if (journal_copy) flags |= SQLITE_OPEN_URI;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_OPEN, library->open_v2)(text, &database->database, flags, NULL);
  actql_adapter_free(library, text);
  if (code != SQLITE_OK) {
    actql_database_error(database, "open inspection database failed");
  } else database->opened = true;
  return database;
}

void *actql_native_sqlite_open_inspection_database(
  actql_native_sqlite_library *library, moonbit_bytes_t path,
  int32_t length, int64_t max_body_bytes
) {
  return actql_open_inspection_database(library, path, length, max_body_bytes, false);
}

void *actql_native_sqlite_open_journal_inspection_database(
  actql_native_sqlite_library *library, moonbit_bytes_t path,
  int32_t length, int64_t max_body_bytes
) {
  return actql_open_inspection_database(library, path, length, max_body_bytes, true);
}

int32_t actql_native_sqlite_close_checked(
  actql_native_sqlite_database *database
) {
  if (database == NULL) return 1;
  if (!actql_library_current(database->library)) return 0;
  if (database->journal_pin_close_unknown) return 0;
  if (database->lookup_generation != 0) return 0;
  if (database->checked_close_ack) return 1;
  if (database->database == NULL) {
    actql_retire_result_storage(database);
    bool ack = database->journal_descriptor_ack == NULL ||
      database->journal_descriptor_ack(NULL) == ACTQL_SQLITE_COMPONENT_OK;
    if (ack) {
      actql_adapter_free(database->library, database->error);
      database->error = NULL;
      database->checked_close_ack = true;
      if (database->store_operation != NULL)
        database->store_operation->database_closed = true;
    }
    return ack;
  }
  database->test_checked_close_count++;
  if (database->test_close_failures > 0) {
    database->test_close_failures--;
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "injected inspection close failure");
    return 0;
  }
  int code = database->library->close_v2(database->database);
  if (code != SQLITE_OK) {
    actql_database_error(database, "close SQLite database failed");
    return 0;
  }
  database->database = NULL;
  database->opened = false;
  actql_retire_result_storage(database);
  bool ack = database->journal_descriptor_ack == NULL ||
    database->journal_descriptor_ack(NULL) == ACTQL_SQLITE_COMPONENT_OK;
  if (ack) {
    actql_adapter_free(database->library, database->error);
    database->error = NULL;
    database->checked_close_ack = true;
    if (database->store_operation != NULL)
      database->store_operation->database_closed = true;
  }
  return ack;
}

// Whitebox observation only, never a physical-close ACK or a settlement port.
int32_t actql_native_sqlite_test_result_storage_empty(
  actql_native_sqlite_database *database
) {
  return database->result_body == NULL && database->result_key == NULL &&
    database->result_body_length == 0 && database->result_key_length == 0 &&
    database->result_revision == 0 && database->result_capacity_bytes == 0 &&
    database->result_capacity_objects == 0;
}

// Whitebox-only callers inject a physical close failure on their own database;
// no environment setting or public execution/authorization API enables it.
void actql_native_sqlite_test_fail_close(
  actql_native_sqlite_database *database, int32_t failures
) { database->test_close_failures = failures; }

// Whitebox-only injection: the caller owns this database and its transaction.
void actql_native_sqlite_test_fail_commit(
  actql_native_sqlite_database *database, int32_t failures
) { database->test_commit_failures = failures; database->test_commit_skip = 0; }

void actql_native_sqlite_test_fail_commit_reply(
  actql_native_sqlite_database *database, int32_t failures
) { database->test_commit_reply_failures = failures; database->test_commit_skip = 0; }

// Select an owned transaction boundary after preceding successful commits.
// This is whitebox fault injection, not an environment-controlled retry mode.
void actql_native_sqlite_test_fail_commit_after(
  actql_native_sqlite_database *database, int32_t skip, int32_t reply_lost
) {
  database->test_commit_skip = skip > 0 ? skip : 0;
  database->test_commit_failures = reply_lost ? 0 : 1;
  database->test_commit_reply_failures = reply_lost ? 1 : 0;
}

int32_t actql_native_sqlite_test_checked_close_count(
  actql_native_sqlite_database *database
) { return database->test_checked_close_count; }

static void actql_native_sqlite_database_finalize(void *value) {
  actql_native_sqlite_database *database = value;
  if (database->store_operation != NULL) {
    actql_native_store_operation *original = database->store_operation;
    /* Last managed alias only: physical close, descriptor and result-storage
     * ACKs were recorded in the original entered scope. Never call the
     * component again from the outer context merely to retire this shell. */
    if (!original->database_closed || original->flight || original->sql ||
        database->database != NULL || database->journal_pin_close_unknown ||
        database->lookup_generation != 0 || database->error != NULL ||
        database->result_body != NULL || database->result_key != NULL) return;
  } else if (database->checked_close_ack) {
    /* Only the already-acknowledged shell remains. Re-entering a component
     * here would lose the Library pin when the original scope has ended. */
    if (database->process != getpid() || database->database != NULL ||
        database->journal_pin_close_unknown ||
        database->lookup_generation != 0 || database->error != NULL ||
        database->result_body != NULL || database->result_key != NULL) return;
  } else {
    actql_native_sqlite_database_close(database);
    if (database->library != NULL && database->library->selected_component &&
        (database->database != NULL || database->journal_pin_close_unknown ||
         (database->journal_descriptor_ack != NULL &&
         database->journal_descriptor_ack(NULL) != ACTQL_SQLITE_COMPONENT_OK))) return;
    actql_adapter_free(database->library, database->error);
    actql_adapter_free(database->library, database->result_body);
    actql_adapter_free(database->library, database->result_key);
  }
  database->error = NULL;
  database->result_body = NULL;
  database->result_key = NULL;
  if (database->store_operation != NULL) {
    moonbit_decref(database->store_operation);
    database->store_operation = NULL;
  }
  if (database->library != NULL) {
    if (database->library_child) {
      database->library->database_children--;
      database->library_child = false;
    }
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
  actql_replace_error_for(library, &library->error, library->diagnostic_ceiling, error == NULL ? name : error);
  return false;
}

#define ACTQL_LOAD(library, field, symbol) \
  actql_load_symbol((library), (void **)&((library)->field), (symbol))

static int actql_exec(
  actql_native_sqlite_database *database,
  const char *sql
) {
  char *message = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_EXEC, database->library->exec)(
    database->database,
    sql,
    NULL,
    NULL,
    &message
  );
  if (code != SQLITE_OK) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling,
      message == NULL ? "SQLite execution failed" : message
    );
  }
  if (message != NULL) database->library->free_memory(message);
  return code;
}

static int actql_user_version(actql_native_sqlite_database *database) {
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
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
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
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

#define ACTQL_RECORDS_FIELDS \
  "namespace TEXT NOT NULL," \
  "record_key TEXT NOT NULL," \
  "revision INTEGER NOT NULL CHECK(revision >= 0)," \
  "body BLOB NOT NULL," \
  "PRIMARY KEY(namespace, record_key)"
#define ACTQL_CAPACITY_FIELDS \
  "namespace TEXT NOT NULL," \
  "reservation_key TEXT NOT NULL," \
  "reserved_bytes INTEGER NOT NULL CHECK(reserved_bytes >= 0)," \
  "reserved_objects INTEGER NOT NULL CHECK(reserved_objects >= 0)," \
  "PRIMARY KEY(namespace, reservation_key)"
#define ACTQL_CLAIMS_FIELDS \
  "namespace TEXT NOT NULL," \
  "claim_key TEXT NOT NULL," \
  "ordinal INTEGER NOT NULL CHECK(ordinal > 0)," \
  "PRIMARY KEY(namespace, claim_key)," \
  "UNIQUE(namespace, ordinal)"

int32_t actql_native_sqlite_inspection_schema(
  actql_native_sqlite_database *database
) {
  if (!database->opened || !actql_database_library_available(database->library) || actql_user_version(database) != 3) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "unsupported inspection SQLite schema");
    return 0;
  }
  const char *names[] = {"actql_records", "actql_capacity", "actql_claims"};
  const char *definitions[] = {
    "CREATE TABLE actql_records(" ACTQL_RECORDS_FIELDS ") STRICT",
    "CREATE TABLE actql_capacity(" ACTQL_CAPACITY_FIELDS ") STRICT",
    "CREATE TABLE actql_claims(" ACTQL_CLAIMS_FIELDS ") STRICT"
  };
  for (int index = 0; index < 3; index++) {
    sqlite3_stmt *statement = NULL;
    int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
      "SELECT sql FROM sqlite_schema WHERE type='table' AND name=?1", -1,
      &statement, NULL);
    if (code == SQLITE_OK) code = database->library->bind_text(statement, 1,
      names[index], -1, SQLITE_STATIC);
    if (code == SQLITE_OK) code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    int matches = 0;
    if (code == SQLITE_ROW) {
      int length = database->library->column_bytes(statement, 0);
      const void *sql = database->library->column_blob(statement, 0);
      matches = length == (int)strlen(definitions[index]) && sql != NULL &&
        memcmp(sql, definitions[index], (size_t)length) == 0;
    }
    if (statement != NULL && database->library->finalize(statement) != SQLITE_OK)
      matches = 0;
    if (!matches) {
      actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "unknown inspection SQLite schema");
      return 0;
    }
  }
  if (database->journal_inspection_observer != NULL &&
      database->journal_inspection_observer(database->database) != ACTQL_SQLITE_COMPONENT_OK) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling,
      "read-only Journal did not retain its private heap WAL path");
    return 0;
  }
  return 1;
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
  if (version > 3) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "unsupported SQLite schema version");
    return false;
  }
  const char *schema =
    "BEGIN IMMEDIATE;"
    "CREATE TABLE IF NOT EXISTS actql_records("
    ACTQL_RECORDS_FIELDS
    ") STRICT;"
    "CREATE TABLE IF NOT EXISTS actql_capacity("
    ACTQL_CAPACITY_FIELDS
    ") STRICT;"
    "CREATE TABLE IF NOT EXISTS actql_claims("
    ACTQL_CLAIMS_FIELDS
    ") STRICT;"
    "PRAGMA user_version=3;"
    "COMMIT;";
  if (actql_exec(database, schema) != SQLITE_OK) {
    ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_EXEC, database->library->exec)(database->database, "ROLLBACK", NULL, NULL, NULL);
    return false;
  }
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
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

// Whitebox fixture only: a separately exec'd process creates the unclosed WAL.
// Never call SQLite or platform libraries on the child side of fork pre-exec.
extern char **environ;
static int fixture_write(int descriptor, const void *value, size_t length) {
  const unsigned char *bytes = value;
  while (length) {
    ssize_t count = write(descriptor, bytes, length);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) return 0;
    bytes += count; length -= (size_t)count;
  }
  return 1;
}
int32_t actql_native_sqlite_test_unclosed_coordinator(
  actql_native_sqlite_library *library,
  moonbit_bytes_t path, int32_t path_length,
  moonbit_bytes_t key, int32_t key_length,
  moonbit_bytes_t body, int32_t body_length,
  int32_t missing_schema
) {
  const char *fixture = getenv("ACTQL_TEST_NATIVE_UNCLOSED_SQLITE_FIXTURE");
  const char *sqlite_library = getenv("ACTQL_TEST_NATIVE_SQLITE_LIBRARY");
  if (!library || !fixture || !sqlite_library || key_length <= 0 ||
      key_length > 65536 || body_length < 0 || body_length > 1048576) return 0;
  char *text = actql_copy_text(path, path_length);
  if (!text) return 0;
  size_t length = strlen(text);
  char *input = malloc(length + 15), *shm = malloc(length + 5);
  if (!input || !shm) { free(input); free(shm); free(text); return 0; }
  snprintf(input, length + 15, "%s.fixture-input", text);
  int descriptor = open(input, O_CREAT | O_EXCL | O_WRONLY | O_NOFOLLOW, 0600);
  uint32_t lengths[] = {(uint32_t)key_length, (uint32_t)body_length};
  int written = descriptor >= 0 && fixture_write(descriptor, lengths, sizeof(lengths)) &&
    fixture_write(descriptor, key, (size_t)key_length) && fixture_write(descriptor, body, (size_t)body_length);
  if (descriptor >= 0 && close(descriptor)) written = 0;
  int result = 0;
  if (written) {
    char *arguments[] = {(char *)fixture, (char *)sqlite_library, text, input,
      missing_schema ? "1" : "0", NULL};
    pid_t child;
    int spawned = posix_spawn(&child, fixture, NULL, NULL, arguments, environ);
    if (!spawned) {
      int status = -1, waited;
      do { waited = waitpid(child, &status, 0); } while (waited < 0 && errno == EINTR);
      result = waited == child && WIFEXITED(status) && WEXITSTATUS(status) == 0;
    }
  }
  // Keep failed fixture inputs as evidence inside the caller's owned namespace.
  if (result) {
    snprintf(shm, length + 5, "%s-shm", text);
    result = unlink(shm) == 0 && unlink(input) == 0;
  }
  free(input); free(shm); free(text);
  return result;
}

moonbit_bytes_t actql_native_sqlite_test_file_bytes(
  moonbit_bytes_t path, int32_t length
) {
  char *text = actql_copy_text(path, length);
  if (text == NULL) return actql_copy_bytes(NULL, 0);
  int descriptor = open(text, O_RDONLY | O_NOFOLLOW);
  free(text);
  struct stat info;
  if (descriptor < 0 || fstat(descriptor, &info) != 0 ||
      info.st_size < 0 || info.st_size > 1048576) {
    if (descriptor >= 0) close(descriptor);
    return actql_copy_bytes(NULL, 0);
  }
  moonbit_bytes_t bytes = moonbit_make_bytes_raw((int32_t)info.st_size);
  off_t position = 0;
  while (position < info.st_size) {
    ssize_t count = pread(descriptor, bytes + position,
      (size_t)(info.st_size - position), position);
    if (count < 0 && errno == EINTR) continue;
    if (count <= 0) break;
    position += count;
  }
  close(descriptor);
  if (position != info.st_size) return actql_copy_bytes(NULL, 0);
  return bytes;
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
  int32_t length,
  int32_t diagnostic_ceiling
) {
  actql_native_sqlite_library *library = moonbit_make_external_object(
    actql_native_sqlite_library_finalize,
    sizeof(actql_native_sqlite_library)
  );
  memset(library, 0, sizeof(*library));
  library->diagnostic_ceiling = diagnostic_ceiling;
  char *path_text = actql_copy_text_for(library, path, length);
  if (path_text == NULL) {
    actql_replace_error_for(library, &library->error, library->diagnostic_ceiling, "SQLite library path allocation failed");
    return library;
  }
  library->dynamic_library = dlopen(path_text, RTLD_NOW | RTLD_LOCAL);
  actql_adapter_free(library, path_text);
  if (library->dynamic_library == NULL) {
    actql_replace_error_for(library, &library->error, library->diagnostic_ceiling, dlerror());
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
      !ACTQL_LOAD(library, busy_timeout, "sqlite3_busy_timeout") ||
      !ACTQL_LOAD(library, get_autocommit, "sqlite3_get_autocommit")) {
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
    return library;
  }
  if (library->libversion_number() < 3037000) {
    actql_replace_error_for(library, &library->error, library->diagnostic_ceiling, "SQLite 3.37.0 or later is required");
    dlclose(library->dynamic_library);
    library->dynamic_library = NULL;
  }
  return library;
}

int32_t actql_native_sqlite_library_ready(
  actql_native_sqlite_library *library
) {
  return actql_library_available(library);
}

/* Original immutable selection only, not current/funding/cleanup permission.
 * Keep legacy zero observable as unavailable for a finite-bound projection. */
int32_t actql_native_sqlite_library_diagnostic_ceiling(
  actql_native_sqlite_library *library
) {
  return library == NULL ? 0 : library->diagnostic_ceiling;
}

int32_t actql_native_sqlite_database_diagnostic_ceiling(
  actql_native_sqlite_database *database
) {
  return database == NULL ? 0 : database->diagnostic_ceiling;
}

/* Observe this exact Database's original selected Library inside its current
 * context. Legacy malloc and diagnostic ceilings cannot prove this origin.
 * No SQL, allocation, configuration, cleanup or authorization is performed. */
int32_t actql_native_sqlite_database_current_component_matches_heap(
  actql_native_sqlite_database *database, int64_t expected_heap_bytes
) {
  if (database == NULL || !database->opened || database->database == NULL ||
      expected_heap_bytes < 4096 || expected_heap_bytes > INT_MAX) return 0;
  actql_native_sqlite_library *library = database->library;
  return library != NULL && library->selected_component &&
    library->selected_heap_bytes == expected_heap_bytes &&
    library->component_owned && library->selected_context_user &&
    library->selected_api != NULL && actql_library_available(library);
}

static moonbit_bytes_t actql_copy_diagnostic(const char *text, int32_t ceiling) {
  size_t length;
  if (!actql_diagnostic_length(text, ceiling, &length) || length > INT32_MAX)
    return actql_copy_bytes(NULL, 0);
  return actql_copy_bytes(text, (int32_t)length);
}

moonbit_bytes_t actql_native_sqlite_library_error(
  actql_native_sqlite_library *library
) {
  return library == NULL || !actql_library_current(library) ? actql_copy_bytes(NULL, 0) :
    actql_copy_diagnostic(library->error, library->diagnostic_ceiling);
}

moonbit_bytes_t actql_native_sqlite_library_version(
  actql_native_sqlite_library *library
) {
  if (!actql_library_available(library)) {
    return actql_copy_message("");
  }
  return actql_copy_message(library->libversion());
}

// Preserve the primary open diagnosis and the same handle when its immediate
// cleanup is not acknowledged. The custody API can later observe close on this
// object; it never opens another connection or initializes schema again.
static void actql_retire_failed_open_database(
  actql_native_sqlite_database *database
) {
  database->opened = false;
  if (database->database == NULL) return;
  if (database->test_close_failures > 0) {
    database->test_close_failures--;
    return;
  }
  if (database->library->close_v2(database->database) == SQLITE_OK)
    database->database = NULL;
}

// Whitebox fault injection on an already owned connection, using the same
// failed-open cleanup boundary. No environment option enables this path.
void actql_native_sqlite_test_failed_open_cleanup(
  actql_native_sqlite_database *database
) {
  actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling,
    "injected original database open failure");
  actql_retire_failed_open_database(database);
}

/* Only the original adoption Journal caller selects this restriction. The
 * caller separately retains its Session/Lock; neither this mode nor a path is
 * proof of that custody, resource admission or permission. */
static bool actql_select_journal_exclusive(actql_native_sqlite_database *database) {
  sqlite3_stmt *statement = NULL;
  actql_native_sqlite_library *library = database->library;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, library->prepare_v2)(database->database,
    "PRAGMA main.locking_mode=EXCLUSIVE", -1, &statement, NULL);
  bool selected = false;
  if (code == SQLITE_OK && ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, library->step)(statement) == SQLITE_ROW) {
    const void *mode = library->column_blob(statement, 0);
    int length = library->column_bytes(statement, 0);
    selected = mode != NULL && length == 9 && memcmp(mode, "exclusive", 9) == 0 &&
      ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, library->step)(statement) == SQLITE_DONE;
  }
  if (statement != NULL && library->finalize(statement) != SQLITE_OK) selected = false;
  return selected;
}

static actql_heap_wal_fn actql_original_journal_wal_port(
    actql_native_sqlite_library *library, const char *symbol) {
#ifdef ACTQL_SCOPED_READ_ALLOCATOR
  if (library == NULL || !library->selected_component || !library->selected_ready ||
      library->selected_api == NULL || !library->component_owned) return NULL;
  Dl_info origin;
  if (!dladdr(library->selected_api, &origin)) return NULL;
  actql_heap_wal_fn port = NULL;
  dlerror();
  *(void **)(&port) = dlsym(library->dynamic_library, symbol);
  return dlerror() == NULL && actql_component_origin((void *)port, origin.dli_fbase)
    ? port : NULL;
#else
  (void)library; (void)symbol;
  return NULL;
#endif
}

static void *actql_open_database(
  actql_native_sqlite_library *library,
  moonbit_bytes_t path,
  int32_t length,
  int64_t max_body_bytes,
  int mode,
  uint64_t expected_device,
  uint64_t expected_inode,
  bool journal_exclusive,
  actql_native_store_operation *store_operation
) {
  if (!actql_library_current(library) || (library != NULL && library->selected_component &&
      !actql_library_available(library))) return NULL;
  actql_native_sqlite_database *database = moonbit_make_external_object(
    actql_native_sqlite_database_finalize,
    sizeof(actql_native_sqlite_database)
  );
  memset(database, 0, sizeof(*database));
  database->library = library;
  database->process = getpid();
  if (library != NULL) {
    moonbit_incref(library);
    library->database_children++;
    database->library_child = true;
  }
  if (store_operation != NULL) {
    database->store_operation = store_operation;
    moonbit_incref(store_operation);
    store_operation->binding_attempted = true;
    store_operation->bound_database = database;
  }
  database->max_body_bytes = max_body_bytes;
  database->diagnostic_ceiling = library == NULL ? 0 : library->diagnostic_ceiling;
  if (!actql_library_available(library)) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "SQLite library is unavailable");
    return database;
  }
  actql_heap_wal_fn heap_wal = journal_exclusive
    ? actql_original_journal_wal_port(library, "actql_sqlite_component_heap_wal") : NULL;
  if (journal_exclusive) database->journal_descriptor_ack =
    actql_original_journal_wal_port(library, "actql_sqlite_component_descriptor_ack");
  if (journal_exclusive && (heap_wal == NULL || database->journal_descriptor_ack == NULL)) {
    actql_replace_error_for(library, &database->error, database->diagnostic_ceiling,
      "selected Journal heap-WAL observation is unavailable");
    return database;
  }
  bool contained = mode != 0;
  bool existing = mode == 1;
  if (contained && (length < 2 || length > 4096 || path[0] != '/' ||
      memchr(path, 0, (size_t)length) != NULL)) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "invalid existing database path");
    return database;
  }
  char *path_text = actql_copy_text_for(library, path, length);
  if (path_text == NULL) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "database path allocation failed");
    return database;
  }
  int pinned = -1;
  struct stat original;
  if (contained) {
    pinned = open(path_text, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (pinned < 0 || fstat(pinned, &original) != 0 ||
        !S_ISREG(original.st_mode) ||
        (existing ? original.st_size < 1 : original.st_size != 0) ||
        (mode == 2 && ((uint64_t)original.st_dev != expected_device ||
          (uint64_t)original.st_ino != expected_inode))) {
      if (pinned >= 0 && close(pinned) != 0 && journal_exclusive) {
        database->journal_pin_descriptor = pinned;
        database->journal_pin_close_unknown = true;
      }
      actql_adapter_free(library, path_text);
      actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "existing database is unavailable");
      return database;
    }
  }
  int flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX;
  flags |= contained ? SQLITE_OPEN_NOFOLLOW : SQLITE_OPEN_CREATE;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_OPEN, library->open_v2)(
    path_text,
    &database->database,
    flags,
    NULL
  );
  if (code == SQLITE_OK && contained) {
    struct stat selected;
    if (lstat(path_text, &selected) != 0 || !S_ISREG(selected.st_mode) ||
        selected.st_dev != original.st_dev || selected.st_ino != original.st_ino)
      code = SQLITE_CANTOPEN;
  }
  if (pinned >= 0 && close(pinned) != 0 && journal_exclusive) {
    database->journal_pin_descriptor = pinned;
    database->journal_pin_close_unknown = true;
    code = SQLITE_IOERR_CLOSE;
  }
  actql_adapter_free(library, path_text);
  if (code != SQLITE_OK) {
    actql_database_error(database, "open SQLite database failed");
    actql_retire_failed_open_database(database);
    return database;
  }
  code = library->busy_timeout(database->database, 5000);
  if (code != SQLITE_OK) {
    actql_database_error(database, "configure SQLite busy timeout failed");
    actql_retire_failed_open_database(database);
    return database;
  }
  /* This PRAGMA does not require schema loading in the pinned SQLite. It must
   * precede inspection_schema, user_version and the first WAL access. SQLite
   * still has to acquire its real exclusive lock at that first access. */
  if (journal_exclusive && !actql_select_journal_exclusive(database)) {
    actql_replace_error_for(library, &database->error, database->diagnostic_ceiling,
      "select original Journal exclusive locking failed");
    actql_retire_failed_open_database(database);
    return database;
  }
  // Restoration validates the retained schema. It cannot create tables,
  // migrate the format, or infer fresh custody from a missing record.
  database->opened = true;
  bool admitted = existing
    ? actql_native_sqlite_inspection_schema(database) != 0 &&
      actql_exec(database, "PRAGMA synchronous=FULL;PRAGMA foreign_keys=ON") == SQLITE_OK
    : actql_initialize_schema(database);
  if (!admitted) {
    actql_retire_failed_open_database(database);
    return database;
  }
  if (journal_exclusive && heap_wal(database->database) != ACTQL_SQLITE_COMPONENT_OK) {
    actql_replace_error_for(library, &database->error, database->diagnostic_ceiling,
      "original Journal did not acquire heap-backed exclusive WAL");
    actql_retire_failed_open_database(database);
    return database;
  }
  database->opened = true;
  return database;
}

void *actql_native_sqlite_open_database(
  actql_native_sqlite_library *library,
  moonbit_bytes_t path,
  int32_t length,
  int64_t max_body_bytes
) {
  return actql_open_database(library, path, length, max_body_bytes, 0, 0, 0, false, NULL);
}

void *actql_native_sqlite_open_existing_database(
  actql_native_sqlite_library *library,
  moonbit_bytes_t path,
  int32_t length,
  int64_t max_body_bytes
) {
  return actql_open_database(library, path, length, max_body_bytes, 1, 0, 0, false, NULL);
}

// Only the exact exclusively created, still-empty file may receive a schema.
// The Host must bind that physical proof to its durable one-time intent first.
void *actql_native_sqlite_initialize_owned_database(
  actql_native_sqlite_library *library,
  moonbit_bytes_t path,
  int32_t length,
  uint64_t device,
  uint64_t inode,
  int64_t max_body_bytes
) {
  return actql_open_database(library, path, length, max_body_bytes, 2, device, inode, false, NULL);
}

/* Selected original Local Result Store only. Its existing Store Owner retains
 * format, exclusive Root lock, original authority and cleanup. The same private
 * Library/heap may already retain the adoption Journal; no second heap/credit.
 * Select before any schema/WAL access, without changing generic open defaults. */
void *actql_native_sqlite_open_local_store_database(
  actql_native_sqlite_library *library, moonbit_bytes_t path, int32_t length,
  int64_t max_body_bytes
) {
  return actql_open_database(library, path, length, max_body_bytes, 0, 0, 0, true, NULL);
}

void *actql_native_sqlite_open_existing_local_store_database(
  actql_native_sqlite_library *library, moonbit_bytes_t path, int32_t length,
  int64_t max_body_bytes
) {
  return actql_open_database(library, path, length, max_body_bytes, 1, 0, 0, true, NULL);
}

void *actql_native_sqlite_open_existing_journal_database(
  actql_native_sqlite_library *library, moonbit_bytes_t path, int32_t length,
  int64_t max_body_bytes
) {
  return actql_open_database(library, path, length, max_body_bytes, 1, 0, 0, true, NULL);
}

void *actql_native_sqlite_initialize_owned_journal_database(
  actql_native_sqlite_library *library, moonbit_bytes_t path, int32_t length,
  uint64_t device, uint64_t inode, int64_t max_body_bytes
) {
  return actql_open_database(library, path, length, max_body_bytes, 2, device, inode, true, NULL);
}

/* Same original one-shot binding before the first Database acquisition. A
 * failed scope or open retains this original; it cannot mint a replacement. */
static void *actql_open_original_database(
  actql_native_sqlite_library *library, actql_native_store_operation *original,
  moonbit_bytes_t path, int32_t length, int64_t max_body_bytes, int32_t existing,
  bool journal_exclusive
) {
  if (!actql_store_operation_thread(original) || original->library != library ||
      original->closed || original->open_attempted || original->binding_attempted ||
      !original->activated || original->cleanup || original->failed ||
      !original->flight || original->sql || (existing != 0 && existing != 1)) return NULL;
  original->open_attempted = true;
  if (actql_store_operation_enter_sql(original, 0) != 0) return NULL;
  void *database = actql_open_database(library, path, length, max_body_bytes,
    existing, 0, 0, journal_exclusive, original);
  /* Keep SQL entered until the typed caller has captured this exact ready or
   * failed-open reply and diagnostic. Its explicit finish then returns Read. */
  return database;
}

MOONBIT_FFI_EXPORT void *actql_native_sqlite_open_original_store_database(
  actql_native_sqlite_library *library, actql_native_store_operation *original,
  moonbit_bytes_t path, int32_t length, int64_t max_body_bytes, int32_t existing
) {
  return actql_open_original_database(library, original, path, length,
    max_body_bytes, existing, true);
}

/* The fixed Remote coordinator retains its own original physical scope. This
 * entrance preserves generic open/restore policy; it selects no Local WAL or
 * Host/business supplier and grants no scope merely from a path or label. */
MOONBIT_FFI_EXPORT void *actql_native_sqlite_open_original_remote_database(
  actql_native_sqlite_library *library, actql_native_store_operation *original,
  moonbit_bytes_t path, int32_t length, int64_t max_body_bytes, int32_t existing
) {
  return actql_open_original_database(library, original, path, length,
    max_body_bytes, existing, false);
}

MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_database_acquired(
    actql_native_sqlite_database *database) {
  return database != NULL;
}

MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_store_operation_has_no_database(
    actql_native_store_operation *original) {
  return actql_store_operation_thread(original) && !original->closed &&
    !original->binding_attempted && original->bound_database == NULL;
}

// Whitebox-only loss of one schema constituent in an owner-created fixture.
int32_t actql_native_sqlite_test_drop_capacity(
  actql_native_sqlite_database *database
) {
  return database != NULL && database->opened &&
    actql_exec(database, "DROP TABLE actql_capacity") == SQLITE_OK;
}

int32_t actql_native_sqlite_database_ready(
  actql_native_sqlite_database *database
) {
  return database != NULL && database->opened && actql_database_library_available(database->library);
}

/* Observe retained DATA custody while its existing caller holds the Host and
 * capture facts. No entered Read, SQL, callback, permission or ACK is issued. */
MOONBIT_FFI_EXPORT int32_t actql_native_sqlite_database_retained_data_current(
    actql_native_sqlite_database *database) {
  if (database == NULL || database->process != getpid() ||
      !database->opened || database->database == NULL) return 1;
  actql_native_sqlite_library *library = database->library;
  if (library == NULL || library->dynamic_library == NULL || library->closing ||
      (library->selected_component && (!library->selected_ready ||
       library->selected_process != getpid()))) return 2;
  if (database->transaction_fenced || database->journal_pin_close_unknown) return 3;
  actql_native_store_operation *original = database->store_operation;
  if (original != NULL) {
    if (!actql_store_operation_thread(original) || original->closed ||
        !original->activated || original->bound_database != database ||
        original->library != library || original->database_closed ||
        original->failed || original->cleanup_only) return 4;
    if (original->calling || original->flight || original->sql) return 3;
  }
  return 0;
}

moonbit_bytes_t actql_native_sqlite_database_error(
  actql_native_sqlite_database *database
) {
  return database == NULL || !actql_library_current(database->library) ? actql_copy_bytes(NULL, 0) :
    actql_copy_diagnostic(database->error, database->diagnostic_ceiling);
}

static int32_t actql_database_read(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t caller_body_limit,
  int exact_extent, int64_t expected_revision, int64_t expected_bytes
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  actql_clear_result(database);
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    exact_extent ?
      "SELECT revision, body, typeof(body) = 'blob' FROM actql_records WHERE namespace = ?1 AND record_key = ?2" :
      "SELECT revision, body FROM actql_records WHERE namespace = ?1 AND record_key = ?2",
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if (code == SQLITE_DONE) {
      result = 1;
    } else if (code != SQLITE_ROW) {
      actql_database_error(database, "read journal record failed");
      result = actql_operation_code(code);
    } else {
      int length = database->library->column_bytes(statement, 1);
      sqlite3_int64 revision = database->library->column_int64(statement, 0);
      if (revision < 0 || length < 0 || (!exact_extent && length > database->max_body_bytes) ||
          length > INT32_MAX) {
        actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "invalid stored journal record");
        result = -1;
      } else if (exact_extent &&
          (revision != expected_revision || length != expected_bytes ||
           database->library->column_int64(statement, 2) != 1)) {
        result = 2;
      } else if (caller_body_limit >= 0 && length > caller_body_limit) {
        result = 4;
      } else {
        const void *body = database->library->column_blob(statement, 1);
        unsigned char *copy = length == 0 ? NULL : actql_adapter_allocate(database->library, (size_t)length);
        if (length > 0 && copy == NULL) {
          actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "journal body allocation failed");
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

// Header lookup does not call column_blob or allocate an adapter/Moon body
// copy. The original database's body ceiling and row validation still apply.
static int32_t actql_database_read_header(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length, int observed_extent
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  actql_clear_result(database);
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "SELECT revision, length(body), typeof(body) = 'blob' FROM actql_records "
    "WHERE namespace = ?1 AND record_key = ?2", -1, &statement, NULL);
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare journal header failed");
    return actql_operation_code(code);
  }
  int32_t result = actql_bind_key(database, statement, 1, namespace_bytes,
    namespace_length, 2, key, key_length);
  int64_t revision = 0, length = 0;
  if (result == 0) {
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if (code == SQLITE_DONE) result = 1;
    else if (code != SQLITE_ROW) {
      actql_database_error(database, "read journal header failed");
      result = actql_operation_code(code);
    } else {
      revision = (int64_t)database->library->column_int64(statement, 0);
      length = (int64_t)database->library->column_int64(statement, 1);
      int64_t blob = (int64_t)database->library->column_int64(statement, 2);
      if (revision < 0 || length < 0 || (!observed_extent && length > database->max_body_bytes) ||
          length > INT32_MAX || blob != 1) {
        actql_replace_error_for(database->library, &database->error,
          database->diagnostic_ceiling, "invalid stored journal header");
        result = -1;
      }
    }
  }
  int finalized = database->library->finalize(statement);
  if (finalized != SQLITE_OK) {
    actql_database_error(database, "finalize journal header failed");
    return actql_operation_code(finalized);
  }
  if (result == 0) {
    database->result_revision = revision;
    database->result_header_body_bytes = length;
  }
  return result;
}

int32_t actql_native_sqlite_database_read_header(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length
) {
  return actql_database_read_header(database, namespace_bytes, namespace_length, key, key_length, 0);
}

// Metadata only: no body copy, reservation or read permission.
int32_t actql_native_sqlite_database_observe_body_extent(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length
) {
  return actql_database_read_header(database, namespace_bytes, namespace_length, key, key_length, 1);
}

int64_t actql_native_sqlite_database_result_header_body_bytes(
  actql_native_sqlite_database *database
) {
  return database == NULL || !actql_library_current(database->library) ? 0 : database->result_header_body_bytes;
}

int32_t actql_native_sqlite_database_read(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length
) {
  return actql_database_read(database, namespace_bytes, namespace_length,
    key, key_length, -1, 0, 0, 0);
}

// A caller ceiling is only a physical copy bound, never a reservation or permit.
int32_t actql_native_sqlite_database_read_with_body_limit(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t max_body_bytes
) {
  if (max_body_bytes < 0) return 4;
  return actql_database_read(database, namespace_bytes, namespace_length,
    key, key_length, max_body_bytes, 0, 0, 0);
}


// Copy only the SAME observed revision/type/extent. The caller must have
// acquired its actual Read/SQLite backing before entering this operation.
int32_t actql_native_sqlite_database_read_exact_body_extent(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length,
  int64_t revision, int64_t body_bytes
) {
  if (revision < 0 || body_bytes < 0 || body_bytes > INT32_MAX) return 4;
  return actql_database_read(database, namespace_bytes, namespace_length,
    key, key_length, body_bytes, 1, revision, body_bytes);
}

static int32_t actql_database_scan_after(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t after_key,
  int32_t after_key_length,
  int64_t caller_body_limit
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->test_name_scan_refusal && namespace_length == 23 &&
      memcmp(namespace_bytes, "client_submission_names", 23) == 0) return -1;
  actql_clear_result(database);
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
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
        actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "invalid stored journal record");
        result = -1;
      } else if (caller_body_limit >= 0 && body_length > caller_body_limit) {
        result = 4;
      } else {
        unsigned char *key_copy = actql_adapter_allocate(database->library, (size_t)key_length);
        unsigned char *body_copy = body_length == 0
          ? NULL
          : actql_adapter_allocate(database->library, (size_t)body_length);
        if (key_copy == NULL || (body_length > 0 && body_copy == NULL)) {
          actql_adapter_free(database->library, key_copy);
          actql_adapter_free(database->library, body_copy);
          actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "journal scan allocation failed");
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

int32_t actql_native_sqlite_database_scan_after(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t after_key,
  int32_t after_key_length
) {
  return actql_database_scan_after(database, namespace_bytes, namespace_length,
    after_key, after_key_length, -1);
}

// A caller ceiling is only a physical copy bound, never a reservation or permit.
int32_t actql_native_sqlite_database_scan_after_with_body_limit(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t after_key,
  int32_t after_key_length,
  int64_t max_body_bytes
) {
  if (max_body_bytes < 0) return 4;
  return actql_database_scan_after(database, namespace_bytes, namespace_length,
    after_key, after_key_length, max_body_bytes);
}

static int32_t actql_database_insert(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  moonbit_bytes_t body,
  int32_t body_length,
  int64_t body_extent
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  if (body_length < 0 || (int64_t)body_length >
      (body_extent < 0 ? database->max_body_bytes : body_extent)) {
    return 4;
  }
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
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

int32_t actql_native_sqlite_database_insert(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length,
  moonbit_bytes_t body, int32_t body_length
) {
  return actql_database_insert(database, namespace_bytes, namespace_length, key, key_length, body, body_length, -1);
}

// The enclosing caller owns/backed these exact bytes. This grants no capacity,
// mutates no Database ceiling and acknowledges no transaction COMMIT.
int32_t actql_native_sqlite_database_insert_with_body_extent(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length,
  moonbit_bytes_t body, int32_t body_length,
  int64_t body_extent
) {
  if (body_extent < 0 || body_extent != body_length) return 4;
  return actql_database_insert(database, namespace_bytes, namespace_length, key, key_length, body, body_length, body_extent);
}

static int32_t actql_database_compare_exchange(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t expected_revision,
  moonbit_bytes_t body,
  int32_t body_length,
  int64_t body_extent
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  if (body_length < 0 || (int64_t)body_length >
      (body_extent < 0 ? database->max_body_bytes : body_extent)) {
    return 4;
  }
  if (expected_revision < 0 || expected_revision == INT64_MAX) return 2;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if ((code & 0xff) == SQLITE_CONSTRAINT) {
      result = 2;
    } else if (code != SQLITE_DONE) {
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

int32_t actql_native_sqlite_database_compare_exchange(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length,
  int64_t expected_revision,
  moonbit_bytes_t body, int32_t body_length
) {
  return actql_database_compare_exchange(database, namespace_bytes, namespace_length, key, key_length, expected_revision, body, body_length, -1);
}

// The enclosing caller owns/backed these exact bytes. This grants no capacity,
// mutates no Database ceiling and acknowledges no transaction COMMIT.
int32_t actql_native_sqlite_database_compare_exchange_with_body_extent(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length,
  int64_t expected_revision,
  moonbit_bytes_t body, int32_t body_length,
  int64_t body_extent
) {
  if (body_extent < 0 || body_extent != body_length) return 4;
  return actql_database_compare_exchange(database, namespace_bytes, namespace_length, key, key_length, expected_revision, body, body_length, body_extent);
}

// Exact retirement only: the caller owns an active transaction and must
// separately confirm commit/readback before settling its original reservation.
int32_t actql_native_sqlite_database_remove_exact(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length,
  int64_t expected_revision, moonbit_bytes_t body, int32_t body_length
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  if (database->transaction_fenced ||
      database->library->get_autocommit(database->database)) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "exact retirement requires an unfenced transaction");
    return 4;
  }
  if (body_length < 0 || (int64_t)body_length > database->max_body_bytes) return 4;
  if (expected_revision < 0) return 2;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "DELETE FROM actql_records WHERE namespace = ?1 AND record_key = ?2 "
    "AND revision = ?3 AND body = ?4", -1, &statement, NULL);
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare exact journal retirement failed");
    return actql_operation_code(code);
  }
  int32_t result = actql_bind_key(database, statement, 1,
    namespace_bytes, namespace_length, 2, key, key_length);
  if (result == 0) {
    code = database->library->bind_int64(statement, 3, expected_revision);
    if (code == SQLITE_OK) {
      code = database->library->bind_blob(statement, 4, body, body_length, SQLITE_TRANSIENT);
    }
    if (code != SQLITE_OK) {
      actql_database_error(database, "bind exact journal retirement failed");
      result = actql_operation_code(code);
    }
  }
  if (result == 0) {
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if (code != SQLITE_DONE) {
      actql_database_error(database, "exact journal retirement failed");
      result = actql_operation_code(code);
    } else if (database->library->changes64(database->database) != 1) {
      result = 2;
    }
  }
  int finalized = database->library->finalize(statement);
  if (result == 0 && finalized != SQLITE_OK) {
    actql_database_error(database, "finalize exact journal retirement failed");
    result = actql_operation_code(finalized);
  }
  return result;
}

// Test-only physical custody-loss injection. Production exact retirement
// requires its original transaction/revision/body and cannot repair issuance.
int32_t actql_native_sqlite_test_remove_journal_record(
    actql_native_sqlite_database *database,
    moonbit_bytes_t namespace_bytes, int32_t namespace_length,
    moonbit_bytes_t key, int32_t key_length) {
  if (database == NULL || !database->opened) return 0;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "DELETE FROM actql_records WHERE namespace = ?1 AND record_key = ?2",
    -1, &statement, NULL);
  if (code != SQLITE_OK) return 0;
  int bound = actql_bind_key(database, statement, 1, namespace_bytes,
    namespace_length, 2, key, key_length);
  int removed = bound == 0 && ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement) == SQLITE_DONE &&
    database->library->changes64(database->database) == 1;
  int finalized = database->library->finalize(statement);
  return removed && finalized == SQLITE_OK;
}

// A deferred physical snapshot, matching the existing byte-store BEGIN.
// It neither writes nor commits a row and must retain its original stop ACK.
int32_t actql_native_sqlite_database_begin_deferred(
  actql_native_sqlite_database *database
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  int code = actql_exec(database, "BEGIN");
  return code == SQLITE_OK ? 0 : actql_operation_code(code);
}

int32_t actql_native_sqlite_database_begin_immediate(
  actql_native_sqlite_database *database
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  int code = actql_exec(database, "BEGIN IMMEDIATE");
  return code == SQLITE_OK ? 0 : actql_operation_code(code);
}

// An adapter that cannot confirm commit/rollback fences this physical handle.
// There is deliberately no reset: a new handle still requires durable-state
// reconciliation by its owning adapter, never an assumption of non-execution.
void actql_native_sqlite_database_fence_transactions(
    actql_native_sqlite_database *database) {
  if (database != NULL && actql_library_current(database->library)) database->transaction_fenced = 1;
}

int32_t actql_native_sqlite_database_transaction_fenced(
    actql_native_sqlite_database *database) {
  return database == NULL || !actql_library_current(database->library) || database->transaction_fenced;
}

// Observe the same opened connection. A failed observation is never the
// autocommit/no-active result, and this does not clear an uncertainty fence.
int32_t actql_native_sqlite_database_transaction_state(
  actql_native_sqlite_database *database
) {
  if (database == NULL || !database->opened || database->database == NULL ||
      !actql_database_library_available(database->library)) return -1;
  return database->library->get_autocommit(database->database) ? 0 : 1;
}

int32_t actql_native_sqlite_database_commit(
  actql_native_sqlite_database *database
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  if (database->test_commit_skip > 0) {
    database->test_commit_skip--;
    int code = actql_exec(database, "COMMIT");
    return code == SQLITE_OK ? 0 : actql_operation_code(code);
  }
  if (database->test_commit_failures > 0) {
    database->test_commit_failures--;
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "injected transaction commit failure");
    return 4;
  }
  int code = actql_exec(database, "COMMIT");
  if (code == SQLITE_OK && database->test_commit_reply_failures > 0) {
    database->test_commit_reply_failures--;
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "injected lost transaction commit reply");
    return 4;
  }
  return code == SQLITE_OK ? 0 : actql_operation_code(code);
}

int32_t actql_native_sqlite_database_rollback(
  actql_native_sqlite_database *database
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  int code = actql_exec(database, "ROLLBACK");
  return code == SQLITE_OK ? 0 : actql_operation_code(code);
}

static void actql_capacity_rollback(
  actql_native_sqlite_database *database
) {
  ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_EXEC, database->library->exec)(database->database, "ROLLBACK", NULL, NULL, NULL);
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
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
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
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
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
  int64_t max_objects,
  int32_t caller_transaction
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  if (reserved_bytes < 0 || reserved_objects < 0 || max_bytes < 0 ||
      max_objects < 0 || reserved_bytes > max_bytes ||
      reserved_objects > max_objects) {
    return 6;
  }
  // An explicit caller transaction owns both the reservation and its record.
  // Never commit or roll it back here; the caller retains any uncertain state.
  const bool owns_transaction = caller_transaction == 0;
  if (!owns_transaction &&
      database->library->get_autocommit(database->database) != 0) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling, "capacity reservation requires an active transaction");
    return -1;
  }
  int32_t result = owns_transaction ? actql_capacity_begin(database) : 0;
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
      if (owns_transaction) actql_capacity_rollback(database);
      return 2;
    }
    result = owns_transaction ? actql_capacity_commit(database) : 0;
    return result == 0 ? 7 : result;
  }
  if (result != 1) {
    if (owns_transaction) actql_capacity_rollback(database);
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
    if (owns_transaction) actql_capacity_rollback(database);
    return result;
  }
  if (used_bytes < 0 || used_objects < 0 || used_bytes > max_bytes ||
      used_objects > max_objects || reserved_bytes > max_bytes - used_bytes ||
      reserved_objects > max_objects - used_objects) {
    if (owns_transaction) actql_capacity_rollback(database);
    return 6;
  }
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
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
    if (owns_transaction) actql_capacity_rollback(database);
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
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
    if (owns_transaction) actql_capacity_rollback(database);
    return result;
  }
  return owns_transaction ? actql_capacity_commit(database) : 0;
}

static int32_t actql_database_release_capacity(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t reserved_bytes,
  int64_t reserved_objects,
  bool caller_transaction
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  if (reserved_bytes < 0 || reserved_objects < 0) return 2;
  const bool owns_transaction = !caller_transaction;
  if (caller_transaction && database->library->get_autocommit(database->database) != 0) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling,
      "capacity release requires an active transaction");
    return -1;
  }
  int32_t result = owns_transaction ? actql_capacity_begin(database) : 0;
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
    result = owns_transaction ? actql_capacity_commit(database) : 0;
    return result == 0 ? 7 : result;
  }
  if (result != 0 || existing_bytes != reserved_bytes ||
      existing_objects != reserved_objects) {
    if (owns_transaction) actql_capacity_rollback(database);
    return result == 0 ? 2 : result;
  }
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "DELETE FROM actql_capacity WHERE namespace = ?1 "
    "AND reservation_key = ?2",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare capacity release failed");
    if (owns_transaction) actql_capacity_rollback(database);
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
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
    if (owns_transaction) actql_capacity_rollback(database);
    return result;
  }
  return owns_transaction ? actql_capacity_commit(database) : 0;
}

int32_t actql_native_sqlite_database_release_capacity(
  actql_native_sqlite_database *database, moonbit_bytes_t scope, int32_t scope_length,
  moonbit_bytes_t key, int32_t key_length, int64_t bytes, int64_t objects
) {
  return actql_database_release_capacity(database, scope, scope_length, key, key_length,
    bytes, objects, false);
}

int32_t actql_native_sqlite_database_release_capacity_in_transaction(
  actql_native_sqlite_database *database, moonbit_bytes_t scope, int32_t scope_length,
  moonbit_bytes_t key, int32_t key_length, int64_t bytes, int64_t objects
) {
  return actql_database_release_capacity(database, scope, scope_length, key, key_length,
    bytes, objects, true);
}

// Original-claim observation only: no BEGIN/COMMIT, INSERT, reservation or
// ordinal allocation. Finalize must acknowledge both presence and absence.
int32_t actql_native_sqlite_database_lookup_claim_ordinal(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  actql_clear_result(database);
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "SELECT ordinal, typeof(ordinal) = 'integer' FROM actql_claims "
    "WHERE namespace = ?1 AND claim_key = ?2",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare original claim lookup failed");
    if (statement != NULL) database->library->finalize(statement);
    return actql_operation_code(code);
  }
  int32_t result = actql_bind_key(
    database, statement, 1, namespace_bytes, namespace_length, 2, key, key_length
  );
  int64_t ordinal = 0;
  if (result == 0) {
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if (code == SQLITE_DONE) {
      result = 1;
    } else if (code != SQLITE_ROW) {
      actql_database_error(database, "read original claim failed");
      result = actql_operation_code(code);
    } else {
      ordinal = (int64_t)database->library->column_int64(statement, 0);
      // Do not silently coerce a malformed TEXT/FLOAT original to an integer.
      if (ordinal <= 0 || database->library->column_int64(statement, 1) != 1) {
        actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling,
                            "invalid original claim ordinal");
        result = -1;
      }
    }
  }
  // SQLite destroys the statement even when finalize reports an error:
  // https://www.sqlite.org/c3ref/finalize.html
  int finalize_code = database->library->finalize(statement);
  if ((result == 0 || result == 1) && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize original claim lookup failed");
    return actql_operation_code(finalize_code);
  }
  if (result == 0) database->result_revision = ordinal;
  return result;
}

static int32_t actql_claim_ordinal(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length,
  moonbit_bytes_t key,
  int32_t key_length,
  int64_t max_claims,
  bool caller_transaction
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  if (database->lookup_generation != 0) return -1;
  actql_clear_result(database);
  if (max_claims <= 0) return 6;
  // Caller mode never begins, commits or rolls back the owning journal TX.
  // No autocommit fallback can split an ordinal from its original use row.
  const bool owns_transaction = !caller_transaction;
  if (caller_transaction && (database->transaction_fenced ||
      database->library->get_autocommit(database->database) != 0)) {
    actql_replace_error_for(database->library, &database->error, database->diagnostic_ceiling,
                        "claim requires an active unfenced caller transaction");
    return -1;
  }
  int32_t result = owns_transaction ? actql_capacity_begin(database) : 0;
  if (result != 0) return result;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "SELECT ordinal FROM actql_claims "
    "WHERE namespace = ?1 AND claim_key = ?2",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare bounded claim read failed");
    if (owns_transaction) actql_capacity_rollback(database);
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
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if (code == SQLITE_ROW) {
      database->result_revision = (int64_t)database->library->column_int64(
        statement,
        0
      );
      result = database->result_revision > 0 ? 7 : -1;
    } else if (code != SQLITE_DONE) {
      actql_database_error(database, "read bounded claim failed");
      result = actql_operation_code(code);
    }
  }
  int finalize_code = database->library->finalize(statement);
  statement = NULL;
  if (result == 7) {
    if (caller_transaction && finalize_code != SQLITE_OK) {
      actql_database_error(database, "finalize retained caller claim failed");
      return actql_operation_code(finalize_code);
    }
    int32_t commit = owns_transaction ? actql_capacity_commit(database) : 0;
    return commit == 0 ? 7 : commit;
  }
  if (result != 0 || finalize_code != SQLITE_OK) {
    if (result == 0) {
      actql_database_error(database, "finalize bounded claim read failed");
      result = actql_operation_code(finalize_code);
    }
    if (owns_transaction) actql_capacity_rollback(database);
    return result;
  }
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "SELECT COALESCE(MAX(ordinal), 0) FROM actql_claims "
    "WHERE namespace = ?1",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare bounded claim count failed");
    if (owns_transaction) actql_capacity_rollback(database);
    return actql_operation_code(code);
  }
  code = database->library->bind_text(
    statement,
    1,
    (const char *)namespace_bytes,
    namespace_length,
    SQLITE_TRANSIENT
  );
  int64_t prior = 0;
  if (code == SQLITE_OK) code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  if (code == SQLITE_ROW) {
    prior = (int64_t)database->library->column_int64(statement, 0);
  } else {
    actql_database_error(database, "count bounded claims failed");
    result = actql_operation_code(code);
  }
  finalize_code = database->library->finalize(statement);
  statement = NULL;
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize bounded claim count failed");
    result = actql_operation_code(finalize_code);
  }
  if (result != 0) {
    if (owns_transaction) actql_capacity_rollback(database);
    return result;
  }
  if (prior < 0 || prior >= max_claims || prior == INT64_MAX) {
    if (owns_transaction) actql_capacity_rollback(database);
    return 6;
  }
  int64_t ordinal = prior + 1;
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "INSERT INTO actql_claims(namespace, claim_key, ordinal) "
    "VALUES(?1, ?2, ?3)",
    -1,
    &statement,
    NULL
  );
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare bounded claim insert failed");
    if (owns_transaction) actql_capacity_rollback(database);
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
    code = database->library->bind_int64(
      statement,
      3,
      (sqlite3_int64)ordinal
    );
    if (code == SQLITE_OK) code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if (code != SQLITE_DONE) {
      actql_database_error(database, "insert bounded claim failed");
      result = actql_operation_code(code);
    }
  }
  finalize_code = database->library->finalize(statement);
  if (result == 0 && finalize_code != SQLITE_OK) {
    actql_database_error(database, "finalize bounded claim insert failed");
    result = actql_operation_code(finalize_code);
  }
  if (result != 0) {
    if (owns_transaction) actql_capacity_rollback(database);
    return result;
  }
  result = owns_transaction ? actql_capacity_commit(database) : 0;
  if (result == 0) database->result_revision = ordinal;
  return result;
}

// Existing self-owned ABI and transaction behavior are unchanged.
int32_t actql_native_sqlite_database_claim_ordinal(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length, int64_t max_claims
) {
  return actql_claim_ordinal(database, namespace_bytes, namespace_length,
                            key, key_length, max_claims, false);
}

int32_t actql_native_sqlite_database_claim_ordinal_in_transaction(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length, int64_t max_claims
) {
  return actql_claim_ordinal(database, namespace_bytes, namespace_length,
                            key, key_length, max_claims, true);
}

// Read an existing reservation without acquiring, refreshing or releasing it.
// Absence and SQL/finalize failure retain their distinct existing result codes.
int32_t actql_native_sqlite_database_read_capacity(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes, int32_t namespace_length,
  moonbit_bytes_t key, int32_t key_length
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  actql_clear_result(database);
  int64_t bytes = 0, objects = 0;
  int32_t result = actql_capacity_existing(database, namespace_bytes,
    namespace_length, key, key_length, &bytes, &objects);
  if (result == 0) {
    database->result_capacity_bytes = bytes;
    database->result_capacity_objects = objects;
  }
  return result;
}

// One SQLite statement observes this database's physical totals, including
// private rows when the same connection has a caller-owned transaction. It
// copies no row body and never begins, commits or rolls back that transaction.
int32_t actql_native_sqlite_database_usage(
  actql_native_sqlite_database *database
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
  actql_clear_result(database);
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "SELECT COUNT(*), COALESCE(SUM(length(body)), 0), "
    "(SELECT COUNT(*) FROM actql_capacity) FROM actql_records",
    -1, &statement, NULL);
  if (code != SQLITE_OK) {
    actql_database_error(database, "prepare database usage failed");
    return actql_operation_code(code);
  }
  int32_t result = 0;
  int64_t records = 0, bytes = 0, reservations = 0;
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  if (code == SQLITE_ROW) {
    records = (int64_t)database->library->column_int64(statement, 0);
    bytes = (int64_t)database->library->column_int64(statement, 1);
    reservations = (int64_t)database->library->column_int64(statement, 2);
    if (records < 0 || bytes < 0 || reservations < 0) {
      actql_replace_error_for(database->library, &database->error,
        database->diagnostic_ceiling, "invalid database usage totals");
      result = -1;
    }
  } else {
    actql_database_error(database, "read database usage failed");
    result = actql_operation_code(code);
  }
  int finalized = database->library->finalize(statement);
  if (finalized != SQLITE_OK) {
    actql_database_error(database, "finalize database usage failed");
    return actql_operation_code(finalized);
  }
  if (result == 0) {
    database->result_record_count = records;
    database->result_record_body_bytes = bytes;
    database->result_reservation_count = reservations;
  }
  return result;
}

int64_t actql_native_sqlite_database_result_record_count(
  actql_native_sqlite_database *database
) {
  return database == NULL || !actql_library_current(database->library) ? 0 : database->result_record_count;
}

int64_t actql_native_sqlite_database_result_record_body_bytes(
  actql_native_sqlite_database *database
) {
  return database == NULL || !actql_library_current(database->library) ? 0 : database->result_record_body_bytes;
}

int64_t actql_native_sqlite_database_result_reservation_count(
  actql_native_sqlite_database *database
) {
  return database == NULL || !actql_library_current(database->library) ? 0 : database->result_reservation_count;
}

int32_t actql_native_sqlite_database_capacity_usage(
  actql_native_sqlite_database *database,
  moonbit_bytes_t namespace_bytes,
  int32_t namespace_length
) {
  if (database == NULL || !database->opened || !actql_database_library_available(database->library)) return 5;
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
  return database == NULL || !actql_library_current(database->library) ? 0 : database->result_capacity_bytes;
}

int64_t actql_native_sqlite_database_result_capacity_objects(
  actql_native_sqlite_database *database
) {
  return database == NULL || !actql_library_current(database->library) ? 0 : database->result_capacity_objects;
}

int64_t actql_native_sqlite_database_result_revision(
  actql_native_sqlite_database *database
) {
  return database == NULL || !actql_library_current(database->library) ? 0 : database->result_revision;
}

moonbit_bytes_t actql_native_sqlite_database_result_body(
  actql_native_sqlite_database *database
) {
  if (database == NULL || !actql_library_current(database->library)) return actql_copy_bytes(NULL, 0);
  return actql_copy_bytes(database->result_body, database->result_body_length);
}

moonbit_bytes_t actql_native_sqlite_database_result_key(
  actql_native_sqlite_database *database
) {
  if (database == NULL || !actql_library_current(database->library)) return actql_copy_bytes(NULL, 0);
  return actql_copy_bytes(database->result_key, database->result_key_length);
}

void actql_native_sqlite_close_database(
  actql_native_sqlite_database *database
) {
  if (database != NULL) actql_native_sqlite_database_close(database);
}

#include "sqlite_selected_component.inc"

// A generation is issued only after the original fenced connection has
// physically established NoActive. No token is accepted from the wire.
int64_t actql_native_sqlite_lookup_claim(actql_native_sqlite_database *database) {
  if (database == NULL || !database->opened || database->process != getpid() ||
      !actql_database_library_available(database->library) ||
      !database->transaction_fenced || database->lookup_generation != 0 ||
      database->lookup_sequence == INT64_MAX ||
      !database->library->get_autocommit(database->database)) return 0;
  database->lookup_generation = ++database->lookup_sequence;
  database->lookup_start_attempted = false;
  database->lookup_begin_attempted = false;
  database->lookup_ready = false;
  database->lookup_stop_attempted = false;
  return database->lookup_generation;
}

static bool actql_lookup_original(actql_native_sqlite_database *database,
                                 int64_t generation) {
  return database != NULL && database->opened && database->process == getpid() &&
    database->library != NULL && database->library->dynamic_library != NULL &&
    actql_library_current(database->library) && generation > 0 &&
    generation == database->lookup_generation && database->transaction_fenced;
}

int32_t actql_native_sqlite_lookup_current(actql_native_sqlite_database *database,
                                         int64_t generation) {
  return actql_lookup_original(database, generation) &&
    actql_database_library_available(database->library) &&
    !database->test_lookup_current_failure && database->lookup_ready &&
    !database->lookup_stop_attempted &&
    !database->library->get_autocommit(database->database);
}

int32_t actql_native_sqlite_lookup_start(actql_native_sqlite_database *database,
                                       int64_t generation) {
  if (!actql_lookup_original(database, generation) ||
      !actql_database_library_available(database->library) ||
      database->lookup_start_attempted ||
      !database->library->get_autocommit(database->database)) return -1;
  database->lookup_start_attempted = true;
  // This connection is permanently fenced. query_only is never reset, and
  // ordinary entry points cannot end/replace the read child's transaction.
  int code = actql_exec(database, "PRAGMA query_only=ON");
  if (code != SQLITE_OK) return actql_operation_code(code);
  sqlite3_stmt *statement = NULL;
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "PRAGMA query_only", -1, &statement, NULL);
  if (code != SQLITE_OK) return actql_operation_code(code);
  int stepped = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  bool enforced = stepped == SQLITE_ROW &&
    database->library->column_int64(statement, 0) == 1;
  int finalized = database->library->finalize(statement);
  if (!enforced || finalized != SQLITE_OK) return -1;
  if (database->test_lookup_before_begin > 0) {
    database->test_lookup_before_begin--;
    return -1;
  }
  database->lookup_begin_attempted = true;
  database->test_lookup_begin_count++;
  code = actql_exec(database, "BEGIN");
  if (code != SQLITE_OK) return actql_operation_code(code);
  // BEGIN alone does not pin an SQLite snapshot. Read the original database
  // before reporting readiness; subsequent payload/metadata reads share it.
  code = actql_exec(database, "SELECT count(*) FROM sqlite_schema");
  if (code != SQLITE_OK) return actql_operation_code(code);
  database->lookup_ready = true;
  if (database->test_lookup_start_reply > 0) {
    database->test_lookup_start_reply--;
    return -1;
  }
  return 0;
}

int32_t actql_native_sqlite_lookup_stop(actql_native_sqlite_database *database,
                                      int64_t generation) {
  if (!actql_lookup_original(database, generation)) return -1;
  // Current loss invalidates observations, but does not create another child
  // or authorize SQL on a foreign process/context. Original cleanup retries
  // inspect this same read attempt, never repeat BEGIN or a lost ROLLBACK.
  bool was_stopped = database->lookup_stop_attempted;
  database->lookup_stop_attempted = true;
  database->lookup_ready = false;
  if (!database->library->get_autocommit(database->database)) {
    if (!database->lookup_begin_attempted || was_stopped) return -1;
    if (database->test_lookup_stop_failure > 0) {
      database->test_lookup_stop_failure--;
      // A known pre-SQL refusal is not a lost physical attempt.
      database->lookup_stop_attempted = false;
      return -1;
    }
    database->test_lookup_stop_count++;
    int code = actql_exec(database, "ROLLBACK");
    if (code != SQLITE_OK) return actql_operation_code(code);
    if (database->test_lookup_stop_reply > 0) {
      database->test_lookup_stop_reply--;
      return -1;
    }
  }
  if (!database->library->get_autocommit(database->database)) return -1;
  actql_clear_result(database);
  database->lookup_generation = 0;
  if (database->test_lookup_poststop > 0) {
    database->test_lookup_poststop--;
    database->test_lookup_current_failure = 1;
  }
  return 0;
}

// Whitebox faults/counters affect only a caller-owned diagnostic database.
void actql_native_sqlite_test_lookup_fault(actql_native_sqlite_database *database,
                                         int32_t kind) {
  if (kind == 1) database->test_lookup_start_reply = 1;
  if (kind == 2) database->test_lookup_stop_reply = 1;
  if (kind == 3) database->test_lookup_stop_failure = 1;
  if (kind == 4) database->test_lookup_current_failure = 1;
  if (kind == 5) database->test_lookup_current_failure = 0;
  if (kind == 6) database->test_lookup_before_begin = 1;
  if (kind == 7) database->test_lookup_poststop = 1;
}
int32_t actql_native_sqlite_test_lookup_count(actql_native_sqlite_database *database,
                                           int32_t kind) {
  return kind == 1 ? database->test_lookup_begin_count : database->test_lookup_stop_count;
}

int32_t actql_native_sqlite_lookup_stopped_current(
    actql_native_sqlite_database *database, int64_t generation) {
  return database != NULL && database->opened && database->process == getpid() &&
    actql_database_library_available(database->library) &&
    !database->test_lookup_current_failure && generation > 0 &&
    database->lookup_sequence == generation && database->lookup_generation == 0 &&
    database->library->get_autocommit(database->database);
}

#include "journal_name_inventory.h"
#include "journal_run_definition.h"

/* Collision diagnosis only, under the caller's existing transaction and
 * already admitted exact index. The returned locator authenticates no Run. */
MOONBIT_FFI_EXPORT int32_t actql_native_client_run_definition_key(
    actql_native_sqlite_database *database, moonbit_bytes_t definition,
    int32_t length) {
  if (!actql_run_definition_database_current(database)) return 5;
  if (definition == NULL || length < 1 || length > 512 ||
      memchr(definition, 0, (size_t)length) != NULL) return 6;
  if (database->library->get_autocommit(database->database)) return -1;
  actql_clear_result(database);
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY,
    database->library->prepare_v2)(database->database,
    "SELECT record_key FROM actql_records INDEXED BY actql_client_run_definition_unique "
    "WHERE namespace='client_runs' AND "
    "json_extract(json_extract(CAST(body AS TEXT),'$.run_definition'),"
    "'$.run_definition_cid')=?1 LIMIT 2", -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    actql_database_error(database, "prepare Run definition locator failed");
    return actql_operation_code(code);
  }
  code = database->library->bind_text(statement, 1, (const char *)definition,
    length, SQLITE_TRANSIENT);
  int result = 0, key_length = 0;
  unsigned char *copy = NULL;
  if (code == SQLITE_OK) {
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP,
      database->library->step)(statement);
    if (code == SQLITE_DONE) result = 1;
    else if (code != SQLITE_ROW) result = actql_operation_code(code);
    else {
      key_length = database->library->column_bytes(statement, 0);
      const void *key = database->library->column_blob(statement, 0);
      if (key == NULL || key_length < 1 || key_length > 512) result = 6;
      else {
        copy = actql_adapter_allocate(database->library, (size_t)key_length);
        if (copy == NULL) result = -1;
        else memcpy(copy, key, (size_t)key_length);
      }
      if (result == 0) {
        code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP,
          database->library->step)(statement);
        if (code == SQLITE_ROW) result = -1;
        else if (code != SQLITE_DONE) result = actql_operation_code(code);
      }
    }
  } else result = actql_operation_code(code);
  int finalized = database->library->finalize(statement);
  if ((result == 0 || result == 1) && finalized != SQLITE_OK)
    result = actql_operation_code(finalized);
  if (result == 0) {
    database->result_key = copy;
    database->result_key_length = key_length;
  } else {
    actql_adapter_free(database->library, copy);
    if (result != 1) actql_database_error(database, "read Run definition locator failed");
  }
  return result;
}
#include "journal_read_evidence.h"
