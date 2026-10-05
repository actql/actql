///|
/// Enable durable physical entry before any input or provider work. A Run
/// binding alone is never an implicit permit to bypass this Host boundary.
pub fn require_model_call_entry(
  active : Execution,
) -> Result[Unit, InvocationBindingIssue] {
  if active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.phase is Input) ||
    active.work != 0L ||
    !(active.source is Physical(_)) {
    return Err(IncompleteExecution)
  }
  active.durable_calls = true
  Ok(())
}

///|
pub fn prepared_call_set(active : Execution) -> @model.ModelPreparedCallSet? {
  if active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.phase is Model) {
    return None
  }
  match active.model {
    Some(model) => @model.prepared_model_call_set(model)
    None => None
  }
}

///|
pub fn bind_model_scope(
  active : Execution,
  prepared : @model.ModelPreparedCallSet,
  scope : @publication.RunEvidenceValue,
  provider : @publication.RunEvidenceValue,
  expected : @publication.ModelInvocationBoundary,
) -> Result[@publication.BoundModelInvocationScope, InvocationBindingIssue] {
  guard !active.reclaimed &&
    !active.cancelled &&
    !active.advancing &&
    active.run_binding is Some(run) &&
    active.model is Some(model) &&
    @model.prepared_model_matches(prepared, model) &&
    @model.prepared_model_input_artifact(prepared) is Some(input) &&
    @model.prepared_model_call_count(prepared) is Some(count) else {
    return Err(ForeignRun)
  }
  let (task, _, _) = @publication_host.client_infer_occurrence_coordinates(
    active.occurrence,
  )
  guard active.plan is Some(plan) &&
    active.call_scope is Some(call_scope) &&
    expected.task_index == task.to_int64() &&
    expected.strategy_revision == 0L &&
    expected.inference_barrier_cid ==
    @publication_host.client_infer_plan_graph_barrier_cid(plan) &&
    @publication_host.client_infer_call_scope_unit_id(call_scope) ==
    Some(expected.unit_id) else {
    return Err(ForeignRun)
  }
  let slots = []
  for index in 0..<count {
    guard @model.prepared_model_call_at(prepared, index) is Some(call) else {
      return Err(IncompleteExecution)
    }
    slots.push(call)
  }
  let bound = match
    @publication_host.bind_client_model_invocation_scope(
      run.compiled,
      run.definition,
      scope,
      provider,
      input,
      slots,
      expected,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Evidence(issue))
  }
  if @model.bind_prepared_model_scope(prepared, bound) is Err(_) {
    return Err(ForeignRun)
  }
  Ok(bound)
}

///|
pub fn bind_model_dispatch(
  active : Execution,
  prepared : @model.ModelPreparedCallSet,
  admission : @publication_host.ClientInferDispatchAdmission,
  enter : (@model.ModelCallEntry) -> Bool,
) -> Result[Unit, InvocationBindingIssue] {
  guard !active.reclaimed &&
    !active.cancelled &&
    !active.advancing &&
    active.run_binding is Some(run) &&
    active.model is Some(model) &&
    @model.prepared_model_matches(prepared, model) &&
    @publication_host.client_infer_dispatch_matches_run(
      admission,
      run.compiled,
      run.definition,
    ) else {
    return Err(ForeignRun)
  }
  if @model.bind_prepared_model_dispatch(prepared, admission, enter) is Err(_) {
    return Err(ForeignRun)
  }
  active.dispatch_admission = Some(admission)
  Ok(())
}

///|
pub fn call_settlement(active : Execution) -> @model.ModelCallSettlement? {
  if active.reclaimed || active.advancing {
    None
  } else {
    match active.model {
      Some(model) => @model.model_call_settlement(model)
      None => None
    }
  }
}

///|
pub fn unknown_calls(active : Execution) -> Bool {
  active.model.map(@model.model_execution_unknown_calls).unwrap_or(false)
}

///|
pub fn stopped_attempt_slot(active : Execution, index : Int) -> Int? {
  match active.model {
    Some(model) => @model.stopped_model_attempt_slot(model, index)
    None => None
  }
}

///|
/// Historical slot fences only remove send eligibility. Actual saved/unknown
/// proofs must still be admitted against the completed fixed inventory later.
pub fn restrict_model_send_slots(
  active : Execution,
  eligible : Array[Bool],
) -> Result[Unit, InvocationBindingIssue] {
  if !active.durable_calls ||
    active.reclaimed ||
    active.cancelled ||
    active.advancing ||
    !(active.phase is Input) ||
    active.work != 0L ||
    active.model_send_mask is Some(_) ||
    eligible.length() > 128 {
    return Err(IncompleteExecution)
  }
  active.model_send_mask = Some(eligible.copy())
  Ok(())
}

///|
pub fn model_cleanup_progress(active : Execution) -> Int {
  active.model.map(@model.model_cleanup_progress).unwrap_or(0)
}
