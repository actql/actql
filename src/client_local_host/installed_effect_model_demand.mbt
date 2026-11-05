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
  model_limits : @resources.LedgerLimits
  read_retained_bytes : Int64
  read_execution_bytes : Int64
  bootstrap_retained_bytes : Int64
  bootstrap_execution_bytes : Int64
  max_reservations : Int
  max_holdings : Int
  max_delegations : Int
  components : Array[ClientInstalledEffectModelDemand]?
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
  bootstrap? : (Int64, Int64)? = None,
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
      model_limits,
      read_retained_bytes,
      read_execution_bytes,
      bootstrap~,
    )
    is Some(limits) else {
    return Err(InsufficientCapacity)
  }
  let (bootstrap_retained_bytes, bootstrap_execution_bytes) = bootstrap.unwrap_or(
    (read_retained_bytes, read_execution_bytes),
  )
  Ok({
    prepared,
    compiled,
    _compilation: compilation,
    definition,
    _occurrence: occurrence,
    graph,
    limits,
    model_limits,
    read_retained_bytes,
    read_execution_bytes,
    bootstrap_retained_bytes,
    bootstrap_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    components: None,
  })
}

///|
/// The original selected per-read window. This projects retained DATA only;
/// it neither selects bounds again nor issues a Scope or resource allowance.
pub fn installed_effect_model_read_window(
  model : ClientInstalledEffectModelDemand,
) -> Array[Int64] {
  [model.read_retained_bytes, model.read_execution_bytes]
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

///|
/// Compose original component DATA for one Effect Plan, one bootstrap and one
/// preparation Ledger. Only the complete compiler order can be adopted.
pub fn prepare_installed_effect_models_demand(
  components : Array[ClientInstalledEffectModelDemand],
) -> Result[ClientInstalledEffectModelDemand, ClientInstalledManagedRunIssue] {
  guard components.length() > 1 && components.length() <= 128 else {
    return Err(ForeignOriginal)
  }
  let first = components[0]
  let graphs = @publication_host.client_compiled_run_infers(first.compiled)
  if graphs.length() != components.length() { return Err(ForeignOriginal) }
  let mut models : @resources.LedgerLimits = {
    planning_work: 0, attempts: 0, holdings: 0, transfer_bytes: 0L,
    retained_bytes: 0L, execution_bytes: 0L,
  }
  let mut r = 0L
  let mut e = 0L
  let mut br = 0L
  let mut be = 0L
  let mut reservations = 0
  let mut holdings = 0
  let mut delegations = 0
  for index, original in components {
    if original.components is Some(_) ||
      !physical_equal(original.prepared, first.prepared) ||
      !physical_equal(original.compiled, first.compiled) ||
      !physical_equal(original._compilation, first._compilation) ||
      !physical_equal(original.definition, first.definition) ||
      !physical_equal(original.graph, graphs[index]) ||
      !@publication_host.client_infer_occurrence_matches_plan(original._occurrence, graphs[index]) {
      return Err(ForeignOriginal)
    }
    guard @resources.add_ledger_limits(models, original.model_limits) is Some(next) &&
      @execution.checked_preparation_add_product(r, original.read_retained_bytes, 1L) is Some(next_r) &&
      @execution.checked_preparation_add_product(e, original.read_execution_bytes, 1L) is Some(next_e) else {
      return Err(InsufficientCapacity)
    }
    models = next
    r = next_r
    e = next_e
    br = Int64::max(br, original.bootstrap_retained_bytes)
    be = Int64::max(be, original.bootstrap_execution_bytes)
    reservations = Int::max(reservations, original.max_reservations)
    holdings = Int::max(holdings, original.max_holdings)
    delegations = Int::max(delegations, original.max_delegations)
  }
  guard installed_model_demand_limits(models, r, e, bootstrap=Some((br, be))) is Some(limits) else {
    return Err(InsufficientCapacity)
  }
  Ok({ ..first, limits, model_limits: models, read_retained_bytes: r, read_execution_bytes: e,
    bootstrap_retained_bytes: br, bootstrap_execution_bytes: be,
    max_reservations: reservations, max_holdings: holdings, max_delegations: delegations,
    components: Some(components.copy()), })
}

///|
fn installed_effect_model_demand_complete(model : ClientInstalledEffectModelDemand) -> Bool {
  let graphs = @publication_host.client_compiled_run_infers(model.compiled)
  match model.components {
    None => graphs.length() == 1 && physical_equal(graphs[0], model.graph)
    Some(originals) => {
      if originals.length() < 2 || graphs.length() != originals.length() { return false }
      for index, original in originals {
        if original.components is Some(_) || !physical_equal(original.graph, graphs[index]) ||
          !physical_equal(original.compiled, model.compiled) ||
          !physical_equal(original._compilation, model._compilation) ||
          !physical_equal(original.prepared, model.prepared) ||
          !physical_equal(original.definition, model.definition) { return false }
      }
      true
    }
  }
}
