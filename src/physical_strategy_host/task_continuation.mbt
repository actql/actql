///|
pub(all) enum CapturedTaskContinuationIssue {
  StalePause
  WorkLimit
  InvalidCut
  MissingCompletion(Int)
  MissingOutput(Int)
  OutputCapacity
  OutputEncoding
  OutputRefused
  Boundary(CapturedTaskBoundaryIssue)
} derive(Eq, Debug)

///|
priv enum ContinuationTaskSelection {
  Completed
  KeepOutput
  Ready
  Blocked
}

///|
/// Read of the original scheduler cut at a settled pause. It keeps only an
/// inventory, not row data, a stop acknowledgement or a recovery claim.
struct CapturedTaskContinuation {
  loan : CapturedTaskBoundary
  revision : Int
  start_revision : Int
  next_task : Int
  mut inventory : FixedArray[ContinuationTaskSelection]?
}

///|
fn task_continuation_current(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  revision : Int,
  generation : Int,
) -> Bool {
  revision >= 2 &&
  generation > 0 &&
  run.generation == generation &&
  run.running is None &&
  run.failure is None &&
  captured_compute_first_task(run) == 0 &&
  captured_task_control_state(run, hooks) == Ok((revision, Paused)) &&
  hooks.control is Some(control) &&
  // This path serves the selected Local Sample controller, whose start
  // ordinal is latched from the original physical-start acknowledgement.
  control.physical_start_revision > 0 &&
  control.sample_commits is Some(_)
}

///|
fn task_continuation_bytes(tasks : Int) -> Int64 {
  // One array entry per task, the read wrapper and inventory, and the
  // simultaneously live scalar projections and result/error carriers.
  captured_boundary_read_bytes +
  @execution.preparation_representation_cost({
    record_headers: 10L,
    reference_slots: 10L,
    scalar_words: 24L + tasks.to_int64(),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
/// Borrow the exact original partial execution. In a single graph pass, keep
/// every completed producer still needed by an incomplete task or an original
/// root Result. Control edges constrain readiness without retaining rows.
/// Availability and physical custody of a required output are checked by its
/// own subsequent export. No historical acceptance can call this without the
/// same current in-memory controller and settled boundary.
pub fn read_captured_task_continuation(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  revision : Int,
  generation : Int,
  max_work : Int,
  visitor_backing? : Int64 = 0L,
) -> Result[CapturedTaskContinuation, CapturedTaskContinuationIssue] {
  guard task_continuation_current(run, hooks, revision, generation) &&
    hooks.committed is Some(record) &&
    captured_boundary_record_current(run, hooks, record, Settled) else {
    return Err(StalePause)
  }
  let graph = run.graph
  let tasks = graph_task_count(graph)
  let backing = task_continuation_bytes(tasks)
  if visitor_backing < 0L || visitor_backing > 9223372036854775807L - backing {
    return Err(OutputCapacity)
  }
  let residents = run.resident_environments.length()
  // Prepay array initialization, two complete task scans and the linear
  // graph/result walks. Amounts are bounded before any traversal or allocation.
  let work = 4L +
    3L * tasks.to_int64() +
    graph_data_count(graph).to_int64() +
    graph_control_count(graph).to_int64() +
    graph_result_count(graph).to_int64() +
    residents.to_int64()
  if work > max_work.to_int64() {
    return Err(WorkLimit)
  }
  match @resources.charge_planning(run.ledger, work.to_int()) {
    Err(issue) => return Err(Boundary(Resource(issue)))
    Ok(_) => ()
  }
  if !task_continuation_current(run, hooks, revision, generation) {
    return Err(StalePause)
  }
  let loan = match
    acquire_captured_boundary_read(
      run,
      hooks,
      record,
      Settled,
      backing + visitor_backing,
    ) {
    Err(issue) => return Err(Boundary(issue))
    Ok(value) => value
  }
  let result = if !task_continuation_current(run, hooks, revision, generation) ||
    run.resident_environments.length() != residents ||
    resident_provision_pending(run) {
    Err(StalePause)
  } else {
    select_task_continuation(run, hooks, loan, revision, generation, tasks)
  }
  if result is Err(_) {
    // The original boundary list still owns any refused capacity return.
    return_captured_task_boundary(loan) |> ignore
  }
  result
}

///|
fn select_task_continuation(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  loan : CapturedTaskBoundary,
  revision : Int,
  generation : Int,
  tasks : Int,
) -> Result[CapturedTaskContinuation, CapturedTaskContinuationIssue] {
  let control = hooks.control.unwrap()
  let graph = run.graph
  let inventory : FixedArray[ContinuationTaskSelection] = FixedArray::make(
    tasks,
    Ready,
  )
  let mut remaining = 0
  for task in 0..<tasks {
    if run.done[task] {
      guard captured_relation_sample_commit(run, task)
        is Some((commit, _, start)) &&
        commit <= generation &&
        (task != loan.task || commit == generation) &&
        start == control.physical_start_revision else {
        return Err(MissingCompletion(task))
      }
      inventory[task] = Completed
    } else {
      remaining += 1
    }
  }
  if remaining != control.remaining || remaining == 0 {
    return Err(InvalidCut)
  }
  for edge in graph.data_iter() {
    if run.done[edge.consumer] {
      if !run.done[edge.producer] {
        return Err(InvalidCut)
      }
    } else if !run.done[edge.producer] {
      inventory[edge.consumer] = Blocked
    } else {
      if !continuation_has_output(run, edge.producer, edge.target) {
        return Err(MissingOutput(edge.producer))
      }
      inventory[edge.producer] = KeepOutput
    }
  }
  for edge in graph.control_iter() {
    if !run.done[edge.predecessor] {
      if run.done[edge.consumer] {
        return Err(InvalidCut)
      }
      inventory[edge.consumer] = Blocked
    }
  }
  for index in 0..<graph_result_count(graph) {
    let task = graph_result_task(graph, index).unwrap()
    if run.done[task] {
      let result = graph_result_occurrence(graph, index).unwrap()
      let target = @pipeline.producer_target(
        @ports.port_input(@execution.managed_result_occurrence_port(result)),
      )
      if !continuation_has_output(run, task, target) {
        return Err(MissingOutput(task))
      }
      inventory[task] = KeepOutput
    }
  }
  for task in 0..<tasks {
    match inventory[task] {
      Ready =>
        return Ok({
          loan,
          revision,
          start_revision: control.physical_start_revision,
          next_task: task,
          inventory: Some(inventory),
        })
      Completed | KeepOutput | Blocked => ()
    }
  }
  Err(InvalidCut)
}

///|
fn continuation_has_output(
  run : CapturedDAG,
  task : Int,
  target : @pipeline.Target,
) -> Bool {
  run.lifetimes[task].live &&
  captured_task_target(run, task) == Some(target) &&
  (
    run.outputs[task] is Some(Materialized(_)) ||
    run.outputs[task] is Some(Managed(_))
  )
}

///|
fn task_continuation_inventory(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
) -> FixedArray[ContinuationTaskSelection]? {
  guard cut.inventory is Some(inventory) &&
    cut.loan.original is Some(read) &&
    task_continuation_current(
      run,
      read.hooks,
      cut.revision,
      cut.loan.generation,
    ) &&
    captured_task_boundary_current(run, cut.loan) else {
    return None
  }
  Some(inventory)
}

///|
/// Original physical start, control revision, completed generation, next
/// physical task and task count. A suspended or external reader still needs
/// the existing Journal and exact original Plan/Run/Map authority.
pub fn captured_task_continuation_position(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
) -> (Int, Int, Int, Int, Int)? {
  guard task_continuation_inventory(run, cut) is Some(inventory) else {
    return None
  }
  Some(
    (
      cut.start_revision,
      cut.revision,
      cut.loan.generation,
      cut.next_task,
      inventory.length(),
    ),
  )
}

///|
/// The committed generation and actual consumed attempt for this completed
/// task, plus whether a complete copy of its exact output is required.
pub fn captured_task_continuation_completion(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
) -> (Int, Int, Bool)? {
  guard task_continuation_inventory(run, cut) is Some(inventory) &&
    task >= 0 &&
    task < inventory.length() &&
    captured_relation_sample_commit(run, task) is Some((generation, attempt, _)) else {
    return None
  }
  match inventory[task] {
    Completed => Some((generation, attempt, false))
    KeepOutput => Some((generation, attempt, true))
    Ready | Blocked => None
  }
}

///|
/// Revoke the inventory before returning its original reservation. On a
/// declined return the same borrow remains in the existing cleanup owner.
pub fn return_captured_task_continuation(
  cut : CapturedTaskContinuation,
) -> Result[Unit, CapturedTaskBoundaryIssue] {
  cut.inventory = None
  return_captured_task_boundary(cut.loan)
}

///|
priv enum CapturedContinuationOutputPin {
  ResidentRelation(CapturedResidentGenerationPin)
  MaterializedRelation(CapturedOutputPin)
}

///|
priv struct CapturedContinuationOutputRead {
  cut : CapturedTaskContinuation
  loan : CapturedTaskBoundary
  run : CapturedDAG
  task : Int
  pin : CapturedContinuationOutputPin
  authorize : () -> Bool
  mut checking : Bool
}

///|
fn continuation_output_current(read : CapturedContinuationOutputRead) -> Bool {
  let { run, task, pin, .. } = read
  guard captured_task_boundary_current(run, read.loan) &&
    captured_task_continuation_completion(run, read.cut, task)
    is Some((_, _, true)) &&
    run.lifetimes[task].live else {
    return false
  }
  match (pin, run.outputs[task]) {
    (ResidentRelation(original), Some(Managed(current))) =>
      original.live &&
      original.reference is Managed(expected) &&
      @execution.managed_completed_reference_same(expected, current)
    (MaterializedRelation(original), Some(Materialized(current))) =>
      original.live && physical_equal(original.output, current)
    _ => false
  }
}

///|
fn continuation_output_available(read : CapturedContinuationOutputRead) -> Bool {
  match read.pin {
    ResidentRelation(pin) => captured_resident_generation_pin_available(pin)
    MaterializedRelation(pin) =>
      @execution.completed_output_available(pin.output)
  }
}

///|
fn check_continuation_output(read : CapturedContinuationOutputRead) -> Bool {
  if read.checking || !continuation_output_current(read) {
    return false
  }
  read.checking = true
  let result = (read.authorize)() &&
    continuation_output_current(read) &&
    continuation_output_available(read) &&
    continuation_output_current(read)
  read.checking = false
  result
}

///|
/// Hold the exact required managed Relation, including its original cell
/// projection, through a synchronous conversion. The converter already owns
/// the typed originals and funds its own writer and destination. This read
/// supplies only a revocable current callback, never a row alias or durable
/// acceptance. A converter must dispose its physical reader before returning.
pub fn[T] with_captured_task_continuation_output(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput,
  authorize : () -> Bool,
  visit : (() -> Bool) -> Unit,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  with_task_continuation_output(
    run,
    cut,
    task,
    completed,
    original,
    authorize,
    0L,
    (current, _) => visit(current),
  )
}

///|
let captured_continuation_output_read_bytes : Int64 = captured_boundary_read_bytes +
  @execution.preparation_representation_cost({
    record_headers: 17L,
    reference_slots: 28L,
    scalar_words: 25L,
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()

///|
fn[T] with_task_continuation_output(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
  completed : @execution.ManagedCompletedOutput[T],
  original : @execution.CompletedOutput,
  authorize : () -> Bool,
  backing : Int64,
  visit : (() -> Bool, CapturedTaskBoundary) -> Unit,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  guard task_continuation_inventory(run, cut) is Some(_) else {
    return Err(StalePause)
  }
  guard captured_task_continuation_completion(run, cut, task)
    is Some((_, _, true)) &&
    captured_task_target(run, task) is Some(target) &&
    captured_managed_task_output_matches(run, task, target, completed) &&
    @execution.managed_completed_output_original_occurrence(completed)
    is Some(occurrence) &&
    @execution.completed_output_occurrence_matches_original(
      occurrence, original,
    ) &&
    @execution.completed_has_cell_access(original) else {
    return Err(MissingOutput(task))
  }
  with_task_continuation_output_boundary(run, cut, backing, loan => {
    read_task_continuation_managed(
      run, cut, task, target, completed, loan, authorize, visit,
    )
  })
}

///|
fn with_task_continuation_output_boundary(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  backing : Int64,
  visit : (CapturedTaskBoundary) -> Result[Unit, CapturedTaskContinuationIssue],
) -> Result[Unit, CapturedTaskContinuationIssue] {
  // The scoped gate, pin and revocation callback share the original fork.
  let bytes = captured_continuation_output_read_bytes + backing
  let loan = match fork_captured_task_boundary(run, cut.loan, bytes) {
    Ok(value) => value
    Err(issue) => return Err(Boundary(issue))
  }
  let result = visit(loan)
  let returned = return_captured_task_boundary(loan)
  match result {
    Err(issue) => Err(issue)
    Ok(_) =>
      returned
      .map_err(issue => CapturedTaskContinuationIssue::Boundary(issue))
      .bind(_ => {
        if task_continuation_inventory(run, cut) is None {
          Err(StalePause)
        } else {
          Ok(())
        }
      })
  }
}

///|
fn[T] read_task_continuation_managed(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
  target : @pipeline.Target,
  completed : @execution.ManagedCompletedOutput[T],
  loan : CapturedTaskBoundary,
  authorize : () -> Bool,
  visit : (() -> Bool, CapturedTaskBoundary) -> Unit,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  if !authorize() || task_continuation_inventory(run, cut) is None {
    return Err(StalePause)
  }
  if !captured_managed_task_output_matches(run, task, target, completed) {
    return Err(MissingOutput(task))
  }
  let pin = match acquire_captured_resident_generation_pin(run, task, 1) {
    Ok(value) => value
    Err(Physical(issue)) => return Err(Boundary(Resource(issue)))
    Err(_) => return Err(MissingOutput(task))
  }
  defer release_captured_resident_generation_pin(pin) |> ignore
  let read = {
    cut,
    loan,
    run,
    task,
    pin: ResidentRelation(pin),
    authorize,
    checking: false,
  }
  visit_task_continuation_output(read, current => {
    if !captured_managed_task_output_matches(run, task, target, completed) {
      return false
    }
    visit(current, loan)
    true
  })
}

///|
fn with_task_continuation_materialized_output(
  run : CapturedDAG,
  cut : CapturedTaskContinuation,
  task : Int,
  authorize : () -> Bool,
  backing : Int64,
  visit : (@execution.CompletedOutput, () -> Bool, CapturedTaskBoundary) -> Unit,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  guard task_continuation_inventory(run, cut) is Some(_) else {
    return Err(StalePause)
  }
  guard @resources.restored_ledger_attempts(run.ledger) is Some(_) &&
    captured_task_continuation_completion(run, cut, task) is Some((_, _, true)) &&
    captured_task_target(run, task) is Some(target) else {
    return Err(MissingOutput(task))
  }
  with_task_continuation_output_boundary(run, cut, backing, loan => {
    if !authorize() || task_continuation_inventory(run, cut) is None {
      return Err(StalePause)
    }
    let pin = match pin_captured_task_output(run, task, target, 1) {
      Ok(value) => value
      Err(Physical(issue)) => return Err(Boundary(Resource(issue)))
      Err(_) => return Err(MissingOutput(task))
    }
    // A live producer cannot retire on unpin. Avoid a whole-graph
    // cleanup pass for each retained output in this same cut.
    defer (if run.lifetimes[task].live {
      drop_captured_output_pin(pin) |> ignore
    } else {
      release_captured_output_pin(pin) |> ignore
    })
    let read = {
      cut,
      loan,
      run,
      task,
      pin: MaterializedRelation(pin),
      authorize,
      checking: false,
    }
    visit_task_continuation_output(read, current => {
      visit(pin.output, current, loan)
      true
    })
  })
}

///|
fn visit_task_continuation_output(
  read : CapturedContinuationOutputRead,
  visit : (() -> Bool) -> Bool,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  let active : Ref[CapturedContinuationOutputRead?] = Ref(Some(read))
  let current = () => {
    match active.val {
      Some(value) => check_continuation_output(value)
      None => false
    }
  }
  defer {
    active.val = None
  }
  if !current() {
    return Err(StalePause)
  }
  if visit(current) && current() {
    Ok(())
  } else {
    Err(StalePause)
  }
}
