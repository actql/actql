///|
/// One exact run/task execution. Physical lifecycle belongs to the common
/// driver; the installed implementation owns its private transport state.
/// Construction is private: callers cannot attach arbitrary completion hooks.
struct TaskExecution {
  owner : StrategyOfferOwner
  task : Int
  registration_key : String
  reservation : @resources.Reservation
  mut retained_bytes : (() -> Result[Int64, RunIssue])?
  scratch : Int64
  mut hooks : @connector.ExecutionLifecycleOperations[RunIssue]?
  mut execution_settled : Bool
  mut disposed : Bool
  mut failed_holding : @resources.Holding?
  mut resident : ResidentExecution?
  attempt : @execution.ManagedExecutionAttempt
  numeric : Array[TaskNumericReduction]
  numeric_captures : Array[TaskNumericCapture]
  numeric_pending : Array[TaskNumericExecution]
  numeric_occurrence_counts : Array[Int?]
  mut numeric_sealed : Bool
}

///|
/// One selected static numeric slot. The checked slot owns the profile and
/// operation; the chosen candidate supplies exactly one pinned member.
priv struct TaskNumericReduction {
  observation : TaskNumericObservation
  reduction : @numeric.Reduction
}

///|
/// One exact dynamic occurrence captured before managed completion. The value
/// is the outcome returned by the selected common reduction, not a connector
/// supplied summary.
priv struct TaskNumericCapture {
  selected : Int
  occurrence : Int
  outcome : @numeric.Outcome
}

///|
fn numeric_reduction_slot_open(counts : Array[Int?], index : Int) -> Bool {
  counts.get(index).map(value => value is None).unwrap_or(false)
}

///|
fn select_declared_numeric_member(
  profile : @numeric.Profile,
  declarations : Array[@connector.NumericReductionSupport],
) -> @numeric.Reduction? {
  let profile_cid = @numeric.cid(profile)
  let mut selected_member = None
  for support in declarations {
    if @connector.numeric_reduction_support_profile_cid(support) == profile_cid {
      if selected_member is Some(_) {
        return None
      }
      selected_member = Some(
        @connector.numeric_reduction_support_member_cid(support),
      )
    }
  }
  selected_member.bind(member_cid => {
    match @numeric.select(profile, member_cid) {
      Ok(reduction) => Some(reduction)
      Err(_) => None
    }
  })
}

///|
fn[I] select_task_numeric_reductions(
  run : CapturedDAG,
  task : Int,
  candidate : @connector.ManagedFixedComputeCandidate[I],
) -> Array[TaskNumericReduction]? {
  guard run.graph.numeric.get(task) is Some(observations) else { return None }
  let declarations = []
  let declaration_count = @connector.managed_fixed_compute_candidate_numeric_reduction_count(
    candidate,
  )
  for index in 0..<declaration_count {
    declarations.push(
      @connector.managed_fixed_compute_candidate_numeric_reduction_at(
        candidate, index,
      ).unwrap(),
    )
  }
  let selected = []
  for observation in observations {
    let profile = observation.profile
    guard select_declared_numeric_member(profile, declarations)
      is Some(reduction) else {
      return None
    }
    selected.push({ observation, reduction, })
  }
  Some(selected)
}

///|
fn task_execution_cancel(execution : TaskExecution) -> Unit {
  (execution.hooks.unwrap().cancel)()
}

///|
fn task_execution_settled(execution : TaskExecution) -> Unit {
  (execution.hooks.unwrap().settled)()
}

///|
fn task_execution_ready(execution : TaskExecution) -> Result[Unit, RunIssue] {
  (execution.hooks.unwrap().ready)()
}

///|
fn task_execution_dispose(execution : TaskExecution) -> Unit {
  (execution.hooks.unwrap().dispose)()
}

///|
fn task_execution_retention_released(execution : TaskExecution) -> Bool {
  (execution.hooks.unwrap().retention_released)()
}

///|
fn task_execution_released(
  hooks : @connector.ExecutionLifecycleOperations[RunIssue],
) -> Unit {
  (hooks.released)()
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
/// Registered materializing execution. A selected shared-resource realization
/// must supply its exact resource admission; omitting it cannot evade the
/// selected reuse contract. The owning driver supplies the admitted output at
/// the common completion boundary.
pub fn[T] start_captured_materializing_execution(
  run : CapturedDAG,
  task : Int,
  prepared : @connector.PreparedExecution[T, RunIssue],
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
  if !consume_task_activation(run, task) {
    return Err(ActivationNotAuthorized)
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
  guard select_task_numeric_reductions(run, task, candidate) is Some(numeric) else {
    return Err(ForeignCandidate)
  }
  for (step, required) in run.join_limits[task] {
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
  if !analytic_envelopes_satisfied(run.analytic_envelopes[task], step => {
      @connector.prepared_managed_execution_analytic_envelope(prepared, step)
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
        registration_key: @connector.capability_registration_selection_key(
          @connector.managed_fixed_compute_candidate_registration(candidate),
        ),
        reservation,
        retained_bytes: Some(fn() {
          match @connector.prepared_managed_execution_retained_bytes(prepared) {
            Ok(bytes) => Ok(bytes)
            Err(Candidate(issue)) => Err(Compute(issue))
            Err(Implementation(issue)) => Err(issue)
          }
        }),
        scratch,
        hooks: Some(@connector.managed_execution_lifecycle(hooks)),
        execution_settled: false,
        disposed: false,
        failed_holding: None,
        resident: None,
        attempt: @execution.issue_managed_execution_attempt(),
        numeric,
        numeric_captures: [],
        numeric_pending: [],
        numeric_occurrence_counts: Array::make(numeric.length(), None),
        numeric_sealed: false,
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
  prepared : @connector.PreparedExecution[T, RunIssue],
  resident : ResidentExecution?,
) -> Result[(T, TaskExecution), RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  if next_captured_task(run) != Some(task) {
    return Err(NotReady)
  }
  if !consume_task_activation(run, task) {
    return Err(ActivationNotAuthorized)
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
  for (step, required) in run.join_limits[task] {
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
  if !analytic_envelopes_satisfied(run.analytic_envelopes[task], step => {
      @connector.prepared_execution_analytic_envelope(prepared, step)
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
  match @connector.start_prepared_execution_lifecycle(prepared) {
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
        registration_key: @connector.capability_registration_selection_key(
          @connector.fixed_compute_candidate_registration(candidate),
        ),
        reservation,
        retained_bytes: Some(fn() {
          match @connector.prepared_execution_retained_bytes(prepared) {
            Ok(bytes) => Ok(bytes)
            Err(Candidate(issue)) => Err(Compute(issue))
            Err(Implementation(issue)) => Err(issue)
          }
        }),
        scratch,
        hooks: Some(hooks),
        execution_settled: false,
        disposed: false,
        failed_holding: None,
        resident,
        attempt: @execution.issue_managed_execution_attempt(),
        numeric: [],
        numeric_captures: [],
        numeric_pending: [],
        numeric_occurrence_counts: [],
        numeric_sealed: true,
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
/// Stable selected registration identity for trusted Host wiring. This is not
/// an implementation capability or permission to dispatch another attempt.
pub fn task_execution_registration_key(
  run : CapturedDAG,
  execution : TaskExecution,
) -> String? {
  if task_execution_matches(run, execution) {
    Some(execution.registration_key)
  } else {
    None
  }
}

///|
/// Count the exact static numeric slots selected for this managed attempt.
/// Foreign or already-replaced execution handles expose no selection.
pub fn task_execution_numeric_reduction_count(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Int? {
  if task_execution_matches(run, execution) {
    Some(execution.numeric.length())
  } else {
    None
  }
}

///|
/// Execute and retain one dynamic occurrence through the attempt-owned common
/// boundary. A connector cannot replace a member, duplicate an occurrence, or
/// add observations after sealing the successful evaluation.
pub fn execute_task_numeric_reduction_for_slot(
  run : CapturedDAG,
  execution : TaskExecution,
  step : Int,
  name : String,
  occurrence : Int,
  contributors : Array[Double],
  expected_count : Int,
  max_work : Int,
) -> Result[@numeric.Outcome, @numeric.ReductionIssue]? {
  let pending = match
    start_task_numeric_reduction_for_slot(
      run, execution, step, name, occurrence, contributors, expected_count, max_work,
    ) {
    None => return None
    Some(Err(issue)) => return Some(Err(issue))
    Some(Ok(pending)) => pending
  }
  while true {
    match advance_task_numeric_reduction(run, pending) {
      None => {
        close_task_numeric_reduction(run, pending) |> ignore
        return None
      }
      Some(Err(issue)) => return Some(Err(issue))
      Some(Ok(None)) => ()
      Some(Ok(Some(outcome))) => return Some(Ok(outcome))
    }
  } nobreak {
    close_task_numeric_reduction(run, pending) |> ignore
    None
  }
}

///|
/// Seal one exact operation-owned slot after its evaluator has emitted the
/// complete occurrence domain. Expected cardinality never comes from captured
/// outcomes, so a missing occurrence remains observable.
pub fn seal_task_numeric_reduction_slot(
  run : CapturedDAG,
  execution : TaskExecution,
  step : Int,
  name : String,
  occurrence_count : Int,
) -> Bool {
  if !task_execution_matches(run, execution) ||
    execution.disposed ||
    execution.numeric_sealed ||
    occurrence_count < 0 {
    return false
  }
  let mut selected_index = None
  for index, selected in execution.numeric {
    if selected.observation.step == step && selected.observation.name == name {
      if selected_index is Some(_) {
        return false
      }
      selected_index = Some(index)
    }
  }
  guard selected_index is Some(selected) &&
    execution.numeric_occurrence_counts[selected] is None else {
    return false
  }
  if execution.numeric_pending.any(pending => pending.selected == selected) {
    return false
  }
  let mut count = 0
  for capture in execution.numeric_captures {
    if capture.selected == selected {
      if capture.occurrence < 0 || capture.occurrence >= occurrence_count {
        return false
      }
      count += 1
    }
  }
  if count != occurrence_count {
    return false
  }
  execution.numeric_occurrence_counts[selected] = Some(occurrence_count)
  true
}

///|
/// Seal the exact attempt only after every operation-owned slot has already
/// closed. Completion refuses an execution with an unresolved slot.
pub fn seal_task_numeric_reductions(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Bool {
  if !task_execution_matches(run, execution) ||
    execution.disposed ||
    execution.numeric_sealed ||
    !execution.numeric_pending.is_empty() ||
    execution.numeric_occurrence_counts.any(value => value is None) {
    return false
  }
  execution.numeric_sealed = true
  true
}

///|
pub fn task_execution_numeric_capture_count(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Int? {
  if task_execution_matches(run, execution) {
    Some(execution.numeric_captures.length())
  } else {
    None
  }
}

///|
pub fn task_execution_numeric_capture_work(
  run : CapturedDAG,
  execution : TaskExecution,
  index : Int,
) -> Int? {
  if !task_execution_matches(run, execution) {
    return None
  }
  execution.numeric_captures
  .get(index)
  .map(capture => @numeric.outcome_work(capture.outcome))
}

///|
pub fn task_execution_numeric_reduction_slot_cid(
  run : CapturedDAG,
  execution : TaskExecution,
  index : Int,
) -> String? {
  if !task_execution_matches(run, execution) {
    return None
  }
  execution.numeric.get(index).map(selected => selected.observation.slot_cid)
}

///|
pub fn task_execution_numeric_reduction_member_cid(
  run : CapturedDAG,
  execution : TaskExecution,
  index : Int,
) -> String? {
  if !task_execution_matches(run, execution) {
    return None
  }
  execution.numeric
  .get(index)
  .map(selected => @numeric.reduction_cid(selected.reduction))
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
fn complete_materialized_execution(
  run : CapturedDAG,
  execution : TaskExecution,
  finish : () -> Result[@execution.CompletedOutput, RunIssue],
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
  match finish() {
    Ok(output) => {
      let completed = match
        validate_materialized_task_output(
          run,
          task,
          output,
          holding,
          ForeignCandidate,
        ) {
        Err(issue) => Err(issue)
        Ok(_) => {
          let binding = match execution.resident {
            Some(resource) =>
              match resource.pending {
                Some(pending) =>
                  bind_resident_output(run, task, pending, output)
                None => Ok(())
              }
            None => Ok(())
          }
          match binding {
            Err(issue) => Err(issue)
            Ok(_) =>
              commit_materialized_task_output(
                run,
                task,
                output,
                holding,
                ForeignCandidate,
              )
          }
        }
      }
      match completed {
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
/// Complete a materializing execution from its exact admitted output. This is
/// the migration target for in-memory implementations: the implementation no
/// longer owns a separate finish or publication success path.
pub fn complete_materializing_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
  output : @execution.CompletedOutput,
) -> Result[Unit, RunIssue] {
  complete_materialized_execution(run, execution, fn() { Ok(output) })
}

///|
/// Complete a materializing execution whose physical verifier can establish
/// the output only after the common holding has been admitted. The callback
/// has no publication authority and is not retained by the execution.
pub fn complete_deferred_materializing_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
  materialize : () -> Result[@execution.CompletedOutput, RunIssue],
) -> Result[Unit, RunIssue] {
  complete_materialized_execution(run, execution, materialize)
}

///|
/// Record the running attempt's computation failure as the task's primary
/// failure. A foreign or no longer running execution records nothing.
pub fn fail_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
  issue : RunIssue,
) -> Bool {
  guard run.running is Some((task, active)) &&
    physical_equal(active, execution) &&
    task_execution_matches(run, execution) else {
    return false
  }
  fail_captured_task(run, task, issue)
  true
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
  for pending in execution.numeric_pending {
    @numeric.close_reduction(pending.state)
    pending.closed = true
  }
  execution.numeric_pending.clear()
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
