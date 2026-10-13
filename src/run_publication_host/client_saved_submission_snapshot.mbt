///|
/// Read-only original journal observation. Issuance is not a COMMIT ACK,
/// current authority, a new acceptance, dispatch or permission to resend.
/// Its caller retains the original same-Store snapshot and input/workspace
/// loans until observation transfer and cleanup finish.
pub struct ClientSavedSubmissionSnapshot {
  record : ClientSubmittedJournalEncoding
  submission : ClientJournalPhysicalRow
  run : ClientJournalPhysicalRow?
  inspection : ClientRunJournalInspection?
}

///|
pub fn client_saved_submission_record(
  value : ClientSavedSubmissionSnapshot,
) -> ClientSubmittedJournalEncoding {
  value.record
}

///|
pub fn client_saved_submission_revision(
  value : ClientSavedSubmissionSnapshot,
) -> Int64 {
  value.submission.revision
}

///|
/// Original physical row, not a re-encoding of decoded or candidate fields.
pub fn client_saved_submission_row(
  value : ClientSavedSubmissionSnapshot,
) -> ClientJournalPhysicalRow {
  value.submission
}

///|
/// Actual retained Run bytes, never the earlier candidate-byte projection.
pub fn client_saved_submission_run_row(
  value : ClientSavedSubmissionSnapshot,
) -> ClientJournalPhysicalRow? {
  value.run
}

///|
fn[E] read_client_saved_submission_row(
  row : ClientJournalPhysicalRow,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
  expected_reference? : ClientSubmissionReferenceRecord? = None,
) -> Result[ClientSavedSubmissionSnapshot, E] {
  let record = match decode_client_submitted_journal_row(row.body) {
    Ok(value) => value
    Err(_) => return Err(custody_lost)
  }
  if row.revision < 0L ||
    row.key != client_submission_reference_record_request_id(record.reference) {
    return Err(custody_lost)
  }
  if expected_reference is Some(reference) &&
    client_submission_reference_record_wire(record.reference) !=
    client_submission_reference_record_wire(reference) {
    return Err(custody_lost)
  }
  let (run, inspection) = match record.run_admission {
    None => (None, None)
    Some(admission) => {
      let key = client_request_scope_cid(admission.0)
      let retained = match read("client_runs", key) {
        Ok(Some(value)) if value.key == key && value.revision >= 0L => value
        Err(issue) => return Err(issue)
        _ => return Err(custody_lost)
      }
      // The same original nested Run/Policy/Checkpoint/Effect validator is
      // mandatory. Outer JSON fields alone cannot validate retained custody.
      let run = match validate_run(retained) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      match
        validate_client_submitted_retained_run(
          record.reference,
          admission,
          run.request,
          run.definition,
          retained.revision,
        ) {
        Ok(_) => (Some(retained), Some(run))
        Err(_) => return Err(custody_lost)
      }
    }
  }
  Ok({ record, submission: row, run, inspection, })
}

///|
/// The original retained-submission reader. The physical Host authenticates
/// the exact epoch and current scope before and inside its original transaction.
/// Confirmed missing history remains None; it cannot authorize a new operation.
/// Complete inventory checks remain a separate, explicit caller obligation.
pub fn[E] read_client_saved_submission(
  reference : ClientSubmissionReferenceRecord,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
) -> Result[ClientSavedSubmissionSnapshot?, E] {
  let key = client_submission_reference_record_request_id(reference)
  let row = match read("client_submitted_intents", key) {
    Ok(Some(value)) if value.key == key => value
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let snapshot = match
    read_client_saved_submission_row(
      row,
      read,
      validate_run,
      custody_lost,
      expected_reference=Some(reference),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(Some(snapshot))
}

///|
/// Join full original Run/Submission inventories and the exact saved row using
/// one trusted same-transaction physical port. All required namespaces remain
/// selected; a partial scan, count, validator Unit or candidate cannot replace
/// these observations. No write, preparation, dispatch or automatic retry runs.
pub fn[E] inspect_client_saved_submission(
  reference : ClientSubmissionReferenceRecord,
  max_records : Int,
  scan : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  confirm_cancellation : () -> Result[Unit, E],
  custody_lost : E,
) -> Result[ClientSavedSubmissionSnapshot?, E] {
  match
    inspect_client_run_journal_inventory(
      max_records, scan, read, validate_run, confirm_cancellation, custody_lost,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match
    inspect_client_submitted_journal_inventory(
      max_records,
      scan,
      read,
      row => {
        read_client_saved_submission_row(row, read, validate_run, custody_lost).map(snapshot => {
            snapshot.record
          },
        )
      },
      custody_lost,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  read_client_saved_submission(reference, read, validate_run, custody_lost)
}
