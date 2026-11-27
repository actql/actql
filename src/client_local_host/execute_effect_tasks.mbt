///|
// The exact captured DAG and its original managed operations live here before
// the caller enters a provider step. No physical reader or current callback
// is retained between steps.
struct LocalEffectTaskExecution {
  run : @strategy.CapturedDAG
  installed : @local_driver.LocalDispatchModule
  max_entries : Int
  first : Int
  primary : Int
  tasks : Array[LocalValuesTaskExecution?]
  live : Ref[Bool]
  mut cursor : LocalEffectTaskCursor?
}

///|
priv struct LocalEffectTaskCursor {
  index : Int
  producers : Array[Int]
  mut input : Int
  mut row : Int
  mut phase : LocalEffectTaskPhase
}

///|
priv enum LocalEffectTaskPhase {
  Transfer
  Execute
  PrepareFinalization
  Finalize
  Complete
}

///|
/// Reuse the retained Effect task/table allowance. The stepped caller has
/// one extra owner record with its Option, and one live cursor with its
/// Option and phase. The task closures and inputs are already quoted there.
pub fn stepped_effect_local_tasks_control_capacity(
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  retained_effect_local_tasks_control_capacity(graph).bind(
    stepped_local_tasks_control_capacity,
  )
}

///|
pub fn stepped_whole_source_local_tasks_control_capacity(
  graph : @strategy.CheckedDAG,
) -> @execution.ExecutionCapacity? {
  source_input_local_tasks_control_capacity(graph).bind(
    stepped_local_tasks_control_capacity,
  )
}

///|
fn stepped_local_tasks_control_capacity(
  base : @execution.ExecutionCapacity,
) -> @execution.ExecutionCapacity? {
  guard @execution.preparation_representation_cost({
      record_headers: 6L,
      reference_slots: 12L,
      scalar_words: 9L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    })
    is Some(cursor) &&
    @execution.execution_capacity(cursor, cursor) is Some(extra) else {
    return None
  }
  @execution.add_execution_capacity(base, extra)
}

///|
/// The caller funds the complete control capacity on this Run before opening
/// the driver, and retains it until all of this original's children close.
pub fn begin_stepped_effect_local_tasks(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  captured : @strategy.CapturedEffectRunDAG,
) -> Result[LocalEffectTaskExecution, LocalValuesExecutionIssue] {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  let count = @strategy.graph_task_count(graph)
  let first = @strategy.graph_captured_prefix(graph)
  let primary = @strategy.captured_effect_run_source_at(captured, 0)
    .map(@strategy.checked_effect_source_task)
    .unwrap_or(-1)
  guard physical_equal(run, @strategy.captured_effect_run_dag(captured)) &&
    @strategy.graph_program_has_effects(graph) &&
    count > first &&
    primary >= first &&
    primary < count else {
    return Err(UnsupportedGraph)
  }
  begin_stepped_local_tasks(setup, run, count, first, primary)
}

///|
/// Borrow the exact already opened Pure Whole host. The same stepped task
/// owner handles the ordered supplied inputs and the actual named results.
pub fn begin_stepped_whole_source_local_tasks(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
) -> Result[LocalEffectTaskExecution, LocalValuesExecutionIssue] {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  let graph = @strategy.captured_dag_graph(run)
  let count = @strategy.graph_task_count(graph)
  guard installed_managed_preparation_admission_original(
      owner, prepared, request,
    )
    is Some(_) &&
    owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    !plan.whole_sources.is_empty() &&
    owner.source_free_captured is Some(original) &&
    physical_equal(original, run) &&
    physical_equal(plan.graph, graph) &&
    @strategy.source_inputs_dag_matches_original(
      graph,
      @publication_host.prepared_client_graph(prepared),
    ) &&
    !owner.effect_operation_closing &&
    !@strategy.graph_program_has_effects(graph) &&
    @strategy.graph_captured_prefix(graph) == 0 &&
    count > 0 &&
    @strategy.next_captured_task(run) == Some(0) &&
    @strategy.graph_result_task(graph, 0) is Some(primary) &&
    primary >= 0 &&
    primary < count else {
    return Err(UnsupportedGraph)
  }
  begin_stepped_local_tasks(setup, run, count, 0, primary)
}

///|
fn begin_stepped_local_tasks(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  run : @strategy.CapturedDAG,
  count : Int,
  first : Int,
  primary : Int,
) -> Result[LocalEffectTaskExecution, LocalValuesExecutionIssue] {
  guard @builtin.configured_local_module(
      @builtin.configured_host_modules(setup),
    )
    is Some(installed) else {
    return Err(MissingLocalModule)
  }
  Ok({
    run,
    installed,
    max_entries: @host_driver.compute_host_max_entries(
      @builtin.configured_host_runtime(setup),
    ),
    first,
    primary,
    tasks: Array::make(count, None),
    live: Ref(true),
    cursor: None,
  })
}

///|
fn LocalEffectTaskExecution::completed_outputs(
  self : LocalEffectTaskExecution,
) -> Bool {
  guard self.tasks[self.primary] is Some({ completed: Some(_), .. }) else {
    return false
  }
  let graph = @strategy.captured_dag_graph(self.run)
  if @strategy.graph_program_has_effects(graph) {
    return true
  }
  for index in 0..<@strategy.graph_result_count(graph) {
    guard @strategy.graph_result_task(graph, index) is Some(task) &&
      self.tasks.get(task) is Some(Some({ completed: Some(_), .. })) else {
      return false
    }
  }
  true
}

///|
fn LocalEffectTaskExecution::start_next(
  self : LocalEffectTaskExecution,
  current : () -> Bool,
) -> Result[Bool, LocalValuesExecutionIssue] {
  let graph = @strategy.captured_dag_graph(self.run)
  guard @strategy.next_captured_task(self.run) is Some(_) else {
    return if self.completed_outputs() { Ok(true) } else { Err(MissingOutput) }
  }
  let retained_effect = @strategy.graph_program_has_effects(graph)
  let (index, producers, prepared) = match
    prepare_local_values_task(
      self.run,
      graph,
      self.installed,
      self.tasks,
      self.first,
      retained_effect,
      !retained_effect,
      false,
      self.max_entries,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !current() {
    return Err(Fenced)
  }
  let operations = match
    start_local_values_task(
      self.run,
      index,
      self.installed,
      prepared,
      true,
      // A Pure Whole task starts with its admitted Source or completed
      // producer; the driver can quote that exact managed-row transport.
      canonical_managed_rows=!retained_effect,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  self.tasks[index] = Some({ operations, settled: false, completed: None, })
  if !operations.retained_inputs.is_empty() {
    return Err(UnsupportedGraph)
  }
  self.cursor = Some({ index, producers, input: 0, row: 0, phase: Transfer, })
  Ok(false)
}

///|
fn LocalEffectTaskExecution::transfer_input(
  self : LocalEffectTaskExecution,
  cursor : LocalEffectTaskCursor,
  task : LocalValuesTaskExecution,
) -> Result[Unit, LocalValuesExecutionIssue] {
  guard task.operations.inputs.get(cursor.input) is Some(transfer) else {
    cursor.phase = Execute
    return Ok(())
  }
  let input = @execution.managed_producer_read_input_index(transfer.input)
  guard cursor.producers.get(input) is Some(producer) &&
    self.tasks.get(producer) is Some(Some(from)) &&
    from.completed is Some(output) &&
    @execution.managed_producer_read_matches_reference(
      transfer.input,
      @execution.managed_completed_reference(output),
    ) else {
    return Err(MissingOutput)
  }
  if cursor.row < @execution.managed_completed_output_row_count(output) {
    let wire = match (from.operations.output_row)(cursor.row) {
      Ok(value) => value
      Err(issue) => return Err(Driver(issue))
    }
    match (transfer.append)(wire) {
      Ok(_) => ()
      Err(issue) => return Err(Driver(issue))
    }
    cursor.row += 1
  } else {
    match (transfer.finish)() {
      Ok(_) => ()
      Err(issue) => return Err(Driver(issue))
    }
    cursor.input += 1
    cursor.row = 0
  }
  Ok(())
}

///|
/// Advance at most one bounded provider/finalizer step or one original row
/// transfer. Failure seals this driver; only close may follow it. The caller
/// reobserves the current Run and physical inputs around each call.
pub fn LocalEffectTaskExecution::advance(
  self : LocalEffectTaskExecution,
  quantum : Int,
  current : () -> Bool,
) -> Result[Bool, LocalValuesExecutionIssue] {
  let result = if quantum <= 0 {
    Err(LocalValuesExecutionIssue::InvalidLimits)
  } else if !self.live.val || !current() {
    Err(Fenced)
  } else {
    self
    .advance_step(quantum, current)
    .bind(done => {
      if current() && self.live.val {
        Ok(done)
      } else {
        Err(Fenced)
      }
    })
  }
  if result is Err(_) {
    self.live.val = false
  }
  result
}

///|
fn LocalEffectTaskExecution::advance_step(
  self : LocalEffectTaskExecution,
  quantum : Int,
  current : () -> Bool,
) -> Result[Bool, LocalValuesExecutionIssue] {
  guard self.cursor is Some(cursor) else { return self.start_next(current) }
  guard self.tasks[cursor.index] is Some(task) else {
    return Err(UnsupportedGraph)
  }
  let operations = task.operations
  let live = self.live
  match cursor.phase {
    Transfer =>
      match self.transfer_input(cursor, task) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
    Execute => {
      let progress = match (operations.advance)(quantum) {
        Ok(value) => value
        Err(issue) => return Err(Driver(issue))
      }
      if progress.complete {
        cursor.phase = PrepareFinalization
      } else if progress.await_io ||
        progress.waiting ||
        progress.settlement is Some(_) ||
        progress.work <= 0L {
        return Err(FinalizationLimit)
      }
    }
    PrepareFinalization => {
      match
        (operations.prepare_finalization)(
          cursor.index,
          operations.storage_bytes,
          () => live.val,
        ) {
        Ok(_) => ()
        Err(issue) => return Err(Driver(issue))
      }
      cursor.phase = Finalize
    }
    Finalize => {
      let progress = match (operations.advance_finalization)(quantum) {
        Ok(value) => value
        Err(issue) => return Err(Driver(issue))
      }
      if progress.complete {
        cursor.phase = Complete
      } else if progress.work <= 0L {
        return Err(FinalizationLimit)
      }
    }
    Complete => {
      match (operations.settle)() {
        Ok(_) => ()
        Err(issue) => return Err(Driver(issue))
      }
      task.settled = true
      task.completed = match
        (operations.complete)(cursor.index, operations.storage_bytes, () => {
          live.val
        }) {
        Ok(value) => Some(value)
        Err(issue) => return Err(Driver(issue))
      }
      self.cursor = None
    }
  }
  Ok(false)
}

///|
/// Use the same graph-owned completions and Output operations as Native.
pub fn LocalEffectTaskExecution::result(
  self : LocalEffectTaskExecution,
) -> LocalValuesExecution? {
  guard self.live.val &&
    self.cursor is None &&
    @strategy.next_captured_task(self.run) is None &&
    self.completed_outputs() &&
    self.tasks[self.primary] is Some(primary) &&
    primary.completed is Some(completed) else {
    return None
  }
  let lookup = fn(task : Int) {
    guard self.tasks.get(task) is Some(Some(original)) &&
      original.completed is Some(output) else {
      return None
    }
    Some((original.operations, output))
  }
  Some({
    run: self.run,
    operations: primary.operations,
    completed,
    available: self.live,
    tasks: Some((lookup, () => self.close())),
  })
}

///|
pub fn LocalEffectTaskExecution::close(self : LocalEffectTaskExecution) -> Bool {
  self.live.val = false
  if self.cursor is Some(cursor) && self.tasks[cursor.index] is Some(task) {
    let operations = task.operations
    (operations.close)()
    if !(operations.execution_stopped)() {
      // Disposal forbids activation. The one existing provider can still
      // need its bounded stop poll; retirement depends on its real ACK.
      (operations.advance)(1) |> ignore
    }
  }
  close_local_values_tasks(self.run, self.tasks)
}
