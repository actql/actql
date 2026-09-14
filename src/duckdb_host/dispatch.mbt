///|
/// Bounded application configuration; no source connection, SQL callback or
/// completion injection. Generated sequences retain their exact checked owners.
pub(all) struct TaskDispatchLimits {
  input_entries : Int
  input_name_bytes : Int
  candidate_work : Int
  capacity : @planning.FixedComputeCapacity
  local_execution : @execution.SequenceExecutionLimits
  guards : @execution.FixedInputGuardMeasureLimits
  native_query : @duckdb.NativeQueryLimits
  native : @planning.DuckDBComputeLimits
  transport : @duckdb.TransportColumnLimits
}

///|
struct StrategyHostDispatch {
  run : @strategy.CapturedDAG
  registry : @planning.CapabilityRegistry
  local_registration : @planning.CapabilityRegistration
  native_registration : @planning.CapabilityRegistration
  generated : Array[@execution.GeneratedSequence]
  limits : TaskDispatchLimits
  mut pending : TaskDispatch?
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
    @planning.FixedComputeChoice,
    @planning.PreparedCompute[@execution.GeneratedSequence]
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
  Candidate(@planning.FixedComputeIssue)
}

///|
pub fn configure_strategy_dispatch(
  run : @strategy.CapturedDAG,
  registry : @planning.CapabilityRegistry,
  local_registration : @planning.CapabilityRegistration,
  native_registration : @planning.CapabilityRegistration,
  generated : Array[@execution.GeneratedSequence],
  limits : TaskDispatchLimits,
) -> Result[StrategyHostDispatch, DispatchIssue] {
  let graph = @strategy.captured_dag_graph(run)
  if generated.length() != @strategy.graph_task_count(graph) - 1 ||
    limits.input_entries < 0 ||
    limits.input_name_bytes < 0 ||
    limits.candidate_work < 1 ||
    !@planning.capability_registration_matches(local_registration, registry) ||
    !@planning.capability_registration_matches(native_registration, registry) ||
    physical_equal(local_registration, native_registration) {
    return Err(InvalidConfiguration)
  }
  for index, item in generated {
    if !physical_equal(
        @execution.generated_sequence_owner(item),
        @strategy.graph_task_owner(graph, index + 1).unwrap(),
      ) {
      return Err(InvalidConfiguration)
    }
  }
  Ok({
    run,
    registry,
    local_registration,
    native_registration,
    generated: generated.copy(),
    limits,
    pending: None,
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
  guard @strategy.captured_dag_strategy(host.run) is Some(revision) else {
    return Err(NoStrategy)
  }
  guard @strategy.strategy_registration(revision, task) is Some(registration) else {
    return Err(ForeignSelection)
  }
  match @strategy.charge_planning(@strategy.captured_dag_ledger(host.run), 1) {
    Err(issue) => return Err(Run(Physical(issue)))
    Ok(_) => ()
  }
  let input = match
    @strategy.captured_task_input(
      host.run,
      task,
      host.limits.input_entries,
      host.limits.input_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Run(issue))
  }
  let request = match
    @planning.prepare_fixed_compute_request(input, host.limits.capacity) {
    Ok(value) => value
    Err(issue) => return Err(Candidate(issue))
  }
  let generated = host.generated[task - 1]
  let quantities : @planning.QueryQuantities = {
    transfer_bytes: None,
    retained_bytes: None,
    money_units: None,
  }
  let work = if physical_equal(registration, host.local_registration) {
    let candidate = match
      @planning.local_fixed_compute_candidate(
        registration,
        request,
        generated,
        [],
        quantities,
        host.limits.candidate_work,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Candidate(issue))
    }
    let choice = match
      @planning.choose_fixed_compute_candidate(
        host.registry,
        request,
        [@planning.prepared_compute_candidate(candidate)],
        Some([0]),
        host.limits.candidate_work,
      ) {
      Ok(Proposed(choice)) => choice
      Ok(_) => return Err(ForeignSelection)
      Err(issue) => return Err(Candidate(issue))
    }
    DispatchWork::Local(choice, candidate)
  } else if physical_equal(registration, host.native_registration) {
    let candidate = match
      @planning.duckdb_fixed_compute_candidate(
        registration,
        request,
        "owned_input",
        host.limits.native_query,
        [],
        quantities,
        host.limits.candidate_work,
      ) {
      Ok(value) => value
      Err(issue) => return Err(Candidate(issue))
    }
    let choice = match
      @planning.choose_fixed_compute_candidate(
        host.registry,
        request,
        [@planning.prepared_compute_candidate(candidate)],
        Some([0]),
        host.limits.candidate_work,
      ) {
      Ok(Proposed(choice)) => choice
      Ok(_) => return Err(ForeignSelection)
      Err(issue) => return Err(Candidate(issue))
    }
    DispatchWork::Native(
      configure_strategy_compute_host(
        host.run,
        task,
        configure_compute_host(
          choice,
          candidate,
          generated,
          host.limits.native,
          host.limits.transport,
        ),
      ),
    )
  } else {
    return Err(ForeignSelection)
  }
  let dispatch = { owner: host, task, revision, work, consumed: false, }
  host.pending = Some(dispatch)
  Ok(Some(dispatch))
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
  @strategy.execute_captured_local_task(
    dispatch.owner.run,
    dispatch.task,
    choice,
    candidate,
    dispatch.owner.limits.local_execution,
    dispatch.owner.limits.guards,
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
pub fn dispatch_run(host : StrategyHostDispatch) -> @strategy.CapturedDAG {
  host.run
}

///|
pub fn stop_strategy_dispatch(host : StrategyHostDispatch) -> Unit {
  host.pending = None
  @strategy.stop_captured_dag(host.run)
}
