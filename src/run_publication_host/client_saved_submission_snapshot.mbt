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
  state_original : ClientRetainedRunStateOriginal?
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
/// The authenticated metadata from this snapshot, with its Model failure
/// locator still opaque. Only the current Read can resolve an exact proof.
pub fn client_saved_submission_retained_state_original(
  value : ClientSavedSubmissionSnapshot,
) -> ClientRetainedRunStateOriginal? {
  value.state_original
}

///|
/// Confirm the cancellation head attached to the Run validated in this
/// snapshot. Callers retaining an earlier snapshot first reobserve the exact
/// current Run bytes and generation in the same reader. False means this
/// snapshot contains no inspected Run, so a caller requiring the complete
/// custody audit still has to perform it.
pub fn[E] confirm_client_saved_submission_cancellation(
  value : ClientSavedSubmissionSnapshot,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[Bool, E] {
  guard value.run is Some(row) &&
    value.inspection is Some(original) else { return Ok(false) }
  guard original.cancellation_head is Some(head) else { return Ok(true) }
  guard @publication.run_definition_namespace(original.definition)
    is Some(namespace_id) else { return Err(custody_lost) }
  observe_client_accepted_cancellation_original(
    head, namespace_id, original.request, original.definition, row.revision,
    read, custody_lost,
  ).map(_ => true)
}

///|
/// Confirm the immutable reference locator for the Run that was admitted in
/// this same snapshot. The locator is subordinate to the checked Run.
pub fn[E] confirm_client_saved_submission_locator(
  value : ClientSavedSubmissionSnapshot,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  custody_lost : E,
) -> Result[Unit, E] {
  guard value.inspection is Some(original) &&
    client_saved_run_reference_locator(
      value.record.reference, original.request, original.definition,
    ) is Ok((key, body)) else { return Err(custody_lost) }
  match read("client_run_reference_index", key) {
    Ok(Some(row)) if row.key == key && row.revision == 0L && row.body == body =>
      Ok(())
    Err(issue) => Err(issue)
    _ => Err(custody_lost)
  }
}

///|
/// Reobserve only this original snapshot's immutable admitted DATA. This does
/// not run a different validator or claim its success. The caller must retain
/// the same completed issuer/purpose and independently check current scope,
/// cancellation and all publication/File fences. The selected slot reader
/// supplies the caller's custody refusal and uses the same physical snapshot.
/// Only the general point reader can return None for an unmatched original.
/// An optional material proof belongs to the caller's same physical reader
/// after it has already checked this exact snapshot's full material inventory.
pub fn[E] reobserve_client_saved_submission_original(
  original : ClientSavedSubmissionSnapshot,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  read_task_slots? : ((String, Int) -> Result[ClientJournalPhysicalRow?, E], E)? = None,
  prove_task_material? : (() -> Result[Bool, E])? = None,
) -> Result[ClientSavedSubmissionSnapshot?, E] {
  let no_exact_original = () => {
    match read_task_slots {
      Some((_, custody_lost)) => Err(custody_lost)
      None => Ok(None)
    }
  }
  guard original.record.run_admission is Some(_) &&
    original.run is Some(run) &&
    original.inspection is Some(inspection) else {
    return no_exact_original()
  }
  let submission = match
    read("client_submitted_intents", original.submission.key) {
    Err(issue) => return Err(issue)
    Ok(Some(row)) => row
    Ok(None) => return no_exact_original()
  }
  if submission.key != original.submission.key ||
    submission.revision != original.submission.revision ||
    submission.body != original.submission.body {
    return no_exact_original()
  }
  match read("client_runs", run.key) {
    Err(issue) => Err(issue)
    Ok(Some(row)) if row.key == run.key &&
      row.revision == run.revision &&
      row.body == run.body =>
      match original.task_materials {
        None => Ok(Some(original))
        Some(wire) => {
          // Snapshot construction checked this wire under this inspection CID.
          // Reuse it only after the complete fresh exact material observation.
          guard inspection.task_materials_cid is Some(cid) else {
            return no_exact_original()
          }
          if prove_task_material is Some(prove) {
            match prove() {
              Ok(true) => return Ok(Some(original))
              Ok(false) => ()
              Err(issue) => return Err(issue)
            }
          }
          // A selected physical reader receives only the already matched Run
          // key and the next ordinal. A physical refusal never selects a point
          // read. The physical reader and its close stay with the caller.
          let read_slot = match read_task_slots {
            Some((take, _)) => (index, _) => take(run.key, index)
            None => (_, key) => read("client_task_run_materials", key)
          }
          match
            read_saved_task_material_original(
              run.key,
              cid,
              original.task_materials,
              (index, key) => {
                read_slot(index, key).map_err(issue => Some(issue))
              },
              None,
            ) {
            Ok(actual) if actual == wire => Ok(Some(original))
            Ok(_) | Err(None) => no_exact_original()
            Err(Some(issue)) => Err(issue)
          }
        }
      }
    _ => no_exact_original()
  }
}

///|
fn[Plan, E] read_client_saved_submission_row_with_task_original(
  row : ClientJournalPhysicalRow,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
  task_original : ClientTaskMaterialsOriginal[Plan]?,
  before_construction? : ((ClientSubmittedJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
  expected_reference? : ClientSubmissionReferenceRecord? = None,
  fund_task_read? : ((Int64) -> Result[Unit, E])? = None,
  read_task_slots? : ((String, Int) -> Result[ClientJournalPhysicalRow?, E])? = None,
) -> Result[ClientSavedSubmissionSnapshot, E] {
  let record = match
    decode_client_submitted_journal_row(row.body, before_construction~) {
    Ok(value) => value
    Err(_) => return Err(custody_lost)
  }
  read_decoded_client_saved_submission_row(
    row,
    record,
    read,
    validate_run,
    custody_lost,
    task_original,
    expected_reference~,
    read_task_slots~,
    fund_task_read~,
  )
}

///|
// Only the canonical constructors in this module supply this local value.
// No decoded record is accepted from a physical or public caller.
fn[Plan, E] read_decoded_client_saved_submission_row(
  row : ClientJournalPhysicalRow,
  record : ClientSubmittedJournalEncoding,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
  task_original : ClientTaskMaterialsOriginal[Plan]?,
  expected_reference? : ClientSubmissionReferenceRecord? = None,
  fund_task_read? : ((Int64) -> Result[Unit, E])? = None,
  read_task_slots? : ((String, Int) -> Result[ClientJournalPhysicalRow?, E])? = None,
) -> Result[ClientSavedSubmissionSnapshot, E] {
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
        Some((revision, Some(key))) =>
          match
            admit_client_retained_run_state_original(
              original.definition,
              wire,
              revision,
              key,
            ) {
            Ok(state) => Some(state)
            Err(_) => return Err(custody_lost)
          }
        Some((_, None)) => return Err(custody_lost)
      }
    }
  }
  let task_materials = match (run, inspection) {
    (Some(row), Some(original)) =>
      match original.task_materials_cid {
        None => None
        Some(cid) => {
          let read_slot = match read_task_slots {
            Some(take) => (ordinal, _) => take(row.key, ordinal)
            None => (_, key) => read("client_task_run_materials", key)
          }
          match
            read_task_material_original_slots(
              row.key,
              cid,
              read_slot,
              custody_lost,
              task_original,
              fund_workspace=fund_task_read,
            ) {
            Ok((wire, _)) => Some(wire)
            Err(issue) => return Err(issue)
          }
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
/// Validate one scanned row within its SAME original read call. Its canonical
/// decode remains local across the fresh point read; exact key/revision/whole
/// bytes permit reuse, never a normalized replacement or earlier transaction.
/// All Run/task/snapshot validation remains in the original reader below.
/// Complete inventories, current and transaction fences stay with the caller.
/// The caller retains original construction backing through this same call
/// and its existing snapshot consumption; this creates no new retained owner.
pub fn[Plan, E] read_client_scanned_submission_with_task_original(
  scanned : ClientJournalPhysicalRow,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
  task_original : ClientTaskMaterialsOriginal[Plan]?,
  before_construction? : ((ClientSubmittedJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
) -> Result[ClientSavedSubmissionSnapshot, E] {
  // Keep malformed canonical input before physical IO, as in the original
  // scan/decode/reference-reader composition. Carry only this canonical local
  // result; do not infer backing or object liveness from compiler optimizations.
  let record = match
    decode_client_submitted_journal_row(scanned.body, before_construction~) {
    Ok(value) => value
    Err(_) => return Err(custody_lost)
  }
  let reference = record.reference
  let key = client_submission_reference_record_request_id(reference)
  let actual = match read("client_submitted_intents", key) {
    Ok(Some(row)) if row.key == key => row
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let same = actual.key == scanned.key &&
    actual.revision == scanned.revision &&
    actual.body == scanned.body
  let observed = if same {
    read_decoded_client_saved_submission_row(
      actual,
      record,
      read,
      validate_run,
      custody_lost,
      task_original,
      expected_reference=Some(reference),
    )
  } else {
    // A miss retains the original validator and its failure/callback order.
    // No changed body or revision borrows the earlier pure result.
    read_client_saved_submission_row_with_task_original(
      actual,
      read,
      validate_run,
      custody_lost,
      task_original,
      expected_reference=Some(reference),
      before_construction~,
    )
  }
  let snapshot = match observed {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !same {
    return Err(custody_lost)
  }
  Ok(snapshot)
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
  read_task_slots? : ((String, Int) -> Result[ClientJournalPhysicalRow?, E])? = None,
) -> Result[ClientSavedSubmissionSnapshot?, E] {
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  read_client_saved_submission_with_task_original(
    reference,
    read,
    validate_run,
    custody_lost,
    original,
    before_construction~,
    read_task_slots~,
  )
}

///|
/// Same saved-row read with an already retained pure material original. All
/// nested Run/binding/construction callbacks and physical reads still execute.
pub fn[Plan, E] read_client_saved_submission_with_task_original(
  reference : ClientSubmissionReferenceRecord,
  read : (String, String) -> Result[ClientJournalPhysicalRow?, E],
  validate_run : (ClientJournalPhysicalRow) -> Result[
    ClientRunJournalInspection,
    E,
  ],
  custody_lost : E,
  task_original : ClientTaskMaterialsOriginal[Plan]?,
  before_construction? : ((ClientSubmittedJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
  fund_task_read? : ((Int64) -> Result[Unit, E])? = None,
  read_task_slots? : ((String, Int) -> Result[ClientJournalPhysicalRow?, E])? = None,
) -> Result[ClientSavedSubmissionSnapshot?, E] {
  let key = client_submission_reference_record_request_id(reference)
  let row = match read("client_submitted_intents", key) {
    Ok(Some(value)) if value.key == key => value
    Ok(None) => return Ok(None)
    Err(issue) => return Err(issue)
    _ => return Err(custody_lost)
  }
  let snapshot = match
    read_client_saved_submission_row_with_task_original(
      row,
      read,
      validate_run,
      custody_lost,
      task_original,
      expected_reference=Some(reference),
      before_construction~,
      read_task_slots~,
      fund_task_read~,
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
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
) -> Result[ClientSavedSubmissionSnapshot?, E] {
  let original : ClientTaskMaterialsOriginal[Unit]? = None
  inspect_client_saved_submission_with_task_original(
    reference, max_records, scan, read, validate_run, confirm_cancellation, custody_lost,
    original,
    task_material_count~,
  )
}

///|
/// The same complete read with a nominal Task material original already held
/// by the caller. Every physical row, chunk and cancellation check still runs.
/// The Task-only caller funds both the full index and each chunk restore.
pub fn[Plan, E] inspect_client_saved_submission_with_task_original(
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
  task_original : ClientTaskMaterialsOriginal[Plan]?,
  task_funding? : ((Int64) -> Result[Unit, E], (Int64) -> Result[Unit, E])? = None,
  task_material_count? : ((Int) -> Result[Bool?, E])? = None,
) -> Result[ClientSavedSubmissionSnapshot?, E] {
  let (fund_indexes, fund_task_read) = match task_funding {
    Some((indexes, task)) => (Some(indexes), Some(task))
    None => (None, None)
  }
  match
    inspect_client_run_journal_inventory_with_index_funding(
      max_records,
      scan,
      read,
      validate_run,
      confirm_cancellation,
      custody_lost,
      task_original,
      fund_indexes,
      fund_task_read,
      task_material_count~,
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
        read_client_saved_submission_row_with_task_original(
          row,
          read,
          validate_run,
          custody_lost,
          task_original,
          fund_task_read~,
        ).map(snapshot => snapshot.record)
      },
      custody_lost,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  read_client_saved_submission_with_task_original(
    reference,
    read,
    validate_run,
    custody_lost,
    task_original,
    fund_task_read~,
  )
}
