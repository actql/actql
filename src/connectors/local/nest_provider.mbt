///|
fn bounded_nest_issue(
  issue : @execution.BoundedNestIssue,
  step : Int,
) -> @connector.FixedComputeIssue {
  match issue {
    @execution.InputLimit => @connector.Execution(@execution.InputLimit)
    @execution.Rows(row_issue) =>
      @connector.Execution(@execution.Rows(step, row_issue))
    @execution.Capture(capture_issue) =>
      @connector.Execution(@execution.Capture(step, capture_issue))
    _ => @connector.Execution(@execution.InputSet)
  }
}

///|
/// Indexed parent-major nest over parent and child managed reads.
fn nest_provider(
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> ManagedProvider {
  managed_provider(
    sequence => {
      guard @execution.generated_sequence_step_index_at(sequence, 0)
        is Some(step) &&
        @execution.generated_sequence_step_index_at(sequence, 1) is None &&
        @execution.generated_sequence_step_at(sequence, 0)
        is Some(@lower.NestStep(_)) else {
        return false
      }
      @lower.node_at(
        @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
        step,
      )
      is Some(_)
    },
    sequence => {
      @execution.generated_sequence_capacity(sequence, limits, measurement)
    },
    (sequence, inputs, _max_rows, max_value_bytes, execution) => {
      guard inputs is [parent, child] &&
        @execution.generated_sequence_step_index_at(sequence, 0) is Some(step) else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let control = @bounded.control()
      let active = match
        @execution.start_bounded_nest(
          control,
          sequence,
          parent,
          child,
          execution.rows.max_rows,
          execution.rows.input_values,
          execution.rows.output_values,
          execution.max_work,
          execution.max_frames,
          execution.rows.operation_entries,
          max_value_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(bounded_nest_issue(issue, step))
      }
      Ok(
        bounded_session_execution(
          quantum => {
            match @execution.advance_bounded_nest(active, quantum) {
              Err(issue) => Err(bounded_nest_issue(issue, step))
              Ok(@execution.BoundedNestContinue(progress~, work~)) =>
                Ok(SessionContinue(progress, work))
              Ok(@execution.BoundedNestComplete(output, progress~, work~)) =>
                Ok(SessionComplete(output, progress, work))
              Ok(@execution.BoundedNestFailed(issue, progress~, work~)) =>
                Ok(
                  SessionFailed(bounded_nest_issue(issue, step), progress, work),
                )
              Ok(@execution.BoundedNestStopped(_, progress~, work~)) =>
                Ok(SessionStopped(progress, work))
            }
          },
          fn() { @bounded.request_cancel(control) },
          fn() {
            @execution.cleanup_bounded_nest(active).map_err(issue => {
              bounded_nest_issue(issue, step)
            })
          },
        ),
      )
    },
  )
}
