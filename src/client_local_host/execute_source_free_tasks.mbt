///|
// Same original Local dispatch/task finalization, with retained outputs for
// every checked predecessor. There is no synthetic combined Program, another
// scheduler, Ledger, physical start or authorization decision here.
fn close_local_values_tasks(
  run : @strategy.CapturedDAG,
  tasks : Array[LocalValuesTaskExecution?],
) -> Bool {
  for index = tasks.length() - 1; index >= 0; index = index - 1 {
    if tasks[index] is Some(task) {
      (task.operations.close)()
    }
  }
  @strategy.stop_captured_dag(run)
  for index in 0..<@strategy.graph_task_count(@strategy.captured_dag_graph(run)) {
    @strategy.close_captured_task_output(run, index)
  }
  @strategy.refresh_captured_retention(run)
  let mut ready = true
  for index = tasks.length() - 1; index >= 0; index = index - 1 {
    if tasks[index] is Some(task) {
      if !task.settled {
        match (task.operations.settle)() {
          Ok(_) => task.settled = true
          Err(_) => ready = false
        }
      }
      if !(task.operations.execution_stopped)() ||
        !(task.operations.cleanup_refresh)() {
        ready = false
      }
    }
  }
  ready
}

///|
/// Execute a finite source-free ordinary Local graph on its already admitted
/// original Run. Each task is selected by that same DAG; managed predecessor
/// wire is admitted through the existing exact transfer bridge before Compute.
/// The legacy single-task/Effect entry is unchanged.
pub fn execute_source_free_local_tasks_guarded(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  require_live? : (() -> Bool)? = None,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  execute_local_tasks_guarded(
    setup,
    finalization_quantum,
    max_finalization_rounds,
    require_current,
    require_live~,
    first=0,
  )
}

///|
/// Continue the single original Row capture through its checked Common tail.
/// The original Host must already have authorized physical work. This entry
/// neither admits a Run nor claims a Source task or supplies authorization.
/// Source custody stays with the caller and must outlive every Compute borrow.
/// The outer Host must reserve the explicit control quote before this call and
/// retain it until all returned execution or failure cleanup has completed.
pub fn execute_captured_local_tasks_guarded(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  capture : @row_source_host.RowSourceCapture,
  requirements : ClientLocalRequirements,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  require_live? : (() -> Bool)? = None,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  // The original outer Host reserves captured_local_tasks_control_capacity
  // before entering here. These wrappers retain borrowed originals only.
  let guarded_current = () => {
    require_current() &&
    captured_local_tasks_current(run, capture, requirements)
  }
  let guarded_live = match require_live {
    None => None
    Some(check) =>
      Some(() => {
        check() && captured_local_tasks_current(run, capture, requirements)
      })
  }
  execute_local_tasks_guarded(
    setup,
    finalization_quantum,
    max_finalization_rounds,
    guarded_current,
    require_live=guarded_live,
    first=1,
  )
}

///|
// Recheck original custody after callbacks. Equal preparations, copied source
// wrappers and captures on another Ledger cannot stand in for these originals.
fn captured_local_tasks_current(
  run : @strategy.CapturedDAG,
  capture : @row_source_host.RowSourceCapture,
  requirements : ClientLocalRequirements,
) -> Bool {
  requirements.capacity_plan.graph_offset == 1 &&
  physical_equal(
    @publication_host.prepared_client_graph(requirements.prepared),
    @strategy.captured_dag_graph(run),
  ) &&
  @row_source_host.check_row_capture_compute_binding(capture, run, 0)
}

///|
fn execute_local_tasks_guarded(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  require_live~ : (() -> Bool)?,
  first~ : Int,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  if finalization_quantum <= 0 || max_finalization_rounds <= 0 {
    return Err(failed_local_values_execution(InvalidLimits))
  }
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  let count = @strategy.graph_task_count(graph)
  // Do not size the retained task table from an unsupported graph. Stopping
  // this original run is still its caller-owned cleanup, not another attempt.
  if count <= first {
    let cleanup = () => close_local_values_tasks(run, [])
    return Err({ issue: UnsupportedGraph, cleanup, cleaned: cleanup(), })
  }
  let tasks : Array[LocalValuesTaskExecution?] = Array::make(count, None)
  let available = Ref(true)
  let current = () => available.val && require_current()
  // Legacy callers retain their original callback at each poll. A trusted
  // caller may separate cheap original-lifetime polling from its currentness
  // guard, which still runs at dispatch and callback-return boundaries below.
  // Neither callback establishes Account authorization in this adapter.
  let live = () => {
    if !available.val {
      return false
    }
    match require_live {
      Some(check) => check()
      None => require_current()
    }
  }
  let reject = fn(
    issue : LocalValuesExecutionIssue,
  ) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
    available.val = false
    let cleanup = () => close_local_values_tasks(run, tasks)
    Err(LocalValuesExecutionFailure::{ issue, cleanup, cleaned: cleanup(), })
  }
  if !current() {
    return reject(Fenced)
  }
  if require_live is Some(poll) && !poll() {
    return reject(Fenced)
  }
  if @strategy.graph_captured_prefix(graph) != first ||
    (first == 0 && !@strategy.graph_source_free_inputs_complete(graph)) ||
    @strategy.graph_program_has_effects(graph) ||
    @strategy.next_captured_task(run) != Some(first) {
    return reject(UnsupportedGraph)
  }
  guard @builtin.configured_local_module(
      @builtin.configured_host_modules(setup),
    )
    is Some(installed) else {
    return reject(MissingLocalModule)
  }
  for _ in first..<count {
    if !current() {
      return reject(Fenced)
    }
    // The single-capture factory retains adaptive proposals, not a selected
    // strategy. Let the existing Host select/refresh them on this same Run.
    if first == 1 {
      match
        @host_driver.refresh_compute_host(
          @builtin.configured_host_runtime(setup),
        ) {
        Ok(_) => ()
        Err(issue) => return reject(Estimate(issue))
      }
      if !current() {
        return reject(Fenced)
      }
    }
    guard @strategy.next_captured_task(run) is Some(index) &&
      index >= first &&
      index < count &&
      tasks[index] is None &&
      @strategy.graph_task_owner(graph, index) is Some(_) else {
      return reject(UnsupportedGraph)
    }
    // Carrier snapshots remain with their existing physical Store owner.
    // This entry does not turn a missing Carrier custody into row storage.
    if @local_driver.local_dispatch_next_carrier_path(installed) {
      return reject(UnsupportedGraph)
    }
    let producers = @strategy.captured_next_managed_producers(run)
    let inputs : Array[@local_driver.LocalManagedAvailableOutput[Int]] = []
    for producer in producers {
      if first == 1 && producer == 0 {
        inputs.push(@local_driver.local_managed_captured_relation_input())
        continue
      }
      guard producer >= first &&
        producer < count &&
        tasks[producer] is Some(task) &&
        task.completed is Some(output) else {
        return reject(MissingOutput)
      }
      inputs.push(@local_driver.local_managed_relation_output(output))
    }
    let obligations = match
      @strategy.captured_next_managed_obligations(
        run,
        @host_driver.compute_host_max_entries(
          @builtin.configured_host_runtime(setup),
        ),
      ) {
      Ok(value) => value
      Err(_) => return reject(Driver(Configuration(InvalidLimits)))
    }
    let prepared = match
      @local_driver.prepare_local_managed_dispatch_with_outputs(
        installed, inputs, obligations, 0L,
      ) {
      Ok(Some(value)) => value
      Ok(None) => return reject(UnsupportedGraph)
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
    let operations = match
      @local_driver.start_local_managed_dispatch_node(prepared) {
      Ok(value) => value
      Err(issue) => return reject(Driver(issue))
    }
    // Retain actual operations before the next current callback can fail.
    let task : LocalValuesTaskExecution = {
      operations,
      settled: false,
      completed: None,
    }
    tasks[index] = Some(task)
    if !current() {
      return reject(Fenced)
    }
    if !operations.retained_inputs.is_empty() {
      return reject(UnsupportedGraph)
    }
    for transfer in operations.inputs {
      if !current() {
        return reject(Fenced)
      }
      let input = @execution.managed_producer_read_input_index(transfer.input)
      guard input >= 0 &&
        input < producers.length() &&
        tasks[producers[input]] is Some(producer) &&
        producer.completed is Some(output) &&
        @execution.managed_producer_read_matches_reference(
          transfer.input,
          @execution.managed_completed_reference(output),
        ) else {
        return reject(MissingOutput)
      }
      for row in 0..<@execution.managed_completed_output_row_count(output) {
        if !live() {
          return reject(Fenced)
        }
        let wire = match (producer.operations.output_row)(row) {
          Ok(value) => value
          Err(issue) => return reject(Driver(issue))
        }
        match (transfer.append)(wire) {
          Ok(_) => ()
          Err(issue) => return reject(Driver(issue))
        }
      }
      if !current() {
        return reject(Fenced)
      }
      match (transfer.finish)() {
        Ok(_) => ()
        Err(issue) => return reject(Driver(issue))
      }
      if !current() {
        return reject(Fenced)
      }
    }
    if !current() {
      return reject(Fenced)
    }
    match (operations.execute)() {
      Ok(_) => ()
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
    match
      (operations.prepare_finalization)(index, operations.storage_bytes, live) {
      Ok(_) => ()
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
    let mut complete = false
    for _ in 0..<max_finalization_rounds {
      if !live() {
        return reject(Fenced)
      }
      let progress = match
        (operations.advance_finalization)(finalization_quantum) {
        Ok(value) => value
        Err(issue) => return reject(Driver(issue))
      }
      if progress.complete {
        complete = true
        break
      }
      if progress.work <= 0L {
        break
      }
    }
    if !current() {
      return reject(Fenced)
    }
    if !complete {
      return reject(FinalizationLimit)
    }
    match (operations.settle)() {
      Ok(_) => task.settled = true
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
    task.completed = match
      (operations.complete)(index, operations.storage_bytes, live) {
      Ok(value) => Some(value)
      Err(issue) => return reject(Driver(issue))
    }
    if !current() {
      return reject(Fenced)
    }
  }
  if @strategy.next_captured_task(run) is Some(_) {
    return reject(UnsupportedGraph)
  }
  let result = @strategy.graph_result_task(graph, 0).unwrap_or(count - 1)
  guard result >= 0 &&
    result < count &&
    tasks[result] is Some(primary) &&
    primary.completed is Some(completed) else {
    return reject(MissingOutput)
  }
  let lookup = fn(task : Int) {
    guard tasks.get(task) is Some(Some(original)) &&
      original.completed is Some(output) else {
      return None
    }
    Some((original.operations, output))
  }
  let cleanup = () => close_local_values_tasks(run, tasks)
  Ok({
    run,
    operations: primary.operations,
    completed,
    available,
    tasks: Some((lookup, cleanup)),
  })
}
