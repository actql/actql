///|
priv enum WatermarkPhase {
  BeginRecord
  ReadFields
  Classify
  CommitRecord
  AppendRecord
  Finish
}

///|
priv enum WatermarkSource {
  Stored(@records.ProducerRead, @storage.Storage)
  Viewed(@lifecycle.ProducerView)
}

///|
priv struct WatermarkState {
  source : WatermarkSource
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
  mut append : @records.RecordAppend?
  mut control_work_remaining : Int
}

///|
fn watermark_source_available(source : WatermarkSource) -> Bool {
  match source {
    Stored(input, _) => @records.producer_read_available(input)
    Viewed(view) => @lifecycle.producer_view_record_count(view) is Some(_)
  }
}

///|
fn watermark_source_record_count(source : WatermarkSource) -> Int? {
  match source {
    Stored(_, storage) => Some(@storage.record_count(storage))
    Viewed(view) => @lifecycle.producer_view_record_count(view)
  }
}

///|
fn watermark_source_field_count(source : WatermarkSource, record : Int) -> Int? {
  match source {
    Stored(_, storage) => @storage.record_field_count(storage, record)
    Viewed(view) =>
      match @lifecycle.producer_view_record_field_count(view, record) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn watermark_source_field(
  source : WatermarkSource,
  record : Int,
  field : Int,
) -> (@schema.FieldName, @value.CheckedValue)? {
  match source {
    Stored(_, storage) => @storage.record_field_at(storage, record, field)
    Viewed(view) =>
      match @lifecycle.producer_view_record_field(view, record, field) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
/// Private observation only; Session retains cleanup and completion authority.
#warnings("-unused_field")
struct WatermarkExecution {
  state : WatermarkState
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
  ControlWorkLimit
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
  guard watermark_source_field_count(state.source, state.record)
    is Some(field_count) else {
    return Err(InvalidRecord(state.record))
  }
  let current = match state.output {
    Some(output) => @records.output_workspace_slots(output)
    None => return Err(InvalidKernel)
  }
  if field_count > 2147483643 ||
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
  guard watermark_source_field(state.source, state.record, state.field)
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
  let current = match state.output {
    Some(output) => @records.output_workspace_slots(output)
    None => return Err(InvalidKernel)
  }
  guard event_emission_workspace(
      state.fields.length() + 3,
      1,
      state.limits.max_value_depth,
      state.fields.length() + 4,
    )
    is Some(needed) &&
    current <= state.limits.max_workspace_slots &&
    needed <= state.limits.max_workspace_slots - current else {
    return Err(WorkspaceLimit)
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
  match
    @records.start_record_append(
      output,
      state.fields,
      external_workspace_slots=state.fields.length() + 1,
    ) {
    Ok(append) => {
      state.append = Some(append)
      state.phase = AppendRecord
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
    if !watermark_source_available(state.source) {
      return @bounded.Failed(InputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(ControlWorkLimit, progress, used)
    }
    match state.phase {
      BeginRecord =>
        if state.record <
          watermark_source_record_count(state.source).unwrap_or(-1) {
          match begin_record(state) {
            Ok(_) => used += 1
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = Finish
        }
      ReadFields => {
        let count = watermark_source_field_count(state.source, state.record).unwrap_or(
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
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      AppendRecord => {
        used += 1
        guard state.append is Some(append) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        match @records.advance_record_append(append) {
          Ok(false) => ()
          Ok(true) => {
            state.append = None
            state.fields = []
            state.time = None
            state.record += 1
            state.phase = BeginRecord
            progress += 1
          }
          Err(issue) => return @bounded.Failed(Output(issue), progress, used)
        }
      }
      Finish => {
        used += 1
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
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_state(state : WatermarkState) -> Bool {
  if state.append is Some(append) {
    @records.cleanup_record_append(append) |> ignore
    state.append = None
  }
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.fields = []
  state.time = None
  true
}

///|
fn start_watermark_source(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  source : WatermarkSource,
  input_carrier : @carrier.Carrier,
  output_carrier : @carrier.Carrier,
  watermark : Double,
  drops_late : Bool,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit : Int,
) -> Result[WatermarkExecution, WatermarkIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard input_carrier is @carrier.EventValue(events) else {
    return Err(InputUnavailable)
  }
  if limits.max_value_nodes < 1 || limits.max_workspace_slots < 3 {
    return Err(InvalidLimits)
  }
  if control_work_limit < 0 {
    return Err(InvalidLimits)
  }
  if control_work_limit == 0 {
    return Err(ControlWorkLimit)
  }
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
    append: None,
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control, state, watermark_step, cleanup_state, @records.discard_completed,
  )
  Ok({
    state,
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: 3,
  })
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
  control_work_limit? : Int? = None,
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
  guard @records.producer_read_storage(input) is Some(storage) else {
    return Err(InputUnavailable)
  }
  start_watermark_source(
    control,
    sequence,
    step,
    Stored(input, storage),
    @storage.carrier(storage),
    @lower.event_output_carrier(event),
    watermark,
    drops_late,
    limits,
    storage_bytes,
    available,
    control_work_limit.unwrap_or(limits.max_work),
  )
}

///|
pub fn start_watermark_view(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[WatermarkExecution, WatermarkIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.EventStep(event)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "TEA.watermark.label" &&
    @lower.node_input_target(node, 0) is Some(target) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
    is Some(input_carrier) &&
    @lifecycle.producer_view_kind(input) == @carrier.EventsKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_view_record_count(input) is Some(_) &&
    @lower.event_watermark(event) is Some(watermark) &&
    @lower.event_watermark_drops_late(event) is Some(drops_late) else {
    return Err(InvalidKernel)
  }
  start_watermark_source(
    control,
    sequence,
    step,
    Viewed(input),
    input_carrier,
    @lower.event_output_carrier(event),
    watermark,
    drops_late,
    limits,
    storage_bytes,
    available,
    control_work_limit.unwrap_or(limits.max_work),
  )
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
