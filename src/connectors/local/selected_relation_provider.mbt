///|
/// Common Relation execution for one checked internal unary operation. Family
/// providers do not reinterpret or implement RelA after a Carrier bridge.
fn selected_binding_rows_supported(kernel : @lower.PreparedKernel) -> Bool {
  match @lower.kernel_body(kernel) {
    @lower.AssertAll(_)
    | @lower.AssertUnique(_)
    | @lower.SnapshotMap(_)
    | @lower.OrderedBindings(_)
    | @lower.Filter(_)
    | @lower.Select(_)
    | @lower.DistinctRows
    | @lower.StableSort(_)
    | @lower.TopK(_, _)
    | @lower.PartitionedTopK(_, _)
    | @lower.Limit(_, _, _) => true
    _ => false
  }
}

///|
fn selected_binding_rows_issue(
  issue : @execution.BoundedBindingRowsIssue,
  step : Int,
) -> @connector.FixedComputeIssue {
  match issue {
    @execution.InputLimit => @connector.Execution(@execution.InputLimit)
    @execution.UnsupportedDistinctField(name) =>
      @connector.Execution(@execution.UnsupportedRowComparison(step, name))
    @execution.Rows(row_issue) =>
      @connector.Execution(@execution.Rows(step, row_issue))
    @execution.Capture(capture_issue) =>
      @connector.Execution(@execution.Capture(step, capture_issue))
    _ => @connector.Execution(@execution.InputSet)
  }
}

///|
fn selected_binding_rows_execution(
  sequence : @execution.GeneratedSequence,
  input : ManagedProviderInput,
  execution : @execution.SequenceExecutionLimits,
  max_value_bytes : Int,
  step : Int,
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  let control = @bounded.control()
  let started = match input {
    RelationInput(read) =>
      @execution.start_bounded_binding_rows(
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
      @execution.start_bounded_binding_rows_supplied(
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
    Err(issue) => return Err(selected_binding_rows_issue(issue, step))
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
          @execution.advance_bounded_binding_rows(active, quantum) {
          Ok(value) => value
          Err(issue) => {
            terminated.val = true
            return Ok(
              managed_provider_failed(
                selected_binding_rows_issue(issue, step),
                0L,
                0L,
              ),
            )
          }
        }
        let (next_progress, next_work, terminal) = match poll {
          @execution.BoundedBindingRowsContinue(progress~, work~) =>
            (progress, work, false)
          @execution.BoundedBindingRowsComplete(_, progress~, work~)
          | @execution.BoundedBindingRowsFailed(_, progress~, work~)
          | @execution.BoundedBindingRowsStopped(_, progress~, work~) =>
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
          @execution.BoundedBindingRowsContinue(_) =>
            Ok(managed_provider_continue(progress_delta, work_delta))
          @execution.BoundedBindingRowsComplete(output, ..) =>
            Ok(managed_provider_complete(output, progress_delta, work_delta))
          @execution.BoundedBindingRowsFailed(issue, ..) =>
            Ok(
              managed_provider_failed(
                selected_binding_rows_issue(issue, step),
                progress_delta,
                work_delta,
              ),
            )
          @execution.BoundedBindingRowsStopped(_, ..) =>
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
        match @execution.cleanup_bounded_binding_rows(active) {
          Ok(true) => {
            reclaimed.val = true
            Ok(true)
          }
          Ok(false) => Ok(false)
          Err(issue) => Err(selected_binding_rows_issue(issue, step))
        }
      },
    ),
  )
}

///|
fn selected_relation_provider(
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
) -> ManagedProvider {
  managed_provider_with_inputs(
    sequence => {
      if @execution.generated_sequence_step_count(sequence) != 1 {
        return false
      }
      guard @execution.generated_sequence_step_index_at(sequence, 0)
        is Some(step) &&
        @execution.generated_sequence_step_at(sequence, 0)
        is Some(@lower.RowStep(kernel)) else {
        return false
      }
      // Only bodies with a bounded evaluator can enter this provider.
      if !selected_binding_rows_supported(kernel) {
        return false
      }
      match
        @execution.completion_preparation_selected_step(
          @execution.generated_completion_preparation(sequence),
        ) {
        Some(selected) => if selected != step { return false }
        None => ()
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
      guard inputs is [input] else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      guard @execution.generated_sequence_step_index_at(sequence, 0)
        is Some(step) &&
        @execution.generated_sequence_step_at(sequence, 0)
        is Some(@lower.RowStep(kernel)) else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      if !selected_binding_rows_supported(kernel) {
        return Err(@connector.Execution(@execution.InputSet))
      }
      selected_binding_rows_execution(
        sequence, input, execution, max_value_bytes, step,
      )
    },
  )
}
