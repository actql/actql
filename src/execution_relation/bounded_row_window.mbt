///|
priv enum BoundedRowWindowPhase {
  ResolveInputField
  ResolveOutputField
  ChargeInput
  BeginSource
  CollectMembership
  BeginMembership
  BuildCell
  CommitRow
  FinishOutput
  Terminal
}

///|
priv enum BoundedRowWindowInput {
  CompletedWindowInput(ProducerRead)
  SuppliedWindowInput(SuppliedRelationRead)
}

///|
fn bounded_window_input_available(input : BoundedRowWindowInput) -> Bool {
  match input {
    CompletedWindowInput(read) =>
      producer_read_available(read) && producer_read_has_cell_access(read)
    SuppliedWindowInput(read) => supplied_relation_read_available(read)
  }
}

///|
fn bounded_window_input_matches(
  input : BoundedRowWindowInput,
  owner : @lower.BoundPrepared,
  step : Int,
) -> Bool {
  match input {
    CompletedWindowInput(read) =>
      producer_read_matches_operation_input(read, owner, step, 0)
    SuppliedWindowInput(read) =>
      supplied_relation_read_matches_operation_input(read, owner, step, 0)
  }
}

///|
fn bounded_window_input_schema(input : BoundedRowWindowInput) -> @schema.Schema {
  match input {
    CompletedWindowInput(read) => producer_read_schema(read)
    SuppliedWindowInput(read) => supplied_relation_read_schema(read)
  }
}

///|
fn bounded_window_input_count(input : BoundedRowWindowInput) -> Int {
  match input {
    CompletedWindowInput(read) => producer_read_row_count(read)
    SuppliedWindowInput(read) => supplied_relation_read_row_count(read)
  }
}

///|
fn bounded_window_input_cell(
  input : BoundedRowWindowInput,
  row : Int,
  column : Int,
) -> Value? {
  match input {
    CompletedWindowInput(read) => producer_read_cell(read, row, column)
    SuppliedWindowInput(read) =>
      supplied_relation_read_cell(read, row, column).map(capture)
  }
}

///|
fn bounded_window_trusted_input(
  input : BoundedRowWindowInput,
) -> TrustedOutputInput {
  match input {
    CompletedWindowInput(read) => trusted_output_relation_input(read)
    SuppliedWindowInput(read) => trusted_output_supplied_relation_input(read)
  }
}

///|
priv struct BoundedRowWindowState {
  input : BoundedRowWindowInput
  window : @lower.PreparedWindow
  output_schema : @schema.Schema
  control : ControlBudget
  workspace : RowWorkspace
  input_values : ValueBudget
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedRowWindowPhase
  mut input_names : Array[String]
  mut output_columns : Array[Int]
  input_ordinals : Map[String, Int]
  mut field : Int
  mut time_column : Int
  mut saw_start : Bool
  mut saw_end : Bool
  mut charge_row : Int
  mut charge_column : Int
  mut charge_open : Bool
  mut charge_measure : SteppedValueMeasure?
  mut source : Int
  mut time : @grid.Coordinate?
  mut current : @bigint.BigInt
  size : @bigint.BigInt
  step : @bigint.BigInt
  mut memberships : Array[(Double, Double)]
  mut membership : Int
  mut column : Int
  mut checked_row : Array[@admitted.CheckedValue]
  mut emitted : Int
  max_rows : Int
}

///|
pub(all) enum BoundedRowWindowIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedRowWindowExecution {
  state : BoundedRowWindowState
  session : @bounded.Session[
    BoundedRowWindowState,
    CompletedOutput,
    BoundedRowWindowIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
#warnings("-unused_value")
fn bounded_row_window_measuring_input(
  execution : BoundedRowWindowExecution,
) -> Bool {
  execution.state.phase is ChargeInput &&
  execution.state.charge_measure is Some(_)
}

///|
pub enum BoundedRowWindowPoll {
  BoundedRowWindowContinue(progress~ : Int64, work~ : Int64)
  BoundedRowWindowComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedRowWindowFailed(
    BoundedRowWindowIssue,
    progress~ : Int64,
    work~ : Int64
  )
  BoundedRowWindowStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn bounded_row_window_failure(
  issue : BoundedRowWindowIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedRowWindowIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_row_window_state(state : BoundedRowWindowState) -> Bool {
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.input_names = []
  state.output_columns = []
  state.input_ordinals.clear()
  state.memberships = []
  state.checked_row = []
  if state.charge_measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.charge_measure = None
  }
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn bounded_row_window_step(
  state : BoundedRowWindowState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedRowWindowIssue] {
  let mut used = 0
  let mut progress = 0
  let width = @schema.field_count(bounded_window_input_schema(state.input))
  let output_width = @schema.field_count(state.output_schema)
  let (start_field, end_field) = @lower.window_boundaries(state.window)
  let start_name = @schema.reference_name(start_field)
  let end_name = @schema.reference_name(end_field)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !bounded_window_input_available(state.input) {
      return bounded_row_window_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ResolveInputField => {
        if state.field == width {
          if state.time_column < 0 ||
            !spend_control_text(state.control, start_name) ||
            !spend_control_text(state.control, end_name) {
            return bounded_row_window_failure(
              Rows(if state.time_column < 0 { InvalidRows } else { RowLimit }),
              progress,
              used,
            )
          }
          state.field = 0
          state.phase = ResolveOutputField
          continue
        }
        guard @schema.field_at(
            bounded_window_input_schema(state.input),
            state.field,
          )
          is Some(field) else {
          return bounded_row_window_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        if state.input_ordinals.contains(name) {
          return bounded_row_window_failure(Rows(InvalidRows), progress, used)
        }
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) ||
          !reserve_slots(state.workspace, 2) {
          return bounded_row_window_failure(Rows(RowLimit), progress, used)
        }
        state.input_ordinals[name] = state.field
        state.input_names.push(name)
        if name == @schema.reference_name(@lower.window_time(state.window)) {
          state.time_column = state.field
        }
        state.field += 1
        used += 1
      }
      ResolveOutputField => {
        if state.field == output_width {
          if !state.saw_start || !state.saw_end {
            return bounded_row_window_failure(Rows(InvalidRows), progress, used)
          }
          state.phase = ChargeInput
          continue
        }
        guard @schema.field_at(state.output_schema, state.field) is Some(field) else {
          return bounded_row_window_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        if !spend_control_text(state.control, name) ||
          !reserve_slots(state.workspace, 1) {
          return bounded_row_window_failure(Rows(RowLimit), progress, used)
        }
        let source = if name == start_name {
          if state.saw_start {
            return bounded_row_window_failure(Rows(InvalidRows), progress, used)
          }
          state.saw_start = true
          -1
        } else if name == end_name {
          if state.saw_end {
            return bounded_row_window_failure(Rows(InvalidRows), progress, used)
          }
          state.saw_end = true
          -2
        } else {
          match state.input_ordinals.get(name) {
            Some(index) => index
            None =>
              return bounded_row_window_failure(
                Rows(InvalidRows),
                progress,
                used,
              )
          }
        }
        state.output_columns.push(source)
        state.field += 1
        used += 1
      }
      ChargeInput => {
        if state.charge_row == bounded_window_input_count(state.input) {
          state.phase = BeginSource
          continue
        }
        if !state.charge_open {
          if !spend_control(state.control, 1) ||
            !charge_node(state.input_values, 1) {
            return bounded_row_window_failure(InputLimit, progress, used)
          }
          state.charge_open = true
          used += 1
        } else if state.charge_column < width {
          if state.charge_measure is None {
            let column = state.charge_column
            guard bounded_window_input_cell(
                state.input,
                state.charge_row,
                column,
              )
              is Some(value) else {
              return bounded_row_window_failure(
                InvalidExecution,
                progress,
                used,
              )
            }
            if !charge_text(state.input_values, state.input_names[column]) {
              return bounded_row_window_failure(InputLimit, progress, used)
            }
            guard start_stepped_measure_result(value, state.workspace)
              is Some(cursor) else {
              return bounded_row_window_failure(Rows(RowLimit), progress, used)
            }
            state.charge_measure = Some(cursor)
          }
          let cursor = state.charge_measure.unwrap()
          match advance_stepped_measure_result(cursor, state.input_values) {
            SteppedMeasureLimit =>
              return bounded_row_window_failure(InputLimit, progress, used)
            SteppedMeasureWorkspaceLimit =>
              return bounded_row_window_failure(Rows(RowLimit), progress, used)
            SteppedMeasureContinue => ()
            SteppedMeasureComplete => {
              clear_stepped_measure(cursor)
              state.charge_measure = None
              state.charge_column += 1
            }
          }
          used += 1
        } else {
          state.charge_row += 1
          state.charge_column = 0
          state.charge_open = false
        }
      }
      BeginSource => {
        if state.source == bounded_window_input_count(state.input) {
          state.phase = FinishOutput
          continue
        }
        guard bounded_window_input_cell(
            state.input,
            state.source,
            state.time_column,
          )
          is Some(value) else {
          return bounded_row_window_failure(InvalidExecution, progress, used)
        }
        let coordinate = match
          window_time_coordinate(
            value,
            @lower.window_requires_epoch_milliseconds(state.window),
            state.control,
          ) {
          Ok(value) => value
          Err(issue) =>
            return bounded_row_window_failure(
              Rows(window_time_row_issue(issue, state.source)),
              progress,
              used + 1,
            )
        }
        if !spend_control(state.control, 1) {
          return bounded_row_window_failure(Rows(RowLimit), progress, used + 1)
        }
        state.time = Some(coordinate)
        state.current = @grid.latest_start(
          coordinate,
          @lower.window_effective_step(state.window),
          @lower.window_offset(state.window),
        )
        state.phase = CollectMembership
        used += 1
      }
      CollectMembership => {
        guard state.time is Some(time) else {
          return bounded_row_window_failure(InvalidExecution, progress, used)
        }
        let end = state.current + state.size
        if @grid.compare(time, state.current) < 0 ||
          @grid.compare(time, end) >= 0 {
          state.membership = state.memberships.length() - 1
          state.phase = BeginMembership
          continue
        }
        if state.emitted >= state.max_rows ||
          state.memberships.length() >= state.max_rows - state.emitted ||
          !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) {
          return bounded_row_window_failure(Rows(RowLimit), progress, used + 1)
        }
        guard @grid.exact_binary64_boundary(state.current) is Some(start_number) &&
          @grid.exact_binary64_boundary(end) is Some(end_number) else {
          return bounded_row_window_failure(
            Rows(WindowArithmetic(state.source)),
            progress,
            used + 1,
          )
        }
        state.memberships.push((start_number, end_number))
        if @lower.window_kind(state.window) == @window.Fixed {
          state.membership = state.memberships.length() - 1
          state.phase = BeginMembership
        } else {
          state.current -= state.step
        }
        used += 1
      }
      BeginMembership => {
        if state.membership < 0 {
          release_slots(state.workspace, state.memberships.length())
          state.memberships = []
          state.source += 1
          state.phase = BeginSource
          continue
        }
        state.checked_row = []
        state.column = 0
        state.phase = BuildCell
      }
      BuildCell => {
        if state.column == output_width {
          state.phase = CommitRow
          continue
        }
        let source = state.output_columns[state.column]
        let (start_number, end_number) = state.memberships[state.membership]
        let value = if source == -1 {
          Number(start_number)
        } else if source == -2 {
          Number(end_number)
        } else {
          guard bounded_window_input_cell(state.input, state.source, source)
            is Some(value) else {
            return bounded_row_window_failure(InvalidExecution, progress, used)
          }
          value
        }
        guard @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return bounded_row_window_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, 1) {
          return bounded_row_window_failure(Rows(RowLimit), progress, used)
        }
        guard checked_ordered_output_value(
            value,
            field.contract,
            state.admitted_limits,
          )
          is Some(checked) else {
          return bounded_row_window_failure(Rows(InvalidRows), progress, used)
        }
        state.checked_row.push(checked)
        state.column += 1
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return bounded_row_window_failure(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Err(issue) =>
            return bounded_row_window_failure(
              Capture(issue),
              progress,
              used + 1,
            )
          Ok(_) => ()
        }
        release_slots(state.workspace, state.checked_row.length())
        state.checked_row = []
        state.emitted += 1
        state.membership -= 1
        state.phase = BeginMembership
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_row_window_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_row_window_failure(
              Capture(issue),
              progress,
              used + 1,
            )
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) =>
            bounded_row_window_failure(Completion(issue), progress, used)
        }
      }
      Terminal =>
        return bounded_row_window_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_bounded_row_window_with_input(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : BoundedRowWindowInput,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedRowWindowExecution, BoundedRowWindowIssue] {
  if max_rows < 0 ||
    max_work < 0 ||
    max_frames < 0 ||
    max_entries < 0 ||
    max_name_bytes < 0 {
    return Err(InvalidExecution)
  }
  let owner = @lower.sequence_owner(generated.sequence)
  guard generated_sequence_step_index_at(generated, 0) is Some(step) &&
    generated_sequence_step_index_at(generated, 1) is None &&
    @lower.sequence_step(generated.sequence, step)
    is Some(@lower.WindowStep(window)) &&
    bounded_window_input_matches(input, owner, step) &&
    bounded_window_input_available(input) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  let width = @schema.field_count(bounded_window_input_schema(input))
  let output_width = @schema.field_count(output_schema)
  let size = @lower.window_size(window)
  let interval = @lower.window_effective_step(window)
  if size <= 0L ||
    interval <= 0L ||
    output_width < 2 ||
    output_width - 2 != width ||
    bounded_window_input_count(input) > max_rows ||
    width > max_entries / 2 ||
    output_width > max_entries - width * 2 {
    return Err(Rows(RowLimit))
  }
  let input_values = match value_budget(input_values) {
    Ok(value) => value
    Err(_) => return Err(InputLimit)
  }
  let output = match
    prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      output_values,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
  }
  let rows : Ref[AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    prepare_trusted_output_port_with_inputs(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs=[bounded_window_trusted_input(input)],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedRowWindowState = {
    input,
    window,
    output_schema,
    control: { remaining: max_work, max_frames, },
    workspace: row_workspace(max_entries),
    input_values,
    admitted_limits: {
      max_nodes: output_values.max_nodes,
      max_depth: output_values.max_depth,
      max_text_bytes: output_values.max_text_bytes,
    },
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: ResolveInputField,
    input_names: [],
    output_columns: [],
    input_ordinals: Map([]),
    field: 0,
    time_column: -1,
    saw_start: false,
    saw_end: false,
    charge_row: 0,
    charge_column: 0,
    charge_open: false,
    charge_measure: None,
    source: 0,
    time: None,
    current: @bigint.BigInt::from_int(0),
    size: @bigint.BigInt::from_int64(size),
    step: @bigint.BigInt::from_int64(interval),
    memberships: [],
    membership: -1,
    column: 0,
    checked_row: [],
    emitted: 0,
    max_rows,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_row_window_step,
    cleanup_bounded_row_window_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ state, session, token: Some(token), accepted, })
}

///|
pub fn start_bounded_row_window(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : ProducerRead,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedRowWindowExecution, BoundedRowWindowIssue] {
  start_bounded_row_window_with_input(
    engine,
    generated,
    CompletedWindowInput(input),
    max_rows,
    input_values,
    output_values,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
  )
}

///|
pub fn start_bounded_row_window_supplied(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : SuppliedRelationRead,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedRowWindowExecution, BoundedRowWindowIssue] {
  start_bounded_row_window_with_input(
    engine,
    generated,
    SuppliedWindowInput(input),
    max_rows,
    input_values,
    output_values,
    max_work,
    max_frames,
    max_entries,
    max_name_bytes,
  )
}

///|
pub fn advance_bounded_row_window(
  value : BoundedRowWindowExecution,
  quantum : Int,
) -> Result[BoundedRowWindowPoll, BoundedRowWindowIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedRowWindowContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedRowWindowComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedRowWindowFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedRowWindowStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_row_window(
  value : BoundedRowWindowExecution,
) -> Result[Bool, BoundedRowWindowIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
