///|
priv struct AsOfProviderExecution {
  active : @execution.BoundedAsOfJoinExecution
  control : @bounded.Control
  step : Int
  mut progress : Int64
  mut work : Int64
  mut terminal : Bool
  mut reclaimed : Bool
}

///|
fn asof_provider_accepts(sequence : @execution.GeneratedSequence) -> Bool {
  let count = Ref(0)
  let accepted = @execution.generated_sequence_all_steps(sequence, fn(step) {
    count.val += 1
    step is @lower.AsOfJoinStep(_)
  })
  // The Host binds the selected search ceiling after provider installation
  // and before execution starts. Shape support must remain discoverable while
  // that request-specific evidence is still absent.
  accepted && count.val == 1
}

///|
fn asof_provider_issue() -> @connector.FixedComputeIssue {
  @connector.Execution(@execution.InputSet)
}

///|
fn asof_provider_failure(
  issue : @execution.BoundedAsOfJoinIssue,
  step : Int,
) -> @connector.FixedComputeIssue {
  match issue {
    @execution.Rows(row_issue) =>
      @connector.Execution(@execution.Rows(step, row_issue))
    @execution.Capture(capture_issue) =>
      @connector.Execution(@execution.Capture(step, capture_issue))
    _ => asof_provider_issue()
  }
}

///|
fn asof_provider_delta(current : Int64, prior : Int64) -> Int64? {
  if current < prior {
    None
  } else {
    Some(current - prior)
  }
}

///|
fn asof_provider_poll(
  state : AsOfProviderExecution,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if state.terminal || quantum <= 0 {
    return Err(@connector.InvalidLimits)
  }
  let poll = match @execution.advance_bounded_asof_join(state.active, quantum) {
    Ok(value) => value
    Err(_) => {
      state.terminal = true
      return Ok(@local.managed_provider_failed(asof_provider_issue(), 0L, 0L))
    }
  }
  let (progress, work, terminal) = match poll {
    @execution.BoundedAsOfJoinContinue(progress~, work~) =>
      (progress, work, false)
    @execution.BoundedAsOfJoinComplete(_, progress~, work~) =>
      (progress, work, true)
    @execution.BoundedAsOfJoinFailed(_, progress~, work~) =>
      (progress, work, true)
    @execution.BoundedAsOfJoinStopped(_, progress~, work~) =>
      (progress, work, true)
  }
  guard asof_provider_delta(progress, state.progress) is Some(progress_delta) &&
    asof_provider_delta(work, state.work) is Some(work_delta) else {
    state.terminal = true
    return Ok(@local.managed_provider_failed(asof_provider_issue(), 0L, 0L))
  }
  state.progress = progress
  state.work = work
  if terminal {
    state.terminal = true
  }
  match poll {
    @execution.BoundedAsOfJoinContinue(_) =>
      Ok(@local.managed_provider_continue(progress_delta, work_delta))
    @execution.BoundedAsOfJoinComplete(output, ..) =>
      Ok(@local.managed_provider_complete(output, progress_delta, work_delta))
    @execution.BoundedAsOfJoinFailed(issue, ..) =>
      Ok(
        @local.managed_provider_failed(
          asof_provider_failure(issue, state.step),
          progress_delta,
          work_delta,
        ),
      )
    @execution.BoundedAsOfJoinStopped(_, ..) =>
      Ok(@local.managed_provider_stopped_poll(progress_delta, work_delta))
  }
}

///|
fn cleanup_asof_provider(
  state : AsOfProviderExecution,
) -> Result[Bool, @connector.FixedComputeIssue] {
  if !state.terminal {
    return Ok(false)
  }
  if state.reclaimed {
    return Ok(true)
  }
  match @execution.cleanup_bounded_asof_join(state.active) {
    Ok(true) => {
      state.reclaimed = true
      Ok(true)
    }
    Ok(false) => Ok(false)
    Err(_) => Err(asof_provider_issue())
  }
}

///|
pub fn asof_join_provider(
  limits : @storage.Limits,
  capacity : @execution.ExecutionCapacity,
) -> @local.ManagedProvider {
  @local.managed_provider_with_inputs(
    asof_provider_accepts,
    sequence => {
      if asof_provider_accepts(sequence) {
        Some(capacity)
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes, execution) {
      if !asof_provider_accepts(sequence) ||
        inputs.length() != 2 ||
        max_rows < 0 ||
        max_value_bytes < 0 ||
        execution.max_work <= 0 ||
        execution.max_frames < 0 {
        return Err(@connector.InvalidLimits)
      }
      let control = @bounded.control()
      let step = @execution.generated_sequence_step_index_at(sequence, 0).unwrap()
      guard inputs[1] is @local.RelationInput(right) else {
        return Err(asof_provider_issue())
      }
      let started = match inputs[0] {
        @local.RelationInput(left) =>
          @execution.start_bounded_asof_join(
            control,
            sequence,
            left,
            right,
            max_rows,
            execution.rows.output_values,
            execution.max_work,
            execution.max_frames,
            limits.max_workspace_slots,
            max_value_bytes,
          )
        @local.CarrierInput(left) =>
          @execution.start_bounded_asof_join_events(
            control,
            sequence,
            left,
            right,
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
        Err(issue) => return Err(asof_provider_failure(issue, step))
      }
      let state : AsOfProviderExecution = {
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
          quantum => asof_provider_poll(state, quantum),
          fn() { @bounded.request_cancel(state.control) },
          fn() { state.terminal },
          fn() { cleanup_asof_provider(state) },
        ),
      )
    },
  )
}
