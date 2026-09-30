///|
priv struct SequenceMatchProviderExecution {
  active : @execution.BoundedSequenceMatchExecution
  control : @bounded.Control
  step : Int
  mut progress : Int64
  mut work : Int64
  mut terminal : Bool
  mut reclaimed : Bool
}

///|
fn sequence_match_provider_accepts(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  let count = Ref(0)
  let accepted = @execution.generated_sequence_all_steps(sequence, fn(step) {
    count.val += 1
    step is @lower.SequenceMatchStep(_)
  })
  accepted && count.val == 1
}

///|
fn sequence_match_provider_issue() -> @connector.FixedComputeIssue {
  @connector.Execution(@execution.InputSet)
}

///|
fn sequence_match_provider_failure(
  issue : @execution.BoundedSequenceMatchIssue,
  step : Int,
) -> @connector.FixedComputeIssue {
  match issue {
    @execution.Rows(row_issue) =>
      @connector.Execution(@execution.Rows(step, row_issue))
    @execution.Capture(capture_issue) =>
      @connector.Execution(@execution.Capture(step, capture_issue))
    _ => sequence_match_provider_issue()
  }
}

///|
fn sequence_match_provider_delta(current : Int64, prior : Int64) -> Int64? {
  if current < prior {
    None
  } else {
    Some(current - prior)
  }
}

///|
fn sequence_match_provider_poll(
  state : SequenceMatchProviderExecution,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if state.terminal || quantum <= 0 {
    return Err(@connector.InvalidLimits)
  }
  let poll = match
    @execution.advance_bounded_sequence_match(state.active, quantum) {
    Ok(value) => value
    Err(_) => {
      state.terminal = true
      return Ok(
        @local.managed_provider_failed(sequence_match_provider_issue(), 0L, 0L),
      )
    }
  }
  let (progress, work, terminal) = match poll {
    @execution.BoundedSequenceMatchContinue(progress~, work~) =>
      (progress, work, false)
    @execution.BoundedSequenceMatchComplete(_, progress~, work~) =>
      (progress, work, true)
    @execution.BoundedSequenceMatchFailed(_, progress~, work~) =>
      (progress, work, true)
    @execution.BoundedSequenceMatchStopped(_, progress~, work~) =>
      (progress, work, true)
  }
  guard sequence_match_provider_delta(progress, state.progress)
    is Some(progress_delta) &&
    sequence_match_provider_delta(work, state.work) is Some(work_delta) else {
    state.terminal = true
    return Ok(
      @local.managed_provider_failed(sequence_match_provider_issue(), 0L, 0L),
    )
  }
  state.progress = progress
  state.work = work
  if terminal {
    state.terminal = true
  }
  match poll {
    @execution.BoundedSequenceMatchContinue(_) =>
      Ok(@local.managed_provider_continue(progress_delta, work_delta))
    @execution.BoundedSequenceMatchComplete(output, ..) =>
      Ok(@local.managed_provider_complete(output, progress_delta, work_delta))
    @execution.BoundedSequenceMatchFailed(issue, ..) =>
      Ok(
        @local.managed_provider_failed(
          sequence_match_provider_failure(issue, state.step),
          progress_delta,
          work_delta,
        ),
      )
    @execution.BoundedSequenceMatchStopped(_, ..) =>
      Ok(@local.managed_provider_stopped_poll(progress_delta, work_delta))
  }
}

///|
fn cleanup_sequence_match_provider(
  state : SequenceMatchProviderExecution,
) -> Result[Bool, @connector.FixedComputeIssue] {
  if !state.terminal {
    return Ok(false)
  }
  if state.reclaimed {
    return Ok(true)
  }
  match @execution.cleanup_bounded_sequence_match(state.active) {
    Ok(true) => {
      state.reclaimed = true
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(_) => Err(sequence_match_provider_issue())
  }
}

///|
pub fn sequence_match_provider(
  limits : @storage.Limits,
  capacity : @execution.ExecutionCapacity,
) -> @local.ManagedProvider {
  @local.managed_provider_with_inputs(
    sequence_match_provider_accepts,
    sequence => {
      if sequence_match_provider_accepts(sequence) {
        Some(capacity)
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes, execution) {
      if !sequence_match_provider_accepts(sequence) ||
        inputs.length() != 1 ||
        max_rows < 0 ||
        max_value_bytes < 0 ||
        execution.max_work <= 0 ||
        execution.max_frames < 0 {
        return Err(@connector.InvalidLimits)
      }
      let control = @bounded.control()
      let step = @execution.generated_sequence_step_index_at(sequence, 0).unwrap()
      let started = match inputs[0] {
        @local.RelationInput(input) =>
          @execution.start_bounded_sequence_match(
            control,
            sequence,
            input,
            max_rows,
            execution.rows.output_values,
            execution.max_work,
            execution.max_frames,
            limits.max_workspace_slots,
            max_value_bytes,
          )
        @local.CarrierInput(input) =>
          @execution.start_bounded_sequence_match_events(
            control,
            sequence,
            input,
            max_rows,
            execution.rows.output_values,
            execution.max_work,
            execution.max_frames,
            limits.max_workspace_slots,
            max_value_bytes,
          )
        @local.SuppliedRelationInput(_) => Err(@execution.InvalidExecution)
      }
      let active = match started {
        Ok(value) => value
        Err(issue) => return Err(sequence_match_provider_failure(issue, step))
      }
      let state : SequenceMatchProviderExecution = {
        active,
        control,
        step,
        progress: 0L,
        work: 0L,
        terminal: false,
        reclaimed: false,
      }
      Ok(
        @local.managed_provider_execution(
          quantum => sequence_match_provider_poll(state, quantum),
          fn() { @bounded.request_cancel(state.control) },
          fn() { state.terminal },
          fn() { cleanup_sequence_match_provider(state) },
        ),
      )
    },
  )
}
