///|
// Pure compiler inputs belonging to one original checked keyed join. Retained
// sequences and port indices are not completed rows, access or an IO grant.
priv struct ClientKeyedPlanFragmentInputs {
  occurrence : ClientInferOccurrence
  acquisition : ClientKeyedAcquisition
  left : ClientTaskPipelineInput
  joined : ClientTaskPipelineInput
  left_sources : Array[Int]
  left_target : @pipeline.Target
  join_step : Int
  final_step : Int
  left_node_id : String
  joined_node_id : String
}

///|
fn client_keyed_plan_acquisition_matches(
  acquisition : ClientKeyedAcquisition,
  occurrence : ClientInferOccurrence,
) -> Bool {
  (match acquisition.program {
    KeyedPure(original) => physical_equal(original, occurrence.owner)
    KeyedEffect(original) =>
      client_infer_occurrence_matches_effect(occurrence, original)
  }) &&
  physical_equal(acquisition.owner, occurrence.preparation)
}

///|
// Project the exact original source ports referenced by the already selected
// prefix sequence. Do not infer them from aliases, a second Program parse or
// the current provider. This also prevents a future right input from becoming
// an unused input of its own left producer (and therefore a cyclic Plan edge).
fn client_keyed_prefix_sources(
  input : ClientTaskPipelineInput,
  max_nodes : Int,
) -> Result[Array[Int], ClientTaskFragmentIssue] {
  let prepared = @lower.bound_preparation(input.owner)
  let pipeline = @lower.pipeline(prepared)
  let count = @pipeline.input_count(pipeline)
  if count < 0 || count > max_nodes || input.end_step < 0 {
    return Err(InvalidLimits)
  }
  let selected = Array::make(count, false)
  for step in 0..<(input.end_step + 1) {
    guard @lower.sequence_canonical_node_count(input.sequence, step)
      is Some(nodes) else {
      continue
    }
    if nodes == 0 {
      continue
    }
    guard @lower.node_at(prepared, step) is Some(node) else {
      return Err(MissingTask)
    }
    for port in 0..<@lower.node_input_count(node) {
      guard @lower.node_input_target(node, port) is Some(target) else {
        return Err(MissingTask)
      }
      if target is @pipeline.Input(index) {
        if index < 0 || index >= count {
          return Err(MissingTask)
        }
        selected[index] = true
      }
    }
  }
  let sources = []
  for index in 0..<count {
    if selected[index] {
      sources.push(index)
    }
  }
  Ok(sources)
}

///|
// The same prefix and selected-range lowering as the actual Model compiler.
// No completion boundary is synthesized: the checked keyed join consumes the
// real left and right ports, and the following pure steps keep their order.
fn prepare_client_keyed_plan_fragment_inputs(
  occurrence : ClientInferOccurrence,
  acquisition : ClientKeyedAcquisition,
  sequence_limits : @lower.SequenceLimits,
  max_nodes : Int,
) -> Result[ClientKeyedPlanFragmentInputs, ClientInferPlanGraphIssue] {
  guard client_infer_occurrence_matches(occurrence, occurrence.owner) &&
    client_keyed_plan_acquisition_matches(acquisition, occurrence) &&
    physical_equal(acquisition.owner, occurrence.preparation) &&
    acquisition.binding.stage == occurrence.stage else {
    return Err(UnsupportedProgram)
  }
  let left_target = @acquisition.keyed_join_left(acquisition.binding.join)
  let join_step = @acquisition.keyed_join_step(acquisition.binding.join)
  let final_step = occurrence.step - 1
  let prepared = @lower.bound_preparation(occurrence.preparation)
  guard join_step <= final_step &&
    @lower.node_at(prepared, final_step) is Some(final_node) else {
    return Err(UnsupportedProgram)
  }
  let (left_step, left_output) = match left_target {
    @pipeline.Step(step) => {
      guard step >= 0 &&
        step < join_step &&
        @lower.node_at(prepared, step) is Some(node) else {
        return Err(UnsupportedProgram)
      }
      (step, @lower.node_id(node))
    }
    @pipeline.Input(index) => {
      guard @pipeline.input_at(@lower.pipeline(prepared), index)
        is Some((name, _)) else {
        return Err(UnsupportedProgram)
      }
      // An already checked input needs no preceding operation. Its empty
      // prefix retains the same bound owner and original input port.
      (-1, name)
    }
  }
  let left = match
    prepare_client_task_pipeline_input(
      occurrence.preparation,
      left_step,
      left_output,
      None,
      Some(left_step),
      true,
      sequence_limits,
      original_input=match left_target {
        @pipeline.Input(index) => Some(index)
        @pipeline.Step(_) => None
      },
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(Pipeline(issue)))
  }
  let joined = match
    prepare_client_task_pipeline_input(
      occurrence.preparation,
      final_step,
      @lower.node_id(final_node),
      Some(join_step),
      Some(final_step),
      true,
      sequence_limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(Pipeline(issue)))
  }
  let left_sources = match left_target {
    @pipeline.Input(index) => [index]
    @pipeline.Step(_) =>
      match client_keyed_prefix_sources(left, max_nodes) {
        Ok(value) => value
        Err(issue) => return Err(Input(issue))
      }
  }
  let prefix = "task_" +
    occurrence.task.to_string() +
    "_lookup_" +
    join_step.to_string()
  Ok({
    occurrence,
    acquisition,
    left,
    joined,
    left_sources,
    left_target,
    join_step,
    final_step,
    left_node_id: prefix + "_left",
    joined_node_id: prefix + "_joined",
  })
}

///|
// Both measurements use the same filtered emitter as construction. Their
// containing Request must reserve the complete simultaneous geometry before
// the issuer runs; a tuple of byte counts is not a capacity token.
fn measure_client_keyed_plan_fragments(
  original : ClientKeyedPlanFragmentInputs,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientTaskFragmentConstruction, ClientTaskFragmentConstruction),
  ClientInferPlanGraphIssue,
] {
  let before = match
    measure_client_task_fragment_construction(
      original.occurrence.preparation,
      original.left_target,
      None,
      original.left_node_id,
      original.left,
      max_wire_bytes,
      max_nodes,
      max_depth,
      source_selection=Some(original.left_sources),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let joined = match
    measure_client_task_fragment_construction(
      original.occurrence.preparation,
      @pipeline.Step(original.final_step),
      Some(original.join_step),
      original.joined_node_id,
      original.joined,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  Ok((before, joined))
}

///|
fn issue_client_keyed_plan_fragments(
  original : ClientKeyedPlanFragmentInputs,
  max_wire_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  (ClientTaskFragmentNode, ClientTaskFragmentNode),
  ClientInferPlanGraphIssue,
] {
  let before = match
    construct_client_task_pipeline(
      original.left,
      max_wire_bytes,
      max_nodes,
      max_depth,
      source_selection=Some(original.left_sources),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(Pipeline(issue)))
  }
  let joined = match
    construct_client_task_pipeline(
      original.joined,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(Pipeline(issue)))
  }
  let before = match
    issue_client_task_fragment_body(
      original.occurrence.preparation,
      original.left_target,
      None,
      original.left_node_id,
      before,
      max_wire_bytes,
      max_nodes,
      max_depth,
      source_selection=Some(original.left_sources),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  let joined = match
    issue_client_task_fragment_body(
      original.occurrence.preparation,
      @pipeline.Step(original.final_step),
      Some(original.join_step),
      original.joined_node_id,
      joined,
      max_wire_bytes,
      max_nodes,
      max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Input(issue))
  }
  Ok((before, joined))
}
