///|
pub(all) enum LocalSubmittedRunRowsIssue {
  ForeignPreparation
  ForeignReference
  AuthorizationMismatch
  Epoch(@host.SubmissionIdentityIssue)
  EpochNotAdmissible(@host.SubmissionEpochValidity)
  Binding(@host.ClientRunBindingIssue)
  CustodyLost
  Encoding(@host.ClientJournalEncodingIssue)
}

///|
/// Original Owner-issued write candidates. This object is not a committed
/// admission, current Run revision, dispatch permit or execution outcome.
pub struct LocalSubmittedRunRows {
  plan : LocalRunPlan
  preparation : @input.LocalSubmittedPreparation
  reference : @host.ClientSubmissionReferenceRecord
  preparing : Bytes
  run : Bytes
  submitted : Bytes
  local_policy_original : String?
  observation_originals : String?
  task_materials : LocalRunTaskMaterialsOriginal?
}

///|
/// Project the first-admission rows for the exact original preparation.
/// The Host must separately authenticate the epoch in the same physical Store
/// transaction, validate complete journal/count custody and recheck current
/// authority before adopting the saved rows. A projection does no I/O and
/// cannot replace those observations with these candidate bytes.
pub fn prepare_local_submitted_run_rows(
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  reference : @host.ClientSubmissionReferenceRecord,
  retained_preparing : Bytes,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
  now : Double,
  local_policy_original? : @host.ClientLocalRunPolicyOriginal? = None,
) -> Result[LocalSubmittedRunRows, LocalSubmittedRunRowsIssue] {
  prepare_local_submitted_run_rows_original(
    plan,
    preparation,
    reference,
    retained_preparing,
    permit,
    current,
    tuple,
    context_cid,
    now,
    local_policy_original,
    None,
    None,
  )
}

///|
/// The ordinary SDK acceptance keeps its actual original compiler evidence
/// before the first transaction. Missing old evidence is never recaptured.
pub fn prepare_local_sdk_submitted_run_rows(
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  reference : @host.ClientSubmissionReferenceRecord,
  retained_preparing : Bytes,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
  now : Double,
  local_policy_original : @host.ClientLocalRunPolicyOriginal,
  task_materials? : LocalRunTaskMaterialsOriginal? = None,
) -> Result[LocalSubmittedRunRows, LocalSubmittedRunRowsIssue] {
  let originals = match
    @host.capture_client_run_observation_originals(
      plan.compiled,
      plan.definition,
    ) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  let wire = match originals.wire() {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  prepare_local_submitted_run_rows_original(
    plan,
    preparation,
    reference,
    retained_preparing,
    permit,
    current,
    tuple,
    context_cid,
    now,
    Some(local_policy_original),
    Some(wire),
    task_materials,
  )
}

///|
fn prepare_local_submitted_run_rows_original(
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  reference : @host.ClientSubmissionReferenceRecord,
  retained_preparing : Bytes,
  permit : @authorization.DispatchAuthorization,
  current : @authorization.AdmittedAccountConfiguration,
  tuple : @authorization.AccessTuple,
  context_cid : String,
  now : Double,
  local_policy_original : @host.ClientLocalRunPolicyOriginal?,
  observation_originals : String?,
  task_materials : LocalRunTaskMaterialsOriginal?,
) -> Result[LocalSubmittedRunRows, LocalSubmittedRunRowsIssue] {
  if !physical_equal(
      plan.input,
      @input.local_submitted_preparation_input(preparation),
    ) {
    return Err(ForeignPreparation)
  }
  if task_materials is Some(original) && !physical_equal(original.plan, plan) {
    return Err(ForeignPreparation)
  }
  match
    @host.validate_client_run_binding(
      plan.request,
      plan.prepared,
      plan.compiled,
      plan.definition,
    ) {
    Ok(_) => ()
    Err(issue) => return Err(Binding(issue))
  }
  if !@host.client_submission_reference_matches_request(reference, plan.request) {
    return Err(ForeignReference)
  }
  let epoch = @host.client_submission_epoch_token_body(
    @host.client_submission_reference_record_epoch(reference),
  )
  match @host.submission_epoch_validity(epoch, now) {
    Err(issue) => return Err(Epoch(issue))
    Ok(Admissible) => ()
    Ok(validity) => return Err(EpochNotAdmissible(validity))
  }
  if current.account_id() != plan.account_id ||
    tuple != plan.tuple ||
    context_cid != plan.execution_context_cid ||
    !authorized_input(plan.prepared, permit, current, tuple, context_cid) {
    return Err(AuthorizationMismatch)
  }
  let intent = @input.local_submitted_preparation_intent(preparation)
  let reference_wire = @host.client_submission_reference_record_wire(reference)
  let preparing = match
    @host.client_submitted_intent_journal_row_body(reference_wire, intent) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  if preparing != retained_preparing ||
    !@host.client_submitted_intent_transition("preparing", "ready") {
    return Err(CustodyLost)
  }
  // The Host supplies the selected nominal original. Structural correspondence
  // cannot replace its adopted profile/current or the same-transaction ACK.
  let local_policy_original = match local_policy_original {
    None => None
    Some(original) => {
      let body = @host.client_local_run_policy_original_body(original)
      if @host.validate_client_local_run_policy_original_run(
          body,
          plan.request,
          plan.definition,
        )
        is Err(_) {
        return Err(CustodyLost)
      }
      Some(@utf8.decode(body) catch { _ => return Err(CustodyLost) })
    }
  }
  let run = match
    @host.client_run_journal_row_body(
      {
        request: plan.request,
        definition: plan.definition,
        dispatch_reserved: false,
        physical_start_claimed: false,
        cancellation_requested: false,
        publication_binding: None,
        publication_policy_originals: task_materials.map(value => {
          value.publication_policy_originals
        }),
        effect_material_originals: None,
        task_materials_cid: task_materials.map(value => value.cid),
        checkpoint: None,
      },
      local_run_policy_originals=local_policy_original,
      run_observation_originals=observation_originals,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  let submitted = match
    @host.client_submitted_intent_journal_row_body(
      reference_wire,
      intent,
      run_admission=Some((plan.request, local_run_definition_cid(plan), 0L)),
      run_state_observation=Some((0L, None)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  Ok({
    plan,
    preparation,
    reference,
    preparing,
    run,
    submitted,
    local_policy_original,
    observation_originals,
    task_materials,
  })
}

///|
/// Exact immutable chunk candidates belonging to these same nominal rows.
/// All entries must be inserted with the Run/ready/count writes atomically.
pub fn local_submitted_run_task_materials(
  value : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
) -> Result[LocalRunTaskMaterialsOriginal?, LocalSubmittedRunRowsIssue] {
  if !physical_equal(value.plan, plan) ||
    !physical_equal(value.preparation, preparation) {
    return Err(ForeignPreparation)
  }
  Ok(value.task_materials)
}

///|
/// The output stays attached to its original nominal preparation and Plan.
/// The returned bytes grant no custody to a copied input or saved response.
pub fn local_submitted_run_rows(
  value : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
) -> Result[(String, String, Bytes, Bytes, Bytes), LocalSubmittedRunRowsIssue] {
  if !physical_equal(value.plan, plan) ||
    !physical_equal(value.preparation, preparation) {
    return Err(ForeignPreparation)
  }
  Ok(
    (
      @host.client_request_scope_cid(plan.request),
      @host.client_submission_reference_record_request_id(value.reference),
      value.preparing,
      value.run,
      value.submitted,
    ),
  )
}

///|
/// Validate the actual saved row relationship against the original nominal
/// checked preparation. Inputs are observations from the same trusted Store
/// snapshot, not SDK flags or the earlier candidate-byte projection. This
/// pure check supplies no complete inventory, HMAC, COMMIT acknowledgement,
/// accepted public operation, dispatch or physical-start fact.
/// Nested Policy/Checkpoint/Effect originals still require their original
/// Run Owners; decoding their outer strings is not semantic readmission.
pub fn validate_local_saved_submitted_rows(
  value : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  run_key : String,
  run_revision : Int64,
  run_body : Bytes,
  submission_key : String,
  submission_revision : Int64,
  submission_body : Bytes,
) -> Result[Unit, LocalSubmittedRunRowsIssue] {
  local_saved_submitted_row_originals(
    value, plan, preparation, run_key, run_revision, run_body, submission_key, submission_revision,
    submission_body,
  ).map(_ => ())
}

///|
fn local_saved_submitted_row_originals(
  value : LocalSubmittedRunRows,
  plan : LocalRunPlan,
  preparation : @input.LocalSubmittedPreparation,
  run_key : String,
  run_revision : Int64,
  run_body : Bytes,
  submission_key : String,
  submission_revision : Int64,
  submission_body : Bytes,
  decode_run? : (Bytes) -> Result[
    (@host.ClientRunJournalEncoding, String?, String?),
    @host.ClientJournalDecodingIssue,
  ] = bytes => {
    @host.decode_client_run_journal_row_with_observation_originals(bytes)
  },
) -> Result[
  (@host.ClientRunJournalEncoding, String?, String?),
  LocalSubmittedRunRowsIssue,
] {
  if !physical_equal(value.plan, plan) ||
    !physical_equal(value.preparation, preparation) {
    return Err(ForeignPreparation)
  }
  if run_key != @host.client_request_scope_cid(plan.request) ||
    submission_key !=
    @host.client_submission_reference_record_request_id(value.reference) ||
    run_revision < 0L ||
    submission_revision < 0L {
    return Err(CustodyLost)
  }
  let (run, saved_policy, saved_observation) = match decode_run(run_body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  // Later Run revisions may change dispatch/publication facts. The original
  // finite Policy packet is immutable, including its initial issued_at.
  if saved_policy != value.local_policy_original ||
    saved_observation != value.observation_originals ||
    run.task_materials_cid != value.task_materials.map(original => original.cid) {
    return Err(CustodyLost)
  }
  if value.task_materials is Some(original) &&
    run.publication_policy_originals !=
    Some(original.publication_policy_originals) {
    return Err(CustodyLost)
  }
  let submitted = match
    @host.decode_client_submitted_journal_row(submission_body) {
    Ok(value) => value
    Err(_) => return Err(CustodyLost)
  }
  if @host.client_submission_reference_record_wire(submitted.reference) !=
    @host.client_submission_reference_record_wire(value.reference) ||
    @host.client_submitted_intent_cid(submitted.intent) !=
    @host.client_submitted_intent_cid(
      @input.local_submitted_preparation_intent(preparation),
    ) ||
    @host.client_request_identity_relation(plan.request, run.request) !=
    @host.SameRequest ||
    @publication.publication_contract_identity(run.definition) !=
    local_run_definition_cid(plan) {
    return Err(CustodyLost)
  }
  guard submitted.run_admission is Some(admission) else {
    return Err(CustodyLost)
  }
  match
    @host.validate_client_submitted_retained_run(
      submitted.reference,
      admission,
      run.request,
      run.definition,
      run_revision,
    ) {
    Ok(_) => Ok((run, saved_policy, saved_observation))
    Err(_) => Err(CustodyLost)
  }
}
