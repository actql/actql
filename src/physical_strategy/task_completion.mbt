///|
/// The only mutation that makes a task output visible to scheduling and
/// producer binding. Representation-specific verification must finish before
/// this call; no Connector callback runs after the slot is committed.
fn commit_task_output(
  run : CapturedDAG,
  task : Int,
  output : CommittedTaskOutput,
  holding : @resources.Holding?,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard task > 0 &&
    task < run.outputs.length() &&
    !run.done[task] &&
    run.outputs[task] is None &&
    run.resources[task] is None else {
    return Err(ForeignCandidate)
  }
  if holding is Some(value) && !@resources.holding_available(run.ledger, value) {
    return Err(Physical(InvalidCharge))
  }
  run.resources[task] = Some({
    holding,
    release_confirmed: fn() { true },
    parents: task_parents(run, task),
  })
  run.outputs[task] = Some(output)
  run.done[task] = true
  clear_captured_inputs(run, task)
  run.generation += 1
  Ok(())
}

///|
fn validate_materialized_task_output(
  run : CapturedDAG,
  task : Int,
  output : @execution.CompletedOutput,
  holding : @resources.Holding,
  mismatch : RunIssue,
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard captured_task_target(run, task) is Some(target) &&
    @execution.completed_output_matches_port(
      output,
      run.graph.owners[task],
      target,
    ) &&
    captured_output_inputs_match(run, task, output) else {
    return Err(mismatch)
  }
  if !@resources.holding_available(run.ledger, holding) {
    return Err(Physical(InvalidCharge))
  }
  Ok(())
}

///|
/// Commit a verified materialized output without a Connector publication hook.
/// This is the product success boundary for synchronous and materializing work.
fn commit_materialized_task_output(
  run : CapturedDAG,
  task : Int,
  output : @execution.CompletedOutput,
  holding : @resources.Holding,
  mismatch : RunIssue,
) -> Result[Unit, RunIssue] {
  match
    validate_materialized_task_output(run, task, output, holding, mismatch) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  commit_task_output(run, task, Materialized(output), Some(holding))
}

///|
/// New-profile success boundary. It consumes an exact managed completion and
/// the already-admitted retained-body allocation without manufacturing a
/// legacy `CompletedOutput` or calling the legacy finisher. Resident-table
/// publication is deliberately excluded until it has an equivalent managed
/// ownership bridge.
pub fn[T] complete_managed_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
  output : @execution.ManagedCompletedOutput[T],
  allocation? : TaskRetainedAllocation,
  managed_inputs? : Array[@execution.ManagedProducerRead[T]],
) -> Result[Unit, RunIssue] {
  complete_managed_task_execution_with_inputs(
    run,
    execution,
    output,
    allocation?,
    managed_inputs?=managed_inputs.map(inputs => {
      inputs.map(input => @execution.managed_relation_input_binding(input))
    }),
  )
}

///|
/// Complete a Relation output from an exact ordered mixture of managed input
/// Carriers.
pub fn[T] complete_managed_task_execution_with_inputs(
  run : CapturedDAG,
  execution : TaskExecution,
  output : @execution.ManagedCompletedOutput[T],
  allocation? : TaskRetainedAllocation,
  managed_inputs? : Array[@execution.ManagedInputBinding],
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard run.running is Some((task, active)) &&
    physical_equal(active, execution) &&
    task_execution_matches(run, execution) else {
    return Err(ForeignCandidate)
  }
  if execution.disposed ||
    !execution.execution_settled ||
    execution.resident is Some(_) ||
    (!execution.numeric.is_empty() && !execution.numeric_sealed) {
    return Err(Physical(InvalidCharge))
  }
  match task_execution_ready(execution) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard captured_task_target(run, task) is Some(target) &&
    @execution.managed_completed_output_matches_port(
      output,
      run.graph.owners[task],
      target,
    ) &&
    @execution.managed_completed_output_matches_attempt(
      output,
      execution.attempt,
    ) else {
    return Err(ForeignCandidate)
  }
  let input_matches = match managed_inputs {
    Some(inputs) =>
      captured_mixed_managed_inputs_match(run, task, inputs) &&
      @execution.managed_completed_output_matches_common_inputs(output, inputs)
    None => {
      let inputs = []
      for input in run.inputs[task] {
        guard input is Some(input) else { return Err(ForeignCandidate) }
        inputs.push(input)
      }
      @execution.managed_completed_output_matches_inputs(output, inputs)
    }
  }
  if !input_matches {
    return Err(ForeignCandidate)
  }
  guard @execution.managed_completed_output_storage_bytes(output)
    is Some(storage_bytes) else {
    return Err(MissingOutput)
  }
  let holding = if storage_bytes == 0L {
    if allocation is Some(_) {
      return Err(Physical(InvalidCharge))
    }
    None
  } else {
    guard allocation is Some(owned) &&
      owned.live &&
      physical_equal(owned.owner, run) &&
      physical_equal(owned.execution, execution) &&
      owned.bytes == storage_bytes &&
      @resources.holding_available(run.ledger, owned.holding) else {
      return Err(Physical(InvalidCharge))
    }
    Some(owned.holding)
  }
  if run.stopped || !@execution.managed_completed_output_available(output) {
    return Err(if run.stopped { Stopped } else { MissingOutput })
  }
  match
    commit_task_output(
      run,
      task,
      Managed(@execution.managed_completed_reference(output)),
      holding,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if allocation is Some(owned) {
    // Ownership moved to the graph's retained task resource. The old Host
    // token can no longer release it independently.
    owned.live = false
  }
  execution.retained_bytes = None
  @resources.settle_reservation(run.ledger, execution.reservation) |> ignore
  run.running = None
  Ok(())
}

///|
/// Common success boundary for a managed non-Relation Carrier. The typed
/// payload remains owned by its Carrier runtime and Host; this function stores
/// only the exact type-erased completion occurrence and retained allocation.
pub fn complete_carrier_managed_task_execution(
  run : CapturedDAG,
  execution : TaskExecution,
  output : @execution.CarrierManagedCompletedOutput,
  allocation? : TaskRetainedAllocation,
  managed_inputs? : Array[@execution.CarrierManagedProducerRead],
) -> Result[Unit, RunIssue] {
  complete_carrier_managed_task_execution_with_inputs(
    run,
    execution,
    output,
    allocation?,
    managed_inputs?=managed_inputs.map(inputs => {
      inputs.map(input => @execution.managed_carrier_input_binding(input))
    }),
  )
}

///|
/// Complete one Carrier output from an exact ordered mixture of Relation and
/// Carrier producer use sites.
pub fn complete_carrier_managed_task_execution_with_inputs(
  run : CapturedDAG,
  execution : TaskExecution,
  output : @execution.CarrierManagedCompletedOutput,
  allocation? : TaskRetainedAllocation,
  managed_inputs? : Array[@execution.ManagedInputBinding],
) -> Result[Unit, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  guard run.running is Some((task, active)) &&
    physical_equal(active, execution) &&
    task_execution_matches(run, execution) else {
    return Err(ForeignCandidate)
  }
  if execution.disposed ||
    !execution.execution_settled ||
    execution.resident is Some(_) ||
    (!execution.numeric.is_empty() && !execution.numeric_sealed) {
    return Err(Physical(InvalidCharge))
  }
  match task_execution_ready(execution) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard captured_task_target(run, task) is Some(target) &&
    @execution.carrier_managed_completed_output_matches_port(
      output,
      run.graph.owners[task],
      target,
    ) &&
    @execution.carrier_managed_completed_output_matches_attempt(
      output,
      execution.attempt,
    ) else {
    return Err(ForeignCandidate)
  }
  let input_matches = match managed_inputs {
    Some(inputs) =>
      captured_mixed_managed_inputs_match(run, task, inputs) &&
      @execution.carrier_managed_completed_output_matches_managed_inputs(
        output, inputs,
      )
    None => {
      // An omitted input proof is valid only when no internal managed
      // producer edge exists. Acquisition and supplied inputs retain their
      // separate capture evidence and cannot be fabricated here.
      let has_internal = run.graph.data.any(edge => {
        edge.consumer == task && edge.producer > 0
      })
      !has_internal &&
      @execution.carrier_managed_completed_output_matches_inputs(output, [])
    }
  }
  if !input_matches {
    return Err(ForeignCandidate)
  }
  guard @execution.carrier_managed_completed_output_storage_bytes(output)
    is Some(storage_bytes) else {
    return Err(MissingOutput)
  }
  let holding = if storage_bytes == 0L {
    if allocation is Some(_) {
      return Err(Physical(InvalidCharge))
    }
    None
  } else {
    guard allocation is Some(owned) &&
      owned.live &&
      physical_equal(owned.owner, run) &&
      physical_equal(owned.execution, execution) &&
      owned.bytes == storage_bytes &&
      @resources.holding_available(run.ledger, owned.holding) else {
      return Err(Physical(InvalidCharge))
    }
    Some(owned.holding)
  }
  if run.stopped ||
    !@execution.carrier_managed_completed_output_available(output) {
    return Err(if run.stopped { Stopped } else { MissingOutput })
  }
  match
    commit_task_output(
      run,
      task,
      CarrierManaged(@execution.carrier_managed_completed_reference(output)),
      holding,
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if allocation is Some(owned) {
    // Ownership moved to the graph's retained task resource. The old Host
    // token can no longer release it independently.
    owned.live = false
  }
  execution.retained_bytes = None
  @resources.settle_reservation(run.ledger, execution.reservation) |> ignore
  run.running = None
  Ok(())
}
