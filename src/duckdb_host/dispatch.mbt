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
  local_module : @local_connector.LocalComputeModule
  native_registration : @connector.CapabilityRegistration
  local_channel : @host_driver.DispatchChannel[@connector.SynchronousCompute]
  native_channel : @host_driver.DispatchChannel[
    StrategyComputeHostConfiguration,
  ]
  installation : @host_driver.DispatchHost[StrategyHostDispatch, DispatchIssue]
  generated : Array[@execution.GeneratedSequence]
  native_rejections : Array[String?]
  resident_rejections : Array[String?]
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
  let native_rejections : Array[String?] = []
  let resident_rejections : Array[String?] = []
  for index, item in generated {
    if !physical_equal(
        @execution.generated_sequence_owner(item),
        @strategy.graph_task_owner(graph, index + 1).unwrap(),
      ) {
      return Err(InvalidConfiguration)
    }
    // Bounded compilation against exact checked ownership, before any costs.
    match
      @resources.charge_planning(
        @strategy.captured_dag_ledger(run),
        limits.candidate_work,
      ) {
      Err(issue) => return Err(Run(Physical(issue)))
      Ok(_) => ()
    }
    native_rejections.push(
      @duckdb_compute.duckdb_compute_static_rejection(
        @execution.generated_sequence_owner(item),
        limits.capacity,
        limits.native_query,
      ),
    )
    resident_rejections.push(
      @duckdb_compute.duckdb_resident_static_rejection(
        @execution.generated_sequence_owner(item),
      ),
    )
  }
  let local_module = match
    @local_connector.prepare_local_compute_module(
      registry,
      local_registration,
      generated,
      limits.local_execution,
      limits.guards,
      limits.candidate_work,
      @strategy.graph_task_count(graph) - 1,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  let implementations = match
    @connector.install_capability_implementations(
      registry,
      [
        (local_registration, prepare_local_dispatch_work),
        (native_registration, prepare_native_dispatch_work),
      ],
      2,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidConfiguration)
  }
  let driver = @host_driver.open_dispatch_driver(run)
  let local_channel = match
    @host_driver.open_dispatch_channel(driver, registry, local_registration) {
    Ok(value) => value
    Err(issue) => return Err(dispatch_driver_issue(issue))
  }
  let native_channel = match
    @host_driver.open_dispatch_channel(driver, registry, native_registration) {
    Ok(value) => value
    Err(issue) => return Err(dispatch_driver_issue(issue))
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
    local_channel,
    native_channel,
    installation,
    generated: generated.copy(),
    native_rejections,
    resident_rejections,
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
  match @host_driver.prepare_next_installed_task(host.installation, host) {
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
  for index, reason in host.native_rejections {
    if reason is Some(reason) {
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
    for index, reason in host.resident_rejections {
      if reason is Some(reason) {
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
  let compute = match
    @host_driver.take_installed_task(
      dispatch.owner.installation,
      dispatch.prepared,
      dispatch.owner.local_channel,
    ) {
    Err(issue) => return Err(dispatch_driver_issue(issue))
    Ok(value) => value
  }
  @strategy.execute_captured_synchronous_task(
    dispatch.owner.run,
    @host_driver.prepared_task_index(dispatch.prepared),
    compute,
  ).map_err(issue => Run(issue))
}

///|
pub fn take_native_dispatch(
  dispatch : TaskDispatch,
) -> Result[StrategyComputeHostConfiguration, DispatchIssue] {
  @host_driver.take_installed_task(
    dispatch.owner.installation,
    dispatch.prepared,
    dispatch.owner.native_channel,
  ).map_err(dispatch_driver_issue)
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
