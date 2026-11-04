///|
/// Open the admitted bound Effect Run on its original managed parent. The
/// retained plan supplies both the generated originals and their configured
/// Local limits. Bound Run admission, physical Source custody and permission
/// remain their existing independent obligations.
pub fn open_installed_effect_managed_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
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
  let opened = select_installed_effect_managed_host(
    owner,
    bound,
    sources.copy(),
  )
  owner.source_free_opening = false
  opened
}

///|
fn select_installed_effect_managed_host(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  let plan = match
    installed_effect_managed_operation_plan(
      owner,
      @publication_host.prepared_client_effect_run_computation(bound),
      owner.request,
    ) {
    Err(issue) => return Err(issue)
    Ok(plan) => plan
  }
  if !physical_equal(
      plan.prepared,
      @publication_host.prepared_client_effect_run_computation(bound),
    ) {
    return Err(ForeignOriginal)
  }
  // The plan already prepared its Source requirements and sequences with this
  // admitted invocation original. Equal wire/CIDs or another restored context
  // cannot replace its actual Run admission/definition during the handoff.
  if plan.query_time is Some(original) &&
    !@publication_host.client_effect_run_query_time_matches(
      bound,
      original,
      plan.request,
    ) {
    return Err(ForeignOriginal)
  }
  let graph = installed_managed_owner_graph(Effect(plan.prepared))
  let first = @strategy.graph_captured_prefix(graph)
  if sources.length() != first ||
    plan.sequences.length() != @strategy.graph_task_count(graph) ||
    !client_local_capacity_plan_matches(
      plan.capacity_plan,
      plan.compute_sequences,
      plan.capacity_plan.admitted_rows,
    ) {
    return Err(ForeignOriginal)
  }
  let ledger = match require_installed_managed_run(owner) {
    Err(issue) => return Err(issue)
    Ok(ledger) => ledger
  }
  // Reentrant current/provider callbacks cannot replace this owner's one DAG
  // or retire the parent while its original configuration is in progress.
  open_installed_effect_managed_host_original(
    owner, bound, sources, plan, ledger,
  )
}

///|
fn open_installed_effect_managed_host_original(
  owner : ClientInstalledManagedRun,
  bound : @publication_host.PreparedClientEffectRun,
  sources : Array[@query.CapturedInputSource],
  plan : ClientInstalledEffectManagedPlan,
  ledger : @resources.Ledger,
) -> Result[
  (
    @builtin.ConfiguredComputeHost[@strategy.RunIssue],
    @strategy.CapturedEffectRunDAG,
    Array[@execution.GeneratedSequence],
  )?,
  ClientInstalledManagedRunIssue,
] {
  let graph = installed_managed_owner_graph(Effect(plan.prepared))
  let first = @strategy.graph_captured_prefix(graph)
  let checked = @publication_host.prepared_client_effect_run_graph(bound)
  if !physical_equal(@strategy.checked_effect_run_graph(checked), graph) ||
    !installed_effect_managed_limits_fit(owner, plan, ledger) {
    return Err(ForeignOriginal)
  }
  let opened = if first == 0 {
    @strategy.open_source_free_effect_run_dag(checked, ledger)
  } else if first == 1 {
    @strategy.open_captured_effect_run_dag(checked, sources[0], ledger)
  } else {
    @strategy.open_multi_captured_effect_run_dag(
      checked,
      Array::makei(first, index => (index, sources[index])),
      ledger,
    )
  }
  let captured = match opened {
    Err(_) => return Err(Unsupported)
    Ok(value) => value
  }
  let run = @strategy.captured_effect_run_dag(captured)
  // Retain immediately, before provider/configuration callbacks can fail.
  // None/error does not certify release; the original parent keeps cleanup.
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
    Err(issue) => {
      ignore(reject_client_local_run(run))
      return Err(issue)
    }
    Ok(original) =>
      if !physical_equal(original, ledger) {
        ignore(reject_client_local_run(run))
        return Err(ForeignOriginal)
      }
  }
  Ok(host.map(value => (value, captured, plan.sequences)))
}
