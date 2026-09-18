///|
priv struct PublicationScope {
  mut active : Bool
  mut claimed : Bool
}

///|
/// Constructed only after common port/input/holding verification. A connector
/// publication hook cannot exchange the output or keep publication authority
/// after returning. No public constructor or output getter is provided.
struct TaskPublication {
  owner : StrategyOfferOwner
  task : Int
  holding : @resources.Holding
  scope : PublicationScope
  mut output : @execution.CompletedOutput?
}

///|
fn claim_publication_scope(scope : PublicationScope) -> Bool {
  if !scope.active || scope.claimed {
    return false
  }
  scope.claimed = true
  true
}

///|
fn close_publication_scope(scope : PublicationScope) -> Unit {
  scope.active = false
}

///|
fn claim_task_publication(
  run : CapturedDAG,
  task : Int,
  publication : TaskPublication,
) -> @execution.CompletedOutput? {
  if run.stopped ||
    !physical_equal(run.offer_owner, publication.owner) ||
    task != publication.task ||
    !@resources.holding_available(run.ledger, publication.holding) ||
    !claim_publication_scope(publication.scope) {
    return None
  }
  publication.output
}

///|
/// The common success boundary for synchronous and asynchronous realizations.
/// This stays private: the caller must already own a verified execution and its
/// allocation. Connector-specific publication runs only after exact output-port
/// and input-binding checks, and cannot expose a DAG success without retention.
fn publish_task_completion(
  run : CapturedDAG,
  task : Int,
  output : @execution.CompletedOutput,
  holding : @resources.Holding,
  mismatch : RunIssue,
  publish : (TaskPublication) -> Result[Unit, RunIssue],
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
  let publication = {
    owner: run.offer_owner,
    task,
    holding,
    scope: { active: true, claimed: false, },
    output: Some(output),
  }
  let published = publish(publication)
  close_publication_scope(publication.scope)
  publication.output = None
  match published {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if run.stopped {
    return Err(Stopped)
  }
  if !@resources.holding_available(run.ledger, holding) {
    return Err(Physical(InvalidCharge))
  }
  // No connector callback or fallible operation splits retention attachment
  // from success. Completed descendants do not borrow upstream availability.
  run.resources[task] = Some({
    holding: Some(holding),
    release_confirmed: fn() { true },
    parents: task_parents(run, task),
  })
  run.completed[task] = Some(output)
  run.done[task] = true
  clear_captured_inputs(run, task)
  run.generation += 1
  Ok(())
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
      captured_managed_inputs_match(run, task, inputs) &&
      @execution.managed_completed_output_matches_managed_inputs(output, inputs)
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
  if allocation is Some(owned) {
    // Ownership moves to the graph's retained task resource. The old Host
    // token can no longer release it independently.
    owned.live = false
  }
  execution.retained_bytes = None
  run.resources[task] = Some({
    holding,
    release_confirmed: fn() { true },
    parents: task_parents(run, task),
  })
  run.completed[task] = None
  run.managed_completed[task] = Some(
    @execution.managed_completed_reference(output),
  )
  run.done[task] = true
  clear_captured_inputs(run, task)
  run.generation += 1
  @resources.settle_reservation(run.ledger, execution.reservation) |> ignore
  run.running = None
  Ok(())
}
