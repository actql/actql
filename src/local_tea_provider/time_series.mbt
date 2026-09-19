///|
priv struct TimeSeriesProviderExecution {
  active : @tea.TimeSeriesExecution
  mut progress : Int64
  mut work : Int64
  mut terminal : Bool
  mut reclaimed : Bool
}

///|
fn time_series_provider_accepts(
  sequence : @execution.GeneratedSequence,
) -> Bool {
  let index = Ref(0)
  let accepted = @execution.generated_sequence_all_steps(sequence, fn(step) {
    let current = index.val
    index.val += 1
    current == 0 && step is @lower.TimeSeriesStep(_)
  })
  accepted && index.val == 1
}

///|
fn time_series_provider_delta(current : Int64, prior : Int64) -> Int64? {
  if current < prior {
    None
  } else {
    Some(current - prior)
  }
}

///|
fn time_series_provider_poll(
  value : TimeSeriesProviderExecution,
  quantum : Int,
) -> Result[@local.ManagedProviderPoll, @connector.FixedComputeIssue] {
  if value.terminal || quantum <= 0 {
    return Err(@connector.InvalidLimits)
  }
  let poll = match @tea.advance_time_series(value.active, quantum) {
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
    @tea.SeriesContinue(progress~, work~) => (progress, work, false)
    @tea.SeriesComplete(_, progress~, work~) => (progress, work, true)
    @tea.SeriesFailed(_, progress~, work~) => (progress, work, true)
    @tea.SeriesStopped(_, progress~, work~) => (progress, work, true)
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
  if terminal {
    value.terminal = true
  }
  match poll {
    @tea.SeriesContinue(_) =>
      Ok(@local.managed_provider_continue(progress_delta, work_delta))
    @tea.SeriesComplete(output, ..) =>
      Ok(@local.managed_provider_complete(output, progress_delta, work_delta))
    @tea.SeriesFailed(_, ..) =>
      Ok(
        @local.managed_provider_failed(
          @connector.Execution(@execution.InputSet),
          progress_delta,
          work_delta,
        ),
      )
    @tea.SeriesStopped(_, ..) =>
      Ok(@local.managed_provider_stopped_poll(progress_delta, work_delta))
  }
}

///|
fn cleanup_time_series_provider(
  value : TimeSeriesProviderExecution,
) -> Result[Bool, @connector.FixedComputeIssue] {
  if !value.terminal {
    return Ok(false)
  }
  if value.reclaimed {
    return Ok(true)
  }
  let cleaned = match @tea.cleanup_time_series(value.active) {
    Ok(result) => result
    Err(_) => return Err(@connector.Execution(@execution.InputSet))
  }
  if cleaned && !@tea.time_series_cleanup_pending(value.active) {
    value.reclaimed = true
  }
  Ok(value.reclaimed)
}

///|
pub fn time_series_provider(
  limits : @storage.Limits,
  capacity : @execution.ExecutionCapacity,
) -> @local.ManagedProvider {
  @local.managed_provider(
    time_series_provider_accepts,
    sequence => {
      if time_series_provider_accepts(sequence) {
        Some(capacity)
      } else {
        None
      }
    },
    fn(sequence, inputs, max_rows, max_value_bytes) {
      if !time_series_provider_accepts(sequence) ||
        !inputs.is_empty() ||
        max_rows < 0 ||
        max_value_bytes < 0 {
        return Err(@connector.InvalidLimits)
      }
      let control = @bounded.control()
      let active = match
        @tea.start_time_series(
          control,
          @execution.generated_completion_preparation(sequence),
          @execution.generated_prepared_sequence(sequence),
          0,
          max_rows,
          {
            max_nodes: limits.max_value_nodes,
            max_text_bytes: max_value_bytes,
            max_depth: limits.max_value_depth,
            max_work: limits.max_work,
          },
          limits.max_workspace_slots,
          max_value_bytes,
        ) {
        Ok(value) => value
        Err(_) => return Err(@connector.Execution(@execution.InputSet))
      }
      let state : TimeSeriesProviderExecution = {
        active,
        progress: 0L,
        work: 0L,
        terminal: false,
        reclaimed: false,
      }
      Ok(
        @local.managed_provider_execution(
          quantum => time_series_provider_poll(state, quantum),
          fn() { @bounded.request_cancel(control) },
          fn() { state.terminal },
          fn() { cleanup_time_series_provider(state) },
        ),
      )
    },
  )
}
