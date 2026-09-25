///|
/// Adapt the exact bounded selected-row evaluator for the legacy synchronous
/// fixed-compute API. Standard managed execution advances the same evaluator
/// through the Host driver instead of draining it here.
pub fn execute_selected_relation_step(
  generated : GeneratedSequence,
  input : ProducerRead,
  limits : SequenceExecutionLimits,
) -> Result[(CompletedOutput, Int64), (SequenceRunIssue, Int64)] {
  guard generated.selected_steps is Some([step]) &&
    producer_read_matches_operation_input(
      input,
      @lower.sequence_owner(generated.sequence),
      step,
      0,
    ) else {
    return Err((InputSet, 0L))
  }
  let session = match
    start_bounded_binding_rows(
      @bounded.control(),
      generated,
      input,
      limits.rows.max_rows,
      limits.rows.input_values,
      limits.rows.output_values,
      limits.max_work,
      limits.max_frames,
      limits.rows.operation_entries,
      limits.rows.output_values.max_text_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err((selected_relation_issue(step, issue), 0L))
  }
  let mut consumed = 0L
  while true {
    match advance_bounded_binding_rows(session, 1024) {
      Ok(BoundedBindingRowsContinue(work~, ..)) => consumed = work
      Ok(BoundedBindingRowsComplete(output, work~, ..)) => {
        cleanup_bounded_binding_rows(session) |> ignore
        return Ok((output, work))
      }
      Ok(BoundedBindingRowsFailed(issue, work~, ..)) => {
        cleanup_bounded_binding_rows(session) |> ignore
        return Err((selected_relation_issue(step, issue), work))
      }
      Ok(BoundedBindingRowsStopped(_, work~, ..)) => {
        cleanup_bounded_binding_rows(session) |> ignore
        return Err((InputSet, work))
      }
      Err(issue) => {
        cleanup_bounded_binding_rows(session) |> ignore
        return Err((selected_relation_issue(step, issue), consumed))
      }
    }
  }
  Err((InputSet, consumed))
}

///|
fn selected_relation_issue(
  step : Int,
  issue : BoundedBindingRowsIssue,
) -> SequenceRunIssue {
  match issue {
    InputLimit => InputLimit
    UnsupportedDistinctField(name) => UnsupportedRowComparison(step, name)
    Rows(rows) => Rows(step, rows)
    Capture(capture) => Capture(step, capture)
    InvalidExecution | Completion(_) | Execution(_) => InputSet
  }
}
