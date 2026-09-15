///|
/// One exact run/task execution. Physical lifecycle belongs to the common
/// driver; the installed implementation owns its private transport state.
/// Construction is private: callers cannot attach arbitrary completion hooks.
struct TaskExecution {
  task : Int
  reservation : @resources.Reservation
  retention : Int64
  scratch : Int64
  mut hooks : @connector.ExecutionOperations[RunIssue, TaskPublication]?
  mut execution_settled : Bool
  mut disposed : Bool
  mut failed_holding : @resources.Holding?
}

///|
/// Registered asynchronous execution without a shared-copy admission. A
/// selected shared-resource realization must use its exact resource admission;
/// it cannot evade that requirement through this task-local entry.
pub fn[T] start_captured_execution(
  run : CapturedDAG,
  task : Int,
  prepared : @connector.PreparedExecution[T, RunIssue, TaskPublication],
) -> Result[(T, TaskExecution), RunIssue] {
  if run.strategy.bind(revision => strategy_resident_profile(revision, task))
    is Some(_) {
    return Err(ForeignCandidate)
  }
  start_task_execution(run, task, prepared, 0L)
}

///|
/// Synchronous preparation only: the installed implementation may construct
/// owned transport state here, but must not start I/O. An error therefore has
/// confirmed absence of external work and releases the untouched reservation.
/// Actual execution starts only after the returned handle is registered.
fn[T] start_task_execution(
  run : CapturedDAG,
  task : Int,
  prepared : @connector.PreparedExecution[T, RunIssue, TaskPublication],
  shared_execution : Int64,
) -> Result[(T, TaskExecution), RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  let candidate = @connector.prepared_execution_candidate(prepared)
  if !strategy_candidate_matches(run, task, candidate) ||
    !captured_request_inputs_match(
      run,
      task,
      @connector.fixed_compute_candidate_request(candidate),
    ) {
    return Err(ForeignCandidate)
  }
  if !@connector.prepared_execution_available(prepared) {
    return Err(Compute(NotSelected))
  }
  if captured_task_join_output_limit(run, task) is Some(required) {
    guard @connector.prepared_execution_join_output_ceiling(prepared)
      is Some((0, actual)) &&
      actual <= required else {
      return Err(ForeignCandidate)
    }
  }
  let capacity = @connector.prepared_execution_capacity(prepared)
  let transfer = capacity.transfer_bytes
  let retention = capacity.retained_bytes
  let scratch = capacity.scratch_bytes
  let execution_capacity = capacity.execution_bytes
  if transfer < 0L ||
    retention < 0L ||
    scratch < 0L ||
    execution_capacity < 0L ||
    scratch > execution_capacity ||
    shared_execution < 0L ||
    execution_capacity > 9223372036854775807L - shared_execution {
    return Err(Physical(InvalidLimits))
  }
  if strategy_task_envelope(run, task) is Some(capacity) &&
    (
      transfer > capacity.transfer_bytes ||
      retention > capacity.retained_bytes ||
      execution_capacity + shared_execution > capacity.execution_bytes
    ) {
    return Err(Physical(InvalidCharge))
  }
  // Shared resources already have their own reservation. They still contribute
  // to the selected task envelope, but are not reserved a second time here.
  let reservation = match
    @resources.reserve_attempt(
      run.ledger,
      transfer,
      retention,
      execution_capacity,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match @connector.start_prepared_execution(prepared) {
    Err(issue) => {
      @resources.settle_reservation(run.ledger, reservation) |> ignore
      let failure = match issue {
        Candidate(issue) => RunIssue::Compute(issue)
        Implementation(issue) => issue
      }
      fail_captured_task(run, task, failure)
      Err(failure)
    }
    Ok((payload, hooks)) => {
      let execution : TaskExecution = {
        task,
        reservation,
        retention,
        scratch,
        hooks: Some(hooks),
        execution_settled: false,
        disposed: false,
        failed_holding: None,
      }
      run.executions[task] = Some(execution)
      run.running = Some((task, execution))
      Ok((payload, execution))
    }
  }
}

///|
fn task_execution_matches(run : CapturedDAG, execution : TaskExecution) -> Bool {
  run.executions.get(execution.task).bind(x => x) is Some(owned) &&
  physical_equal(owned, execution)
}

///|
pub fn charge_task_execution_transfer(
  run : CapturedDAG,
  execution : TaskExecution,
  bytes : Int64,
) -> Result[Unit, @resources.LedgerIssue] {
  if !task_execution_matches(run, execution) {
    return Err(ForeignOwner)
  }
  if execution.disposed || execution.execution_settled {
    return Err(ClosedReservation)
  }
  @resources.charge_transfer(run.ledger, execution.reservation, bytes)
}

///|
/// Acknowledgement is supplied by the installed trusted transport, not by
/// ordinary selection. False retains cleanup responsibility and all capacity.
pub fn settle_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
  confirmed : Bool,
) -> Result[Unit, @resources.LedgerIssue] {
  if !task_execution_matches(run, execution) {
    return Err(ForeignOwner)
  }
  if execution.execution_settled {
    return Ok(())
  }
  if !confirmed {
    return @resources.mark_cleanup_pending(run.ledger, execution.reservation)
  }
  let result = if execution.disposed {
    @resources.settle_reservation(run.ledger, execution.reservation)
  } else {
    @resources.settle_execution_reservation(
      run.ledger,
      execution.reservation,
      remaining_execution=execution.scratch,
    )
  }
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      execution.execution_settled = true
      (execution.hooks.unwrap().settled)()
      if execution.disposed {
        release_task_execution(run, execution)
      }
      Ok(())
    }
  }
}

///|
/// Verification, result holding and successful DAG completion are one boundary.
/// No success is exposed if the implementation cannot supply its owned output.
pub fn complete_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard run.running is Some((task, active)) &&
    physical_equal(active, execution) &&
    task_execution_matches(run, execution) else {
    return Err(ForeignCandidate)
  }
  if execution.disposed || !execution.execution_settled {
    return Err(Physical(InvalidCharge))
  }
  let hooks = execution.hooks.unwrap()
  match (hooks.ready)() {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let holding = match
    @resources.retain_allocation(
      run.ledger,
      execution.reservation,
      execution.retention,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  match (hooks.finish)() {
    Ok(output) => {
      match
        publish_task_completion(
          run,
          task,
          output,
          holding,
          ForeignCandidate,
          hooks.publish,
        ) {
        Err(issue) => {
          execution.failed_holding = Some(holding)
          fail_captured_task(run, task, issue)
          return Err(issue)
        }
        Ok(_) => ()
      }
      @resources.settle_reservation(run.ledger, execution.reservation) |> ignore
      run.running = None
      Ok(())
    }
    Err(issue) => {
      execution.failed_holding = Some(holding)
      fail_captured_task(run, task, issue)
      Err(issue)
    }
  }
}

///|
pub fn close_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Unit {
  if !task_execution_matches(run, execution) || execution.disposed {
    return
  }
  if run.running is Some((_, active)) && physical_equal(active, execution) {
    stop_captured_dag(run)
  }
  execution.disposed = true
  (execution.hooks.unwrap().dispose)()
  close_captured_task_output(run, execution.task)
  if execution.execution_settled {
    release_task_execution(run, execution)
  }
}

///|
/// Private finalization only after disposal AND actual execution settlement.
/// Completed descendant holdings and already consumed transfer stay intact.
fn release_task_execution(run : CapturedDAG, execution : TaskExecution) -> Unit {
  if !execution.disposed ||
    !execution.execution_settled ||
    !task_execution_matches(run, execution) {
    return
  }
  if execution.failed_holding is Some(holding) {
    @resources.release_allocation(run.ledger, holding) |> ignore
    execution.failed_holding = None
  }
  if @resources.reservation_open(execution.reservation) {
    @resources.settle_reservation(run.ledger, execution.reservation) |> ignore
  }
  captured_cleanup_confirmed(run, execution)
  run.executions[execution.task] = None
  let hooks = execution.hooks.unwrap()
  execution.hooks = None
  (hooks.released)()
}
