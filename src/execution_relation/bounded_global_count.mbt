///|
priv enum BoundedGlobalCountInput {
  CompletedGlobalCountInput(ProducerRead)
  SuppliedGlobalCountInput(SuppliedRelationRead)
}

///|
fn global_count_input_available(input : BoundedGlobalCountInput) -> Bool {
  match input {
    CompletedGlobalCountInput(read) =>
      producer_read_available(read) && producer_read_has_cell_access(read)
    SuppliedGlobalCountInput(read) => supplied_relation_read_available(read)
  }
}

///|
fn global_count_input_matches(
  input : BoundedGlobalCountInput,
  owner : @lower.BoundPrepared,
  step : Int,
) -> Bool {
  match input {
    CompletedGlobalCountInput(read) =>
      producer_read_matches_operation_input(read, owner, step, 0)
    SuppliedGlobalCountInput(read) =>
      supplied_relation_read_matches_operation_input(read, owner, step, 0)
  }
}

///|
fn global_count_input_schema(input : BoundedGlobalCountInput) -> @schema.Schema {
  match input {
    CompletedGlobalCountInput(read) => producer_read_schema(read)
    SuppliedGlobalCountInput(read) => supplied_relation_read_schema(read)
  }
}

///|
fn global_count_input_count(input : BoundedGlobalCountInput) -> Int {
  match input {
    CompletedGlobalCountInput(read) => producer_read_row_count(read)
    SuppliedGlobalCountInput(read) => supplied_relation_read_row_count(read)
  }
}

///|
fn global_count_input_cell(
  input : BoundedGlobalCountInput,
  row : Int,
  column : Int,
) -> Value? {
  match input {
    CompletedGlobalCountInput(read) => producer_read_cell(read, row, column)
    SuppliedGlobalCountInput(read) =>
      supplied_relation_read_cell(read, row, column).map(capture)
  }
}

///|
fn global_count_trusted_input(
  input : BoundedGlobalCountInput,
) -> TrustedOutputInput {
  match input {
    CompletedGlobalCountInput(read) => trusted_output_relation_input(read)
    SuppliedGlobalCountInput(read) =>
      trusted_output_supplied_relation_input(read)
  }
}

///|
priv enum BoundedGlobalCountPhase {
  ResolveInput
  ResolveAggregates
  ResolveOutput
  ChargeInput
  CountRows
  BuildOutput
  CommitOutput
  FinishOutput
  Terminal
}

///|
priv struct BoundedGlobalCountState {
  input : BoundedGlobalCountInput
  group : @lower.PreparedCountGroup
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
  mut phase : BoundedGlobalCountPhase
  ordinals : Map[String, Int]
  mut input_names : Array[String]
  aggregate_names : Map[String, Int]
  mut aggregate_columns : Array[Int?]
  mut counts : Array[Int]
  mut output_columns : Array[Int]
  mut field : Int
  mut charge_row : Int
  mut charge_column : Int
  mut charge_open : Bool
  mut row : Int
  mut aggregate : Int
  mut row_open : Bool
  mut checked_row : Array[@admitted.CheckedValue]
}

///|
pub(all) enum BoundedGlobalCountIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedGlobalCountExecution {
  session : @bounded.Session[
    BoundedGlobalCountState,
    CompletedOutput,
    BoundedGlobalCountIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum BoundedGlobalCountPoll {
  BoundedGlobalCountContinue(progress~ : Int64, work~ : Int64)
  BoundedGlobalCountComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedGlobalCountFailed(
    BoundedGlobalCountIssue,
    progress~ : Int64,
    work~ : Int64
  )
  BoundedGlobalCountStopped(
    @bounded.StopReason,
    progress~ : Int64,
    work~ : Int64
  )
}

///|
fn global_count_failure(
  issue : BoundedGlobalCountIssue,
  progress : Int,
  used : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedGlobalCountIssue] {
  @bounded.Failed(issue, progress, used)
}

///|
fn cleanup_bounded_global_count_state(state : BoundedGlobalCountState) -> Bool {
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.ordinals.clear()
  state.input_names = []
  state.aggregate_names.clear()
  state.aggregate_columns = []
  state.counts = []
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
fn bounded_global_count_step(
  state : BoundedGlobalCountState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedGlobalCountIssue] {
  let mut used = 0
  let mut progress = 0
  let width = @schema.field_count(global_count_input_schema(state.input))
  let aggregate_count = @lower.count_group_aggregate_count(state.group)
  let output_width = @schema.field_count(state.output_schema)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !global_count_input_available(state.input) {
      return global_count_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ResolveInput => {
        if state.field == width {
          state.field = 0
          state.phase = ResolveAggregates
          continue
        }
        guard @schema.field_at(
            global_count_input_schema(state.input),
            state.field,
          )
          is Some(field) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        if state.ordinals.contains(name) {
          return global_count_failure(Rows(InvalidRows), progress, used)
        }
        if !reserve_slots(state.workspace, 2) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        state.ordinals[name] = state.field
        state.input_names.push(name)
        state.field += 1
        used += 1
      }
      ResolveAggregates => {
        if state.field == aggregate_count {
          state.field = 0
          state.phase = ResolveOutput
          continue
        }
        guard @lower.count_group_aggregate_at(state.group, state.field)
          is Some(aggregate) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        if state.aggregate_names.contains(aggregate.name) {
          return global_count_failure(Rows(InvalidRows), progress, used)
        }
        let column = match aggregate.field {
          None => None
          Some(field) => {
            let name = @schema.reference_name(field)
            if !spend_control_text(state.control, name) {
              return global_count_failure(Rows(RowLimit), progress, used)
            }
            match state.ordinals.get(name) {
              Some(index) => Some(index)
              None =>
                return global_count_failure(Rows(InvalidRows), progress, used)
            }
          }
        }
        if !reserve_slots(state.workspace, 3) ||
          !spend_control(state.control, 1) ||
          !spend_control_text(state.control, aggregate.name) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        state.aggregate_names[aggregate.name] = state.field
        state.aggregate_columns.push(column)
        state.counts.push(0)
        state.field += 1
        used += 1
      }
      ResolveOutput => {
        if state.field == output_width {
          state.phase = ChargeInput
          continue
        }
        guard @schema.field_at(state.output_schema, state.field) is Some(field) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        guard state.aggregate_names.get(name) is Some(index) else {
          return global_count_failure(Rows(InvalidRows), progress, used)
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control_text(state.control, name) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        state.output_columns.push(index)
        state.field += 1
        used += 1
      }
      ChargeInput => {
        if state.charge_row == global_count_input_count(state.input) {
          state.phase = CountRows
          continue
        }
        if !state.charge_open {
          if !spend_control(state.control, 1) ||
            !charge_node(state.input_values, 1) {
            return global_count_failure(InputLimit, progress, used)
          }
          state.charge_open = true
          used += 1
        } else if state.charge_column < width {
          guard global_count_input_cell(
              state.input,
              state.charge_row,
              state.charge_column,
            )
            is Some(value) else {
            return global_count_failure(InvalidExecution, progress, used)
          }
          if !charge_text(
              state.input_values,
              state.input_names[state.charge_column],
            ) ||
            !measure_result(value, state.input_values) {
            return global_count_failure(InputLimit, progress, used)
          }
          state.charge_column += 1
          used += 1
        } else {
          state.charge_row += 1
          state.charge_column = 0
          state.charge_open = false
        }
      }
      CountRows => {
        if state.row == global_count_input_count(state.input) {
          state.field = 0
          state.phase = BuildOutput
          continue
        }
        if !state.row_open {
          if !spend_control(state.control, 1) {
            return global_count_failure(Rows(RowLimit), progress, used)
          }
          state.row_open = true
          used += 1
        } else if state.aggregate < aggregate_count {
          if !spend_control(state.control, 1) {
            return global_count_failure(Rows(RowLimit), progress, used)
          }
          let counted = match state.aggregate_columns[state.aggregate] {
            None => true
            Some(column) => {
              guard global_count_input_cell(state.input, state.row, column)
                is Some(value) else {
                return global_count_failure(InvalidExecution, progress, used)
              }
              !(value is Null)
            }
          }
          if counted {
            state.counts[state.aggregate] += 1
          }
          state.aggregate += 1
          used += 1
        } else {
          state.row += 1
          state.aggregate = 0
          state.row_open = false
        }
      }
      BuildOutput => {
        if state.field == output_width {
          state.phase = CommitOutput
          continue
        }
        guard @schema.field_at(state.output_schema, state.field) is Some(field) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        if !reserve_slots(state.workspace, 1) ||
          !spend_control(state.control, 1) {
          return global_count_failure(Rows(RowLimit), progress, used)
        }
        let count = state.counts[state.output_columns[state.field]]
        guard checked_ordered_output_value(
            Number(count.to_double()),
            field.contract,
            state.admitted_limits,
          )
          is Some(checked) else {
          return global_count_failure(Rows(InvalidRows), progress, used)
        }
        state.checked_row.push(checked)
        state.field += 1
        used += 1
      }
      CommitOutput => {
        guard state.output is Some(output) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Err(issue) =>
            return global_count_failure(Capture(issue), progress, used + 1)
          Ok(_) => ()
        }
        release_slots(state.workspace, state.checked_row.length())
        state.checked_row = []
        state.phase = FinishOutput
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return global_count_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return global_count_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => global_count_failure(Completion(issue), progress, used)
        }
      }
      Terminal => return global_count_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn start_bounded_global_count_with_input(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  input : BoundedGlobalCountInput,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedGlobalCountExecution, BoundedGlobalCountIssue] {
  if max_rows < 1 ||
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
    @lower.kernel_count_group(kernel) is Some(group) &&
    @lower.count_group_key_count(group) == 0 &&
    global_count_input_matches(input, owner, step) &&
    global_count_input_available(input) else {
    return Err(InvalidExecution)
  }
  let output_schema = @lower.count_group_output_schema(group)
  if @schema.field_count(output_schema) !=
    @lower.count_group_aggregate_count(group) {
    return Err(InvalidExecution)
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
      inputs=[global_count_trusted_input(input)],
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedGlobalCountState = {
    input,
    group,
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
    phase: ResolveInput,
    ordinals: Map([]),
    input_names: [],
    aggregate_names: Map([]),
    aggregate_columns: [],
    counts: [],
    output_columns: [],
    field: 0,
    charge_row: 0,
    charge_column: 0,
    charge_open: false,
    row: 0,
    aggregate: 0,
    row_open: false,
    checked_row: [],
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_global_count_step,
    cleanup_bounded_global_count_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn start_bounded_global_count(
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
) -> Result[BoundedGlobalCountExecution, BoundedGlobalCountIssue] {
  start_bounded_global_count_with_input(
    engine,
    generated,
    CompletedGlobalCountInput(input),
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
pub fn start_bounded_global_count_supplied(
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
) -> Result[BoundedGlobalCountExecution, BoundedGlobalCountIssue] {
  start_bounded_global_count_with_input(
    engine,
    generated,
    SuppliedGlobalCountInput(input),
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
pub fn advance_bounded_global_count(
  value : BoundedGlobalCountExecution,
  quantum : Int,
) -> Result[BoundedGlobalCountPoll, BoundedGlobalCountIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedGlobalCountContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedGlobalCountComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedGlobalCountFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedGlobalCountStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_global_count(
  value : BoundedGlobalCountExecution,
) -> Result[Bool, BoundedGlobalCountIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
