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
  native_registration : @connector.CapabilityRegistration
  implementations : @connector.CapabilityImplementations[
    (
      StrategyHostDispatch,
      Int,
      @strategy.StrategyRevision,
      @connector.FixedComputeRequest,
    ) -> Result[DispatchWork, DispatchIssue],
  ]
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
  ticket : @host_driver.DispatchTicket
  work : DispatchWork
}

///|
priv enum DispatchWork {
  Synchronous(@connector.SynchronousCompute)
  Native(StrategyComputeHostConfiguration)
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
      if limits.capacity.common_fragment is Some(_) {
        Some("unsupported_common_fragment")
      } else {
        match
          @duckdb_compute.check_duckdb_compute_static(
            @execution.generated_sequence_owner(item),
            limits.native_query,
          ) {
          Ok(_) => None
          Err(UnsupportedPredicate) => Some("unsupported_predicate")
          Err(UnsupportedShape) => Some("unsupported_shape")
          Err(UnsupportedField) => Some("unsupported_field")
          Err(Parameter(_)) => Some("unsupported_parameter_type")
          Err(_) => Some("native_compilation_limits_or_contract")
        }
      },
    )
    let owner = @execution.generated_sequence_owner(item)
    let pipeline = @lower.pipeline(@lower.bound_preparation(owner))
    resident_rejections.push(
      match
        @duckdb.check_resident_output_static(
          owner,
          Step(@pipeline.step_count(pipeline) - 1),
        ) {
        Ok(_) => None
        Err(_) => Some("unsupported_resident_output_names")
      },
    )
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
  Ok({
    run,
    driver: @host_driver.open_dispatch_driver(run),
    registry,
    local_registration,
    native_registration,
    implementations,
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
  guard @strategy.next_captured_task(host.run) is Some(task) else {
    return Ok(None)
  }
  match refresh_dispatch_estimates(host) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard @strategy.captured_dag_strategy(host.run) is Some(revision) else {
    return Err(NoStrategy)
  }
  guard @strategy.strategy_registration(revision, task) is Some(registration) else {
    return Err(ForeignSelection)
  }
  let request = match
    @host_driver.prepare_dispatch_inputs(
      host.driver,
      task,
      revision,
      host.limits.capacity,
      host.limits.input_entries,
      host.limits.input_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(dispatch_driver_issue(issue))
  }
  guard @connector.capability_implementation(host.implementations, registration)
    is Some(implementation) else {
    return Err(ForeignSelection)
  }
  let work = match implementation(host, task, revision, request) {
    Ok(work) => work
    Err(issue) => return Err(issue)
  }
  match @host_driver.prepare_dispatch_ticket(host.driver, task, revision) {
    Err(issue) => Err(dispatch_driver_issue(issue))
    Ok(ticket) => Ok(Some({ owner: host, ticket, work, }))
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
fn consume_dispatch(dispatch : TaskDispatch) -> Result[Unit, DispatchIssue] {
  @host_driver.consume_dispatch_ticket(dispatch.owner.driver, dispatch.ticket).map_err(
    dispatch_driver_issue,
  )
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
  guard dispatch.work is Synchronous(compute) else {
    return Err(ForeignSelection)
  }
  match consume_dispatch(dispatch) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  @strategy.execute_captured_synchronous_task(
    dispatch.owner.run,
    @host_driver.dispatch_ticket_task(dispatch.ticket),
    compute,
  ).map_err(issue => Run(issue))
}

///|
pub fn take_native_dispatch(
  dispatch : TaskDispatch,
) -> Result[StrategyComputeHostConfiguration, DispatchIssue] {
  guard dispatch.work is Native(setup) else { return Err(ForeignSelection) }
  match consume_dispatch(dispatch) {
    Err(issue) => Err(issue)
    Ok(_) => Ok(setup)
  }
}

///|
pub fn dispatch_task(dispatch : TaskDispatch) -> Int {
  @host_driver.dispatch_ticket_task(dispatch.ticket)
}

///|
pub fn dispatch_is_native(dispatch : TaskDispatch) -> Bool {
  dispatch.work is Native(_)
}

///|
pub fn dispatch_is_resident(dispatch : TaskDispatch) -> Bool {
  @strategy.strategy_resident_profile(
    @host_driver.dispatch_ticket_revision(dispatch.ticket),
    @host_driver.dispatch_ticket_task(dispatch.ticket),
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
