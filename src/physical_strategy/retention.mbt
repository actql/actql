///|
priv struct TaskLifetime {
  mut live : Bool
}

///|
priv struct TaskRetention {
  mut holding : @resources.Holding?
  mut release_confirmed : () -> Bool
  parents : Array[Int]
}

///|
fn task_parents(run : CapturedDAG, task : Int) -> Array[Int] {
  let parents = []
  for edge in run.graph.data {
    if edge.consumer == task && !parents.contains(edge.producer) {
      parents.push(edge.producer)
    }
  }
  parents
}

///|
/// Trusted Host accounting: associate its exact allocation token only after this
/// task has established success. Task zero is the validated captured root.
/// Sharing is by owned token, never equal CIDs. The Host must keep this port
/// open while exporting the allocation to users outside this run.
/// External storage supplies its original physical-release predicate here;
/// logical close and lack of consumers do not establish physical cleanup.
/// The default is for allocations requiring no asynchronous external release.
pub fn retain_captured_task_allocation(
  run : CapturedDAG,
  task : Int,
  holding : @resources.Holding,
  release_confirmed? : () -> Bool = fn() { true },
) -> Result[Unit, @resources.LedgerIssue] {
  if !@resources.holding_belongs_to(run.ledger, holding) {
    return Err(ForeignOwner)
  }
  guard @resources.holding_available(run.ledger, holding) &&
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
  resource.release_confirmed = release_confirmed
  Ok(())
}

///|
/// Poll the original attached physical-release checks after Host cleanup.
/// This does not close any result, acknowledge cleanup, or replace its check.
pub fn refresh_captured_retention(run : CapturedDAG) -> Unit {
  collect_captured_retention(run)
}

///|
/// Release the Host's result port. Already completed descendants keep their own
/// results and the backing allocations they retain; new readers are revoked.
/// Exporting a result outside this run requires the Host to keep its port open
/// for that external use. This is not a GC/foreign-handle discovery mechanism.
pub fn close_captured_task_output(run : CapturedDAG, task : Int) -> Unit {
  if task < 0 || task >= run.outputs.length() {
    return
  }
  if !task_done(run, task) {
    return
  }
  if run.executions[task] is Some(execution) && !execution.disposed {
    close_task_execution(run, execution)
    return
  }
  run.lifetimes[task].live = false
  if task == 0 {
    run.source = None
  }
  run.outputs[task] = None
  // A cached binding is not a started consumer. Drop our revoked aliases;
  // an in-flight native attempt keeps its input until cleanup is confirmed.
  for edge in run.graph.data {
    if edge.producer == task &&
      !run.done[edge.consumer] &&
      !(run.running is Some((active, _)) && active == edge.consumer) {
      clear_captured_inputs(run, edge.consumer)
    }
  }
  collect_captured_retention(run)
}

///|
fn collect_captured_retention(run : CapturedDAG) -> Unit {
  // Backward edges ensure one descending pass releases newly unreferenced
  // ancestors. This traversal is bounded by the checked graph's task limit.
  for task = run.resources.length() - 1; task >= 0; task = task - 1 {
    guard !run.lifetimes[task].live && run.resources[task] is Some(resource) else {
      continue
    }
    let mut needed = false
    if run.executions[task] is Some(execution) &&
      (!execution.disposed || !task_execution_retention_released(execution)) {
      needed = true
    }
    for child in run.resources {
      if child is Some(child) && child.parents.contains(task) {
        needed = true
      }
    }
    if run.running is Some((active, _)) &&
      run.graph.data.any(edge => {
        edge.consumer == active && edge.producer == task
      }) {
      needed = true
    }
    if !needed && (resource.release_confirmed)() {
      if resource.holding is Some(holding) {
        @resources.release_allocation(run.ledger, holding) |> ignore
      }
      run.resources[task] = None
    }
  }
}

///|
/// Invoke only after the original Host confirms stopped/cleaned native work.
fn captured_cleanup_confirmed(
  run : CapturedDAG,
  execution : TaskExecution,
) -> Unit {
  if run.stopped &&
    run.running is Some((_, expected)) &&
    physical_equal(expected, execution) {
    run.running = None
    collect_captured_retention(run)
  }
}
