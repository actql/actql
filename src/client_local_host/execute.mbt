///|
/// Retained native-capable Local Values execution. The legacy constructor
/// drives one task; the graph entries retain every original Compute task.
/// Checked strategy, resource Ledger and managed completions remain owned by
/// their existing modules; this adapter drives only their installed operations.
pub struct LocalValuesExecution {
  run : @strategy.CapturedDAG
  operations : @local_driver.LocalManagedDispatchOperations[Int]
  completed : @execution.ManagedCompletedOutput[Int]
  available : Ref[Bool]
  tasks : (
    (Int) -> (
      @local_driver.LocalManagedDispatchOperations[Int],
      @execution.ManagedCompletedOutput[Int],
    )?,
    () -> Bool,
  )?
}

///|
priv struct LocalValuesTaskExecution {
  operations : @local_driver.LocalManagedDispatchOperations[Int]
  mut settled : Bool
  mut completed : @execution.ManagedCompletedOutput[Int]?
}

///|
pub(all) enum LocalValuesExecutionIssue {
  InvalidLimits
  Fenced
  UnsupportedGraph
  MissingLocalModule
  Driver(@local_driver.LocalDispatchIssue)
  Estimate(@host_driver.AdaptiveEstimateIssue[@strategy.RunIssue])
  FinalizationLimit
  MissingOutput
}

///|
/// A failed physical Values occurrence retains only its cleanup owner.
/// Retrying cleanup cannot reopen the kernel or repeat Compute.
pub struct LocalValuesExecutionFailure {
  issue : LocalValuesExecutionIssue
  cleanup : () -> Bool
  mut cleaned : Bool
}

///|
pub fn local_values_execution_failure_issue(
  failure : LocalValuesExecutionFailure,
) -> LocalValuesExecutionIssue {
  failure.issue
}

///|
pub fn local_values_execution_failure_cleanup_pending(
  failure : LocalValuesExecutionFailure,
) -> Bool {
  !failure.cleaned
}

///|
pub fn retry_local_values_execution_failure_cleanup(
  failure : LocalValuesExecutionFailure,
) -> Bool {
  if !failure.cleaned {
    failure.cleaned = (failure.cleanup)()
  }
  failure.cleaned
}

///|
fn failed_local_values_execution(
  issue : LocalValuesExecutionIssue,
) -> LocalValuesExecutionFailure {
  { issue, cleanup: () => true, cleaned: true, }
}

///|
fn stop_local_values_run(run : @strategy.CapturedDAG) -> Unit {
  @strategy.stop_captured_dag(run)
  @strategy.close_captured_task_output(run, 0)
  @strategy.refresh_captured_retention(run)
}

///|
fn reject_local_values_operations(
  run : @strategy.CapturedDAG,
  operations : @local_driver.LocalManagedDispatchOperations[Int],
  issue : LocalValuesExecutionIssue,
) -> LocalValuesExecutionFailure {
  (operations.close)()
  stop_local_values_run(run)
  let cleanup = fn() {
    match (operations.settle)() {
      Err(_) => false
      Ok(_) => (operations.cleanup_refresh)()
    }
  }
  let cleaned = cleanup()
  { issue, cleanup, cleaned, }
}

///|
/// Call only after the Host has accepted and reserved the exact Run. The
/// bounded finalization loop advances the existing task owner; it neither
/// chooses another candidate nor retries Compute after an uncertain start.
pub fn execute_source_free_values(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  execute_source_free_values_guarded(
    setup,
    finalization_quantum,
    max_finalization_rounds,
    () => true,
  )
}

///|
/// The original Native journal/authority supplies this fence. It is checked
/// around physical boundaries, not interpreted as a cancellation terminal.
/// Failure retains the same task's cleanup handle and never restarts Compute.
pub fn execute_source_free_values_guarded(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  if finalization_quantum <= 0 || max_finalization_rounds <= 0 {
    return Err(failed_local_values_execution(InvalidLimits))
  }
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  if !require_current() {
    stop_local_values_run(run)
    return Err(failed_local_values_execution(Fenced))
  }
  if @strategy.graph_task_count(graph) != 1 ||
    @strategy.next_captured_task(run) != Some(0) {
    stop_local_values_run(run)
    return Err(failed_local_values_execution(UnsupportedGraph))
  }
  guard @builtin.configured_local_module(
      @builtin.configured_host_modules(setup),
    )
    is Some(installed) &&
    @strategy.graph_task_owner(graph, 0) is Some(owner) else {
    stop_local_values_run(run)
    return Err(failed_local_values_execution(MissingLocalModule))
  }
  let empty : Array[@execution.ManagedCompletedOutput[Int]] = []
  let prepared = match
    @local_driver.prepare_local_managed_dispatch(
      installed,
      empty,
      @execution.process_managed_obligations(owner),
      0L,
    ) {
    Ok(Some(value)) => value
    Ok(None) => {
      stop_local_values_run(run)
      return Err(failed_local_values_execution(UnsupportedGraph))
    }
    Err(issue) => {
      stop_local_values_run(run)
      return Err(failed_local_values_execution(Driver(issue)))
    }
  }
  if !require_current() {
    stop_local_values_run(run)
    return Err(failed_local_values_execution(Fenced))
  }
  let operations = match
    @local_driver.start_local_managed_dispatch_node(prepared) {
    Ok(value) => value
    Err(issue) => {
      stop_local_values_run(run)
      return Err(failed_local_values_execution(Driver(issue)))
    }
  }
  if !operations.inputs.is_empty() {
    return Err(
      reject_local_values_operations(run, operations, UnsupportedGraph),
    )
  }
  if !require_current() {
    return Err(reject_local_values_operations(run, operations, Fenced))
  }
  match (operations.execute)() {
    Ok(_) => ()
    Err(issue) =>
      return Err(reject_local_values_operations(run, operations, Driver(issue)))
  }
  let available = Ref(true)
  if !require_current() {
    return Err(reject_local_values_operations(run, operations, Fenced))
  }
  match
    (operations.prepare_finalization)(0, operations.storage_bytes, fn() {
      available.val && require_current()
    }) {
    Ok(_) => ()
    Err(issue) =>
      return Err(reject_local_values_operations(run, operations, Driver(issue)))
  }
  let mut complete = false
  for _ in 0..<max_finalization_rounds {
    if !require_current() {
      available.val = false
      return Err(reject_local_values_operations(run, operations, Fenced))
    }
    let progress = match
      (operations.advance_finalization)(finalization_quantum) {
      Ok(value) => value
      Err(issue) => {
        available.val = false
        return Err(
          reject_local_values_operations(run, operations, Driver(issue)),
        )
      }
    }
    if progress.complete {
      complete = true
      break
    }
    if progress.work <= 0L {
      break
    }
  }
  if !require_current() {
    available.val = false
    return Err(reject_local_values_operations(run, operations, Fenced))
  }
  if !complete {
    available.val = false
    return Err(
      reject_local_values_operations(run, operations, FinalizationLimit),
    )
  }
  match (operations.settle)() {
    Ok(_) => ()
    Err(issue) => {
      available.val = false
      return Err(reject_local_values_operations(run, operations, Driver(issue)))
    }
  }
  if !require_current() {
    available.val = false
    return Err(reject_local_values_operations(run, operations, Fenced))
  }
  let completed = match
    (operations.complete)(0, operations.storage_bytes, fn() {
      available.val && require_current()
    }) {
    Ok(value) => value
    Err(issue) => {
      available.val = false
      return Err(reject_local_values_operations(run, operations, Driver(issue)))
    }
  }
  let execution : LocalValuesExecution = {
    run,
    operations,
    completed,
    available,
    tasks: None,
  }
  if !require_current() {
    // Completion already transferred cleanup to this execution. Repeating
    // the pre-completion settle path would leave a completed task pending.
    let cleanup = () => execution.close()
    return Err({ issue: Fenced, cleanup, cleaned: cleanup(), })
  }
  Ok(execution)
}

///|
pub fn LocalValuesExecution::completed_output(
  self : LocalValuesExecution,
) -> @execution.ManagedCompletedOutput[Int] {
  self.completed
}

///|
pub fn LocalValuesExecution::material(
  self : LocalValuesExecution,
) -> @execution.ManagedRetainedOutput[Int]? {
  (self.operations.material)()
}

///|
pub fn LocalValuesExecution::rows(
  self : LocalValuesExecution,
) -> Result[Array[String], LocalValuesExecutionIssue] {
  if !self.available.val {
    return Err(MissingOutput)
  }
  let rows : Array[String] = []
  for index in 0..<(self.operations.output_rows)() {
    match (self.operations.output_row)(index) {
      Ok(row) => rows.push(row)
      Err(issue) => return Err(Driver(issue))
    }
  }
  Ok(rows)
}

///|
pub fn LocalValuesExecution::close(self : LocalValuesExecution) -> Bool {
  if self.tasks is Some((_, cleanup)) {
    self.available.val = false
    return cleanup()
  }
  if !self.available.val {
    return (self.operations.cleanup_refresh)()
  }
  self.available.val = false
  (self.operations.close)()
  let cleaned = (self.operations.cleanup_refresh)()
  stop_local_values_run(self.run)
  cleaned
}
