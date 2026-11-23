///|
// Construction state on the existing Model Task, not another owner, Ledger,
// send authority or publication purpose. Its one token precedes physical send.
priv struct ModelAttemptProofCapacity {
  capacity : @resources.CapacityReservation
  mut retained : Int64
  mut execution : Int64
}

///|
// The three existing flat codecs are attempt/accounting/outcome. They own
// fixed keys, SHA256 IDs, scalar quantities and a closed failure vocabulary;
// no response/input tree or maximum permitted call inventory is copied here.
fn model_attempt_proof_construction(
  state : ModelState,
  slot_cid : String,
  reported_response? : Bool = false,
) -> (Int64, Int64)? {
  let names = "actql-model-call-attempt/0.1actql-model-attempt-accounting/0.1actql-model-attempt-outcome/0.1versionattempt_cidslot_cidrun_definition_cidmodel_task_cidfixed_request_cidauthority_evidence_cidprovider_idattemptcumulative_workuncertain_wire_bytesinput_tokensoutput_tokenscost_unitsduration_msreservationtokenscategoryfailure"
  let report_keys = "reported_responseraw_response_artifact_cidresponse_profile_cidobserved_atprovider_reported_model_idprovider_request_idfinish_reasonresponse_completeprovider_metadata"
  let report_text = if reported_response {
    report_keys.length().to_int64() + 2L * 71L + 64L + 3L * 256L + 5L + 64L + 256L
  } else {
    0L
  }
  let text = names.length().to_int64() + report_text +
    @environment.model_task_connector(state.task).length().to_int64() +
    slot_cid.length().to_int64() +
    state.fixed_request_cid.length().to_int64() +
    // Four protocol-sized CID fields and closed outcome/failure tags. The
    // quantities use at most20 decimal units in these SAME fixed codecs.
    4L * 71L +
    "result_unknownokprovider_failurecontract_violationcancelleddeadlineoutput_identityoutput_valuebudget_exceeded"
    .length()
    .to_int64() +
    12L * 20L
  let wire = Int64::min(16384L, 6L * text)
  // Count the closed report fields plus its optional one-pair metadata.
  // Include their parser/converter records and writer key/value tuples.
  let report_fields = if reported_response { 9L } else { 0L }
  guard @shape.collection_construction_extent({
      records: 96L + 8L * report_fields,
      record_references: 256L + 16L * report_fields,
      record_words: 96L + 8L * report_fields,
      reference_arrays: 16L + report_fields,
      reference_items: 192L + 8L * report_fields,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps: if reported_response { 5L } else { 3L },
      map_entries: 48L + report_fields + (if reported_response { 1L } else { 0L }),
    })
    is Some(tree) &&
    @encode.text_writer_construction_inventory(wire.to_int(), 256, 8)
    is Some(writer) &&
    @relation.preparation_representation_cost({
      record_headers: tree.record_headers + 12L,
      reference_slots: tree.reference_slots + 24L,
      scalar_words: tree.scalar_words + 16L,
      owned_utf16_units: 8L * wire,
      owned_wire_bytes: 3L * wire,
    })
    is Some(retained) &&
    @relation.preparation_representation_cost({
      record_headers: writer.record_headers + tree.record_headers + 16L,
      reference_slots: writer.reference_slots + tree.reference_slots + 32L,
      scalar_words: writer.scalar_words + tree.scalar_words + 16L,
      owned_utf16_units: writer.owned_utf16_units + 8L * wire,
      owned_wire_bytes: 4L * wire,
    })
    is Some(workspace) else {
    return None
  }
  Some((retained, workspace))
}

///|
fn original_model_attempt_proof_capacity_current(state : ModelState) -> Bool {
  guard state.original_startup is Some(startup) &&
    startup.used &&
    physical_equal(startup.ledger, state.ledger) &&
    physical_equal(startup.rows, state.rows) &&
    state.prepared_capacity is Some(prepared) &&
    physical_equal(prepared, startup.capacity) &&
    state.call_scope is Some(scope) &&
    startup.scope is Some(original) &&
    physical_equal(scope, original) &&
    state.attempt_proof_capacity is Some(proof) else {
    return false
  }
  @resources.capacity_reservation_covers(
    state.ledger,
    proof.capacity,
    proof.retained,
    proof.execution,
  )
}

///|
fn prepare_original_model_attempt_proof(
  state : ModelState,
  slot : Int,
  slot_cid : String,
) -> Result[Unit, ModelExecutionIssue] {
  if state.original_startup is None ||
    @relation.prepared_infer_rows_count(state.rows) <= 128 ||
    !model_slot_send_eligible(state, slot) ||
    !(state.source is Provider(_)) {
    return Ok(())
  }
  // This one call has actually completed preparation. A Task/item/token
  // maximum is never interpreted as a constructed call or a numeric grant.
  guard slot >= 0 &&
    slot < @relation.prepared_infer_rows_count(state.rows) &&
    slot == state.requests.length() &&
    state.request is Some(request) &&
    request.slot == slot &&
    request.slot_cid is Some(prepared_slot) &&
    prepared_slot == slot_cid &&
    !state.reclaimed &&
    !state.stop_requested &&
    state.original_startup is Some(startup) &&
    startup.used &&
    physical_equal(startup.ledger, state.ledger) &&
    physical_equal(startup.rows, state.rows) &&
    state.prepared_capacity is Some(prepared) &&
    physical_equal(prepared, startup.capacity) &&
    state.call_scope is Some(scope) &&
    startup.scope is Some(original) &&
    physical_equal(scope, original) &&
    model_attempt_proof_construction(state, slot_cid) is Some((r, e)) else {
    return Err(OutputIdentity)
  }
  grow_original_model_attempt_proof(state, r, e)
}

///|
fn prepare_saved_structured_attempt_report(
  state : ModelState,
  request : ModelRequest,
) -> Result[Unit, ModelExecutionIssue] {
  if state.original_startup is None ||
    @relation.prepared_infer_rows_count(state.rows) <= 128 {
    return Ok(())
  }
  // The original flat proof was prepaid during request construction. Only
  // this selected SDK Plan can add a reported failure section to that proof.
  guard request.slot == state.physical_next_slot &&
    model_slot_send_eligible(state, request.slot) &&
    original_model_attempt_proof_capacity_current(state) &&
    model_attempt_proof_construction(state, request.slot_cid) is Some((base, _)) &&
    model_attempt_proof_construction(state, request.slot_cid, reported_response=true)
    is Some((retained, workspace)) && retained >= base else {
    return Err(OutputIdentity)
  }
  grow_original_model_attempt_proof(state, retained - base, workspace, preserve_workspace=true)
}

///|
fn grow_original_model_attempt_proof(
  state : ModelState,
  retained : Int64,
  workspace : Int64,
  preserve_workspace? : Bool = false,
) -> Result[Unit, ModelExecutionIssue] {
  let old_r = state.attempt_proof_capacity
    .map(value => value.retained)
    .unwrap_or(0L)
  let old_e = state.attempt_proof_capacity
    .map(value => value.execution)
    .unwrap_or(0L)
  let workspace = if preserve_workspace {
    Int64::max(old_e - old_r, workspace)
  } else {
    workspace
  }
  guard @relation.checked_preparation_add_product(old_r, retained, 1L) is Some(next_r) &&
    @relation.checked_preparation_add_product(next_r, workspace, 1L) is Some(next_e) else {
    return Err(InvalidLimits)
  }
  let next_e = Int64::max(old_e, next_e)
  match check_original_mock_capacity(state, next_r - old_r, next_e - old_e) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match state.attempt_proof_capacity {
    None => {
      let token = match
        @resources.reserve_capacity(state.ledger, next_r, next_e) {
        Err(issue) => return Err(Ledger(issue))
        Ok(value) => value
      }
      // Keep the exact token before any following constructor/liveness check.
      state.attempt_proof_capacity = Some({
        capacity: token,
        retained: next_r,
        execution: next_e,
      })
    }
    Some(value) =>
      match
        @resources.grow_capacity_reservation(
          state.ledger,
          value.capacity,
          next_r,
          next_e,
        ) {
        Err(issue) => return Err(Ledger(issue))
        Ok(_) => {
          value.retained = next_r
          value.execution = next_e
        }
      }
  }
  if state.stop_requested || state.reclaimed {
    return Err(OutputIdentity)
  }
  Ok(())
}

///|
/// Cleanup walks the actual stopped trace inventory only with its pre-send
/// Task-owned token. This issues no capacity, attempt, publication or current
/// authorization and keeps the legacy/unfunded path separately bounded.
pub fn funded_stopped_model_attempt_count(execution : ModelExecution) -> Int? {
  guard @bounded.session_stopped(execution.session) &&
    !execution.state.reclaimed &&
    original_model_attempt_proof_capacity_current(execution.state) else {
    return None
  }
  Some(execution.state.attempt_slots.length())
}
