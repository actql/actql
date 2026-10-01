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
  guard step > 0 &&
    @lower.sequence_count(prefix.sequence) == step &&
    physical_equal(rows.input.expected, owner) &&
    rows.input.target == @pipeline.Step(step - 1) &&
    rows.input.source is CompletedInput(_) &&
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
    contracts: prefix.contracts,
    sequence: prefix.sequence,
    retained_ids: [output_id],
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
