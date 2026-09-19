///|
priv enum WatermarkPhase {
  BeginRecord
  ReadFields
  Classify
  CommitRecord
  Finish
}

///|
priv struct WatermarkState {
  input : @records.ProducerRead
  source : @storage.Storage
  mut output : @records.OutputBuilder?
  limits : @storage.Limits
  time_name : String
  timestamp : Bool
  watermark : Double
  drops_late : Bool
  watermark_contract : @contract.Contract
  late_contract : @contract.Contract
  decision_contract : @contract.Contract
  mut phase : WatermarkPhase
  mut record : Int
  mut field : Int
  mut fields : Array[(@schema.FieldName, @value.CheckedValue)]
  mut time : @value.CheckedValue?
}

///|
struct WatermarkExecution {
  session : @bounded.Session[WatermarkState, @records.Completed, WatermarkIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
}

///|
pub enum WatermarkPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@records.Completed, progress~ : Int64, work~ : Int64)
  Failed(WatermarkIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum WatermarkIssue {
  InvalidKernel
  InvalidLimits
  InputUnavailable
  InvalidRecord(Int)
  InvalidTime(Int)
  WorkspaceLimit
  Output(@records.Issue)
  Execution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn output_contract(
  carrier : @carrier.Carrier,
  name : String,
) -> @contract.Contract? {
  guard carrier is @carrier.EventValue(events) &&
    @carrier.lookup(@carrier.event_records(events), @schema.Unqualified(name))
    is @carrier.Present(field) else {
    return None
  }
  field.contract
}

///|
fn begin_record(state : WatermarkState) -> Result[Unit, WatermarkIssue] {
  guard @storage.record_field_count(state.source, state.record)
    is Some(field_count) else {
    return Err(InvalidRecord(state.record))
  }
  let current = match state.output {
    Some(output) => @records.output_workspace_slots(output)
    None => return Err(InvalidKernel)
  }
  if field_count > 2147483644 ||
    current > state.limits.max_workspace_slots ||
    field_count + 3 > state.limits.max_workspace_slots - current {
    return Err(WorkspaceLimit)
  }
  state.field = 0
  state.fields = []
  state.time = None
  state.phase = ReadFields
  Ok(())
}

///|
fn read_field(state : WatermarkState) -> Result[Unit, WatermarkIssue] {
  guard @storage.record_field_at(state.source, state.record, state.field)
    is Some((name, checked)) else {
    return Err(InvalidRecord(state.record))
  }
  if @schema.reference_name(name) == state.time_name {
    if state.time is Some(_) {
      return Err(InvalidRecord(state.record))
    }
    state.time = Some(checked)
  }
  state.fields.push((name, checked))
  state.field += 1
  Ok(())
}

///|
fn classify_record(state : WatermarkState) -> Result[Bool, WatermarkIssue] {
  guard state.time is Some(time) &&
    @value.event_time_milliseconds(time, state.timestamp) is Some(value) else {
    return Err(InvalidTime(state.record))
  }
  let late = value < state.watermark
  if late && state.drops_late {
    state.fields = []
    state.time = None
    state.record += 1
    state.phase = BeginRecord
    return Ok(false)
  }
  guard @value.checked_number_value(state.watermark, state.watermark_contract)
    is Some(watermark) &&
    @value.checked_boolean_value(late, state.late_contract) is Some(late_value) &&
    @value.checked_text_value(
      if late {
        "mark"
      } else {
        "keep"
      },
      state.decision_contract,
    )
    is Some(decision) else {
    return Err(InvalidKernel)
  }
  state.fields.push((@schema.Unqualified("watermark_ms"), watermark))
  state.fields.push((@schema.Unqualified("late"), late_value))
  state.fields.push((@schema.Unqualified("watermark_decision"), decision))
  state.phase = CommitRecord
  Ok(true)
}

///|
fn commit_record(state : WatermarkState) -> Result[Unit, WatermarkIssue] {
  guard state.output is Some(output) else { return Err(InvalidKernel) }
  match @records.append_record(output, state.fields) {
    Ok(_) => {
      state.fields = []
      state.time = None
      state.record += 1
      state.phase = BeginRecord
      Ok(())
    }
    Err(issue) => Err(Output(issue))
  }
}

///|
fn watermark_step(
  state : WatermarkState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, WatermarkIssue] {
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
          match begin_record(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = Finish
        }
      ReadFields => {
        let count = @storage.record_field_count(state.source, state.record).unwrap_or(
          -1,
        )
        if state.field < count {
          match read_field(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = Classify
        }
      }
      Classify => {
        used += 1
        match classify_record(state) {
          Ok(retained) => if !retained { progress += 1 }
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CommitRecord => {
        used += 1
        match commit_record(state) {
          Ok(_) => progress += 1
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      Finish => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(Output(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_state(state : WatermarkState) -> Bool {
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.fields = []
  state.time = None
  true
}

///|
pub fn start_watermark(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[WatermarkExecution, WatermarkIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.EventStep(event)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "TEA.watermark.label" &&
    @records.producer_read_matches_operation_input(input, owner, step, 0) &&
    @lower.event_watermark(event) is Some(watermark) &&
    @lower.event_watermark_drops_late(event) is Some(drops_late) else {
    return Err(InvalidKernel)
  }
  guard @records.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.EventValue(events) else {
    return Err(InputUnavailable)
  }
  if limits.max_value_nodes < 1 || limits.max_workspace_slots < 3 {
    return Err(InvalidLimits)
  }
  let output_carrier = @lower.event_output_carrier(event)
  guard output_contract(output_carrier, "watermark_ms")
    is Some(watermark_contract) &&
    output_contract(output_carrier, "late") is Some(late_contract) &&
    output_contract(output_carrier, "watermark_decision")
    is Some(decision_contract) else {
    return Err(InvalidKernel)
  }
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
  let state : WatermarkState = {
    input,
    source,
    output: Some(output),
    limits,
    time_name: @schema.reference_name(@carrier.event_time(events).name),
    timestamp: @carrier.event_clock_encoding(events) == @carrier.UtcTimestamp,
    watermark,
    drops_late,
    watermark_contract,
    late_contract,
    decision_contract,
    phase: BeginRecord,
    record: 0,
    field: 0,
    fields: [],
    time: None,
  }
  let (session, token) = @bounded.start(
    control, state, watermark_step, cleanup_state, @records.discard_completed,
  )
  Ok({ session, token: Some(token), max_noninterruptible_value_nodes: 3, })
}

///|
pub fn watermark_max_noninterruptible_value_nodes(
  value : WatermarkExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn advance_watermark(
  value : WatermarkExecution,
  quantum : Int,
) -> Result[WatermarkPoll, WatermarkIssue] {
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
pub fn watermark_stopped(value : WatermarkExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn watermark_cleanup_pending(value : WatermarkExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_watermark(
  value : WatermarkExecution,
) -> Result[Bool, WatermarkIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
