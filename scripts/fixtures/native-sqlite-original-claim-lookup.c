// Callback fault injection against the exact FFI, separate from the real
// Native/SQLite tests. No operational database, credential, key or grant.
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../src/platform_native/sqlite/sqlite_stub.c"

static int prepare_code, bind_code, step_code, finalize_code;
static int prepares, binds, steps, finalizes, integer_type;
static int64_t original_ordinal;
static int allocate_on_prepare_error;
static sqlite3_stmt *const fixture_statement = (sqlite3_stmt *)(uintptr_t)1;

static int fixture_prepare(sqlite3 *database, const char *sql, int length,
                           sqlite3_stmt **statement, const char **tail) {
  assert(database != NULL && length == -1 && tail == NULL);
  assert(strcmp(sql, "SELECT ordinal, typeof(ordinal) = 'integer' FROM actql_claims "
                     "WHERE namespace = ?1 AND claim_key = ?2") == 0);
  prepares++;
  *statement = prepare_code == SQLITE_OK || allocate_on_prepare_error
    ? fixture_statement : NULL;
  return prepare_code;
}
static int fixture_bind(sqlite3_stmt *statement, int index, const char *value,
                        int length, void (*destroy)(void *)) {
  assert(statement == fixture_statement && destroy == SQLITE_TRANSIENT);
  assert((index == 1 && length == 5 && memcmp(value, "grant", 5) == 0) ||
         (index == 2 && length == 3 && memcmp(value, "use", 3) == 0));
  binds++;
  return bind_code;
}
static int fixture_step(sqlite3_stmt *statement) {
  assert(statement == fixture_statement);
  steps++;
  return step_code;
}
static sqlite3_int64 fixture_column(sqlite3_stmt *statement, int index) {
  assert(statement == fixture_statement && step_code == SQLITE_ROW);
  assert(index == 0 || index == 1);
  return index == 0 ? original_ordinal : integer_type;
}
static int fixture_finalize(sqlite3_stmt *statement) {
  assert(statement == fixture_statement);
  finalizes++;
  return finalize_code;
}
static const char *fixture_error(sqlite3 *database) {
  assert(database != NULL);
  return "injected original claim read failure";
}
static int forbid_exec(sqlite3 *database, const char *sql,
                       int (*callback)(void *, int, char **, char **),
                       void *context, char **message) {
  (void)database; (void)sql; (void)callback; (void)context; (void)message;
  assert(!"lookup attempted transaction, write or initialization");
  return SQLITE_MISUSE;
}
static void reset_fixture(void) {
  prepare_code = bind_code = finalize_code = SQLITE_OK;
  step_code = SQLITE_ROW;
  original_ordinal = 7;
  integer_type = 1;
  prepares = binds = steps = finalizes = allocate_on_prepare_error = 0;
}
static int lookup(actql_native_sqlite_database *database) {
  return actql_native_sqlite_database_lookup_claim_ordinal(
    database, (moonbit_bytes_t)"grant", 5, (moonbit_bytes_t)"use", 3);
}

int main(void) {
  actql_native_sqlite_library library = {0};
  library.prepare_v2 = fixture_prepare;
  library.bind_text = fixture_bind;
  library.step = fixture_step;
  library.column_int64 = fixture_column;
  library.finalize = fixture_finalize;
  library.errmsg = fixture_error;
  library.exec = forbid_exec;
  actql_native_sqlite_database database = {0};
  database.library = &library;
  database.database = (sqlite3 *)&database;
  database.opened = true;
  database.diagnostic_ceiling = 64;

  reset_fixture();
  assert(lookup(&database) == 0 && database.result_revision == 7);
  assert(prepares == 1 && binds == 2 && steps == 1 && finalizes == 1);
  puts("exact stored positive ordinal after finalize ACK: PASS");

  reset_fixture(); step_code = SQLITE_DONE;
  assert(lookup(&database) == 1 && database.result_revision == 0);
  assert(finalizes == 1);
  puts("absent original does not allocate or retain stale result: PASS");

  reset_fixture(); finalize_code = SQLITE_IOERR;
  assert(lookup(&database) != 0 && database.result_revision == 0);
  assert(finalizes == 1);
  puts("present original finalize failure never returns success: PASS");

  reset_fixture(); step_code = SQLITE_DONE; finalize_code = SQLITE_IOERR;
  assert(lookup(&database) != 1 && database.result_revision == 0);
  assert(finalizes == 1);
  puts("absent original finalize failure never returns absence: PASS");

  reset_fixture(); original_ordinal = 0;
  assert(lookup(&database) == -1 && database.result_revision == 0);
  assert(finalizes == 1);
  puts("nonpositive stored ordinal is refused: PASS");

  reset_fixture(); integer_type = 0;
  assert(lookup(&database) == -1 && database.result_revision == 0);
  assert(finalizes == 1);
  puts("noninteger original is not coerced to a positive ordinal: PASS");

  reset_fixture(); bind_code = SQLITE_BUSY;
  assert(lookup(&database) == 3 && steps == 0 && finalizes == 1);
  assert(database.result_revision == 0);
  puts("bind failure retires the same statement: PASS");

  reset_fixture(); step_code = SQLITE_BUSY;
  assert(lookup(&database) == 3 && steps == 1 && finalizes == 1);
  assert(database.result_revision == 0);
  puts("step failure retires the same statement: PASS");

  reset_fixture(); prepare_code = SQLITE_BUSY; allocate_on_prepare_error = 1;
  assert(lookup(&database) == 3 && binds == 0 && finalizes == 1);
  puts("prepare error retires its returned statement: PASS");

  reset_fixture(); prepare_code = SQLITE_BUSY;
  assert(lookup(&database) == 3 && binds == 0 && finalizes == 0);
  puts("prepare error without a statement has no invented cleanup: PASS");

  reset_fixture(); original_ordinal = INT64_MAX;
  assert(lookup(&database) == 0 && database.result_revision == INT64_MAX);
  assert(finalizes == 1);
  puts("storage identity is exact and grants no use-limit permission: PASS");

  reset_fixture(); database.opened = false;
  assert(lookup(&database) == 5 && prepares == 0 && finalizes == 0);
  assert(lookup(NULL) == 5);
  puts("closed database refuses before observation: PASS");
  actql_clear_result(&database);
  puts("Original claim lookup C cases: 12/12");
  return 0;
}
