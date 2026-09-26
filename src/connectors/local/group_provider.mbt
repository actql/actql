///|
fn bounded_group_issue(
  issue : @execution.BoundedGroupIssue,
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
fn group_provider(
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> ManagedProvider {
  managed_provider_with_inputs(
    sequence => {
      guard @execution.generated_sequence_step_count(sequence) == 1 &&
        @execution.generated_sequence_step_index_at(sequence, 0) is Some(step) &&
        @execution.generated_sequence_step_at(sequence, 0)
        is Some(@lower.RowStep(kernel)) &&
        @lower.kernel_group(kernel) is Some(group) &&
        @execution.bounded_group_supported(group) else {
        return false
      }
      @lower.node_at(
        @lower.bound_preparation(@execution.generated_sequence_owner(sequence)),
        step,
      )
      .map(node => @lower.node_accepts_managed_relation_view(node, 0))
      .unwrap_or(false)
    },
    sequence => {
      @execution.generated_sequence_capacity(sequence, limits, measurement)
    },
    (sequence, inputs, _max_rows, max_value_bytes, execution) => {
      guard inputs is [input] &&
        @execution.generated_sequence_step_index_at(sequence, 0) is Some(step) else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      let control = @bounded.control()
      let started = match input {
        RelationInput(read) =>
          @execution.start_bounded_group_execution(
            control,
            sequence,
            read,
            execution.rows.max_rows,
            execution.rows.input_values,
            execution.rows.output_values,
            execution.rows.input_values,
            execution.max_work,
            execution.max_frames,
            execution.rows.operation_entries,
            max_value_bytes,
          )
        SuppliedRelationInput(read) =>
          @execution.start_bounded_group_execution_supplied(
            control,
            sequence,
            read,
            execution.rows.max_rows,
            execution.rows.input_values,
            execution.rows.output_values,
            execution.rows.input_values,
            execution.max_work,
            execution.max_frames,
            execution.rows.operation_entries,
            max_value_bytes,
          )
        CarrierInput(_) => return Err(@connector.Execution(@execution.InputSet))
      }
      let active = match started {
        Ok(value) => value
        Err(issue) => return Err(bounded_group_issue(issue, step))
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
              @execution.advance_bounded_group_execution(active, quantum) {
              Ok(value) => value
              Err(issue) => {
                terminated.val = true
                return Ok(
                  managed_provider_failed(
                    bounded_group_issue(issue, step),
                    0L,
                    0L,
                  ),
                )
              }
            }
            let (next_progress, next_work, terminal) = match poll {
              @execution.BoundedGroupContinue(progress~, work~) =>
                (progress, work, false)
              @execution.BoundedGroupComplete(_, progress~, work~)
              | @execution.BoundedGroupFailed(_, progress~, work~)
              | @execution.BoundedGroupStopped(_, progress~, work~) =>
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
              @execution.BoundedGroupContinue(_) =>
                Ok(managed_provider_continue(progress_delta, work_delta))
              @execution.BoundedGroupComplete(output, ..) =>
                Ok(
                  managed_provider_complete(output, progress_delta, work_delta),
                )
              @execution.BoundedGroupFailed(issue, ..) =>
                Ok(
                  managed_provider_failed(
                    bounded_group_issue(issue, step),
                    progress_delta,
                    work_delta,
                  ),
                )
              @execution.BoundedGroupStopped(_, ..) =>
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
            match @execution.cleanup_bounded_group_execution(active) {
              Ok(true) => {
                reclaimed.val = true
                Ok(true)
              }
              Ok(false) => Ok(false)
              Err(issue) => Err(bounded_group_issue(issue, step))
            }
          },
        ),
      )
    },
  )
}
