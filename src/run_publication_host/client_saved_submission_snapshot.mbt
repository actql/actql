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
  state_original : ClientRunStateOriginal?
  task_materials : String?
}

///|
/// Exact logical codec wire selected from immutable bounded chunk rows in
/// this same original read. Historical absence never synthesizes material.
pub fn client_saved_submission_task_materials_original(
  value : ClientSavedSubmissionSnapshot,
) -> String? {
  value.task_materials
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
/// The original observed metadata already restored by this same snapshot.
/// Historical absence stays absent. This supplies no current availability,
/// authority, physical acknowledgement or permission to dispatch again.
pub fn client_saved_submission_state_original(
  value : ClientSavedSubmissionSnapshot,
) -> ClientRunStateOriginal? {
  value.state_original
}

///|
/// Reobserve only this original snapshot's immutable admitted DATA. This does
/// not run a different validator or claim its success. The caller must retain
/// the same completed issuer/purpose and independently check current scope,
/// cancellation and all publication/File fences. None means no exact original
/// correspondence, not confirmed missing history: use the full existing reader.
pub fn[E] reobserve_client_saved_submission_original(
  original : ClientSavedSubmissionSnapshot,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
) -> Result[ClientSavedSubmissionSnapshot?, E] {
  guard original.record.run_admission is Some(_) &&
    original.run is Some(run) &&
    original.inspection is Some(_) else {
    return Ok(None)
  }
  let submission = match
    read("client_submitted_intents", original.submission.key) {
    Err(issue) => return Err(issue)
    Ok(Some(row)) => row
    Ok(None) => return Ok(None)
  }
  if submission.key != original.submission.key ||
    submission.revision != original.submission.revision ||
    submission.body != original.submission.body {
    return Ok(None)
  }
  match read("client_runs", run.key) {
    Err(issue) => Err(issue)
    Ok(Some(row)) if row.key == run.key &&
      row.revision == run.revision &&
      row.body == run.body =>
      match original.task_materials {
        None => Ok(Some(original))
        Some(wire) => {
          let cid = match client_task_material_original_cid(wire) {
            Ok(cid) => cid
            Err(_) => return Ok(None)
          }
          match
            read_client_task_material_original(
              run.key,
              cid,
              (table, key) => read(table, key).map_err(issue => Some(issue)),
              None,
            ) {
            Ok(actual) if actual == wire => Ok(Some(original))
            Ok(_) => Ok(None)
            Err(None) => Ok(None)
            Err(Some(issue)) => Err(issue)
          }
        }
      }
    _ => Ok(None)
  }
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
  before_construction? : ((ClientSubmittedJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
  expected_reference? : ClientSubmissionReferenceRecord? = None,
) -> Result[ClientSavedSubmissionSnapshot, E] {
  let record = match
    decode_client_submitted_journal_row(row.body, before_construction~) {
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
  let state_original = match record.run_state_original {
    None => None
    Some(wire) => {
      guard inspection is Some(original) else { return Err(custody_lost) }
      match record.run_state_observation {
        None => {
          if validate_client_historical_run_state_original(
              original.definition,
              wire,
            )
            is Err(_) {
            return Err(custody_lost)
          }
          None
        }
        Some(_) =>
          match restore_client_run_state_original(original.definition, wire) {
            Ok(state) => Some(state)
            Err(_) => return Err(custody_lost)
          }
      }
    }
  }
  let task_materials = match (run, inspection) {
    (Some(row), Some(original)) =>
      match original.task_materials_cid {
        None => None
        Some(cid) =>
          match
            read_client_task_material_original(row.key, cid, read, custody_lost) {
            Ok(wire) => Some(wire)
            Err(issue) => return Err(issue)
          }
      }
    _ => None
  }
  Ok({
    record,
    submission: row,
    run,
    inspection,
    state_original,
    task_materials,
  })
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
  before_construction? : ((ClientSubmittedJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
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
      before_construction~,
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

///|
/// Select an existing public Run reference only through complete original
/// Run/Submission inventories. Equality locates retained metadata, never
/// authorizes it. The physical Host must authenticate its current scope and
/// retain the same Store snapshot around the whole call and response transfer.
/// Missing and ambiguous histories cannot issue a Run, grant or resend.
pub fn[E] inspect_client_saved_run_reference(
  namespace_id : String,
  authority_scope_cid : String,
  definition_cid : String,
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
  let mut selected : ClientSavedSubmissionSnapshot? = None
  let inspected = inspect_client_submitted_journal_inventory(
    max_records,
    scan,
    read,
    row => {
      let snapshot = match
        read_client_saved_submission_row(row, read, validate_run, custody_lost) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      if snapshot.inspection is Some(run) &&
        client_request_authority_scope_cid(run.request) == authority_scope_cid &&
        @publication.publication_contract_identity(run.definition) ==
        definition_cid &&
        @publication.run_definition_namespace(run.definition) ==
        Some(namespace_id) {
        if selected is Some(_) {
          return Err(custody_lost)
        }
        selected = Some(snapshot)
      }
      Ok(snapshot.record)
    },
    custody_lost,
  )
  match inspected {
    Ok(_) => Ok(selected)
    Err(issue) => Err(issue)
  }
}
