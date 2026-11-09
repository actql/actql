///|
/// Bind the acquisition output contract to the selected completed prefix.
/// Infer remains outside AoA: this selects only its checked output target and
/// grants no success authority. A retained sequence can include later checked
/// steps; its selected logical endpoint, not its whole node count, must be the
/// original pre-Infer producer. The installed ModelTask owner must verify it.
pub fn prepare_infer_completion(
  prefix : GeneratedSequence,
  rows : PreparedInferRows,
  step : Int,
) -> CompletionPreparation? {
  let owner = generated_sequence_owner(prefix)
  let count = generated_sequence_step_count(prefix)
  guard step > 0 &&
    count > 0 &&
    generated_sequence_step_index_at(prefix, count - 1) == Some(step - 1) &&
    physical_equal(rows.input.expected, owner) else {
    return None
  }
  prepare_completed_infer_completion(rows, step)
}

///|
/// Reuse the exact completion borrowed during mapping, including a checked
/// Content producer or restored input. This does not execute that producer,
/// manufacture a pure prefix, or grant Model success authority. Its original
/// physical owner must keep the input available until the consumer settles.
pub fn prepare_completed_infer_completion(
  rows : PreparedInferRows,
  step : Int,
) -> CompletionPreparation? {
  let owner = rows.input.expected
  guard step > 0 &&
    rows.input.target == @pipeline.Step(step - 1) &&
    rows.input.source is CompletedInput(input) &&
    !rows.reclaimed &&
    infer_rows_available(rows.input) &&
    @lower.infer_output_binding(
      owner,
      step,
      prepared_infer_rows_owner(rows),
      rows.input.target,
    )
    is Some(output_id) else {
    return None
  }
  Some({
    contracts: input.completion.contracts,
    sequence: input.completion.sequence,
    retained_ids: [output_id],
    selected_step: Some(step),
    selected_terminal_step: Some(step),
    serialization_output: None,
  })
}

///|
pub fn infer_completion_matches_rows(
  value : CompletionPreparation,
  rows : PreparedInferRows,
) -> Bool {
  let step = completion_preparation_terminal_step(value)
  let owner = completion_preparation_owner(value)
  guard !rows.reclaimed &&
    physical_equal(rows.input.expected, owner) &&
    rows.input.target == @pipeline.Step(step - 1) &&
    @lower.infer_output_binding(
      owner,
      step,
      prepared_infer_rows_owner(rows),
      rows.input.target,
    )
    is Some(output_id) else {
    return false
  }
  value.selected_step == Some(step) &&
  value.selected_terminal_step == Some(step) &&
  value.retained_ids == [output_id]
}
