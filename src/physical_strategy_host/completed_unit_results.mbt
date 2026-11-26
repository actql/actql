///|
priv struct CheckedLocalUnitResultPort {
  stage : Int
  task : Int
  occurrence : @execution.ManagedResultOccurrence
}

///|
fn require_captured_local_unit_completion(
  run : CapturedDAG,
  unit : Int,
  max_work : Int,
) -> Result[Int, RunIssue] {
  let graph = run.graph
  if unit < 0 || unit >= graph.stage_tasks_count() {
    return Err(ForeignCandidate)
  }
  // All original tasks of the selected Unit must have completed. A Whole
  // input graph has no captured-prefix tasks; its actual completed JOIN is
  // still the producer. Neither an individual Source nor a future Model can
  // substitute for that whole original Unit's Result inventory.
  guard graph.stage_tasks_count_at(unit) is Some(task_count) &&
    graph.stage_tasks_iter_at(unit) is Some(tasks) else {
    return Err(ForeignCandidate)
  }
  if task_count > max_work {
    return Err(PreviewWorkLimit)
  }
  for task in tasks {
    if !task_done(run, task) {
      return Err(
        if unit >= graph.captured_prefix_value() {
          ForeignCandidate
        } else {
          NotReady
        },
      )
    }
  }
  Ok(max_work - task_count)
}

///|
fn append_checked_local_unit_result_ports(
  graph : CheckedDAG,
  stage : Int,
  publications : @ports.ResultPorts,
  output : Array[CheckedLocalUnitResultPort],
) -> Result[Unit, RunIssue] {
  for index in 0..<@ports.port_count(publications) {
    let port = @ports.port_at(publications, index).unwrap()
    // A captured Unit can also publish a later computed Result. Resolve its
    // exact checked target before falling back to that Unit's Source task.
    // The ordinary pin still checks the original owner, target and lifetime.
    let selected = match
      graph_stage_target_task(graph, stage, @ports.port_target(port)) {
      Some(task) => Some(task)
      None if stage < graph.captured_prefix_value() => Some(stage)
      None => None
    }
    guard selected is Some(task) && graph.owners_at(task) is Some(owner) else {
      return Err(ForeignCandidate)
    }
    let name = @ports.name(@ports.port_result(port))
    let occurrence = match
      @execution.bind_managed_result_occurrence(owner, name, port) {
      Ok(value) => value
      Err(_) => return Err(ForeignCandidate)
    }
    output.push({ stage, task, occurrence, })
  }
  Ok(())
}

///|
/// The complete checked Result inventory of a finished Unit in one Run.
/// The original pin set owns liveness and cleanup for every declared Result.
struct CapturedCompletedUnitResults {
  run : CapturedDAG
  unit : Int
  pins : CapturedAnyResultOutputSet
}

///|
/// Retain a finished Unit before starting its consumers. Select all its
/// declared Result ports from the checked wiring, including private Results.
pub fn pin_captured_completed_unit_results(
  run : CapturedDAG,
  unit : Int,
  max_pins : Int,
  max_work : Int,
) -> Result[CapturedCompletedUnitResults, RunIssue] {
  if run.stopped {
    return Err(Stopped)
  }
  let remaining = match
    require_captured_local_unit_completion(run, unit, max_work) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let graph = run.graph
  let wiring = @context.program_incoming_wiring(
    @context.incoming_links_requirements(
      @context.program_incoming_gates_owner(
        @checked.incoming_gates(graph.program_value()),
      ),
    ),
  )
  guard @results.wiring_stage_at(wiring, unit) is Some(stage) else {
    return Err(ForeignCandidate)
  }
  let publications = @results.stage_port_publications(stage)
  let count = @ports.port_count(publications)
  if count == 0 || count > max_pins || count > remaining {
    return Err(PreviewWorkLimit)
  }
  let ports = []
  match
    append_checked_local_unit_result_ports(graph, unit, publications, ports) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let requests = ports.map(port => (port.task, port.occurrence))
  let pins = match pin_captured_any_result_output_set(run, requests, max_pins) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if run.stopped {
    release_captured_any_result_output_set(pins) |> ignore
    return Err(Stopped)
  }
  Ok({ run, unit, pins, })
}

///|
/// Check the same captured Run and Unit with no physical read or callback.
pub fn captured_completed_unit_results_match(
  value : CapturedCompletedUnitResults,
  run : CapturedDAG,
  unit : Int,
) -> Bool {
  value.pins.live &&
  !run.stopped &&
  physical_equal(value.run, run) &&
  value.unit == unit
}

///|
pub fn captured_completed_unit_result_count(
  value : CapturedCompletedUnitResults,
) -> Int {
  if captured_completed_unit_results_match(value, value.run, value.unit) {
    value.pins.borrows.length()
  } else {
    0
  }
}

///|
pub fn captured_completed_unit_result_at(
  value : CapturedCompletedUnitResults,
  index : Int,
) -> CapturedAnyResultBorrow? {
  if !captured_completed_unit_results_match(value, value.run, value.unit) {
    return None
  }
  let borrow = captured_any_result_output_set_borrow_at(value.pins, index)
  guard borrow is Some(original) &&
    captured_any_result_borrow_available(original) &&
    captured_completed_unit_results_match(value, value.run, value.unit) else {
    return None
  }
  borrow
}

///|
pub fn release_captured_completed_unit_results(
  value : CapturedCompletedUnitResults,
) -> Bool {
  release_captured_any_result_output_set(value.pins)
}
