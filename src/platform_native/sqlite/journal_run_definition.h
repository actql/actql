#ifndef ACTQL_NATIVE_JOURNAL_RUN_DEFINITION_H
#define ACTQL_NATIVE_JOURNAL_RUN_DEFINITION_H

/* The index is the physical format discriminator, independent of removable
 * Journal records. It grants no authority and owns no transaction. */
#define ACTQL_RUN_DEFINITION_INDEX \
  "CREATE UNIQUE INDEX actql_client_run_definition_unique ON actql_records(" \
  "json_extract(json_extract(CAST(body AS TEXT),'$.run_definition')," \
  "'$.run_definition_cid')) WHERE namespace='client_runs'"

static bool actql_run_definition_database_current(
    actql_native_sqlite_database *database) {
  return database != NULL && database->opened &&
    actql_database_library_available(database->library) &&
    !database->transaction_fenced && database->lookup_generation == 0;
}

/* Probe the actual same Library, not compile options or a second SQLite. */
static bool actql_run_definition_json_available(
    actql_native_sqlite_database *database) {
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "SELECT json_extract(json_extract('{\"run_definition\":\"{\\\"run_definition_cid\\\":\\\"probe\\\"}\"}',"
    "'$.run_definition'),'$.run_definition_cid')", -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return false;
  }
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  const void *value = code == SQLITE_ROW ? database->library->column_blob(statement, 0) : NULL;
  bool exact = value != NULL && database->library->column_bytes(statement, 0) == 5 &&
    memcmp(value, "probe", 5) == 0;
  if (code == SQLITE_ROW)
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  int finalized = database->library->finalize(statement);
  return exact && code == SQLITE_DONE && finalized == SQLITE_OK;
}

/* 0 = legacy absent, 1 = exact, -1 = unsupported/current or colliding schema.
 * Typed Journal admission still rejects missing or malformed CID fields:
 * SQLite's UNIQUE NULL behavior is not an admission proof. */
int32_t actql_native_client_run_definition_schema(
    actql_native_sqlite_database *database) {
  if (!actql_run_definition_database_current(database) ||
      !actql_run_definition_json_available(database)) return -1;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "SELECT type,tbl_name,sql FROM sqlite_schema "
    "WHERE name='actql_client_run_definition_unique' COLLATE NOCASE", -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return -1;
  }
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  int result = code == SQLITE_DONE ? 0 : -1;
  if (code == SQLITE_ROW) {
    const char *expected[] = {"index", "actql_records", ACTQL_RUN_DEFINITION_INDEX};
    bool exact = true;
    for (int i = 0; i < 3; i++) {
      const void *value = database->library->column_blob(statement, i);
      int size = database->library->column_bytes(statement, i);
      if (value == NULL || size != (int)strlen(expected[i]) ||
          memcmp(value, expected[i], (size_t)size) != 0) exact = false;
    }
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if (exact && code == SQLITE_DONE) result = 1;
  }
  int finalized = database->library->finalize(statement);
  return code == SQLITE_DONE && finalized == SQLITE_OK ? result : -1;
}

/* Only the caller's existing transaction may install. The bounded streaming
 * prepass covers all table rows because even a partial-index build scans the
 * table. This is a work ceiling, not a byte-demand or allocation guarantee.
 * No body copies, census arrays, BEGIN, COMMIT, ROLLBACK or retry are added. */
int32_t actql_native_client_run_definition_install(
    actql_native_sqlite_database *database, int64_t max_inspect_rows) {
  if (!actql_run_definition_database_current(database) || max_inspect_rows < 0 ||
      max_inspect_rows > 536870912 ||
      database->library->get_autocommit(database->database) ||
      actql_native_client_run_definition_schema(database) != 0) return -1;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database, "SELECT 1 FROM actql_records", -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    actql_database_error(database, "prepare Run definition index bound failed");
    return -1;
  }
  int64_t rows = 0;
  bool exceeded = false;
  while ((code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement)) == SQLITE_ROW) {
    if (rows == max_inspect_rows) { exceeded = true; break; }
    rows++;
  }
  int finalized = database->library->finalize(statement);
  if (finalized != SQLITE_OK || (!exceeded && code != SQLITE_DONE)) {
    actql_database_error(database, "read Run definition index bound failed");
    return -1;
  }
  if (exceeded) return 6;
  if (actql_exec(database, ACTQL_RUN_DEFINITION_INDEX) != SQLITE_OK) return -1;
  return actql_native_client_run_definition_schema(database) == 1 ? 0 : -1;
}
#endif
