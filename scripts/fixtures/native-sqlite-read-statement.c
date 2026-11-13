/* Actual adapter and platform SQLite. This is a fresh private fixture, not a
 * selected component, managed Store authority or ordinary Host acceptance. */
#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include "../../src/platform_native/sqlite/sqlite_stub.c"

void actql_native_timing_count(int32_t tag) { (void)tag; }
static int prepares, resets, clears, finalizes, steps;
static int forced_bind, forced_step, forced_reset, forced_clear, forced_finalize;
static int counted_prepare(sqlite3 *db, const char *sql, int n,
    sqlite3_stmt **out, const char **tail) {
  prepares++;
  return sqlite3_prepare_v2(db, sql, n, out, tail);
}
static int counted_reset(sqlite3_stmt *statement) {
  resets++;
  int code = sqlite3_reset(statement);
  return forced_reset ? forced_reset : code;
}
static int counted_clear(sqlite3_stmt *statement) {
  clears++;
  int code = sqlite3_clear_bindings(statement);
  return forced_clear ? forced_clear : code;
}
static int counted_finalize(sqlite3_stmt *statement) {
  finalizes++;
  int code = sqlite3_finalize(statement);
  return forced_finalize ? forced_finalize : code;
}
static int counted_step(sqlite3_stmt *statement) {
  steps++;
  return forced_step ? forced_step : sqlite3_step(statement);
}
static int counted_bind(sqlite3_stmt *statement, int index, const char *text,
    int bytes, void (*dispose)(void *)) {
  return forced_bind == index ? SQLITE_RANGE
    : sqlite3_bind_text(statement, index, text, bytes, dispose);
}
#define REQUIRE(expression) do { if (!(expression)) { \
  fprintf(stderr, "failed: %s at line %d (prepares=%d)\n", \
    #expression, __LINE__, prepares); return 1; \
} } while (0)

static int controls(void);
int main(int argc, char **argv) {
  if (argc == 2 && strcmp(argv[1], "controls") == 0) return controls();
  REQUIRE(argc == 1);
  actql_native_sqlite_library library = {0};
  library.prepare_v2 = counted_prepare;
  library.bind_text = sqlite3_bind_text;
  library.column_int64 = sqlite3_column_int64;
  library.column_bytes = sqlite3_column_bytes;
  library.column_blob = sqlite3_column_blob;
  library.step = sqlite3_step;
  library.finalize = sqlite3_finalize;
  library.reset = sqlite3_reset;
  library.clear_bindings = sqlite3_clear_bindings;
  library.close_v2 = sqlite3_close;
  library.errmsg = sqlite3_errmsg;
  actql_native_sqlite_database database = {0};
  database.library = &library;
  database.process = getpid();
  database.opened = true;
  database.max_body_bytes = 64;
  database.diagnostic_ceiling = 256;
  REQUIRE(sqlite3_open(":memory:", &database.database) == SQLITE_OK);
  REQUIRE(sqlite3_exec(database.database,
    "CREATE TABLE actql_records(namespace TEXT,record_key TEXT,revision INTEGER,body BLOB,PRIMARY KEY(namespace,record_key));"
    "INSERT INTO actql_records VALUES('first','one',0,CAST('original' AS BLOB)),('second','two',7,CAST('different' AS BLOB))",
    NULL, NULL, NULL) == SQLITE_OK);
  REQUIRE(actql_native_sqlite_database_read(&database,
    (moonbit_bytes_t)"first", 5, (moonbit_bytes_t)"one", 3) == 0);
  REQUIRE(database.result_revision == 0 && database.result_body_length == 8 &&
    memcmp(database.result_body, "original", 8) == 0);
  REQUIRE(actql_native_sqlite_database_read(&database,
    (moonbit_bytes_t)"second", 6, (moonbit_bytes_t)"two", 3) == 0);
  REQUIRE(database.result_revision == 7 && database.result_body_length == 9 &&
    memcmp(database.result_body, "different", 9) == 0);
  REQUIRE(prepares == 1);
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1);
  REQUIRE(database.database == NULL && database.checked_close_ack);
  puts("same original Database rebinds distinct rows with one prepared SELECT and checked close: PASS");
  puts("Physical read statement C cases: 1/1");
  return 0;
}

static void init(actql_native_sqlite_library *library,
    actql_native_sqlite_database *database) {
  memset(library, 0, sizeof(*library));
  memset(database, 0, sizeof(*database));
  prepares = resets = clears = finalizes = steps = 0;
  forced_bind = forced_step = forced_reset = forced_clear = forced_finalize = 0;
  library->prepare_v2 = counted_prepare;
  library->bind_text = counted_bind;
  library->column_int64 = sqlite3_column_int64;
  library->column_bytes = sqlite3_column_bytes;
  library->column_blob = sqlite3_column_blob;
  library->step = counted_step;
  library->finalize = counted_finalize;
  library->reset = counted_reset;
  library->clear_bindings = counted_clear;
  library->close_v2 = sqlite3_close;
  library->errmsg = sqlite3_errmsg;
  database->library = library;
  database->process = getpid();
  database->opened = true;
  database->max_body_bytes = 64;
  database->diagnostic_ceiling = 256;
  assert(sqlite3_open(":memory:", &database->database) == SQLITE_OK);
  assert(sqlite3_exec(database->database,
    "CREATE TABLE actql_records(namespace TEXT,record_key TEXT,revision INTEGER,body BLOB,PRIMARY KEY(namespace,record_key));"
    "INSERT INTO actql_records VALUES('first','one',0,CAST('original' AS BLOB)),('second','two',7,CAST('different' AS BLOB))",
    NULL, NULL, NULL) == SQLITE_OK);
}
static int read_one(actql_native_sqlite_database *database) {
  return actql_native_sqlite_database_read(database,
    (moonbit_bytes_t)"first", 5, (moonbit_bytes_t)"one", 3);
}
static bool unbound(actql_native_sqlite_database *database) {
  char *text = sqlite3_expanded_sql(database->record_read_statement);
  bool empty = text != NULL && strstr(text, "namespace = NULL AND record_key = NULL") != NULL;
  sqlite3_free(text);
  return empty && !database->record_read_in_use;
}

static int controls(void) {
  actql_native_sqlite_library library;
  actql_native_sqlite_database database;
  init(&library, &database);
  REQUIRE(read_one(&database) == 0 && unbound(&database));
  REQUIRE(actql_native_sqlite_database_read(&database,
    (moonbit_bytes_t)"first", 5, (moonbit_bytes_t)"absent", 6) == 1);
  REQUIRE(database.result_body == NULL && unbound(&database));
  REQUIRE(actql_database_read(&database, (moonbit_bytes_t)"first", 5,
    (moonbit_bytes_t)"one", 3, 7, 0, 0, 0) == 4);
  REQUIRE(database.result_body == NULL && unbound(&database));
  database.max_body_bytes = 7;
  REQUIRE(read_one(&database) == -1 && database.result_body == NULL && unbound(&database));
  database.max_body_bytes = 64;
  REQUIRE(read_one(&database) == 0 && prepares == 1 && resets == 5 && clears == 5);
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1);
  puts("each missing bounded or successful read clears both original bindings and snapshots: PASS");

  init(&library, &database);
  REQUIRE(read_one(&database) == 0);
  REQUIRE(sqlite3_exec(database.database,
    "BEGIN; UPDATE actql_records SET revision=1,body=CAST('changed' AS BLOB) WHERE namespace='first';",
    NULL, NULL, NULL) == SQLITE_OK);
  REQUIRE(read_one(&database) == 0 && database.result_revision == 1);
  REQUIRE(!sqlite3_get_autocommit(database.database));
  REQUIRE(sqlite3_exec(database.database, "ROLLBACK; ALTER TABLE actql_records ADD COLUMN extra TEXT;",
    NULL, NULL, NULL) == SQLITE_OK);
  REQUIRE(read_one(&database) == 0 && database.result_revision == 0 && prepares == 1);
  REQUIRE(database.result_body_length == 8 && memcmp(database.result_body, "original", 8) == 0);
  REQUIRE(sqlite3_get_autocommit(database.database));
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1);
  puts("fresh executions observe same-owner transaction rollback and SQLite schema revalidation: PASS");

  init(&library, &database);
  forced_bind = 2;
  REQUIRE(read_one(&database) == -1 && steps == 0 && resets == 1 && clears == 1);
  REQUIRE(unbound(&database) && prepares == 1);
  forced_bind = 0;
  REQUIRE(read_one(&database) == 0 && prepares == 1);
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1);
  puts("second-bind failure clears the first binding without skipping original refusal: PASS");

  init(&library, &database);
  forced_step = SQLITE_BUSY;
  forced_reset = SQLITE_IOERR;
  REQUIRE(read_one(&database) == 3 && resets == 1 && clears == 1 && finalizes == 1);
  REQUIRE(database.record_read_statement == NULL && !database.record_read_in_use);
  forced_step = forced_reset = 0;
  REQUIRE(read_one(&database) == 0 && prepares == 2);
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1);
  puts("primary busy survives reset failure while the failed original statement retires once: PASS");

  init(&library, &database);
  forced_reset = SQLITE_IOERR;
  REQUIRE(read_one(&database) == -1 && database.record_read_statement == NULL);
  REQUIRE(resets == 1 && clears == 1 && finalizes == 1);
  REQUIRE(actql_native_sqlite_database_read(&database,
    (moonbit_bytes_t)"first", 5, (moonbit_bytes_t)"absent", 6) == -1);
  forced_reset = 0;
  forced_clear = SQLITE_IOERR;
  REQUIRE(read_one(&database) == -1 && database.record_read_statement == NULL);
  REQUIRE(resets == 3 && clears == 3 && finalizes == 3);
  forced_clear = 0;
  REQUIRE(read_one(&database) == 0);
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1);
  puts("reset or clear failure never confirms a successful or absent row and cuts the spent alias: PASS");

  init(&library, &database);
  REQUIRE(read_one(&database) == 0);
  sqlite3_stmt *ordinary = database.record_read_statement;
  REQUIRE(actql_database_read(&database, (moonbit_bytes_t)"first", 5,
    (moonbit_bytes_t)"one", 3, -1, 1, 0, 8) == 0);
  REQUIRE(actql_database_read(&database, (moonbit_bytes_t)"first", 5,
    (moonbit_bytes_t)"one", 3, -1, 1, 0, 7) == 2);
  REQUIRE(database.record_read_statement == ordinary && prepares == 3 && finalizes == 2);
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1 && finalizes == 3);
  puts("exact original-extent reads retain their separate complete prepare finalize and refusal: PASS");

  init(&library, &database);
  REQUIRE(read_one(&database) == 0);
  database.record_read_in_use = true;
  REQUIRE(actql_native_sqlite_close_checked(&database) == 0 && finalizes == 0);
  REQUIRE(read_one(&database) == -1 && prepares == 1);
  database.record_read_in_use = false;
  database.test_close_failures = 1;
  REQUIRE(actql_native_sqlite_close_checked(&database) == 0 && database.record_read_statement != NULL);
  forced_finalize = SQLITE_IOERR;
  REQUIRE(actql_native_sqlite_close_checked(&database) == 0 && !database.checked_close_ack);
  REQUIRE(database.database != NULL && database.opened && database.record_read_statement == NULL && finalizes == 1);
  forced_finalize = 0;
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1 && database.checked_close_ack && finalizes == 1);
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1 && finalizes == 1);
  puts("active and failed close retain the same Database and never repeat consumed finalize or fake ACK: PASS");

  init(&library, &database);
  actql_native_sqlite_library other_library;
  actql_native_sqlite_database other;
  REQUIRE(read_one(&database) == 0);
  init(&other_library, &other);
  REQUIRE(read_one(&other) == 0 && other.record_read_statement != database.record_read_statement);
  REQUIRE(actql_native_sqlite_close_checked(&database) == 1);
  int before = prepares;
  REQUIRE(read_one(&database) == 5 && prepares == before);
  REQUIRE(read_one(&other) == 0 && prepares == before);
  REQUIRE(actql_native_sqlite_close_checked(&other) == 1);
  puts("different original Databases never share a slot and closed originals execute no SQL: PASS");
  puts("Physical read statement C cases: 8/8");
  return 0;
}
