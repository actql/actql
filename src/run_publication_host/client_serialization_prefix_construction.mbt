///|
/// Measure the SAME checked serialization input fragment before its wire/tree
/// constructors. This retains no Graph, emitted pipeline or claimed identity.
/// Sorting uses the original internal sort and all other prefixes preserve
/// the actual bound input, including a detour from an earlier authored step.
pub fn measure_prepared_client_serialization_prefix_construction(
  owner : PreparedClientProgram,
  task : Int,
  step : Int,
  max_preparation_work : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentConstruction, ClientSerializationPrefixIssue] {
  if max_wire_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(Fragment(InvalidLimits))
  }
  let barrier = match
    prepare_client_serialization(
      owner,
      task,
      step,
      max_work=max_preparation_work,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Preparation(issue))
  }
  let terminal = match
    @pipeline.serialization_order_input(@lower.serialization_order(barrier)) {
    Step(index) => index
    Input(_) => return Err(ExternalInput)
  }
  let first = @strategy.graph_task_selected_step(owner.graph, task).unwrap_or(0)
  let selected = @strategy.graph_task_selected_step(owner.graph, task)
  if terminal < first && selected != Some(step) {
    return Err(ExternalInput)
  }
  let bound = @lower.serialization_owner(barrier)
  let prepared = @lower.bound_preparation(bound)
  let sorted = @pipeline.serialization_sort(
      @lower.serialization_checked(barrier),
    )
    is Some(_)
  let output_step = if sorted { step } else { terminal }
  let end_step = if sorted { step } else { step - 1 }
  guard output_step >= 0 &&
    output_step <= end_step &&
    @lower.node_at(prepared, output_step) is Some(output) else {
    return Err(Fragment(MissingOutput))
  }
  let selected = if sorted { selected } else { None }
  let serialization_input = if sorted { Some(barrier) } else { None }
  let input = match
    prepare_client_task_pipeline_input(
      bound,
      end_step,
      @lower.node_id(output),
      selected,
      Some(end_step),
      true,
      sequence_limits,
      serialization_input~,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Fragment(Pipeline(issue)))
  }
  measure_client_task_fragment_construction(
    bound,
    @pipeline.Step(output_step),
    selected,
    "task_" + task.to_string() + "_before_serialize_" + step.to_string(),
    input,
    max_wire_bytes,
    max_nodes,
    max_depth,
    serialization_input~,
  ).map_err(issue => Fragment(issue))
}
