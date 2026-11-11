///|
/// The same rejected journal acquisition, never a usable Host. The original
/// issue retains its diagnostic and physical identities even after cleanup.
/// Session aliases retain this exact carrier rather than bypassing its DB/Root
/// obligations through the legacy lock-only close path.
struct NativeLocalJournalOpenFailure {
  original_issue : NativeLocalAdoptionIssue
  mut database : @sqlite.Database?
  physical_open_failure : @sqlite.NativeSqliteOpenFailure?
  initial_signing_failure : NativeLocalInitialSigningFailure?
  mut initial_signing_cleaned : Bool
  retained_read : NativeLocalAdoptionIssue?
  mut retained_read_cleaned : Bool
  acquisition : NativeLocalAdoptionOpenFailure
  original_resources : NativeLocalJournalOriginalResources?
}

///|
pub fn NativeLocalJournalOpenFailure::issue(
  self : NativeLocalJournalOpenFailure,
) -> NativeLocalAdoptionIssue {
  self.original_issue
}

///|
/// Cleanup only. No SQL re-open, initialization, rollback/replay or replacement
/// claim occurs here. Preserve the same DB on a failed close, and retain the
/// original exclusive lock until all acquired Readers and Roots acknowledge.
/// This does not retire escaped aliases, worker/domain loans or a funded read.
pub fn NativeLocalJournalOpenFailure::retry_cleanup(
  self : NativeLocalJournalOpenFailure,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match self.original_resources {
    Some(original) => original.cleanup_journal_failure(self)
    None => {
      match self.cleanup_read_prefix() {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      match self.cleanup_database() {
        Err(issue) => return Err(issue)
        Ok(_) => ()
      }
      self.acquisition.retry_cleanup()
    }
  }
}

///|
/// Installed existing-only caller. Invoke the original journal/adoption body
/// once; failure retains every actual partial acquisition and fences this same
/// Session. A repeated call returns its original refusal, never another open.
/// The caller still owns the successful Host and separate outer cleanup ACKs.
pub fn NativeLocalAdoptionSession::open_existing_journal_with_custody(
  self : NativeLocalAdoptionSession,
  library : @sqlite.Library,
  crypto : @crypto.Library,
  ttl_ms : Double,
  max_records : Int,
  max_snapshot_bytes : Int64,
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> Result[NativeLocalHostConnection, NativeLocalJournalOpenFailure] {
  if self.journal_open_failure is Some(original) {
    return Err(original)
  }
  let opened = if self.existing_only {
    self.open_journal(
      library,
      crypto,
      ttl_ms,
      max_records,
      max_snapshot_bytes,
      max_retained_intent_bytes~,
    )
  } else {
    Err(InvalidInput)
  }
  match opened {
    Ok(host) => Ok(host)
    Err(issue) => Err(self.retain_journal_open_failure(issue))
  }
}

///|
// One original failure carrier is shared by legacy and original-pair callers.
// Retain the actual DB and acquisition before publishing the refusal.
fn NativeLocalAdoptionSession::retain_journal_open_failure_with_resources(
  self : NativeLocalAdoptionSession,
  issue : NativeLocalAdoptionIssue,
  original_resources : NativeLocalJournalOriginalResources?,
  physical_open_failure? : @sqlite.NativeSqliteOpenFailure? = None,
) -> NativeLocalJournalOpenFailure {
  let (database, inner) = match issue {
    DatabasePending(database, original) => (Some(database), original)
    original => (None, original)
  }
  let acquisition : NativeLocalAdoptionOpenFailure = {
    original_issue: inner,
    source_root: Some(self.source_root),
    parent: Some(self.parent),
    root: Some(self.root),
    managed: self.settings.managed.map(original => original.root),
    lock: Some(self.lock),
    root_acquisition: None,
    lock_acquisition: None,
    original_read_cleaned: false,
  }
  let original : NativeLocalJournalOpenFailure = {
    original_issue: issue,
    database,
    physical_open_failure,
    initial_signing_failure: self.initial_signing_failure.val,
    initial_signing_cleaned: false,
    retained_read: self.read_cleanup,
    retained_read_cleaned: false,
    acquisition,
    original_resources,
  }
  self.closed = true
  self.journal_open_failure = Some(original)
  original
}

///|
fn NativeLocalJournalOpenFailure::cleanup_read_prefix(
  self : NativeLocalJournalOpenFailure,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if !self.initial_signing_cleaned {
    if self.initial_signing_failure is Some(original) {
      match original.retry_cleanup() {
        Err(issue) => return Err(Filesystem(issue))
        Ok(_) => ()
      }
    }
    self.initial_signing_cleaned = true
  }
  if !self.retained_read_cleaned {
    let cleaned = match self.retained_read {
      Some(ReadAcquisitionFailure(original)) => original.retry_cleanup()
      Some(ReadPending(reader, _)) => reader.close()
      None => Ok(())
      Some(issue) => return Err(issue)
    }
    match cleaned {
      Err(issue) => return Err(Filesystem(issue))
      Ok(_) => self.retained_read_cleaned = true
    }
  }
  Ok(())
}

///|
fn NativeLocalJournalOpenFailure::cleanup_database(
  self : NativeLocalJournalOpenFailure,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match retry_local_journal_inspection_cleanup(self.original_issue) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.close_original_database()
}

///|
fn NativeLocalJournalOpenFailure::close_original_database(
  self : NativeLocalJournalOpenFailure,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  if self.physical_open_failure is Some(original) {
    match original.retry_cleanup() {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => ()
    }
  }
  if self.database is Some(database) {
    match database.close_checked() {
      Err(issue) => return Err(Physical(issue))
      Ok(_) => self.database = None
    }
  }
  Ok(())
}

///|
// The immutable original issue already owns this exact copied DB/scratch
// cleanup. Consume its ACK before releasing any original Root or lock; do not
// open another inspection or replace the semantic refusal on a cleanup error.
fn retry_local_journal_inspection_cleanup(
  issue : NativeLocalAdoptionIssue,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match original_local_journal_inspection_cleanup(issue) {
    Some(original) =>
      original.retry().map_err(issue => InspectionCleanup(issue))
    None => Ok(())
  }
}

///|
fn original_local_journal_inspection_cleanup(
  issue : NativeLocalAdoptionIssue,
) -> @journal.CoordinatorInitializationCleanup? {
  match issue {
    InspectionPending(_, _, original) => Some(original)
    Inspection(
      Inspection(@journal.InitializationCleanupPending(_, _, original), _)
    ) => Some(original)
    DatabasePending(_, original) =>
      original_local_journal_inspection_cleanup(original)
    OriginalResourceLeave(Some(original), _) =>
      original_local_journal_inspection_cleanup(original)
    _ => None
  }
}

///|
fn NativeLocalJournalOpenFailure::close_inspection_database(
  self : NativeLocalJournalOpenFailure,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match original_local_journal_inspection_cleanup(self.original_issue) {
    Some(original) =>
      original.close_database().map_err(issue => InspectionCleanup(issue))
    None => Ok(())
  }
}

///|
fn NativeLocalJournalOpenFailure::close_inspection_snapshot(
  self : NativeLocalJournalOpenFailure,
) -> Result[Unit, NativeLocalAdoptionIssue] {
  match original_local_journal_inspection_cleanup(self.original_issue) {
    Some(original) =>
      original.close_snapshot().map_err(issue => InspectionCleanup(issue))
    None => Ok(())
  }
}

///|
fn NativeLocalAdoptionSession::retain_journal_open_failure(
  self : NativeLocalAdoptionSession,
  issue : NativeLocalAdoptionIssue,
) -> NativeLocalJournalOpenFailure {
  self.retain_journal_open_failure_with_resources(issue, None)
}
