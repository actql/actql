///|
priv enum RowsToEventsPhase {
  BeginRow
  ReadCell
  CommitRow
  FinishRows
}

///|
priv struct RowsToEventsState {
  input : @execution.ProducerRead
  mut output : @records.OutputBuilder?
  schema : @schema.Schema
  value_limits : @value.Limits
  mut phase : RowsToEventsPhase
  mut row : Int
  mut column : Int
  mut fields : Array[(@schema.FieldName, @value.CheckedValue)]
}

///|
struct RowsToEventsExecution {
  session : @bounded.Session[
    RowsToEventsState,
    @records.Completed,
    EventsBridgeIssue,
  ]
  mut token : @bounded.Token?
}

///|
pub enum RowsToEventsPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@records.Completed, progress~ : Int64, work~ : Int64)
  Failed(EventsBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
priv enum EventsToRowsPhase {
  BeginRecord
  FindField
  CommitRelationRow
  FinishRelation
}

///|
priv struct EventsToRowsState {
  input : @records.ProducerRead
  source : @storage.Storage
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  schema : @schema.Schema
  mut phase : EventsToRowsPhase
  mut record : Int
  mut column : Int
  mut candidate : Int
  mut values : Array[@value.CheckedValue]
}

///|
struct EventsToRowsExecution {
  session : @bounded.Session[
    EventsToRowsState,
    @execution.CompletedOutput,
    EventsBridgeIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum EventsToRowsPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  Failed(EventsBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum EventsBridgeIssue {
  InvalidKernel
  InputUnavailable
  InvalidRow(Int)
  InvalidRecord(Int)
  Output(@records.Issue)
  RelationOutput(@execution.CaptureIssue)
  Completion(@execution.TrustedOutputIssue)
  Execution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn rows_to_events_step(
  state : RowsToEventsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, EventsBridgeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@execution.producer_read_available(state.input) {
      return @bounded.Failed(InputUnavailable, progress, used)
    }
    match state.phase {
      BeginRow =>
        if state.row < @execution.producer_read_row_count(state.input) {
          state.column = 0
          state.fields = []
          state.phase = ReadCell
        } else {
          state.phase = FinishRows
        }
      ReadCell =>
        if state.column < @schema.field_count(state.schema) {
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            @execution.producer_read_checked_cell(
              state.input,
              state.row,
              state.column,
              state.value_limits,
            )
            is Some(checked) else {
            return @bounded.Failed(InvalidRow(state.row), progress, used)
          }
          state.fields.push((field.name, checked))
          state.column += 1
          used += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        used += 1
        match @records.append_record(output, state.fields) {
          Err(issue) => return @bounded.Failed(Output(issue), progress, used)
          Ok(_) => {
            state.fields = []
            state.row += 1
            state.phase = BeginRow
            progress += 1
          }
        }
      }
      FinishRows => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) => @bounded.Failed(Output(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_rows_to_events_state(state : RowsToEventsState) -> Bool {
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.fields = []
  true
}

///|
pub fn start_rows_to_events(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @execution.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[RowsToEventsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.EventStep(event)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "BRIDGE.rows.to_events" &&
    @lower.node_input_target(node, 0) ==
    Some(@pipeline.Input(@execution.producer_read_input_index(input))) &&
    physical_equal(@execution.producer_read_receiver(input), owner) &&
    @execution.producer_read_available(input) &&
    @carrier.kind(@lower.event_output_carrier(event)) == @carrier.EventsKind else {
    return Err(InvalidKernel)
  }
  let schema = @execution.producer_read_schema(input)
  let output = match
    @records.prepare_output(
      owner,
      @pipeline.Step(step),
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  let state : RowsToEventsState = {
    input,
    output: Some(output),
    schema,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    phase: BeginRow,
    row: 0,
    column: 0,
    fields: [],
  }
  let (session, token) = @bounded.start(
    control, state, rows_to_events_step, cleanup_rows_to_events_state, @records.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
pub fn advance_rows_to_events(
  value : RowsToEventsExecution,
  quantum : Int,
) -> Result[RowsToEventsPoll, EventsBridgeIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_rows_to_events(
  value : RowsToEventsExecution,
) -> Result[Bool, EventsBridgeIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}

///|
pub fn rows_to_events_cleanup_pending(value : RowsToEventsExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
fn events_to_rows_step(
  state : EventsToRowsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, EventsBridgeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@records.producer_read_available(state.input) {
      return @bounded.Failed(InputUnavailable, progress, used)
    }
    match state.phase {
      BeginRecord =>
        if state.record < @storage.record_count(state.source) {
          state.column = 0
          state.candidate = 0
          state.values = []
          state.phase = FindField
        } else {
          state.phase = FinishRelation
        }
      FindField =>
        if state.column < @schema.field_count(state.schema) {
          guard @schema.field_at(state.schema, state.column) is Some(expected) &&
            @storage.record_field_count(state.source, state.record)
            is Some(width) else {
            return @bounded.Failed(InvalidRecord(state.record), progress, used)
          }
          if state.candidate >= width {
            return @bounded.Failed(InvalidRecord(state.record), progress, used)
          }
          guard @storage.record_field_at(
              state.source,
              state.record,
              state.candidate,
            )
            is Some((name, checked)) else {
            return @bounded.Failed(InvalidRecord(state.record), progress, used)
          }
          used += 1
          state.candidate += 1
          if name == expected.name {
            state.values.push(checked)
            state.column += 1
            state.candidate = 0
          }
        } else {
          state.phase = CommitRelationRow
        }
      CommitRelationRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        used += 1
        match @execution.append_admitted_output(output, state.values) {
          Err(issue) =>
            return @bounded.Failed(RelationOutput(issue), progress, used)
          Ok(_) => {
            state.values = []
            state.record += 1
            state.phase = BeginRecord
            progress += 1
          }
        }
      }
      FinishRelation => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(RelationOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) => @bounded.Failed(Completion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_events_to_rows_state(state : EventsToRowsState) -> Bool {
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.values = []
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
pub fn start_events_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[EventsToRowsExecution, EventsBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.CarrierProjectionStep(projection)) &&
    @lower.carrier_projection_operation(projection) == @projection.Events &&
    @records.producer_read_matches_operation_input(input, owner, step, 0) &&
    @records.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.EventValue(_) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidKernel)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(RelationOutput(issue))
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
      inputs~,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : EventsToRowsState = {
    input,
    source,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    schema,
    phase: BeginRecord,
    record: 0,
    column: 0,
    candidate: 0,
    values: [],
  }
  let (session, token) = @bounded.start(
    control,
    state,
    events_to_rows_step,
    cleanup_events_to_rows_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_events_to_rows(
  value : EventsToRowsExecution,
  quantum : Int,
) -> Result[EventsToRowsPoll, EventsBridgeIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_events_to_rows(
  value : EventsToRowsExecution,
) -> Result[Bool, EventsBridgeIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}

///|
pub fn events_to_rows_cleanup_pending(value : EventsToRowsExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}
