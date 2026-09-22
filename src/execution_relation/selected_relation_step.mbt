///|
/// Execute one checked unary Relation occurrence selected by common physical
/// segmentation. The read retains the internal Step use site; it is not
/// relabeled as an authored pipeline input.
pub fn execute_selected_relation_step(
  generated : GeneratedSequence,
  input : ProducerRead,
  limits : SequenceExecutionLimits,
) -> Result[(CompletedOutput, Int64), (SequenceRunIssue, Int64)] {
  guard generated.selected_steps is Some([step]) &&
    @lower.sequence_step(generated.sequence, step)
    is Some(@lower.RowStep(kernel)) &&
    @lower.node_at(
      @lower.bound_preparation(@lower.sequence_owner(generated.sequence)),
      step,
    )
    is Some(node) &&
    @lower.node_accepts_managed_relation_view(node, 0) &&
    producer_read_matches_operation_input(
      input,
      @lower.sequence_owner(generated.sequence),
      step,
      0,
    ) &&
    input.bound.output.table is Some(source) else {
    return Err((InputSet, 0L))
  }
  if limits.max_work < 0 ||
    limits.rows.max_rows < 0 ||
    limits.rows.operation_entries < 0 {
    return Err((InvalidLimits, 0L))
  }
  let control = { remaining: limits.max_work, max_frames: limits.max_frames, }
  let input_budget = match value_budget(limits.rows.input_values) {
    Ok(value) => value
    Err(_) => return Err((InvalidLimits, 0L))
  }
  let output_budget = match value_budget(limits.rows.output_values) {
    Ok(value) => value
    Err(_) => return Err((InvalidLimits, 0L))
  }
  let mut logical : LogicalBudget? = None
  for context in generated.contexts {
    if physical_equal(context.kernel, kernel) {
      if logical is Some(_) {
        return Err((InputSet, 0L))
      }
      logical = match fragment_runtime_for_kernel(context, kernel) {
        Ok(value) => Some(value)
        Err(_) => return Err((InputSet, 0L))
      }
    }
  }
  if !charge_completed_rows(source, limits.rows.max_rows, control, input_budget) {
    return Err((InputLimit, (limits.max_work - control.remaining).to_int64()))
  }
  let result = match
    evaluate_completed_rows(
      kernel,
      source,
      limits.rows.max_rows,
      control,
      output_budget,
      { limit: limits.rows.operation_entries, live: 0, peak: 0, },
      logical,
      identity_limits=Some(limits.rows.input_values),
    ) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        (Rows(step, issue), (limits.max_work - control.remaining).to_int64()),
      )
  }
  if !producer_read_available(input) {
    return Err(
      (InputOwnership, (limits.max_work - control.remaining).to_int64()),
    )
  }
  let owner = @lower.sequence_owner(generated.sequence)
  let target = @pipeline.Step(step)
  let completion : CompletedSequence = {
    result_identity: Ref(()),
    readmitted: false,
    contracts: generated.contracts,
    sequence: generated.sequence,
    store: ImportedStore(
      @lower.preparation_input_count(@lower.bound_preparation(owner)),
      target,
      result,
    ),
    _producer_inputs: [input.bound],
    input_bindings: [input.bound.identity],
    live: None,
  }
  Ok(
    (
      { completion, target, table: Some(result), representation: None, },
      (limits.max_work - control.remaining).to_int64(),
    ),
  )
}
