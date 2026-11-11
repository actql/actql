///|
/// A read-only observation of retained Client custody. Physical absence does
/// not prove a fresh environment, non-execution, or permission to initialize.
pub enum NativeClientStateInspection {
  PhysicallyAbsent
  Retained
}

///|
pub(all) enum NativeClientCustodyIssue {
  Epoch(NativeClientEpochIssue)
  Run(NativeClientRunJournalIssue)
  Submission(NativeClientRunJournalIssue)
}

///|
pub(all) enum NativeClientStateInspectionIssue {
  InvalidLimit
  Custody(NativeClientCustodyIssue)
  // Preserve semantic refusal alongside any retryable physical cleanup owner.
  Inspection(@journal.NativeRemoteJournalIssue, NativeClientCustodyIssue?)
}

///|
/// Reuse the existing pinned SQLite/WAL copy and retryable cleanup owner before
/// any normal writer opens an unclassified Local journal. Every retained row
/// is checked by the existing epoch, Run and original-intent custody decoders.
/// This observation confers no authority and is not a durable initialization
/// decision. A later
/// writer must recheck custody and the trusted Host's initialization intent in
/// its own transaction; missing or changed custody is never repaired here.
pub fn inspect_native_client_state(
  library : @sqlite.Library,
  path : String,
  max_record_bytes : Int64,
  max_snapshot_bytes : Int64,
  max_records : Int,
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> Result[NativeClientStateInspection, NativeClientStateInspectionIssue] {
  if max_record_bytes < 1L ||
    max_record_bytes > 1048576L ||
    max_snapshot_bytes < 0L ||
    max_records < 1 ||
    max_retained_intent_bytes < 0L {
    return Err(InvalidLimit)
  }
  let mut refusal : NativeClientCustodyIssue? = None
  let inspected = @journal.inspect_sqlite_source(
    library,
    path,
    max_record_bytes,
    max_snapshot_bytes,
    database => {
      guard database is Some(database) else { return Ok(PhysicallyAbsent) }
      match
        inspect_native_client_custody_rows(
          database,
          max_records,
          max_retained_intent_bytes~,
        ) {
        Ok(value) => Ok(value)
        Err(issue) => {
          refusal = Some(issue)
          Err(@journal.StateCollision)
        }
      }
    },
  )
  match inspected {
    Ok(value) => Ok(value)
    Err(@journal.StateCollision) =>
      match refusal {
        Some(issue) => Err(Custody(issue))
        None => Err(Inspection(@journal.StateCollision, None))
      }
    Err(issue) => Err(Inspection(issue, refusal))
  }
}

///|
// The same retained-row audit is shared by ordinary and phased inspection.
// Routing SQL queries does not weaken any original Run, Policy or intent check.
fn inspect_native_client_custody_rows(
  database : @sqlite.Database,
  max_records : Int,
  reads? : NativeClientJournalReadAccess? = None,
  max_retained_intent_bytes? : Int64 = 67108864L,
) -> Result[NativeClientStateInspection, NativeClientCustodyIssue] {
  match read_epoch_custody(database, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(Epoch(issue))
  }
  match run_journal_custody(database, max_records, reads~) {
    Ok(_) => ()
    Err(issue) => return Err(Run(issue))
  }
  let journal : NativeClientRunJournal = {
    database,
    max_records,
    max_retained_intent_bytes,
    append_schema: 0,
    observed_evidence_schema: None,
    fenced: false,
    publication_read_locked: false,
    transaction_active: false,
    admitted_record: None,
    operation_run_identity: None,
    operation_prepared_binding: None,
    operation_record: None,
    operation_submission: None,
    admitted_adoption: None,
    operation_active: false,
    admitted_publications: [],
  }
  match journal.submitted_intent_custody(reads~) {
    Ok(_) => Ok(Retained)
    Err(issue) => Err(Submission(issue))
  }
}
