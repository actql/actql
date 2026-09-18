///|
/// One exact run/task execution. Physical lifecycle belongs to the common
/// driver; the installed implementation owns its private transport state.
/// Construction is private: callers cannot attach arbitrary completion hooks.
struct TaskExecution {
  owner : StrategyOfferOwner
  task : Int
  reservation : @resources.Reservation
  mut retained_bytes : (() -> Result[Int64, RunIssue])?
  scratch : Int64
  mut hooks : TaskExecutionHooks?
  mut execution_settled : Bool
  mut disposed : Bool
  mut failed_holding : @resources.Holding?
  mut resident : ResidentExecution?
  attempt : @execution.ManagedExecutionAttempt
}

///|
/// Common physical lifecycle with explicitly distinct publication families.
/// A managed execution cannot be coerced into the legacy output finisher.
priv enum TaskExecutionHooks {
  Legacy(@connector.ExecutionOperations[RunIssue, TaskPublication])
  Managed(@connector.ManagedExecutionOperations[RunIssue])
}

///|
fn task_execution_cancel(execution : TaskExecution) -> Unit {
  match execution.hooks.unwrap() {
    Legacy(hooks) => (hooks.cancel)()
    Managed(hooks) => (hooks.cancel)()
  }
}

///|
fn task_execution_settled(execution : TaskExecution) -> Unit {
  match execution.hooks.unwrap() {
    Legacy(hooks) => (hooks.settled)()
    Managed(hooks) => (hooks.settled)()
  }
}

///|
fn task_execution_ready(execution : TaskExecution) -> Result[Unit, RunIssue] {
  match execution.hooks.unwrap() {
    Legacy(hooks) => (hooks.ready)()
    Managed(hooks) => (hooks.ready)()
  }
}

///|
fn task_execution_dispose(execution : TaskExecution) -> Unit {
  match execution.hooks.unwrap() {
    Legacy(hooks) => (hooks.dispose)()
    Managed(hooks) => (hooks.dispose)()
  }
}

///|
fn task_execution_retention_released(execution : TaskExecution) -> Bool {
  match execution.hooks.unwrap() {
    Legacy(hooks) => (hooks.retention_released)()
    Managed(hooks) => (hooks.retention_released)()
  }
}

///|
fn task_execution_released(hooks : TaskExecutionHooks) -> Unit {
  match hooks {
    Legacy(hooks) => (hooks.released)()
    Managed(hooks) => (hooks.released)()
  }
}

///|
/// One auxiliary retained allocation charged to an already admitted task.
/// This is not another attempt and does not create completion authority. The
/// trusted Host that owns the concrete allocation must release this token when
/// that allocation is no longer reachable by any admitted consumer.
struct TaskRetainedAllocation {
  owner : CapturedDAG
  execution : TaskExecution
  holding : @resources.Holding
  bytes : Int64
  mut live : Bool
}

///|
/// Registered asynchronous execution. A selected shared-resource realization
/// must supply its exact resource admission; omitting it cannot evade the
/// selected reuse contract.
pub fn[T] start_captured_execution(
  run : CapturedDAG,
  task : Int,
  prepared : @connector.PreparedExecution[T, RunIssue, TaskPublication],
  resident? : ResidentExecution,
) -> Result[(T, TaskExecution), RunIssue] {
  start_task_execution(run, task, prepared, resident)
}

///|
/// Register one selected managed-profile execution without manufacturing a
/// legacy request or completion finisher. Store pin/use admission remains the
/// installed Host's responsibility inside its prepared lifecycle.
pub fn[I, T] start_captured_managed_execution(
  run : CapturedDAG,
  task : Int,
  prepared : @connector.PreparedManagedExecution[I, T, RunIssue],
) -> Result[(T, TaskExecution), RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  let candidate = @connector.prepared_managed_execution_candidate(prepared)
  let request = @connector.managed_fixed_compute_candidate_request(candidate)
  if !strategy_managed_candidate_matches(run, task, candidate) ||
    !captured_managed_request_inputs_match(run, task, request) {
    return Err(ForeignCandidate)
  }
  if !@connector.prepared_managed_execution_available(prepared) {
    return Err(Compute(NotSelected))
  }
  for (step, claim) in run.join_limits[task] {
    let required = @derivation.minimum_value(@witness.limit_minimum(claim))
    guard @connector.prepared_managed_execution_join_output_ceiling(
        prepared, step,
      )
      is Some(actual) &&
      actual <= required else {
      return Err(ForeignCandidate)
    }
  }
  if !aggregate_output_limits_satisfied(run.aggregate_limits[task], (
      step,
      name,
      unit,
    ) => {
      @connector.prepared_managed_execution_aggregate_output_ceiling(
        prepared, step, name, unit,
      )
    }) {
    return Err(ForeignCandidate)
  }
  let capacity = @connector.prepared_managed_execution_capacity(prepared)
  let transfer = capacity.transfer_bytes
  let retention = capacity.retained_bytes
  let scratch = capacity.scratch_bytes
  let execution_capacity = capacity.execution_bytes
  if transfer < 0L ||
    retention < 0L ||
    scratch < 0L ||
    execution_capacity < scratch {
    return Err(Physical(InvalidLimits))
  }
  if strategy_task_envelope(run, task) is Some(selected) &&
    (
      transfer > selected.transfer_bytes ||
      retention > selected.retained_bytes ||
      execution_capacity > selected.execution_bytes
    ) {
    return Err(Physical(InvalidCharge))
  }
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
  match @connector.start_prepared_managed_execution(prepared) {
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
        owner: run.offer_owner,
        task,
        reservation,
        retained_bytes: Some(fn() {
          match @connector.prepared_managed_execution_retained_bytes(prepared) {
            Ok(bytes) => Ok(bytes)
            Err(Candidate(issue)) => Err(Compute(issue))
            Err(Implementation(issue)) => Err(issue)
          }
        }),
        scratch,
        hooks: Some(Managed(hooks)),
        execution_settled: false,
        disposed: false,
        failed_holding: None,
        resident: None,
        attempt: @execution.issue_managed_execution_attempt(),
      }
      run.executions[task] = Some(execution)
      run.running = Some((task, execution))
      Ok((payload, execution))
    }
  }
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
  resident : ResidentExecution?,
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
  for (step, claim) in run.join_limits[task] {
    let required = @derivation.minimum_value(@witness.limit_minimum(claim))
    guard @connector.prepared_execution_join_output_ceiling(prepared, step)
      is Some(actual) &&
      actual <= required else {
      return Err(ForeignCandidate)
    }
  }
  if !aggregate_output_limits_satisfied(run.aggregate_limits[task], (
      step,
      name,
      unit,
    ) => {
      @connector.prepared_execution_aggregate_output_ceiling(
        prepared, step, name, unit,
      )
    }) {
    return Err(ForeignCandidate)
  }
  let capacity = @connector.prepared_execution_capacity(prepared)
  let transfer = capacity.transfer_bytes
  let retention = capacity.retained_bytes
  let scratch = capacity.scratch_bytes
  let execution_capacity = capacity.execution_bytes
  let shared_execution = match
    resident_execution_capacity(run, task, candidate, capacity, resident) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
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
  if resident is Some(resource) {
    match activate_resident_execution(run, resource) {
      Ok(_) => ()
      Err(issue) => {
        @resources.settle_reservation(run.ledger, reservation) |> ignore
        return Err(issue)
      }
    }
  }
  match @connector.start_prepared_execution(prepared) {
    Err(issue) => {
      if resident is Some(resource) {
        abandon_resident_execution(resource)
      }
      @resources.settle_reservation(run.ledger, reservation) |> ignore
      let failure = match issue {
        Candidate(issue) => RunIssue::Compute(issue)
        Implementation(issue) => issue
      }
      fail_captured_task(run, task, failure)
      Err(failure)
    }
    Ok((payload, hooks)) => {
      if resident is Some(resource) {
        resource.inputs.claimed = true
      }
      let execution : TaskExecution = {
        owner: run.offer_owner,
        task,
        reservation,
        retained_bytes: Some(fn() {
          match @connector.prepared_execution_retained_bytes(prepared) {
            Ok(bytes) => Ok(bytes)
            Err(Candidate(issue)) => Err(Compute(issue))
            Err(Implementation(issue)) => Err(issue)
          }
        }),
        scratch,
        hooks: Some(Legacy(hooks)),
        execution_settled: false,
        disposed: false,
        failed_holding: None,
        resident,
        attempt: @execution.issue_managed_execution_attempt(),
      }
      run.executions[task] = Some(execution)
      run.running = Some((task, execution))
      Ok((payload, execution))
    }
  }
}

///|
/// Return the opaque attempt only to an owner holding the exact registered
/// execution. Preparations and connector registrations cannot derive it.
pub fn task_execution_managed_attempt(
  run : CapturedDAG,
  execution : TaskExecution,
) -> @execution.ManagedExecutionAttempt? {
  if task_execution_matches(run, execution) {
    Some(execution.attempt)
  } else {
    None
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
/// Convert part of this task's existing retention reservation into one exact
/// auxiliary physical allocation. This is used for bounded retained metadata
/// that is distinct from the task's primary output allocation. Capacity must
/// have been present in the selected task envelope before execution started.
pub fn retain_task_execution_allocation(
  run : CapturedDAG,
  execution : TaskExecution,
  bytes : Int64,
) -> Result[TaskRetainedAllocation, @resources.LedgerIssue] {
  if !task_execution_matches(run, execution) {
    return Err(ForeignOwner)
  }
  if execution.disposed || !@resources.reservation_open(execution.reservation) {
    return Err(ClosedReservation)
  }
  match @resources.retain_allocation(run.ledger, execution.reservation, bytes) {
    Err(issue) => Err(issue)
    Ok(holding) => Ok({ owner: run, execution, holding, bytes, live: true, })
  }
}

///|
/// Idempotently release the exact auxiliary allocation. Releasing it does not
/// close the task, settle native execution, or revoke any other allocation.
/// The token remains releasable after task cleanup so a late Host cleanup
/// acknowledgement cannot strand ledger capacity.
pub fn release_task_execution_allocation(
  allocation : TaskRetainedAllocation,
) -> Result[Bool, @resources.LedgerIssue] {
  if !allocation.live {
    return Ok(false)
  }
  match
    @resources.release_allocation(allocation.owner.ledger, allocation.holding) {
    Err(issue) => Err(issue)
    Ok(_) => {
      allocation.live = false
      Ok(true)
    }
  }
}

///|
pub fn task_execution_allocation_available(
  allocation : TaskRetainedAllocation,
) -> Bool {
  allocation.live &&
  @resources.holding_available(allocation.owner.ledger, allocation.holding)
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
  // Actual execution stop releases native capacity. An independently owned
  // file/provisional output can still require retention after disposal.
  let result = @resources.settle_execution_reservation(
    run.ledger,
    execution.reservation,
    remaining_execution=if execution.disposed { 0L } else { execution.scratch },
  )
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      execution.execution_settled = true
      if execution.resident is Some(resource) {
        return_resident_inputs(resource.inputs) |> ignore
      }
      task_execution_settled(execution)
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
  guard execution.hooks.unwrap() is Legacy(hooks) else {
    return Err(ForeignCandidate)
  }
  if execution.resident is Some(resource) {
    guard resource.pending is Some(pending) &&
      pending.committed &&
      resident_environment_available(run, pending.environment) else {
      return Err(NotReady)
    }
  }
  match task_execution_ready(execution) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let retained_bytes = match execution.retained_bytes.unwrap()() {
    Ok(bytes) => bytes
    Err(issue) => return Err(issue)
  }
  let holding = match
    @resources.retain_allocation(
      run.ledger,
      execution.reservation,
      retained_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  execution.retained_bytes = None
  match (hooks.finish)() {
    Ok(output) => {
      match
        publish_task_completion(run, task, output, holding, ForeignCandidate, fn(
          publication,
        ) {
          if execution.resident is Some(resource) &&
            resource.pending is Some(pending) {
            match publish_resident_output(run, task, pending, publication) {
              Err(issue) => return Err(issue)
              Ok(_) => ()
            }
          }
          (hooks.publish)(publication)
        }) {
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
  execution.retained_bytes = None
  task_execution_dispose(execution)
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
  if !task_execution_retention_released(execution) {
    // Dispose has synchronously freed MoonBit scratch; external retained
    // storage has its own acknowledgement and must keep its reservation.
    if @resources.reservation_open(execution.reservation) {
      @resources.settle_execution_reservation(
        run.ledger,
        execution.reservation,
        remaining_execution=0L,
      )
      |> ignore
    }
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
  execution.resident = None
  task_execution_released(hooks)
  collect_captured_retention(run)
}

///|
/// Poll installed cleanup facts after disposal, without treating this call as
/// evidence of native stop or file deletion. The exact task remains tracked
/// until both confirmations have arrived; no consumed transfer is refunded.
pub fn refresh_task_execution_cleanup(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Result[Bool, @resources.LedgerIssue] {
  if physical_equal(execution.owner, run.offer_owner) &&
    execution.disposed &&
    execution.hooks is None {
    return Ok(true)
  }
  if !task_execution_matches(run, execution) {
    return Err(ForeignOwner)
  }
  if !execution.disposed {
    return Err(InvalidCharge)
  }
  release_task_execution(run, execution)
  Ok(!task_execution_matches(run, execution))
}
