///|
/// Bind the acquisition output contract to the exact completed pure prefix.
/// Infer remains outside AoA: this selects only its checked output target and
/// grants no success authority. The installed ModelTask owner must verify it.
pub fn prepare_infer_completion(
  prefix : GeneratedSequence,
  rows : PreparedInferRows,
  step : Int,
) -> CompletionPreparation? {
  let owner = generated_sequence_owner(prefix)
  let prepared = @lower.bound_preparation(owner)
  guard step > 0 &&
    @lower.sequence_count(prefix.sequence) == step &&
    physical_equal(rows.input.expected, owner) &&
    rows.input.target == @pipeline.Step(step - 1) &&
    rows.input.source is CompletedInput(_) &&
    !rows.reclaimed &&
    infer_rows_available(rows.input) &&
    @lower.node_at(prepared, step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) &&
    physical_equal(infer, prepared_infer_rows_owner(rows)) &&
    @lower.node_input_count(node) == 1 &&
    @lower.node_input_target(node, 0) == Some(rows.input.target) else {
    return None
  }
  Some({
    contracts: prefix.contracts,
    sequence: prefix.sequence,
    retained_ids: [@lower.node_id(node)],
    selected_step: Some(step),
    selected_terminal_step: Some(step),
  })
}

///|
pub fn infer_completion_matches_rows(
  value : CompletionPreparation,
  rows : PreparedInferRows,
) -> Bool {
  let step = completion_preparation_terminal_step(value)
  let owner = completion_preparation_owner(value)
  let prepared = @lower.bound_preparation(owner)
  guard !rows.reclaimed &&
    physical_equal(rows.input.expected, owner) &&
    rows.input.target == @pipeline.Step(step - 1) &&
    @lower.node_at(prepared, step) is Some(node) &&
    @lower.payload(node) is @lower.Infer(infer) else {
    return false
  }
  value.selected_step == Some(step) &&
  value.selected_terminal_step == Some(step) &&
  value.retained_ids == [@lower.node_id(node)] &&
  physical_equal(infer, prepared_infer_rows_owner(rows))
}
