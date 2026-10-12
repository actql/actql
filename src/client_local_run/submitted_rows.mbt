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
) -> Result[LocalSubmittedRunRows, LocalSubmittedRunRowsIssue] {
  if !physical_equal(
      plan.input,
      @input.local_submitted_preparation_input(preparation),
    ) {
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
  let run = match
    @host.client_run_journal_row_body({
      request: plan.request,
      definition: plan.definition,
      dispatch_reserved: false,
      physical_start_claimed: false,
      cancellation_requested: false,
      publication_binding: None,
      publication_policy_originals: None,
      effect_material_originals: None,
      checkpoint: None,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  let submitted = match
    @host.client_submitted_intent_journal_row_body(
      reference_wire,
      intent,
      run_admission=Some((plan.request, local_run_definition_cid(plan), 0L)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Encoding(issue))
  }
  Ok({ plan, preparation, reference, preparing, run, submitted, })
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
