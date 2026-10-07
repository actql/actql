///|
/// Checked Relation execution shared by single-step and chained tasks.
/// Family providers do not reinterpret RelA after a Carrier bridge.
fn selected_binding_rows_supported(kernel : @lower.PreparedKernel) -> Bool {
  if @lower.kernel_json_pick(kernel) is Some(_) {
    return true
  }
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
  completed : Array[@execution.CompletedOutput?],
  max_entries : Int,
  max_value_bytes : Int,
) -> Result[Array[ManagedProviderInput], @connector.FixedComputeIssue] {
  let owner = @execution.generated_sequence_owner(sequence)
  guard @execution.generated_sequence_step_index_at(sequence, 0)
    is Some(first_step) &&
    @execution.generated_sequence_step_index_at(sequence, position)
    is Some(step) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  let selected : Array[ManagedProviderInput] = []
  for port in 0..<@lower.node_input_count(node) {
    let target = @lower.node_input_target(node, port)
    let external = match target {
      Some(@pipeline.Input(_)) => true
      Some(@pipeline.Step(producer)) => producer < first_step
      None => false
    }
    if external {
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
      continue
    }
    match target {
      Some(@pipeline.Step(producer_step)) => {
        let mut producer_position = -1
        for earlier in 0..<position {
          if @execution.generated_sequence_step_index_at(sequence, earlier) ==
            Some(producer_step) {
            producer_position = earlier
            break
          }
        }
        guard producer_position >= 0 &&
          completed.get(producer_position) is Some(Some(output)) else {
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
      _ => return Err(@connector.Execution(@execution.InputSet))
    }
  }
  Ok(selected)
}

///|
/// These bounded Relation kernels transfer an accepted completion independently
/// of their execution scratch. Their existing cleanup preserves that output.
/// Family providers retain their original conservative lifecycle and capacity.
fn relation_chain_reclaims_completed_scratch(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  for index in 0..<@execution.generated_sequence_step_count(sequence) {
    match @execution.generated_sequence_step_at(sequence, index) {
      Some(@lower.JoinStep(_)) => ()
      Some(@lower.RowStep(kernel)) =>
        if !selected_binding_rows_supported(kernel) &&
          !(@lower.kernel_body(kernel) is @lower.Groups(_)) &&
          !(@lower.kernel_body(kernel) is @lower.CountGroups(_)) {
          return false
        }
      _ => return false
    }
  }
  true
}

///|
/// Completed output remains held for every exact downstream edge. An eligible
/// built-in-only chain confirms child cleanup and drops its execution before
/// the next child starts, so only one scratch envelope can be live at a time.
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
  let reclaims_scratch = relation_chain_reclaims_completed_scratch(sequence)
  let mut retained_children = 0L
  let mut scratch = 0L
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
    if retained_children > 9223372036854775807L - child.retained_bytes {
      return None
    }
    retained_children += child.retained_bytes
    if reclaims_scratch {
      scratch = Int64::max(scratch, child.execution_bytes)
    } else {
      if scratch > 9223372036854775807L - child.execution_bytes {
        return None
      }
      scratch += child.execution_bytes
    }
  }
  if retained_children > 9223372036854775807L - scratch {
    return None
  }
  let live_children = retained_children + scratch
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
/// intermediate result remains private and supplies its exact later checked edges.
fn bounded_relation_chain_execution(
  sequence : @execution.GeneratedSequence,
  inputs : Array[ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_value_bytes : Int,
  numeric : @execution.NumericAggregateExecution?,
  family : Array[ManagedProvider],
) -> Result[ManagedProviderExecution, @connector.FixedComputeIssue] {
  bounded_relation_chain_execution_state(
    sequence, inputs, execution, measurement, max_value_bytes, numeric, family,
  ).map(result => result.0)
}

///|
priv struct RelationChainExecutionState {
  mut children : Array[ManagedProviderExecution]
  mut current : ManagedProviderExecution?
  mut completed : Array[@execution.CompletedOutput?]
  mut position : Int
  mut pending : Bool
  mut reclaiming : Bool
}

///|
/// Preserve pending cleanup custody until the same child confirms reclamation.
fn reclaim_relation_chain_child(
  state : RelationChainExecutionState,
) -> Result[Bool, @connector.FixedComputeIssue] {
  if !state.reclaiming {
    return Ok(true)
  }
  guard state.current is Some(active) && managed_provider_stopped(active) else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  match cleanup_managed_provider(active) {
    Ok(true) => {
      // Output provenance retains exact identities, not the child execution.
      // Drop every execution reference, including immutable input captures.
      state.current = None
      state.children = []
      state.reclaiming = false
      Ok(true)
    }
    result => result
  }
}

///|
fn bounded_relation_chain_execution_state(
  sequence : @execution.GeneratedSequence,
  inputs : Array[ManagedProviderInput],
  execution : @execution.SequenceExecutionLimits,
  measurement : @execution.FixedInputGuardMeasureLimits,
  max_value_bytes : Int,
  numeric : @execution.NumericAggregateExecution?,
  family : Array[ManagedProvider],
) -> Result[
  (ManagedProviderExecution, RelationChainExecutionState),
  @connector.FixedComputeIssue,
] {
  let count = @execution.generated_sequence_step_count(sequence)
  guard count > 1 &&
    @execution.generated_sequence_step_index_at(sequence, 0) is Some(first_step) &&
    @execution.select_generated_sequence_step(sequence, first_step)
    is Some(first) else {
    return Err(@connector.Execution(@execution.InputSet))
  }
  let state : RelationChainExecutionState = {
    children: [],
    current: None,
    completed: Array::make(count, None),
    position: 0,
    pending: false,
    reclaiming: false,
  }
  let first_inputs = match
    relation_chain_step_inputs(
      sequence,
      0,
      inputs,
      state.completed,
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
  state.children = [initial]
  state.current = Some(initial)
  let used = Ref(0L)
  // Productive admission only. The existing ManagedProviderExecution owner
  // separately sums all reported deltas, including mandatory stop work.
  let cancelled = Ref(false)
  let terminal = Ref(false)
  let reclaimed = Ref(false)
  let cleanup_index = Ref(-1)
  let reclaims_scratch = relation_chain_reclaims_completed_scratch(sequence)
  let start_next = fn() -> Result[Unit, @connector.FixedComputeIssue] {
    guard state.position > 0 &&
      state.position < count &&
      @execution.generated_sequence_step_index_at(sequence, state.position)
      is Some(step) &&
      @execution.select_generated_sequence_step(sequence, step)
      is Some(selected) else {
      return Err(@connector.Execution(@execution.InputSet))
    }
    let next_inputs = match
      relation_chain_step_inputs(
        sequence,
        state.position,
        inputs,
        state.completed,
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
    state.children.push(next)
    state.current = Some(next)
    state.pending = false
    Ok(())
  }
  Ok(
    managed_provider_execution_with_child_work_issue(
      quantum => {
        if quantum <= 0 || terminal.val {
          return Err(@connector.InvalidLimits)
        }
        if cancelled.val && state.pending {
          terminal.val = true
          return Ok(managed_provider_stopped_poll(0L, 0L))
        }
        if state.pending {
          match reclaim_relation_chain_child(state) {
            Ok(true) => ()
            Ok(false) => return Ok(managed_provider_waiting(0L, 0L))
            Err(issue) => {
              terminal.val = true
              return Ok(managed_provider_failed(issue, 0L, 0L))
            }
          }
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
        guard state.current is Some(active) else {
          terminal.val = true
          return Ok(
            managed_provider_failed(
              @connector.Execution(@execution.InputSet),
              0L,
              0L,
            ),
          )
        }
        if cancelled.val || used.val >= execution.max_work.to_int64() {
          // The exhausted budget must not authorize another compute step.
          // Confirm the active child's stop before exposing the limit error;
          // otherwise its private output remains owned by an active session.
          cancel_managed_provider(active) |> ignore
          let poll = match advance_managed_provider(active, 1) {
            Ok(value) => value
            Err(issue) => {
              if !managed_provider_stopped(active) {
                return Err(issue)
              }
              // An independently confirmed stop may reject further advance.
              // No new delta was reported: preserve the budget failure and
              // cleanup custody without inventing work or inferring stop
              // from the exception itself.
              managed_provider_stopped_poll(0L, 0L)
            }
          }
          let (progress, work) = match poll {
            Continue(progress~, work~)
            | Waiting(progress~, work~)
            | Settling(_, progress~, work~)
            | Complete(_, progress~, work~)
            | CarrierComplete(_, progress~, work~)
            | Failed(_, progress~, work~)
            | Stopped(progress~, work~) => (progress, work)
          }
          if progress < 0L || work < 0L || work > 1L {
            return Err(@connector.InvalidLimits)
          }
          if !managed_provider_stopped(active) {
            // A child may retain Store/authority custody during stop. Preserve
            // its explicit pause rather than inventing zero-work Continue.
            return match poll {
              Waiting(..) | Settling(_, ..) => Ok(poll)
              _ => Ok(managed_provider_continue(progress, work))
            }
          }
          terminal.val = true
          if used.val < execution.max_work.to_int64() {
            return Ok(managed_provider_stopped_poll(progress, work))
          }
          return Ok(
            managed_provider_failed(
              @connector.Execution(@execution.InputLimit),
              progress,
              work,
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
        if managed_provider_cumulative_work(active) is Err(_) {
          // The common child owner has already requested cancellation. Do
          // not declare physical stop from an accounting error; keep this
          // chain in its stop-only branch until that child confirms it.
          cancelled.val = true
          terminal.val = managed_provider_stopped(active)
          return Err(@connector.InvalidLimits)
        }
        let (progress, work) = match poll {
          Continue(progress~, work~)
          | Waiting(progress~, work~)
          | Settling(_, progress~, work~)
          | Complete(_, progress~, work~)
          | CarrierComplete(_, progress~, work~)
          | Failed(_, progress~, work~)
          | Stopped(progress~, work~) => (progress, work)
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
          Waiting(..) | Settling(_, ..) => Ok(poll)
          Complete(output, ..) => {
            if state.position == count - 1 {
              terminal.val = true
              return Ok(managed_provider_complete(output, progress, work))
            }
            state.completed[state.position] = Some(output)
            state.position += 1
            state.pending = true
            if reclaims_scratch {
              state.reclaiming = true
              match reclaim_relation_chain_child(state) {
                Ok(_) => ()
                Err(issue) => {
                  terminal.val = true
                  return Ok(managed_provider_failed(issue, progress, work))
                }
              }
            } else {
              state.current = None
            }
            if work > 0L {
              Ok(managed_provider_continue(progress, work))
            } else if reclaims_scratch {
              // These kernels charge completion work. Preserve an explicit
              // cleanup pause if a future bounded implementation needs it.
              Ok(managed_provider_waiting(progress, work))
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
        if state.current is Some(active) {
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
          cleanup_index.val = state.children.length() - 1
        }
        // Conservative chains still retain prior execution readers; release
        // them in reverse order. Eligible chains retain only the current child.
        // Completed output custody is cleared separately after reclamation.
        while cleanup_index.val >= 0 {
          match cleanup_managed_provider(state.children[cleanup_index.val]) {
            Ok(true) => cleanup_index.val -= 1
            Ok(false) => return Ok(false)
            Err(issue) => return Err(issue)
          }
        }
        state.current = None
        state.completed = []
        state.children = []
        reclaimed.val = true
        Ok(true)
      },
      fn() {
        for child in state.children {
          if managed_provider_cumulative_work(child) is Err(issue) {
            return Some(issue)
          }
        }
        None
      },
    ),
  ).map(active => (active, state))
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
      let used_by_later = Array::make(count, false)
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
                let first_step = @execution.generated_sequence_step_index_at(
                  sequence, 0,
                ).unwrap()
                if producer_step < first_step {
                  continue
                }
                let mut producer_position = -1
                for earlier in 0..<index {
                  if @execution.generated_sequence_step_index_at(
                      sequence, earlier,
                    ) ==
                    Some(producer_step) {
                    producer_position = earlier
                    break
                  }
                }
                if producer_position < 0 {
                  return false
                }
                used_by_later[producer_position] = true
              }
              None => return false
            }
          }
        }
      }
      // An external-only child may form a second branch. Every private
      // output before the final step must still be consumed within the task.
      for index in 0..<(count - 1) {
        if !used_by_later[index] {
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
