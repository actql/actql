///|
priv enum EventWindowPhase {
  BeginRecord
  ReadField
  PrepareMembership
  SeekEarliest
  BuildMembership
  CopyMembership
  CommitMembership
  AppendMembership
  Finish
}

///|
priv enum EventWindowSource {
  Stored(@records.ProducerRead, @storage.Storage)
  Viewed(@lifecycle.ProducerView)
}

///|
priv struct EventWindowState {
  source : EventWindowSource
  mut output : @records.OutputBuilder?
  limits : @storage.Limits
  window : @lower.PreparedWindow
  time_name : String
  timestamp : Bool
  start_name : @schema.FieldName
  end_name : @schema.FieldName
  start_contract : @contract.Contract
  end_contract : @contract.Contract
  size : Int64
  step : Int64
  offset : Int64
  mut phase : EventWindowPhase
  mut record : Int
  mut field : Int
  mut fields : Array[(@schema.FieldName, @value.CheckedValue)]
  mut emission : Array[(@schema.FieldName, @value.CheckedValue)]
  mut emission_field : Int
  mut append : @records.RecordAppend?
  mut time : @value.CheckedValue?
  mut coordinate : @grid.Coordinate?
  mut current : @bigint.BigInt
  mut latest : @bigint.BigInt
  mut control_work_remaining : Int
}

///|
fn event_window_source_available(source : EventWindowSource) -> Bool {
  match source {
    Stored(input, _) => @records.producer_read_available(input)
    Viewed(view) => @lifecycle.producer_view_record_count(view) is Some(_)
  }
}

///|
fn event_window_source_record_count(source : EventWindowSource) -> Int? {
  match source {
    Stored(_, storage) => Some(@storage.record_count(storage))
    Viewed(view) => @lifecycle.producer_view_record_count(view)
  }
}

///|
fn event_window_source_field_count(
  source : EventWindowSource,
  record : Int,
) -> Int? {
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
fn event_window_source_field(
  source : EventWindowSource,
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
struct EventWindowExecution {
  state : EventWindowState
  session : @bounded.Session[
    EventWindowState,
    @records.Completed,
    EventWindowIssue,
  ]
  mut token : @bounded.Token?
}

///|
pub enum EventWindowPoll {
  EventWindowContinue(progress~ : Int64, work~ : Int64)
  EventWindowComplete(@records.Completed, progress~ : Int64, work~ : Int64)
  EventWindowFailed(EventWindowIssue, progress~ : Int64, work~ : Int64)
  EventWindowStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum EventWindowIssue {
  InvalidEventWindowKernel
  InvalidEventWindowLimits
  EventWindowInputUnavailable
  InvalidEventWindowRecord(Int)
  InvalidEventWindowTime(Int)
  EventWindowArithmetic(Int)
  EventWindowWorkLimit
  EventWindowWorkspaceLimit
  EventWindowOutput(@records.Issue)
  EventWindowExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn event_window_coordinate(
  value : @value.CheckedValue,
  timestamp : Bool,
) -> @grid.Coordinate? {
  if timestamp {
    guard value.value is @value.Timestamp(text) &&
      @value.timestamp_epoch_milliseconds(text) is Some(milliseconds) else {
      return None
    }
    Some(@grid.from_timestamp_milliseconds(milliseconds))
  } else {
    guard value.value is @value.Number(number) &&
      !number.is_nan() &&
      !number.is_inf() else {
      return None
    }
    @grid.from_finite_number(number)
  }
}

///|
fn event_window_output_contract(
  carrier : @carrier.Carrier,
  name : @schema.FieldName,
) -> @contract.Contract? {
  guard carrier is @carrier.EventValue(events) &&
    @carrier.lookup(@carrier.event_records(events), name)
    is @carrier.Present(field) else {
    return None
  }
  field.contract
}

///|
fn event_window_begin_record(
  state : EventWindowState,
) -> Result[Unit, EventWindowIssue] {
  guard event_window_source_field_count(state.source, state.record)
    is Some(field_count) else {
    return Err(InvalidEventWindowRecord(state.record))
  }
  let current = match state.output {
    Some(output) => @records.output_workspace_slots(output)
    None => return Err(InvalidEventWindowKernel)
  }
  guard field_count <= state.limits.max_fields_per_record - 2 &&
    field_count <= (2147483647 - 4) / 2 &&
    current <= state.limits.max_workspace_slots &&
    field_count + 2 <= state.limits.max_workspace_slots - current else {
    return Err(EventWindowWorkspaceLimit)
  }
  state.field = 0
  state.fields = []
  state.emission = []
  state.time = None
  state.coordinate = None
  state.phase = ReadField
  Ok(())
}

///|
fn event_window_read_field(
  state : EventWindowState,
) -> Result[Unit, EventWindowIssue] {
  guard event_window_source_field(state.source, state.record, state.field)
    is Some((name, checked)) else {
    return Err(InvalidEventWindowRecord(state.record))
  }
  if @schema.reference_name(name) == state.time_name {
    if state.time is Some(_) {
      return Err(InvalidEventWindowRecord(state.record))
    }
    state.time = Some(checked)
  }
  state.fields.push((name, checked))
  state.field += 1
  Ok(())
}

///|
fn event_window_prepare_membership(
  state : EventWindowState,
) -> Result[Unit, EventWindowIssue] {
  guard state.time is Some(time) &&
    event_window_coordinate(time, state.timestamp) is Some(coordinate) else {
    return Err(InvalidEventWindowTime(state.record))
  }
  state.coordinate = Some(coordinate)
  let latest = @grid.latest_start(coordinate, state.step, state.offset)
  let end = latest + @bigint.BigInt::from_int64(state.size)
  if @grid.compare(coordinate, latest) < 0 ||
    @grid.compare(coordinate, end) >= 0 {
    state.fields = []
    state.time = None
    state.coordinate = None
    state.record += 1
    state.phase = BeginRecord
    return Ok(())
  }
  state.current = latest
  state.latest = latest
  state.phase = SeekEarliest
  Ok(())
}

///|
fn event_window_seek_earliest(
  state : EventWindowState,
) -> Result[Unit, EventWindowIssue] {
  if @lower.window_kind(state.window) == @window.Fixed {
    state.phase = BuildMembership
    return Ok(())
  }
  match state.coordinate {
    Some(time) => {
      let candidate = state.current - @bigint.BigInt::from_int64(state.step)
      let end = candidate + @bigint.BigInt::from_int64(state.size)
      if @grid.compare(time, candidate) >= 0 && @grid.compare(time, end) < 0 {
        state.current = candidate
      } else {
        state.phase = BuildMembership
      }
    }
    None => return Err(InvalidEventWindowTime(state.record))
  }
  Ok(())
}

///|
fn event_window_build_membership(
  state : EventWindowState,
) -> Result[Unit, EventWindowIssue] {
  guard state.output is Some(output) else {
    return Err(InvalidEventWindowKernel)
  }
  let current = @records.output_workspace_slots(output)
  guard event_emission_workspace(
      state.fields.length() + 2,
      if @lower.window_kind(state.window) == @window.Sliding {
        2
      } else {
        1
      },
      state.limits.max_value_depth,
      state.fields.length() * 2 + 4,
    )
    is Some(needed) &&
    current <= state.limits.max_workspace_slots &&
    needed <= state.limits.max_workspace_slots - current else {
    return Err(EventWindowWorkspaceLimit)
  }
  state.emission = []
  state.emission_field = 0
  state.phase = CopyMembership
  Ok(())
}

///|
fn event_window_copy_membership(
  state : EventWindowState,
) -> Result[Unit, EventWindowIssue] {
  if state.emission_field < state.fields.length() {
    state.emission.push(state.fields[state.emission_field])
    state.emission_field += 1
    return Ok(())
  }
  guard state.coordinate is Some(_) &&
    @grid.exact_binary64_boundary(state.current) is Some(start) &&
    @grid.exact_binary64_boundary(
      state.current + @bigint.BigInt::from_int64(state.size),
    )
    is Some(end) else {
    return Err(EventWindowArithmetic(state.record))
  }
  guard @value.checked_number_value(start, state.start_contract)
    is Some(start_value) &&
    @value.checked_number_value(end, state.end_contract) is Some(end_value) else {
    return Err(InvalidEventWindowKernel)
  }
  state.emission.push((state.start_name, start_value))
  state.emission.push((state.end_name, end_value))
  state.phase = CommitMembership
  Ok(())
}

///|
fn event_window_commit_membership(
  state : EventWindowState,
) -> Result[Unit, EventWindowIssue] {
  guard state.output is Some(output) else {
    return Err(InvalidEventWindowKernel)
  }
  match
    @records.start_record_append(
      output,
      state.emission,
      external_workspace_slots=state.fields.length() +
        state.emission.length() +
        2,
    ) {
    Err(issue) => Err(EventWindowOutput(issue))
    Ok(append) => {
      state.append = Some(append)
      state.phase = AppendMembership
      Ok(())
    }
  }
}

///|
fn event_window_step(
  state : EventWindowState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, EventWindowIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !event_window_source_available(state.source) {
      return @bounded.Failed(EventWindowInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(EventWindowWorkLimit, progress, used)
    }
    match state.phase {
      BeginRecord =>
        if state.record <
          event_window_source_record_count(state.source).unwrap_or(-1) {
          used += 1
          match event_window_begin_record(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = Finish
        }
      ReadField => {
        let count = event_window_source_field_count(state.source, state.record).unwrap_or(
          -1,
        )
        if state.field < count {
          used += 1
          match event_window_read_field(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = PrepareMembership
        }
      }
      PrepareMembership => {
        used += 1
        match event_window_prepare_membership(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      SeekEarliest => {
        used += 1
        match event_window_seek_earliest(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      BuildMembership => {
        used += 1
        match event_window_build_membership(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyMembership => {
        used += 1
        match event_window_copy_membership(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CommitMembership => {
        used += 1
        match event_window_commit_membership(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      AppendMembership => {
        used += 1
        guard state.append is Some(append) else {
          return @bounded.Failed(InvalidEventWindowKernel, progress, used)
        }
        match @records.advance_record_append(append) {
          Ok(false) => ()
          Ok(true) => {
            state.append = None
            state.emission = []
            state.emission_field = 0
            if state.current == state.latest {
              state.fields = []
              state.time = None
              state.coordinate = None
              state.record += 1
              state.phase = BeginRecord
            } else {
              state.current += @bigint.BigInt::from_int64(state.step)
              state.phase = BuildMembership
            }
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(EventWindowOutput(issue), progress, used)
        }
      }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidEventWindowKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) =>
            @bounded.Failed(EventWindowOutput(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_event_window_state(state : EventWindowState) -> Bool {
  if state.append is Some(append) {
    @records.cleanup_record_append(append) |> ignore
    state.append = None
  }
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.fields = []
  state.emission = []
  state.emission_field = 0
  state.time = None
  state.coordinate = None
  true
}

///|
fn event_window_output_bound(records : Int, size : Int64, step : Int64) -> Int? {
  if records < 0 || size <= 0L || step <= 0L {
    return None
  }
  let quotient = size / step
  let multiplier = quotient + (if size % step == 0L { 0L } else { 1L })
  if multiplier > 2147483647L ||
    (records != 0 && multiplier > (2147483647 / records).to_int64()) {
    None
  } else {
    Some(records * multiplier.to_int())
  }
}

///|
fn start_event_window_source(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  source : EventWindowSource,
  input_carrier : @carrier.Carrier,
  window : @lower.PreparedWindow,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit : Int,
) -> Result[EventWindowExecution, EventWindowIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard input_carrier is @carrier.EventValue(events) &&
    event_window_source_record_count(source) is Some(records) else {
    return Err(EventWindowInputUnavailable)
  }
  if control_work_limit < 0 {
    return Err(InvalidEventWindowLimits)
  }
  if control_work_limit == 0 {
    return Err(EventWindowWorkLimit)
  }
  let size = @lower.window_size(window)
  let step_size = @lower.window_effective_step(window)
  let (start_name, end_name) = @lower.window_boundaries(window)
  let output_carrier = @lower.window_output_carrier(window)
  guard output_carrier is @carrier.EventValue(output_events) else {
    return Err(InvalidEventWindowKernel)
  }
  let output_records = @carrier.event_records(output_events)
  let declared_fields = @carrier.field_count(output_records)
  let admitted_fields = if @carrier.field_set(output_records) == @carrier.Closed {
    declared_fields
  } else {
    limits.max_fields_per_record
  }
  guard size > 0L &&
    step_size > 0L &&
    records <= limits.max_input_records &&
    event_window_output_bound(records, size, step_size) is Some(maximum) &&
    maximum <= limits.max_records &&
    declared_fields <= limits.max_fields_per_record &&
    admitted_fields <= 2147483645 &&
    (
      maximum == 0 ||
      admitted_fields + 2 <= limits.max_workspace_slots / maximum
    ) &&
    event_window_output_contract(output_carrier, start_name)
    is Some(start_contract) &&
    event_window_output_contract(output_carrier, end_name) is Some(end_contract) else {
    return Err(InvalidEventWindowLimits)
  }
  let additional = if @lower.window_kind(window) == @window.Sliding {
    [start_name]
  } else {
    []
  }
  let output = match
    @records.prepare_output_with_identities(
      owner,
      @pipeline.Step(step),
      additional,
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(EventWindowOutput(issue))
  }
  let state : EventWindowState = {
    source,
    output: Some(output),
    limits,
    window,
    time_name: @schema.reference_name(@carrier.event_time(events).name),
    timestamp: @carrier.event_clock_encoding(events) == @carrier.UtcTimestamp,
    start_name,
    end_name,
    start_contract,
    end_contract,
    size,
    step: step_size,
    offset: @lower.window_offset(window),
    phase: BeginRecord,
    record: 0,
    field: 0,
    fields: [],
    emission: [],
    emission_field: 0,
    append: None,
    time: None,
    coordinate: None,
    current: @bigint.BigInt::from_int(0),
    latest: @bigint.BigInt::from_int(0),
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control, state, event_window_step, cleanup_event_window_state, @records.discard_completed,
  )
  Ok({ state, session, token: Some(token), })
}

///|
pub fn start_event_window(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[EventWindowExecution, EventWindowIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.WindowStep(window)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.window_preserves_events(window) &&
    (
      @lower.operation(node) == "TEA.window.fixed_label" ||
      @lower.operation(node) == "TEA.window.sliding_assign"
    ) &&
    @records.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidEventWindowKernel)
  }
  guard @records.producer_read_storage(input) is Some(storage) else {
    return Err(EventWindowInputUnavailable)
  }
  start_event_window_source(
    control,
    sequence,
    step,
    Stored(input, storage),
    @storage.carrier(storage),
    window,
    limits,
    storage_bytes,
    available,
    control_work_limit.unwrap_or(limits.max_work),
  )
}

///|
pub fn start_event_window_view(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[EventWindowExecution, EventWindowIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.WindowStep(window)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.window_preserves_events(window) &&
    (
      @lower.operation(node) == "TEA.window.fixed_label" ||
      @lower.operation(node) == "TEA.window.sliding_assign"
    ) &&
    @lower.node_input_target(node, 0) is Some(target) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
    is Some(input_carrier) &&
    @lifecycle.producer_view_kind(input) == @carrier.EventsKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) else {
    return Err(InvalidEventWindowKernel)
  }
  start_event_window_source(
    control,
    sequence,
    step,
    Viewed(input),
    input_carrier,
    window,
    limits,
    storage_bytes,
    available,
    control_work_limit.unwrap_or(limits.max_work),
  )
}

///|
pub fn advance_event_window(
  value : EventWindowExecution,
  quantum : Int,
) -> Result[EventWindowPoll, EventWindowIssue] {
  guard value.token is Some(token) else {
    return Err(EventWindowExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(EventWindowExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(EventWindowContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(EventWindowComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(EventWindowFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(EventWindowStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_event_window(
  value : EventWindowExecution,
) -> Result[Bool, EventWindowIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    EventWindowExecutionIssue(issue)
  })
}

///|
pub fn event_window_cleanup_pending(value : EventWindowExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}
