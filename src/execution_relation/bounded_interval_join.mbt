///|
priv enum BoundedIntervalPhase {
  ReadLeftClocks
  ReadRightClocks
  BeginPair
  CompareKey
  EvaluatePair
  EmitRemainder
  BuildOutputRow
  CheckOutputRow
  CommitOutputRow
  FinishOutput
  Terminal
}

///|
priv enum IntervalEmitContinuation {
  NextPair
  NextLeft
}

///|
priv struct BoundedIntervalState {
  left : ProducerRead
  right : ProducerRead
  keys : Array[(Int, Int)]
  left_operand : (Int, Int?)
  right_operand : (Int, Int)
  columns : Array[(Bool, Int)]
  output_schema : @schema.Schema
  kind : @join.Kind
  overlap : Bool
  timestamp : Bool
  search_ceiling : Int64
  output_ceiling : Int
  control : ControlBudget
  workspace : RowWorkspace
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut left_starts : Array[Int64]
  mut left_ends : Array[Int64]
  mut right_starts : Array[Int64]
  mut right_ends : Array[Int64]
  mut phase : BoundedIntervalPhase
  mut left_row : Int
  mut right_row : Int
  mut key_index : Int
  mut matched : Bool
  mut visited : Int64
  mut emitted : Int
  mut emit_right : Int?
  mut emit_continuation : IntervalEmitContinuation
  mut column : Int
  mut output_row : Array[Value]
  mut checked_row : Array[@admitted.Value]
  mut output_recheck : @admitted.RecheckCursor?
  mut output_charge : BoundedOutputRowCharge?
}

///|
pub(all) enum BoundedIntervalJoinIssue {
  InvalidExecution
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedIntervalJoinExecution {
  session : @bounded.Session[
    BoundedIntervalState,
    CompletedOutput,
    BoundedIntervalJoinIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  state : BoundedIntervalState
}

///|
pub enum BoundedIntervalJoinPoll {
  BoundedIntervalJoinContinue(progress~ : Int64, work~ : Int64)
  BoundedIntervalJoinComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedIntervalJoinFailed(
    BoundedIntervalJoinIssue,
    progress~ : Int64,
    work~ : Int64
  )
  BoundedIntervalJoinStopped(
    @bounded.StopReason,
    progress~ : Int64,
    work~ : Int64
  )
}

///|
fn bounded_interval_failure(
  issue : BoundedIntervalJoinIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedIntervalJoinIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_interval_state(state : BoundedIntervalState) -> Bool {
  if state.output_recheck is Some(cursor) {
    @admitted.cancel_recheck_runtime_value(cursor)
    state.output_recheck = None
  }
  if state.output_charge is Some(cursor) {
    cleanup_bounded_output_row_charge(cursor)
    state.output_charge = None
  }
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.left_starts = []
  state.left_ends = []
  state.right_starts = []
  state.right_ends = []
  state.output_row = []
  state.checked_row = []
  state.workspace.live = 0
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn bounded_interval_inputs_available(state : BoundedIntervalState) -> Bool {
  producer_read_available(state.left) && producer_read_available(state.right)
}

///|
fn bounded_interval_schedule_output(
  state : BoundedIntervalState,
  right : Int?,
  continuation : IntervalEmitContinuation,
) -> Bool {
  if state.emitted >= state.output_ceiling {
    return false
  }
  state.emit_right = right
  state.emit_continuation = continuation
  state.column = 0
  state.output_row = []
  state.checked_row = []
  state.phase = BuildOutputRow
  true
}

///|
fn bounded_interval_step(
  state : BoundedIntervalState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedIntervalJoinIssue] {
  let mut used = 0
  let mut progress = 0
  let left_count = producer_read_row_count(state.left)
  let right_count = producer_read_row_count(state.right)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !bounded_interval_inputs_available(state) {
      return bounded_interval_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ReadLeftClocks => {
        if state.left_row == left_count {
          state.left_row = 0
          state.phase = ReadRightClocks
          continue
        }
        guard producer_read_cell(
            state.left,
            state.left_row,
            state.left_operand.0,
          )
          is Some(raw_start) else {
          return bounded_interval_failure(InvalidExecution, progress, used)
        }
        let start = match
          interval_clock(raw_start, state.timestamp, state.control) {
          Ok(value) => value
          Err(issue) =>
            return bounded_interval_failure(Rows(issue), progress, used + 1)
        }
        let end = match state.left_operand.1 {
          None => start
          Some(column) => {
            guard producer_read_cell(state.left, state.left_row, column)
              is Some(raw_end) else {
              return bounded_interval_failure(InvalidExecution, progress, used)
            }
            match interval_clock(raw_end, state.timestamp, state.control) {
              Ok(value) if start < value => value
              Ok(_) =>
                return bounded_interval_failure(
                  Rows(InvalidRows),
                  progress,
                  used + 1,
                )
              Err(issue) =>
                return bounded_interval_failure(Rows(issue), progress, used + 1)
            }
          }
        }
        state.left_starts.push(start)
        state.left_ends.push(end)
        state.left_row += 1
        used += 1
        progress += 1
      }
      ReadRightClocks => {
        if state.right_row == right_count {
          state.right_row = 0
          state.phase = BeginPair
          continue
        }
        guard producer_read_cell(
            state.right,
            state.right_row,
            state.right_operand.0,
          )
          is Some(raw_start) &&
          producer_read_cell(
            state.right,
            state.right_row,
            state.right_operand.1,
          )
          is Some(raw_end) else {
          return bounded_interval_failure(InvalidExecution, progress, used)
        }
        let start = match
          interval_clock(raw_start, state.timestamp, state.control) {
          Ok(value) => value
          Err(issue) =>
            return bounded_interval_failure(Rows(issue), progress, used + 1)
        }
        let end = match
          interval_clock(raw_end, state.timestamp, state.control) {
          Ok(value) if start < value => value
          Ok(_) =>
            return bounded_interval_failure(
              Rows(InvalidRows),
              progress,
              used + 1,
            )
          Err(issue) =>
            return bounded_interval_failure(Rows(issue), progress, used + 1)
        }
        state.right_starts.push(start)
        state.right_ends.push(end)
        state.right_row += 1
        used += 1
        progress += 1
      }
      BeginPair => {
        if state.left_row == left_count {
          state.phase = FinishOutput
          continue
        }
        if state.right_row == right_count {
          state.phase = EmitRemainder
          continue
        }
        if state.visited >= state.search_ceiling {
          return bounded_interval_failure(Rows(RowLimit), progress, used)
        }
        if !spend_control(state.control, 1) {
          return bounded_interval_failure(Rows(RowLimit), progress, used + 1)
        }
        state.phase = CompareKey
        used += 1
      }
      CompareKey => {
        if state.key_index == state.keys.length() {
          state.phase = EvaluatePair
          continue
        }
        let pair = state.keys[state.key_index]
        guard producer_read_cell(state.left, state.left_row, pair.0)
          is Some(left_value) &&
          producer_read_cell(state.right, state.right_row, pair.1)
          is Some(right_value) else {
          return bounded_interval_failure(InvalidExecution, progress, used)
        }
        if left_value is Null || right_value is Null {
          state.visited += 1L
          state.key_index = 0
          state.right_row += 1
          state.phase = BeginPair
          progress += 1
        } else {
          match compare_complete_value(left_value, right_value, state.control) {
            Ok(0) => state.key_index += 1
            Ok(_) => {
              state.visited += 1L
              state.key_index = 0
              state.right_row += 1
              state.phase = BeginPair
              progress += 1
            }
            Err(issue) =>
              return bounded_interval_failure(
                Rows(ordering_row_issue(issue)),
                progress,
                used + 1,
              )
          }
        }
        used += 1
      }
      EvaluatePair => {
        state.visited += 1L
        let temporal_match = if state.overlap {
          state.left_starts[state.left_row] < state.right_ends[state.right_row] &&
          state.right_starts[state.right_row] < state.left_ends[state.left_row]
        } else {
          state.right_starts[state.right_row] <=
          state.left_starts[state.left_row] &&
          state.left_starts[state.left_row] < state.right_ends[state.right_row]
        }
        if temporal_match {
          state.matched = true
        }
        if temporal_match &&
          (state.kind == @join.Inner || state.kind == @join.Left) {
          if !bounded_interval_schedule_output(
              state,
              Some(state.right_row),
              NextPair,
            ) {
            return bounded_interval_failure(Rows(RowLimit), progress, used)
          }
        } else {
          state.right_row += 1
          state.key_index = 0
          state.phase = BeginPair
        }
        used += 1
        progress += 1
      }
      EmitRemainder => {
        let emit = (state.kind == @join.Left && !state.matched) ||
          (state.kind == @join.Semi && state.matched) ||
          (state.kind == @join.Anti && !state.matched)
        if emit {
          if !bounded_interval_schedule_output(state, None, NextLeft) {
            return bounded_interval_failure(Rows(RowLimit), progress, used)
          }
        } else {
          state.left_row += 1
          state.right_row = 0
          state.key_index = 0
          state.matched = false
          state.phase = BeginPair
        }
        used += 1
        progress += 1
      }
      BuildOutputRow => {
        if state.column == state.columns.length() {
          state.column = 0
          state.phase = CheckOutputRow
          continue
        }
        let source = state.columns[state.column]
        let value = if source.0 {
          producer_read_cell(state.left, state.left_row, source.1)
        } else {
          match state.emit_right {
            Some(row) => producer_read_cell(state.right, row, source.1)
            None => Some(Null)
          }
        }
        guard value is Some(value) && reserve_slots(state.workspace, 1) else {
          return bounded_interval_failure(Rows(RowLimit), progress, used)
        }
        state.output_row.push(value)
        state.column += 1
        used += 1
      }
      CheckOutputRow => {
        if state.output_recheck is Some(cursor) {
          match @admitted.advance_recheck_runtime_value(cursor) {
            RecheckContinue => ()
            RecheckFailed =>
              return bounded_interval_failure(
                InvalidExecution,
                progress,
                used + 1,
              )
            RecheckComplete(checked, _, _) => {
              state.output_recheck = None
              state.checked_row.push(checked.value)
              state.column += 1
            }
          }
          used += 1
          continue
        }
        if state.column == state.columns.length() {
          state.phase = CommitOutputRow
          continue
        }
        guard @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return bounded_interval_failure(InvalidExecution, progress, used)
        }
        if !reserve_slots(state.workspace, 1) {
          return bounded_interval_failure(Rows(RowLimit), progress, used)
        }
        let cell = state.output_row[state.column]
        if bounded_small_output_value(cell) {
          guard checked_ordered_output_value(
              cell,
              field.contract,
              state.admitted_limits,
            )
            is Some(checked) else {
            return bounded_interval_failure(InvalidExecution, progress, used)
          }
          state.checked_row.push(checked.value)
          state.column += 1
        } else {
          guard start_ordered_output_value_recheck(
              cell,
              field.contract,
              state.admitted_limits,
            )
            is Some(cursor) else {
            return bounded_interval_failure(InvalidExecution, progress, used)
          }
          state.output_recheck = Some(cursor)
        }
        used += 1
      }
      CommitOutputRow => {
        guard state.output is Some(output) else {
          return bounded_interval_failure(InvalidExecution, progress, used)
        }
        if state.output_charge is None {
          match
            start_bounded_output_row_charge(
              output,
              state.checked_row,
              state.workspace,
            ) {
            Err(OutputCapture(issue)) =>
              return bounded_interval_failure(
                Capture(issue),
                progress,
                used + 1,
              )
            Err(OutputWorkspace) =>
              return bounded_interval_failure(
                Rows(RowLimit),
                progress,
                used + 1,
              )
            Ok(cursor) => state.output_charge = Some(cursor)
          }
          used += 1
          continue
        }
        match advance_bounded_output_row_charge(state.output_charge.unwrap()) {
          Err(OutputCapture(issue)) =>
            return bounded_interval_failure(Capture(issue), progress, used + 1)
          Err(OutputWorkspace) =>
            return bounded_interval_failure(Rows(RowLimit), progress, used + 1)
          Ok(false) => {
            used += 1
            continue
          }
          Ok(true) => state.output_charge = None
        }
        release_slots(
          state.workspace,
          state.output_row.length() + state.checked_row.length(),
        )
        state.output_row = []
        state.checked_row = []
        state.emitted += 1
        match state.emit_continuation {
          NextPair => {
            state.right_row += 1
            state.key_index = 0
            state.phase = BeginPair
          }
          NextLeft => {
            state.left_row += 1
            state.right_row = 0
            state.key_index = 0
            state.matched = false
            state.phase = BeginPair
          }
        }
        used += 1
        progress += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_interval_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_interval_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) =>
            bounded_interval_failure(Completion(issue), progress, used)
        }
      }
      Terminal =>
        return bounded_interval_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_interval_join(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  left : ProducerRead,
  right : ProducerRead,
  max_rows : Int,
  values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedIntervalJoinExecution, BoundedIntervalJoinIssue] {
  if max_rows < 0 ||
    max_work < 0 ||
    max_frames < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 {
    return Err(InvalidExecution)
  }
  let sequence = generated.sequence
  let owner = @lower.sequence_owner(sequence)
  guard generated_sequence_step_count(generated) == 1 &&
    generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_at(generated, 0)
    is Some(@lower.IntervalJoinStep(kernel)) &&
    producer_read_matches_operation_input(left, owner, step, 0) &&
    producer_read_matches_operation_input(right, owner, step, 1) &&
    producer_read_has_cell_access(left) &&
    producer_read_has_cell_access(right) &&
    producer_read_row_count(left) <= max_rows &&
    producer_read_row_count(right) <= max_rows &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  let search_ceiling = match
    generated_interval_search_ceiling(generated, step) {
    Some(value) if value >= 0L => value
    _ => return Err(InvalidExecution)
  }
  let left_count = producer_read_row_count(left)
  let right_count = producer_read_row_count(right)
  if right_count != 0 &&
    left_count.to_int64() > search_ceiling / right_count.to_int64() {
    return Err(Rows(RowLimit))
  }
  let key_count = @lower.interval_join_key_count(kernel)
  let column_count = @lower.interval_join_field_count(kernel)
  let mut available_entries = max_entries
  if key_count < 0 || column_count < 0 || left_count > available_entries / 2 {
    return Err(Rows(RowLimit))
  }
  available_entries -= left_count * 2
  if right_count > available_entries / 2 {
    return Err(Rows(RowLimit))
  }
  available_entries -= right_count * 2
  if key_count > available_entries / 2 {
    return Err(Rows(RowLimit))
  }
  available_entries -= key_count * 2
  if column_count > available_entries / 2 {
    return Err(Rows(RowLimit))
  }
  let mut output_ceiling = max_rows
  if @lower.interval_join_output_limit(kernel) is Some(value) &&
    value < output_ceiling.to_int64() {
    if value < 0L {
      return Err(InvalidExecution)
    }
    output_ceiling = value.to_int()
  }
  if generated_join_output_ceiling(generated, step) is Some(value) &&
    value < output_ceiling.to_int64() {
    if value < 0L {
      return Err(InvalidExecution)
    }
    output_ceiling = value.to_int()
  }
  let control : ControlBudget = { remaining: max_work, max_frames, }
  let workspace = row_workspace(max_entries)
  let resolve = fn(input : ProducerRead, field : @schema.FieldName) -> Int? {
    let schema = producer_read_schema(input)
    let name = @schema.reference_name(field)
    for index in 0..<@schema.field_count(schema) {
      if !spend_control(control, 1) || !spend_control_text(control, name) {
        return None
      }
      guard @schema.field_at(schema, index) is Some(candidate) else {
        return None
      }
      if @schema.reference_name(candidate.name) == name {
        return Some(index)
      }
    }
    None
  }
  let keys : Array[(Int, Int)] = []
  for index in 0..<key_count {
    guard @lower.interval_join_key_at(kernel, index) is Some(pair) &&
      resolve(left, pair.0) is Some(left_column) &&
      resolve(right, pair.1) is Some(right_column) else {
      return Err(InvalidExecution)
    }
    keys.push((left_column, right_column))
  }
  let resolve_operand = fn(
    input : ProducerRead,
    operand : @join.TemporalOperand,
  ) -> (Int, Int?)? {
    match operand {
      @join.Point(time) => resolve(input, time).map(column => (column, None))
      @join.Interval(start, end) => {
        guard resolve(input, start) is Some(start_column) &&
          resolve(input, end) is Some(end_column) else {
          return None
        }
        Some((start_column, Some(end_column)))
      }
    }
  }
  guard resolve_operand(left, @lower.interval_join_operand(kernel, true))
    is Some(left_operand) &&
    resolve_operand(right, @lower.interval_join_operand(kernel, false))
    is Some((right_start, Some(right_end))) else {
    return Err(InvalidExecution)
  }
  let columns : Array[(Bool, Int)] = []
  for index in 0..<column_count {
    guard @lower.interval_join_field_at(kernel, index) is Some(field) else {
      return Err(InvalidExecution)
    }
    let (on_left, source) = match field.input {
      @schema.Qualified(side, name) =>
        (side == @schema.Left, @schema.Unqualified(name))
      _ => return Err(InvalidExecution)
    }
    guard resolve(if on_left { left } else { right }, source) is Some(column) else {
      return Err(InvalidExecution)
    }
    columns.push((on_left, column))
  }
  if left_count > max_entries / 2 ||
    right_count > max_entries / 2 ||
    keys.length() > max_entries / 2 ||
    columns.length() > max_entries / 2 {
    return Err(Rows(RowLimit))
  }
  let left_slots = left_count * 2
  let right_slots = right_count * 2
  let key_slots = keys.length() * 2
  let column_slots = columns.length() * 2
  if key_slots > max_entries - column_slots {
    return Err(Rows(RowLimit))
  }
  let metadata = key_slots + column_slots
  if !reserve_slots(workspace, metadata) ||
    !reserve_slots(workspace, left_slots) ||
    !reserve_slots(workspace, right_slots) {
    return Err(Rows(RowLimit))
  }
  let output = match
    prepare_admitted_output(owner, @pipeline.Step(step), output_ceiling, values) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    prepare_trusted_output_port(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[left, right],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedIntervalState = {
    left,
    right,
    keys,
    left_operand,
    right_operand: (right_start, right_end),
    columns,
    output_schema,
    kind: @lower.interval_join_kind(kernel),
    overlap: @lower.interval_join_mode(kernel) == @join.Overlap,
    timestamp: @lower.interval_join_uses_timestamps(kernel),
    search_ceiling,
    output_ceiling,
    control,
    workspace,
    admitted_limits: {
      max_nodes: values.max_nodes,
      max_depth: values.max_depth,
      max_text_bytes: values.max_text_bytes,
    },
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    left_starts: [],
    left_ends: [],
    right_starts: [],
    right_ends: [],
    phase: ReadLeftClocks,
    left_row: 0,
    right_row: 0,
    key_index: 0,
    matched: false,
    visited: 0L,
    emitted: 0,
    emit_right: None,
    emit_continuation: NextPair,
    column: 0,
    output_row: [],
    checked_row: [],
    output_recheck: None,
    output_charge: None,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_interval_step,
    cleanup_bounded_interval_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, state, })
}

///|
pub fn advance_bounded_interval_join(
  value : BoundedIntervalJoinExecution,
  quantum : Int,
) -> Result[BoundedIntervalJoinPoll, BoundedIntervalJoinIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedIntervalJoinContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedIntervalJoinComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedIntervalJoinFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedIntervalJoinStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_interval_join(
  value : BoundedIntervalJoinExecution,
) -> Result[Bool, BoundedIntervalJoinIssue] {
  let changed = match @bounded.cleanup(value.session) {
    Ok(changed) => changed
    Err(issue) => return Err(Execution(issue))
  }
  if !@bounded.cleanup_pending(value.session) &&
    (value.state.workspace.live != 0 ||
    value.state.output_recheck is Some(_) ||
    value.state.output_charge is Some(_)) {
    return Err(InvalidExecution)
  }
  Ok(changed)
}

///|
pub fn bounded_interval_join_cleanup_pending(
  value : BoundedIntervalJoinExecution,
) -> Bool {
  @bounded.cleanup_pending(value.session)
}
