///|
// Persistence is an observation of the original journal operation, not a
// current dispatch permit. Stop and current authority are intentionally not
// prerequisites for retaining its late acknowledgement. The original owner,
// active entry, request, attempt, plan and reservation must still be retained.
fn model_call_entry_persistence_owned(
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
) -> Bool {
  let state = prepared.owner.state
  guard !state.reclaimed &&
    physical_equal(entry.prepared, prepared) &&
    state.prepared_call_set is Some(original) &&
    physical_equal(original, prepared) &&
    model_slot_progress_owned(state, entry.progress) &&
    entry.progress.phase is DispatchSlot &&
    entry.progress.slot == entry.slot &&
    entry.progress.entry is Some(current) &&
    physical_equal(current, entry) &&
    state.dispatch_admission is Some(admission) &&
    physical_equal(admission, entry.admission) &&
    state.call_scope is Some(scope) &&
    @publication_host.client_infer_call_scope_matches_rows(
      scope,
      state.rows,
      state.fixed_request_cid,
    ) &&
    state.requests.get(entry.slot) is Some(request) &&
    request.call is Some(call) &&
    physical_equal(call, entry.trace.call) &&
    state.reservations.get(entry.slot) is Some(reservation) &&
    @resources.reservation_open(reservation) else {
    return false
  }
  if state.physical_preflight is Some(_) {
    guard state.physical_plans.get(entry.slot) is Some(plan) &&
      physical_equal(plan.request, request.request) else {
      return false
    }
  }
  true
}

///|
/// The installed journal calls this only after saving the original entry.
/// Pending, unconfirmed persistence and a confirmed absent write cannot call
/// this issuer. It preserves the same nominal acknowledgement after an await
/// even if stop/current permission changed, but grants no transport permission.
/// Equal CIDs, copied JSON, reclaimed or another owner's entries cannot issue
/// this handle. The existing current checks and one-shot gate remain required.
pub fn acknowledge_saved_model_call_entry(
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
) -> ModelCallEntryAcknowledgement? {
  if !model_call_entry_persistence_owned(entry, prepared) || entry.send_started {
    return None
  }
  if entry.acknowledgement is Some(original) {
    return Some(original)
  }
  let acknowledgement : ModelCallEntryAcknowledgement = { entry, }
  entry.acknowledgement = Some(acknowledgement)
  Some(acknowledgement)
}

///|
/// Borrow the exact finite call inventory and its admitted evidence for the
/// installed persistence operation. This checks ownership, not a fresh current
/// permission: a late original save remains observable after stop/revocation.
/// It creates no acknowledgement, dispatch authority or replacement Entry.
pub fn model_call_entry_persistence_originals(
  entry : ModelCallEntry,
  prepared : ModelPreparedCallSet,
  admission : @publication_host.ClientInferDispatchAdmission,
) -> (
  Int,
  Int,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
  @publication.RunEvidenceValue,
  @publication.BoundModelInvocationScope,
)? {
  if !model_call_entry_persistence_owned(entry, prepared) ||
    !physical_equal(entry.admission, admission) ||
    entry.send_started {
    return None
  }
  guard prepared.scope is Some(scope) else { return None }
  Some(
    (
      prepared.owner.state.requests.length(),
      entry.slot,
      entry.trace.call,
      entry.trace.attempt,
      entry.trace.authority,
      scope,
    ),
  )
}
