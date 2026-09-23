///|
fn bounded_values_issue(
  issue : @execution.BoundedValuesIssue,
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
fn values_provider(
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> ManagedProvider {
  managed_provider(
    sequence => {
      @execution.generated_sequence_step_index_at(sequence, 0) is Some(_) &&
      @execution.generated_sequence_step_index_at(sequence, 1) is None &&
      @execution.generated_sequence_step_at(sequence, 0)
      is Some(@lower.ValuesStep(_))
    },
    sequence => {
      @execution.generated_sequence_capacity(sequence, limits, measurement)
    },
    (sequence, inputs, max_rows, max_value_bytes, execution) => {
      guard inputs is [] &&
        @execution.generated_sequence_step_index_at(sequence, 0) is Some(step) else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let control = @bounded.control()
      let active = match
        @execution.start_bounded_values(
          control,
          sequence,
          max_rows,
          execution.rows.input_values,
          execution.rows.output_values,
          execution.max_work,
          execution.max_frames,
          execution.rows.operation_entries,
          max_value_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(bounded_values_issue(issue, step))
      }
      let terminated = Ref(false)
      let reclaimed = Ref(false)
      let progress = Ref(0L)
      let work = Ref(0L)
      Ok(
        managed_provider_execution(
          quantum => {
            if quantum <= 0 || terminated.val {
              return Err(@connector.InvalidLimits)
            }
            let poll = match
              @execution.advance_bounded_values(active, quantum) {
              Ok(value) => value
              Err(issue) => {
                terminated.val = true
                return Ok(
                  managed_provider_failed(
                    bounded_values_issue(issue, step),
                    0L,
                    0L,
                  ),
                )
              }
            }
            let (next_progress, next_work, terminal) = match poll {
              @execution.BoundedValuesContinue(progress~, work~) =>
                (progress, work, false)
              @execution.BoundedValuesComplete(_, progress~, work~)
              | @execution.BoundedValuesFailed(_, progress~, work~)
              | @execution.BoundedValuesStopped(_, progress~, work~) =>
                (progress, work, true)
            }
            if next_progress < progress.val || next_work < work.val {
              terminated.val = true
              return Ok(
                managed_provider_failed(
                  @connector.Execution(@execution.InputSet),
                  0L,
                  0L,
                ),
              )
            }
            let progress_delta = next_progress - progress.val
            let work_delta = next_work - work.val
            progress.val = next_progress
            work.val = next_work
            if terminal {
              terminated.val = true
            }
            match poll {
              @execution.BoundedValuesContinue(_) =>
                Ok(managed_provider_continue(progress_delta, work_delta))
              @execution.BoundedValuesComplete(output, ..) =>
                Ok(
                  managed_provider_complete(output, progress_delta, work_delta),
                )
              @execution.BoundedValuesFailed(issue, ..) =>
                Ok(
                  managed_provider_failed(
                    bounded_values_issue(issue, step),
                    progress_delta,
                    work_delta,
                  ),
                )
              @execution.BoundedValuesStopped(_, ..) =>
                Ok(managed_provider_stopped_poll(progress_delta, work_delta))
            }
          },
          fn() { @bounded.request_cancel(control) },
          fn() { terminated.val },
          fn() {
            if !terminated.val {
              return Ok(false)
            }
            if reclaimed.val {
              return Ok(true)
            }
            match @execution.cleanup_bounded_values(active) {
              Ok(true) => {
                reclaimed.val = true
                Ok(true)
              }
              Ok(false) => Ok(false)
              Err(issue) => Err(bounded_values_issue(issue, step))
            }
          },
        ),
      )
    },
  )
}
