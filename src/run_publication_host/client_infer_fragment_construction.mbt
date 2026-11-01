///|
// Same prefix/suffix lowering inputs as the original Model Graph issuer.
// This returns only codec construction DATA; no Fragment, Graph or CID exists.
fn measure_client_infer_fragment_construction(
  occurrence : ClientInferOccurrence,
  step : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  serialization_boundary? : Int? = None,
) -> Result[
  (ClientTaskFragmentConstruction, ClientTaskPipelineInput),
  ClientTaskFragmentIssue,
] {
  let owner = occurrence.preparation
  guard step >= 0 &&
    step != occurrence.step &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(output) else {
    return Err(MissingOutput)
  }
  let before = step < occurrence.step
  let selected = if before { None } else { Some(step) }
  let input = match
    prepare_client_task_pipeline_input(
      owner,
      step,
      @lower.node_id(output),
      selected,
      if before {
        Some(step)
      } else {
        None
      },
      before,
      sequence_limits,
      infer_boundary=if before { None } else { Some(occurrence.step) },
      serialization_boundary=if before { None } else { serialization_boundary },
    ) {
    Err(issue) => return Err(Pipeline(issue))
    Ok(value) => value
  }
  let name = if before {
    "task_" +
    occurrence.task.to_string() +
    "_before_infer_" +
    occurrence.step.to_string()
  } else {
    "task_" + occurrence.task.to_string() + "_after_infer_" + step.to_string()
  }
  measure_client_task_fragment_construction(
    owner,
    @pipeline.Step(step),
    selected,
    name,
    input,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map(geometry => (geometry, input))
}

///|
// Issue from the SAME lowering/emission retained during construction sizing.
// No second prepare_sequence/prepare_sequence_prefix enters this path.
fn issue_constructed_client_infer_fragment(
  occurrence : ClientInferOccurrence,
  step : Int,
  input : ClientTaskPipelineInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  let owner = occurrence.preparation
  let before = step < occurrence.step
  let selected = if before { None } else { Some(step) }
  guard physical_equal(input.owner, owner) &&
    input.end_step == step &&
    input.selected == selected &&
    input.prefix_end == (if before { Some(step) } else { None }) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(output) &&
    input.output == @lower.node_id(output) else {
    return Err(MissingOutput)
  }
  let construction = match
    construct_client_task_pipeline(input, max_wire_bytes, max_nodes, max_depth) {
    Ok(value) => value
    Err(issue) => return Err(Pipeline(issue))
  }
  issue_client_task_fragment_body(
    owner,
    @pipeline.Step(step),
    selected,
    if before {
      "task_" +
      occurrence.task.to_string() +
      "_before_infer_" +
      occurrence.step.to_string()
    } else {
      "task_" + occurrence.task.to_string() + "_after_infer_" + step.to_string()
    },
    construction,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}

///|
// The existing Content consumer lowering, retained before the enclosing Model
// issuer. The byte producer remains the same component, never REL.serialize.
fn measure_client_serialized_infer_fragment_construction(
  occurrence : ClientInferOccurrence,
  component : ClientSerializationPlanGraph,
  step : Int,
  sequence_limits : @lower.SequenceLimits,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientTaskFragmentConstruction, ClientTaskPipelineInput),
  ClientTaskFragmentIssue,
] {
  let owner = occurrence.preparation
  guard physical_equal(component.owner, occurrence.owner) &&
    physical_equal(@lower.serialization_owner(component.barrier), owner) &&
    component.task == occurrence.task &&
    component.step < step &&
    step < occurrence.step &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(output) else {
    return Err(MissingOutput)
  }
  let input = match
    prepare_client_task_pipeline_input(
      owner,
      step,
      @lower.node_id(output),
      Some(step),
      None,
      false,
      sequence_limits,
      completed_serialization=Some((component.step, occurrence.step - 1)),
    ) {
    Err(issue) => return Err(Pipeline(issue))
    Ok(value) => value
  }
  measure_client_task_fragment_construction(
    owner,
    @pipeline.Step(step),
    Some(step),
    "task_" +
    occurrence.task.to_string() +
    "_after_serialize_" +
    step.to_string(),
    input,
    max_wire_bytes,
    max_nodes,
    max_depth,
  ).map(geometry => (geometry, input))
}

///|
// Consume the SAME already lowered Content consumer during Graph issuance.
// Nominal original checks below do not re-lower or reconstruct a byte producer.
fn issue_constructed_client_serialized_infer_fragment(
  occurrence : ClientInferOccurrence,
  component : ClientSerializationPlanGraph,
  step : Int,
  input : ClientTaskPipelineInput,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[ClientTaskFragmentNode, ClientTaskFragmentIssue] {
  let owner = occurrence.preparation
  guard physical_equal(component.owner, occurrence.owner) &&
    physical_equal(@lower.serialization_owner(component.barrier), owner) &&
    component.task == occurrence.task &&
    component.step < step &&
    step < occurrence.step &&
    physical_equal(input.owner, owner) &&
    input.end_step == step &&
    input.selected == Some(step) &&
    input.prefix_end is None &&
    input.first_sequence_step == step &&
    input.sequence_end == step + 1 &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(output) &&
    input.output == @lower.node_id(output) else {
    return Err(MissingOutput)
  }
  let construction = match
    construct_client_task_pipeline(input, max_wire_bytes, max_nodes, max_depth) {
    Err(issue) => return Err(Pipeline(issue))
    Ok(value) => value
  }
  issue_client_task_fragment_body(
    owner,
    @pipeline.Step(step),
    Some(step),
    "task_" +
    occurrence.task.to_string() +
    "_after_serialize_" +
    step.to_string(),
    construction,
    max_wire_bytes,
    max_nodes,
    max_depth,
  )
}
