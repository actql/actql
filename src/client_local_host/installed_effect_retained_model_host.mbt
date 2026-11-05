///|
/// Closed restored-Model caller only. The Node entry first claims the actual
/// completed Execution's one-use output pin. This helper preserves the same
/// installed Plan, bound Run, Source holdings and Effect dependency inventory.
pub fn open_installed_effect_retained_model_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  model_graph : @publication_host.ClientInferPlanGraph,
  output : @execution.CompletedOutput,
  completed_model : @model.ModelExecution,
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  if owner.source_free_opening || owner.source_free_captured is Some(_) {
    return Err(AlreadyBound)
  }
  owner.source_free_opening = true
  defer {
    owner.source_free_opening = false
  }
  select_installed_effect_retained_model_host(
    owner,
    bound,
    sources.copy(),
    compiled,
    definition,
    model_graph,
    output,
    completed_model,
  )
}

///|
fn select_installed_effect_retained_model_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  model_graph : @publication_host.ClientInferPlanGraph,
  output : @execution.CompletedOutput,
  completed_model : @model.ModelExecution,
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  let (plan, ledger) = match
    require_installed_effect_operation_plan(
      owner,
      @publication_host.prepared_client_effect_run_computation(bound),
      owner.request,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let graph = installed_managed_owner_graph(Effect(plan.prepared))
  let checked = @publication_host.prepared_client_effect_run_graph(bound)
  guard plan.model is Some(model) &&
    physical_equal(model.compiled, compiled) &&
    physical_equal(model.definition, definition) &&
    physical_equal(model.graph, model_graph) &&
    @model.original_completed_model_matches_parent(completed_model, ledger) &&
    physical_equal(@strategy.checked_effect_run_graph(checked), graph) &&
    sources.length() == @strategy.graph_captured_prefix(graph) &&
    plan.sequences.length() == @strategy.graph_task_count(graph) &&
    client_local_capacity_plan_matches(
      plan.capacity_plan,
      plan.compute_sequences,
      plan.capacity_plan.admitted_rows,
    ) &&
    installed_effect_managed_limits_fit(owner, plan, ledger) else {
    return Err(ForeignOriginal)
  }
  if plan.query_time is Some(original) &&
    !@publication_host.client_effect_run_query_time_matches(
      bound,
      original,
      plan.request,
    ) {
    return Err(ForeignOriginal)
  }
  let (task, _, step) = @publication_host.client_infer_occurrence_coordinates(
    model._occurrence,
  )
  let captured = match
    @strategy.open_multi_captured_effect_run_retained_model_dag(
      checked,
      Array::makei(sources.length(), index => (index, sources[index])),
      ledger,
      task,
      step,
      output,
    ) {
    Ok(value) => value
    Err(_) => return Err(ForeignOriginal)
  }
  let run = @strategy.captured_effect_run_dag(captured)
  // Retain before the original configuration/current callbacks. A failure
  // leaves cleanup on this same parent; it never returns a stop ACK.
  owner.source_free_captured = Some(run)
  let host = bind_client_local_configuration(
    run,
    plan.configuration,
    1L,
    0L,
    0L,
    0L,
  )
  match require_installed_managed_run(owner) {
    Ok(original) if physical_equal(original, ledger) &&
      @model.original_completed_model_matches_parent(completed_model, original) =>
      ()
    Ok(_) => {
      ignore(reject_client_local_run(run))
      return Err(ForeignOriginal)
    }
    Err(issue) => {
      ignore(reject_client_local_run(run))
      return Err(issue)
    }
  }
  if !@execution.completed_output_available(output) {
    ignore(reject_client_local_run(run))
    return Err(ForeignOriginal)
  }
  Ok(host.map(value => (value, captured, plan.sequences)))
}

///|
/// Cleanup of this original parent's captured consumers also works when a
/// fallible Host constructor never returned its wrapper. Revocation forbids
/// new work, not retirement. Pending children retain the same parent for retry.
pub fn retire_installed_effect_captured_consumers(
  owner : ClientInstalledManagedRun,
) -> Result[Bool, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) && physical_equal(owner, original) else {
    return Err(ForeignOriginal)
  }
  if owner.source_free_opening || owner.effect_operation_opening {
    return Ok(false)
  }
  Ok(
    match owner.source_free_captured {
      Some(run) => @strategy.retire_captured_task_outputs(run)
      None => true
    },
  )
}
