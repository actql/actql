///|
fn selected_join_issue(
  issue : @execution.BoundedJoinIssue,
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
fn selected_join_execution(
  sequence : @execution.GeneratedSequence,
  inputs : Array[ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  max_value_bytes : Int,
  step : Int,
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  let control = @bounded.control()
  guard inputs is [left, right] else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  let project = fn(input : ManagedProviderInput) {
    match input {
      RelationInput(read) =>
        Some(@execution.trusted_output_relation_input(read))
      SuppliedRelationInput(read) =>
        Some(@execution.trusted_output_supplied_relation_input(read))
      CarrierInput(_) => None
    }
  }
  guard project(left) is Some(left) && project(right) is Some(right) else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  let started = @execution.start_bounded_join(
    control,
    sequence,
    left,
    right,
    execution.rows.max_rows,
    execution.rows.input_values,
    execution.rows.output_values,
    execution.max_work,
    execution.max_frames,
    execution.rows.operation_entries,
    max_value_bytes,
  )
  let active = match started {
    Ok(value) => value
    Err(issue) => return Err(selected_join_issue(issue, step))
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
        let poll = match @execution.advance_bounded_join(active, quantum) {
          Ok(value) => value
          Err(issue) => {
            terminated.val = true
            return Ok(
              managed_provider_failed(selected_join_issue(issue, step), 0L, 0L),
            )
          }
        }
        let (next_progress, next_work, terminal) = match poll {
          @execution.BoundedJoinContinue(progress~, work~) =>
            (progress, work, false)
          @execution.BoundedJoinComplete(_, progress~, work~)
          | @execution.BoundedJoinFailed(_, progress~, work~)
          | @execution.BoundedJoinStopped(_, progress~, work~) =>
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
          @execution.BoundedJoinContinue(_) =>
            Ok(managed_provider_continue(progress_delta, work_delta))
          @execution.BoundedJoinComplete(output, ..) =>
            Ok(managed_provider_complete(output, progress_delta, work_delta))
          @execution.BoundedJoinFailed(issue, ..) =>
            Ok(
              managed_provider_failed(
                selected_join_issue(issue, step),
                progress_delta,
                work_delta,
              ),
            )
          @execution.BoundedJoinStopped(_, ..) =>
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
        match @execution.cleanup_bounded_join(active) {
          Ok(true) => {
            reclaimed.val = true
            Ok(true)
          }
          Ok(false) => Ok(false)
          Err(issue) => Err(selected_join_issue(issue, step))
        }
      },
    ),
  )
}
