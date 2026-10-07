///|
/// An execution view owned by the original checked graph. It selects one
/// consumer and its exact imported predecessor, not a replacement Program or
/// evidence that omitted ancestors completed.
struct RetainedTaskProjection {
  original : CheckedDAG
  graph : CheckedDAG
  producer : Int
  consumer : Int
  target : @pipeline.Target
}

///|
pub fn prepare_retained_task_projection(
  original : CheckedDAG,
  consumer : Int,
) -> Result[RetainedTaskProjection, RunIssue] {
  if graph_program_has_effects(original) ||
    consumer <= 0 ||
    consumer >= original.owners.length() ||
    original.input_counts[consumer] != 1 ||
    original.targets[consumer] is None ||
    !original.supplied_slots.is_empty() {
    return Err(UnsupportedGraph)
  }
  let mut selected : DataEdge? = None
  for edge in original.data {
    if edge.consumer == consumer {
      if selected is Some(_) ||
        edge.input != 0 ||
        edge.producer < 0 ||
        edge.producer >= consumer {
        return Err(UnsupportedGraph)
      }
      selected = Some(edge)
    }
  }
  guard selected is Some(edge) else { return Err(UnsupportedGraph) }
  let producer = edge.producer
  let controls : Array[ControlEdge] = []
  for control in original.control {
    if control.consumer == consumer {
      if control.predecessor != producer {
        return Err(UnsupportedGraph)
      }
      controls.push({ ..control, predecessor: 0, consumer: 1, })
    }
  }
  let graph : CheckedDAG = {
    program: original.program,
    source_free_root: false,
    captured_prefix: 1,
    original_tasks: [
      original.original_tasks[producer],
      original.original_tasks[consumer],
    ],
    original_task_count: original.original_task_count,
    owners: [original.owners[producer], original.owners[consumer]],
    stage_tasks: original.stage_tasks.map(tasks => {
      let projected = []
      for task in tasks {
        if task == producer {
          projected.push(0)
        }
        if task == consumer {
          projected.push(1)
        }
      }
      projected
    }),
    targets: [Some(edge.target), original.targets[consumer]],
    input_counts: [
      original.input_counts[producer],
      original.input_counts[consumer],
    ],
    selected_steps: [
      original.selected_steps[producer],
      original.selected_steps[consumer],
    ],
    prefix_ends: [
      original.prefix_ends[producer],
      original.prefix_ends[consumer],
    ],
    data: [{ ..edge, producer: 0, consumer: 1, }],
    supplied_slots: [],
    control: controls,
    operations: [original.operations[producer], original.operations[consumer]],
    numeric: [original.numeric[producer], original.numeric[consumer]],
    results: original.results
    .filter(result => result.task == consumer)
    .map(result => { ..result, task: 1, }),
  }
  Ok({ original, graph, producer, consumer, target: edge.target, })
}

///|
pub fn retained_task_projection_producer(value : RetainedTaskProjection) -> Int {
  value.producer
}

///|
pub fn retained_task_projection_consumer(value : RetainedTaskProjection) -> Int {
  value.consumer
}

///|
pub fn retained_task_projection_target(
  value : RetainedTaskProjection,
) -> @pipeline.Target {
  value.target
}

///|
pub fn retained_task_projection_matches_output(
  value : RetainedTaskProjection,
  output : @execution.CompletedOutput,
) -> Bool {
  @execution.completed_output_available(output) &&
  @execution.completed_output_matches_port(
    output,
    value.original.owners[value.producer],
    value.target,
  )
}

///|
pub fn retained_task_projection_reference(
  value : RetainedTaskProjection,
  max_references : Int,
  max_work : Int,
) -> Result[CheckedTaskReference, CheckedTaskReferenceIssue] {
  prepare_checked_task_reference(value.graph, 1, max_references, max_work)
}

///|
/// The caller retains the independently admitted predecessor and its charged
/// physical custody. The existing DAG owns only this consumer's execution.
pub fn open_retained_task_dag(
  value : RetainedTaskProjection,
  output : @execution.CompletedOutput,
  ledger : @resources.Ledger,
  canonical_wire_bytes~ : Int,
) -> Result[CapturedDAG, RunIssue] {
  if canonical_wire_bytes < 0 ||
    !retained_task_projection_matches_output(value, output) {
    return Err(ForeignCapture)
  }
  open_checked_dag(
    value.graph,
    [],
    ledger,
    [],
    completed=[(0, output)],
    root_wire_bytes=Some(canonical_wire_bytes),
  )
}
