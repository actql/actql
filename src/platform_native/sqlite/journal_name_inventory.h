#ifndef ACTQL_NATIVE_JOURNAL_NAME_INVENTORY_H
#define ACTQL_NATIVE_JOURNAL_NAME_INVENTORY_H

/* Same original Database and actql_records table. These physical controls do
 * not authenticate a name, grant access, begin/commit a transaction or repair
 * an existing database. The Native Journal owns its HMAC, issued CAS and scope. */
#define ACTQL_NAME_INSERT_TRIGGER \
  "CREATE TRIGGER actql_submission_names_insert AFTER INSERT ON actql_records " \
  "WHEN NEW.namespace='client_submission_names' BEGIN " \
  "UPDATE actql_records SET revision=revision+1," \
  "body=CAST(CAST(body AS INTEGER)+1 AS BLOB) " \
  "WHERE namespace='client_submission_name_custody' AND record_key='retained' " \
  "AND revision<9223372036854775807 AND CAST(body AS INTEGER)>=0 " \
  "AND CAST(body AS INTEGER)<1024 " \
  "AND CAST(CAST(body AS INTEGER) AS TEXT)=CAST(body AS TEXT);" \
  "SELECT CASE WHEN changes()=1 THEN 1 ELSE RAISE(ABORT,'name retained custody unavailable') END;END"
#define ACTQL_NAME_DELETE_TRIGGER \
  "CREATE TRIGGER actql_submission_names_delete AFTER DELETE ON actql_records " \
  "WHEN OLD.namespace='client_submission_names' BEGIN " \
  "UPDATE actql_records SET revision=revision+1," \
  "body=CAST(CAST(body AS INTEGER)-1 AS BLOB) " \
  "WHERE namespace='client_submission_name_custody' AND record_key='retained' " \
  "AND revision<9223372036854775807 AND CAST(body AS INTEGER)>0 " \
  "AND CAST(body AS INTEGER)<=1024 " \
  "AND CAST(CAST(body AS INTEGER) AS TEXT)=CAST(body AS TEXT);" \
  "SELECT CASE WHEN changes()=1 THEN 1 ELSE RAISE(ABORT,'name retained custody unavailable') END;END"

static bool actql_name_inventory_database_current(
    actql_native_sqlite_database *database) {
  return database != NULL && database->opened &&
    actql_database_library_available(database->library) &&
    !database->transaction_fenced && database->lookup_generation == 0;
}

/* 0 = absent historical extension, 1 = exact original definitions, -1 = refuse.
 * Inspect all triggers on this table, so unknown overlapping mutations cannot
 * impersonate the installed physical counter mechanism. */
int32_t actql_native_client_submission_name_schema(
    actql_native_sqlite_database *database) {
  if (!actql_name_inventory_database_current(database)) return -1;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "SELECT name,sql FROM sqlite_schema WHERE type='trigger' "
    "AND tbl_name='actql_records' ORDER BY name COLLATE BINARY", -1,
    &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return -1;
  }
  const char *names[] = {"actql_submission_names_delete", "actql_submission_names_insert"};
  const char *sql[] = {ACTQL_NAME_DELETE_TRIGGER, ACTQL_NAME_INSERT_TRIGGER};
  int count = 0;
  bool exact = true;
  while ((code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement)) == SQLITE_ROW) {
    if (count >= 2) { exact = false; break; }
    const void *name = database->library->column_blob(statement, 0);
    const void *body = database->library->column_blob(statement, 1);
    int name_size = database->library->column_bytes(statement, 0);
    int body_size = database->library->column_bytes(statement, 1);
    if (name == NULL || body == NULL || name_size != (int)strlen(names[count]) ||
        body_size != (int)strlen(sql[count]) ||
        memcmp(name, names[count], (size_t)name_size) != 0 ||
        memcmp(body, sql[count], (size_t)body_size) != 0) { exact = false; break; }
    count++;
  }
  int finalized = database->library->finalize(statement);
  if (!exact || code != SQLITE_DONE || finalized != SQLITE_OK) return -1;
  if (count == 0) return 0;
  if (count != 2) return -1;
  statement = NULL;
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "SELECT 1 FROM actql_records WHERE namespace='client_submission_name_custody' "
    "AND record_key NOT IN ('issued','retained') LIMIT 1", -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return -1;
  }
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  finalized = database->library->finalize(statement);
  return code == SQLITE_DONE && finalized == SQLITE_OK ? 1 : -1;
}

/* Original startup census, never the ordinary name-resolution path. Count the
 * indexed namespace without copying record bodies into another history array. */
int64_t actql_native_client_submission_name_census(
    actql_native_sqlite_database *database) {
  if (!actql_name_inventory_database_current(database) ||
      database->library->get_autocommit(database->database)) return -1;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "SELECT count(*) FROM actql_records WHERE namespace='client_submission_names'",
    -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return -1;
  }
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  int64_t count = code == SQLITE_ROW ? database->library->column_int64(statement, 0) : -1;
  if (code == SQLITE_ROW) code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  int finalized = database->library->finalize(statement);
  return code == SQLITE_DONE && finalized == SQLITE_OK ? count : -1;
}

/* Install only inside the original fresh bootstrap transaction, with both
 * original counters already initialized to zero and no retained name rows. */
int32_t actql_native_client_submission_name_install(
    actql_native_sqlite_database *database) {
  if (!actql_name_inventory_database_current(database) ||
      database->library->get_autocommit(database->database) ||
      actql_native_client_submission_name_schema(database) != 0 ||
      actql_native_client_submission_name_census(database) != 0) return 0;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(database->database,
    "SELECT count(*) FROM actql_records WHERE namespace='client_submission_name_custody' "
    "AND record_key IN ('issued','retained') AND revision=0 AND body=X'30'",
    -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return 0;
  }
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  bool original = code == SQLITE_ROW && database->library->column_int64(statement, 0) == 2;
  if (code == SQLITE_ROW) code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  int finalized = database->library->finalize(statement);
  if (!original || code != SQLITE_DONE || finalized != SQLITE_OK) return 0;
  return actql_exec(database, ACTQL_NAME_INSERT_TRIGGER) == SQLITE_OK &&
    actql_exec(database, ACTQL_NAME_DELETE_TRIGGER) == SQLITE_OK &&
    actql_native_client_submission_name_schema(database) == 1;
}

/* Faults apply only to the exact caller-owned diagnostic Database. */
void actql_native_client_test_submission_name_scan_refusal(
    actql_native_sqlite_database *database, int32_t refuse) {
  if (actql_name_inventory_database_current(database))
    database->test_name_scan_refusal = refuse != 0;
}
int32_t actql_native_client_test_submission_name_drop_trigger(
    actql_native_sqlite_database *database) {
  return actql_name_inventory_database_current(database) &&
    actql_exec(database, "DROP TRIGGER actql_submission_names_delete") == SQLITE_OK;
}
int32_t actql_native_client_test_submission_name_replace_trigger(
    actql_native_sqlite_database *database) {
  return actql_native_client_test_submission_name_drop_trigger(database) &&
    actql_exec(database, "CREATE TRIGGER actql_submission_names_delete AFTER DELETE ON actql_records "
      "WHEN OLD.namespace='client_submission_names' BEGIN SELECT 1;END") == SQLITE_OK;
}
#endif
