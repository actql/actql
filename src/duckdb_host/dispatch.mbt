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
  modules : @builtin.ConfiguredComputeModules[DispatchIssue]
  run : @strategy.CapturedDAG
  driver : @host_driver.DispatchDriver
  local_registration : @connector.CapabilityRegistration
  native_registration : @connector.CapabilityRegistration
  runtime : @host_driver.ComputeHost[Unit, DispatchIssue]
  limits : TaskDispatchLimits
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
  let modules = match
    @builtin.configure_compute_modules(
      driver,
      registry,
      2,
      _issue => InvalidConfiguration,
      with_local=Some(
        (
          local_registration,
          {
            sequences: generated,
            execution: limits.local_execution,
            measurement: limits.guards,
            max_work: limits.candidate_work,
          },
          local_dispatch_issue,
          local_estimate_issue,
        ),
      ),
      with_duckdb=Some(
        (
          native_registration,
          {
            sequences: generated,
            limits: {
              capacity: limits.capacity,
              query: limits.native_query,
              join_validation: limits.join_validation,
              candidate_work: limits.candidate_work,
              execution: limits.native,
              transport: limits.transport,
            },
          },
          duckdb_dispatch_issue,
          duckdb_estimate_issue,
        ),
      ),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let contributions = @builtin.configured_compute_contributions(modules)
  let runtime = match
    @host_driver.open_compute_host(
      driver,
      registry,
      contributions,
      limits.capacity,
      limits.input_entries,
      limits.input_name_bytes,
      2,
    ) {
    Ok(value) => value
    Err(issue) => return Err(compute_host_issue(issue))
  }
  Ok({
    modules,
    run,
    driver,
    local_registration,
    native_registration,
    runtime,
    limits,
  })
}

///|
/// Prepare only the next checked-ready task, against its actual completed input.
/// The whole-strategy selection remains authoritative; there is no fallback.
pub fn prepare_next_dispatch(
  host : StrategyHostDispatch,
) -> Result[TaskDispatch?, DispatchIssue] {
  match @host_driver.prepare_next_compute_task(host.runtime, ()) {
    Err(issue) => Err(compute_host_issue(issue))
    Ok(prepared) => Ok(prepared.map(prepared => { owner: host, prepared, }))
  }
}

///|
fn compute_host_issue(
  issue : @host_driver.ComputeHostIssue[DispatchIssue],
) -> DispatchIssue {
  match issue {
    ForeignInstallation => InvalidConfiguration
    Installation(_) => InvalidConfiguration
    Estimate(issue) => adaptive_estimate_issue(issue)
    Dispatch(NoStrategy) => NoStrategy
    Dispatch(Dispatch(issue)) => dispatch_driver_issue(issue)
    Dispatch(MissingImplementation) => ForeignSelection
    Dispatch(Implementation(issue)) => issue
  }
}

///|
pub fn dispatch_excluded_realizations(
  host : StrategyHostDispatch,
  max_work : Int,
) -> Result[Array[(Int, String, String)], @host_driver.ComputeDiagnosticsIssue] {
  @host_driver.compute_host_exclusions(host.runtime, max_work)
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
  @builtin.dispatch_local(
    dispatch.owner.modules,
    @host_driver.compute_host_dispatch(dispatch.owner.runtime),
    dispatch.prepared,
  ).map_err(configured_dispatch_issue)
}

///|
pub fn take_native_dispatch(
  dispatch : TaskDispatch,
) -> Result[@duckdb_driver.StrategyComputeHostConfiguration, DispatchIssue] {
  @builtin.dispatch_duckdb(
    dispatch.owner.modules,
    @host_driver.compute_host_dispatch(dispatch.owner.runtime),
    dispatch.prepared,
  ).map_err(configured_dispatch_issue)
}

///|
fn configured_dispatch_issue(
  issue : @builtin.ConfiguredDispatchIssue[DispatchIssue],
) -> DispatchIssue {
  match issue {
    MissingImplementation => InvalidConfiguration
    Implementation(issue) => issue
  }
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
  dispatch_resource_binding(dispatch) is Some(_)
}

///|
/// The exact selected resource, not a connector name or content identity.
pub fn dispatch_resource_binding(
  dispatch : TaskDispatch,
) -> @connector.ResourceBinding? {
  @strategy.strategy_resident_profile(
    @host_driver.prepared_task_revision(dispatch.prepared),
    @host_driver.prepared_task_index(dispatch.prepared),
  ).map(@strategy.resident_profile_resource_binding)
}

///|
pub fn dispatch_run(host : StrategyHostDispatch) -> @strategy.CapturedDAG {
  host.run
}

///|
/// The actual configured subset, not every implementation present in the build.
pub fn dispatch_module_keys(host : StrategyHostDispatch) -> Array[String] {
  @builtin.configured_compute_module_keys(host.modules)
}

///|
pub fn stop_strategy_dispatch(host : StrategyHostDispatch) -> Unit {
  @host_driver.stop_dispatch_driver(host.driver)
}
