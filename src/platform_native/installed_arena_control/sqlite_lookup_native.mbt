///|
/// Persistent controller registered before entering the original child scope.
/// It retains the SAME Database's ready/pending read, including postcheck loss.
/// This is no second transaction Owner and cannot supply Store authority.
struct InstalledArenaSqliteLookup {
  database : InstalledArenaSqliteDatabase
  mut original : @sqlite.NativeLookupRead?
  mut failed : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaSqliteLookupAcquisition {
  ReadySqliteLookup(InstalledArenaSqliteLookup)
  PendingSqliteLookup(InstalledArenaSqliteLookup, InstalledArenaSqliteIssue)
}

///|
fn InstalledArenaHost::original_sqlite_lookup(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteLookup,
) -> Result[Unit, InstalledArenaSqliteIssue] {
  match self.original_sqlite_database(record.database) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !(record.database.lookup is Some(original) &&
    physical_equal(original, record)) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  Ok(())
}

///|
/// Current/nominal refusal occurs before child registration. Once the physical
/// start may have been reached, preserve its child BEFORE the outer postcheck.
pub fn InstalledArenaHost::prepare_sqlite_lookup(
  self : InstalledArenaHost,
  database : InstalledArenaSqliteDatabase,
) -> Result[InstalledArenaSqliteLookupAcquisition, InstalledArenaSqliteIssue] {
  match self.original_sqlite_database(database) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match self.current_sqlite_library(database.library) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if database.failed ||
    database.closed ||
    database.scope_open ||
    database.calling {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)))
  }
  if database.lookup is Some(previous) && !previous.closed {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  let record : InstalledArenaSqliteLookup = {
    database,
    original: None,
    failed: false,
    closed: false,
  }
  database.lookup = Some(record)
  let result = self.call_sqlite_database_owned(database, Some(record), physical => {
    match physical.prepare_lookup_read() {
      Err(issue) => Err(issue)
      Ok(@sqlite.ReadyLookupRead(original)) => {
        record.original = Some(original)
        Ok(())
      }
      Ok(@sqlite.PendingLookupRead(original, issue)) => {
        record.original = Some(original)
        Err(issue)
      }
    }
  })
  match result {
    ObservedDatabaseCall(Ok(_), None) => Ok(ReadySqliteLookup(record))
    RefusedDatabaseCall(issue) => {
      record.failed = true
      Ok(PendingSqliteLookup(record, issue))
    }
    ObservedDatabaseCall(Err(issue), _) => {
      record.failed = true
      Ok(PendingSqliteLookup(record, Library(issue)))
    }
    ObservedDatabaseCall(Ok(_), Some(issue)) => {
      record.failed = true
      Ok(PendingSqliteLookup(record, issue))
    }
  }
}

///|
/// The exact original live read child is the only active-fenced read port.
/// Ordinary Database calls retain their refusal; there is no Bool exception.
pub fn[T] InstalledArenaHost::call_sqlite_lookup(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteLookup,
  call : (@sqlite.NativeLookupRead) -> Result[T, @sqlite.NativeSqliteIssue],
) -> InstalledArenaSqliteDatabaseCall[T] {
  match self.original_sqlite_lookup(record) {
    Err(issue) => return RefusedDatabaseCall(issue)
    Ok(_) => ()
  }
  if record.failed || record.closed {
    return RefusedDatabaseCall(
      Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
    )
  }
  guard record.original is Some(original) else {
    return RefusedDatabaseCall(
      Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
    )
  }
  // Reuse the SAME entry/postcheck Owner without retaining another captured
  // trampoline throughout the physical read. Its allocations use the original
  // finite arena too; there is no additional capacity or allocator fallback.
  let physical = match
    self.enter_sqlite_database_call(record.database, Some(record)) {
    Err(issue) => return RefusedDatabaseCall(issue)
    Ok(physical) => physical
  }
  let value = if !physical.owns_lookup_read(original) {
    Err(@sqlite.Physical("foreign original SQLite read child"))
  } else {
    match original.require_current() {
      Err(issue) => Err(issue)
      Ok(_) => {
        let value = call(original)
        match original.require_current() {
          Err(issue) => Err(issue)
          Ok(_) => value
        }
      }
    }
  }
  let result = self.finish_sqlite_database_call(record.database, value)
  if result is ObservedDatabaseCall(_, Some(_)) {
    record.failed = true
  }
  result
}

///|
/// Completion is separate from cleanup. The original Host's postcheck and
/// physical stop must both ACK before the installed caller publishes a scan.
pub fn InstalledArenaHost::finish_sqlite_lookup(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteLookup,
) -> InstalledArenaSqliteDatabaseCall[Unit] {
  match self.original_sqlite_lookup(record) {
    Err(issue) => return RefusedDatabaseCall(issue)
    Ok(_) => ()
  }
  if record.failed || record.closed {
    return RefusedDatabaseCall(
      Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
    )
  }
  guard record.original is Some(original) else {
    return RefusedDatabaseCall(
      Domain(@bootstrap.Bootstrap(@bootstrap.Unavailable)),
    )
  }
  let result = self.call_sqlite_database_owned(record.database, Some(record), physical => {
    if !physical.owns_lookup_read(original) {
      return Err(@sqlite.Physical("foreign original SQLite read child"))
    }
    match original.finish() {
      Err(issue) => Err(issue)
      Ok(_) => {
        record.original = None
        Ok(())
      }
    }
  })
  if result is ObservedDatabaseCall(Ok(_), None) {
    record.closed = true
    record.database.lookup = None
  } else {
    record.failed = true
  }
  result
}

///|
/// Same child-first cleanup even after current failure or logical closing.
/// Failed scope leave/physical stop retains the same child and parent debt.
pub fn InstalledArenaHost::close_sqlite_lookup(
  self : InstalledArenaHost,
  record : InstalledArenaSqliteLookup,
) -> Result[Unit, InstalledArenaSqliteIssue] {
  // Cut the reverse registration only after all original cleanup ACKs. A
  // repeated closed cleanup may acknowledge that old retirement, but cannot
  // touch a later child's registration or regain read permission.
  if record.closed && record.database.lookup is None {
    return self.original_sqlite_database(record.database)
  }
  match self.original_sqlite_lookup(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let database = record.database
  if database.calling {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  if record.closed {
    return Ok(())
  }
  record.failed = true
  if database.scope_open {
    match self.leave_domain_read(database.library.domain) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => database.scope_open = false
    }
  }
  if record.original is None {
    record.closed = true
    database.lookup = None
    return Ok(())
  }
  match self.enter_domain_read_cleanup(database.library.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => database.scope_open = true
  }
  let cleanup = match record.original {
    None => Ok(())
    Some(original) =>
      match original.retry_cleanup() {
        Err(issue) => Err(Library(issue))
        Ok(_) => {
          record.original = None
          Ok(())
        }
      }
  }
  let leave = self.leave_domain_read(database.library.domain)
  if leave is Ok(_) {
    database.scope_open = false
  }
  match cleanup {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match leave {
    Err(issue) => Err(Domain(issue))
    Ok(_) => {
      record.closed = true
      database.lookup = None
      Ok(())
    }
  }
}
