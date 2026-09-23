///|
priv enum BoundedAppendPhase {
  ResolveField
  BeginRow
  BuildCell
  CommitRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedAppendState {
  left : ProducerRead
  right : ProducerRead
  kernel : @lower.PreparedAppendKernel
  output_schema : @schema.Schema
  control : ControlBudget
  workspace : RowWorkspace
  admitted_limits : @admitted.Limits
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : TrustedOutputPort[Unit]
  mut names : Array[String]
  mut left_columns : Array[Int]
  mut right_columns : Array[Int]
  mut phase : BoundedAppendPhase
  mut field : Int
  mut on_left : Bool
  mut left_row : Int
  mut right_row : Int
  mut column : Int
  mut checked_row : Array[@admitted.CheckedValue]
}

///|
pub(all) enum BoundedAppendIssue {
  InvalidExecution
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedAppendExecution {
  session : @bounded.Session[
    BoundedAppendState,
    CompletedOutput,
    BoundedAppendIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum BoundedAppendPoll {
  BoundedAppendContinue(progress~ : Int64, work~ : Int64)
  BoundedAppendComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedAppendFailed(BoundedAppendIssue, progress~ : Int64, work~ : Int64)
  BoundedAppendStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn bounded_append_failure(
  issue : BoundedAppendIssue,
  progress : Int,
  work : Int,
) -> @bounded.KernelStep[CompletedOutput, BoundedAppendIssue] {
  @bounded.Failed(issue, progress, work)
}

///|
fn cleanup_bounded_append_state(state : BoundedAppendState) -> Bool {
  if state.output is Some(output) {
    cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.names = []
  state.left_columns = []
  state.right_columns = []
  state.checked_row = []
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn bounded_append_step(
  state : BoundedAppendState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedAppendIssue] {
  let mut used = 0
  let mut progress = 0
  let width = @lower.append_kernel_field_count(state.kernel)
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !producer_read_available(state.left) ||
      !producer_read_available(state.right) {
      return bounded_append_failure(InvalidExecution, progress, used)
    }
    match state.phase {
      ResolveField => {
        if state.field == width {
          state.phase = BeginRow
          continue
        }
        guard @lower.append_kernel_field_at(state.kernel, state.field)
          is Some((field, left_column, right_column)) &&
          @schema.field_at(producer_read_schema(state.left), left_column)
          is Some(left_field) &&
          @schema.field_at(producer_read_schema(state.right), right_column)
          is Some(right_field) else {
          return bounded_append_failure(Rows(InputMismatch), progress, used)
        }
        let name = @schema.reference_name(field)
        if @schema.reference_name(left_field.name) != name ||
          @schema.reference_name(right_field.name) != name {
          return bounded_append_failure(Rows(InputMismatch), progress, used)
        }
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, name) ||
          !reserve_slots(state.workspace, 3) {
          return bounded_append_failure(Rows(RowLimit), progress, used)
        }
        state.names.push(name)
        state.left_columns.push(left_column)
        state.right_columns.push(right_column)
        state.field += 1
        used += 1
      }
      BeginRow => {
        if state.left_row < producer_read_row_count(state.left) {
          state.on_left = true
        } else if state.right_row < producer_read_row_count(state.right) {
          state.on_left = false
        } else {
          state.phase = FinishOutput
          continue
        }
        if !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, 2) {
          return bounded_append_failure(Rows(RowLimit), progress, used)
        }
        state.column = 0
        state.checked_row = []
        state.phase = BuildCell
        used += 1
      }
      BuildCell => {
        if state.column == width {
          state.phase = CommitRow
          continue
        }
        let input = if state.on_left { state.left } else { state.right }
        let row = if state.on_left { state.left_row } else { state.right_row }
        let source = if state.on_left {
          state.left_columns[state.column]
        } else {
          state.right_columns[state.column]
        }
        guard producer_read_cell(input, row, source) is Some(value) &&
          @schema.field_at(state.output_schema, state.column) is Some(field) else {
          return bounded_append_failure(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, 1) {
          return bounded_append_failure(Rows(RowLimit), progress, used)
        }
        guard checked_ordered_output_value(
            value,
            field.contract,
            state.admitted_limits,
          )
          is Some(checked) else {
          return bounded_append_failure(Rows(InputMismatch), progress, used)
        }
        state.checked_row.push(checked)
        state.column += 1
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return bounded_append_failure(InvalidExecution, progress, used)
        }
        match append_admitted_output(output, state.checked_row) {
          Err(issue) =>
            return bounded_append_failure(Capture(issue), progress, used + 1)
          Ok(_) => ()
        }
        release_slots(state.workspace, state.checked_row.length())
        state.checked_row = []
        if state.on_left {
          state.left_row += 1
        } else {
          state.right_row += 1
        }
        state.phase = BeginRow
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return bounded_append_failure(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return bounded_append_failure(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        return match complete_trusted_output(state.port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) =>
            bounded_append_failure(Completion(issue), progress, used)
        }
      }
      Terminal =>
        return bounded_append_failure(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_append(
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
) -> Result[BoundedAppendExecution, BoundedAppendIssue] {
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
    is Some(@lower.AppendStep(kernel)) &&
    producer_read_matches_operation_input(left, owner, step, 0) &&
    producer_read_matches_operation_input(right, owner, step, 1) &&
    producer_read_has_cell_access(left) &&
    producer_read_has_cell_access(right) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(output_schema) else {
    return Err(InvalidExecution)
  }
  let left_count = producer_read_row_count(left)
  let right_count = producer_read_row_count(right)
  if left_count > max_rows || right_count > max_rows - left_count {
    return Err(Rows(RowLimit))
  }
  let width = @lower.append_kernel_field_count(kernel)
  if width != @schema.field_count(output_schema) ||
    width > @schema.field_count(producer_read_schema(left)) ||
    width > @schema.field_count(producer_read_schema(right)) ||
    width > max_entries / 3 {
    return Err(Rows(RowLimit))
  }
  let workspace = row_workspace(max_entries)
  let output = match
    prepare_admitted_output(owner, @pipeline.Step(step), max_rows, values) {
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
  let state : BoundedAppendState = {
    left,
    right,
    kernel,
    output_schema,
    control: { remaining: max_work, max_frames, },
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
    names: [],
    left_columns: [],
    right_columns: [],
    phase: ResolveField,
    field: 0,
    on_left: true,
    left_row: 0,
    right_row: 0,
    column: 0,
    checked_row: [],
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_append_step,
    cleanup_bounded_append_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_bounded_append(
  value : BoundedAppendExecution,
  quantum : Int,
) -> Result[BoundedAppendPoll, BoundedAppendIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedAppendContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedAppendComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedAppendFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedAppendStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_append(
  value : BoundedAppendExecution,
) -> Result[Bool, BoundedAppendIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
