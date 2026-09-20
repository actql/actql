///|
priv enum SessionPhase {
  LoadBegin
  LoadField
  LoadTerm
  LoadVerify
  SortBeginPass
  SortBeginRun
  SortChoose
  SortCompare
  SortWrite
  GroupBegin
  GroupCompareKey
  GroupBoundary
  IdentityBegin
  IdentityTerm
  IdentityCommit
  EmitBegin
  EmitFields
  EmitCommit
  Finish
}

///|
priv enum SessionIdentityScalarIssue {
  InvalidIdentityScalar
  IdentityScalarLimit
}

///|
priv enum SessionSource {
  Stored(@records.ProducerRead, @storage.Storage)
  Viewed(@lifecycle.ProducerView)
}

///|
priv struct SessionState {
  source : SessionSource
  mut output : @records.OutputBuilder?
  limits : @storage.Limits
  prepared : @lower.PreparedEvent
  records : Int
  keys : Int
  terms : Int
  gap : Int64
  scratch : Int
  start_name : @schema.FieldName
  end_name : @schema.FieldName
  id_name : @schema.FieldName
  start_contract : @contract.Contract
  end_contract : @contract.Contract
  id_contract : @contract.Contract
  mut phase : SessionPhase
  mut record : Int
  mut field : Int
  mut term : Int
  mut current : (@schema.FieldName, @value.CheckedValue)?
  mut cells : Array[@value.CheckedValue?]
  mut times : Array[Int64]
  mut source_order : Array[Int]
  mut target_order : Array[Int]
  mut width : Int
  mut run_start : Int
  mut middle : Int
  mut run_end : Int
  mut left : Int
  mut right : Int
  mut write : Int
  mut compare_left : Int
  mut compare_right : Int
  mut choose_left : Bool
  mut group_start : Int
  mut group_scan : Int
  mut previous_time : Int64
  mut session_start : Int64
  mut session_end : Int64
  mut session_id : String
  mut identity_first : Int
  mut identity_term : Int
  mut identity_bytes : Int
  mut identity_parts : Array[String]
  mut emit : Int
  mut emit_field : Int
  mut emit_fields : Array[(@schema.FieldName, @value.CheckedValue)]
}

///|
fn session_source_available(source : SessionSource) -> Bool {
  match source {
    Stored(input, _) => @records.producer_read_available(input)
    Viewed(view) => @lifecycle.producer_view_record_count(view) is Some(_)
  }
}

///|
fn session_source_field_count(source : SessionSource, record : Int) -> Int? {
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
fn session_source_field(
  source : SessionSource,
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
struct SessionExecution {
  session : @bounded.Session[SessionState, @records.Completed, SessionIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_bytes : Int
}

///|
pub enum SessionPoll {
  SessionContinue(progress~ : Int64, work~ : Int64)
  SessionComplete(@records.Completed, progress~ : Int64, work~ : Int64)
  SessionFailed(SessionIssue, progress~ : Int64, work~ : Int64)
  SessionStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum SessionIssue {
  InvalidSessionKernel
  InvalidSessionLimits
  SessionInputUnavailable
  InvalidSessionRecord(Int)
  InvalidSessionValue(Int, Int)
  SessionArithmetic(Int)
  SessionIdentityLimit
  SessionWorkspaceLimit
  SessionOutput(@records.Issue)
  SessionExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn session_checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn session_checked_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn session_scratch(records : Int, terms : Int) -> Int? {
  guard session_checked_multiply(records, terms) is Some(cells) &&
    session_checked_multiply(records, 3) is Some(indices) &&
    session_checked_add(cells, indices) is Some(fixed) &&
    session_checked_add(fixed, terms + 1) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn session_term_name(state : SessionState, term : Int) -> @schema.FieldName? {
  if term < state.keys {
    match @lower.event_session_keys(state.prepared) {
      Some(keys) => keys.get(term)
      None => None
    }
  } else if term == state.keys {
    @lower.event_session_time(state.prepared)
  } else if term == state.keys + 1 {
    @lower.event_session_identity(state.prepared)
  } else {
    None
  }
}

///|
fn session_cell(
  state : SessionState,
  record : Int,
  term : Int,
) -> @value.CheckedValue? {
  match state.cells.get(record * state.terms + term) {
    Some(value) => value
    None => None
  }
}

///|
fn session_compare_values(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
) -> Int? {
  match (left.value, right.value) {
    (@value.Null, @value.Null) => Some(0)
    (@value.Null, _) => Some(-1)
    (_, @value.Null) => Some(1)
    _ => event_compare_non_null(left, right)
  }
}

///|
fn session_compare_term(
  state : SessionState,
  left_record : Int,
  right_record : Int,
  term : Int,
) -> Int? {
  if term == state.keys {
    let left = state.times[left_record]
    let right = state.times[right_record]
    return Some(if left < right { -1 } else if left > right { 1 } else { 0 })
  }
  guard session_cell(state, left_record, term) is Some(left) &&
    session_cell(state, right_record, term) is Some(right) else {
    return None
  }
  session_compare_values(left, right)
}

///|
fn session_time(value : @value.CheckedValue, timestamp : Bool) -> Int64? {
  if timestamp {
    guard value.value is @value.Timestamp(text) else { return None }
    @value.timestamp_epoch_milliseconds(text)
  } else {
    guard value.value is @value.Number(number) else { return None }
    @scalar.read_safe_integer(number)
  }
}

///|
fn session_load_step(state : SessionState) -> Result[Unit, SessionIssue] {
  match state.phase {
    LoadBegin => {
      if state.record >= state.records {
        state.width = 1
        state.phase = SortBeginPass
        return Ok(())
      }
      guard session_source_field_count(state.source, state.record) is Some(_) else {
        return Err(InvalidSessionRecord(state.record))
      }
      state.field = 0
      state.current = None
      state.phase = LoadField
      Ok(())
    }
    LoadField => {
      let count = session_source_field_count(state.source, state.record).unwrap_or(
        -1,
      )
      if state.field >= count {
        state.term = 0
        state.phase = LoadVerify
        return Ok(())
      }
      guard session_source_field(state.source, state.record, state.field)
        is Some(value) else {
        return Err(InvalidSessionRecord(state.record))
      }
      state.current = Some(value)
      state.term = 0
      state.phase = LoadTerm
      Ok(())
    }
    LoadTerm => {
      guard state.current is Some((name, value)) &&
        session_term_name(state, state.term) is Some(expected) else {
        return Err(InvalidSessionRecord(state.record))
      }
      if @schema.reference_name(name) == @schema.reference_name(expected) {
        state.cells[state.record * state.terms + state.term] = Some(value)
      }
      state.term += 1
      if state.term >= state.terms {
        state.current = None
        state.field += 1
        state.phase = LoadField
      }
      Ok(())
    }
    LoadVerify => {
      guard session_cell(state, state.record, state.term) is Some(value) &&
        event_value_supported(value) else {
        return Err(InvalidSessionValue(state.record, state.term))
      }
      if state.term == state.keys {
        guard @lower.event_session_uses_timestamp(state.prepared)
          is Some(timestamp) &&
          session_time(value, timestamp) is Some(time) else {
          return Err(InvalidSessionValue(state.record, state.term))
        }
        state.times[state.record] = time
      }
      state.term += 1
      if state.term >= state.terms {
        state.record += 1
        state.phase = LoadBegin
      }
      Ok(())
    }
    _ => Err(InvalidSessionKernel)
  }
}

///|
fn session_sort_step(state : SessionState) -> Result[Unit, SessionIssue] {
  match state.phase {
    SortBeginPass => {
      if state.records < 2 || state.width >= state.records {
        state.group_start = 0
        state.phase = GroupBegin
      } else {
        state.run_start = 0
        state.phase = SortBeginRun
      }
      Ok(())
    }
    SortBeginRun => {
      if state.run_start >= state.records {
        let prior = state.source_order
        state.source_order = state.target_order
        state.target_order = prior
        state.width = if state.width > state.records / 2 {
          state.records
        } else {
          state.width * 2
        }
        state.phase = SortBeginPass
        return Ok(())
      }
      state.middle = state.run_start +
        Int::min(state.width, state.records - state.run_start)
      state.run_end = state.middle +
        Int::min(state.width, state.records - state.middle)
      state.left = state.run_start
      state.right = state.middle
      state.write = state.run_start
      state.phase = SortChoose
      Ok(())
    }
    SortChoose => {
      if state.write >= state.run_end {
        state.run_start = state.run_end
        state.phase = SortBeginRun
      } else if state.left >= state.middle {
        state.choose_left = false
        state.phase = SortWrite
      } else if state.right >= state.run_end {
        state.choose_left = true
        state.phase = SortWrite
      } else {
        state.compare_left = state.source_order[state.left]
        state.compare_right = state.source_order[state.right]
        state.term = 0
        state.phase = SortCompare
      }
      Ok(())
    }
    SortCompare => {
      guard session_compare_term(
          state,
          state.compare_left,
          state.compare_right,
          state.term,
        )
        is Some(comparison) else {
        return Err(InvalidSessionValue(state.compare_left, state.term))
      }
      state.term += 1
      if comparison != 0 {
        state.choose_left = comparison < 0
        state.phase = SortWrite
      } else if state.term >= state.terms {
        state.choose_left = true
        state.phase = SortWrite
      }
      Ok(())
    }
    SortWrite => {
      state.target_order[state.write] = if state.choose_left {
        let selected = state.source_order[state.left]
        state.left += 1
        selected
      } else {
        let selected = state.source_order[state.right]
        state.right += 1
        selected
      }
      state.write += 1
      state.phase = SortChoose
      Ok(())
    }
    _ => Err(InvalidSessionKernel)
  }
}

///|
fn session_scalar_identity(
  value : @value.CheckedValue,
  max_part_bytes : Int,
) -> Result[String, SessionIdentityScalarIssue] {
  if max_part_bytes < 0 {
    return Err(IdentityScalarLimit)
  }
  match value.value {
    @value.Null =>
      if max_part_bytes >= 2 {
        Ok("n:")
      } else {
        Err(IdentityScalarLimit)
      }
    @value.Reference(reference) => {
      if !@value.reference_available(reference) {
        return Err(InvalidIdentityScalar)
      }
      let text = @value.reference_identity_cid(reference)
      let length = text.length().to_string()
      let bytes = 3 + length.length() + @utf8.encode(text).length()
      if bytes <= max_part_bytes {
        Ok("r:" + length + ":" + text)
      } else {
        Err(IdentityScalarLimit)
      }
    }
    _ => {
      guard @value.canonical_scalar_text(value, max_part_bytes) is Some(text) else {
        return match value.value {
          @value.Boolean(_)
          | @value.Number(_)
          | @value.Text(_)
          | @value.Date(_)
          | @value.Timestamp(_)
          | @value.Decimal(_) => Err(IdentityScalarLimit)
          _ => Err(InvalidIdentityScalar)
        }
      }
      let length = text.length().to_string()
      let bytes = 3 + length.length() + @utf8.encode(text).length()
      if bytes <= max_part_bytes {
        Ok("v:" + length + ":" + text)
      } else {
        Err(IdentityScalarLimit)
      }
    }
  }
}

///|
fn session_identity_add_part(
  state : SessionState,
  part : String,
) -> Result[Unit, SessionIssue] {
  let addition = ":" + part
  let bytes = @utf8.encode(addition).length()
  guard session_checked_add(state.identity_bytes, bytes) is Some(total) &&
    total <= state.limits.max_value_bytes else {
    return Err(SessionIdentityLimit)
  }
  state.identity_parts.push(addition)
  state.identity_bytes = total
  Ok(())
}

///|
fn session_identity_step(state : SessionState) -> Result[Unit, SessionIssue] {
  match state.phase {
    IdentityBegin => {
      let prefix = "session:" + state.session_start.to_string()
      let bytes = @utf8.encode(prefix).length()
      if bytes > state.limits.max_value_bytes {
        return Err(SessionIdentityLimit)
      }
      state.identity_term = 0
      state.identity_bytes = bytes
      state.identity_parts = [prefix]
      state.phase = IdentityTerm
      Ok(())
    }
    IdentityTerm => {
      if state.identity_term > state.keys {
        state.phase = IdentityCommit
        return Ok(())
      }
      let cell = if state.identity_term < state.keys {
        session_cell(state, state.identity_first, state.identity_term)
      } else {
        session_cell(state, state.identity_first, state.keys + 1)
      }
      let remaining = state.limits.max_value_bytes - state.identity_bytes
      guard cell is Some(value) else {
        return Err(
          InvalidSessionValue(state.identity_first, state.identity_term),
        )
      }
      let part = match session_scalar_identity(value, remaining - 1) {
        Ok(part) => part
        Err(IdentityScalarLimit) => return Err(SessionIdentityLimit)
        Err(InvalidIdentityScalar) =>
          return Err(
            InvalidSessionValue(
              state.identity_first,
              if state.identity_term < state.keys {
                state.identity_term
              } else {
                state.keys + 1
              },
            ),
          )
      }
      match session_identity_add_part(state, part) {
        Ok(_) => ()
        Err(issue) => return Err(issue)
      }
      state.identity_term += 1
      Ok(())
    }
    IdentityCommit => {
      let identity = state.identity_parts.join("")
      if @utf8.encode(identity).length() != state.identity_bytes {
        return Err(SessionIdentityLimit)
      }
      state.session_id = identity
      state.identity_parts = []
      state.emit = state.group_start
      state.phase = EmitBegin
      Ok(())
    }
    _ => Err(InvalidSessionKernel)
  }
}

///|
fn session_finish_group(state : SessionState) -> Result[Unit, SessionIssue] {
  let first = state.source_order[state.group_start]
  let last = state.source_order[state.group_scan - 1]
  state.session_start = state.times[first]
  let last_time = state.times[last]
  if last_time > 9223372036854775807L - state.gap {
    return Err(SessionArithmetic(last))
  }
  state.session_end = last_time + state.gap
  state.identity_first = first
  state.phase = IdentityBegin
  Ok(())
}

///|
fn session_group_step(state : SessionState) -> Result[Unit, SessionIssue] {
  match state.phase {
    GroupBegin => {
      if state.group_start >= state.records {
        state.cells = []
        state.times = []
        state.source_order = []
        state.target_order = []
        state.phase = Finish
        return Ok(())
      }
      let first = state.source_order[state.group_start]
      state.previous_time = state.times[first]
      state.group_scan = state.group_start + 1
      state.term = 0
      if state.group_scan >= state.records {
        session_finish_group(state)
      } else if state.keys == 0 {
        state.phase = GroupBoundary
        Ok(())
      } else {
        state.phase = GroupCompareKey
        Ok(())
      }
    }
    GroupCompareKey => {
      let first = state.source_order[state.group_start]
      let candidate = state.source_order[state.group_scan]
      guard session_compare_term(state, first, candidate, state.term)
        is Some(comparison) else {
        return Err(InvalidSessionValue(candidate, state.term))
      }
      state.term += 1
      if comparison != 0 {
        session_finish_group(state)
      } else if state.term >= state.keys {
        state.phase = GroupBoundary
        Ok(())
      } else {
        Ok(())
      }
    }
    GroupBoundary => {
      let candidate = state.source_order[state.group_scan]
      let time = state.times[candidate]
      if state.previous_time > 9223372036854775807L - state.gap {
        return Err(SessionArithmetic(candidate))
      }
      if time < state.previous_time + state.gap {
        state.previous_time = time
        state.group_scan += 1
        if state.group_scan >= state.records {
          session_finish_group(state)
        } else if state.keys == 0 {
          Ok(())
        } else {
          state.term = 0
          state.phase = GroupCompareKey
          Ok(())
        }
      } else {
        session_finish_group(state)
      }
    }
    _ => Err(InvalidSessionKernel)
  }
}

///|
fn session_emit_step(state : SessionState) -> Result[Bool, SessionIssue] {
  match state.phase {
    EmitBegin => {
      if state.emit >= state.group_scan {
        state.group_start = state.group_scan
        state.phase = GroupBegin
        return Ok(false)
      }
      let record = state.source_order[state.emit]
      guard session_source_field_count(state.source, record) is Some(fields) &&
        session_checked_multiply(fields + 3, 2) is Some(temporary) else {
        return Err(InvalidSessionRecord(record))
      }
      let current = match state.output {
        Some(output) => @records.output_workspace_slots(output)
        None => return Err(InvalidSessionKernel)
      }
      if current > state.limits.max_workspace_slots ||
        state.scratch > state.limits.max_workspace_slots - current ||
        temporary > state.limits.max_workspace_slots - current - state.scratch {
        return Err(SessionWorkspaceLimit)
      }
      state.emit_field = 0
      state.emit_fields = []
      state.phase = EmitFields
      Ok(false)
    }
    EmitFields => {
      let record = state.source_order[state.emit]
      let count = session_source_field_count(state.source, record).unwrap_or(-1)
      if state.emit_field >= count {
        if state.session_start < -9007199254740991L ||
          state.session_start > 9007199254740991L ||
          state.session_end < -9007199254740991L ||
          state.session_end > 9007199254740991L {
          return Err(SessionArithmetic(record))
        }
        guard @value.checked_number_value(
            state.session_start.to_double(),
            state.start_contract,
          )
          is Some(start) &&
          @value.checked_number_value(
            state.session_end.to_double(),
            state.end_contract,
          )
          is Some(end) &&
          @value.checked_text_value(state.session_id, state.id_contract)
          is Some(identity) else {
          return Err(SessionArithmetic(record))
        }
        state.emit_fields.push((state.start_name, start))
        state.emit_fields.push((state.end_name, end))
        state.emit_fields.push((state.id_name, identity))
        state.phase = EmitCommit
        return Ok(false)
      }
      guard session_source_field(state.source, record, state.emit_field)
        is Some(field) else {
        return Err(InvalidSessionRecord(record))
      }
      state.emit_fields.push(field)
      state.emit_field += 1
      Ok(false)
    }
    EmitCommit => {
      guard state.output is Some(output) else {
        return Err(InvalidSessionKernel)
      }
      match @records.append_record(output, state.emit_fields) {
        Ok(_) => {
          state.emit_fields = []
          state.emit += 1
          state.phase = EmitBegin
          Ok(true)
        }
        Err(issue) => Err(SessionOutput(issue))
      }
    }
    _ => Err(InvalidSessionKernel)
  }
}

///|
fn session_step(
  state : SessionState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, SessionIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !session_source_available(state.source) {
      return @bounded.Failed(SessionInputUnavailable, progress, used)
    }
    used += 1
    let outcome = match state.phase {
      LoadBegin | LoadField | LoadTerm | LoadVerify => session_load_step(state)
      SortBeginPass | SortBeginRun | SortChoose | SortCompare | SortWrite =>
        session_sort_step(state)
      GroupBegin | GroupCompareKey | GroupBoundary => session_group_step(state)
      IdentityBegin | IdentityTerm | IdentityCommit =>
        session_identity_step(state)
      EmitBegin | EmitFields | EmitCommit =>
        match session_emit_step(state) {
          Ok(emitted) => {
            if emitted {
              progress += 1
            }
            Ok(())
          }
          Err(issue) => Err(issue)
        }
      Finish => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidSessionKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(SessionOutput(issue), progress, used)
        }
      }
    }
    if outcome is Err(issue) {
      return @bounded.Failed(issue, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_session_state(state : SessionState) -> Bool {
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.current = None
  state.cells = []
  state.times = []
  state.source_order = []
  state.target_order = []
  state.session_id = ""
  state.identity_parts = []
  state.emit_fields = []
  true
}

///|
fn session_output_contract(
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
fn start_session_with_source(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  event : @lower.PreparedEvent,
  keys : Array[@schema.FieldName],
  gap : Int64,
  source : SessionSource,
  records : Int,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[SessionExecution, SessionIssue] {
  let owner = @lower.sequence_owner(sequence)
  let terms = keys.length() + 2
  guard records <= limits.max_input_records &&
    records <= limits.max_records &&
    session_scratch(records, terms) is Some(scratch) &&
    scratch <= limits.max_workspace_slots else {
    return Err(SessionWorkspaceLimit)
  }
  let start_name = @schema.Unqualified("session_start_ms")
  let end_name = @schema.Unqualified("session_end_ms")
  let id_name = @schema.Unqualified("session_id")
  let output_carrier = @lower.event_output_carrier(event)
  guard session_output_contract(output_carrier, start_name)
    is Some(start_contract) &&
    session_output_contract(output_carrier, end_name) is Some(end_contract) &&
    session_output_contract(output_carrier, id_name) is Some(id_contract) else {
    return Err(InvalidSessionKernel)
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
    Err(issue) => return Err(SessionOutput(issue))
  }
  let state : SessionState = {
    source,
    output: Some(output),
    limits,
    prepared: event,
    records,
    keys: keys.length(),
    terms,
    gap,
    scratch,
    start_name,
    end_name,
    id_name,
    start_contract,
    end_contract,
    id_contract,
    phase: LoadBegin,
    record: 0,
    field: 0,
    term: 0,
    current: None,
    cells: Array::make(records * terms, None),
    times: Array::make(records, 0L),
    source_order: Array::makei(records, index => index),
    target_order: Array::make(records, 0),
    width: 1,
    run_start: 0,
    middle: 0,
    run_end: 0,
    left: 0,
    right: 0,
    write: 0,
    compare_left: 0,
    compare_right: 0,
    choose_left: false,
    group_start: 0,
    group_scan: 0,
    previous_time: 0L,
    session_start: 0L,
    session_end: 0L,
    session_id: "",
    identity_first: 0,
    identity_term: 0,
    identity_bytes: 0,
    identity_parts: [],
    emit: 0,
    emit_field: 0,
    emit_fields: [],
  }
  let (session, token) = @bounded.start(
    control, state, session_step, cleanup_session_state, @records.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_bytes: limits.max_value_bytes,
  })
}

///|
pub fn start_session(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[SessionExecution, SessionIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.EventStep(event)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "TEA.window.session_assign" &&
    @records.producer_read_matches_operation_input(input, owner, step, 0) &&
    @lower.event_session_keys(event) is Some(keys) &&
    @lower.event_session_gap(event) is Some(gap) &&
    gap > 0L else {
    return Err(InvalidSessionKernel)
  }
  guard @records.producer_read_storage(input) is Some(storage) &&
    @storage.carrier(storage) is @carrier.EventValue(_) else {
    return Err(SessionInputUnavailable)
  }
  start_session_with_source(
    control,
    sequence,
    step,
    event,
    keys,
    gap,
    Stored(input, storage),
    @storage.record_count(storage),
    limits,
    storage_bytes,
    available,
  )
}

///|
pub fn start_session_view(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[SessionExecution, SessionIssue] {
  let owner = @lower.sequence_owner(sequence)
  let reference = @lifecycle.producer_view_read_reference(input)
  guard @lower.sequence_step(sequence, step) is Some(@lower.EventStep(event)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "TEA.window.session_assign" &&
    @lifecycle.producer_view_kind(input) == @carrier.EventsKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      reference, owner, step, 0,
    ) &&
    @lifecycle.producer_view_record_count(input) is Some(records) &&
    @lower.event_session_keys(event) is Some(keys) &&
    @lower.event_session_gap(event) is Some(gap) &&
    gap > 0L else {
    return Err(InvalidSessionKernel)
  }
  start_session_with_source(
    control,
    sequence,
    step,
    event,
    keys,
    gap,
    Viewed(input),
    records,
    limits,
    storage_bytes,
    available,
  )
}

///|
pub fn session_max_noninterruptible_value_bytes(
  value : SessionExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_session(
  value : SessionExecution,
  quantum : Int,
) -> Result[SessionPoll, SessionIssue] {
  guard value.token is Some(token) else {
    return Err(SessionExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(SessionExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(SessionContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(SessionComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(SessionFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(SessionStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn session_cleanup_pending(value : SessionExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_session(value : SessionExecution) -> Result[Bool, SessionIssue] {
  @bounded.cleanup(value.session).map_err(issue => SessionExecutionIssue(issue))
}
