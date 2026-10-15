///|
priv enum CalendarSeriesPhase {
  ResolveCalendarInterval
  EmitCalendarInterval(Int64, Int64)
  FinishCalendarSeries
}

///|
priv struct CalendarSeriesState {
  mut cursor : @calendar_cursor.SeriesCursor?
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  start_contract : @contract.Contract
  end_contract : @contract.Contract
  start_first : Bool
  mut control_work_remaining : Int
  mut phase : CalendarSeriesPhase
}

///|
struct CalendarSeriesExecution {
  session : @bounded.Session[
    CalendarSeriesState,
    @execution.CompletedOutput,
    CalendarSeriesExecutionIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum CalendarSeriesPoll {
  CalendarContinue(progress~ : Int64, work~ : Int64)
  CalendarComplete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  CalendarFailed(CalendarSeriesExecutionIssue, progress~ : Int64, work~ : Int64)
  CalendarStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum CalendarSeriesExecutionIssue {
  InvalidCalendarKernel
  InvalidCalendarExecutionLimits
  CalendarControlWorkLimit
  InvalidCalendarTimestamp
  CalendarBoundary(@calendar_cursor.SeriesIssue)
  CalendarOutput(@execution.CaptureIssue)
  CalendarCompletion(@execution.TrustedOutputIssue)
  CalendarExecution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn calendar_series_step(
  state : CalendarSeriesState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[
  @execution.CompletedOutput,
  CalendarSeriesExecutionIssue,
] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if state.control_work_remaining == 0 {
      return @bounded.Failed(CalendarControlWorkLimit, progress, used)
    }
    match state.phase {
      ResolveCalendarInterval => {
        guard state.cursor is Some(cursor) else {
          return @bounded.Failed(InvalidCalendarKernel, progress, used)
        }
        let remaining = Int::min(quantum - used, state.control_work_remaining)
        let poll = match @calendar_cursor.advance_series(cursor, remaining) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(CalendarBoundary(issue), progress, used)
        }
        let work = match poll {
          CalendarSeriesContinue(work~)
          | CalendarSeriesRow(work~, ..)
          | CalendarSeriesComplete(work~)
          | CalendarSeriesFailed(_, work~) => work
        }
        // The original cursor reports only this advance's work. It retains its
        // own continuation and cumulative ceiling; neither resets at a yield.
        used += work
        state.control_work_remaining -= work
        match poll {
          CalendarSeriesContinue(_) => ()
          CalendarSeriesRow(start_ms~, end_ms~, ..) =>
            state.phase = EmitCalendarInterval(start_ms, end_ms)
          CalendarSeriesComplete(_) => {
            state.cursor = None
            state.phase = FinishCalendarSeries
          }
          CalendarSeriesFailed(issue, ..) =>
            return @bounded.Failed(CalendarBoundary(issue), progress, used)
        }
      }
      EmitCalendarInterval(start_ms, end_ms) => {
        used += 1
        state.control_work_remaining -= 1
        guard @value.epoch_milliseconds_timestamp(start_ms) is Some(start) &&
          @value.epoch_milliseconds_timestamp(end_ms) is Some(end) &&
          @value.checked_timestamp_value(start, state.start_contract)
          is Some(start_value) &&
          @value.checked_timestamp_value(end, state.end_contract)
          is Some(end_value) &&
          state.output is Some(output) else {
          return @bounded.Failed(InvalidCalendarTimestamp, progress, used)
        }
        let supplied = if state.start_first {
          [start_value, end_value]
        } else {
          [end_value, start_value]
        }
        match @execution.append_admitted_output(output, supplied) {
          Err(issue) =>
            return @bounded.Failed(CalendarOutput(issue), progress, used)
          Ok(_) => {
            progress += 1
            state.phase = ResolveCalendarInterval
          }
        }
      }
      FinishCalendarSeries => {
        used += 1
        state.control_work_remaining -= 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidCalendarKernel, progress, used)
        }
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(CalendarOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) =>
            @bounded.Failed(CalendarCompletion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_calendar_series_state(state : CalendarSeriesState) -> Bool {
  state.cursor = None
  state.phase = FinishCalendarSeries
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  if state.output is Some(output) {
    // The original buffer owner retains the same handle across bounded
    // reclamation retries. Completion acceptance never clears retained rows.
    if !@execution.reclaim_bounded_admitted_output(output, state.accepted.val) {
      return false
    }
    state.output = None
  }
  true
}

///|
/// A bounded realization of the exact original Calendar series. Profile
/// selection, operation obligations and task-level resource admission remain
/// with the ordinary checked/managed owners; this API installs no authority.
pub fn start_calendar_series(
  control : @bounded.Control,
  generated : @execution.GeneratedSequence,
  step : Int,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit? : Int? = None,
) -> Result[CalendarSeriesExecution, CalendarSeriesExecutionIssue] {
  if max_rows < 0 || max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidCalendarExecutionLimits)
  }
  let sequence = @execution.generated_prepared_sequence(generated)
  let preparation = @execution.generated_completion_preparation(generated)
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step) is Some(@lower.CalendarStep(series)) &&
    physical_equal(@lower.calendar_owner(series), owner) &&
    @lower.calendar_step(series) == step &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "TEA.calendar.series" &&
    @lower.input_ids(node).is_empty() &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) &&
    @schema.field_count(schema) == 2 &&
    @schema.lookup_reference(schema, "start") is Some(start_field) &&
    @schema.lookup_reference(schema, "end") is Some(end_field) &&
    @lower.calendar_row_bound(series) is Some(_) &&
    @lower.calendar_start(series) is Some(start_text) &&
    @lower.calendar_end(series) is Some(end_text) &&
    @value.timestamp_epoch_milliseconds(start_text) is Some(start) &&
    @value.timestamp_epoch_milliseconds(end_text) is Some(end) else {
    return Err(InvalidCalendarKernel)
  }
  let max_rows = match
    @execution.generated_calendar_output_ceiling(generated, step) {
    Some(ceiling) if ceiling < max_rows.to_int64() => ceiling.to_int()
    _ => max_rows
  }
  let control_work_limit = control_work_limit.unwrap_or(limits.max_work)
  if control_work_limit < 0 {
    return Err(InvalidCalendarExecutionLimits)
  }
  if control_work_limit == 0 {
    return Err(CalendarControlWorkLimit)
  }
  let options = @calendar.options(@lower.calendar_checked(series))
  let cursor = match
    @calendar_cursor.start_series(
      @lower.calendar_table(series),
      start,
      end,
      @calendar_options.unit(options),
      week_start=@calendar_options.week_start(options),
      max_rows~,
      max_work=control_work_limit,
    ) {
    Ok(value) => value
    Err(issue) => return Err(CalendarBoundary(issue))
  }
  let output = match
    @execution.prepare_bounded_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(CalendarOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    @execution.prepare_trusted_output_port(
      preparation,
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[],
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(CalendarCompletion(issue))
    }
  }
  let state : CalendarSeriesState = {
    cursor: Some(cursor),
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    start_contract: start_field.contract,
    end_contract: end_field.contract,
    start_first: @schema.field_reference_name_at(schema, 0) == Some("start"),
    control_work_remaining: control_work_limit,
    phase: ResolveCalendarInterval,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    calendar_series_step,
    cleanup_calendar_series_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_calendar_series(
  value : CalendarSeriesExecution,
  quantum : Int,
) -> Result[CalendarSeriesPoll, CalendarSeriesExecutionIssue] {
  guard value.token is Some(token) else {
    return Err(CalendarExecution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(CalendarExecution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(CalendarContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(CalendarComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(CalendarFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(CalendarStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_calendar_series(
  value : CalendarSeriesExecution,
) -> Result[Bool, CalendarSeriesExecutionIssue] {
  @bounded.cleanup(value.session).map_err(issue => CalendarExecution(issue))
}

///|
pub fn calendar_series_cleanup_pending(value : CalendarSeriesExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}
