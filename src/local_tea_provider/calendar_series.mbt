///|
priv struct CalendarSeriesProviderExecution {
  active : @tea.CalendarSeriesExecution
  mut progress : Int64
  mut work : Int64
  mut terminal : Bool
  mut reclaimed : Bool
}

///|
fn calendar_series_provider_accepts(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  guard @execution.generated_sequence_step_count(sequence) == 1 &&
    @execution.generated_sequence_step_at(sequence, 0)
    is Some(@lower.CalendarStep(series)) else {
    return false
  }
  @lower.calendar_start(series) is Some(_) &&
  @lower.calendar_end(series) is Some(_) &&
  @lower.calendar_row_bound(series) is Some(_) &&
  @execution.generated_sequence_step_index_at(sequence, 0) ==
  Some(@lower.calendar_step(series))
}

///|
fn calendar_series_provider_poll(
  value : CalendarSeriesProviderExecution,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if value.terminal || quantum <= 0 {
    return Err(@connector.InvalidLimits)
  }
  let poll = match @tea.advance_calendar_series(value.active, quantum) {
    Ok(result) => result
    Err(_) => {
      value.terminal = true
      return Ok(
        @local.managed_provider_failed(
          @connector.Execution(@execution.InputSet),
          0L,
          0L,
        ),
      )
    }
  }
  let (progress, work, terminal) = match poll {
    @tea.CalendarContinue(progress~, work~) => (progress, work, false)
    @tea.CalendarComplete(_, progress~, work~)
    | @tea.CalendarFailed(_, progress~, work~)
    | @tea.CalendarStopped(_, progress~, work~) => (progress, work, true)
  }
  guard time_series_provider_delta(progress, value.progress)
    is Some(progress_delta) &&
    time_series_provider_delta(work, value.work) is Some(work_delta) else {
    value.terminal = true
    return Ok(
      @local.managed_provider_failed(
        @connector.Execution(@execution.InputSet),
        0L,
        0L,
      ),
    )
  }
  value.progress = progress
  value.work = work
  value.terminal = terminal
  match poll {
    @tea.CalendarContinue(_) =>
      Ok(@local.managed_provider_continue(progress_delta, work_delta))
    @tea.CalendarComplete(output, ..) =>
      Ok(@local.managed_provider_complete(output, progress_delta, work_delta))
    @tea.CalendarFailed(_, ..) =>
      Ok(
        @local.managed_provider_failed(
          @connector.Execution(@execution.InputSet),
          progress_delta,
          work_delta,
        ),
      )
    @tea.CalendarStopped(_, ..) =>
      Ok(@local.managed_provider_stopped_poll(progress_delta, work_delta))
  }
}

///|
fn cleanup_calendar_series_provider(
  value : CalendarSeriesProviderExecution,
) -> Result[Bool, @connector.FixedComputeIssue] {
  if !value.terminal {
    return Ok(false)
  }
  if value.reclaimed {
    return Ok(true)
  }
  let cleaned = match @tea.cleanup_calendar_series(value.active) {
    Ok(result) => result
    Err(_) => return Err(@connector.Execution(@execution.InputSet))
  }
  if cleaned && !@tea.calendar_series_cleanup_pending(value.active) {
    value.reclaimed = true
  }
  Ok(value.reclaimed)
}

///|
pub fn calendar_series_provider(
  limits : @storage.Limits,
  capacity : @execution.ExecutionCapacity,
) -> @local.ManagedProvider {
  @local.managed_provider(
    calendar_series_provider_accepts,
    sequence => {
      if calendar_series_provider_accepts(sequence) {
        Some(capacity)
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes, execution) {
      if !calendar_series_provider_accepts(sequence) ||
        !inputs.is_empty() ||
        max_rows < 0 ||
        max_value_bytes < 0 {
        return Err(@connector.InvalidLimits)
      }
      let control = @bounded.control()
      let active = match
        @tea.start_calendar_series(
          control,
          @execution.generated_completion_preparation(sequence),
          @execution.generated_prepared_sequence(sequence),
          @execution.generated_sequence_step_index_at(sequence, 0).unwrap(),
          max_rows,
          {
            max_nodes: limits.max_value_nodes,
            max_text_bytes: max_value_bytes,
            max_depth: limits.max_value_depth,
            max_work: limits.max_work,
          },
          limits.max_workspace_slots,
          max_value_bytes,
          control_work_limit=Some(execution.max_work),
        ) {
        Ok(value) => value
        Err(_) => return Err(@connector.Execution(@execution.InputSet))
      }
      let state : CalendarSeriesProviderExecution = {
        active,
        progress: 0L,
        work: 0L,
        terminal: false,
        reclaimed: false,
      }
      Ok(
        @local.managed_provider_execution(
          quantum => calendar_series_provider_poll(state, quantum),
          fn() { @bounded.request_cancel(control) },
          fn() { state.terminal },
          fn() { cleanup_calendar_series_provider(state) },
        ),
      )
    },
  )
}
