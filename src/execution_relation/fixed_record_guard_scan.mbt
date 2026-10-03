///|
priv enum RecordGuardSource {
  Supplied(SuppliedRelationRead)
  Completed(CompletedOutput)
}

///|
priv enum RecordGuardPhase {
  BeginRow
  BeginColumn
  Emit(IdentityWireCursor)
  EndRow
  Done
}

///|
priv struct RecordGuardState {
  source : RecordGuardSource
  scope : FixedInputGuardPhase
  rows : Int
  columns : Int
  ceiling : Int
  initial : FixedInputGuardMeasureLimits
  budget : FixedInputGuardBudget
  workspace : RowWorkspace
  writer_nodes : Int
  writer_depth : Int
  mut row : Int
  mut column : Int
  mut writer : @encode.Writer?
  mut phase : RecordGuardPhase
}

///|
/// One common bounded session; no acquisition or publication authority.
struct FixedRecordGuardScan {
  session : @bounded.Session[
    RecordGuardState,
    FixedInputGuardMeasureLimits,
    FixedInputGuardIssue,
  ]
  mut token : @bounded.Token
}

///|
fn record_guard_available(source : RecordGuardSource) -> Bool {
  match source {
    Supplied(read) => supplied_relation_read_available(read)
    Completed(output) => completed_output_available(output)
  }
}

///|
fn record_guard_name(source : RecordGuardSource, column : Int) -> String {
  match source {
    Supplied(read) =>
      @schema.reference_name(
        @schema.field_at(captured_schema(read.rows), column).unwrap().name,
      )
    Completed(output) => completed_column_name(output, column).unwrap()
  }
}

///|
fn record_guard_cell(
  source : RecordGuardSource,
  row : Int,
  column : Int,
) -> Value {
  match source {
    Supplied(read) => Captured(captured_cell(read.rows, row, column).unwrap())
    Completed(output) => completed_cell(output, row, column).unwrap()
  }
}

///|
fn clear_record_guard(state : RecordGuardState) -> Bool {
  if state.phase is Emit(cursor) {
    cancel_identity_wire(cursor)
  }
  if state.writer is Some(writer) {
    @encode.cancel_writer(writer)
    state.writer = None
  }
  state.phase = Done
  release_slots(state.workspace, state.workspace.live)
  workspace_healthy(state.workspace)
}

///|
fn step_record_guard(
  state : RecordGuardState,
) -> Result[Unit, FixedInputGuardIssue] {
  if !record_guard_available(state.source) {
    return Err(ForeignInput)
  }
  if state.budget.work <= 0 {
    return Err(MeasurementWork)
  }
  state.budget.work -= 1
  try {
    match state.phase {
      BeginRow =>
        if state.row == state.rows {
          state.phase = Done
        } else {
          let writer = @encode.measuring_writer(
            state.budget.bytes,
            Int::min(state.budget.nodes, state.writer_nodes),
            state.writer_depth,
          )
          state.writer = Some(writer)
          @encode.begin_object(writer)
          state.column = 0
          state.phase = BeginColumn
        }
      BeginColumn =>
        if state.column == state.columns {
          state.phase = EndRow
        } else {
          let writer = state.writer.unwrap()
          @encode.key(writer, record_guard_name(state.source, state.column))
          state.phase = Emit(
            identity_scan_emit(
              record_guard_cell(state.source, state.row, state.column),
              writer,
            ),
          )
        }
      Emit(cursor) =>
        if advance_identity_wire(cursor) {
          state.column += 1
          state.phase = BeginColumn
        }
      EndRow => {
        let writer = state.writer.unwrap()
        @encode.end_object(writer)
        let (bytes, nodes, _) = @encode.finish_measurement_usage(writer)
        state.writer = None
        state.budget.bytes -= bytes
        state.budget.nodes -= nodes
        if bytes > state.ceiling {
          return Err(ValueBytes(state.scope, state.row, -1))
        }
        state.row += 1
        state.phase = BeginRow
      }
      Done => ()
    }
    Ok(())
  } catch {
    issue => Err(Measurement(state.scope, state.row, -1, issue))
  }
}

///|
fn start_record_guard(
  control : @bounded.Control,
  source : RecordGuardSource,
  rows : Int,
  columns : Int,
  scope : FixedInputGuardPhase,
  ceiling : Int,
  physical : FixedInputGuardMeasureLimits,
  max_workspace_slots : Int,
) -> Result[FixedRecordGuardScan, FixedInputGuardIssue] {
  if ceiling < 0 ||
    physical.max_work < 0 ||
    physical.max_bytes < 0 ||
    physical.max_nodes < 0 ||
    physical.max_depth < 0 ||
    max_workspace_slots < 0 {
    return Err(InvalidLimits)
  }
  if !record_guard_available(source) {
    return Err(ForeignInput)
  }
  let workspace = row_workspace(max_workspace_slots)
  // Reserve the writer's keys and the existing wire cursor's continuations
  // before either is created. No row object or encoded payload is retained.
  if max_workspace_slots == 0 {
    return Err(MeasurementWork)
  }
  // Limit the writer's live envelope, not the cumulative node allowance.
  // A high cumulative allowance must not require allocating it up front.
  let writer_depth = Int::min(physical.max_depth, (max_workspace_slots - 1) / 3)
  let writer_nodes = Int::min(
    physical.max_nodes,
    (max_workspace_slots - writer_depth - 1) / 2,
  )
  guard checked_row_slots_add(writer_nodes, writer_nodes) is Some(slots) &&
    checked_row_slots_add(slots, writer_depth) is Some(slots) &&
    checked_row_slots_add(slots, 1) is Some(slots) &&
    reserve_slots(workspace, slots) else {
    return Err(MeasurementWork)
  }
  let state : RecordGuardState = {
    source,
    scope,
    rows,
    columns,
    ceiling,
    initial: physical,
    budget: {
      work: physical.max_work,
      bytes: physical.max_bytes,
      nodes: physical.max_nodes,
      depth: physical.max_depth,
    },
    workspace,
    writer_nodes,
    writer_depth,
    row: 0,
    column: 0,
    writer: None,
    phase: BeginRow,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    (state, quantum, reader) => {
      let mut used = 0
      while used < quantum {
        if @bounded.stop_requested(reader) is Some(reason) {
          return @bounded.Stopped(reason, used, used)
        }
        used += 1
        match step_record_guard(state) {
          Err(issue) => return @bounded.Failed(issue, used, used)
          Ok(_) => ()
        }
        if state.phase is Done {
          return @bounded.Complete(
            {
              ..state.initial,
              max_work: state.budget.work,
              max_bytes: state.budget.bytes,
              max_nodes: state.budget.nodes,
            },
            used,
            used,
          )
        }
      }
      @bounded.Continue(used, used)
    },
    clear_record_guard,
    _ => true,
  )
  Ok({ session, token, })
}

///|
pub fn start_supplied_record_guard(
  control : @bounded.Control,
  input : SuppliedRelationRead,
  ceiling : Int,
  physical : FixedInputGuardMeasureLimits,
  max_workspace_slots : Int,
) -> Result[FixedRecordGuardScan, FixedInputGuardIssue] {
  start_record_guard(
    control,
    Supplied(input),
    supplied_relation_read_row_count(input),
    @schema.field_count(supplied_relation_read_schema(input)),
    InputValues,
    ceiling,
    physical,
    max_workspace_slots,
  )
}

///|
pub fn start_completed_record_guard(
  control : @bounded.Control,
  output : CompletedOutput,
  ceiling : Int,
  physical : FixedInputGuardMeasureLimits,
  max_workspace_slots : Int,
) -> Result[FixedRecordGuardScan, FixedInputGuardIssue] {
  if output.table is None {
    return Err(InputRepresentationRequired(0))
  }
  start_record_guard(
    control,
    Completed(output),
    completed_row_count(output),
    completed_column_count(output),
    Output,
    ceiling,
    physical,
    max_workspace_slots,
  )
}

///|
pub fn advance_fixed_record_guard(
  scan : FixedRecordGuardScan,
  quantum : Int,
) -> Result[
  @bounded.Observation[FixedInputGuardMeasureLimits, FixedInputGuardIssue],
  @bounded.Issue,
] {
  let poll = match @bounded.advance(scan.session, scan.token, quantum) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if poll is @bounded.ContinueWith(token, ..) {
    scan.token = token
  }
  Ok(poll)
}

///|
pub fn cleanup_fixed_record_guard(
  scan : FixedRecordGuardScan,
) -> Result[Bool, @bounded.Issue] {
  match @bounded.cleanup(scan.session) {
    Ok(_) => Ok(!@bounded.cleanup_pending(scan.session))
    Err(issue) => Err(issue)
  }
}
