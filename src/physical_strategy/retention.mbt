///|
priv struct TaskLifetime {
  mut live : Bool
}

///|
priv struct TaskRetention {
  mut holding : Holding?
  parent : Int?
}

///|
fn task_parent(run : CapturedDAG, task : Int) -> Int? {
  for edge in run.graph.data {
    if edge.consumer == task && edge.producer != 0 {
      return Some(edge.producer)
    }
  }
  None
}

///|
fn record_task_retention(run : CapturedDAG, task : Int) -> Unit {
  run.done[task] = true
  run.resources[task] = Some({ holding: None, parent: task_parent(run, task), })
}

///|
/// Trusted Host accounting: associate its exact allocation token only after this
/// task has established success. Sharing is by owned token, never equal CIDs.
pub fn retain_captured_task_allocation(
  run : CapturedDAG,
  task : Int,
  holding : Holding,
) -> Result[Unit, LedgerIssue] {
  if !physical_equal(holding.owner, run.ledger) {
    return Err(ForeignOwner)
  }
  guard holding.live &&
    run.resources.get(task).bind(x => x) is Some(resource) &&
    resource.holding is None &&
    run.lifetimes[task].live else {
    return Err(InvalidCharge)
  }
  for existing in run.resources {
    if existing is Some(existing) &&
      existing.holding is Some(value) &&
      physical_equal(value, holding) {
      return Err(InvalidCharge)
    }
  }
  resource.holding = Some(holding)
  Ok(())
}

///|
/// Release the Host's result port. Already completed descendants keep their own
/// results and the backing allocations they retain; new readers are revoked.
/// Exporting a result outside this run requires the Host to keep its port open
/// for that external use. This is not a GC/foreign-handle discovery mechanism.
pub fn close_captured_task_output(run : CapturedDAG, task : Int) -> Unit {
  if task <= 0 || task >= run.completed.length() {
    return
  }
  if !run.done[task] {
    return
  }
  run.lifetimes[task].live = false
  run.completed[task] = None
  // A cached binding is not a started consumer. Drop our revoked aliases;
  // an in-flight native attempt keeps its input until cleanup is confirmed.
  for edge in run.graph.data {
    if edge.producer == task &&
      !run.done[edge.consumer] &&
      !(run.running is Some((active, _)) && active == edge.consumer) {
      run.inputs[edge.consumer] = None
    }
  }
  collect_captured_retention(run)
}

///|
fn collect_captured_retention(run : CapturedDAG) -> Unit {
  // Backward edges ensure one descending pass releases newly unreferenced
  // ancestors. This traversal is bounded by the checked graph's task limit.
  for task = run.resources.length() - 1; task > 0; task = task - 1 {
    guard !run.lifetimes[task].live && run.resources[task] is Some(resource) else {
      continue
    }
    let mut needed = false
    for child in run.resources {
      if child is Some(child) && child.parent == Some(task) {
        needed = true
      }
    }
    if run.running is Some((active, _)) &&
      task_parent(run, active) == Some(task) {
      needed = true
    }
    if !needed {
      if resource.holding is Some(holding) {
        release_allocation(run.ledger, holding) |> ignore
      }
      run.resources[task] = None
    }
  }
}

///|
/// Invoke only after the original Host confirms stopped/cleaned native work.
pub fn captured_cleanup_confirmed(
  run : CapturedDAG,
  attempt : @planning.DuckDBComputeAttempt,
) -> Unit {
  if run.stopped &&
    run.running is Some((_, expected)) &&
    physical_equal(expected, attempt) {
    run.running = None
    collect_captured_retention(run)
  }
}
