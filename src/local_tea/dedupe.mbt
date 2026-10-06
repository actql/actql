///|
priv enum DedupePhase {
  InitializeCells
  InitializeOrders
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
  GroupCompare
  GroupTieBegin
  GroupTieCompare
  GroupAdvance
  GroupFinish
  EmitBegin
  EmitFields
  EmitCommit
  EmitAppend
  Finish
}

///|
priv enum DedupeSource {
  Stored(@records.ProducerRead, @storage.Storage)
  Viewed(@lifecycle.ProducerView)
}

///|
priv struct DedupeState {
  source : DedupeSource
  mut output : @records.OutputBuilder?
  limits : @storage.Limits
  prepared : @lower.PreparedEvent
  records : Int
  cell_count : Int
  keys : Int
  terms : Int
  scratch : Int
  mut phase : DedupePhase
  mut record : Int
  mut field : Int
  mut term : Int
  mut current : (@schema.FieldName, @value.CheckedValue)?
  mut cells : Array[@value.CheckedValue?]
  mut source_order : Array[Int]
  mut target_order : Array[Int]
  initialized_cells : Ref[Int]
  initialized_orders : Ref[Int]
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
  mut survivors : Array[Int]
  mut emit : Int
  mut emit_field : Int
  mut emit_fields : Array[(@schema.FieldName, @value.CheckedValue)]
  mut append : @records.RecordAppend?
  mut control_work_remaining : Int
}

///|
fn dedupe_source_available(source : DedupeSource) -> Bool {
  match source {
    Stored(input, _) => @records.producer_read_available(input)
    Viewed(view) => @lifecycle.producer_view_record_count(view) is Some(_)
  }
}

///|
fn dedupe_source_record_count(source : DedupeSource) -> Int? {
  match source {
    Stored(_, storage) => Some(@storage.record_count(storage))
    Viewed(view) => @lifecycle.producer_view_record_count(view)
  }
}

///|
fn dedupe_source_field_count(source : DedupeSource, record : Int) -> Int? {
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
fn dedupe_source_field(
  source : DedupeSource,
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
struct DedupeExecution {
  state : DedupeState
  session : @bounded.Session[DedupeState, @records.Completed, DedupeIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
  initialized_cells : Ref[Int]
  initialized_orders : Ref[Int]
}

///|
pub enum DedupePoll {
  DedupeContinue(progress~ : Int64, work~ : Int64)
  DedupeComplete(@records.Completed, progress~ : Int64, work~ : Int64)
  DedupeFailed(DedupeIssue, progress~ : Int64, work~ : Int64)
  DedupeStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum DedupeIssue {
  InvalidDedupeKernel
  InvalidDedupeLimits
  DedupeInputLimit
  DedupeInputUnavailable
  InvalidDedupeRecord(Int)
  InvalidDedupeValue(Int, Int)
  DedupeTopTie(Int, Int)
  DedupeControlWorkLimit
  DedupeWorkspaceLimit
  DedupeOutput(@records.Issue)
  DedupeExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn dedupe_checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn dedupe_checked_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn dedupe_initialize_step(state : DedupeState) -> Unit {
  match state.phase {
    InitializeCells =>
      if state.cells.length() < state.cell_count {
        state.cells.push(None)
        state.initialized_cells.val += 1
      } else {
        state.phase = InitializeOrders
      }
    InitializeOrders =>
      if state.source_order.length() < state.records {
        state.source_order.push(state.source_order.length())
        state.target_order.push(0)
        state.initialized_orders.val += 1
      } else {
        state.phase = LoadBegin
      }
    _ => ()
  }
}

///|
fn dedupe_scratch(records : Int, terms : Int) -> Int? {
  guard dedupe_checked_multiply(records, terms) is Some(cells) &&
    dedupe_checked_multiply(records, 3) is Some(indices) &&
    dedupe_checked_add(cells, indices) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn event_compare_non_null(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
) -> Int? {
  match @value.compare_group_key_values(left, right) {
    Ok(order) => Some(order)
    Err(_) => None
  }
}

///|
fn event_value_supported(value : @value.CheckedValue) -> Bool {
  match value.value {
    @value.Null
    | @value.Number(_)
    | @value.Boolean(_)
    | @value.Text(_)
    | @value.Date(_)
    | @value.Timestamp(_)
    | @value.Decimal(_) => true
    @value.Reference(reference) => @value.reference_available(reference)
    @value.Array(_)
    | @value.Object(_)
    | @value.Vector(_)
    | @value.JsonData(_) => false
  }
}

///|
fn dedupe_term_name(state : DedupeState, term : Int) -> @schema.FieldName? {
  if term < state.keys {
    @lower.event_dedupe_key_at(state.prepared, term)
  } else {
    @lower.event_dedupe_order_at(state.prepared, term - state.keys).map(value => {
      value.0
    })
  }
}

///|
fn dedupe_cell(
  state : DedupeState,
  record : Int,
  term : Int,
) -> @value.CheckedValue? {
  match state.cells.get(record * state.terms + term) {
    Some(value) => value
    None => None
  }
}

///|
fn dedupe_compare_term(
  state : DedupeState,
  left_record : Int,
  right_record : Int,
  term : Int,
) -> Int? {
  guard dedupe_cell(state, left_record, term) is Some(left) &&
    dedupe_cell(state, right_record, term) is Some(right) else {
    return None
  }
  let (descending, nulls_first) = if term < state.keys {
    (false, true)
  } else {
    guard @lower.event_dedupe_order_at(state.prepared, term - state.keys)
      is Some((_, descending, nulls_first)) else {
      return None
    }
    (descending, nulls_first)
  }
  match (left.value, right.value) {
    (@value.Null, @value.Null) => Some(0)
    (@value.Null, _) => Some(if nulls_first { -1 } else { 1 })
    (_, @value.Null) => Some(if nulls_first { 1 } else { -1 })
    _ =>
      event_compare_non_null(left, right).map(order => {
        if descending {
          -order
        } else {
          order
        }
      })
  }
}

///|
fn dedupe_load_step(state : DedupeState) -> Result[Unit, DedupeIssue] {
  match state.phase {
    LoadBegin => {
      if state.record >= state.records {
        state.width = 1
        state.phase = SortBeginPass
        return Ok(())
      }
      guard dedupe_source_field_count(state.source, state.record) is Some(_) else {
        return Err(InvalidDedupeRecord(state.record))
      }
      state.field = 0
      state.current = None
      state.phase = LoadField
      Ok(())
    }
    LoadField => {
      let count = dedupe_source_field_count(state.source, state.record).unwrap_or(
        -1,
      )
      if state.field >= count {
        state.term = 0
        state.phase = LoadVerify
        return Ok(())
      }
      guard dedupe_source_field(state.source, state.record, state.field)
        is Some(value) else {
        return Err(InvalidDedupeRecord(state.record))
      }
      state.current = Some(value)
      state.term = 0
      state.phase = LoadTerm
      Ok(())
    }
    LoadTerm => {
      guard state.current is Some((name, value)) &&
        dedupe_term_name(state, state.term) is Some(expected) else {
        return Err(InvalidDedupeRecord(state.record))
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
      guard dedupe_cell(state, state.record, state.term) is Some(value) &&
        event_value_supported(value) else {
        return Err(InvalidDedupeValue(state.record, state.term))
      }
      state.term += 1
      if state.term >= state.terms {
        state.record += 1
        state.phase = LoadBegin
      }
      Ok(())
    }
    _ => Err(InvalidDedupeKernel)
  }
}

///|
fn dedupe_sort_step(state : DedupeState) -> Result[Unit, DedupeIssue] {
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
      guard dedupe_compare_term(
          state,
          state.compare_left,
          state.compare_right,
          state.term,
        )
        is Some(comparison) else {
        return Err(InvalidDedupeValue(state.compare_left, state.term))
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
    _ => Err(InvalidDedupeKernel)
  }
}

///|
fn dedupe_begin_group_compare(state : DedupeState) -> Unit {
  if state.keys == 0 {
    state.phase = GroupTieBegin
  } else {
    state.term = 0
    state.phase = GroupCompare
  }
}

///|
fn dedupe_group_step(state : DedupeState) -> Result[Unit, DedupeIssue] {
  match state.phase {
    GroupBegin => {
      if state.group_start >= state.records {
        state.cells = []
        state.source_order = []
        state.target_order = []
        state.emit = 0
        state.phase = EmitBegin
      } else {
        state.group_scan = state.group_start + 1
        if state.group_scan >= state.records {
          state.phase = GroupFinish
        } else {
          dedupe_begin_group_compare(state)
        }
      }
      Ok(())
    }
    GroupCompare => {
      let leader = state.source_order[state.group_start]
      let candidate = state.source_order[state.group_scan]
      guard dedupe_compare_term(state, leader, candidate, state.term)
        is Some(comparison) else {
        return Err(InvalidDedupeValue(candidate, state.term))
      }
      state.term += 1
      if comparison != 0 {
        state.phase = GroupFinish
      } else if state.term >= state.keys {
        state.phase = GroupTieBegin
      }
      Ok(())
    }
    GroupTieBegin => {
      if state.group_scan == state.group_start + 1 {
        state.term = state.keys
        state.phase = GroupTieCompare
      } else {
        state.phase = GroupAdvance
      }
      Ok(())
    }
    GroupTieCompare => {
      let leader = state.source_order[state.group_start]
      let candidate = state.source_order[state.group_scan]
      guard dedupe_compare_term(state, leader, candidate, state.term)
        is Some(comparison) else {
        return Err(InvalidDedupeValue(candidate, state.term))
      }
      state.term += 1
      if comparison != 0 {
        state.phase = GroupAdvance
      } else if state.term >= state.terms {
        return Err(DedupeTopTie(leader, candidate))
      }
      Ok(())
    }
    GroupAdvance => {
      state.group_scan += 1
      if state.group_scan >= state.records {
        state.phase = GroupFinish
      } else {
        dedupe_begin_group_compare(state)
      }
      Ok(())
    }
    GroupFinish => {
      state.survivors.push(state.source_order[state.group_start])
      state.group_start = state.group_scan
      state.phase = GroupBegin
      Ok(())
    }
    _ => Err(InvalidDedupeKernel)
  }
}

///|
fn dedupe_emit_step(state : DedupeState) -> Result[Bool, DedupeIssue] {
  match state.phase {
    EmitBegin => {
      if state.emit >= state.survivors.length() {
        state.survivors = []
        state.phase = Finish
        return Ok(false)
      }
      let record = state.survivors[state.emit]
      guard dedupe_source_field_count(state.source, record) is Some(fields) &&
        dedupe_checked_add(state.scratch, fields) is Some(field_slots) &&
        dedupe_checked_add(field_slots, 1) is Some(owned) &&
        event_emission_workspace(fields, 1, state.limits.max_value_depth, owned)
        is Some(temporary) else {
        return Err(InvalidDedupeRecord(record))
      }
      let current = match state.output {
        Some(output) => @records.output_workspace_slots(output)
        None => return Err(InvalidDedupeKernel)
      }
      if current > state.limits.max_workspace_slots ||
        temporary > state.limits.max_workspace_slots - current {
        return Err(DedupeWorkspaceLimit)
      }
      state.emit_field = 0
      state.emit_fields = []
      state.phase = EmitFields
      Ok(false)
    }
    EmitFields => {
      let record = state.survivors[state.emit]
      let count = dedupe_source_field_count(state.source, record).unwrap_or(-1)
      if state.emit_field >= count {
        state.phase = EmitCommit
        return Ok(false)
      }
      guard dedupe_source_field(state.source, record, state.emit_field)
        is Some(field) else {
        return Err(InvalidDedupeRecord(record))
      }
      state.emit_fields.push(field)
      state.emit_field += 1
      Ok(false)
    }
    EmitCommit => {
      guard state.output is Some(output) else {
        return Err(InvalidDedupeKernel)
      }
      match
        @records.start_record_append(
          output,
          state.emit_fields,
          external_workspace_slots=state.scratch +
            state.emit_fields.length() +
            1,
        ) {
        Ok(append) => {
          state.append = Some(append)
          state.phase = EmitAppend
          Ok(false)
        }
        Err(issue) => Err(DedupeOutput(issue))
      }
    }
    EmitAppend => {
      guard state.append is Some(append) else {
        return Err(InvalidDedupeKernel)
      }
      match @records.advance_record_append(append) {
        Ok(false) => Ok(false)
        Ok(true) => {
          state.append = None
          state.emit_fields = []
          state.emit += 1
          state.phase = EmitBegin
          Ok(true)
        }
        Err(issue) => Err(DedupeOutput(issue))
      }
    }
    _ => Err(InvalidDedupeKernel)
  }
}

///|
fn dedupe_step(
  state : DedupeState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@records.Completed, DedupeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !dedupe_source_available(state.source) {
      return @bounded.Failed(DedupeInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(DedupeControlWorkLimit, progress, used)
    }
    match state.phase {
      InitializeCells | InitializeOrders => {
        used += 1
        dedupe_initialize_step(state)
      }
      LoadBegin | LoadField | LoadTerm | LoadVerify => {
        used += 1
        match dedupe_load_step(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      SortBeginPass | SortBeginRun | SortChoose | SortCompare | SortWrite => {
        used += 1
        match dedupe_sort_step(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      GroupBegin
      | GroupCompare
      | GroupTieBegin
      | GroupTieCompare
      | GroupAdvance
      | GroupFinish => {
        used += 1
        match dedupe_group_step(state) {
          Ok(_) => ()
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      EmitBegin | EmitFields | EmitCommit | EmitAppend => {
        used += 1
        match dedupe_emit_step(state) {
          Ok(emitted) => if emitted { progress += 1 }
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidDedupeKernel, progress, used)
        }
        state.output = None
        return match @records.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(DedupeOutput(issue), progress, used)
        }
      }
    }
  }
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_dedupe_state(state : DedupeState) -> Bool {
  if state.append is Some(append) {
    @records.cleanup_record_append(append) |> ignore
    state.append = None
  }
  if state.output is Some(output) {
    @records.cancel_output(output) |> ignore
    state.output = None
  }
  state.current = None
  state.cells = []
  state.source_order = []
  state.target_order = []
  state.survivors = []
  state.emit_fields = []
  true
}

///|
fn start_dedupe_source(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  source : DedupeSource,
  event : @lower.PreparedEvent,
  keys : Int,
  order : Int,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit : Int,
) -> Result[DedupeExecution, DedupeIssue] {
  if control_work_limit < 0 {
    return Err(InvalidDedupeLimits)
  }
  if control_work_limit == 0 {
    return Err(DedupeControlWorkLimit)
  }
  let owner = @lower.sequence_owner(sequence)
  if limits.max_value_nodes < 1 ||
    limits.max_workspace_slots < 0 ||
    limits.max_input_records < 0 {
    return Err(InvalidDedupeLimits)
  }
  guard dedupe_source_record_count(source) is Some(records) else {
    return Err(DedupeInputUnavailable)
  }
  if records > limits.max_input_records {
    return Err(DedupeInputLimit)
  }
  guard dedupe_checked_add(keys, order) is Some(terms) &&
    terms > 0 &&
    dedupe_checked_multiply(records, terms) is Some(cell_count) &&
    dedupe_scratch(records, terms) is Some(scratch_slots) else {
    return Err(DedupeWorkspaceLimit)
  }
  if scratch_slots > limits.max_workspace_slots {
    return Err(DedupeWorkspaceLimit)
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
    Err(issue) => return Err(DedupeOutput(issue))
  }
  let initialized_cells = Ref(0)
  let initialized_orders = Ref(0)
  let state : DedupeState = {
    source,
    output: Some(output),
    limits,
    prepared: event,
    records,
    cell_count,
    keys,
    terms,
    scratch: scratch_slots,
    phase: InitializeCells,
    record: 0,
    field: 0,
    term: 0,
    current: None,
    cells: [],
    source_order: [],
    target_order: [],
    initialized_cells,
    initialized_orders,
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
    survivors: [],
    emit: 0,
    emit_field: 0,
    emit_fields: [],
    append: None,
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control, state, dedupe_step, cleanup_dedupe_state, @records.discard_completed,
  )
  Ok({
    state,
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: 1,
    max_noninterruptible_value_bytes: limits.max_value_bytes,
    initialized_cells,
    initialized_orders,
  })
}

///|
pub fn start_dedupe(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @records.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[DedupeExecution, DedupeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.EventStep(event)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "TEA.dedupe" &&
    @records.producer_read_matches_operation_input(input, owner, step, 0) &&
    @lower.event_dedupe_key_count(event) is Some(keys) &&
    @lower.event_dedupe_order_count(event) is Some(order) &&
    order > 0 else {
    return Err(InvalidDedupeKernel)
  }
  guard @records.producer_read_storage(input) is Some(storage) &&
    @storage.carrier(storage) is @carrier.EventValue(_) else {
    return Err(DedupeInputUnavailable)
  }
  start_dedupe_source(
    control,
    sequence,
    step,
    Stored(input, storage),
    event,
    keys,
    order,
    limits,
    storage_bytes,
    available,
    control_work_limit.unwrap_or(limits.max_work),
  )
}

///|
pub fn start_dedupe_view(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[DedupeExecution, DedupeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.EventStep(event)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "TEA.dedupe" &&
    @lower.node_input_target(node, 0) is Some(target) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
    is Some(@carrier.EventValue(_)) &&
    @lifecycle.producer_view_kind(input) == @carrier.EventsKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lower.event_dedupe_key_count(event) is Some(keys) &&
    @lower.event_dedupe_order_count(event) is Some(order) &&
    order > 0 else {
    return Err(InvalidDedupeKernel)
  }
  start_dedupe_source(
    control,
    sequence,
    step,
    Viewed(input),
    event,
    keys,
    order,
    limits,
    storage_bytes,
    available,
    control_work_limit.unwrap_or(limits.max_work),
  )
}

///|
/// Diagnostic progress for the bounded scratch initialization. It reports
/// the cells and paired index entries built so far, not output progress.
pub fn dedupe_initialization_progress(value : DedupeExecution) -> (Int, Int) {
  (value.initialized_cells.val, value.initialized_orders.val)
}

///|
pub fn dedupe_max_noninterruptible_value_nodes(value : DedupeExecution) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn dedupe_max_noninterruptible_value_bytes(value : DedupeExecution) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_dedupe(
  value : DedupeExecution,
  quantum : Int,
) -> Result[DedupePoll, DedupeIssue] {
  guard value.token is Some(token) else {
    return Err(DedupeExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(DedupeExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(DedupeContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(DedupeComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(DedupeFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(DedupeStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn dedupe_stopped(value : DedupeExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn dedupe_cleanup_pending(value : DedupeExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_dedupe(value : DedupeExecution) -> Result[Bool, DedupeIssue] {
  @bounded.cleanup(value.session).map_err(issue => DedupeExecutionIssue(issue))
}
