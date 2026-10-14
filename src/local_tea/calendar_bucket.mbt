///|
priv enum CalendarBucketPhase {
  ReadCalendarInputField
  RecheckCalendarInputField
  ResolveCalendarBucket
  BuildCalendarBucket(Int64, Int64)
  EmitCalendarBucketRow
  FinishCalendarBucket
}

///|
priv struct CalendarBucketState {
  input : @execution.ProducerRead
  prepared : @lower.PreparedCalendar
  time_column : Int
  into_column : Int
  output_columns : Array[Int]
  input_width : Int
  input_rows : Int
  value_limits : @execution.ValueLimits
  workspace : Int
  into_contract : @contract.Contract
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut row : Int
  mut column : Int
  mut cells : Array[@value.Value?]
  mut recheck : @value.RecheckCursor?
  mut interval : @calendar_cursor.IntervalCursor?
  mut row_cursor : @execution.AdmittedOutputRowCursor?
  mut bucket : @value.Value?
  mut instant : Int64?
  mut remaining_work : Int
  mut phase : CalendarBucketPhase
}

///|
struct CalendarBucketExecution {
  session : @bounded.Session[
    CalendarBucketState,
    @execution.CompletedOutput,
    CalendarBucketExecutionIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum CalendarBucketPoll {
  BucketContinue(progress~ : Int64, work~ : Int64)
  BucketComplete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  BucketFailed(CalendarBucketExecutionIssue, progress~ : Int64, work~ : Int64)
  BucketStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum CalendarBucketExecutionIssue {
  InvalidCalendarBucketKernel
  InvalidCalendarBucketLimits
  InvalidCalendarBucketInput
  CalendarBucketWorkLimit
  CalendarBucketBoundary(@calendar_cursor.IntervalIssue)
  CalendarBucketRow(@execution.AdmittedOutputRowIssue)
  CalendarBucketOutput(@execution.CaptureIssue)
  CalendarBucketCompletion(@execution.TrustedOutputIssue)
  CalendarBucketExecution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn calendar_bucket_step(
  state : CalendarBucketState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[
  @execution.CompletedOutput,
  CalendarBucketExecutionIssue,
] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@execution.producer_read_available(state.input) {
      return @bounded.Failed(InvalidCalendarBucketInput, progress, used)
    }
    if state.remaining_work == 0 {
      return @bounded.Failed(CalendarBucketWorkLimit, progress, used)
    }
    match state.phase {
      ReadCalendarInputField => {
        used += 1
        state.remaining_work -= 1
        if state.row == state.input_rows {
          state.phase = FinishCalendarBucket
          continue
        }
        if state.column == state.input_width {
          guard state.instant is Some(instant) else {
            return @bounded.Failed(InvalidCalendarBucketInput, progress, used)
          }
          let options = @calendar.options(
            @lower.calendar_checked(state.prepared),
          )
          state.interval = Some(
            match
              @calendar_cursor.start_interval(
                @lower.calendar_table(state.prepared),
                instant,
                @calendar_options.unit(options),
                week_start=@calendar_options.week_start(options),
                max_work=state.remaining_work,
              ) {
              Ok(cursor) => cursor
              Err(issue) =>
                return @bounded.Failed(
                  CalendarBucketBoundary(issue),
                  progress,
                  used,
                )
            },
          )
          state.phase = ResolveCalendarBucket
          continue
        }
        match
          @execution.producer_read_cell_present(
            state.input,
            state.row,
            state.column,
          ) {
          Err(_) =>
            return @bounded.Failed(InvalidCalendarBucketInput, progress, used)
          Ok(false) => {
            state.cells.push(None)
            state.column += 1
          }
          Ok(true) => {
            guard @execution.start_producer_read_cell_recheck(
                state.input,
                state.row,
                state.column,
                {
                  max_nodes: state.value_limits.max_nodes,
                  max_text_bytes: state.value_limits.max_text_bytes,
                  max_depth: state.value_limits.max_depth,
                },
              )
              is Some(cursor) else {
              return @bounded.Failed(InvalidCalendarBucketInput, progress, used)
            }
            state.recheck = Some(cursor)
            state.phase = RecheckCalendarInputField
          }
        }
      }
      RecheckCalendarInputField => {
        used += 1
        state.remaining_work -= 1
        guard state.recheck is Some(cursor) &&
          @value.recheck_pending_frames(cursor) < state.workspace else {
          return @bounded.Failed(InvalidCalendarBucketLimits, progress, used)
        }
        match @value.advance_recheck_runtime_value(cursor) {
          RecheckContinue => ()
          RecheckFailed =>
            return @bounded.Failed(InvalidCalendarBucketInput, progress, used)
          RecheckComplete(checked, _, _) => {
            if state.column == state.time_column {
              guard checked.value is @value.Timestamp(text) &&
                @value.timestamp_epoch_milliseconds(text) is Some(instant) else {
                return @bounded.Failed(
                  InvalidCalendarBucketInput,
                  progress,
                  used,
                )
              }
              state.instant = Some(instant)
            }
            state.cells.push(Some(checked.value))
            state.column += 1
            state.recheck = None
            state.phase = ReadCalendarInputField
          }
        }
      }
      ResolveCalendarBucket => {
        guard state.interval is Some(cursor) else {
          return @bounded.Failed(InvalidCalendarBucketKernel, progress, used)
        }
        let poll = match
          @calendar_cursor.advance_interval(
            cursor,
            Int::min(quantum - used, state.remaining_work),
          ) {
          Ok(poll) => poll
          Err(issue) =>
            return @bounded.Failed(
              CalendarBucketBoundary(issue),
              progress,
              used,
            )
        }
        let work = match poll {
          IntervalContinue(work~)
          | IntervalReady(work~, ..)
          | IntervalFailed(_, work~) => work
        }
        used += work
        state.remaining_work -= work
        match poll {
          IntervalContinue(_) => ()
          IntervalFailed(issue, ..) =>
            return @bounded.Failed(
              CalendarBucketBoundary(issue),
              progress,
              used,
            )
          IntervalReady(start_ms~, end_ms~, ..) => {
            state.interval = None
            state.phase = BuildCalendarBucket(start_ms, end_ms)
          }
        }
      }
      BuildCalendarBucket(start_ms, end_ms) => {
        used += 1
        state.remaining_work -= 1
        guard state.into_contract.shape is @contract.Object(fields) &&
          @contract.field_count(fields) == 2 &&
          @contract.field_at(fields, 0) is Some(end_field) &&
          end_field.name == "end" &&
          @contract.field_at(fields, 1) is Some(start_field) &&
          start_field.name == "start" &&
          @value.epoch_milliseconds_timestamp(start_ms) is Some(start_text) &&
          @value.epoch_milliseconds_timestamp(end_ms) is Some(end_text) &&
          @value.checked_timestamp_value(start_text, start_field.contract)
          is Some(start) &&
          @value.checked_timestamp_value(end_text, end_field.contract)
          is Some(end) &&
          @value.prepare_contract_object_value(state.into_contract)
          is Some(builder) &&
          @value.append_contract_object_field(builder, 0, end.value) &&
          @value.append_contract_object_field(builder, 1, start.value) &&
          @value.finish_object_value(builder) is Some(bucket) &&
          state.output is Some(output) else {
          return @bounded.Failed(InvalidCalendarBucketKernel, progress, used)
        }
        state.bucket = Some(bucket)
        state.row_cursor = Some(
          match
            @execution.start_admitted_presence_output_row(
              output,
              state.workspace,
              column => {
                if column == state.into_column {
                  state.bucket.map(value => {
                    @execution.relation_cell(Some(value))
                  })
                } else {
                  state.output_columns
                  .get(column)
                  .bind(source => {
                    state.cells.get(source).map(@execution.relation_cell)
                  })
                }
              },
            ) {
            Ok(cursor) => cursor
            Err(issue) =>
              return @bounded.Failed(CalendarBucketRow(issue), progress, used)
          },
        )
        state.phase = EmitCalendarBucketRow
      }
      EmitCalendarBucketRow => {
        used += 1
        state.remaining_work -= 1
        guard state.row_cursor is Some(cursor) else {
          return @bounded.Failed(InvalidCalendarBucketKernel, progress, used)
        }
        match @execution.advance_admitted_output_row(cursor) {
          Err(issue) =>
            return @bounded.Failed(CalendarBucketRow(issue), progress, used)
          Ok(false) => ()
          Ok(true) => {
            if !@execution.cleanup_admitted_output_row(cursor) {
              return @bounded.Failed(
                InvalidCalendarBucketLimits,
                progress,
                used,
              )
            }
            state.row_cursor = None
            state.cells = []
            state.bucket = None
            state.instant = None
            state.row += 1
            state.column = 0
            state.phase = ReadCalendarInputField
            progress += 1
          }
        }
      }
      FinishCalendarBucket => {
        used += 1
        state.remaining_work -= 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidCalendarBucketKernel, progress, used)
        }
        state.rows.val = Some(
          match @execution.finish_admitted_output(output) {
            Ok(rows) => rows
            Err(issue) =>
              return @bounded.Failed(
                CalendarBucketOutput(issue),
                progress,
                used,
              )
          },
        )
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(CalendarBucketCompletion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_calendar_bucket_state(state : CalendarBucketState) -> Bool {
  if state.recheck is Some(cursor) {
    @value.cancel_recheck_runtime_value(cursor)
    state.recheck = None
  }
  state.interval = None
  if state.row_cursor is Some(cursor) {
    if !@execution.cleanup_admitted_output_row(cursor) {
      return false
    }
    state.row_cursor = None
  }
  state.cells = []
  state.bucket = None
  state.instant = None
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  if state.output is Some(output) {
    if !@execution.reclaim_bounded_admitted_output(output, state.accepted.val) {
      return false
    }
    state.output = None
  }
  true
}

///|
pub fn start_calendar_bucket(
  control : @bounded.Control,
  generated : @execution.GeneratedSequence,
  step : Int,
  input : @execution.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit? : Int? = None,
) -> Result[CalendarBucketExecution, CalendarBucketExecutionIssue] {
  if max_rows < 0 || max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidCalendarBucketLimits)
  }
  let owner = @execution.generated_sequence_owner(generated)
  let prepared = @lower.bound_preparation(owner)
  guard @execution.generated_sequence_step_count(generated) == 1 &&
    @execution.generated_sequence_step_index_at(generated, 0) == Some(step) &&
    @execution.generated_sequence_step_at(generated, 0)
    is Some(@lower.CalendarStep(calendar)) &&
    @lower.calendar_step(calendar) == step &&
    @lower.node_at(prepared, step) is Some(node) &&
    @lower.operation(node) == "TEA.calendar.bucket" &&
    @lower.calendar_row_bound(calendar) is None &&
    @execution.producer_read_matches_operation_input(input, owner, step, 0) &&
    @execution.producer_read_has_cell_access(input) &&
    @calendar_options.input(
      @calendar.options(@lower.calendar_checked(calendar)),
    )
    is @calendar_options.Field(time~, into~) &&
    @lower.preparation_schema_at(prepared, @pipeline.Step(step)) is Some(schema) else {
    return Err(InvalidCalendarBucketKernel)
  }
  let input_schema = @execution.producer_read_schema(input)
  let width = @schema.field_count(input_schema)
  let count = @schema.field_count(schema)
  if width == 2147483647 ||
    count != width + 1 ||
    width > (max_entries - count) / 2 ||
    max_entries < count {
    return Err(InvalidCalendarBucketLimits)
  }
  let mapping = Array::make(count, -1)
  let mut into_column = -1
  let mut time_column = -1
  for column in 0..<width {
    let field = @schema.field_at(input_schema, column).unwrap()
    if @schema.lookup_reference(input_schema, time).map(value => value.name) ==
      Some(field.name) {
      time_column = column
    }
    for target in 0..<count {
      if @schema.field_at(schema, target).map(value => value.name) ==
        Some(field.name) {
        mapping[target] = column
      }
    }
  }
  for column in 0..<count {
    if @schema.field_reference_name_at(schema, column) == Some(into) {
      into_column = column
    } else if mapping[column] < 0 {
      return Err(InvalidCalendarBucketKernel)
    }
  }
  guard time_column >= 0 &&
    into_column >= 0 &&
    @schema.field_at(schema, into_column) is Some(into_field) else {
    return Err(InvalidCalendarBucketKernel)
  }
  let maximum = match
    @execution.generated_calendar_output_ceiling(generated, step) {
    Some(ceiling) if ceiling < max_rows.to_int64() => ceiling.to_int()
    _ => max_rows
  }
  let work = control_work_limit.unwrap_or(limits.max_work)
  if work < 0 || count == 2147483647 || width > work / (count + 1) {
    return Err(CalendarBucketWorkLimit)
  }
  let output = match
    @execution.prepare_bounded_admitted_output(
      owner,
      @pipeline.Step(step),
      maximum,
      limits,
    ) {
    Ok(output) => output
    Err(issue) => return Err(CalendarBucketOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    @execution.prepare_trusted_output_port(
      @execution.generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      _ => {
        if live.val && @execution.producer_read_available(input) {
          rows.val
        } else {
          None
        }
      },
      inputs=[input],
    ) {
    Ok(port) => port
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(CalendarBucketCompletion(issue))
    }
  }
  let state : CalendarBucketState = {
    input,
    prepared: calendar,
    time_column,
    into_column,
    output_columns: mapping,
    input_width: width,
    input_rows: @execution.producer_read_row_count(input),
    value_limits: limits,
    workspace: max_entries - count - width,
    into_contract: into_field.contract,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    row: 0,
    column: 0,
    cells: [],
    recheck: None,
    interval: None,
    row_cursor: None,
    bucket: None,
    instant: None,
    remaining_work: work - width * (count + 1),
    phase: ReadCalendarInputField,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    calendar_bucket_step,
    cleanup_calendar_bucket_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_calendar_bucket(
  value : CalendarBucketExecution,
  quantum : Int,
) -> Result[CalendarBucketPoll, CalendarBucketExecutionIssue] {
  guard value.token is Some(token) else {
    return Err(CalendarBucketExecution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(CalendarBucketExecution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BucketContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BucketComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BucketFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BucketStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_calendar_bucket(
  value : CalendarBucketExecution,
) -> Result[Bool, CalendarBucketExecutionIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    CalendarBucketExecution(issue)
  })
}

///|
pub fn calendar_bucket_cleanup_pending(value : CalendarBucketExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}
