///|
/// The narrow physical acquisition lane executes a two-step checked prefix.
/// Every external dependency must be this exact original input; downstream
/// Stage inputs are not silently promoted into completed input evidence.
fn acquisition_prefix_input(
  output : CompletedOutput,
  sequence : GeneratedSequence,
) -> Int? {
  let owner = generated_sequence_owner(sequence)
  guard !output.completion.readmitted &&
    completed_output_available(output) &&
    physical_equal(@lower.sequence_owner(output.completion.sequence), owner) &&
    generated_sequence_step_count(sequence) == 2 &&
    generated_sequence_step_index_at(sequence, 0) == Some(0) &&
    generated_sequence_step_index_at(sequence, 1) == Some(1) &&
    output.target == @pipeline.Step(1) else {
    return None
  }
  let prepared = @lower.bound_preparation(owner)
  guard @lower.node_at(prepared, 0) is Some(first) &&
    @lower.node_at(prepared, 1) is Some(second) &&
    @lower.node_input_count(first) == 1 &&
    @lower.node_input_count(second) == 1 &&
    @lower.node_input_target(first, 0) is Some(@pipeline.Input(index)) &&
    @lower.node_input_target(second, 0) == Some(@pipeline.Step(0)) else {
    return None
  }
  Some(index)
}

///|
/// Seal only the actual supplied occurrence consumed by an admitted prefix.
/// Ordinary full-input provenance APIs retain their stricter full-Stage rule.
pub fn anchor_completed_acquisition_input(
  output : CompletedOutput,
  sequence : GeneratedSequence,
  input : SuppliedRelationRead,
) -> CompletedOutput? {
  guard acquisition_prefix_input(output, sequence) is Some(index) &&
    supplied_relation_read_matches_input(
      input,
      generated_sequence_owner(sequence),
      index,
    ) else {
    return None
  }
  Some({
    ..output,
    completion: { ..output.completion, input_bindings: [input.identity], },
  })
}

///|
pub fn completed_acquisition_matches_supplied_input(
  output : CompletedOutput,
  sequence : GeneratedSequence,
  input : SuppliedRelationRead,
) -> Bool {
  guard acquisition_prefix_input(output, sequence) is Some(index) &&
    physical_equal(input.receiver, generated_sequence_owner(sequence)) &&
    input.input_index == index &&
    output.completion.input_bindings.length() == 1 else {
    return false
  }
  physical_equal(output.completion.input_bindings[0], input.identity)
}

///|
/// Capture authority still belongs to the acquisition owner. This confirms the
/// immutable input occurrence, not equality of rows, contracts or request CIDs.
pub fn completed_acquisition_matches_captured_input(
  output : CompletedOutput,
  sequence : GeneratedSequence,
  input : CapturedRows,
) -> Bool {
  guard acquisition_prefix_input(output, sequence) is Some(index) &&
    output.completion.input_bindings.length() == 1 &&
    physical_equal(captured_owner(input), generated_sequence_owner(sequence)) &&
    captured_origin(input) == SuppliedInput(index) else {
    return false
  }
  let identity = output.completion.input_bindings[0]
  identity.carrier is None &&
  identity.input_index == index &&
  identity.supplied is Some(actual) &&
  physical_equal(actual, input)
}
