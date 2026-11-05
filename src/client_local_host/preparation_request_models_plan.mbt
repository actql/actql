///|
// Demand DATA on the existing immutable Model Plan. One native Array retains
// the exact compiler-selected Graphs and their original read partitions.
// This is neither a Scope, physical holding, retry grant nor cleanup owner.
priv struct ClientInstalledModelReadPartition {
  graph : @publication_host.ClientInferPlanGraph
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
/// Prepare the complete source-free Model Plan on its SAME Request. Fold the
/// selected module's compute demand ONCE, all actual concurrent Model/read
/// demands, and the independently retained bootstrap ONCE. No scalar first
/// occurrence can stand in for a complete multi-INFER Plan.
pub fn[I] prepare_request_models_source_free_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  original : ClientInstalledManagedSourceFreePreparation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrences : Array[@publication_host.ClientInferOccurrence],
  graphs : Array[@publication_host.ClientInferPlanGraph],
  model_limits : Array[@resources.LedgerLimits],
  read_retained_bytes : Array[Int64],
  read_execution_bytes : Array[Int64],
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  bootstrap? : (Int64, Int64)? = None,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  prepare_request_models_plan_owned(
    owner,
    input,
    Some(original),
    None,
    request,
    compiled,
    definition,
    occurrences,
    graphs,
    model_limits,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    bootstrap,
  )
}

///|
/// Same complete Model Plan for the original captured Source module.
pub fn[I] prepare_request_models_capture_plan(
  owner : ClientRequestPreparation[I],
  input : I,
  original : ClientInstalledManagedCapturePlan,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrences : Array[@publication_host.ClientInferOccurrence],
  graphs : Array[@publication_host.ClientInferPlanGraph],
  model_limits : Array[@resources.LedgerLimits],
  read_retained_bytes : Array[Int64],
  read_execution_bytes : Array[Int64],
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  bootstrap? : (Int64, Int64)? = None,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  prepare_request_models_plan_owned(
    owner,
    input,
    None,
    Some(original),
    request,
    compiled,
    definition,
    occurrences,
    graphs,
    model_limits,
    read_retained_bytes,
    read_execution_bytes,
    max_reservations,
    max_holdings,
    max_delegations,
    bootstrap,
  )
}

///|
fn[I] prepare_request_models_plan_owned(
  owner : ClientRequestPreparation[I],
  input : I,
  source_free : ClientInstalledManagedSourceFreePreparation?,
  captured : ClientInstalledManagedCapturePlan?,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  occurrences : Array[@publication_host.ClientInferOccurrence],
  graphs : Array[@publication_host.ClientInferPlanGraph],
  model_limits : Array[@resources.LedgerLimits],
  read_retained_bytes : Array[Int64],
  read_execution_bytes : Array[Int64],
  max_reservations : Int,
  max_holdings : Int,
  max_delegations : Int,
  bootstrap : (Int64, Int64)?,
) -> Result[ClientInstalledManagedModelPlan, ClientInstalledManagedRunIssue] {
  let (module_prepared, compilation, compute_limits, query_time) = match
    (source_free, captured) {
    (Some(original), None) => {
      guard owner.program_source_free is Some(selected) &&
        physical_equal(selected, original) &&
        original.owner is Pure(prepared) &&
        original.configuration is Some(_) &&
        original.compilation is Some(@publication_host.Tasks(compilation)) else {
        return Err(ForeignOriginal)
      }
      if original._observed_query_time is Some((_, bound)) &&
        !physical_equal(bound, request) {
        return Err(ForeignOriginal)
      }
      (
        prepared,
        compilation,
        original.limits,
        original._observed_query_time.map(value => value.0),
      )
    }
    (None, Some(original)) => {
      guard owner.program_captured is Some(selected) &&
        physical_equal(selected, original) &&
        physical_equal(original.request, request) &&
        original.compilation is Some(@publication_host.Tasks(compilation)) else {
        return Err(ForeignOriginal)
      }
      (
        original.prepared,
        compilation,
        original.limits,
        original._observed_query_time,
      )
    }
    _ => return Err(ForeignOriginal)
  }
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(same_input) &&
    physical_equal(same_input, input) &&
    owner.program_capacity is Some(capacity) &&
    owner.compiled_program is Some(prepared) &&
    physical_equal(module_prepared, prepared) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelsCompilation(_, _, _, retained_graphs)) &&
    owner.program_compilation
    is Some(@publication_host.Tasks(retained_compilation)) &&
    physical_equal(compilation, retained_compilation) &&
    installed_mock_model_compilation_matches(prepared, compilation) &&
    @publication_host.client_compiled_run_matches_tasks(
      compiled, prepared, compilation,
    ) &&
    @publication_host.check_client_compiled_run_definition(compiled, definition)
    is Ok(_) &&
    owner.program_model is None &&
    owner.program_domain_quote is None &&
    graphs.length() > 1 &&
    graphs.length() == retained_graphs.length() &&
    graphs.length() == compilation.infers.length() &&
    graphs.length() == occurrences.length() &&
    graphs.length() == model_limits.length() &&
    graphs.length() == read_retained_bytes.length() &&
    graphs.length() == read_execution_bytes.length() &&
    max_reservations >= 0 &&
    max_holdings >= 0 &&
    max_delegations >= 0 else {
    return Err(ForeignOriginal)
  }
  let identity = @publication_host.prepared_client_identity(prepared)
  if identity.program_definition_cid !=
    @publication_host.client_request_program_cid(request) ||
    identity.parameter_values_cid !=
    @publication_host.client_request_parameters_cid(request) {
    return Err(ForeignOriginal)
  }
  if query_time is Some(time) &&
    @publication_host.client_query_time_preparation_context_for_run(
      time, prepared, compiled, definition, request,
    )
    is Err(_) {
    return Err(ForeignOriginal)
  }
  let count = graphs.length()
  guard @execution.preparation_array_representation(1L, count.to_int64(), true)
    is Some(array) &&
    @execution.preparation_representation_cost({
      ..array,
      record_headers: array.record_headers + count.to_int64() + 1L,
      reference_slots: array.reference_slots + count.to_int64() + 1L,
      scalar_words: array.scalar_words + 2L * count.to_int64() + 1L,
    })
    is Some(bytes) else {
    return Err(InsufficientCapacity)
  }
  let (old_r, old_e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(old_r, bytes, 1L)
    is Some(next_r) &&
    @execution.checked_preparation_add_product(old_e, bytes, 1L) is Some(next_e) else {
    return Err(InsufficientCapacity)
  }
  owner.phase = Selecting
  match
    @resources.reserve_working_preparation_phase(
      capacity, input, next_r, next_e,
    ) {
    Err(issue) => {
      if owner.phase == Selecting {
        owner.phase = ProgramBodyFailed
      }
      return Err(Preparation(issue))
    }
    Ok(_) => ()
  }
  guard owner.phase == Selecting &&
    owner.input is Some(current_input) &&
    physical_equal(current_input, input) &&
    owner.program_capacity is Some(current_capacity) &&
    physical_equal(current_capacity, capacity) &&
    (match (source_free, captured) {
      (Some(original), None) =>
        owner.program_source_free is Some(current) &&
        physical_equal(current, original)
      (None, Some(original)) =>
        owner.program_captured is Some(current) &&
        physical_equal(current, original)
      _ => false
    }) &&
    owner.program_model is None else {
    return Err(ForeignOriginal)
  }
  // The resize's current callback may reenter/mutate caller-owned Arrays.
  // Capture and fold the actual checked tuple only AFTER that boundary; the
  // closed native records below never retain those mutable input Arrays.
  owner.phase = ProgramBodyFailed
  guard graphs.length() == count &&
    occurrences.length() == count &&
    model_limits.length() == count &&
    read_retained_bytes.length() == count &&
    read_execution_bytes.length() == count else {
    return Err(ForeignOriginal)
  }
  let mut models : @resources.LedgerLimits = {
    planning_work: 0,
    attempts: 0,
    holdings: 0,
    transfer_bytes: 0L,
    retained_bytes: 0L,
    execution_bytes: 0L,
  }
  let mut r = 0L
  let mut e = 0L
  let mut bindings = 0L
  for index, graph in graphs {
    if !physical_equal(retained_graphs[index], graph) ||
      !physical_equal(compilation.infers[index], graph) ||
      graph.serialization is Some(_) ||
      !@publication_host.client_infer_occurrence_matches_plan(
        occurrences[index],
        graph,
      ) ||
      !@publication_host.client_infer_occurrence_matches_compiled_run(
        occurrences[index],
        compiled,
      ) ||
      read_retained_bytes[index] <= 0L ||
      read_execution_bytes[index] <= 0L {
      return Err(ForeignOriginal)
    }
    guard @resources.add_ledger_limits(models, model_limits[index])
      is Some(next) &&
      @execution.checked_preparation_add_product(
        r,
        read_retained_bytes[index],
        1L,
      )
      is Some(next_r) &&
      @execution.checked_preparation_add_product(
        e,
        read_execution_bytes[index],
        1L,
      )
      is Some(next_e) else {
      return Err(InsufficientCapacity)
    }
    guard @execution.checked_preparation_add_product(
        bindings,
        1L,
        if @publication_host.client_infer_occurrence_terminal(
            occurrences[index],
          ) {
          1L
        } else {
          2L
        },
      )
      is Some(next_bindings) else {
      return Err(InsufficientCapacity)
    }
    bindings = next_bindings
    models = next
    r = next_r
    e = next_e
  }
  // The original module already owns its complete configured Local driver.
  // Reuse the single-Model charge calculation across ALL checked bindings;
  // the raw whole-Run planning ceiling is not construction work per group.
  let configuration = match (source_free, captured) {
    (Some(original), None) => original.configuration.unwrap()
    (None, Some(original)) => original.configuration
    _ => return Err(ForeignOriginal)
  }
  let compute_limits = match
    installed_mock_models_compute_limits(
      configuration, compute_limits, bindings,
    ) {
    None => return Err(InsufficientCapacity)
    Some(value) => value
  }
  // One module demand, every original concurrent child, one bootstrap.
  guard installed_model_demand_limits(models, r, e, bootstrap~) is Some(models) &&
    @resources.add_ledger_limits(compute_limits, models) is Some(limits) else {
    return Err(InsufficientCapacity)
  }
  let partitions : Array[ClientInstalledModelReadPartition] = []
  for index, graph in retained_graphs {
    partitions.push({
      graph,
      retained_bytes: read_retained_bytes[index],
      execution_bytes: read_execution_bytes[index],
    })
  }
  let plan : ClientInstalledManagedModelPlan = {
    prepared,
    request,
    compiled,
    definition,
    graph: retained_graphs[0],
    _occurrence: occurrences[0],
    models: Some(partitions),
    source_free,
    captured,
    content_prefix: None,
    limits,
    max_reservations,
    max_holdings,
    max_delegations,
  }
  owner.program_model = Some(plan)
  owner.phase = ModelPlanReserved
  Ok(plan)
}

///|
fn request_model_plan_quantity_limits(
  plan : ClientInstalledManagedModelPlan,
  installed : @resources.QuantityAmounts,
) -> @resources.QuantityAmounts? {
  request_model_group_quantity_limits(plan.graph, plan.models, installed)
}

///|
fn request_model_group_quantity_limits(
  first_graph : @publication_host.ClientInferPlanGraph,
  models : Array[ClientInstalledModelReadPartition]?,
  installed : @resources.QuantityAmounts,
  graphs? : Array[@publication_host.ClientInferPlanGraph]? = None,
  effect_models? : Array[ClientInstalledEffectModelDemand]? = None,
) -> @resources.QuantityAmounts? {
  if ((models is Some(_) || graphs is Some(_)) && effect_models is Some(_)) ||
    (models is Some(_) && graphs is Some(_)) {
    return None
  }
  let mut tokens = 0L
  let mut cost = 0L
  let mut duration = 0L
  // Borrow the actual compiler group already retained on this Plan. Singles
  // keep exactly their original execution contract and min intersection.
  let mut index = 0
  let count = if effect_models is Some(originals) { originals.length() } else { match graphs {
    Some(originals) => originals.length()
    None =>
      match models {
        None => 1
        Some(models) => models.length()
      }
  }
  }
  while index < count {
    let graph = if effect_models is Some(originals) { originals[index].graph } else { match graphs {
      Some(originals) => originals[index]
      None =>
        match models {
          None => first_graph
          Some(models) => models[index].graph
        }
    }
    }
    let execution = @publication_host.client_infer_plan_graph_execution_contract(
      graph,
    )
    guard @execution.checked_preparation_add_product(
        tokens,
        @environment.model_execution_ceiling(
          execution,
          @environment.TotalTokenReservation,
        ),
        1L,
      )
      is Some(t) &&
      @execution.checked_preparation_add_product(
        cost,
        @environment.model_execution_ceiling(
          execution,
          @environment.TotalCostUnits,
        ),
        1L,
      )
      is Some(c) &&
      @execution.checked_preparation_add_product(
        duration,
        @environment.model_execution_ceiling(
          execution,
          @environment.TotalDurationMs,
        ),
        1L,
      )
      is Some(d) else {
      return None
    }
    tokens = t
    cost = c
    duration = d
    index += 1
  }
  Some({
    tokens: Int64::min(installed.tokens, tokens),
    cost_units: Int64::min(installed.cost_units, cost),
    duration_ms: Int64::min(installed.duration_ms, duration),
  })
}

///|
fn bind_request_multiple_model_read_scopes(
  plan : ClientInstalledManagedModelPlan,
  ledger : @resources.Ledger,
  identity : @resources.OriginalLedgerIdentity,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  @publication_host.ClientModelReadPreparationIssue,
] {
  guard plan.models is Some(models) else {
    return Err(@publication_host.ForeignRun)
  }
  let compilation = match (plan.source_free, plan.captured) {
    (Some(original), None) => original.compilation
    (None, Some(original)) => original.compilation
    _ => None
  }
  guard compilation is Some(@publication_host.Tasks(compilation)) else {
    return Err(@publication_host.ForeignRun)
  }
  let retained : Array[Int64] = []
  let execution : Array[Int64] = []
  for selected in models {
    retained.push(selected.retained_bytes)
    execution.push(selected.execution_bytes)
  }
  @publication_host.bind_client_model_read_scopes(
    plan.compiled,
    plan.definition,
    compilation.infers,
    ledger,
    identity,
    retained,
    execution,
  )
}

///|
pub fn[I] prepare_request_models_read_scopes(
  owner : ClientRequestPreparation[I],
  input : I,
  plan : ClientInstalledManagedModelPlan,
  quantity_limits? : @resources.QuantityAmounts? = None,
) -> Result[
  Array[@publication_host.ClientModelReadScope],
  ClientInstalledManagedRunIssue,
] {
  if plan.models is None {
    return Err(ForeignOriginal)
  }
  prepare_request_model_read_scopes_owned(
    owner, input, plan, quantity_limits, bind_request_multiple_model_read_scopes,
  )
}

///|
/// The existing higher typed bridge projects each original installed Limits
/// into three temporary Arrays. Back exactly those projection containers on
/// this SAME Request before the bridge constructs them. This internal entry
/// is not a Node export, Plan issuer, scalar allowance or Model authority.
pub fn[I] reserve_request_models_plan_projection(
  owner : ClientRequestPreparation[I],
  input : I,
  count : Int,
) -> Result[Unit, ClientInstalledManagedRunIssue] {
  guard owner.phase == ModelPlanReserved &&
    owner.input is Some(original) &&
    physical_equal(original, input) &&
    owner.program_capacity is Some(capacity) &&
    owner.program_domain_compilation_inputs
    is Some(RequestModelsCompilation(_, _, _, graphs)) &&
    count > 1 &&
    count == graphs.length() &&
    owner.program_model is None &&
    @execution.preparation_array_representation(3L, 3L * count.to_int64(), true)
    is Some(arrays) &&
    @execution.preparation_representation_cost(arrays) is Some(bytes) else {
    return Err(ForeignOriginal)
  }
  let (r, e) = match
    @resources.preparation_capacity_working_extents(capacity, input) {
    Err(issue) => return Err(Preparation(issue))
    Ok(value) => value
  }
  guard @execution.checked_preparation_add_product(r, bytes, 1L) is Some(r) &&
    @execution.checked_preparation_add_product(e, bytes, 1L) is Some(e) else {
    return Err(InsufficientCapacity)
  }
  owner.phase = Selecting
  match @resources.reserve_working_preparation_phase(capacity, input, r, e) {
    Err(issue) => {
      if owner.phase == Selecting {
        owner.phase = ProgramBodyFailed
      }
      return Err(Preparation(issue))
    }
    Ok(_) => ()
  }
  guard owner.phase == Selecting &&
    owner.input is Some(current_input) &&
    physical_equal(current_input, input) &&
    owner.program_capacity is Some(current_capacity) &&
    physical_equal(current_capacity, capacity) &&
    owner.program_model is None else {
    return Err(ForeignOriginal)
  }
  owner.phase = ModelPlanReserved
  Ok(())
}
