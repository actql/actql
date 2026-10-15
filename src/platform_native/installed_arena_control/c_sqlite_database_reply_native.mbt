///|
/// The original physical call result and its post-call fence are separate.
/// Neither row presence nor transport success acknowledges Run publication.
priv enum SqliteDatabaseReplyValue {
  DatabaseUnit
  DatabaseRevision(Int64)
  DatabaseRow(@sqlite.NativeJournalEntry)
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
    if database.transaction_fenced() {
      match database.transaction_state() {
        Ok(@sqlite.NoActiveSqliteTransaction) => ()
        Ok(@sqlite.ActiveSqliteTransaction) =>
          return Err(
            @sqlite.Physical("original SQLite transaction remains unconfirmed"),
          )
        Err(issue) => return Err(issue)
      }
    }
    match database.read_with_body_limit(scope, key, max_body_bytes) {
      Ok(value) =>
        Ok(DatabaseRow({ key, revision: value.revision, body: value.body, }))
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
    if database.transaction_fenced() {
      match database.transaction_state() {
        Ok(@sqlite.NoActiveSqliteTransaction) => ()
        Ok(@sqlite.ActiveSqliteTransaction) =>
          return Err(
            @sqlite.Physical("original SQLite transaction remains unconfirmed"),
          )
        Err(issue) => return Err(issue)
      }
    }
    match
      database.scan_after_with_body_limit(scope, after_key, max_body_bytes) {
      Ok(value) => Ok(DatabaseRow(value))
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
  if self.value is Some(DatabaseRow(_)) {
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
    Some(DatabaseRow(value)) => value.revision
    _ => -1L
  }
}

///|
pub fn InstalledArenaSqliteDatabaseReply::body(
  self : InstalledArenaSqliteDatabaseReply,
) -> Bytes {
  match self.value {
    Some(DatabaseRow(value)) => value.body
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
    Some(DatabaseRow(value)) => @utf8.encode(value.key)
    _ => b""
  }
}
