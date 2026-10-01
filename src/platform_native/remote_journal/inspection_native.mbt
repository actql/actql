///|
priv type JournalInspection

///|
/// Cleanup-only owner for a failed Coordinator format inspection. The source
/// journal is never opened normally while this responsibility is pending.
struct CoordinatorInitializationCleanup {
  inspection : JournalInspection
  mut database : @sqlite.Database?
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
fn inspection_issue(owner : JournalInspection) -> NativeRemoteJournalIssue {
  let message = @utf8.decode(inspection_error(owner)) catch {
    _ => "invalid inspection diagnostic"
  }
  Physical(@sqlite.Physical(message))
}

///|
/// Retries only physical close and deletion of the private inspection copy.
/// It never retries format admission, opens the source, or executes a Run.
pub fn CoordinatorInitializationCleanup::retry(
  self : CoordinatorInitializationCleanup,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if !self.pending {
    return Ok(())
  }
  match self.database {
    Some(database) =>
      match database.close_checked() {
        Ok(_) => self.database = None
        Err(issue) => return Err(Physical(issue))
      }
    None => ()
  }
  if !inspection_close(self.inspection) {
    return Err(inspection_issue(self.inspection))
  }
  self.pending = false
  Ok(())
}

///|
fn inspect_coordinator_copy(
  library : @sqlite.Library,
  max_record_bytes : Int64,
  cleanup : CoordinatorInitializationCleanup,
  control : @remote.CoordinatorDispatchJournal,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if max_record_bytes < 0L {
    return Err(Physical(@sqlite.InvalidLimit))
  }
  if !inspection_ready(cleanup.inspection) {
    return Err(inspection_issue(cleanup.inspection))
  }
  let path = @utf8.decode(inspection_path(cleanup.inspection)) catch {
    _ => return Err(Physical(@sqlite.Physical("invalid inspection path")))
  }
  if !path.is_empty() {
    let database = library.open_inspection_database(path, max_record_bytes)
    cleanup.database = Some(database)
    match database.inspection_status() {
      Ok(_) => ()
      Err(issue) => return Err(Physical(issue))
    }
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
  }
  if !inspection_validate(cleanup.inspection) {
    return Err(inspection_issue(cleanup.inspection))
  }
  Ok(())
}

///|
fn inspect_coordinator_source(
  library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  control : @remote.CoordinatorDispatchJournal,
) -> Result[Unit, NativeRemoteJournalIssue] {
  let bytes = @utf8.encode(path)
  let cleanup : CoordinatorInitializationCleanup = {
    inspection: inspection_open(bytes, bytes.length()),
    database: None,
    pending: true,
  }
  let admission = inspect_coordinator_copy(
    library, max_record_bytes, cleanup, control,
  )
  finish_coordinator_inspection(cleanup, admission)
}

///|
fn finish_coordinator_inspection(
  cleanup : CoordinatorInitializationCleanup,
  admission : Result[Unit, NativeRemoteJournalIssue],
) -> Result[Unit, NativeRemoteJournalIssue] {
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
