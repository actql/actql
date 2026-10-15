///|
/// One installed private Store per original Library. This is a retained view
/// of the existing Database/failed-open Owner, not another transaction ledger.
struct InstalledArenaSqliteDatabase {
  library : InstalledArenaSqliteLibrary
  max_body_bytes : Int64
  mut database : @sqlite.Database?
  mut failure : @sqlite.NativeSqliteOpenFailure?
  mut failed : Bool
  mut scope_open : Bool
  mut calling : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaSqliteDatabaseOpening {
  ExistingSqliteDatabase
  InitializeOwnedSqliteDatabase(@filesystem.NativeFileOwnership)
}

///|
pub(all) enum InstalledArenaSqliteDatabaseAcquisition {
  ReadySqliteDatabase(InstalledArenaSqliteDatabase)
  PendingSqliteDatabase(InstalledArenaSqliteDatabase, InstalledArenaSqliteIssue)
}

///|
/// Preserve whether the physical callback was reached and its exact result.
/// A post-call current/leave failure cannot turn COMMIT into an unattempted
/// operation or authorize replay. The original caller keeps reconciliation.
pub(all) enum InstalledArenaSqliteDatabaseCall[T] {
  RefusedDatabaseCall(InstalledArenaSqliteIssue)
  ObservedDatabaseCall(
    Result[T, @sqlite.NativeSqliteIssue],
    InstalledArenaSqliteIssue?
  )
}

///|
fn InstalledArenaHost::original_sqlite_database(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteDatabase,
) -> Result[Unit, InstalledArenaSqliteIssue] {
  match self.original_sqlite_library(record.library) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !(record.library.database is Some(original) &&
    physical_equal(original, record)) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  Ok(())
}

///|
/// The installed caller first binds its Root/Store epoch and saved intent.
/// Initialize uses only the original exclusive file; restore never creates or
/// repairs. Path/ownership scalars do not supply adoption or authorization.
pub fn InstalledArenaHost::prepare_sqlite_database(
  self : InstalledArenaHost,
  library : InstalledArenaSqliteLibrary,
  path : String,
  max_body_bytes : Int64,
  opening : InstalledArenaSqliteDatabaseOpening,
) -> Result[InstalledArenaSqliteDatabaseAcquisition, InstalledArenaSqliteIssue] {
  let original = match self.current_sqlite_library(library) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  if library.database is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
  }
  let record : InstalledArenaSqliteDatabase = {
    library,
    max_body_bytes,
    database: None,
    failure: None,
    failed: false,
    scope_open: false,
    calling: false,
    closed: false,
  }
  library.database = Some(record)
  let mut primary_issue : InstalledArenaSqliteIssue? = None
  match self.enter_domain_read(library.domain) {
    Err(issue) =>
      primary_issue = first_sqlite_issue(primary_issue, Domain(issue))
    Ok(_) => {
      record.scope_open = true
      let opened = match opening {
        ExistingSqliteDatabase =>
          original.open_existing_database_with_custody(path, max_body_bytes)
        InitializeOwnedSqliteDatabase(ownership) =>
          original.initialize_owned_database_with_custody(
            path, ownership, max_body_bytes,
          )
      }
      match opened {
        Ok(database) => record.database = Some(database)
        Err(failure) => {
          record.failure = Some(failure)
          primary_issue = first_sqlite_issue(
            primary_issue,
            Library(failure.issue()),
          )
        }
      }
      match self.require_domain_read_current(library.domain) {
        Err(issue) =>
          primary_issue = first_sqlite_issue(primary_issue, Domain(issue))
        Ok(_) => ()
      }
      match self.leave_domain_read(library.domain) {
        Err(issue) =>
          primary_issue = first_sqlite_issue(primary_issue, Domain(issue))
        Ok(_) => record.scope_open = false
      }
    }
  }
  record.failed = primary_issue is Some(_)
  match primary_issue {
    None => Ok(ReadySqliteDatabase(record))
    Some(issue) => Ok(PendingSqliteDatabase(record, issue))
  }
}

///|
/// Run existing typed Database operations inside the original managed scope.
/// Returned rows/diagnostics remain actual aliases until their caller releases
/// them. No scope exit, read or physical SQL result acknowledges a Run/Store.
pub fn[T] InstalledArenaHost::call_sqlite_database(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteDatabase,
  call : (@sqlite.Database) -> Result[T, @sqlite.NativeSqliteIssue],
) -> InstalledArenaSqliteDatabaseCall[T] {
  match self.original_sqlite_database(record) {
    Err(issue) => return RefusedDatabaseCall(issue)
    Ok(_) => ()
  }
  match self.current_sqlite_library(record.library) {
    Err(issue) => return RefusedDatabaseCall(issue)
    Ok(_) => ()
  }
  if record.failed || record.closed || record.scope_open {
    return RefusedDatabaseCall(
      Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
    )
  }
  guard record.database is Some(database) else {
    return RefusedDatabaseCall(
      Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
    )
  }
  match self.enter_domain_read(record.library.domain) {
    Err(issue) => return RefusedDatabaseCall(Domain(issue))
    Ok(_) => record.scope_open = true
  }
  record.calling = true
  let result = call(database)
  record.calling = false
  let mut after : InstalledArenaSqliteIssue? = None
  match self.require_domain_read_current(record.library.domain) {
    Err(issue) => after = first_sqlite_issue(after, Domain(issue))
    Ok(_) => ()
  }
  match self.leave_domain_read(record.library.domain) {
    Err(issue) => after = first_sqlite_issue(after, Domain(issue))
    Ok(_) => record.scope_open = false
  }
  if after is Some(_) {
    record.failed = true
  }
  ObservedDatabaseCall(result, after)
}

///|
/// Retire the SAME Database or failed-open carrier before its Library. A
/// failed cleanup/leave retains the same child and original parent custody.
pub fn InstalledArenaHost::close_sqlite_database(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteDatabase,
) -> Result[Unit, InstalledArenaSqliteIssue] {
  match self.original_sqlite_database(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.calling {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  if record.closed {
    return Ok(())
  }
  if record.scope_open {
    match self.leave_domain_read(record.library.domain) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => record.scope_open = false
    }
  }
  if record.database is None && record.failure is None {
    record.closed = true
    return Ok(())
  }
  match self.enter_domain_read_cleanup(record.library.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => record.scope_open = true
  }
  let cleanup = match record.database {
    Some(database) =>
      match database.close_checked() {
        Err(issue) => Err(Library(issue))
        Ok(_) => {
          record.database = None
          Ok(())
        }
      }
    None =>
      match record.failure {
        Some(failure) =>
          match failure.retry_cleanup() {
            Err(issue) => Err(Library(issue))
            Ok(_) => {
              record.failure = None
              Ok(())
            }
          }
        None => Ok(())
      }
  }
  let leave = self.leave_domain_read(record.library.domain)
  if leave is Ok(_) {
    record.scope_open = false
  }
  match cleanup {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match leave {
    Err(issue) => Err(Domain(issue))
    Ok(_) => {
      record.closed = true
      Ok(())
    }
  }
}
