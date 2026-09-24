///|
/// One native-capable Local Values task occurrence. The checked strategy,
/// resource ledger and managed completion remain owned by their existing
/// MoonBit modules; this adapter only drives their installed operations.
pub struct LocalValuesExecution {
  run : @strategy.CapturedDAG
  operations : @local_driver.LocalManagedDispatchOperations[Int]
  completed : @execution.ManagedCompletedOutput[Int]
  available : Ref[Bool]
}

///|
pub(all) enum LocalValuesExecutionIssue {
  InvalidLimits
  UnsupportedGraph
  MissingLocalModule
  Driver(@local_driver.LocalDispatchIssue)
  FinalizationLimit
  MissingOutput
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
) -> Unit {
  (operations.close)()
  (operations.cleanup_refresh)() |> ignore
  stop_local_values_run(run)
}

///|
/// Call only after the Host has accepted and reserved the exact Run. The
/// bounded finalization loop advances the existing task owner; it neither
/// chooses another candidate nor retries Compute after an uncertain start.
pub fn execute_source_free_values(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
) -> Result[LocalValuesExecution, LocalValuesExecutionIssue] {
  if finalization_quantum <= 0 || max_finalization_rounds <= 0 {
    return Err(InvalidLimits)
  }
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  if @strategy.graph_task_count(graph) != 1 ||
    @strategy.next_captured_task(run) != Some(0) {
    stop_local_values_run(run)
    return Err(UnsupportedGraph)
  }
  guard @builtin.configured_local_module(
      @builtin.configured_host_modules(setup),
    ) is Some(installed) &&
    @strategy.graph_task_owner(graph, 0) is Some(owner) else {
    stop_local_values_run(run)
    return Err(MissingLocalModule)
  }
  let empty : Array[@execution.ManagedCompletedOutput[Int]] = []
  let prepared = match
    @local_driver.prepare_local_managed_dispatch(
      installed, empty, @execution.process_managed_obligations(owner), 0L,
    ) {
    Ok(Some(value)) => value
    Ok(None) => {
      stop_local_values_run(run)
      return Err(UnsupportedGraph)
    }
    Err(issue) => {
      stop_local_values_run(run)
      return Err(Driver(issue))
    }
  }
  let operations = match @local_driver.start_local_managed_dispatch_node(prepared) {
    Ok(value) => value
    Err(issue) => {
      stop_local_values_run(run)
      return Err(Driver(issue))
    }
  }
  if !operations.inputs.is_empty() {
    reject_local_values_operations(run, operations)
    return Err(UnsupportedGraph)
  }
  match (operations.execute)() {
    Ok(_) => ()
    Err(issue) => {
      reject_local_values_operations(run, operations)
      return Err(Driver(issue))
    }
  }
  let available = Ref(true)
  match
    (operations.prepare_finalization)(
      0, operations.storage_bytes, fn() { available.val },
    ) {
    Ok(_) => ()
    Err(issue) => {
      reject_local_values_operations(run, operations)
      return Err(Driver(issue))
    }
  }
  let mut complete = false
  for _ in 0..<max_finalization_rounds {
    let progress = match
      (operations.advance_finalization)(finalization_quantum) {
      Ok(value) => value
      Err(issue) => {
        available.val = false
        reject_local_values_operations(run, operations)
        return Err(Driver(issue))
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
  if !complete {
    available.val = false
    reject_local_values_operations(run, operations)
    return Err(FinalizationLimit)
  }
  match (operations.settle)() {
    Ok(_) => ()
    Err(issue) => {
      available.val = false
      reject_local_values_operations(run, operations)
      return Err(Driver(issue))
    }
  }
  let completed = match
    (operations.complete)(
      0, operations.storage_bytes, fn() { available.val },
    ) {
    Ok(value) => value
    Err(issue) => {
      available.val = false
      reject_local_values_operations(run, operations)
      return Err(Driver(issue))
    }
  }
  Ok({ run, operations, completed, available, })
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
  if !self.available.val {
    return (self.operations.cleanup_refresh)()
  }
  self.available.val = false
  (self.operations.close)()
  let cleaned = (self.operations.cleanup_refresh)()
  stop_local_values_run(self.run)
  cleaned
}
