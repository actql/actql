///|
/// The authenticated Journal and Store caller supplies the original occurrence
/// together with an independently admitted live output on the receiving graph.
pub(all) struct RestoredTaskOccurrence {
  task : Int
  generation : Int
  attempt : Int
  output : @execution.CompletedOutput?
  retire : (() -> Bool)?
}

///|
pub(all) struct RestoredTaskCut {
  start_revision : Int
  control_revision : Int
  generation : Int
  completed_task : Int
  next_task : Int
  completed : ReadOnlyArray[RestoredTaskOccurrence]
}

///|
/// Index and attempt arrays, transient output wrappers, and validation
/// controls. The receiving output reservation covers its retained wrapper,
/// resource entry and release callback until the last actual borrower returns.
pub fn restored_task_cut_backing(tasks : Int) -> Int64 {
  @execution.preparation_representation_cost({
    record_headers: 18L + 4L * tasks.to_int64(),
    reference_slots: 32L + 8L * tasks.to_int64(),
    scalar_words: 36L + 6L * tasks.to_int64(),
    owned_utf16_units: 0L,
    owned_wire_bytes: 0L,
  }).unwrap()
}

///|
/// Restore an authenticated partial cut into the same checked scheduler. The
/// original Host owns the borrowed material, funded slots and their cleanup.
/// This never claims a send, acknowledges a stop or accepts a resume command.
pub fn restore_captured_task_cut(
  run : CapturedDAG,
  hooks : CapturedTaskBoundaryHooks,
  cut : RestoredTaskCut,
  backing : @resources.CapacityReservation,
  current : () -> Bool,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  guard captured_task_control_state(run, hooks) is Ok((0, Paused)) &&
    hooks.control is Some(control) &&
    control.sample_commits is Some(commits) &&
    control.physical_start_revision == 0 &&
    run.generation == 0 &&
    hooks.committed is None &&
    @resources.restored_ledger_attempts(run.ledger) is Some(attempts) else {
    return Err(StalePause)
  }
  let graph = run.graph
  let tasks = run.done.length()
  if cut.start_revision <= 0 ||
    cut.control_revision < 2 ||
    cut.generation != cut.completed.length() ||
    cut.generation <= 0 ||
    cut.generation >= tasks ||
    cut.generation > attempts ||
    cut.completed_task < 0 ||
    cut.completed_task >= tasks ||
    cut.next_task < 0 ||
    cut.next_task >= tasks {
    return Err(InvalidCut)
  }
  let bytes = restored_task_cut_backing(tasks)
  let available = () => {
    @resources.capacity_reservation_covers(run.ledger, backing, bytes, bytes)
  }
  if !available() {
    return Err(OutputCapacity)
  }
  // Validate the two ordinal indexes and the closure over all original
  // dependencies. Include the existing readiness selector's full worst case.
  let edges = graph_data_count(graph).to_int64() +
    graph_control_count(graph).to_int64()
  let work = 4L +
    12L * tasks.to_int64() +
    edges +
    graph_result_count(graph).to_int64()
  if work > 2147483647L || 1L + edges > (2147483647L - work) / tasks.to_int64() {
    return Err(WorkLimit)
  }
  let work = (work + (1L + edges) * tasks.to_int64()).to_int()
  control.changing = true
  let owns = () => {
    !run.stopped &&
    !hooks.closing &&
    captured_control_owner_matches(run, hooks) &&
    captured_boundary_setup_unstarted(run) &&
    @resources.restored_ledger_attempts(run.ledger) == Some(attempts) &&
    available()
  }
  defer {
    control.changing = false
    if run.stopped || hooks.closing {
      refresh_captured_task_boundary_cleanup(run)
    }
  }
  match @resources.charge_planning(run.ledger, work) {
    Err(issue) => return Err(Boundary(Resource(issue)))
    Ok(_) => ()
  }
  if !owns() || !current() || !owns() {
    return Err(StalePause)
  }
  match validate_restored_task_cut(graph, cut, attempts, tasks) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !owns() || !current() || !owns() {
    return Err(StalePause)
  }
  // Only inert slot writes follow the final owner/current guard. Neither
  // starting a task nor issuing a new attempt participates in restoration.
  for item in cut.completed {
    let task = item.task
    run.done[task] = true
    commits[2 * task] = item.generation
    commits[2 * task + 1] = item.attempt
    match item.output {
      Some(output) => {
        run.outputs[task] = Some(Materialized(output))
        if item.retire is Some(retire) {
          // Readmitted rows own independent retained data. Register the
          // release on the existing slot without borrowing older outputs.
          run.resources[task] = Some({
            holding: None,
            release_confirmed: retire,
            cleanup_observation: CleanupReady,
            parents: [],
          })
        }
      }
      None => run.lifetimes[task].live = false
    }
  }
  run.generation = cut.generation
  control.remaining = tasks - cut.generation
  control.physical_start_revision = cut.start_revision
  control.revision = cut.control_revision
  hooks.committed = Some({
    task: cut.completed_task,
    generation: cut.generation,
    strategy_revision: run.revisions,
  })
  Ok(())
}

///|
fn validate_restored_task_cut(
  graph : CheckedDAG,
  cut : RestoredTaskCut,
  attempts : Int,
  tasks : Int,
) -> Result[Unit, CapturedTaskContinuationIssue] {
  let by_task = FixedArray::make(tasks, -1)
  let by_generation = FixedArray::make(cut.generation, 0)
  let required = FixedArray::make(tasks, false)
  for index in 0..<cut.completed.length() {
    let item = cut.completed[index]
    if item.task < 0 ||
      item.task >= tasks ||
      by_task[item.task] != -1 ||
      item.generation < 1 ||
      item.generation > cut.generation ||
      by_generation[item.generation - 1] != 0 ||
      item.attempt < 1 ||
      item.attempt > attempts {
      return Err(InvalidCut)
    }
    if item.generation == cut.generation && item.task != cut.completed_task {
      return Err(InvalidCut)
    }
    by_task[item.task] = index
    by_generation[item.generation - 1] = item.attempt
  }
  for index in 1..<by_generation.length() {
    if by_generation[index - 1] >= by_generation[index] {
      return Err(InvalidCut)
    }
  }
  let generation = task => {
    let index = by_task[task]
    if index < 0 {
      0
    } else {
      cut.completed[index].generation
    }
  }
  for edge in graph.data_iter() {
    let producer = generation(edge.producer)
    let consumer = generation(edge.consumer)
    if consumer != 0 {
      if producer == 0 || producer >= consumer {
        return Err(InvalidCut)
      }
    } else if producer != 0 {
      required[edge.producer] = true
      if graph_task_target(graph, edge.producer) != Some(edge.target) {
        return Err(MissingOutput(edge.producer))
      }
    }
  }
  for edge in graph.control_iter() {
    let predecessor = generation(edge.predecessor)
    let consumer = generation(edge.consumer)
    if consumer != 0 && (predecessor == 0 || predecessor >= consumer) {
      return Err(InvalidCut)
    }
  }
  for index in 0..<graph_result_count(graph) {
    let task = graph_result_task(graph, index).unwrap()
    if generation(task) != 0 {
      let result = graph_result_occurrence(graph, index).unwrap()
      let target = @pipeline.producer_target(
        @ports.port_input(@execution.managed_result_occurrence_port(result)),
      )
      if graph_task_target(graph, task) != Some(target) {
        return Err(MissingOutput(task))
      }
      required[task] = true
    }
  }
  for item in cut.completed {
    match item.output {
      Some(output) if required[item.task] => {
        guard graph_task_target(graph, item.task) is Some(target) &&
          @execution.completed_output_matches_port(
            output,
            graph.owners_at(item.task).unwrap(),
            target,
          ) else {
          return Err(MissingOutput(item.task))
        }
      }
      None if !required[item.task] && item.retire is None => ()
      _ => return Err(MissingOutput(item.task))
    }
  }
  if next_dependency_ready_task(graph, task => by_task[task] >= 0) !=
    Some(cut.next_task) {
    return Err(InvalidCut)
  }
  Ok(())
}
