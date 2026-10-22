/* Exact production port with platform SQLite. This proves bounded physical
 * grouping/transaction behavior, not request admission or a selected Host. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../src/platform_native/sqlite/sqlite_stub.c"

void actql_native_timing_count(int32_t tag) { (void)tag; }

static int prepares, finalizes, steps, scan_steps, force_step, force_finalize;
static int prepare(sqlite3 *database, const char *sql, int length,
                   sqlite3_stmt **statement, const char **tail) {
  prepares++;
  return sqlite3_prepare_v2(database, sql, length, statement, tail);
}
static int step(sqlite3_stmt *statement) {
  steps++;
  int code = force_step ? force_step : sqlite3_step(statement);
  scan_steps = sqlite3_stmt_status(statement, SQLITE_STMTSTATUS_FULLSCAN_STEP, 0);
  return code;
}
static int finalize(sqlite3_stmt *statement) {
  finalizes++;
  int code = sqlite3_finalize(statement);
  return force_finalize ? force_finalize : code;
}
static void sql(sqlite3 *database, const char *text) {
  if (sqlite3_exec(database, text, NULL, NULL, NULL) != SQLITE_OK) {
    fprintf(stderr, "SQL failed: %s\n%s\n", text, sqlite3_errmsg(database));
    assert(false);
  }
}
static void insert(sqlite3 *database, const char *name, const char *body) {
  sqlite3_stmt *statement = NULL;
  assert(sqlite3_prepare_v2(database,
    "INSERT INTO actql_records VALUES('client_local_read_evidence',?1,0,?2)",
    -1, &statement, NULL) == SQLITE_OK);
  assert(sqlite3_bind_text(statement, 1, name, -1, SQLITE_TRANSIENT) == SQLITE_OK);
  assert(sqlite3_bind_blob(statement, 2, body, (int)strlen(body), SQLITE_TRANSIENT) == SQLITE_OK);
  assert(sqlite3_step(statement) == SQLITE_DONE);
  assert(sqlite3_finalize(statement) == SQLITE_OK);
}
static int usage(actql_native_sqlite_database *database, const char *request,
                 int64_t max_entries, int64_t max_bytes) {
  prepares = finalizes = steps = scan_steps = 0;
  return actql_native_client_read_evidence_usage(database,
    (moonbit_bytes_t)request, (int32_t)strlen(request), max_entries, max_bytes);
}
static void clear_error(actql_native_sqlite_database *database) {
  actql_adapter_free(database->library, database->error);
  database->error = NULL;
}

#define PACKET(request) "{\"authorization_context\":\"a\",\"data_ceiling\":\"c\",\"egress_admission\":\"e\",\"request\":\"" request "\"}"
static const char *selected = PACKET("selected");
static const char *other = PACKET("other");

int main(void) {
  actql_native_sqlite_library library = {0};
  library.prepare_v2 = prepare;
  library.step = step;
  library.finalize = finalize;
  library.bind_text = sqlite3_bind_text;
  library.bind_int64 = sqlite3_bind_int64;
  library.column_int64 = sqlite3_column_int64;
  library.column_blob = sqlite3_column_blob;
  library.column_bytes = sqlite3_column_bytes;
  library.get_autocommit = sqlite3_get_autocommit;
  library.exec = sqlite3_exec;
  library.free_memory = sqlite3_free;
  library.errmsg = sqlite3_errmsg;
  actql_native_sqlite_database database = {0};
  database.library = &library;
  database.opened = true;
  database.process = getpid();
  database.diagnostic_ceiling = 256;
  assert(sqlite3_open(":memory:", &database.database) == SQLITE_OK);
  sql(database.database, "CREATE TABLE actql_records(namespace TEXT NOT NULL,record_key TEXT NOT NULL,revision INTEGER NOT NULL,body BLOB NOT NULL,PRIMARY KEY(namespace,record_key)) WITHOUT ROWID");
  insert(database.database, "one", selected);
  for (int i = 0; i < 1000; i++) {
    char key[32]; snprintf(key, sizeof(key), "unrelated-%04d", i);
    insert(database.database, key, other);
  }
  assert(actql_native_client_read_evidence_schema(&database) == 0);
  assert(actql_native_client_read_evidence_install(&database, 1001) == -1);
  sql(database.database, "BEGIN IMMEDIATE");
  assert(usage(&database, "selected", 64, 65536) == -1);
  assert(database.result_record_count == 0 && database.result_record_body_bytes == 0);
  assert(!sqlite3_get_autocommit(database.database));
  puts("absent index refuses usage and out-of-transaction installation: PASS");

  assert(actql_native_client_read_evidence_install(&database, 1000) == 6);
  assert(actql_native_client_read_evidence_schema(&database) == 0);
  assert(!sqlite3_get_autocommit(database.database));
  assert(actql_native_client_read_evidence_install(&database, 1001) == 0);
  assert(actql_native_client_read_evidence_schema(&database) == 1);
  assert(usage(&database, "selected", 64, 65536) == 0);
  assert(database.result_record_count == 1);
  assert(database.result_record_body_bytes == (int64_t)strlen(selected));
  assert(prepares == 1 && finalizes == 1 && steps == 2 && scan_steps == 0);
  puts("bounded explicit index installation and selected query exclude unrelated history: PASS");

  insert(database.database, "two", selected);
  assert(usage(&database, "selected", 64, 65536) == 0);
  assert(database.result_record_count == 2 &&
    database.result_record_body_bytes == 2 * (int64_t)strlen(selected));
  assert(!sqlite3_get_autocommit(database.database));
  sql(database.database, "ROLLBACK");
  assert(actql_native_client_read_evidence_schema(&database) == 0);
  sql(database.database, "BEGIN IMMEDIATE");
  assert(actql_native_client_read_evidence_install(&database, 1001) == 0);
  sql(database.database, "COMMIT");
  assert(usage(&database, "selected", 64, 65536) == -1);
  sql(database.database, "BEGIN IMMEDIATE");
  assert(usage(&database, "selected", 64, 65536) == 0 && database.result_record_count == 1);
  puts("same connection sees uncommitted rows while rollback and COMMIT remain caller-owned: PASS");

  assert(usage(&database, "absent", 0, 0) == 0);
  assert(database.result_record_count == 0 && database.result_record_body_bytes == 0);
  assert(usage(&database, "selected", 0, 65536) == 6);
  assert(usage(&database, "selected", 64, (int64_t)strlen(selected) - 1) == 6);
  assert(database.result_record_count == 0 && database.result_record_body_bytes == 0);
  assert(usage(&database, "selected", 64, (int64_t)strlen(selected)) == 0);
  for (int i = 1; i < 65; i++) {
    char key[32]; snprintf(key, sizeof(key), "selected-%04d", i);
    insert(database.database, key, selected);
  }
  assert(usage(&database, "selected", 64, 65536) == 6);
  assert(steps == 65 && finalizes == 1 && scan_steps == 0);
  assert(database.result_record_count == 0 && database.result_record_body_bytes == 0);
  puts("zero exact miss and entry/byte/65th-row bounds preserve distinct results: PASS");

  const char *invalid[] = {
    "{\"request\":\"selected\"}",
    "{\"authorization_context\":\"a\",\"data_ceiling\":\"c\",\"egress_admission\":\"e\",\"request\":\"selected\",\"request\":\"hidden\"}",
    "{\"authorization_context\":\"a\",\"data_ceiling\":\"c\",\"egress_admission\":\"e\",\"request\":null}",
    "not-json"
  };
  for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
    sqlite3_stmt *statement = NULL;
    assert(sqlite3_prepare_v2(database.database,
      "INSERT INTO actql_records VALUES('client_local_read_evidence','bad',0,?1)",
      -1, &statement, NULL) == SQLITE_OK);
    assert(sqlite3_bind_blob(statement, 1, invalid[i], (int)strlen(invalid[i]), SQLITE_TRANSIENT) == SQLITE_OK);
    assert(sqlite3_step(statement) != SQLITE_DONE);
    assert(sqlite3_finalize(statement) != SQLITE_OK);
    assert(!sqlite3_get_autocommit(database.database));
  }
  assert(sqlite3_exec(database.database,
    "UPDATE actql_records SET revision=1 WHERE record_key='one'", NULL,NULL,NULL) != SQLITE_OK);
  puts("index refuses malformed duplicate missing and nonzero-revision packets on later writes: PASS");
  sql(database.database, "ROLLBACK");

  sql(database.database, "BEGIN IMMEDIATE");
  force_step = SQLITE_BUSY;
  assert(usage(&database, "selected", 64, 65536) == 3);
  assert(finalizes == 1 && !sqlite3_get_autocommit(database.database));
  force_step = SQLITE_IOERR;
  assert(usage(&database, "selected", 64, 65536) == -1 && finalizes == 1);
  force_step = 0; force_finalize = SQLITE_IOERR;
  assert(usage(&database, "selected", 64, 65536) == -1 && finalizes == 1);
  assert(database.result_record_count == 0 && database.result_record_body_bytes == 0);
  force_finalize = 0;
  sql(database.database, "ROLLBACK");
  puts("BUSY IO and finalize failure remain failures without row totals or transaction ACK: PASS");

  sql(database.database, "DROP INDEX actql_client_read_evidence_request");
  sql(database.database, "CREATE INDEX actql_client_read_evidence_request ON actql_records(record_key)");
  assert(actql_native_client_read_evidence_schema(&database) == -1);
  sql(database.database, "DROP INDEX actql_client_read_evidence_request");
  insert(database.database, "malformed-before-maintenance", "{}");
  sql(database.database, "BEGIN IMMEDIATE");
  assert(actql_native_client_read_evidence_install(&database, 1002) == -1);
  assert(actql_native_client_read_evidence_schema(&database) == 0);
  sql(database.database, "ROLLBACK");
  puts("foreign schema and malformed legacy packet refuse explicit admission and installation: PASS");

  database.opened = false;
  assert(usage(&database, "selected", 64, 65536) == 5);
  assert(prepares == 0 && finalizes == 0);
  database.opened = true; database.lookup_generation = 1;
  assert(usage(&database, "selected", 64, 65536) == 5 && prepares == 0);
  database.lookup_generation = 0; database.transaction_fenced = 1;
  assert(usage(&database, "selected", 64, 65536) == 5 && prepares == 0);
  clear_error(&database);
  assert(sqlite3_close(database.database) == SQLITE_OK);
  puts("closed fenced and foreign lookup frames refuse before SQLite: PASS");
  puts("Selected read evidence C cases: 8/8");
  return 0;
}
