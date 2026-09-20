///|
priv enum EventWindowPhase {
  BeginRecord
  ReadField
  PrepareMembership
  SeekEarliest
  BuildMembership
  CommitMembership
  Finish
}

///|
priv enum EventWindowCoordinate {
  Exact(Int64)
  Binary(Double)
}

///|
priv struct EventWindowState {
  input : @records.ProducerRead
  source : @storage.Storage
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
  mut time : @value.CheckedValue?
  mut coordinate : EventWindowCoordinate?
  mut exact_current : Int64
  mut exact_latest : Int64
  mut binary_current : Double
  mut binary_latest : Double
}

///|
struct EventWindowExecution {
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
  EventWindowWorkspaceLimit
  EventWindowOutput(@records.Issue)
  EventWindowExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn event_window_floor_mod(value : Int64, divisor : Int64) -> Int64 {
  let remainder = value % divisor
  if remainder < 0L {
    remainder + divisor
  } else {
    remainder
  }
}

///|
fn event_window_latest_exact(
  time : Int64,
  step : Int64,
  offset : Int64,
) -> Int64? {
  let grid = event_window_floor_mod(offset, step)
  let remainder = event_window_floor_mod(time, step)
  let delta = event_window_floor_mod(remainder - grid, step)
  if time < -9223372036854775807L - 1L + delta {
    None
  } else {
    Some(time - delta)
  }
}

///|
fn event_window_latest_binary(
  time : Double,
  step : Double,
  offset : Double,
) -> Double? {
  let shifted = (time - offset) / step
  if shifted.is_nan() || shifted.is_inf() {
    return None
  }
  let start = shifted.floor() * step + offset
  if start.is_nan() || start.is_inf() || start > time {
    None
  } else {
    Some(if start == 0.0 { 0.0 } else { start })
  }
}

///|
fn event_window_exact_double(value : Int64) -> Double? {
  if value < -9007199254740991L || value > 9007199254740991L {
    None
  } else {
    Some(value.to_double())
  }
}

///|
fn event_window_coordinate(
  value : @value.CheckedValue,
  timestamp : Bool,
) -> EventWindowCoordinate? {
  if timestamp {
    guard value.value is @value.Timestamp(text) &&
      @value.timestamp_epoch_milliseconds(text) is Some(milliseconds) else {
      return None
    }
    Some(Exact(milliseconds))
  } else {
    guard value.value is @value.Number(number) &&
      !number.is_nan() &&
      !number.is_inf() else {
      return None
    }
    match @scalar.read_safe_integer(number.floor()) {
      Some(floor) => Some(Exact(floor))
      None => Some(Binary(number))
    }
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
  guard @storage.record_field_count(state.source, state.record)
    is Some(field_count) else {
    return Err(InvalidEventWindowRecord(state.record))
  }
  if field_count > state.limits.max_fields_per_record - 2 ||
    field_count + 2 > state.limits.max_workspace_slots {
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
  guard @storage.record_field_at(state.source, state.record, state.field)
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
  match coordinate {
    Exact(time_floor) => {
      guard event_window_latest_exact(time_floor, state.step, state.offset)
        is Some(latest) else {
        return Err(EventWindowArithmetic(state.record))
      }
      if latest > 9223372036854775807L - state.size {
        return Err(EventWindowArithmetic(state.record))
      }
      if time_floor < latest || time_floor >= latest + state.size {
        state.fields = []
        state.time = None
        state.coordinate = None
        state.record += 1
        state.phase = BeginRecord
        return Ok(())
      }
      state.exact_current = latest
      state.exact_latest = latest
    }
    Binary(time_value) => {
      let step = state.step.to_double()
      let grid = event_window_floor_mod(state.offset, state.step).to_double()
      guard event_window_latest_binary(time_value, step, grid) is Some(latest) else {
        return Err(EventWindowArithmetic(state.record))
      }
      let end = latest + state.size.to_double()
      if end.is_nan() || end.is_inf() || end <= latest {
        return Err(EventWindowArithmetic(state.record))
      }
      if time_value < latest || time_value >= end {
        state.fields = []
        state.time = None
        state.coordinate = None
        state.record += 1
        state.phase = BeginRecord
        return Ok(())
      }
      state.binary_current = latest
      state.binary_latest = latest
    }
  }
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
    Some(Exact(time_floor)) => {
      if state.exact_current < -9223372036854775807L - 1L + state.step {
        state.phase = BuildMembership
        return Ok(())
      }
      let candidate = state.exact_current - state.step
      if candidate > 9223372036854775807L - state.size {
        return Err(EventWindowArithmetic(state.record))
      }
      let end = candidate + state.size
      if candidate <= time_floor && time_floor < end {
        state.exact_current = candidate
      } else {
        state.phase = BuildMembership
      }
    }
    Some(Binary(time_value)) => {
      let candidate = state.binary_current - state.step.to_double()
      let end = candidate + state.size.to_double()
      if candidate.is_nan() ||
        candidate.is_inf() ||
        end.is_nan() ||
        end.is_inf() ||
        end <= candidate {
        return Err(EventWindowArithmetic(state.record))
      }
      if candidate <= time_value && time_value < end {
        state.binary_current = candidate
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
  let (start, end) = match state.coordinate {
    Some(Exact(_)) => {
      if state.exact_current > 9223372036854775807L - state.size {
        return Err(EventWindowArithmetic(state.record))
      }
      guard event_window_exact_double(state.exact_current) is Some(start) &&
        event_window_exact_double(state.exact_current + state.size) is Some(end) else {
        return Err(EventWindowArithmetic(state.record))
      }
      (start, end)
    }
    Some(Binary(_)) => {
      let start = state.binary_current
      let end = start + state.size.to_double()
      if end.is_nan() || end.is_inf() || end <= start {
        return Err(EventWindowArithmetic(state.record))
      }
      (start, end)
    }
    None => return Err(InvalidEventWindowTime(state.record))
  }
  guard @value.checked_number_value(start, state.start_contract)
    is Some(start_value) &&
    @value.checked_number_value(end, state.end_contract) is Some(end_value) else {
    return Err(InvalidEventWindowKernel)
  }
  state.emission = state.fields.copy()
  state.emission.push((state.start_name, start_value))
  state.emission.push((state.end_name, end_value))
  state.phase = CommitMembership
  Ok(())
}

///|
fn event_window_commit_membership(
  state : EventWindowState,
) -> Result[Bool, EventWindowIssue] {
  guard state.output is Some(output) else {
    return Err(InvalidEventWindowKernel)
  }
  match @records.append_record(output, state.emission) {
    Err(issue) => Err(EventWindowOutput(issue))
    Ok(_) => {
      state.emission = []
      let last = match state.coordinate {
        Some(Exact(_)) => state.exact_current == state.exact_latest
        Some(Binary(_)) => state.binary_current == state.binary_latest
        None => true
      }
      if last {
        state.fields = []
        state.time = None
        state.coordinate = None
        state.record += 1
        state.phase = BeginRecord
      } else {
        match state.coordinate {
          Some(Exact(_)) => {
            if state.exact_current > 9223372036854775807L - state.step {
              return Err(EventWindowArithmetic(state.record))
            }
            state.exact_current += state.step
          }
          Some(Binary(_)) => {
            let next = state.binary_current + state.step.to_double()
            if next.is_nan() || next.is_inf() || next <= state.binary_current {
              return Err(EventWindowArithmetic(state.record))
            }
            state.binary_current = next
          }
          None => return Err(InvalidEventWindowTime(state.record))
        }
        state.phase = BuildMembership
      }
      Ok(last)
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
    if !@records.producer_read_available(state.input) {
      return @bounded.Failed(EventWindowInputUnavailable, progress, used)
    }
    match state.phase {
      BeginRecord =>
        if state.record < @storage.record_count(state.source) {
          used += 1
          match event_window_begin_record(state) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = Finish
        }
      ReadField => {
        let count = @storage.record_field_count(state.source, state.record).unwrap_or(
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
      CommitMembership => {
        used += 1
        match event_window_commit_membership(state) {
          Ok(_) => progress += 1
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      Finish => {
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
  @bounded.Continue(progress, used)
}

///|
fn cleanup_event_window_state(state : EventWindowState) -> Bool {
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.fields = []
  state.emission = []
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
pub fn start_event_window(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
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
  guard @records.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.EventValue(events) else {
    return Err(EventWindowInputUnavailable)
  }
  let records = @storage.record_count(source)
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
    input,
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
    time: None,
    coordinate: None,
    exact_current: 0L,
    exact_latest: 0L,
    binary_current: 0.0,
    binary_latest: 0.0,
  }
  let (session, token) = @bounded.start(
    control, state, event_window_step, cleanup_event_window_state, @records.discard_completed,
  )
  Ok({ session, token: Some(token), })
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
