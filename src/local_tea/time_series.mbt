///|
priv enum TimeSeriesPhase {
  EmitTime
  FinishSeries
}

///|
priv struct TimeSeriesState {
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  contract : @contract.Contract
  step : Int64
  row_count : Int
  mut current : Int64
  mut row : Int
  mut phase : TimeSeriesPhase
}

///|
struct TimeSeriesExecution {
  session : @bounded.Session[
    TimeSeriesState,
    @execution.CompletedOutput,
    TimeSeriesExecutionIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum TimeSeriesPoll {
  SeriesContinue(progress~ : Int64, work~ : Int64)
  SeriesComplete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  SeriesFailed(TimeSeriesExecutionIssue, progress~ : Int64, work~ : Int64)
  SeriesStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum TimeSeriesExecutionIssue {
  InvalidSeriesKernel
  InvalidSeriesLimits
  InvalidSeriesTimestamp
  SeriesOutput(@execution.CaptureIssue)
  SeriesCompletion(@execution.TrustedOutputIssue)
  SeriesExecution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn time_series_step(
  state : TimeSeriesState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, TimeSeriesExecutionIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    match state.phase {
      EmitTime =>
        if state.row < state.row_count {
          used += 1
          guard @value.epoch_milliseconds_timestamp(state.current) is Some(text) &&
            @value.checked_timestamp_value(text, state.contract) is Some(value) &&
            state.output is Some(output) else {
            return @bounded.Failed(InvalidSeriesTimestamp, progress, used)
          }
          match @execution.append_admitted_output(output, [value]) {
            Err(issue) =>
              return @bounded.Failed(SeriesOutput(issue), progress, used)
            Ok(_) => {
              state.row += 1
              progress += 1
              if state.row < state.row_count {
                if state.current > 9223372036854775807L - state.step {
                  return @bounded.Failed(InvalidSeriesTimestamp, progress, used)
                }
                state.current += state.step
              } else {
                state.phase = FinishSeries
              }
            }
          }
        } else {
          state.phase = FinishSeries
        }
      FinishSeries => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidSeriesKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(SeriesOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(SeriesCompletion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_time_series_state(state : TimeSeriesState) -> Bool {
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
pub fn start_time_series(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[TimeSeriesExecution, TimeSeriesExecutionIssue] {
  if max_rows < 0 || max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidSeriesLimits)
  }
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step) is Some(@lower.TimeSeriesStep(series)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "TEA.time_series" &&
    @lower.input_ids(node).is_empty() &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) &&
    @schema.field_count(schema) == 1 &&
    @schema.field_at(schema, 0) is Some(field) &&
    @schema.reference_name(field.name) == "time" &&
    @lower.time_series_row_count(series) <= max_rows &&
    @value.timestamp_epoch_milliseconds(@lower.time_series_start(series))
    is Some(start) else {
    return Err(InvalidSeriesKernel)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(SeriesOutput(issue))
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
      return Err(SeriesCompletion(issue))
    }
  }
  let state : TimeSeriesState = {
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    contract: field.contract,
    step: @lower.time_series_step(series),
    row_count: @lower.time_series_row_count(series),
    current: start,
    row: 0,
    phase: EmitTime,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    time_series_step,
    cleanup_time_series_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_time_series(
  value : TimeSeriesExecution,
  quantum : Int,
) -> Result[TimeSeriesPoll, TimeSeriesExecutionIssue] {
  guard value.token is Some(token) else {
    return Err(SeriesExecution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(SeriesExecution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(SeriesContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(SeriesComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(SeriesFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(SeriesStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_time_series(
  value : TimeSeriesExecution,
) -> Result[Bool, TimeSeriesExecutionIssue] {
  @bounded.cleanup(value.session).map_err(issue => SeriesExecution(issue))
}

///|
pub fn time_series_cleanup_pending(value : TimeSeriesExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}
