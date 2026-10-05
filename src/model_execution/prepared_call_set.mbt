///|
/// A live view of the entire finite inventory after all no-I/O preparation.
/// It is issued once by this execution and becomes unusable at reclamation.
/// Retaining bytes with equal CIDs cannot manufacture the physical owner.
pub struct ModelPreparedCallSet {
  owner : ModelExecution
  mut scope : @publication.BoundModelInvocationScope?
}

///|
/// Available only during the synchronous physical entry callback. Historical
/// attempt evidence remains readable separately and cannot recreate this token.
pub struct ModelCallEntry {
  prepared : ModelPreparedCallSet
  slot : Int
  trace : ModelAttemptTrace
  admission : @publication_host.ClientInferDispatchAdmission
}

///|
pub fn prepared_model_call_set(
  execution : ModelExecution,
) -> ModelPreparedCallSet? {
  let state = execution.state
  if state.reclaimed ||
    state.stop_requested ||
    !state.durable_calls ||
    !(state.phase is DispatchSlot) ||
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
  let prepared = { owner: execution, scope: None, }
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
  guard prepared_model_current(value) &&
    prepared_model_input_artifact(value) is Some(input) else {
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
  let state = value.owner.state
  guard prepared_model_current(value) &&
    state.phase is DispatchSlot &&
    state.entering is None &&
    state.settlement_pending is None &&
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
  state.dispatch_admission = Some(admission)
  state.enter_call = Some(enter)
  Ok(())
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
  state.phase is DispatchSlot &&
  state.next_slot == entry.slot &&
  state.entering is Some(current) &&
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
  slot : Int
}

///|
pub fn model_call_settlement(
  execution : ModelExecution,
) -> ModelCallSettlement? {
  let state = execution.state
  guard !state.reclaimed &&
    state.settlement_pending is Some(slot) &&
    slot < state.next_slot &&
    state.outcomes.get(slot) is Some(_) else {
    return None
  }
  Some({ owner: execution, slot, })
}

///|
pub fn model_call_settlement_slot(value : ModelCallSettlement) -> Int? {
  let state = value.owner.state
  if !state.reclaimed &&
    state.settlement_pending == Some(value.slot) &&
    value.slot < state.next_slot {
    Some(value.slot)
  } else {
    None
  }
}

///|
/// The installed custody adapter acknowledges only after exact Store originals
/// and the existing journal observation agree. This cannot start a send by itself.
pub fn acknowledge_model_call_settlement(value : ModelCallSettlement) -> Bool {
  if model_call_settlement_slot(value) is None {
    return false
  }
  value.owner.state.settlement_pending = None
  true
}
