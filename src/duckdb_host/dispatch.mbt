///|
/// Bounded application configuration; no source connection, SQL callback or
/// completion injection. Generated sequences retain their exact checked owners.
pub(all) struct TaskDispatchLimits {
  input_entries : Int
  input_name_bytes : Int
  candidate_work : Int
  capacity : @connector.FixedComputeCapacity
  local_execution : @execution.SequenceExecutionLimits
  guards : @execution.FixedInputGuardMeasureLimits
  native_query : @duckdb.NativeQueryLimits
  join_validation : @execution.FixedJoinValidationLimits
  native : @duckdb_compute.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
}

///|
struct StrategyHostDispatch {
  run : @strategy.CapturedDAG
  driver : @host_driver.DispatchDriver
  registry : @connector.CapabilityRegistry
  local_registration : @connector.CapabilityRegistration
  local_module : @local_driver.LocalDispatchModule
  native_registration : @connector.CapabilityRegistration
  native_module : @duckdb_driver.DuckDBDispatchModule
  installation : @host_driver.DispatchHost[Unit, DispatchIssue]
  limits : TaskDispatchLimits
  mut estimates : DispatchEstimates?
  mut resident : ResidentDispatch?
}

///|
struct TaskDispatch {
  owner : StrategyHostDispatch
  prepared : @host_driver.PreparedTaskDispatch
}

///|
pub(all) enum DispatchIssue {
  InvalidConfiguration
  NoStrategy
  ForeignSelection
  PendingTask
  StaleTask
  Run(@strategy.RunIssue)
  Candidate(@connector.FixedComputeIssue)
  NativeCandidate(@duckdb_compute.DuckDBComputeCandidateIssue)
  Search(@strategy.SearchIssue)
  EstimateOverflow
  JoinPreparation(@duckdb.FixedJoinInputIssue)
}

///|
pub fn configure_strategy_dispatch(
  run : @strategy.CapturedDAG,
  registry : @connector.CapabilityRegistry,
  local_registration : @connector.CapabilityRegistration,
  native_registration : @connector.CapabilityRegistration,
  generated : Array[@execution.GeneratedSequence],
  limits : TaskDispatchLimits,
) -> Result[StrategyHostDispatch, DispatchIssue] {
  let graph = @strategy.captured_dag_graph(run)
  if generated.length() != @strategy.graph_task_count(graph) - 1 ||
    limits.input_entries < 0 ||
    limits.input_name_bytes < 0 ||
    limits.candidate_work < 1 ||
    limits.join_validation.max_rows < 0 ||
    limits.join_validation.max_work < 0 ||
    limits.join_validation.max_entries < 0 ||
    !@connector.capability_registration_matches(local_registration, registry) ||
    !@connector.capability_registration_matches(native_registration, registry) ||
    physical_equal(local_registration, native_registration) {
    return Err(InvalidConfiguration)
  }
  let driver = @host_driver.open_dispatch_driver(run)
  let native_module = match
    @duckdb_driver.prepare_duckdb_dispatch_module(
      driver,
      registry,
      native_registration,
      generated,
      {
        capacity: limits.capacity,
        query: limits.native_query,
        join_validation: limits.join_validation,
        candidate_work: limits.candidate_work,
        execution: limits.native,
        transport: limits.transport,
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(duckdb_dispatch_issue(issue))
  }
  let local_module = match
    @local_driver.prepare_local_dispatch_module(
      driver,
      registry,
      local_registration,
      generated,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  let implementations = match
    @connector.install_capability_implementations(
      registry,
      [
        (
          local_registration,
          fn(_context : Unit, task, revision, request) {
            @local_driver.prepare_local_dispatch(
              local_module, task, revision, request,
            ).map_err(local_dispatch_issue)
          },
        ),
        (
          native_registration,
          fn(_context : Unit, task, revision, request) {
            @duckdb_driver.prepare_duckdb_dispatch(
              native_module, task, revision, request,
            ).map_err(duckdb_dispatch_issue)
          },
        ),
      ],
      2,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  let installation = match
    @host_driver.open_dispatch_host(
      driver,
      implementations,
      limits.capacity,
      limits.input_entries,
      limits.input_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(dispatch_driver_issue(issue))
  }
  Ok({
    run,
    driver,
    registry,
    local_registration,
    local_module,
    native_registration,
    native_module,
    installation,
    limits,
    estimates: None,
    resident: None,
  })
}

///|
/// Prepare only the next checked-ready task, against its actual completed input.
/// The whole-strategy selection remains authoritative; there is no fallback.
pub fn prepare_next_dispatch(
  host : StrategyHostDispatch,
) -> Result[TaskDispatch?, DispatchIssue] {
  match @host_driver.check_dispatch_idle(host.driver) {
    Err(issue) => return Err(dispatch_driver_issue(issue))
    Ok(_) => ()
  }
  guard @strategy.next_captured_task(host.run) is Some(_) else {
    return Ok(None)
  }
  match refresh_dispatch_estimates(host) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match @host_driver.prepare_next_installed_task(host.installation, ()) {
    Err(NoStrategy) => Err(NoStrategy)
    Err(Dispatch(issue)) => Err(dispatch_driver_issue(issue))
    Err(MissingImplementation) => Err(ForeignSelection)
    Err(Implementation(issue)) => Err(issue)
    Ok(prepared) => Ok(prepared.map(prepared => { owner: host, prepared, }))
  }
}

///|
pub fn dispatch_excluded_realizations(
  host : StrategyHostDispatch,
) -> Array[(Int, String, String)] {
  let excluded = []
  for
    index in 0..<(@strategy.graph_task_count(
      @strategy.captured_dag_graph(host.run),
    ) -
    1) {
    if @duckdb_driver.duckdb_dispatch_rejection(host.native_module, index + 1)
      is Some(reason) {
      excluded.push(
        (
          index + 1,
          @connector.capability_description(host.native_registration).name,
          reason,
        ),
      )
    }
  }
  if host.resident is Some(_) {
    for
      index in 0..<(@strategy.graph_task_count(
        @strategy.captured_dag_graph(host.run),
      ) -
      1) {
      if @duckdb_driver.duckdb_dispatch_rejection(
          host.native_module,
          index + 1,
          resident=true,
        )
        is Some(reason) {
        excluded.push((index + 1, "duckdb-resident", reason))
      }
    }
  }
  excluded
}

///|
fn dispatch_driver_issue(issue : @host_driver.DispatchIssue) -> DispatchIssue {
  match issue {
    PendingTask => PendingTask
    StaleTask => StaleTask
    Run(issue) => Run(issue)
    Candidate(issue) => Candidate(issue)
  }
}

///|
pub fn execute_synchronous_dispatch(
  dispatch : TaskDispatch,
) -> Result[Unit, DispatchIssue] {
  @local_driver.execute_local_dispatch(
    dispatch.owner.local_module,
    dispatch.owner.installation,
    dispatch.prepared,
  ).map_err(local_dispatch_issue)
}

///|
pub fn take_native_dispatch(
  dispatch : TaskDispatch,
) -> Result[@duckdb_driver.StrategyComputeHostConfiguration, DispatchIssue] {
  @duckdb_driver.take_duckdb_dispatch(
    dispatch.owner.native_module,
    dispatch.owner.installation,
    dispatch.prepared,
  ).map_err(duckdb_dispatch_issue)
}

///|
pub fn dispatch_task(dispatch : TaskDispatch) -> Int {
  @host_driver.prepared_task_index(dispatch.prepared)
}

///|
/// Exact selected registration for transport dispatch, not a backend category.
pub fn dispatch_registration(
  dispatch : TaskDispatch,
) -> @connector.CapabilityRegistration? {
  Some(@host_driver.prepared_task_registration(dispatch.prepared))
}

///|
pub fn dispatch_local_registration(
  host : StrategyHostDispatch,
) -> @connector.CapabilityRegistration {
  host.local_registration
}

///|
pub fn dispatch_duckdb_registration(
  host : StrategyHostDispatch,
) -> @connector.CapabilityRegistration {
  host.native_registration
}

///|
pub fn dispatch_is_resident(dispatch : TaskDispatch) -> Bool {
  @strategy.strategy_resident_profile(
    @host_driver.prepared_task_revision(dispatch.prepared),
    @host_driver.prepared_task_index(dispatch.prepared),
  )
  is Some(_)
}

///|
pub fn dispatch_run(host : StrategyHostDispatch) -> @strategy.CapturedDAG {
  host.run
}

///|
pub fn stop_strategy_dispatch(host : StrategyHostDispatch) -> Unit {
  @host_driver.stop_dispatch_driver(host.driver)
}
