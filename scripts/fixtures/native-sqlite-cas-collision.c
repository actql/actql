/* Exact FFI with platform SQLite: physical CAS classification and statement
 * retirement only, not the selected component, Host or ordinary command. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../src/platform_native/sqlite/sqlite_stub.c"

/* The optional timing sink supplies no behavior or admission in this control. */
void actql_native_timing_count(int32_t tag) { (void)tag; }

static int steps, finalizes, forced_step, forced_finalize;
static int counted_step(sqlite3_stmt *statement) {
  steps++;
  return forced_step ? forced_step : sqlite3_step(statement);
}
static int counted_finalize(sqlite3_stmt *statement) {
  finalizes++;
  int result = sqlite3_finalize(statement);
  return forced_finalize ? forced_finalize : result;
}
static void sql(sqlite3 *database, const char *text) {
  assert(sqlite3_exec(database, text, NULL, NULL, NULL) == SQLITE_OK);
}
static int cas(actql_native_sqlite_database *database, int64_t revision, const char *body) {
  steps = finalizes = 0;
  int code = actql_native_sqlite_database_compare_exchange(database,
    (moonbit_bytes_t)"client_runs", 11, (moonbit_bytes_t)"two", 3,
    revision, (moonbit_bytes_t)body, (int32_t)strlen(body));
  printf("physical CAS code: %d\n", code);
  fflush(stdout);
  return code;
}
static void row(sqlite3 *database, int64_t revision, const char *body) {
  sqlite3_stmt *statement = NULL;
  assert(sqlite3_prepare_v2(database,
    "SELECT revision, body FROM actql_records WHERE namespace='client_runs' AND record_key='two'",
    -1, &statement, NULL) == SQLITE_OK);
  assert(sqlite3_step(statement) == SQLITE_ROW);
  assert(sqlite3_column_int64(statement, 0) == revision);
  assert(sqlite3_column_bytes(statement, 1) == (int)strlen(body));
  assert(memcmp(sqlite3_column_blob(statement, 1), body, strlen(body)) == 0);
  assert(sqlite3_step(statement) == SQLITE_DONE);
  assert(sqlite3_finalize(statement) == SQLITE_OK);
}
#define REQUIRE(expression) do { if (!(expression)) { \
  fprintf(stderr, "failed: %s at line %d\n", #expression, __LINE__); return 1; \
} } while (0)

int main(void) {
  actql_native_sqlite_library library = {0};
  library.prepare_v2 = sqlite3_prepare_v2;
  library.bind_text = sqlite3_bind_text;
  library.bind_blob = sqlite3_bind_blob;
  library.bind_int64 = sqlite3_bind_int64;
  library.step = counted_step;
  library.finalize = counted_finalize;
  library.changes64 = sqlite3_changes64;
  library.errmsg = sqlite3_errmsg;
  actql_native_sqlite_database database = {0};
  database.library = &library;
  database.opened = true;
  database.max_body_bytes = 4096;
  database.diagnostic_ceiling = 256;
  assert(sqlite3_open(":memory:", &database.database) == SQLITE_OK);
  sql(database.database, "CREATE TABLE actql_records(namespace TEXT,record_key TEXT,revision INTEGER,body BLOB,PRIMARY KEY(namespace,record_key))");
  sql(database.database, "INSERT INTO actql_records VALUES('client_runs','one',0,CAST('{\"run_definition\":\"same\"}' AS BLOB)),('client_runs','two',0,CAST('{\"run_definition\":\"other\"}' AS BLOB))");
  sql(database.database, "CREATE UNIQUE INDEX selected_definition ON actql_records(json_extract(CAST(body AS TEXT),'$.run_definition')) WHERE namespace='client_runs'");
  const char *same = "{\"run_definition\":\"same\"}";
  const char *other = "{\"run_definition\":\"other\"}";
  const char *next = "{\"run_definition\":\"next\"}";
  sql(database.database, "BEGIN IMMEDIATE");
  REQUIRE(cas(&database, 0, same) == 2);
  REQUIRE(steps == 1 && finalizes == 1 && database.result_revision == 0);
  REQUIRE(!sqlite3_get_autocommit(database.database));
  row(database.database, 0, other);
  puts("primary UNIQUE update collision preserves original row and transaction: PASS");

  assert(sqlite3_extended_result_codes(database.database, 1) == SQLITE_OK);
  REQUIRE(cas(&database, 0, same) == 2);
  REQUIRE(steps == 1 && finalizes == 1 && database.result_revision == 0);
  row(database.database, 0, other);
  puts("extended UNIQUE update collision has the same existing result: PASS");

  REQUIRE(cas(&database, 99, next) == 2);
  REQUIRE(steps == 1 && finalizes == 1 && database.result_revision == 0);
  row(database.database, 0, other);
  puts("stale revision remains a collision without mutation: PASS");

  forced_step = SQLITE_BUSY;
  REQUIRE(cas(&database, 0, next) == 3);
  REQUIRE(steps == 1 && finalizes == 1 && database.result_revision == 0);
  row(database.database, 0, other);
  puts("injected busy remains distinct and retires original statement: PASS");

  forced_step = SQLITE_IOERR;
  REQUIRE(cas(&database, 0, next) == -1);
  REQUIRE(steps == 1 && finalizes == 1 && database.result_revision == 0);
  row(database.database, 0, other);
  puts("injected IO failure is not a collision or success: PASS");

  forced_step = 0;
  REQUIRE(cas(&database, 0, next) == 0);
  REQUIRE(steps == 1 && finalizes == 1 && database.result_revision == 1);
  row(database.database, 1, next);
  sql(database.database, "ROLLBACK");
  row(database.database, 0, other);
  puts("successful CAS and caller rollback retain distinct outcomes: PASS");

  sql(database.database, "BEGIN IMMEDIATE");
  forced_finalize = SQLITE_IOERR;
  REQUIRE(cas(&database, 0, next) == -1);
  REQUIRE(steps == 1 && finalizes == 1 && !sqlite3_get_autocommit(database.database));
  forced_finalize = 0;
  sql(database.database, "ROLLBACK");
  row(database.database, 0, other);
  puts("injected finalize failure never confirms the actual write or COMMIT: PASS");

  database.opened = false;
  REQUIRE(cas(&database, 0, next) == 5);
  REQUIRE(steps == 0 && finalizes == 0);
  actql_clear_result(&database);
  assert(sqlite3_close(database.database) == SQLITE_OK);
  puts("closed original refuses without touching SQLite: PASS");
  puts("Physical CAS collision C cases: 8/8");
  return 0;
}
