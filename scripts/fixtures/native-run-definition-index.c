/* Algorithm control using the platform SQLite, not an installed supplier or
 * selected arena admission. Include the production port without a copy. */
#include <assert.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <sqlite3.h>

typedef struct {
  int (*prepare_v2)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
  int (*step)(sqlite3_stmt *);
  const void *(*column_blob)(sqlite3_stmt *, int);
  int (*column_bytes)(sqlite3_stmt *, int);
  int (*finalize)(sqlite3_stmt *);
  int (*get_autocommit)(sqlite3 *);
  bool available;
} actql_native_sqlite_library;
typedef struct {
  actql_native_sqlite_library *library;
  sqlite3 *database;
  bool opened;
  int transaction_fenced;
  int64_t lookup_generation;
} actql_native_sqlite_database;
#define ACTQL_NATIVE_TIMED_CALL(tag, call) (call)
static bool actql_database_library_available(actql_native_sqlite_library *library) {
  return library != NULL && library->available;
}
static void actql_database_error(actql_native_sqlite_database *database, const char *message) {
  (void)database; (void)message;
}
static int actql_exec(actql_native_sqlite_database *database, const char *sql) {
  return sqlite3_exec(database->database, sql, NULL, NULL, NULL);
}
#include "../../src/platform_native/sqlite/journal_run_definition.h"

static void sql(actql_native_sqlite_database *database, const char *text) {
  int code = actql_exec(database, text);
  if (code != SQLITE_OK) fprintf(stderr, "%s: %s\n", text, sqlite3_errmsg(database->database));
  assert(code == SQLITE_OK);
}
static const char *first = "INSERT INTO actql_records VALUES('client_runs','one',0,"
  "CAST('{\"run_definition\":\"{\\\"run_definition_cid\\\":\\\"same\\\"}\"}' AS BLOB))";
static const char *duplicate = "INSERT INTO actql_records VALUES('client_runs','two',0,"
  "CAST('{\"run_definition\":\"{\\\"run_definition_cid\\\":\\\"same\\\"}\"}' AS BLOB))";

int main(void) {
  actql_native_sqlite_library library = {
    sqlite3_prepare_v2, sqlite3_step, sqlite3_column_blob, sqlite3_column_bytes,
    sqlite3_finalize, sqlite3_get_autocommit, true
  };
  actql_native_sqlite_database database = { .library = &library, .opened = true };
  assert(sqlite3_open(":memory:", &database.database) == SQLITE_OK);
  sql(&database, "CREATE TABLE actql_records(namespace TEXT,record_key TEXT,revision INTEGER,body BLOB,PRIMARY KEY(namespace,record_key))");
  assert(actql_native_client_run_definition_schema(&database) == 0);
  assert(actql_native_client_run_definition_install(&database, 8) == -1);
  sql(&database, "BEGIN IMMEDIATE");
  assert(actql_native_client_run_definition_install(&database, -1) == -1);
  assert(actql_native_client_run_definition_install(&database, 536870913) == -1);
  assert(actql_native_client_run_definition_install(&database, 0) == 0);
  assert(!sqlite3_get_autocommit(database.database));
  assert(actql_native_client_run_definition_schema(&database) == 1);
  sql(&database, "ROLLBACK");
  assert(actql_native_client_run_definition_schema(&database) == 0);
  puts("caller transaction and rollback: passed");

  sql(&database, "INSERT INTO actql_records VALUES('unrelated','x',0,X'FF')");
  sql(&database, first);
  sql(&database, "BEGIN IMMEDIATE");
  assert(actql_native_client_run_definition_install(&database, 0) == 6);
  assert(actql_native_client_run_definition_install(&database, 1) == 6);
  assert(actql_native_client_run_definition_schema(&database) == 0);
  assert(actql_native_client_run_definition_install(&database, 2) == 0);
  sql(&database, "COMMIT");
  assert(actql_exec(&database, duplicate) == SQLITE_CONSTRAINT);
  sql(&database, "INSERT INTO actql_records VALUES('client_runs','distinct',0,"
    "CAST('{\"run_definition\":\"{\\\"run_definition_cid\\\":\\\"different\\\"}\"}' AS BLOB))");
  assert(actql_exec(&database,
    "UPDATE actql_records SET body=(SELECT body FROM actql_records WHERE record_key='one') "
    "WHERE namespace='client_runs' AND record_key='distinct'") == SQLITE_CONSTRAINT);
  /* Deleting a removable locator does not remove the physical guard. */
  sql(&database, "INSERT INTO actql_records VALUES('client_run_definition_index','locator',0,X'30')");
  sql(&database, "DELETE FROM actql_records WHERE namespace='client_run_definition_index'");
  assert(actql_native_client_run_definition_schema(&database) == 1);
  assert(actql_exec(&database, duplicate) == SQLITE_CONSTRAINT);
  puts("bounded scan, exact capacity and retained uniqueness: passed");

  sql(&database, "DROP INDEX actql_client_run_definition_unique");
  sql(&database, duplicate);
  sql(&database, "BEGIN IMMEDIATE");
  assert(actql_native_client_run_definition_install(&database, 8) == -1);
  assert(!sqlite3_get_autocommit(database.database));
  assert(actql_native_client_run_definition_schema(&database) == 0);
  sql(&database, "ROLLBACK");
  puts("preexisting duplicate refuses without transaction ACK: passed");

  sql(&database, "CREATE INDEX actql_client_run_definition_unique ON actql_records(record_key)");
  assert(actql_native_client_run_definition_schema(&database) == -1);
  sql(&database, "DROP INDEX actql_client_run_definition_unique");
  sql(&database, "CREATE TABLE actql_client_run_definition_unique(x)");
  assert(actql_native_client_run_definition_schema(&database) == -1);
  sql(&database, "DROP TABLE actql_client_run_definition_unique");
  sql(&database, "CREATE INDEX ACTQL_CLIENT_RUN_DEFINITION_UNIQUE ON actql_records(record_key)");
  assert(actql_native_client_run_definition_schema(&database) == -1);
  sql(&database, "DROP INDEX ACTQL_CLIENT_RUN_DEFINITION_UNIQUE");
  database.lookup_generation = 1;
  assert(actql_native_client_run_definition_schema(&database) == -1);
  database.lookup_generation = 0;
  database.transaction_fenced = 1;
  assert(actql_native_client_run_definition_schema(&database) == -1);
  database.transaction_fenced = 0;
  library.available = false;
  assert(actql_native_client_run_definition_schema(&database) == -1);
  library.available = true;
  database.opened = false;
  assert(actql_native_client_run_definition_schema(&database) == -1);
  assert(sqlite3_close(database.database) == SQLITE_OK);
  puts("foreign schema, current and lifetime refusals: passed");
  return 0;
}
