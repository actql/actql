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
