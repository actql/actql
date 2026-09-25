///|
priv enum BoundedUnpivotInput {
  CompletedUnpivotInput(ProducerRead)
  SuppliedUnpivotInput(SuppliedRelationRead)
}

///|
fn unpivot_input_available(input : BoundedUnpivotInput) -> Bool {
  match input {
    CompletedUnpivotInput(read) =>
      producer_read_available(read) && producer_read_has_cell_access(read)
    SuppliedUnpivotInput(read) => supplied_relation_read_available(read)
  }
}

///|
fn unpivot_input_matches(
  input : BoundedUnpivotInput,
  owner : @lower.BoundPrepared,
  step : Int,
) -> Bool {
  match input {
    CompletedUnpivotInput(read) =>
      producer_read_matches_operation_input(read, owner, step, 0)
    SuppliedUnpivotInput(read) =>
      supplied_relation_read_matches_operation_input(read, owner, step, 0)
  }
}

///|
fn unpivot_input_schema(input : BoundedUnpivotInput) -> @schema.Schema {
  match input {
    CompletedUnpivotInput(read) => producer_read_schema(read)
    SuppliedUnpivotInput(read) => supplied_relation_read_schema(read)
  }
}

///|
fn unpivot_input_count(input : BoundedUnpivotInput) -> Int {
  match input {
    CompletedUnpivotInput(read) => producer_read_row_count(read)
    SuppliedUnpivotInput(read) => supplied_relation_read_row_count(read)
  }
}

///|
fn unpivot_input_cell(
  input : BoundedUnpivotInput,
  row : Int,
  column : Int,
) -> Value? {
  match input {
    CompletedUnpivotInput(read) => producer_read_cell(read, row, column)
    SuppliedUnpivotInput(read) =>
      supplied_relation_read_cell(read, row, column).map(capture)
  }
}

///|
fn unpivot_trusted_input(input : BoundedUnpivotInput) -> TrustedOutputInput {
  match input {
    CompletedUnpivotInput(read) => trusted_output_relation_input(read)
    SuppliedUnpivotInput(read) => trusted_output_supplied_relation_input(read)
  }
}

///|
priv enum BoundedUnpivotPhase {
  ResolveInputField
  ResolveColumn
  ResolveKeep
  ResolveOutputField
  ChargeInput
  BeginSource
  BuildCell
  CommitRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedUnpivotState {
  input : BoundedUnpivotInput
  kernel : @lower.PreparedKernel
  output_schema : @schema.Schema
  name_column : String
  value_column : String
  control : ControlBudget
  workspace : RowWorkspace
  input_values : ValueBudget
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut phase : BoundedUnpivotPhase
  mut names : Array[String]
  ordinals : Map[String, Int]
  mut columns : Array[Int]
  mut labels : Array[String]
  keeps : Map[String, Int]
  mut output_columns : Array[Int]
  mut field : Int
  mut saw_name : Bool
  mut saw_value : Bool
  mut charge_row : Int
  mut charge_column : Int
  mut charge_open : Bool
  mut source : Int
  mut occurrence : Int
  mut column : Int
  mut checked_row : Array[@admitted.CheckedValue]
  mut emitted : Int
  max_rows : Int
}

///|
pub(all) enum BoundedUnpivotIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedUnpivotExecution {
  session : @bounded.Session[
    BoundedUnpivotState,
    CompletedOutput,
    BoundedUnpivotIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum BoundedUnpivotPoll {
  BoundedUnpivotContinue(progress~ : Int64, work~ : Int64)
  BoundedUnpivotComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedUnpivotFailed(BoundedUnpivotIssue, progress~ : Int64, work~ : Int64)
  BoundedUnpivotStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn fail_bounded_unpivot(
  issue : BoundedUnpivotIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedUnpivotIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_unpivot_state(state : BoundedUnpivotState) -> Bool {
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.names = []
  state.ordinals.clear()
  state.columns = []
  state.labels = []
  state.keeps.clear()
  state.output_columns = []
  state.checked_row = []
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn bounded_unpivot_step(
  state : BoundedUnpivotState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedUnpivotIssue] {
  let mut used = 0
  let mut progress = 0
  let width = @schema.field_count(unpivot_input_schema(state.input))
  let output_width = @schema.field_count(state.output_schema)
  let column_count = @lower.kernel_unpivot_column_count(state.kernel)
  let keep_count = @lower.kernel_unpivot_keep_count(state.kernel)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !unpivot_input_available(state.input) {
      return fail_bounded_unpivot(InvalidExecution, progress, used)
    }
    match state.phase {
      ResolveInputField => {
        if state.field == width {
          state.field = 0
          state.phase = ResolveColumn
          continue
        }
        guard @schema.field_at(unpivot_input_schema(state.input), state.field)
          is Some(field) else {
          return fail_bounded_unpivot(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        if state.ordinals.contains(name) {
          return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
        }
        if !reserve_slots(state.workspace, 2) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return fail_bounded_unpivot(Rows(RowLimit), progress, used)
        }
        state.names.push(name)
        state.ordinals[name] = state.field
        state.field += 1
        used += 1
      }
      ResolveColumn => {
        if state.field == column_count {
          state.field = 0
          state.phase = ResolveKeep
          continue
        }
        guard @lower.kernel_unpivot_column_at(state.kernel, state.field)
          is Some(field) else {
          return fail_bounded_unpivot(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field)
        guard state.ordinals.get(name) is Some(ordinal) else {
          return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
        }
        if !reserve_slots(state.workspace, 2) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return fail_bounded_unpivot(Rows(RowLimit), progress, used)
        }
        state.columns.push(ordinal)
        state.labels.push(name)
        state.field += 1
        used += 1
      }
      ResolveKeep => {
        if state.field == keep_count {
          state.field = 0
          state.phase = ResolveOutputField
          continue
        }
        guard @lower.kernel_unpivot_keep_at(state.kernel, state.field)
          is Some(field) else {
          return fail_bounded_unpivot(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field)
        if state.keeps.contains(name) {
          return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
        }
        guard state.ordinals.get(name) is Some(ordinal) else {
          return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return fail_bounded_unpivot(Rows(RowLimit), progress, used)
        }
        state.keeps[name] = ordinal
        state.field += 1
        used += 1
      }
      ResolveOutputField => {
        if state.field == output_width {
          if !state.saw_name || !state.saw_value {
            return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
          }
          state.phase = ChargeInput
          continue
        }
        guard @schema.field_at(state.output_schema, state.field) is Some(field) else {
          return fail_bounded_unpivot(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        if !reserve_slots(state.workspace, 1) ||
          !spend_control_text(state.control, name) {
          return fail_bounded_unpivot(Rows(RowLimit), progress, used)
        }
        let source = if name == state.name_column {
          if state.saw_name {
            return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
          }
          state.saw_name = true
          -1
        } else if name == state.value_column {
          if state.saw_value {
            return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
          }
          state.saw_value = true
          -2
        } else {
          guard state.keeps.get(name) is Some(index) else {
            return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
          }
          index
        }
        state.output_columns.push(source)
        state.field += 1
        used += 1
      }
      ChargeInput => {
        if state.charge_row == unpivot_input_count(state.input) {
          state.phase = BeginSource
          continue
        }
        if !state.charge_open {
          if !spend_control(state.control, 1) ||
            !charge_node(state.input_values, 1) {
            return fail_bounded_unpivot(InputLimit, progress, used)
          }
          state.charge_open = true
          used += 1
        } else if state.charge_column < width {
          guard unpivot_input_cell(
              state.input,
              state.charge_row,
              state.charge_column,
            )
            is Some(value) else {
            return fail_bounded_unpivot(InvalidExecution, progress, used)
          }
          if !charge_text(state.input_values, state.names[state.charge_column]) ||
            !measure_result(value, state.input_values) {
            return fail_bounded_unpivot(InputLimit, progress, used)
          }
          state.charge_column += 1
          used += 1
        } else {
          state.charge_row += 1
          state.charge_column = 0
          state.charge_open = false
        }
      }
      BeginSource => {
        if state.source == unpivot_input_count(state.input) {
          state.phase = FinishOutput
          continue
        }
        if state.occurrence == column_count {
          state.source += 1
          state.occurrence = 0
          continue
        }
        if state.emitted >= state.max_rows || !spend_control(state.control, 1) {
          return fail_bounded_unpivot(Rows(RowLimit), progress, used)
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
          Text(state.labels[state.occurrence])
        } else if source == -2 {
          guard unpivot_input_cell(
              state.input,
              state.source,
              state.columns[state.occurrence],
            )
            is Some(value) else {
            return fail_bounded_unpivot(InvalidExecution, progress, used)
          }
          value
        } else {
          guard unpivot_input_cell(state.input, state.source, source)
            is Some(value) else {
            return fail_bounded_unpivot(InvalidExecution, progress, used)
          }
          value
        }
        guard @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return fail_bounded_unpivot(InvalidExecution, progress, used)
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) {
          return fail_bounded_unpivot(Rows(RowLimit), progress, used)
        }
        guard checked_ordered_output_value(
            value,
            field.contract,
            state.admitted_limits,
          )
          is Some(checked) else {
          return fail_bounded_unpivot(Rows(InvalidRows), progress, used)
        }
        state.checked_row.push(checked)
        state.column += 1
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return fail_bounded_unpivot(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Err(issue) =>
            return fail_bounded_unpivot(Capture(issue), progress, used + 1)
          Ok(_) => ()
        }
        release_slots(state.workspace, state.checked_row.length())
        state.checked_row = []
        state.emitted += 1
        state.occurrence += 1
        state.phase = BeginSource
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return fail_bounded_unpivot(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return fail_bounded_unpivot(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => fail_bounded_unpivot(Completion(issue), progress, used)
        }
      }
      Terminal => return fail_bounded_unpivot(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_bounded_unpivot_input(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : BoundedUnpivotInput,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedUnpivotExecution, BoundedUnpivotIssue] {
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
    @lower.kernel_unpivot_outputs(kernel) is Some((name_column, value_column)) &&
    unpivot_input_matches(input, owner, step) &&
    unpivot_input_available(input) else {
    return Err(InvalidExecution)
  }
  let width = @schema.field_count(unpivot_input_schema(input))
  let output_schema = @lower.kernel_output_schema(kernel)
  let output_width = @schema.field_count(output_schema)
  let columns = @lower.kernel_unpivot_column_count(kernel)
  let keep = @lower.kernel_unpivot_keep_count(kernel)
  if columns <= 0 ||
    output_width < 2 ||
    output_width - 2 != keep ||
    unpivot_input_count(input) > max_rows ||
    width > max_entries / 2 ||
    columns > max_entries / 2 {
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
      inputs=[unpivot_trusted_input(input)],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedUnpivotState = {
    input,
    kernel,
    output_schema,
    name_column,
    value_column,
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
    names: [],
    ordinals: Map([]),
    columns: [],
    labels: [],
    keeps: Map([]),
    output_columns: [],
    field: 0,
    saw_name: false,
    saw_value: false,
    charge_row: 0,
    charge_column: 0,
    charge_open: false,
    source: 0,
    occurrence: 0,
    column: 0,
    checked_row: [],
    emitted: 0,
    max_rows,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_unpivot_step,
    cleanup_bounded_unpivot_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn start_bounded_unpivot(
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
) -> Result[BoundedUnpivotExecution, BoundedUnpivotIssue] {
  start_bounded_unpivot_input(
    engine,
    generated,
    CompletedUnpivotInput(input),
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
pub fn start_bounded_unpivot_supplied(
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
) -> Result[BoundedUnpivotExecution, BoundedUnpivotIssue] {
  start_bounded_unpivot_input(
    engine,
    generated,
    SuppliedUnpivotInput(input),
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
pub fn advance_bounded_unpivot(
  value : BoundedUnpivotExecution,
  quantum : Int,
) -> Result[BoundedUnpivotPoll, BoundedUnpivotIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedUnpivotContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedUnpivotComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedUnpivotFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedUnpivotStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_unpivot(
  value : BoundedUnpivotExecution,
) -> Result[Bool, BoundedUnpivotIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
