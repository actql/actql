///|
priv enum BoundedUnnestInput {
  CompletedUnnestInput(ProducerRead)
  SuppliedUnnestInput(SuppliedRelationRead)
}

///|
fn unnest_bounded_available(input : BoundedUnnestInput) -> Bool {
  match input {
    CompletedUnnestInput(read) =>
      producer_read_available(read) && producer_read_has_cell_access(read)
    SuppliedUnnestInput(read) => supplied_relation_read_available(read)
  }
}

///|
fn unnest_bounded_matches(
  input : BoundedUnnestInput,
  owner : @lower.BoundPrepared,
  step : Int,
) -> Bool {
  match input {
    CompletedUnnestInput(read) =>
      producer_read_matches_operation_input(read, owner, step, 0)
    SuppliedUnnestInput(read) =>
      supplied_relation_read_matches_operation_input(read, owner, step, 0)
  }
}

///|
fn unnest_bounded_schema(input : BoundedUnnestInput) -> @schema.Schema {
  match input {
    CompletedUnnestInput(read) => producer_read_schema(read)
    SuppliedUnnestInput(read) => supplied_relation_read_schema(read)
  }
}

///|
fn unnest_bounded_count(input : BoundedUnnestInput) -> Int {
  match input {
    CompletedUnnestInput(read) => producer_read_row_count(read)
    SuppliedUnnestInput(read) => supplied_relation_read_row_count(read)
  }
}

///|
fn unnest_bounded_cell(
  input : BoundedUnnestInput,
  row : Int,
  column : Int,
) -> Value? {
  match input {
    CompletedUnnestInput(read) => producer_read_cell(read, row, column)
    SuppliedUnnestInput(read) =>
      supplied_relation_read_cell(read, row, column).map(capture)
  }
}

///|
fn unnest_bounded_trusted_input(
  input : BoundedUnnestInput,
) -> TrustedOutputInput {
  match input {
    CompletedUnnestInput(read) => trusted_output_relation_input(read)
    SuppliedUnnestInput(read) => trusted_output_supplied_relation_input(read)
  }
}

///|
priv enum BoundedUnnestPhase {
  ResolveInput
  ResolveOutput
  ChargeInput
  BeginSource
  BuildCell
  CommitRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedUnnestState {
  input : BoundedUnnestInput
  output_schema : @schema.Schema
  source_name : String
  element_name : String
  index_name : String?
  outer : Bool
  max_items : Int64?
  control : ControlBudget
  workspace : RowWorkspace
  input_values : ValueBudget
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedUnnestPhase
  mut names : Array[String]
  ordinals : Map[String, Int]
  mut output_columns : Array[Int]
  mut field : Int
  mut source_column : Int
  mut saw_element : Bool
  mut saw_index : Bool
  mut charge_row : Int
  mut charge_column : Int
  mut charge_open : Bool
  mut charge_measure : SteppedValueMeasure?
  mut source : Int
  mut source_ready : Bool
  mut item : Int
  mut item_count : Int
  mut synthetic : Bool
  mut column : Int
  mut checked_row : Array[@admitted.CheckedValue]
  mut emitted : Int
  max_rows : Int
}

///|
pub(all) enum BoundedUnnestIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedUnnestExecution {
  state : BoundedUnnestState
  session : @bounded.Session[
    BoundedUnnestState,
    CompletedOutput,
    BoundedUnnestIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
#warnings("-unused_value")
fn bounded_unnest_measuring_input(execution : BoundedUnnestExecution) -> Bool {
  execution.state.phase is ChargeInput &&
  execution.state.charge_measure is Some(_)
}

///|
pub enum BoundedUnnestPoll {
  BoundedUnnestContinue(progress~ : Int64, work~ : Int64)
  BoundedUnnestComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedUnnestFailed(BoundedUnnestIssue, progress~ : Int64, work~ : Int64)
  BoundedUnnestStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn fail_bounded_unnest(
  issue : BoundedUnnestIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedUnnestIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_unnest_state(state : BoundedUnnestState) -> Bool {
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.names = []
  state.ordinals.clear()
  state.output_columns = []
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
fn bounded_unnest_step(
  state : BoundedUnnestState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedUnnestIssue] {
  let mut used = 0
  let mut progress = 0
  let width = @schema.field_count(unnest_bounded_schema(state.input))
  let output_width = @schema.field_count(state.output_schema)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !unnest_bounded_available(state.input) {
      return fail_bounded_unnest(InvalidExecution, progress, used)
    }
    match state.phase {
      ResolveInput => {
        if state.field == width {
          if state.source_column < 0 {
            return fail_bounded_unnest(Rows(InvalidRows), progress, used)
          }
          state.field = 0
          state.phase = ResolveOutput
          continue
        }
        guard @schema.field_at(unnest_bounded_schema(state.input), state.field)
          is Some(field) else {
          return fail_bounded_unnest(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        if state.ordinals.contains(name) {
          return fail_bounded_unnest(Rows(InvalidRows), progress, used)
        }
        if !reserve_slots(state.workspace, 2) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return fail_bounded_unnest(Rows(RowLimit), progress, used)
        }
        if name == state.source_name {
          state.source_column = state.field
        }
        state.names.push(name)
        state.ordinals[name] = state.field
        state.field += 1
        used += 1
      }
      ResolveOutput => {
        if state.field == output_width {
          if !state.saw_element ||
            (state.index_name is Some(_) && !state.saw_index) {
            return fail_bounded_unnest(Rows(InvalidRows), progress, used)
          }
          state.phase = ChargeInput
          continue
        }
        guard @schema.field_at(state.output_schema, state.field) is Some(field) else {
          return fail_bounded_unnest(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        if !reserve_slots(state.workspace, 1) ||
          !spend_control_text(state.control, name) {
          return fail_bounded_unnest(Rows(RowLimit), progress, used)
        }
        let source = if name == state.element_name {
          if state.saw_element {
            return fail_bounded_unnest(Rows(InvalidRows), progress, used)
          }
          state.saw_element = true
          -1
        } else if state.index_name is Some(index) && name == index {
          if state.saw_index {
            return fail_bounded_unnest(Rows(InvalidRows), progress, used)
          }
          state.saw_index = true
          -2
        } else {
          guard state.ordinals.get(name) is Some(ordinal) else {
            return fail_bounded_unnest(Rows(InvalidRows), progress, used)
          }
          ordinal
        }
        state.output_columns.push(source)
        state.field += 1
        used += 1
      }
      ChargeInput => {
        if state.charge_row == unnest_bounded_count(state.input) {
          state.phase = BeginSource
          continue
        }
        if !state.charge_open {
          if !spend_control(state.control, 1) ||
            !charge_node(state.input_values, 1) {
            return fail_bounded_unnest(InputLimit, progress, used)
          }
          state.charge_open = true
          used += 1
        } else if state.charge_column < width {
          if state.charge_measure is None {
            guard unnest_bounded_cell(
                state.input,
                state.charge_row,
                state.charge_column,
              )
              is Some(value) else {
              return fail_bounded_unnest(InvalidExecution, progress, used)
            }
            if !charge_text(
                state.input_values,
                state.names[state.charge_column],
              ) {
              return fail_bounded_unnest(InputLimit, progress, used)
            }
            guard start_stepped_measure_result(value, state.workspace)
              is Some(cursor) else {
              return fail_bounded_unnest(Rows(RowLimit), progress, used)
            }
            state.charge_measure = Some(cursor)
          }
          let cursor = state.charge_measure.unwrap()
          match advance_stepped_measure_result(cursor, state.input_values) {
            SteppedMeasureLimit =>
              return fail_bounded_unnest(InputLimit, progress, used)
            SteppedMeasureWorkspaceLimit =>
              return fail_bounded_unnest(Rows(RowLimit), progress, used)
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
        if state.source == unnest_bounded_count(state.input) {
          state.phase = FinishOutput
          continue
        }
        if !state.source_ready {
          guard unnest_bounded_cell(
              state.input,
              state.source,
              state.source_column,
            )
            is Some(value) else {
            return fail_bounded_unnest(InvalidExecution, progress, used)
          }
          let count = match value {
            Captured(@admitted.Array(items)) => @admitted.element_count(items)
            Null => 0
            _ => return fail_bounded_unnest(Rows(InvalidRows), progress, used)
          }
          if state.max_items is Some(limit) && count.to_int64() > limit {
            return fail_bounded_unnest(Rows(InvalidRows), progress, used)
          }
          state.synthetic = count == 0
          state.item_count = if state.synthetic && state.outer {
            1
          } else {
            count
          }
          state.source_ready = true
          used += 1
          if state.item_count == 0 {
            state.source += 1
            state.source_ready = false
            continue
          }
          continue
        }
        if state.item == state.item_count {
          state.source += 1
          state.source_ready = false
          state.item = 0
          continue
        }
        if state.emitted >= state.max_rows || !spend_control(state.control, 1) {
          return fail_bounded_unnest(Rows(RowLimit), progress, used)
        }
        state.column = 0
        state.checked_row = []
        state.phase = BuildCell
        used += 1
      }
      BuildCell => {
        if state.column == output_width {
          state.phase = CommitRow
          continue
        }
        let source = state.output_columns[state.column]
        let value = if source == -1 {
          if state.synthetic {
            Null
          } else {
            guard unnest_bounded_cell(
                state.input,
                state.source,
                state.source_column,
              )
              is Some(Captured(@admitted.Array(items))) &&
              @admitted.element_at(items, state.item) is Some(element) else {
              return fail_bounded_unnest(InvalidExecution, progress, used)
            }
            capture(element)
          }
        } else if source == -2 {
          if state.synthetic {
            Null
          } else {
            Number(state.item.to_double())
          }
        } else {
          guard unnest_bounded_cell(state.input, state.source, source)
            is Some(value) else {
            return fail_bounded_unnest(InvalidExecution, progress, used)
          }
          value
        }
        guard @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return fail_bounded_unnest(InvalidExecution, progress, used)
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) {
          return fail_bounded_unnest(Rows(RowLimit), progress, used)
        }
        guard checked_ordered_output_value(
            value,
            field.contract,
            state.admitted_limits,
          )
          is Some(checked) else {
          return fail_bounded_unnest(Rows(InvalidRows), progress, used)
        }
        state.checked_row.push(checked)
        state.column += 1
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return fail_bounded_unnest(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Err(issue) =>
            return fail_bounded_unnest(Capture(issue), progress, used + 1)
          Ok(_) => ()
        }
        release_slots(state.workspace, state.checked_row.length())
        state.checked_row = []
        state.emitted += 1
        state.item += 1
        state.phase = BeginSource
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return fail_bounded_unnest(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return fail_bounded_unnest(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => fail_bounded_unnest(Completion(issue), progress, used)
        }
      }
      Terminal => return fail_bounded_unnest(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_bounded_unnest_input(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : BoundedUnnestInput,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedUnnestExecution, BoundedUnnestIssue] {
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
    is Some(@lower.RowStep(kernel)) &&
    @lower.kernel_unnest(kernel)
    is Some((source_column, element_name, index_name, outer, max_items)) &&
    unnest_bounded_matches(input, owner, step) &&
    unnest_bounded_available(input) else {
    return Err(InvalidExecution)
  }
  let width = @schema.field_count(unnest_bounded_schema(input))
  let output_schema = @lower.kernel_output_schema(kernel)
  let output_width = @schema.field_count(output_schema)
  let added = if index_name is Some(_) { 2 } else { 1 }
  if output_width < added ||
    output_width - added != width ||
    width > max_entries / 2 {
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
      inputs=[unnest_bounded_trusted_input(input)],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedUnnestState = {
    input,
    output_schema,
    source_name: @schema.reference_name(source_column),
    element_name,
    index_name,
    outer,
    max_items,
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
    phase: ResolveInput,
    names: [],
    ordinals: Map([]),
    output_columns: [],
    field: 0,
    source_column: -1,
    saw_element: false,
    saw_index: false,
    charge_row: 0,
    charge_column: 0,
    charge_open: false,
    charge_measure: None,
    source: 0,
    source_ready: false,
    item: 0,
    item_count: 0,
    synthetic: false,
    column: 0,
    checked_row: [],
    emitted: 0,
    max_rows,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_unnest_step,
    cleanup_bounded_unnest_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ state, session, token: Some(token), accepted, })
}

///|
pub fn start_bounded_unnest(
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
) -> Result[BoundedUnnestExecution, BoundedUnnestIssue] {
  start_bounded_unnest_input(
    engine,
    generated,
    CompletedUnnestInput(input),
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
pub fn start_bounded_unnest_supplied(
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
) -> Result[BoundedUnnestExecution, BoundedUnnestIssue] {
  start_bounded_unnest_input(
    engine,
    generated,
    SuppliedUnnestInput(input),
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
pub fn advance_bounded_unnest(
  value : BoundedUnnestExecution,
  quantum : Int,
) -> Result[BoundedUnnestPoll, BoundedUnnestIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedUnnestContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedUnnestComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedUnnestFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedUnnestStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_unnest(
  value : BoundedUnnestExecution,
) -> Result[Bool, BoundedUnnestIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
