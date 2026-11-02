///|
/// Selected Model demand DATA beside the original checked Effect compilation.
/// The installation owns the original selected provider and its bounds; this
/// value grants no Model permission and creates no Ledger, Scope or reader.
struct ClientInstalledEffectModelDemand {
  prepared : @publication_host.PreparedClientEffectComputation
  compiled : @publication_host.ClientCompiledRun
  _compilation : @publication_host.ClientEffectCompilation
  definition : @publication.PublicationContract
  _occurrence : @publication_host.ClientInferOccurrence
  graph : @publication_host.ClientInferPlanGraph
  limits : @resources.LedgerLimits
  bootstrap_retained_bytes : Int64
  bootstrap_execution_bytes : Int64
  max_reservations : Int
  max_holdings : Int
  max_delegations : Int
}

///|
/// Bind the existing installed Model selection once, before quoting the same
/// Effect plan. The domain supplies its selected original bounds, not spare
/// bytes inferred from a Source/Compute quote or a reconstructed Run.
pub fn prepare_installed_effect_model_demand(
  prepared : @publication_host.PreparedClientEffectComputation,
  compiled : @publication_host.ClientCompiledRun,
  compilation : @publication_host.ClientEffectCompilation,
  definition : @publication.PublicationContract,
  occurrence : @publication_host.ClientInferOccurrence,
  graph : @publication_host.ClientInferPlanGraph,
  model_limits : @resources.LedgerLimits,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
) -> Result[ClientInstalledEffectModelDemand, ClientInstalledManagedRunIssue] {
  if !@publication_host.client_compiled_run_matches_effect(
      compiled, prepared, compilation,
    ) ||
    !@publication_host.client_infer_occurrence_matches_effect(
      occurrence, prepared,
    ) ||
    !@publication_host.client_infer_occurrence_matches_compiled_run(
      occurrence, compiled,
    ) ||
    !@publication_host.client_infer_occurrence_matches_plan(occurrence, graph) ||
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Err(_) {
    return Err(ForeignOriginal)
  }
  if max_reservations < 0 || max_holdings < 0 || max_delegations < 0 {
    return Err(InsufficientCapacity)
  }
  guard installed_model_demand_limits(
      model_limits, read_retained_bytes, read_execution_bytes,
    )
    is Some(limits) else {
    return Err(InsufficientCapacity)
  }
  Ok({
    prepared,
    compiled,
    _compilation: compilation,
    definition,
    _occurrence: occurrence,
    graph,
    limits,
    bootstrap_retained_bytes: read_retained_bytes,
    bootstrap_execution_bytes: read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
  })
}

///|
/// The original selected per-read window. This projects retained DATA only;
/// it neither selects bounds again nor issues a Scope or resource allowance.
pub fn installed_effect_model_read_window(
  model : ClientInstalledEffectModelDemand,
) -> Array[Int64] {
  [model.bootstrap_retained_bytes, model.bootstrap_execution_bytes]
}

///|
// One existing Model/read overlap definition for Pure and Effect Plans. The
// original selected domain supplies its bounds; this creates no allowance.
fn installed_model_demand_limits(
  model_limits : @resources.LedgerLimits,
  read_retained_bytes : Int64,
  read_execution_bytes : Int64,
  bootstrap? : (Int64, Int64)? = None,
) -> @resources.LedgerLimits? {
  // These are the original Scope bootstrap and simultaneous read allowance.
  // Both stay retained until the original census/reader retires. Count their
  // overlap before allocation; neither is funded by a disk/codec ceiling.
  let (bootstrap_retained, bootstrap_execution) = bootstrap.unwrap_or(
    (read_retained_bytes, read_execution_bytes),
  )
  guard read_retained_bytes > 0L &&
    read_execution_bytes > 0L &&
    bootstrap_retained > 0L &&
    bootstrap_execution >= 0L &&
    @execution.execution_capacity_inventory_add(
      model_limits.retained_bytes,
      QuotedBytes,
      bootstrap_retained,
      1,
    )
    is Some(retained_bootstrap) &&
    @execution.execution_capacity_inventory_add(
      retained_bootstrap,
      QuotedBytes,
      read_retained_bytes,
      1,
    )
    is Some(retained_bytes) &&
    @execution.execution_capacity_inventory_add(
      model_limits.execution_bytes,
      QuotedBytes,
      bootstrap_execution,
      1,
    )
    is Some(execution_bootstrap) &&
    @execution.execution_capacity_inventory_add(
      execution_bootstrap,
      QuotedBytes,
      read_execution_bytes,
      1,
    )
    is Some(execution_bytes) &&
    @resources.add_ledger_limits(
      {
        planning_work: 0,
        attempts: 0,
        holdings: 0,
        transfer_bytes: 0L,
        retained_bytes: 0L,
        execution_bytes: 0L,
      },
      { ..model_limits, retained_bytes, execution_bytes, },
    )
    is Some(limits) else {
    return None
  }
  Some(limits)
}

///|
/// Immutable DATA correspondence for the already selected original Plan.
/// This cannot issue a Scope or upgrade another Model's cleanup lineage.
pub fn installed_effect_plan_matches_model_demand(
  plan : ClientInstalledEffectManagedPlan,
  model : ClientInstalledEffectModelDemand,
) -> Bool {
  physical_equal(plan.prepared, model.prepared) &&
  plan.model is Some(original) &&
  physical_equal(original, model)
}
