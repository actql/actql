///|
/// Physical view of the same checked computation after whole Source input
/// acquisition. The original root still executes all authored operations;
/// no capture Step or completed task is fabricated. The initial implementation
/// accepts one original direct Source input, independently of Query shape.
pub fn prepare_source_input_dag(
  original : CheckedDAG,
  acquisition : @acquisition.SourceAcquisition,
) -> Result[CheckedDAG, GraphIssue] {
  guard original.captured_prefix == 1 &&
    !original.source_free_root &&
    !original.owners.is_empty() &&
    original.original_tasks[0] == 0 &&
    original.stage_tasks[0] == [0] &&
    original.selected_steps[0] is None &&
    original.prefix_ends[0] is None &&
    original.input_counts[0] == 1 &&
    @acquisition.source_acquisition_input(acquisition) is @pipeline.Input(0) &&
    physical_equal(
      @acquisition.source_acquisition_pipeline(acquisition),
      @lower.pipeline(@lower.bound_preparation(original.owners[0])),
    ) &&
    @context.program_identity_stage_requests(
      @checked.source_identity(original.program),
      0,
    )
    is Some(requests) &&
    physical_equal(requests, @acquisition.source_acquisition_owner(acquisition)) &&
    @acquisition.pipeline_requests_count(requests) == 1 &&
    @acquisition.source_acquisition_source_index(acquisition) == 0 &&
    !original.data.any(edge => edge.consumer == 0) &&
    !original.supplied_slots.any(slot => slot.consumer == 0) else {
    return Err(UnsupportedIncoming(0))
  }
  guard @lower.preparation_output_target(
      @lower.bound_preparation(original.owners[0]),
    )
    is Some(target) else {
    return Err(UnsupportedIncoming(0))
  }
  let targets = original.targets.copy()
  targets[0] = Some(target)
  let supplied_slots = original.supplied_slots.copy()
  supplied_slots.push({
    consumer: 0,
    input: 0,
    source_input: 0,
    operation_input: None,
  })
  let graph = { ..original, captured_prefix: 0, targets, supplied_slots, }
  if !graph_ordered_inputs_complete(graph) {
    return Err(UnsupportedIncoming(0))
  }
  Ok(graph)
}

///|
/// Bind complete Direct inputs to their original task/input coordinates. Task
/// numbering and all authored operations remain those of the checked graph.
pub fn prepare_source_inputs_dag(
  original : CheckedDAG,
  acquisitions : Array[@acquisition.SourceAcquisition],
) -> Result[CheckedDAG, GraphIssue] {
  if original.captured_prefix < 1 || acquisitions.is_empty() {
    return Err(UnsupportedIncoming(0))
  }
  let targets = original.targets.copy()
  let supplied_slots = original.supplied_slots.copy()
  let seen = Array::make(original.captured_prefix, false)
  let identity = @checked.source_identity(original.program)
  for acquisition in acquisitions {
    let stage = @acquisition.declaration(
        @acquisition.mode_input(
          @acquisition.source_acquisition_mode(acquisition),
        ),
      ).stage_index
    guard @context.program_identity_stage_requests(identity, stage)
      is Some(requests) &&
      physical_equal(
        requests,
        @acquisition.source_acquisition_owner(acquisition),
      ) &&
      @acquisition.source_acquisition_input(acquisition)
      is @pipeline.Input(input) &&
      graph_stage_operation_task(original, stage, 0) is Some(task) &&
      task >= 0 &&
      task < original.owners.length() &&
      physical_equal(
        @acquisition.source_acquisition_pipeline(acquisition),
        @lower.pipeline(@lower.bound_preparation(original.owners[task])),
      ) &&
      original.selected_steps[task] is None &&
      !supplied_slots.any(slot => slot.consumer == task && slot.input == input) &&
      !original.data.any(edge => edge.consumer == task && edge.input == input) &&
      @lower.preparation_output_target(
        @lower.bound_preparation(original.owners[task]),
      )
      is Some(target) else {
      return Err(UnsupportedIncoming(stage))
    }
    if task < original.captured_prefix {
      seen[task] = true
      targets[task] = Some(target)
    } else if original.targets[task] != Some(target) {
      // A later Source occurrence supplies its actual receiving port. It may
      // not widen a selected task target or manufacture an earlier completion.
      return Err(UnsupportedIncoming(stage))
    }
    supplied_slots.push({
      consumer: task,
      input,
      source_input: input,
      operation_input: None,
    })
  }
  if seen.any(value => !value) {
    return Err(UnsupportedIncoming(0))
  }
  Ok({ ..original, captured_prefix: 0, targets, supplied_slots, })
}

///|
/// This private physical view preserves all checked task/operation identities.
pub fn source_inputs_dag_matches_original(
  graph : CheckedDAG,
  original : CheckedDAG,
) -> Bool {
  if !(graph.captured_prefix == 0 &&
    !graph.source_free_root &&
    physical_equal(graph.program, original.program) &&
    physical_equal(graph.owners, original.owners) &&
    physical_equal(graph.original_tasks, original.original_tasks) &&
    physical_equal(graph.stage_tasks, original.stage_tasks) &&
    physical_equal(graph.selected_steps, original.selected_steps) &&
    physical_equal(graph.prefix_ends, original.prefix_ends) &&
    physical_equal(graph.data, original.data) &&
    physical_equal(graph.control, original.control) &&
    physical_equal(graph.input_counts, original.input_counts) &&
    physical_equal(graph.operations, original.operations) &&
    physical_equal(graph.numeric, original.numeric) &&
    physical_equal(graph.results, original.results) &&
    graph.original_task_count == original.original_task_count &&
    graph.targets.length() == original.targets.length() &&
    graph.supplied_slots.length() >= original.supplied_slots.length()) {
    return false
  }
  for task in 0..<original.targets.length() {
    let expected = if task < original.captured_prefix {
      @lower.preparation_output_target(
        @lower.bound_preparation(original.owners[task]),
      )
    } else {
      original.targets[task]
    }
    if graph.targets[task] != expected {
      return false
    }
  }
  true
}
