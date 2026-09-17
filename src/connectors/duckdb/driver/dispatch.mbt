///|
/// Concrete connector installation, not common Host or source configuration.
pub(all) struct DuckDBDispatchLimits {
  capacity : @connector.FixedComputeCapacity
  query : @duckdb.NativeQueryLimits
  join_validation : @execution.FixedJoinValidationLimits
  candidate_work : Int
  execution : @compute.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
}

///|
struct DuckDBDispatchModule {
  run : @strategy.CapturedDAG
  registry : @connector.CapabilityRegistry
  registration : @connector.CapabilityRegistration
  sequences : Array[@execution.CompletionPreparation]
  limits : DuckDBDispatchLimits
  rejections : Array[(String?, String?)]
  channel : @host.DispatchChannel[StrategyComputeHostConfiguration]
  resident_estimates : Array[DuckDBResidentEstimates]
  mut estimate_configuration : DuckDBEstimateConfiguration?
  mut retained_output : (Int64, Int64?)?
  mut output_policy_sealed : Bool
}

///|
pub(all) enum DuckDBDispatchIssue {
  InvalidConfiguration
  ForeignSelection
  Run(@strategy.RunIssue)
  Candidate(@connector.FixedComputeIssue)
  NativeCandidate(@compute.DuckDBComputeCandidateIssue)
  JoinPreparation(@duckdb.FixedJoinInputIssue)
  Dispatch(@host.DispatchIssue)
}

///|
/// Bounded static compilation happens before offers. It consumes the existing
/// Host planning allowance, but creates no DB, reads no source and starts no task.
pub fn prepare_duckdb_dispatch_module(
  driver : @host.DispatchDriver,
  registry : @connector.CapabilityRegistry,
  registration : @connector.CapabilityRegistration,
  sequences : Array[@execution.CompletionPreparation],
  limits : DuckDBDispatchLimits,
) -> Result[DuckDBDispatchModule, DuckDBDispatchIssue] {
  let run = @host.dispatch_driver_run(driver)
  let graph = @strategy.captured_dag_graph(run)
  if sequences.length() != @strategy.graph_task_count(graph) - 1 ||
    limits.candidate_work < 1 ||
    limits.join_validation.max_rows < 0 ||
    limits.join_validation.max_work < 0 ||
    limits.join_validation.max_entries < 0 ||
    !@connector.capability_registration_matches(registration, registry) ||
    !@connector.capability_description(registration).fixed_compute {
    return Err(InvalidConfiguration)
  }
  let rejections = []
  for index, sequence in sequences {
    if !(@strategy.graph_task_owner(graph, index + 1) is Some(owner) &&
      physical_equal(owner, @execution.completion_preparation_owner(sequence))) {
      return Err(InvalidConfiguration)
    }
    match
      @resources.charge_planning(
        @strategy.captured_dag_ledger(run),
        limits.candidate_work,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Run(Physical(issue)))
    }
    rejections.push(
      (
        @compute.duckdb_compute_static_rejection(
          @execution.completion_preparation_owner(sequence),
          limits.capacity,
          limits.query,
        ),
        @compute.duckdb_resident_static_rejection(
          @execution.completion_preparation_owner(sequence),
        ),
      ),
    )
  }
  let channel = match
    @host.open_dispatch_channel(driver, registry, registration) {
    Ok(value) => value
    Err(issue) => return Err(Dispatch(issue))
  }
  Ok({
    run,
    registry,
    registration,
    sequences: sequences.copy(),
    limits,
    rejections,
    channel,
    resident_estimates: [],
    estimate_configuration: None,
    retained_output: None,
    output_policy_sealed: false,
  })
}

///|
/// Diagnostics for this exact installation. Runtime owner/liveness/capacity
/// binding remains mandatory even when static rejection is absent.
pub fn duckdb_dispatch_rejection(
  installed : DuckDBDispatchModule,
  task : Int,
  resident? : Bool = false,
) -> String? {
  let graph = @strategy.captured_dag_graph(installed.run)
  guard @strategy.graph_task_operation_count(graph, task) is Some(count) else {
    return Some("invalid_task")
  }
  for index in 0..<count {
    let requirement = @strategy.graph_task_operation_at(graph, task, index).unwrap()
    if requirement.disposition is ExecutionCheck(check) {
      match check {
        GroupExecution(_)
        | JoinOutputLimit(_)
        | JoinRowOrder(_)
        | JoinInputValidation(_)
        | JoinIdentity(_) => ()
        _ => return Some("unsupported_execution_obligation")
      }
    }
  }
  guard installed.rejections.get(task - 1) is Some(reasons) else {
    return Some("invalid_task")
  }
  if resident {
    reasons.1
  } else {
    reasons.0
  }
}

///|
pub fn prepare_duckdb_dispatch(
  installed : DuckDBDispatchModule,
  task : Int,
  revision : @strategy.StrategyRevision,
  request : @connector.FixedComputeRequest,
) -> Result[@host.DispatchWork, DuckDBDispatchIssue] {
  guard installed.sequences.get(task - 1) is Some(sequence) else {
    return Err(ForeignSelection)
  }
  if !physical_equal(
      @connector.fixed_compute_request_owner(request),
      @execution.completion_preparation_owner(sequence),
    ) ||
    !(@strategy.captured_dag_strategy(installed.run) is Some(current) &&
    physical_equal(current, revision)) ||
    !(@strategy.strategy_registration(revision, task) is Some(selected) &&
    physical_equal(selected, installed.registration)) ||
    !@connector.capability_registration_available(installed.registration) {
    return Err(ForeignSelection)
  }
  if duckdb_dispatch_rejection(installed, task) is Some(_) ||
    (
      @strategy.strategy_resident_profile(revision, task) is Some(_) &&
      duckdb_dispatch_rejection(installed, task, resident=true) is Some(_)
    ) {
    return Err(ForeignSelection)
  }
  let preparation = match
    @compute.prepare_duckdb_dispatch_candidate(
      installed.registry,
      installed.registration,
      request,
      installed.limits.query,
      installed.limits.join_validation,
      @strategy.captured_task_join_output_limit(installed.run, task, 0),
      installed.limits.candidate_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NativeCandidate(issue))
  }
  if @compute.duckdb_dispatch_preflight_work(preparation) is Some(work) {
    match
      @resources.charge_planning(
        @strategy.captured_dag_ledger(installed.run),
        work,
      ) {
      Ok(_) => ()
      Err(issue) => return Err(Run(Physical(issue)))
    }
  }
  let selected = match @compute.bind_duckdb_dispatch_candidate(preparation) {
    Ok(value) => value
    Err(Native(JoinPreparation(issue))) => {
      @strategy.stop_captured_dag(installed.run)
      return Err(JoinPreparation(issue))
    }
    Err(Native(issue)) => return Err(NativeCandidate(issue))
    Err(Selection(issue)) => return Err(Candidate(issue))
    Err(NotSelected) => return Err(ForeignSelection)
  }
  @host.stage_dispatch_work(
    installed.channel,
    task,
    revision,
    request,
    configure_strategy_compute_host(
      installed.run,
      task,
      configure_compute_host(
        @compute.duckdb_selected_compute_choice(selected),
        @compute.duckdb_selected_compute_candidate(selected),
        sequence,
        installed.limits.execution,
        installed.limits.transport,
      ),
      output_file_bytes=installed.retained_output
        .map(policy => policy.0)
        .unwrap_or(0L),
    ),
  ).map_err(issue => Dispatch(issue))
}

///|
pub fn[C, E] take_duckdb_dispatch(
  installed : DuckDBDispatchModule,
  host : @host.DispatchHost[C, E],
  task : @host.PreparedTaskDispatch,
) -> Result[StrategyComputeHostConfiguration, DuckDBDispatchIssue] {
  @host.take_installed_task(host, task, installed.channel).map_err(issue => {
    Dispatch(issue)
  })
}

///|
/// Prepare the next unary managed task inside the installed DuckDB module.
/// The standard dispatcher supplies only the exact predecessor completion;
/// this function constructs the receiving request, compiles the registered
/// candidate, compares it and fixes the common completion configuration.
pub fn prepare_duckdb_managed_dispatch(
  installed : DuckDBDispatchModule,
  outputs : Array[@execution.ManagedCompletedOutput[Int]],
  obligations : @execution.ManagedObligations,
  output_file_bytes : Int64,
) -> Result[ManagedStrategyComputeHostConfiguration[Int], DuckDBDispatchIssue] {
  guard @strategy.next_captured_task(installed.run) is Some(task) &&
    installed.sequences.get(task - 1) is Some(sequence) &&
    @strategy.captured_dag_strategy(installed.run) is Some(revision) &&
    @strategy.strategy_registration(revision, task) is Some(selected) &&
    physical_equal(selected, installed.registration) &&
    @connector.capability_registration_available(installed.registration) else {
    return Err(ForeignSelection)
  }
  let inputs = []
  for index, output in outputs {
    match
      @strategy.captured_managed_task_input(
        installed.run,
        task,
        output,
        // Binding a checked schema is connector metadata work. Native-query
        // entries and SQL bytes bound compilation, not producer-name matching.
        installed.limits.execution.metadata_work,
        installed.limits.execution.completion_name_bytes,
        input_index=index,
      ) {
      Ok(value) => inputs.push(value)
      Err(issue) => return Err(Run(issue))
    }
  }
  let request = match
    @connector.prepare_managed_fixed_compute_request(
      inputs,
      installed.limits.capacity,
      obligations,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let prepared = match
    @compute.duckdb_managed_fixed_compute_candidate(
      installed.registration,
      request,
      "managed_input",
      installed.limits.query,
      [{ work_slots: [0, 1, 2, 3, 4, 5, 6, 7], milliseconds: Some(1L), }],
      { transfer_bytes: None, retained_bytes: None, money_units: None, },
      installed.limits.candidate_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NativeCandidate(issue))
  }
  let choice = match
    @connector.choose_managed_fixed_compute_candidate(
      installed.registry,
      request,
      [@connector.prepared_managed_compute_candidate(prepared)],
      None,
      installed.limits.candidate_work,
    ) {
    Ok(Proposed(value)) => value
    Ok(_) => return Err(ForeignSelection)
    Err(issue) => return Err(Candidate(issue))
  }
  guard @connector.managed_fixed_compute_choice_payload(choice, prepared)
    is Some(query) else {
    return Err(ForeignSelection)
  }
  let rows = @duckdb.managed_fixed_query_output_row_ceiling(
    query,
    installed.limits.capacity.max_rows,
  )
  let width = @duckdb.managed_fixed_query_output_column_count(query)
  if rows < 0 || width < 0 || (width > 0 && rows > 2147483647 / width) {
    return Err(InvalidConfiguration)
  }
  let max_index_cells = rows * width
  let join_output_ceilings = []
  guard @strategy.captured_task_join_output_count(installed.run, task)
    is Some(join_count) else {
    return Err(InvalidConfiguration)
  }
  for index in 0..<join_count {
    guard @strategy.captured_task_join_output_at(installed.run, task, index)
      is Some(ceiling) else {
      return Err(InvalidConfiguration)
    }
    join_output_ceilings.push(ceiling)
  }
  configure_managed_strategy_compute_host(
    installed.run,
    task,
    choice,
    prepared,
    sequence,
    @execution.selected_managed_execution_profile(),
    installed.limits.execution,
    installed.limits.transport,
    output_file_bytes,
    max_index_cells,
    join_output_ceilings,
  ).map_err(issue => Run(issue))
}
