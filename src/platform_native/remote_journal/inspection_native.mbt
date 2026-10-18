///|
priv type JournalInspection

///|
/// Cleanup-only owner for a failed Coordinator format inspection. The source
/// journal is never opened normally while this responsibility is pending.
struct CoordinatorInitializationCleanup {
  inspection : JournalInspection
  path : Result[String, NativeRemoteJournalIssue]
  max_record_bytes : Int64
  journal_private_index : Bool
  mut database : @sqlite.Database?
  mut open_attempted : Bool
  mut closing : Bool
  mut pending : Bool
}

///|
pub fn CoordinatorInitializationCleanup::pending(
  self : CoordinatorInitializationCleanup,
) -> Bool {
  self.pending
}

///|
#borrow(path)
extern "C" fn inspection_open(path : Bytes, length : Int) -> JournalInspection = "actql_journal_inspection_open"

///|
#borrow(path)
extern "C" fn inspection_open_bounded(
  path : Bytes,
  length : Int,
  max_snapshot_bytes : Int64,
) -> JournalInspection = "actql_journal_inspection_open_bounded"

///|
#borrow(owner)
extern "C" fn inspection_limit_exceeded(owner : JournalInspection) -> Bool = "actql_journal_inspection_limit_exceeded"

///|
#borrow(owner)
extern "C" fn inspection_ready(owner : JournalInspection) -> Bool = "actql_journal_inspection_ready"

///|
#borrow(owner)
extern "C" fn inspection_path(owner : JournalInspection) -> Bytes = "actql_journal_inspection_path"

///|
#borrow(owner)
extern "C" fn inspection_error(owner : JournalInspection) -> Bytes = "actql_journal_inspection_error"

///|
#borrow(owner)
extern "C" fn inspection_validate(owner : JournalInspection) -> Bool = "actql_journal_inspection_validate"

///|
#borrow(owner)
extern "C" fn inspection_close(owner : JournalInspection) -> Bool = "actql_journal_inspection_close"

///|
#borrow(owner)
extern "C" fn inspection_prepare_private_index(
  owner : JournalInspection,
) -> Bool = "actql_journal_inspection_prepare_private_index"

///|
#borrow(owner)
extern "C" fn inspection_private_index_ready(owner : JournalInspection) -> Bool = "actql_journal_inspection_private_index_ready"

///|
fn inspection_issue(owner : JournalInspection) -> NativeRemoteJournalIssue {
  if inspection_limit_exceeded(owner) {
    return Physical(@sqlite.CapacityExceeded)
  }
  let message = @utf8.decode(inspection_error(owner)) catch {
    _ => "invalid inspection diagnostic"
  }
  Physical(@sqlite.Physical(message))
}

///|
// Capture the exact snapshot before exposing any operation that can fail. Path
// decoding belongs to snapshot preparation, separately from opening SQLite.
fn capture_sqlite_inspection(
  inspection : JournalInspection,
  max_record_bytes : Int64,
) -> CoordinatorInitializationCleanup {
  let path = if max_record_bytes < 0L {
    Err(Physical(@sqlite.InvalidLimit))
  } else if !inspection_ready(inspection) {
    Err(inspection_issue(inspection))
  } else {
    Ok(@utf8.decode(inspection_path(inspection))) catch {
      _ => Err(Physical(@sqlite.Physical("invalid inspection path")))
    }
  }
  {
    inspection,
    path,
    max_record_bytes,
    journal_private_index: false,
    database: None,
    open_attempted: false,
    closing: false,
    pending: true,
  }
}

///|
/// Capture the existing bounded read-only inspection and its cleanup duty.
/// Retain the returned owner before attempting a different resource phase.
/// Except for invalid limits rejected before capture, physical preparation
/// errors remain in this same owner and are returned by `open_database`.
/// This is neither source admission nor a normal writer or resource grant.
pub fn prepare_sqlite_source_inspection(
  path : String,
  max_record_bytes : Int64,
  max_snapshot_bytes : Int64,
) -> Result[CoordinatorInitializationCleanup, NativeRemoteJournalIssue] {
  if max_record_bytes < 0L || max_snapshot_bytes < 0L {
    return Err(Physical(@sqlite.InvalidLimit))
  }
  let bytes = @utf8.encode(path)
  Ok(
    capture_sqlite_inspection(
      inspection_open_bounded(bytes, bytes.length(), max_snapshot_bytes),
      max_record_bytes,
    ),
  )
}

///|
/// Select only the private copied Journal's read-only heap-index route. The
/// same snapshot owns the exclusively created empty SHM and every partial
/// preparation failure. This does not admit the source or acquire its Lock.
/// The trusted Native command caller must retain its original Session/Lock.
pub fn prepare_sqlite_journal_source_inspection(
  path : String,
  max_record_bytes : Int64,
  max_snapshot_bytes : Int64,
) -> Result[CoordinatorInitializationCleanup, NativeRemoteJournalIssue] {
  if max_record_bytes < 0L || max_snapshot_bytes < 0L {
    return Err(Physical(@sqlite.InvalidLimit))
  }
  let bytes = @utf8.encode(path)
  let inspection = inspection_open_bounded(
    bytes,
    bytes.length(),
    max_snapshot_bytes,
  )
  let selected = inspection_prepare_private_index(inspection)
  let captured = capture_sqlite_inspection(inspection, max_record_bytes)
  Ok({
    ..captured,
    journal_private_index: true,
    path: if selected {
      captured.path
    } else {
      Err(inspection_issue(inspection))
    },
  })
}

///|
/// Open this captured copy at most once. The same owner retains the actual DB
/// before checking its inspection status. `None` is physical source absence,
/// never permission to initialize. Retaining a DB alias does not retire it.
pub fn CoordinatorInitializationCleanup::open_database(
  self : CoordinatorInitializationCleanup,
  library : @sqlite.Library,
) -> Result[@sqlite.Database?, NativeRemoteJournalIssue] {
  if self.closing || !self.pending {
    return Err(Closed)
  }
  if self.open_attempted {
    return Err(StateCollision)
  }
  self.open_attempted = true
  let path = match self.path {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !path.is_empty() {
    let database = if self.journal_private_index {
      if !inspection_private_index_ready(self.inspection) {
        return Err(inspection_issue(self.inspection))
      }
      library.open_journal_inspection_database(path, self.max_record_bytes)
    } else {
      library.open_inspection_database(path, self.max_record_bytes)
    }
    self.database = Some(database)
    match database.inspection_status() {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
  }
  Ok(self.database)
}

///|
/// Check the captured source generation after the caller's read-only audit.
/// This does not admit the row contents or authorize a later normal writer.
pub fn CoordinatorInitializationCleanup::validate_source(
  self : CoordinatorInitializationCleanup,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closing || !self.pending {
    return Err(Closed)
  }
  if !self.open_attempted {
    return Err(StateCollision)
  }
  if !inspection_validate(self.inspection) {
    return Err(inspection_issue(self.inspection))
  }
  Ok(())
}

///|
/// Cleanup-only SQLite phase. A failed physical close retains the same DB;
/// no later open or source validation can resume the abandoned admission.
pub fn CoordinatorInitializationCleanup::close_database(
  self : CoordinatorInitializationCleanup,
) -> Result[Unit, NativeRemoteJournalIssue] {
  self.closing = true
  match self.database {
    Some(database) =>
      match database.close_checked() {
        Ok(_) => self.database = None
        Err(issue) => return Err(Physical(issue))
      }
    None => ()
  }
  Ok(())
}

///|
/// Cleanup-only snapshot phase. It cannot delete the copy before the actual
/// DB close acknowledges. Only the original snapshot deletion ACK clears the
/// remaining duty. A failed deletion retries this same snapshot, never capture.
pub fn CoordinatorInitializationCleanup::close_snapshot(
  self : CoordinatorInitializationCleanup,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if !self.pending {
    return Ok(())
  }
  if !self.closing || self.database is Some(_) {
    return Err(CleanupPending)
  }
  if !inspection_close(self.inspection) {
    return Err(inspection_issue(self.inspection))
  }
  self.pending = false
  Ok(())
}

///|
/// Retries only physical DB close and deletion of this private inspection copy.
/// A phased caller can consume their separate ACKs with `close_database` then
/// `close_snapshot`. Neither route retries admission or opens the source.
pub fn CoordinatorInitializationCleanup::retry(
  self : CoordinatorInitializationCleanup,
) -> Result[Unit, NativeRemoteJournalIssue] {
  match self.close_database() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.close_snapshot()
}

///|
fn inspect_coordinator_copy(
  library : @sqlite.Library,
  cleanup : CoordinatorInitializationCleanup,
  control : @remote.CoordinatorDispatchJournal,
) -> Result[Unit, NativeRemoteJournalIssue] {
  inspect_sqlite_copy(library, cleanup, database => {
    guard database is Some(database) else { return Ok(()) }
    inspect_coordinator_rows(database, control)
  })
}

///|
fn inspect_coordinator_rows(
  database : @sqlite.Database,
  control : @remote.CoordinatorDispatchJournal,
) -> Result[Unit, NativeRemoteJournalIssue] {
  let mut cursor = ""
  while true {
    let entry = match database.scan_after("coordinator_dispatch", cursor) {
      Ok(value) => value
      Err(@sqlite.NotFound) => break
      Err(issue) => return Err(Physical(issue))
    }
    let durable = match
      @remote.admit_durable_coordinator_dispatch_record(entry.body) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    let key = match
      @remote.durable_coordinator_dispatch_record_attempt_identity(durable) {
      Ok(value) => value
      Err(issue) => return Err(Protocol(issue))
    }
    if key != entry.key ||
      entry.revision !=
      @remote.durable_coordinator_dispatch_record_revision(durable).to_int64() {
      return Err(StateCollision)
    }
    // Reuse the expected authority of the caller-owned journal, never the
    // authority asserted by the stored record, without committing an intent.
    match
      @remote.prepare_coordinator_dispatch_intent(
        control,
        @remote.durable_coordinator_dispatch_record_request(durable),
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Protocol(issue))
    }
    cursor = entry.key
  }
  Ok(())
}

///|
fn[T] inspect_sqlite_copy(
  library : @sqlite.Library,
  cleanup : CoordinatorInitializationCleanup,
  inspect : (@sqlite.Database?) -> Result[T, NativeRemoteJournalIssue],
) -> Result[T, NativeRemoteJournalIssue] {
  let database = match cleanup.open_database(library) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let admission = inspect(database)
  match cleanup.validate_source() {
    Err(issue) => Err(issue)
    Ok(_) => admission
  }
}

///|
/// Inspect an isolated read-only copy using the existing snapshot and cleanup
/// owner. `None` means physical absence, not a fresh Host or resend permission.
/// The callback must not retain the copied database: it is closed before this
/// function succeeds. Source identity is checked again after the callback.
/// The combined DB/WAL copy is bounded before creating scratch files;
/// `max_record_bytes` separately bounds each SQLite row read.
/// Inspection does not authorize a later writer; it must recheck its own
/// custody and initialization intent within its transaction.
pub fn[T] inspect_sqlite_source(
  library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  max_snapshot_bytes : Int64,
  inspect : (@sqlite.Database?) -> Result[T, NativeRemoteJournalIssue],
) -> Result[T, NativeRemoteJournalIssue] {
  let cleanup = match
    prepare_sqlite_source_inspection(path, max_record_bytes, max_snapshot_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let admission = inspect_sqlite_copy(library, cleanup, inspect)
  finish_coordinator_inspection(cleanup, admission)
}

///|
fn inspect_coordinator_source(
  library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  control : @remote.CoordinatorDispatchJournal,
) -> Result[Unit, NativeRemoteJournalIssue] {
  let bytes = @utf8.encode(path)
  let cleanup = capture_sqlite_inspection(
    inspection_open(bytes, bytes.length()),
    max_record_bytes,
  )
  let admission = inspect_coordinator_copy(library, cleanup, control)
  finish_coordinator_inspection(cleanup, admission)
}

///|
fn[T] finish_coordinator_inspection(
  cleanup : CoordinatorInitializationCleanup,
  admission : Result[T, NativeRemoteJournalIssue],
) -> Result[T, NativeRemoteJournalIssue] {
  match cleanup.retry() {
    Ok(_) => admission
    Err(issue) =>
      Err(
        InitializationCleanupPending(
          match admission {
            Ok(_) => None
            Err(primary) => Some(primary)
          },
          issue,
          cleanup,
        ),
      )
  }
}
