///|
/// A live view of the entire finite inventory after all no-I/O preparation.
/// It is issued once by this execution and becomes unusable at reclamation.
/// Retaining bytes with equal CIDs cannot manufacture the physical owner.
pub struct ModelPreparedCallSet {
  owner : ModelExecution
  mut scope : @publication.BoundModelInvocationScope?
  // One installed original admission, not a new Ledger or per-Run pool.
  mut io_access : @resources.ModelIoAccess?
}

///|
/// Issued only by the physical owner during entry preparation, then retained
/// across an admitted persistence wait. Historical attempt evidence remains
/// readable separately and cannot recreate this token or grant a new send.
pub struct ModelCallEntry {
  prepared : ModelPreparedCallSet
  progress : ModelSlotProgress
  slot : Int
  trace : ModelAttemptTrace
  admission : @publication_host.ClientInferDispatchAdmission
  mut acknowledgement : ModelCallEntryAcknowledgement?
  mut persistence : ModelCallEntryPersistence?
  mut gate_issued : Bool
  mut send_started : Bool
}

///|
pub fn prepared_model_call_set(
  execution : ModelExecution,
) -> ModelPreparedCallSet? {
  let state = execution.state
  if state.reclaimed ||
    state.stop_requested ||
    !state.durable_calls ||
    !(state.progress.phase is DispatchSlot) ||
    state.call_scope is None ||
    state.requests.length() != @relation.prepared_infer_rows_count(state.rows) ||
    (
      state.physical_preflight is Some(_) &&
      state.physical_next_slot != state.requests.length()
    ) {
    return None
  }
  if state.prepared_call_set is Some(value) {
    return Some(value)
  }
  if check_model_original_resources_mutable(state) is Err(_) {
    return None
  }
  let prepared = { owner: execution, scope: None, io_access: None, }
  state.prepared_call_set = Some(prepared)
  Some(prepared)
}

///|
fn prepared_model_current(value : ModelPreparedCallSet) -> Bool {
  let state = value.owner.state
  !state.reclaimed &&
  !state.stop_requested &&
  state.prepared_call_set is Some(original) &&
  physical_equal(original, value) &&
  state.call_scope is Some(scope) &&
  @publication_host.client_infer_call_scope_matches_rows(
    scope,
    state.rows,
    state.fixed_request_cid,
  )
}

///|
pub fn prepared_model_call_count(value : ModelPreparedCallSet) -> Int? {
  if prepared_model_current(value) {
    Some(value.owner.state.requests.length())
  } else {
    None
  }
}

///|
pub fn prepared_model_call_at(
  value : ModelPreparedCallSet,
  slot : Int,
) -> @publication.RunEvidenceValue? {
  if !prepared_model_current(value) {
    return None
  }
  match value.owner.state.requests.get(slot) {
    Some(request) => request.call
    None => None
  }
}

///|
/// The original typed request, not a send capability or a reconstructed row.
pub fn prepared_model_request(
  value : ModelPreparedCallSet,
  slot : Int,
) -> ModelRequest? {
  if !prepared_model_current(value) {
    return None
  }
  value.owner.state.requests.get(slot).map(item => item.request)
}

///|
/// Retained provider-port originals after no-I/O preparation. Callers must
/// reserve copy custody and authorize capture before saving these strings.
pub fn prepared_model_physical_request(
  value : ModelPreparedCallSet,
  slot : Int,
) -> (ModelRequest, ModelPhysicalRequestEvidence)? {
  guard prepared_model_request(value, slot) is Some(request) &&
    value.owner.state.physical_plans.get(slot) is Some(plan) &&
    physical_equal(request, plan.request) &&
    plan.evidence is Some(evidence) else {
    return None
  }
  Some((request, evidence))
}

///|
pub fn prepared_model_input_artifact(
  value : ModelPreparedCallSet,
) -> @publication.RunEvidenceValue? {
  if !prepared_model_current(value) {
    return None
  }
  value.owner.state.call_scope.map(
    @publication_host.client_infer_call_scope_artifact,
  )
}

///|
pub fn prepared_model_input(
  value : ModelPreparedCallSet,
) -> @relation.CompletedOutput? {
  if !prepared_model_current(value) {
    return None
  }
  match value.owner.state.call_scope {
    Some(scope) => @publication_host.client_infer_call_scope_input(scope)
    None => None
  }
}

///|
pub fn prepared_model_identities(
  value : ModelPreparedCallSet,
) -> (String, String, String)? {
  if !prepared_model_current(value) {
    return None
  }
  let state = value.owner.state
  Some(
    (
      @environment.model_task_connector(state.task),
      @environment.model_task_identity(state.task).2,
      state.fixed_request_cid,
    ),
  )
}

///|
/// Binding a declared scope also compares every actual prepared call. This
/// is the execution completeness proof missing from schema/CID admission.
pub fn bind_prepared_model_scope(
  value : ModelPreparedCallSet,
  scope : @publication.BoundModelInvocationScope,
) -> Result[Unit, ModelExecutionIssue] {
  if check_model_original_resources_mutable(value.owner.state) is Err(issue) {
    return Err(issue)
  }
  guard prepared_model_current(value) &&
    prepared_model_input_artifact(value) is Some(input) else {
    return Err(RequestIdentity)
  }
  if value.owner.state.source is Provider(provider) &&
    provider.invocation is OriginalMock(original) &&
    !original_mock_scope_matches(original, scope) {
    return Err(RequestIdentity)
  }
  let slots = @publication.model_invocation_scope_slots(scope)
  if @publication.model_invocation_scope_input_cid(scope) !=
    @publication.run_evidence_value_identity(input) ||
    slots.length() != value.owner.state.requests.length() {
    return Err(RequestIdentity)
  }
  for index in 0..<slots.length() {
    guard prepared_model_call_at(value, index) is Some(call) &&
      @publication.run_evidence_value_identity(call) == slots[index] else {
      return Err(RequestIdentity)
    }
  }
  if value.scope is Some(original) &&
    @publication.model_invocation_scope_cid(original) !=
    @publication.model_invocation_scope_cid(scope) {
    return Err(RequestIdentity)
  }
  value.scope = Some(scope)
  Ok(())
}

///|
pub fn bind_prepared_model_dispatch(
  value : ModelPreparedCallSet,
  admission : @publication_host.ClientInferDispatchAdmission,
  enter : (ModelCallEntry) -> Bool,
) -> Result[Unit, ModelExecutionIssue] {
  if check_prepared_model_dispatch(value, admission) is Err(issue) {
    return Err(issue)
  }
  let state = value.owner.state
  state.dispatch_admission = Some(admission)
  state.enter_call = Some(enter)
  state.enter_persistence = None
  Ok(())
}

///|
/// Private-port connection, not installation of a funded Host capability.
/// The original owner retains one entry across Pending until a typed result.
pub fn bind_prepared_model_entry_persistence(
  value : ModelPreparedCallSet,
  admission : @publication_host.ClientInferDispatchAdmission,
  begin : (ModelCallEntry) -> ModelCallEntryPersistence?,
) -> Result[Unit, ModelExecutionIssue] {
  if check_prepared_model_dispatch(value, admission) is Err(issue) {
    return Err(issue)
  }
  let state = value.owner.state
  state.dispatch_admission = Some(admission)
  state.enter_call = None
  state.enter_persistence = Some(begin)
  Ok(())
}

///|
fn check_prepared_model_dispatch(
  value : ModelPreparedCallSet,
  admission : @publication_host.ClientInferDispatchAdmission,
) -> Result[Unit, ModelExecutionIssue] {
  let state = value.owner.state
  if check_model_original_resources_mutable(state) is Err(issue) {
    return Err(issue)
  }
  guard prepared_model_current(value) &&
    state.progress.phase is DispatchSlot &&
    state.progress.entry is None &&
    state.progress.settlement is None &&
    value.scope is Some(scope) &&
    state.call_scope is Some(call_scope) &&
    @publication_host.client_infer_dispatch_matches_scope(admission, call_scope) &&
    @publication_host.client_infer_dispatch_subject(admission) ==
    @publication.model_invocation_scope_cid(scope) else {
    return Err(RequestIdentity)
  }
  match @publication_host.check_client_infer_dispatch_current(admission) {
    Err(issue) => return Err(Authorization(issue))
    Ok(_) => ()
  }
  // The authority callback may change the resource fence. Nothing mutable
  // follows a stale pre-callback observation of that same original Ledger.
  check_model_original_resources_mutable(state)
}

///|
/// Fail closed outside the actual stack frame immediately before invoke.
/// The journal calls this before it commits EnteredUnknown, at its own time.
pub fn model_call_entry_current(
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
) -> Bool {
  let state = prepared.owner.state
  physical_equal(entry.prepared, prepared) &&
  prepared_model_current(prepared) &&
  model_slot_progress_owned(state, entry.progress) &&
  entry.progress.phase is DispatchSlot &&
  entry.progress.slot == entry.slot &&
  entry.progress.entry is Some(current) &&
  physical_equal(current, entry) &&
  state.dispatch_admission is Some(admission) &&
  physical_equal(admission, entry.admission) &&
  @publication_host.check_client_infer_dispatch_current(admission) is Ok(_) &&
  (
    state.egress_admission is None ||
    @publication_host.check_client_infer_egress_current(
      state.egress_admission.unwrap(),
    )
    is Ok(_)
  )
}

///|
pub fn model_call_entry_originals(
  entry : ModelCallEntry,
) -> (Int, String, String, String)? {
  if !model_call_entry_current(entry, entry.prepared) {
    return None
  }
  Some(
    (
      entry.slot,
      @publication.run_evidence_value_json(entry.trace.call),
      @publication.run_evidence_value_json(entry.trace.attempt),
      @publication.run_evidence_value_json(entry.trace.authority),
    ),
  )
}

///|
pub fn prepared_model_matches(
  value : ModelPreparedCallSet,
  execution : ModelExecution,
) -> Bool {
  physical_equal(value.owner, execution) && prepared_model_current(value)
}

///|
pub fn prepared_model_scope(
  value : ModelPreparedCallSet,
) -> @publication.BoundModelInvocationScope? {
  if prepared_model_current(value) {
    value.scope
  } else {
    None
  }
}

///|
/// One adopted call remains pinned at this explicit custody boundary. It is
/// not evidence that the entire INFER occurrence or its Result completed.
pub struct ModelCallSettlement {
  owner : ModelExecution
  progress : ModelSlotProgress
  slot : Int
}

///|
pub fn model_call_settlement(
  execution : ModelExecution,
) -> ModelCallSettlement? {
  let state = execution.state
  guard !state.reclaimed &&
    state.progress.settlement is Some(slot) &&
    slot < state.progress.slot &&
    model_outcome_at(state, slot) is Some(_) else {
    return None
  }
  Some({ owner: execution, progress: state.progress, slot, })
}

///|
pub fn model_call_settlement_slot(value : ModelCallSettlement) -> Int? {
  let state = value.owner.state
  if model_slot_progress_owned(state, value.progress) &&
    value.progress.settlement == Some(value.slot) &&
    value.slot < value.progress.slot {
    Some(value.slot)
  } else {
    None
  }
}

///|
/// The installed custody adapter acknowledges only after exact Store originals
/// and the existing journal observation agree. This cannot start a send by itself.
pub fn acknowledge_model_call_settlement(value : ModelCallSettlement) -> Bool {
  if check_model_original_resources_mutable(value.owner.state) is Err(_) {
    return false
  }
  if model_call_settlement_slot(value) is None {
    return false
  }
  if value.progress.call is Some(call) {
    guard call.entry is Some(entry) && entry.slot == value.slot else {
      return false
    }
    // This boundary changes only the original custody fact. Physical cleanup
    // callbacks run on a later advance, never inside settlement acknowledgement.
    call.settlement_acknowledged = true
  }
  value.progress.settlement = None
  true
}
