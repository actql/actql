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
      if !(task.operations.execution_stopped)() {
        ready = false
        continue
      }
      if !task.settled {
        match (task.operations.settle)() {
          Ok(_) => task.settled = true
          Err(_) => ready = false
        }
      }
      if !(task.operations.cleanup_refresh)() {
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
  drive_task? : ((Int, @local_driver.LocalManagedDispatchOperations[Int]) -> Result[
    Unit,
    LocalValuesExecutionIssue,
  ])? = None,
  cleanup_ready? : (() -> Bool)? = None,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  execute_local_tasks_guarded(
    setup,
    finalization_quantum,
    max_finalization_rounds,
    require_current,
    require_live~,
    first=0,
    drive_task~,
    cleanup_ready~,
  )
}

///|
/// Execute the original task chain supplied by this retained Whole Source
/// Plan. Equal Graphs or a Host from another Run cannot replace its binding.
/// Source custody remains with the caller through execution and cleanup.
pub fn execute_installed_whole_source_values_guarded(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  drive_task? : ((Int, @local_driver.LocalManagedDispatchOperations[Int]) -> Result[
    Unit,
    LocalValuesExecutionIssue,
  ])? = None,
  cleanup_ready? : (() -> Bool)? = None,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
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
    physical_equal(plan.graph, @strategy.captured_dag_graph(run)) &&
    @strategy.source_inputs_dag_matches_original(
      plan.graph,
      @publication_host.prepared_client_graph(prepared),
    ) else {
    return Err(failed_local_values_execution(UnsupportedGraph))
  }
  execute_local_tasks_guarded(
    setup,
    finalization_quantum,
    max_finalization_rounds,
    require_current,
    require_live=None,
    first=0,
    drive_task~,
    cleanup_ready~,
    whole_source=Some(plan),
  )
}

///|
/// Continue only the original checked Effect computation. Completed Source
/// and Model tasks stay on this same captured DAG; they are not dispatched
/// again. The caller keeps their original output uses until this execution's
/// cleanup returns, including when a later task cannot be started.
pub fn execute_retained_effect_local_tasks_guarded(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  captured : @strategy.CapturedEffectRunDAG,
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  require_live? : (() -> Bool)? = None,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  if !physical_equal(run, @strategy.captured_effect_run_dag(captured)) ||
    !@strategy.graph_program_has_effects(@strategy.captured_dag_graph(run)) {
    return Err(failed_local_values_execution(UnsupportedGraph))
  }
  execute_local_tasks_guarded(
    setup,
    finalization_quantum,
    max_finalization_rounds,
    require_current,
    require_live~,
    first=@strategy.graph_captured_prefix(@strategy.captured_dag_graph(run)),
    retained_effect=Some(captured),
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
// No caller-provided skip count: the original Plan owns every captured task.
// Recheck both the acquisition's RowRun and that exact capture's DAG input;
// equal rows/schema or another capture of the same declaration are insufficient.
fn installed_captured_local_tasks_nominal(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledManagedCapturePlan,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  run : @strategy.CapturedDAG,
  captures : Array[@row_source_host.RowSourceCapture],
) -> Bool {
  let first = @strategy.graph_captured_prefix(plan.graph)
  guard first > 0 &&
    !@strategy.graph_program_has_effects(plan.graph) &&
    plan.whole_sources.is_empty() &&
    plan.captures.length() == first &&
    captures.length() == first &&
    owner.reads.length() == first &&
    owner.original is Some(original_owner) &&
    physical_equal(original_owner, owner) &&
    owner.preparation is Some(PureManaged(_, original_prepared)) &&
    physical_equal(original_prepared, prepared) &&
    owner.captured_preparation is Some(original) &&
    physical_equal(original, plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    physical_equal(owner.request, request) &&
    owner.source_free_captured is Some(original_run) &&
    physical_equal(original_run, run) &&
    physical_equal(plan.graph, @strategy.captured_dag_graph(run)) &&
    owner.ledger is Some(ledger) &&
    physical_equal(ledger, @strategy.captured_dag_ledger(run)) else {
    return false
  }
  for index in 0..<first {
    guard plan.captures[index].acquisition is Some(acquisition) &&
      owner.reads[index] is Some(read) &&
      read.acquisition is Some(original_acquisition) &&
      physical_equal(original_acquisition, acquisition) &&
      read.managed_run is Some((original_owner, occurrence)) &&
      physical_equal(original_owner, owner) &&
      occurrence == index &&
      read.ledger is Some(original_ledger) &&
      physical_equal(original_ledger, ledger) &&
      read.run is Some(row_run) &&
      @row_source_host.check_row_query_capture_run(captures[index], row_run) &&
      @row_source_host.check_row_capture_compute_original(
        captures[index],
        run,
        index,
      ) else {
      return false
    }
  }
  true
}

///|
fn installed_captured_local_tasks_current(
  owner : ClientInstalledManagedRun,
  plan : ClientInstalledManagedCapturePlan,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  run : @strategy.CapturedDAG,
  captures : Array[@row_source_host.RowSourceCapture],
) -> Bool {
  if !installed_captured_local_tasks_nominal(
      owner, plan, prepared, request, run, captures,
    ) {
    return false
  }
  for index in 0..<captures.length() {
    if !@row_source_host.check_row_capture_compute_binding(
        captures[index],
        run,
        index,
      ) {
      return false
    }
  }
  // A later Source verifier can synchronously retire/replace an earlier read.
  // Recheck the complete original inventory without another callback, not only
  // the last successful Source. This does not replace the Account/current gate.
  installed_captured_local_tasks_nominal(
    owner, plan, prepared, request, run, captures,
  )
}

///|
/// Continue the original finite Query captures on their SAME installed Plan.
/// The caller retains physical readers and the separately quoted loop controls
/// through execution/failure cleanup. This neither starts a Source nor claims
/// a Run, and never skips a task selected by a caller-supplied index.
pub fn execute_installed_captured_local_tasks_guarded(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  captures : Array[@row_source_host.RowSourceCapture],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  require_live? : (() -> Bool)? = None,
  drive_task? : ((Int, @local_driver.LocalManagedDispatchOperations[Int]) -> Result[
    Unit,
    LocalValuesExecutionIssue,
  ])? = None,
  cleanup_ready? : (() -> Bool)? = None,
) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
  let run = @host_driver.dispatch_driver_run(
    @builtin.configured_host_driver(setup),
  )
  guard owner.captured_preparation is Some(plan) &&
    captures.length() == plan.captures.length() &&
    captures.length() == @strategy.graph_captured_prefix(plan.graph) &&
    !captures.is_empty() else {
    return Err(failed_local_values_execution(UnsupportedGraph))
  }
  // Snapshot only the bounded reference vector, before any Source/current
  // callback. Its actual allocation is in this entry's existing control quote;
  // rows, readers and acquisition originals are borrowed, never reconstructed.
  let captures = captures.copy()
  guard installed_captured_local_tasks_current(
    owner, plan, prepared, request, run, captures,
  ) else {
    return Err(failed_local_values_execution(UnsupportedGraph))
  }
  // Retain the finite input snapshot; each callback-return check binds every
  // entry again to the Plan/read/DAG originals before dispatch or publication.
  let current = () => {
    require_current() &&
    installed_captured_local_tasks_current(
      owner, plan, prepared, request, run, captures,
    )
  }
  let live = match require_live {
    None => None
    Some(check) =>
      Some(() => {
        check() &&
        installed_captured_local_tasks_current(
          owner, plan, prepared, request, run, captures,
        )
      })
  }
  execute_local_tasks_guarded(
    setup,
    finalization_quantum,
    max_finalization_rounds,
    current,
    require_live=live,
    first=@strategy.graph_captured_prefix(plan.graph),
    drive_task~,
    cleanup_ready~,
    captured_source=Some(plan),
  )
}

///|
fn execute_local_tasks_guarded(
  setup : @builtin.ConfiguredComputeHost[@strategy.RunIssue],
  finalization_quantum : Int,
  max_finalization_rounds : Int,
  require_current : () -> Bool,
  require_live~ : (() -> Bool)?,
  first~ : Int,
  drive_task? : ((Int, @local_driver.LocalManagedDispatchOperations[Int]) -> Result[
    Unit,
    LocalValuesExecutionIssue,
  ])? = None,
  cleanup_ready? : (() -> Bool)? = None,
  retained_effect? : @strategy.CapturedEffectRunDAG? = None,
  whole_source? : ClientInstalledManagedCapturePlan? = None,
  captured_source? : ClientInstalledManagedCapturePlan? = None,
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
    let cleanup = () => {
      cleanup_ready.map(ready => ready()).unwrap_or(true) &&
      close_local_values_tasks(run, [])
    }
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
  // The same cleanup closure retains the tasks on either exit. A Host pause
  // can fail to restore the physical Compute scope before disposal.
  let cleanup = () => {
    cleanup_ready.map(ready => ready()).unwrap_or(true) &&
    close_local_values_tasks(run, tasks)
  }
  let reject = fn(
    issue : LocalValuesExecutionIssue,
  ) -> Result[LocalValuesExecution, LocalValuesExecutionFailure] {
    available.val = false
    Err(LocalValuesExecutionFailure::{ issue, cleanup, cleaned: cleanup(), })
  }
  if !current() {
    return reject(Fenced)
  }
  if require_live is Some(poll) && !poll() {
    return reject(Fenced)
  }
  let continuation = retained_effect is Some(original) &&
    physical_equal(@strategy.captured_effect_run_dag(original), run) &&
    @strategy.graph_program_has_effects(graph)
  // Only the original Whole Plan entrance above supplies this private binding.
  // The public Source-free entry still has no such input or purpose switch.
  let supplied_whole = whole_source is Some(_)
  if @strategy.graph_captured_prefix(graph) != first ||
    (
      !continuation &&
      (
        (
          first == 0 &&
          !supplied_whole &&
          !@strategy.graph_source_free_inputs_complete(graph)
        ) ||
        @strategy.graph_program_has_effects(graph) ||
        @strategy.next_captured_task(run) != Some(first)
      )
    ) {
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
    // This entry starts the exact managed candidate below. The installed
    // fallback estimator belongs to the legacy prepare-next-task boundary;
    // its full materializing envelope cannot preflight this managed request.
    // The retained Model can have completed intermediate tasks already. None
    // only ends dispatch here; the original Result output is still required.
    if continuation && @strategy.next_captured_task(run) is None {
      break
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
      if (continuation || supplied_whole) && producer == -1 {
        inputs.push(@local_driver.local_managed_supplied_relation_input())
        continue
      }
      if continuation &&
        producer >= 0 &&
        producer < count &&
        tasks[producer] is None &&
        @strategy.captured_task_completed(run, producer) {
        // The common DAG binds the receiver to this exact original output.
        // This does not fabricate a ManagedCompletedOutput or its provider.
        inputs.push(@local_driver.local_managed_captured_relation_input())
        continue
      }
      if (first == 1 && producer == 0) ||
        (captured_source is Some(_) && producer >= 0 && producer < first) {
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
    // The same original Source-free Host has one selected Local module.
    // Commit its actual managed candidate only after preparing this next
    // Task with its real inputs; no whole-Run future DATA reservation is
    // needed. The start boundary still admits its complete simultaneous cost.
    if continuation || first == 0 || captured_source is Some(_) {
      match
        @strategy.select_captured_managed_registration(
          run,
          index,
          @local_driver.local_dispatch_registration(installed),
        ) {
        Ok(_) => ()
        Err(issue) => return reject(Driver(Execution(issue)))
      }
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
    // The selected Host may advance this one task across physical pauses.
    // Finalization below still requires these operations' actual completion.
    let executed = match drive_task {
      None => (operations.execute)().map_err(issue => Driver(issue))
      Some(drive) => drive(index, operations)
    }
    match executed {
      Ok(_) => ()
      Err(issue) => return reject(issue)
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
  let result = match retained_effect {
    None => @strategy.graph_result_task(graph, 0).unwrap_or(count - 1)
    Some(original) =>
      // A Model introduces its own retained Result root. The Effect's primary
      // output is selected from its checked source ports, not that Model root.
      @strategy.captured_effect_run_source_at(original, 0)
      .map(@strategy.checked_effect_source_task)
      .unwrap_or(-1)
  }
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
  Ok({
    run,
    operations: primary.operations,
    completed,
    available,
    tasks: Some((lookup, cleanup)),
  })
}

///|
/// Cleanup only the SAME retained Query prefix's original DAG ports, including
/// a failed Host binding that returned no setup. This neither retires Source
/// readers nor reports physical stop. Actual pending task/resource/pin custody
/// refuses completion; no current/availability callback can substitute for it.
pub fn retire_installed_query_capture_ports(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Bool {
  retire_installed_capture_ports(owner, prepared, request, false)
}

///|
/// Retire only the SAME complete-input DAG ports before original physical
/// Source children return. This is not a Source/reader/Host retirement ACK.
pub fn retire_installed_whole_source_ports(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
) -> Bool {
  retire_installed_capture_ports(owner, prepared, request, true)
}

///|
fn retire_installed_capture_ports(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  whole : Bool,
) -> Bool {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    physical_equal(owner.request, request) &&
    owner.preparation is Some(PureManaged(_, original_prepared)) &&
    physical_equal(original_prepared, prepared) &&
    !@strategy.graph_program_has_effects(plan.graph) &&
    (if whole {
      plan.captures.is_empty() &&
      !plan.whole_sources.is_empty() &&
      plan.direct_occurrences is Some(direct) &&
      @publication_host.client_direct_acquisition_occurrence_count(direct) ==
      plan.whole_sources.length()
    } else {
      plan.whole_sources.is_empty() && !plan.captures.is_empty()
    }) &&
    !owner.source_free_opening else {
    return false
  }
  match owner.source_free_captured {
    None => true
    Some(run) => {
      guard physical_equal(plan.graph, @strategy.captured_dag_graph(run)) &&
        owner.ledger is Some(ledger) &&
        physical_equal(ledger, @strategy.captured_dag_ledger(run)) else {
        return false
      }
      close_local_values_tasks(run, []) &&
      !@strategy.captured_task_retirement_pending(run) &&
      !@strategy.captured_task_boundary_cleanup_pending(run)
    }
  }
}
