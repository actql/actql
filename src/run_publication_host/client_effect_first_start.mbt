///|
/// The exact successor of one original Run CAS. It carries no Store
/// acknowledgement or permission to dispatch or retry.
pub struct ClientEffectFirstStartStep {
  original : ClientEffectRunJournalAppend
  dispatch : Bool
  before : ClientJournalPhysicalRow
  body : Bytes
}

///|
/// Project the next start row after inspecting the original Ready and Run in
/// the same fenced Read. A claim needs the previously confirmed dispatch
/// candidate and its exact physical successor in this Read.
pub fn prepare_client_effect_first_start_step(
  preparing : ClientSavedSubmissionSnapshot,
  saved : ClientSavedSubmissionSnapshot,
  materials : ClientEffectRunMaterials,
  original : ClientEffectRunJournalAppend,
  locator : ClientJournalPhysicalRow,
  current_authorization : Bool,
  dispatch? : ClientEffectFirstStartStep? = None,
  before_decode? : ((ClientRunJournalConstruction) -> Result[
    Unit,
    ClientJournalDecodingIssue,
  ])? = None,
  before_encode? : ((Int, Int, Int) -> Result[Unit, ClientJournalEncodingIssue])? = None,
) -> Result[
  ClientEffectFirstStartStep,
  ClientRunJournalAppendIssue[ClientRunStartIssue],
] {
  if !current_authorization {
    return Err(Observation(AuthorizationDenied))
  }
  guard client_first_effect_saved_original_matches(
      preparing, saved, materials, original, locator,
    ) &&
    materials.request is Some(request) &&
    saved.run is Some(before) else {
    return Err(InvalidOriginal)
  }
  let (key, first, _, _) = client_run_journal_append_rows(original.run)
  match dispatch {
    None =>
      if before.key != key || before.revision != 0L || before.body != first {
        return Err(InvalidOriginal)
      }
    Some(dispatch) =>
      if !dispatch.dispatch ||
        !physical_equal(dispatch.original, original) ||
        !confirm_client_effect_first_start_step(dispatch, before) {
        return Err(InvalidOriginal)
      }
  }
  let (record, policy, observation) = match
    decode_client_run_journal_row_with_retained_identity(
      before.body,
      request,
      materials.run_definition,
      before_construction=before_decode,
    ) {
    Ok(decoded) => decoded
    Err(_) => return Err(InvalidOriginal)
  }
  guard record.effect_material_originals is Some(_) &&
    record.checkpoint is None &&
    record.publication_binding is None &&
    record.task_materials_cid is None &&
    !record.cancellation_requested() &&
    !record.physical_start_claimed else {
    return Err(InvalidOriginal)
  }
  let definition = @publication.publication_contract_identity(
    materials.run_definition,
  )
  let changed = if dispatch is None {
    match
      prepare_client_run_start(
        request,
        record.request,
        record.definition,
        definition,
        record.dispatch_reserved,
        true,
      ) {
      Ok(ReserveDispatch) => { ..record, dispatch_reserved: true, }
      Ok(ReconcileReservedDispatch) => return Err(InvalidOriginal)
      Err(issue) => return Err(Observation(issue))
    }
  } else {
    match
      prepare_client_run_physical_start(
        request,
        record.request,
        record.definition,
        definition,
        record.dispatch_reserved,
        true,
        true,
      ) {
      Ok(true) => { ..record, physical_start_claimed: true, }
      Ok(false) => return Err(InvalidOriginal)
      Err(issue) => return Err(Observation(issue))
    }
  }
  client_run_journal_row_body(
    changed,
    local_run_policy_originals=policy,
    run_observation_originals=observation,
    before_construction=before_encode,
  )
  .map(body => { original, dispatch: dispatch is None, before, body, })
  .map_err(issue => Encoding(issue))
}

///|
/// Supply the existing one-row CAS transport's coordinates and bytes.
pub fn client_effect_first_start_step_row(
  step : ClientEffectFirstStartStep,
) -> (ClientJournalPhysicalRow, Bytes) {
  (step.before, step.body)
}

///|
/// Compare the complete successor in the caller's current original Read.
pub fn confirm_client_effect_first_start_step(
  step : ClientEffectFirstStartStep,
  actual : ClientJournalPhysicalRow,
) -> Bool {
  actual.key == step.before.key &&
  actual.revision == step.before.revision + 1L &&
  actual.body == step.body
}
