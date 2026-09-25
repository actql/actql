///|
fn bounded_unpivot_issue(
  issue : @execution.BoundedUnpivotIssue,
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
fn unpivot_provider(
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> ManagedProvider {
  managed_provider_with_inputs(
    sequence => {
      guard @execution.generated_sequence_step_index_at(sequence, 0)
        is Some(step) &&
        @execution.generated_sequence_step_index_at(sequence, 1) is None &&
        @execution.generated_sequence_step_at(sequence, 0)
        is Some(@lower.RowStep(kernel)) &&
        @lower.kernel_unpivot_outputs(kernel) is Some(_) else {
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
          @execution.start_bounded_unpivot(
            control,
            sequence,
            read,
            execution.rows.max_rows,
            execution.rows.input_values,
            execution.rows.output_values,
            execution.max_work,
            execution.max_frames,
            execution.rows.operation_entries,
            max_value_bytes,
          )
        SuppliedRelationInput(read) =>
          @execution.start_bounded_unpivot_supplied(
            control,
            sequence,
            read,
            execution.rows.max_rows,
            execution.rows.input_values,
            execution.rows.output_values,
            execution.max_work,
            execution.max_frames,
            execution.rows.operation_entries,
            max_value_bytes,
          )
        CarrierInput(_) => return Err(@connector.Execution(@execution.InputSet))
      }
      let active = match started {
        Ok(value) => value
        Err(issue) => return Err(bounded_unpivot_issue(issue, step))
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
              @execution.advance_bounded_unpivot(active, quantum) {
              Ok(value) => value
              Err(issue) => {
                terminated.val = true
                return Ok(
                  managed_provider_failed(
                    bounded_unpivot_issue(issue, step),
                    0L,
                    0L,
                  ),
                )
              }
            }
            let (next_progress, next_work, terminal) = match poll {
              @execution.BoundedUnpivotContinue(progress~, work~) =>
                (progress, work, false)
              @execution.BoundedUnpivotComplete(_, progress~, work~)
              | @execution.BoundedUnpivotFailed(_, progress~, work~)
              | @execution.BoundedUnpivotStopped(_, progress~, work~) =>
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
              @execution.BoundedUnpivotContinue(_) =>
                Ok(managed_provider_continue(progress_delta, work_delta))
              @execution.BoundedUnpivotComplete(output, ..) =>
                Ok(
                  managed_provider_complete(output, progress_delta, work_delta),
                )
              @execution.BoundedUnpivotFailed(issue, ..) =>
                Ok(
                  managed_provider_failed(
                    bounded_unpivot_issue(issue, step),
                    progress_delta,
                    work_delta,
                  ),
                )
              @execution.BoundedUnpivotStopped(_, ..) =>
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
            match @execution.cleanup_bounded_unpivot(active) {
              Ok(true) => {
                reclaimed.val = true
                Ok(true)
              }
              Ok(false) => Ok(false)
              Err(issue) => Err(bounded_unpivot_issue(issue, step))
            }
          },
        ),
      )
    },
  )
}
