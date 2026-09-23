///|
fn bounded_append_issue(
  issue : @execution.BoundedAppendIssue,
  step : Int,
) -> @connector.FixedComputeIssue {
  match issue {
    @execution.Rows(row_issue) =>
      @connector.Execution(@execution.Rows(step, row_issue))
    @execution.Capture(capture_issue) =>
      @connector.Execution(@execution.Capture(step, capture_issue))
    _ => @connector.Execution(@execution.InputSet)
  }
}

///|
fn append_provider(
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> ManagedProvider {
  managed_provider(
    sequence => {
      guard @execution.generated_sequence_step_index_at(sequence, 0)
        is Some(step) &&
        @execution.generated_sequence_step_index_at(sequence, 1) is None &&
        @execution.generated_sequence_step_at(sequence, 0)
        is Some(@lower.AppendStep(_)) else {
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
      guard inputs is [left, right] &&
        @execution.generated_sequence_step_index_at(sequence, 0) is Some(step) else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let control = @bounded.control()
      let active = match
        @execution.start_bounded_append(
          control,
          sequence,
          left,
          right,
          execution.rows.max_rows,
          execution.rows.output_values,
          execution.max_work,
          execution.max_frames,
          execution.rows.operation_entries,
          max_value_bytes,
        ) {
        Ok(value) => value
        Err(issue) => return Err(bounded_append_issue(issue, step))
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
              @execution.advance_bounded_append(active, quantum) {
              Ok(value) => value
              Err(issue) => {
                terminated.val = true
                return Ok(
                  managed_provider_failed(
                    bounded_append_issue(issue, step),
                    0L,
                    0L,
                  ),
                )
              }
            }
            let (next_progress, next_work, terminal) = match poll {
              @execution.BoundedAppendContinue(progress~, work~) =>
                (progress, work, false)
              @execution.BoundedAppendComplete(_, progress~, work~)
              | @execution.BoundedAppendFailed(_, progress~, work~)
              | @execution.BoundedAppendStopped(_, progress~, work~) =>
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
              @execution.BoundedAppendContinue(_) =>
                Ok(managed_provider_continue(progress_delta, work_delta))
              @execution.BoundedAppendComplete(output, ..) =>
                Ok(
                  managed_provider_complete(output, progress_delta, work_delta),
                )
              @execution.BoundedAppendFailed(issue, ..) =>
                Ok(
                  managed_provider_failed(
                    bounded_append_issue(issue, step),
                    progress_delta,
                    work_delta,
                  ),
                )
              @execution.BoundedAppendStopped(_, ..) =>
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
            match @execution.cleanup_bounded_append(active) {
              Ok(true) => {
                reclaimed.val = true
                Ok(true)
              }
              Ok(false) => Ok(false)
              Err(issue) => Err(bounded_append_issue(issue, step))
            }
          },
        ),
      )
    },
  )
}
