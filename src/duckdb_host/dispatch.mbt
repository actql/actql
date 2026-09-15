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
  mut pending : TaskDispatch?
  mut estimates : DispatchEstimates?
  mut resident : ResidentDispatch?
}

///|
struct TaskDispatch {
  owner : StrategyHostDispatch
  task : Int
  revision : @strategy.StrategyRevision
  work : DispatchWork
  mut consumed : Bool
}

///|
priv enum DispatchWork {
  Local(
    @connector.FixedComputeChoice,
    @connector.PreparedCompute[@execution.GeneratedSequence]
  )
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
    registry,
    local_registration,
    native_registration,
    implementations,
    generated: generated.copy(),
    native_rejections,
    resident_rejections,
    limits,
    pending: None,
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
  if host.pending is Some(pending) && !pending.consumed {
    if @strategy.captured_dag_strategy(host.run) is Some(revision) &&
      physical_equal(revision, pending.revision) {
      return Err(PendingTask)
    }
    pending.consumed = true
  }
  host.pending = None
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
  match @resources.charge_planning(@strategy.captured_dag_ledger(host.run), 1) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
  let generated = host.generated[task - 1]
  let owner = @execution.generated_sequence_owner(generated)
  let inputs = []
  let count = @pipeline.input_count(
    @lower.pipeline(@lower.bound_preparation(owner)),
  )
  for port in 0..<count {
    let input = match
      @strategy.captured_task_input(
        host.run,
        task,
        host.limits.input_entries,
        host.limits.input_name_bytes,
        input_index=port,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Run(issue))
    }
    inputs.push(input)
  }
  let request = match
    @connector.prepare_fixed_compute_request(inputs, host.limits.capacity) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  guard @connector.capability_implementation(host.implementations, registration)
    is Some(implementation) else {
    return Err(ForeignSelection)
  }
  let work = match implementation(host, task, revision, request) {
    Ok(work) => work
    Err(issue) => return Err(issue)
  }
  let dispatch = { owner: host, task, revision, work, consumed: false, }
  host.pending = Some(dispatch)
  Ok(Some(dispatch))
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
  let host = dispatch.owner
  if dispatch.consumed ||
    @strategy.next_captured_task(host.run) != Some(dispatch.task) ||
    !(host.pending is Some(expected) && physical_equal(expected, dispatch)) ||
    !(@strategy.captured_dag_strategy(host.run) is Some(revision) &&
    physical_equal(revision, dispatch.revision)) {
    return Err(StaleTask)
  }
  dispatch.consumed = true
  host.pending = None
  Ok(())
}

///|
pub fn execute_local_dispatch(
  dispatch : TaskDispatch,
) -> Result[Unit, DispatchIssue] {
  guard dispatch.work is Local(choice, candidate) else {
    return Err(ForeignSelection)
  }
  match consume_dispatch(dispatch) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let compute = match
    @local_connector.prepare_local_compute_execution(
      choice,
      candidate,
      dispatch.owner.limits.local_execution,
      dispatch.owner.limits.guards,
      join_output_ceiling=@strategy.captured_task_join_output_limit(
        dispatch.owner.run,
        dispatch.task,
      ).map(limit => (0, limit)),
    ) {
    Ok(value) => value
    Err(InvalidLimits) => return Err(Run(Physical(InvalidLimits)))
    Err(issue) => return Err(Run(Compute(issue)))
  }
  @strategy.execute_captured_synchronous_task(
    dispatch.owner.run,
    dispatch.task,
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
  dispatch.task
}

///|
pub fn dispatch_is_native(dispatch : TaskDispatch) -> Bool {
  dispatch.work is Native(_)
}

///|
pub fn dispatch_is_resident(dispatch : TaskDispatch) -> Bool {
  @strategy.strategy_resident_profile(dispatch.revision, dispatch.task)
  is Some(_)
}

///|
pub fn dispatch_run(host : StrategyHostDispatch) -> @strategy.CapturedDAG {
  host.run
}

///|
pub fn stop_strategy_dispatch(host : StrategyHostDispatch) -> Unit {
  host.pending = None
  @strategy.stop_captured_dag(host.run)
}
