#ifndef ACTQL_NATIVE_JOURNAL_READ_EVIDENCE_H
#define ACTQL_NATIVE_JOURNAL_READ_EVIDENCE_H

/* Physical grouping of existing closed request wires, not request admission,
 * a capacity reservation, authority, a row-body copy or a transaction ACK. */
/* The expression rejects malformed indexed packets on later writes too.
 * json_remove leaves any extra/duplicate key behind. No request fields or
 * cryptographic meanings are reconstructed or accepted by this index. */
#define ACTQL_READ_EVIDENCE_REQUEST \
  "CASE WHEN json_valid(CAST(body AS TEXT)) THEN CASE WHEN " \
  "revision=0 AND typeof(revision)='integer' AND typeof(body)='blob' " \
  "AND length(body)>0 AND length(body)<=65536 " \
  "AND json_type(CAST(body AS TEXT))='object' " \
  "AND json_type(CAST(body AS TEXT),'$.authorization_context')='text' " \
  "AND json_type(CAST(body AS TEXT),'$.data_ceiling')='text' " \
  "AND json_type(CAST(body AS TEXT),'$.egress_admission')='text' " \
  "AND json_type(CAST(body AS TEXT),'$.request')='text' " \
  "AND length(CAST(json_extract(CAST(body AS TEXT),'$.request') AS BLOB)) " \
  "BETWEEN 1 AND 4096 AND json_remove(CAST(body AS TEXT)," \
  "'$.authorization_context','$.data_ceiling','$.egress_admission','$.request')='{}' " \
  "THEN json_extract(CAST(body AS TEXT),'$.request') " \
  "ELSE json('invalid read evidence') END ELSE json('invalid read evidence') END"

#define ACTQL_READ_EVIDENCE_INDEX \
  "CREATE INDEX actql_client_read_evidence_request ON actql_records(" \
  ACTQL_READ_EVIDENCE_REQUEST ") " \
  "WHERE namespace='client_local_read_evidence'"

static bool actql_read_evidence_database_current(
    actql_native_sqlite_database *database) {
  return database != NULL && database->opened && database->process == getpid() &&
    actql_database_library_available(database->library) &&
    !database->transaction_fenced && database->lookup_generation == 0;
}

/* 0 absent, 1 exact, existing BUSY or Physical on an unsupported/colliding
 * format. A named but different index cannot authorize a fallback table scan. */
int32_t actql_native_client_read_evidence_schema(
    actql_native_sqlite_database *database) {
  if (!actql_read_evidence_database_current(database)) return 5;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "SELECT type,tbl_name,sql FROM sqlite_schema "
    "WHERE name='actql_client_read_evidence_request' COLLATE NOCASE",
    -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return actql_operation_code(code);
  }
  code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
  int result = code == SQLITE_DONE ? 0 : -1;
  if (code == SQLITE_ROW) {
    const char *expected[] = {"index", "actql_records", ACTQL_READ_EVIDENCE_INDEX};
    bool exact = true;
    for (int i = 0; i < 3; i++) {
      const void *body = database->library->column_blob(statement, i);
      int size = database->library->column_bytes(statement, i);
      if (body == NULL || size != (int)strlen(expected[i]) ||
          memcmp(body, expected[i], (size_t)size) != 0) exact = false;
    }
    code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement);
    if (exact && code == SQLITE_DONE) result = 1;
  }
  if (code != SQLITE_DONE) result = actql_operation_code(code);
  int finalized = database->library->finalize(statement);
  return finalized == SQLITE_OK ? result : actql_operation_code(finalized);
}

/* Explicit maintenance only. Building even a partial index visits the table,
 * so stream a complete finite work bound before DDL. The caller retains its
 * original transaction, typed admission, rollback/Unknown and cleanup duty. */
int32_t actql_native_client_read_evidence_install(
    actql_native_sqlite_database *database, int64_t max_inspect_rows) {
  if (!actql_read_evidence_database_current(database)) return 5;
  if (max_inspect_rows < 0 || max_inspect_rows > 536870912 ||
      database->library->get_autocommit(database->database)) return -1;
  int state = actql_native_client_read_evidence_schema(database);
  if (state != 0) return state == 1 ? -1 : state;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "SELECT CASE WHEN namespace='client_local_read_evidence' THEN "
    "length(" ACTQL_READ_EVIDENCE_REQUEST ")>0 ELSE 1 END FROM actql_records",
    -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return actql_operation_code(code);
  }
  int64_t rows = 0;
  int result = 0;
  while ((code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement)) == SQLITE_ROW) {
    if (rows == max_inspect_rows) { result = 6; break; }
    rows++;
    if (database->library->column_int64(statement, 0) != 1) { result = -1; break; }
  }
  if (result == 0 && code != SQLITE_DONE) result = actql_operation_code(code);
  int finalized = database->library->finalize(statement);
  if (finalized != SQLITE_OK) return actql_operation_code(finalized);
  if (result != 0) return result;
  code = actql_exec(database, ACTQL_READ_EVIDENCE_INDEX);
  if (code != SQLITE_OK) return actql_operation_code(code);
  state = actql_native_client_read_evidence_schema(database);
  return state == 1 ? 0 : state == 0 ? -1 : state;
}

/* The existing coordinator admits the exact schema once at its operation
 * boundary, before calling this inside the same original transaction. This
 * getter does not repeat that admission; INDEXED BY forbids absent-index
 * fallback. No public callback or schema mutation may intervene in that fact.
 * Stop at max_entries+1; never decode/export unrelated history or row bodies. */
int32_t actql_native_client_read_evidence_usage(
    actql_native_sqlite_database *database,
    moonbit_bytes_t request_wire, int32_t request_length,
    int64_t max_entries, int64_t max_body_bytes) {
  if (!actql_read_evidence_database_current(database)) return 5;
  actql_clear_result(database);
  if (request_wire == NULL || request_length < 1 || request_length > 4096 ||
      max_entries < 0 || max_entries > 64 ||
      max_body_bytes < 0 || max_body_bytes > 65536 ||
      database->library->get_autocommit(database->database)) return -1;
  sqlite3_stmt *statement = NULL;
  int code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_QUERY, database->library->prepare_v2)(
    database->database,
    "SELECT length(body) FROM actql_records "
    "INDEXED BY actql_client_read_evidence_request "
    "WHERE namespace='client_local_read_evidence' "
    "AND (" ACTQL_READ_EVIDENCE_REQUEST ")=?1 COLLATE BINARY LIMIT ?2",
    -1, &statement, NULL);
  if (code != SQLITE_OK) {
    if (statement != NULL) database->library->finalize(statement);
    return actql_operation_code(code);
  }
  code = database->library->bind_text(statement, 1,
    (const char *)request_wire, request_length, SQLITE_TRANSIENT);
  if (code == SQLITE_OK)
    code = database->library->bind_int64(statement, 2, max_entries + 1);
  int result = code == SQLITE_OK ? 0 : actql_operation_code(code);
  int64_t entries = 0, bytes = 0;
  while (result == 0 &&
      (code = ACTQL_NATIVE_TIMED_CALL(ACTQL_NATIVE_COUNT_SQL_STEP, database->library->step)(statement)) == SQLITE_ROW) {
    int64_t length = database->library->column_int64(statement, 0);
    if (length < 1 || length > 65536) {
      result = -1;
    } else if (entries == max_entries || length > max_body_bytes - bytes) {
      result = 6;
    } else {
      entries++;
      bytes += length;
    }
  }
  if (result == 0 && code != SQLITE_DONE) result = actql_operation_code(code);
  int finalized = database->library->finalize(statement);
  if (finalized != SQLITE_OK) return actql_operation_code(finalized);
  if (result == 0) {
    database->result_record_count = entries;
    database->result_record_body_bytes = bytes;
  }
  return result;
}
#endif
