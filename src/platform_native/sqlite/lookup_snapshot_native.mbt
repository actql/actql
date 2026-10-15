///|
/// A private nominal child of the SAME fenced Database. No wire scalar can
/// construct it. Pending acquisition and failed stop retain this exact child;
/// physical cleanup is distinct from completion of an observation.
struct NativeLookupRead {
  database : Database
  mut generation : Int64
  mut ready : Bool
  mut retired : Bool
  mut completed : Bool
}

///|
#borrow(database)
extern "C" fn lookup_claim_ffi(database : Database) -> Int64 = "actql_native_sqlite_lookup_claim"

///|
#borrow(database)
extern "C" fn lookup_start_ffi(database : Database, generation : Int64) -> Int = "actql_native_sqlite_lookup_start"

///|
#borrow(database)
extern "C" fn lookup_current_ffi(
  database : Database,
  generation : Int64,
) -> Bool = "actql_native_sqlite_lookup_current"

///|
#borrow(database)
extern "C" fn lookup_stop_ffi(database : Database, generation : Int64) -> Int = "actql_native_sqlite_lookup_stop"

///|
#borrow(database)
extern "C" fn lookup_stopped_current_ffi(
  database : Database,
  generation : Int64,
) -> Bool = "actql_native_sqlite_lookup_stopped_current"

///|
/// Allocate custody before the first foreign read-start operation. Claiming
/// requires the actual original fenced connection to be physically NoActive.
/// A pending result MUST be retained for cleanup; it cannot repeat acquisition.
pub fn Database::prepare_lookup_read(
  self : Database,
) -> Result[NativeLookupReadAcquisition, NativeSqliteIssue] {
  let child : NativeLookupRead = {
    database: self,
    generation: 0L,
    ready: false,
    retired: false,
    completed: false,
  }
  let generation = lookup_claim_ffi(self)
  if generation <= 0L {
    return Err(Physical("original fenced Database cannot lend a read snapshot"))
  }
  child.generation = generation
  let code = lookup_start_ffi(self, generation)
  if code == 0 && lookup_current_ffi(self, generation) {
    child.ready = true
    Ok(ReadyLookupRead(child))
  } else {
    Ok(PendingLookupRead(child, operation_issue(self, code)))
  }
}

///|
/// Nominal connection identity, not a path/generation scalar supplied by Python.
pub fn Database::owns_lookup_read(
  self : Database,
  child : NativeLookupRead,
) -> Bool {
  physical_equal(self, child.database)
}

///|
pub fn NativeLookupRead::require_current(
  self : NativeLookupRead,
) -> Result[Unit, NativeSqliteIssue] {
  if !self.ready ||
    self.retired ||
    !lookup_current_ffi(self.database, self.generation) {
    self.ready = false
    Err(Physical("original read snapshot is not current"))
  } else {
    Ok(())
  }
}

///|
/// Only this read child's physical stop can complete its observation. Neither
/// success nor retry_cleanup acknowledges the older uncertain COMMIT.
pub fn NativeLookupRead::finish(
  self : NativeLookupRead,
) -> Result[Unit, NativeSqliteIssue] {
  if self.completed {
    return Ok(())
  }
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let code = lookup_stop_ffi(self.database, self.generation)
  self.ready = false
  if code != 0 {
    return Err(operation_issue(self.database, code))
  }
  self.retired = true
  if !lookup_stopped_current_ffi(self.database, self.generation) {
    return Err(Physical("read snapshot stopped without a current observation"))
  }
  self.completed = true
  Ok(())
}

///|
/// Drain/inspect the SAME start/stop attempt. No re-BEGIN or lost-stop resend.
/// This returns cleanup ACK only; a failed observation stays incomplete.
pub fn NativeLookupRead::retry_cleanup(
  self : NativeLookupRead,
) -> Result[Unit, NativeSqliteIssue] {
  if self.retired {
    return Ok(())
  }
  self.ready = false
  let code = lookup_stop_ffi(self.database, self.generation)
  if code != 0 {
    return Err(operation_issue(self.database, code))
  }
  self.retired = true
  Ok(())
}

///|
/// Closed bounded observation on this original read child; no mutation port.
pub fn NativeLookupRead::read_with_body_limit(
  self : NativeLookupRead,
  scope : String,
  key : String,
  max_body_bytes : Int64,
) -> Result[NativeJournalValue, NativeSqliteIssue] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self.database.read_with_body_limit(scope, key, max_body_bytes)
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  result
}

///|
/// Closed bounded observation on this original read child; no mutation port.
pub fn NativeLookupRead::scan_after_with_body_limit(
  self : NativeLookupRead,
  scope : String,
  after_key : String,
  max_body_bytes : Int64,
) -> Result[NativeJournalEntry, NativeSqliteIssue] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self.database.scan_after_with_body_limit(
    scope, after_key, max_body_bytes,
  )
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  result
}

///|
/// Closed bounded observation on this original read child; no mutation port.
pub fn NativeLookupRead::read_header(
  self : NativeLookupRead,
  scope : String,
  key : String,
) -> Result[NativeJournalHeader, NativeSqliteIssue] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self.database.read_header(scope, key)
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  result
}

///|
/// Closed bounded observation on this original read child; no mutation port.
pub fn NativeLookupRead::read_capacity(
  self : NativeLookupRead,
  scope : String,
  key : String,
) -> Result[NativeCapacityUsage, NativeSqliteIssue] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self.database.read_capacity(scope, key)
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  result
}

///|
/// Closed bounded observation on this original read child; no mutation port.
pub fn NativeLookupRead::capacity_usage(
  self : NativeLookupRead,
  scope : String,
) -> Result[NativeCapacityUsage, NativeSqliteIssue] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self.database.capacity_usage(scope)
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  result
}

///|
/// Closed bounded observation on this original read child; no mutation port.
pub fn NativeLookupRead::database_usage(
  self : NativeLookupRead,
) -> Result[NativeDatabaseUsage, NativeSqliteIssue] {
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let result = self.database.database_usage()
  match self.require_current() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  result
}
