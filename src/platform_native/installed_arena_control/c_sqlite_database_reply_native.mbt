///|
/// The original physical call result and its post-call fence are separate.
/// Neither row presence nor transport success acknowledges Run publication.
priv enum SqliteDatabaseReplyValue {
  DatabaseUnit
  DatabaseRevision(Int64)
  // Keep original row fields directly: an extra NativeJournalEntry wrapper
  // would remain live through the same funded post-call current check.
  DatabaseRow(String, Int64, Bytes)
  DatabaseHeader(Int64, Int64)
  CapacityChanged(Bool)
  CapacityUsage(Int64, Int64)
  DatabaseUsage(Int64, Int64, Int64)
  DatabaseTransactionState(Bool)
}

///|
struct InstalledArenaSqliteDatabaseReply {
  operation : Int
  host : InstalledArenaHost
  library : InstalledArenaSqliteLibrary
  original : InstalledArenaSqliteDatabase?
  // 0=before physical callback, 1=acquisition carrier, 2=callback observed,
  // 3=original close observation. This never describes a Run's outcome.
  stage : Int
  issue : InstalledArenaSqliteIssue?
  after : InstalledArenaSqliteIssue?
  value : SqliteDatabaseReplyValue?
}

///|
fn sqlite_database_open_reply(
  operation : Int,
  host : InstalledArenaHost,
  library : InstalledArenaSqliteLibrary,
  path : String,
  max_body_bytes : Int64,
  opening : InstalledArenaSqliteDatabaseOpening,
) -> InstalledArenaSqliteDatabaseReply {
  let (original, stage, issue) = match
    host.prepare_sqlite_database(library, path, max_body_bytes, opening) {
    Err(issue) => (None, 0, Some(issue))
    Ok(ReadySqliteDatabase(original)) => (Some(original), 1, None)
    Ok(PendingSqliteDatabase(original, issue)) =>
      (Some(original), 1, Some(issue))
  }
  {
    operation,
    host: library.domain.host,
    library,
    original,
    stage,
    issue,
    after: None,
    value: None,
  }
}

///|
pub fn restore_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  library : InstalledArenaSqliteLibrary,
  path : String,
  max_body_bytes : Int64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_open_reply(
    1,
    host,
    library,
    path,
    max_body_bytes,
    ExistingSqliteDatabase,
  )
}

///|
/// Trusted installed Root/adoption caller only. These original file facts are
/// physical fences, not proof that a saved initialization intent was admitted.
pub fn initialize_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  library : InstalledArenaSqliteLibrary,
  path : String,
  max_body_bytes : Int64,
  device : UInt64,
  inode : UInt64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_open_reply(
    2,
    host,
    library,
    path,
    max_body_bytes,
    InitializeOwnedSqliteDatabase({ device, inode, }),
  )
}

///|
fn sqlite_database_call_reply(
  operation : Int,
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  call : (@sqlite.Database) -> Result[
    SqliteDatabaseReplyValue,
    @sqlite.NativeSqliteIssue,
  ],
) -> InstalledArenaSqliteDatabaseReply {
  let (stage, value, issue, after) = match
    host.call_sqlite_database(original, call) {
    RefusedDatabaseCall(issue) => (0, None, Some(issue), None)
    ObservedDatabaseCall(Ok(value), after) => (2, Some(value), None, after)
    ObservedDatabaseCall(Err(issue), after) =>
      (2, None, Some(Library(issue)), after)
  }
  {
    operation,
    host: original.library.domain.host,
    library: original.library,
    original: Some(original),
    stage,
    value,
    issue,
    after,
  }
}

///|
pub fn observe_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(3, host, original, _ => Ok(DatabaseUnit))
}

///|
/// Keep the original uncertainty fence for all row/reservation observations.
/// An active original transaction is not a committed snapshot or an ACK.
fn sqlite_database_committed_observation(
  database : @sqlite.Database,
) -> Result[Unit, @sqlite.NativeSqliteIssue] {
  if !database.transaction_fenced() {
    return Ok(())
  }
  match database.transaction_state() {
    Ok(@sqlite.NoActiveSqliteTransaction) => Ok(())
    Ok(@sqlite.ActiveSqliteTransaction) =>
      Err(@sqlite.Physical("original SQLite transaction remains unconfirmed"))
    Err(issue) => Err(issue)
  }
}

///|
pub fn read_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  key : String,
  max_body_bytes : Int64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(4, host, original, database => {
    // A fenced connection may still expose its original committed rows, but
    // never an uncommitted transaction's private writes as durable lookup.
    match sqlite_database_committed_observation(database) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match database.read_with_body_limit(scope, key, max_body_bytes) {
      Ok(value) => Ok(DatabaseRow(key, value.revision, value.body))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// One bounded original row after the exact cursor. Neither NotFound nor this
/// row proves namespace completeness or acknowledges an inventory/Run.
pub fn scan_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  after_key : String,
  max_body_bytes : Int64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(12, host, original, database => {
    match sqlite_database_committed_observation(database) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match
      database.scan_after_with_body_limit(scope, after_key, max_body_bytes) {
      Ok(value) => Ok(DatabaseRow(value.key, value.revision, value.body))
      Err(issue) => Err(issue)
    }
  })
}

///|
pub fn insert_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  key : String,
  body : Bytes,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(5, host, original, database => {
    if database.transaction_fenced() {
      return Err(
        @sqlite.Physical("original SQLite transaction remains unconfirmed"),
      )
    }
    match database.insert(scope, key, body) {
      Ok(value) => Ok(DatabaseRevision(value))
      Err(issue) => Err(issue)
    }
  })
}

///|
pub fn compare_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  key : String,
  expected : Int64,
  body : Bytes,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(6, host, original, database => {
    if database.transaction_fenced() {
      return Err(
        @sqlite.Physical("original SQLite transaction remains unconfirmed"),
      )
    }
    match database.compare_exchange(scope, key, expected, body) {
      Ok(value) => Ok(DatabaseRevision(value))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// The operation selector is closed here. There is no arbitrary SQL executor.
pub fn transaction_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  operation : Int,
) -> InstalledArenaSqliteDatabaseReply {
  if operation != 7 && operation != 8 && operation != 9 {
    return {
      operation,
      host: original.library.domain.host,
      library: original.library,
      original: Some(original),
      stage: 0,
      issue: Some(Library(@sqlite.InvalidName)),
      after: None,
      value: None,
    }
  }
  sqlite_database_call_reply(operation, host, original, database => {
    if database.transaction_fenced() {
      return Err(
        @sqlite.Physical("original SQLite transaction remains unconfirmed"),
      )
    }
    let result = match operation {
      7 => database.begin_immediate()
      8 => database.commit()
      _ => database.rollback()
    }
    match result {
      Ok(_) => Ok(DatabaseUnit)
      Err(issue) => {
        // No reset or automatic rollback/retry. This is the SAME existing
        // physical handle's uncertainty fence, not a parallel transaction FSM.
        if operation == 8 || operation == 9 {
          database.fence_transactions()
        }
        Err(issue)
      }
    }
  })
}

///|
/// Only the original caller transaction changes physical reservation rows.
/// These amounts are trusted Host DATA, not a Resource grant or commit ACK.
pub fn reserve_installed_sqlite_capacity_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  key : String,
  bytes : Int64,
  objects : Int64,
  max_bytes : Int64,
  max_objects : Int64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(13, host, original, database => {
    if database.transaction_fenced() {
      return Err(
        @sqlite.Physical("original SQLite transaction remains unconfirmed"),
      )
    }
    match
      database.reserve_capacity_in_transaction(
        scope, key, bytes, objects, max_bytes, max_objects,
      ) {
      Ok(changed) => Ok(CapacityChanged(changed))
      Err(issue) => Err(issue)
    }
  })
}

///|
pub fn observe_installed_sqlite_capacity_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(14, host, original, database => {
    match sqlite_database_committed_observation(database) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match database.capacity_usage(scope) {
      Ok(value) =>
        Ok(CapacityUsage(value.reserved_bytes, value.reserved_objects))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Physical row release only. The existing caller must already hold the
/// independent original cleanup ACK; a successful SQL result supplies none.
pub fn release_installed_sqlite_capacity_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  key : String,
  bytes : Int64,
  objects : Int64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(15, host, original, database => {
    if database.transaction_fenced() {
      return Err(
        @sqlite.Physical("original SQLite transaction remains unconfirmed"),
      )
    }
    match database.release_capacity_in_transaction(scope, key, bytes, objects) {
      Ok(changed) => Ok(CapacityChanged(changed))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Original reservation lookup only. A fenced, still-active transaction must
/// not provide its private reservation as reconciliation of committed storage.
pub fn read_installed_sqlite_capacity_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  key : String,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(16, host, original, database => {
    match sqlite_database_committed_observation(database) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match database.read_capacity(scope, key) {
      Ok(value) =>
        Ok(CapacityUsage(value.reserved_bytes, value.reserved_objects))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Raw same-database totals, never an admitted inventory or resource credit.
pub fn observe_installed_sqlite_database_usage_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(17, host, original, database => {
    match sqlite_database_committed_observation(database) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match database.database_usage() {
      Ok(value) =>
        Ok(
          DatabaseUsage(
            value.record_count,
            value.body_bytes,
            value.reservation_count,
          ),
        )
      Err(issue) => Err(issue)
    }
  })
}

///|
/// The original SQLite connection's state only. In particular, autocommit is
/// not the acknowledgment of any particular COMMIT or permission to retry.
pub fn observe_installed_sqlite_transaction_state_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(18, host, original, database => {
    match database.transaction_state() {
      Ok(@sqlite.NoActiveSqliteTransaction) =>
        Ok(DatabaseTransactionState(false))
      Ok(@sqlite.ActiveSqliteTransaction) => Ok(DatabaseTransactionState(true))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Scalar original header, without a body-copy permission or borrowed payload.
pub fn read_installed_sqlite_header_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  key : String,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(19, host, original, database => {
    match sqlite_database_committed_observation(database) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    match database.read_header(scope, key) {
      Ok(value) => Ok(DatabaseHeader(value.revision, value.body_bytes))
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Normal, confirmed connection only. Unconfirmed read-snapshot adoption is
/// deliberately not inferred from autocommit or an inactive DATA observation.
pub fn begin_installed_sqlite_read_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(20, host, original, database => {
    if database.transaction_fenced() {
      return Err(
        @sqlite.Physical("original SQLite transaction remains unconfirmed"),
      )
    }
    match database.begin_deferred() {
      Ok(_) => Ok(DatabaseUnit)
      Err(issue) => Err(issue)
    }
  })
}

///|
/// Existing byte-store record-count ceiling plus the original SQLite capacity
/// formula, in the SAME active transaction. No reservation/credit is reissued.
pub fn reserve_installed_sqlite_bounded_capacity_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
  scope : String,
  key : String,
  bytes : Int64,
  objects : Int64,
  max_bytes : Int64,
  max_objects : Int64,
  max_reservations : Int64,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(21, host, original, database => {
    if max_reservations < 1L || max_reservations > 1024L {
      return Err(@sqlite.InvalidLimit)
    }
    if database.transaction_fenced() {
      return Err(
        @sqlite.Physical("original SQLite transaction remains unconfirmed"),
      )
    }
    match database.transaction_state() {
      Ok(@sqlite.ActiveSqliteTransaction) => ()
      Ok(@sqlite.NoActiveSqliteTransaction) =>
        return Err(
          @sqlite.Physical(
            "capacity reservation requires an active transaction",
          ),
        )
      Err(issue) => return Err(issue)
    }
    match database.read_capacity(scope, key) {
      Ok(_) => ()
      Err(@sqlite.NotFound) =>
        match database.database_usage() {
          Ok(usage) =>
            if usage.reservation_count >= max_reservations {
              return Err(@sqlite.CapacityExceeded)
            }
          Err(issue) => return Err(issue)
        }
      Err(issue) => return Err(issue)
    }
    match
      database.reserve_capacity_in_transaction(
        scope, key, bytes, objects, max_bytes, max_objects,
      ) {
      Ok(changed) => Ok(CapacityChanged(changed))
      Err(issue) => Err(issue)
    }
  })
}

///|
pub fn close_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
) -> InstalledArenaSqliteDatabaseReply {
  let issue = match host.close_sqlite_database(original) {
    Ok(_) => None
    Err(issue) => Some(issue)
  }
  {
    operation: 10,
    host: original.library.domain.host,
    library: original.library,
    original: Some(original),
    stage: 3,
    issue,
    after: None,
    value: None,
  }
}

///|
/// The trusted transport observed an unconfirmed response on this SAME
/// original Database. Fence its existing physical Owner without SQL/replay or
/// clearing any prior uncertainty; original committed lookup stays separate.
pub fn fence_installed_sqlite_database_reply(
  host : InstalledArenaHost,
  original : InstalledArenaSqliteDatabase,
) -> InstalledArenaSqliteDatabaseReply {
  sqlite_database_call_reply(11, host, original, database => {
    database.fence_transactions()
    Ok(DatabaseUnit)
  })
}

///|
pub fn InstalledArenaSqliteDatabaseReply::original_host(
  self : InstalledArenaSqliteDatabaseReply,
) -> InstalledArenaHost {
  self.host
}

///|
pub fn InstalledArenaSqliteDatabaseReply::original_library(
  self : InstalledArenaSqliteDatabaseReply,
) -> InstalledArenaSqliteLibrary {
  self.library
}

///|
pub fn InstalledArenaSqliteDatabaseReply::original_database(
  self : InstalledArenaSqliteDatabaseReply,
) -> InstalledArenaSqliteDatabase? {
  self.original
}

///|
pub fn InstalledArenaSqliteDatabaseReply::operation_tag(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int {
  self.operation
}

///|
pub fn InstalledArenaSqliteDatabaseReply::stage_tag(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int {
  self.stage
}

///|
pub fn InstalledArenaSqliteDatabaseReply::issue_family(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int {
  sqlite_reply_issue_family(self.issue)
}

///|
pub fn InstalledArenaSqliteDatabaseReply::after_issue_family(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int {
  sqlite_reply_issue_family(self.after)
}

///|
pub fn InstalledArenaSqliteDatabaseReply::has_row(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int {
  if self.value is Some(DatabaseRow(_, _, _)) {
    1
  } else {
    0
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::revision(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int64 {
  match self.value {
    Some(DatabaseRevision(value)) => value
    Some(DatabaseRow(_, revision, _)) => revision
    Some(DatabaseHeader(revision, _)) => revision
    _ => -1L
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::body(
  self : InstalledArenaSqliteDatabaseReply,
) -> Bytes {
  match self.value {
    Some(DatabaseRow(_, _, body)) => body
    _ => b""
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::body_bound(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int64 {
  match self.original {
    Some(original) => original.max_body_bytes
    None => -1L
  }
}

///|
/// Original row key DATA only. Copy and release inside the same managed scope.
pub fn InstalledArenaSqliteDatabaseReply::row_key_bytes(
  self : InstalledArenaSqliteDatabaseReply,
) -> Bytes {
  match self.value {
    Some(DatabaseRow(key, _, _)) => @utf8.encode(key)
    _ => b""
  }
}

///|
/// -1 means this exact reply contains no reservation-change observation.
pub fn InstalledArenaSqliteDatabaseReply::capacity_changed(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int {
  match self.value {
    Some(CapacityChanged(true)) => 1
    Some(CapacityChanged(false)) => 0
    _ => -1
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::reserved_bytes(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int64 {
  match self.value {
    Some(CapacityUsage(bytes, _)) => bytes
    _ => -1L
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::reserved_objects(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int64 {
  match self.value {
    Some(CapacityUsage(_, objects)) => objects
    _ => -1L
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::record_count(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int64 {
  match self.value {
    Some(DatabaseUsage(records, _, _)) => records
    _ => -1L
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::record_body_bytes(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int64 {
  match self.value {
    Some(DatabaseUsage(_, bytes, _)) => bytes
    _ => -1L
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::reservation_count(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int64 {
  match self.value {
    Some(DatabaseUsage(_, _, reservations)) => reservations
    _ => -1L
  }
}

///|
/// -1 means no physical state DATA, not inactive or safe to resend.
pub fn InstalledArenaSqliteDatabaseReply::transaction_active(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int {
  match self.value {
    Some(DatabaseTransactionState(active)) => if active { 1 } else { 0 }
    _ => -1
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::has_header(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int {
  if self.value is Some(DatabaseHeader(_, _)) {
    1
  } else {
    0
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::header_body_bytes(
  self : InstalledArenaSqliteDatabaseReply,
) -> Int64 {
  match self.value {
    Some(DatabaseHeader(_, length)) => length
    _ => -1L
  }
}
