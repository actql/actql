///|
/// Checked Relation execution shared by single-step and chained tasks.
/// Family providers do not reinterpret RelA after a Carrier bridge.
fn selected_binding_rows_supported(kernel : @lower.PreparedKernel) -> Bool {
  match @lower.kernel_body(kernel) {
    @lower.AssertAll(_)
    | @lower.AssertUnique(_)
    | @lower.SnapshotMap(_)
    | @lower.OrderedBindings(_)
    | @lower.Filter(_)
    | @lower.JsonPick(_, _, _)
    | @lower.Select(_)
    | @lower.Watermark(_, _, _, _)
    | @lower.Lag(_, _)
    | @lower.DistinctRows
    | @lower.DedupeRows
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
/// A selected step keeps the same typed owner and operation input as the
/// original sequence. Only already bounded Relation providers may join a
/// multi-step chain.
fn bounded_relation_step_provider(
  selected : @execution.GeneratedSequence,
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  family? : Array[ManagedProvider] = [],
) -> ManagedProvider? {
  // Only these Relation-valued family operations use this row-chain owner.
  // A Carrier constructor is not a private Relation output.
  let family_step = match @execution.generated_sequence_step_at(selected, 0) {
    Some(@lower.TimeSeriesStep(_))
    | Some(@lower.IntervalJoinStep(_))
    | Some(@lower.AsOfJoinStep(_))
    | Some(@lower.SequenceMatchStep(_)) => true
    Some(@lower.EventStep(event)) =>
      @carrier.kind(@lower.event_output_carrier(event)) == @carrier.RelationKind &&
      @execution.generated_sequence_step_index_at(selected, 0)
      .bind(step => {
        @lower.node_at(
          @lower.bound_preparation(
            @execution.generated_sequence_owner(selected),
          ),
          step,
        )
      })
      .map(node => @lower.operation(node)) ==
      Some("TEA.window.session_assign")
    _ => false
  }
  if family_step {
    if @execution.generated_sequence_step_count(selected) != 1 ||
      local_sequence_outputs_carrier(selected) {
      return None
    }
    for provider in family {
      if managed_provider_accepts(provider, selected) {
        return Some(provider)
      }
    }
    return None
  }
  for
    provider in [
      selected_relation_provider(execution, measurement),
      cross_join_provider(execution, measurement),
      append_provider(execution, measurement),
      set_provider(execution, measurement),
      nest_provider(execution, measurement),
      global_count_provider(execution, measurement),
      group_provider(execution, measurement),
      row_window_provider(execution, measurement),
      unpivot_provider(execution, measurement),
      unnest_provider(execution, measurement),
      values_provider(execution, measurement),
    ] {
    if managed_provider_accepts(provider, selected) {
      return Some(provider)
    }
  }
  None
}

///|
fn start_bounded_relation_step(
  selected : @execution.GeneratedSequence,
  inputs : Array[ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_value_bytes : Int,
  remaining_work : Int,
  numeric : @execution.NumericAggregateExecution?,
  family : Array[ManagedProvider],
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  guard remaining_work > 0 &&
    bounded_relation_step_provider(selected, execution, measurement, family~)
    is Some(provider) else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  let limited : @execution.SequenceExecutionLimits = {
    rows: execution.rows,
    max_work: remaining_work,
    max_frames: execution.max_frames,
  }
  start_managed_provider_with_inputs_and_execution(
    provider,
    selected,
    inputs,
    execution.rows.max_rows,
    max_value_bytes,
    limited,
    numeric~,
  )
}

///|
/// Preserve each checked operation port when a bounded chain combines a
/// previous private completion with an external input. Repeated targets remain
/// separate input occurrences; the child provider checks their exact binding.
fn relation_chain_step_inputs(
  sequence : @execution.GeneratedSequence,
  position : Int,
  inputs : Array[ManagedProviderInput],
  previous : @execution.CompletedOutput?,
  max_entries : Int,
  max_value_bytes : Int,
) -> Result[Array[ManagedProviderInput], @connector.FixedComputeIssue] {
  let owner = @execution.generated_sequence_owner(sequence)
  guard @execution.generated_sequence_step_index_at(sequence, position)
    is Some(step) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  let prior = if position > 0 {
    @execution.generated_sequence_step_index_at(sequence, position - 1)
  } else {
    None
  }
  let selected : Array[ManagedProviderInput] = []
  for port in 0..<@lower.node_input_count(node) {
    match @lower.node_input_target(node, port) {
      Some(@pipeline.Input(_)) => {
        let mut matched : ManagedProviderInput? = None
        for input in inputs {
          let exact = match input {
            RelationInput(read) =>
              @execution.producer_read_matches_operation_input(
                read, owner, step, port,
              )
            SuppliedRelationInput(read) =>
              @execution.supplied_relation_read_matches_operation_input(
                read, owner, step, port,
              )
            CarrierInput(_) => false
          }
          if exact {
            if matched is Some(_) {
              return Err(@connector.Execution(@execution.InputSet))
            }
            matched = Some(input)
          }
        }
        guard matched is Some(input) else {
          return Err(@connector.Execution(@execution.InputSet))
        }
        selected.push(input)
      }
      Some(@pipeline.Step(producer_step)) => {
        guard prior == Some(producer_step) && previous is Some(output) else {
          return Err(@connector.Execution(@execution.InputSet))
        }
        let bound = match
          @execution.bind_completed_operation_input(
            owner, step, port, owner, output,
          ) {
          Ok(value) => value
          Err(_) => return Err(@connector.Execution(@execution.InputSet))
        }
        let read = match
          @execution.prepare_producer_read(
            owner, bound, max_entries, max_value_bytes,
          ) {
          Ok(value) => value
          Err(_) => return Err(@connector.Execution(@execution.InputSet))
        }
        selected.push(RelationInput(read))
      }
      None => return Err(@connector.Execution(@execution.InputSet))
    }
  }
  Ok(selected)
}

///|
/// Chain children remain owned until the parent is reclaimed. Their private
/// scratch and provisional outputs can therefore overlap even though only one
/// child advances at a time.
fn bounded_relation_chain_capacity(
  sequence : @execution.GeneratedSequence,
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  family : Array[ManagedProvider],
) -> @execution.ExecutionCapacity? {
  guard @execution.generated_sequence_capacity(sequence, limits, measurement)
    is Some(base) else {
    return None
  }
  let count = @execution.generated_sequence_step_count(sequence)
  if count < 2 {
    return Some(base)
  }
  let mut live_children = 0L
  for index in 0..<count {
    guard @execution.generated_sequence_step_index_at(sequence, index)
      is Some(step) &&
      @execution.select_generated_sequence_step(sequence, step)
      is Some(selected) &&
      bounded_relation_step_provider(selected, limits, measurement, family~)
      is Some(provider) &&
      managed_provider_capacity(provider, selected) is Some(child) else {
      return None
    }
    if child.retained_bytes > 9223372036854775807L - child.execution_bytes ||
      live_children >
      9223372036854775807L - child.retained_bytes - child.execution_bytes {
      return None
    }
    live_children += child.retained_bytes + child.execution_bytes
  }
  let handles = count.to_int64() * 256L
  if live_children > 9223372036854775807L - handles {
    return None
  }
  @execution.execution_capacity(
    base.retained_bytes,
    Int64::max(base.execution_bytes, live_children + handles),
  )
}

///|
/// Execute a checked Relation chain inside its original task. Every
/// intermediate result remains private and supplies only the next exact edge.
fn bounded_relation_chain_execution(
  sequence : @execution.GeneratedSequence,
  inputs : Array[ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_value_bytes : Int,
  numeric : @execution.NumericAggregateExecution?,
  family : Array[ManagedProvider],
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  let count = @execution.generated_sequence_step_count(sequence)
  guard count > 1 &&
    @execution.generated_sequence_step_index_at(sequence, 0) is Some(first_step) &&
    @execution.select_generated_sequence_step(sequence, first_step)
    is Some(first) else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  let first_inputs = match
    relation_chain_step_inputs(
      sequence,
      0,
      inputs,
      None,
      execution.rows.operation_entries,
      max_value_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let initial = match
    start_bounded_relation_step(
      first,
      first_inputs,
      execution,
      measurement,
      max_value_bytes,
      execution.max_work,
      numeric,
      family,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let children : Ref[Array[ManagedProviderExecution]] = Ref([initial])
  let previous : Ref[@execution.CompletedOutput?] = Ref(None)
  let current : Ref[ManagedProviderExecution?] = Ref(Some(initial))
  let position = Ref(0)
  let pending = Ref(false)
  let used = Ref(0L)
  let cancelled = Ref(false)
  let terminal = Ref(false)
  let reclaimed = Ref(false)
  let cleanup_index = Ref(-1)
  let start_next = fn() -> Result[Unit, @connector.FixedComputeIssue] {
    guard position.val > 0 &&
      position.val < count &&
      previous.val is Some(output) &&
      @execution.generated_sequence_step_index_at(sequence, position.val)
      is Some(step) &&
      @execution.select_generated_sequence_step(sequence, step)
      is Some(selected) else {
      return Err(@connector.Execution(@execution.InputSet))
    }
    let next_inputs = match
      relation_chain_step_inputs(
        sequence,
        position.val,
        inputs,
        Some(output),
        execution.rows.operation_entries,
        max_value_bytes,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    let remaining = execution.max_work.to_int64() - used.val
    if remaining < 1L {
      return Err(@connector.Execution(@execution.InputLimit))
    }
    let next = match
      start_bounded_relation_step(
        selected,
        next_inputs,
        execution,
        measurement,
        max_value_bytes,
        remaining.to_int(),
        numeric,
        family,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    children.val.push(next)
    current.val = Some(next)
    pending.val = false
    Ok(())
  }
  Ok(
    managed_provider_execution(
      quantum => {
        if quantum <= 0 || terminal.val {
          return Err(@connector.InvalidLimits)
        }
        if cancelled.val && pending.val {
          terminal.val = true
          return Ok(managed_provider_stopped_poll(0L, 0L))
        }
        if pending.val {
          if used.val >= execution.max_work.to_int64() {
            terminal.val = true
            return Ok(
              managed_provider_failed(
                @connector.Execution(@execution.InputLimit),
                0L,
                0L,
              ),
            )
          }
          used.val += 1L
          match start_next() {
            Ok(_) => return Ok(managed_provider_continue(0L, 1L))
            Err(issue) => {
              terminal.val = true
              return Ok(managed_provider_failed(issue, 0L, 1L))
            }
          }
        }
        guard current.val is Some(active) else {
          terminal.val = true
          return Ok(
            managed_provider_failed(
              @connector.Execution(@execution.InputSet),
              0L,
              0L,
            ),
          )
        }
        if used.val >= execution.max_work.to_int64() {
          // The exhausted budget must not authorize another compute step.
          // Confirm the active child's stop before exposing the limit error;
          // otherwise its private output remains owned by an active session.
          cancel_managed_provider(active) |> ignore
          match advance_managed_provider(active, 1) {
            Ok(_) => ()
            Err(_) => ()
          }
          if !managed_provider_stopped(active) {
            return Ok(managed_provider_continue(0L, 1L))
          }
          terminal.val = true
          return Ok(
            managed_provider_failed(
              @connector.Execution(@execution.InputLimit),
              0L,
              0L,
            ),
          )
        }
        let remaining = execution.max_work.to_int64() - used.val
        let child_quantum = Int::min(quantum, remaining.to_int())
        let poll = match advance_managed_provider(active, child_quantum) {
          Ok(value) => value
          Err(issue) => {
            terminal.val = true
            return Ok(managed_provider_failed(issue, 0L, 0L))
          }
        }
        let (progress, work) = match poll {
          Continue(progress~, work~)
          | Complete(_, progress~, work~)
          | Failed(_, progress~, work~)
          | Stopped(progress~, work~) => (progress, work)
          CarrierComplete(_, ..) => {
            terminal.val = true
            return Ok(
              managed_provider_failed(
                @connector.Execution(@execution.InputSet),
                0L,
                0L,
              ),
            )
          }
        }
        if work < 0L ||
          work > child_quantum.to_int64() ||
          used.val > execution.max_work.to_int64() - work {
          terminal.val = true
          return Ok(
            managed_provider_failed(
              @connector.Execution(@execution.InputLimit),
              0L,
              0L,
            ),
          )
        }
        used.val += work
        match poll {
          Continue(..) => Ok(managed_provider_continue(progress, work))
          Complete(output, ..) => {
            if position.val == count - 1 {
              terminal.val = true
              return Ok(managed_provider_complete(output, progress, work))
            }
            previous.val = Some(output)
            position.val += 1
            current.val = None
            pending.val = true
            if work > 0L {
              Ok(managed_provider_continue(progress, work))
            } else if used.val < execution.max_work.to_int64() {
              used.val += 1L
              match start_next() {
                Ok(_) => Ok(managed_provider_continue(progress, 1L))
                Err(issue) => {
                  terminal.val = true
                  Ok(managed_provider_failed(issue, progress, 1L))
                }
              }
            } else {
              terminal.val = true
              Ok(
                managed_provider_failed(
                  @connector.Execution(@execution.InputLimit),
                  progress,
                  0L,
                ),
              )
            }
          }
          Failed(issue, ..) => {
            terminal.val = true
            Ok(managed_provider_failed(issue, progress, work))
          }
          Stopped(..) => {
            terminal.val = true
            Ok(managed_provider_stopped_poll(progress, work))
          }
          CarrierComplete(_, ..) => {
            terminal.val = true
            Ok(
              managed_provider_failed(
                @connector.Execution(@execution.InputSet),
                progress,
                work,
              ),
            )
          }
        }
      },
      fn() {
        if cancelled.val || terminal.val {
          return false
        }
        cancelled.val = true
        if current.val is Some(active) {
          cancel_managed_provider(active) |> ignore
        }
        true
      },
      fn() { terminal.val },
      fn() {
        if reclaimed.val {
          return Ok(true)
        }
        if !terminal.val {
          return Ok(false)
        }
        if cleanup_index.val < 0 {
          cleanup_index.val = children.val.length() - 1
        }
        // A later step borrows its predecessor's private completion.
        // Release those readers before asking the producer to reclaim it.
        while cleanup_index.val >= 0 {
          match cleanup_managed_provider(children.val[cleanup_index.val]) {
            Ok(true) => cleanup_index.val -= 1
            Ok(false) => return Ok(false)
            Err(issue) => return Err(issue)
          }
        }
        current.val = None
        previous.val = None
        children.val = []
        reclaimed.val = true
        Ok(true)
      },
    ),
  )
}

///|
fn selected_relation_provider(
  limits : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  family? : Array[ManagedProvider] = [],
) -> ManagedProvider {
  managed_provider_with_numeric(
    sequence => {
      let count = @execution.generated_sequence_step_count(sequence)
      let owner = @execution.generated_sequence_owner(sequence)
      let prepared = @lower.bound_preparation(owner)
      if count < 1 {
        return false
      }
      for index in 0..<count {
        guard @execution.generated_sequence_step_index_at(sequence, index)
          is Some(step) &&
          @execution.generated_sequence_step_at(sequence, index)
          is Some(operation) &&
          @lower.node_at(prepared, step) is Some(node) else {
          return false
        }
        let selected = if count > 1 {
          match @execution.select_generated_sequence_step(sequence, step) {
            Some(value) => Some(value)
            None => return false
          }
        } else {
          None
        }
        let single_unsupported = if count == 1 {
          match operation {
            @lower.RowStep(kernel) => !selected_binding_rows_supported(kernel)
            @lower.JoinStep(_) => false
            _ => true
          }
        } else {
          false
        }
        let chain_unsupported = if count > 1 {
          match selected {
            Some(value) =>
              bounded_relation_step_provider(
                value,
                limits,
                measurement,
                family~,
              )
              is None
            None => true
          }
        } else {
          false
        }
        let input_count = @lower.node_input_count(node)
        if single_unsupported || chain_unsupported {
          return false
        }
        let previous = if index > 0 {
          @execution.generated_sequence_step_index_at(sequence, index - 1)
        } else {
          None
        }
        let mut prior_inputs = 0
        for port in 0..<input_count {
          if !@lower.node_accepts_managed_relation_view(node, port) {
            return false
          }
          guard @lower.node_input_target(node, port) is Some(target) &&
            @lower.preparation_carrier_at(prepared, target) is Some(carrier) &&
            @carrier.kind(carrier) == @carrier.RelationKind else {
            return false
          }
          if count > 1 {
            match @lower.node_input_target(node, port) {
              Some(@pipeline.Input(source)) =>
                if source < 0 ||
                  source >= @lower.preparation_input_count(prepared) {
                  return false
                }
              Some(@pipeline.Step(producer_step)) => {
                if previous != Some(producer_step) {
                  return false
                }
                prior_inputs += 1
              }
              None => return false
            }
          }
        }
        if count > 1 && index > 0 && prior_inputs == 0 {
          return false
        }
      }
      match
        @execution.completion_preparation_selected_step(
          @execution.generated_completion_preparation(sequence),
        ) {
        Some(step) =>
          count == 1 &&
          @execution.generated_sequence_step_index_at(sequence, 0) == Some(step)
        None => true
      }
    },
    sequence => {
      bounded_relation_chain_capacity(sequence, limits, measurement, family)
    },
    (sequence, inputs, _max_rows, max_value_bytes, execution, numeric) => {
      if @execution.generated_sequence_step_count(sequence) > 1 {
        return bounded_relation_chain_execution(
          sequence, inputs, execution, measurement, max_value_bytes, numeric, family,
        )
      }
      guard @execution.generated_sequence_step_index_at(sequence, 0)
        is Some(step) else {
        return Err(@connector.Execution(@execution.InputSet))
      }
      if @execution.generated_sequence_step_at(sequence, 0)
        is Some(@lower.JoinStep(_)) {
        return selected_join_execution(
          sequence, inputs, execution, max_value_bytes, step,
        )
      }
      guard inputs is [input] &&
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
