/* Production collision locator with real platform SQLite. The caller still
 * authenticates the located Run; this is not a selected Host/Library fixture. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include "../../src/platform_native/sqlite/sqlite_stub.c"

void actql_native_timing_count(int32_t tag) { (void)tag; }
static int prepares, steps, finalizes, fullscan, forced_step, forced_finalize;
static int prepare(sqlite3 *db, const char *sql, int length, sqlite3_stmt **stmt, const char **tail) {
  prepares++; return sqlite3_prepare_v2(db, sql, length, stmt, tail);
}
static int step(sqlite3_stmt *stmt) {
  steps++;
  int code = forced_step ? forced_step : sqlite3_step(stmt);
  fullscan = sqlite3_stmt_status(stmt, SQLITE_STMTSTATUS_FULLSCAN_STEP, 0);
  return code;
}
static int finalize(sqlite3_stmt *stmt) {
  finalizes++; int code = sqlite3_finalize(stmt);
  return forced_finalize ? forced_finalize : code;
}
static void sql(sqlite3 *db, const char *text) {
  assert(sqlite3_exec(db, text, NULL, NULL, NULL) == SQLITE_OK);
}
static int lookup(actql_native_sqlite_database *db, const char *definition) {
  prepares = steps = finalizes = fullscan = 0;
  return actql_native_client_run_definition_key(db, (moonbit_bytes_t)definition,
    (int32_t)strlen(definition));
}
static int insert(actql_native_sqlite_database *db, const char *key, const char *body) {
  return actql_native_sqlite_database_insert(db, (moonbit_bytes_t)"client_runs", 11,
    (moonbit_bytes_t)key, (int32_t)strlen(key), (moonbit_bytes_t)body, (int32_t)strlen(body));
}
static void key_is(actql_native_sqlite_database *db, const char *key) {
  assert(db->result_key_length == (int)strlen(key));
  assert(memcmp(db->result_key, key, strlen(key)) == 0);
  assert(db->result_body == NULL && db->result_body_length == 0);
}
#define BODY(definition) "{\"run_definition\":\"{\\\"run_definition_cid\\\":\\\"" definition "\\\"}\"}"

int main(void) {
  actql_native_sqlite_library library = {0};
  library.prepare_v2 = prepare; library.step = step; library.finalize = finalize;
  library.bind_text = sqlite3_bind_text; library.bind_blob = sqlite3_bind_blob;
  library.column_blob = sqlite3_column_blob; library.column_bytes = sqlite3_column_bytes;
  library.column_int64 = sqlite3_column_int64; library.get_autocommit = sqlite3_get_autocommit;
  library.exec = sqlite3_exec; library.errmsg = sqlite3_errmsg;
  actql_native_sqlite_database db = {0};
  db.library = &library; db.opened = true; db.process = getpid();
  db.max_body_bytes = 4096; db.diagnostic_ceiling = 256;
  assert(sqlite3_open(":memory:", &db.database) == SQLITE_OK);
  sql(db.database, "CREATE TABLE actql_records(namespace TEXT NOT NULL,record_key TEXT NOT NULL,revision INTEGER NOT NULL,body BLOB NOT NULL,PRIMARY KEY(namespace,record_key)) WITHOUT ROWID");
  sql(db.database, "BEGIN IMMEDIATE");
  assert(actql_native_client_run_definition_install(&db, 0) == 0);
  assert(lookup(&db, "selected") == 1);
  assert(prepares == 1 && steps == 1 && finalizes == 1 && fullscan == 0);
  assert(insert(&db, "one", BODY("selected")) == 0);
  for (int i = 0; i < 1000; i++) {
    char statement[128];
    snprintf(statement, sizeof(statement), "INSERT INTO actql_records VALUES('unrelated','%04d',0,X'FF')", i);
    sql(db.database, statement);
  }
  assert(lookup(&db, "selected") == 0); key_is(&db, "one");
  assert(prepares == 1 && steps == 2 && finalizes == 1 && fullscan == 0);
  assert(!sqlite3_get_autocommit(db.database));
  sql(db.database, "COMMIT");
  assert(lookup(&db, "selected") == -1);
  puts("one indexed selected key and caller transaction only: PASS");

  sql(db.database, "BEGIN IMMEDIATE");
  assert(insert(&db, "two", BODY("selected")) == 2);
  assert(lookup(&db, "selected") == 0); key_is(&db, "one");
  assert(insert(&db, "one", BODY("different")) == 2);
  assert(lookup(&db, "different") == 1);
  assert(db.result_key == NULL);
  assert(lookup(&db, "selected' OR 1=1 --") == 1);
  assert(!sqlite3_get_autocommit(db.database));
  puts("actual UNIQUE versus other collision is a locator not classification: PASS");

  assert(insert(&db, "pending", BODY("uncommitted")) == 0);
  assert(lookup(&db, "uncommitted") == 0); key_is(&db, "pending");
  sql(db.database, "ROLLBACK");
  sql(db.database, "BEGIN IMMEDIATE");
  assert(lookup(&db, "uncommitted") == 1);
  assert(lookup(&db, "selected") == 0); key_is(&db, "one");
  puts("same uncommitted rows and rollback without commit ACK: PASS");

  assert(lookup(&db, "") == 6 && prepares == 0);
  char oversized[514]; memset(oversized, 'x', sizeof(oversized)); oversized[513] = 0;
  assert(lookup(&db, oversized) == 6 && prepares == 0);
  forced_step = SQLITE_BUSY;
  assert(lookup(&db, "selected") == 3 && db.result_key == NULL);
  forced_step = SQLITE_IOERR;
  assert(lookup(&db, "selected") == -1 && db.result_key == NULL);
  forced_step = 0; forced_finalize = SQLITE_IOERR;
  assert(lookup(&db, "selected") == -1 && db.result_key == NULL);
  assert(lookup(&db, "missing") == -1 && db.result_key == NULL);
  forced_finalize = 0;
  assert(lookup(&db, "selected") == 0); key_is(&db, "one");
  puts("bounds BUSY IO and finalize errors never become a miss: PASS");

  sql(db.database, "DROP INDEX actql_client_run_definition_unique");
  assert(lookup(&db, "selected") == -1 && db.result_key == NULL);
  db.transaction_fenced = 1;
  assert(lookup(&db, "selected") == 5 && prepares == 0);
  db.transaction_fenced = 0; db.lookup_generation = 1;
  assert(lookup(&db, "selected") == 5 && prepares == 0);
  db.lookup_generation = 0;
  sql(db.database, "ROLLBACK");
  actql_clear_result(&db);
  actql_adapter_free(db.library, db.error); db.error = NULL;
  assert(sqlite3_close(db.database) == SQLITE_OK); db.database = NULL; db.opened = false;
  assert(lookup(&db, "selected") == 5 && prepares == 0);
  puts("missing index and fenced or retired original never fall back: PASS");
  puts("Run definition key C cases: 5/5");
  return 0;
}
