///|
priv enum BoundedValuesPhase {
  PrepareCompletionPort
  ChargeNames
  BeginRow
  BuildCell
  CommitRow
  FinishOutput
  Terminal
}

///|
priv struct BoundedValuesState {
  owner : @lower.BoundPrepared
  step : Int
  schema : @schema.Schema
  count : Int
  width : Int
  input_values : ValueBudget
  admitted_limits : @admitted.Limits
  control : ControlBudget
  workspace : RowWorkspace
  mut output : AdmittedOutput?
  rows : Ref[AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  mut port : TrustedOutputPort[Unit]?
  mut port_preparation : TrustedOutputPreparation?
  mut phase : BoundedValuesPhase
  mut name : Int
  mut row : Int
  mut column : Int
  mut checked_row : Array[@admitted.Value]
  mut pending_input : @admitted.CheckedValue?
  mut input_measure : SteppedValueMeasure?
  mut output_recheck : @admitted.RecheckCursor?
  mut output_charge : BoundedOutputRowCharge?
}

///|
pub(all) enum BoundedValuesIssue {
  InvalidExecution
  InputLimit
  Rows(RowIssue)
  Capture(CaptureIssue)
  Completion(TrustedOutputIssue)
  Execution(@bounded.Issue)
}

///|
struct BoundedValuesExecution {
  state : BoundedValuesState
  session : @bounded.Session[
    BoundedValuesState,
    CompletedOutput,
    BoundedValuesIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum BoundedValuesPoll {
  BoundedValuesContinue(progress~ : Int64, work~ : Int64)
  BoundedValuesComplete(CompletedOutput, progress~ : Int64, work~ : Int64)
  BoundedValuesFailed(BoundedValuesIssue, progress~ : Int64, work~ : Int64)
  BoundedValuesStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn cleanup_bounded_values_state(state : BoundedValuesState) -> Bool {
  if state.port_preparation is Some(cursor) {
    cancel_trusted_output_preparation(cursor)
    state.port_preparation = None
  }
  if state.input_measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.input_measure = None
  }
  state.pending_input = None
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
  state.checked_row = []
  release_slots(state.workspace, state.workspace.live)
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
fn bounded_values_step(
  state : BoundedValuesState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[CompletedOutput, BoundedValuesIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    match state.phase {
      PrepareCompletionPort => {
        guard state.port_preparation is Some(cursor) else {
          return @bounded.Failed(InvalidExecution, progress, used)
        }
        match advance_trusted_output_preparation(cursor) {
          Err(issue) =>
            return @bounded.Failed(Completion(issue), progress, used + 1)
          Ok(false) => ()
          Ok(true) => {
            let live = state.live
            let rows = state.rows
            state.port = match
              finish_trusted_output_preparation(cursor, fn(_) {
                if live.val {
                  rows.val
                } else {
                  None
                }
              }) {
              Ok(port) => Some(port)
              Err(issue) =>
                return @bounded.Failed(Completion(issue), progress, used + 1)
            }
            state.port_preparation = None
            state.phase = ChargeNames
          }
        }
        used += 1
      }
      ChargeNames => {
        if state.name == state.width {
          state.phase = BeginRow
          continue
        }
        guard @schema.field_at(state.schema, state.name) is Some(field) else {
          return @bounded.Failed(InvalidExecution, progress, used)
        }
        if !spend_control(state.control, 1) ||
          !spend_control_text(state.control, @schema.reference_name(field.name)) {
          return @bounded.Failed(Rows(RowLimit), progress, used)
        }
        state.name += 1
        used += 1
      }
      BeginRow => {
        if state.row == state.count {
          state.phase = FinishOutput
          continue
        }
        if !charge_node(state.input_values, 1) ||
          !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, 2) {
          return @bounded.Failed(InputLimit, progress, used)
        }
        state.checked_row = []
        state.column = 0
        state.phase = BuildCell
        used += 1
      }
      BuildCell => {
        if state.output_recheck is Some(cursor) {
          match @admitted.advance_recheck_runtime_value(cursor) {
            RecheckContinue => ()
            RecheckFailed =>
              return @bounded.Failed(
                Capture(InvalidCheckedRow),
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
        if state.input_measure is Some(cursor) {
          match advance_stepped_measure_result(cursor, state.input_values) {
            SteppedMeasureLimit =>
              return @bounded.Failed(InputLimit, progress, used + 1)
            SteppedMeasureWorkspaceLimit =>
              return @bounded.Failed(Rows(RowLimit), progress, used + 1)
            SteppedMeasureContinue => ()
            SteppedMeasureComplete => {
              clear_stepped_measure(cursor)
              state.input_measure = None
            }
          }
          used += 1
          continue
        }
        if state.column == state.width {
          state.phase = CommitRow
          continue
        }
        guard @schema.field_at(state.schema, state.column) is Some(field) else {
          return @bounded.Failed(InvalidExecution, progress, used)
        }
        let name = @schema.reference_name(field.name)
        let checked = match state.pending_input {
          Some(checked) => checked
          None =>
            match
              @lower.bound_values_cell(
                state.owner,
                state.step,
                state.row,
                state.column,
              ) {
              Ok(value) => value
              Err(@lower.MissingValuesParameter(name)) =>
                return @bounded.Failed(
                  Capture(MissingParameter(name)),
                  progress,
                  used,
                )
              Err(_) =>
                return @bounded.Failed(
                  Capture(InvalidCheckedRow),
                  progress,
                  used,
                )
            }
        }
        if state.pending_input is None {
          if !charge_text(state.input_values, name) {
            return @bounded.Failed(InputLimit, progress, used)
          }
          if bounded_small_output_value(Captured(checked.value)) {
            if !measure(checked.value, 2, state.input_values) {
              return @bounded.Failed(InputLimit, progress, used)
            }
          } else {
            guard start_stepped_measure_result(
                Captured(checked.value),
                state.workspace,
              )
              is Some(cursor) else {
              return @bounded.Failed(Rows(RowLimit), progress, used)
            }
            state.pending_input = Some(checked)
            state.input_measure = Some(cursor)
            used += 1
            continue
          }
        }
        state.pending_input = None
        if !spend_control(state.control, 1) ||
          !reserve_slots(state.workspace, 1) {
          return @bounded.Failed(Rows(RowLimit), progress, used)
        }
        if bounded_small_output_value(Captured(checked.value)) {
          guard @admitted.recheck_runtime_value(
              checked.value,
              field.contract,
              state.admitted_limits,
            )
            is Some(output) else {
            return @bounded.Failed(Capture(InvalidCheckedRow), progress, used)
          }
          state.checked_row.push(output.value)
          state.column += 1
        } else {
          guard @admitted.start_recheck_runtime_value(
              checked.value,
              field.contract,
              state.admitted_limits,
            )
            is Some(cursor) else {
            return @bounded.Failed(Capture(InvalidCheckedRow), progress, used)
          }
          state.output_recheck = Some(cursor)
        }
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidExecution, progress, used)
        }
        if state.output_charge is None {
          match
            start_bounded_output_row_charge(
              output,
              state.checked_row,
              state.workspace,
            ) {
            Err(OutputCapture(issue)) =>
              return @bounded.Failed(Capture(issue), progress, used + 1)
            Err(OutputWorkspace) =>
              return @bounded.Failed(Rows(RowLimit), progress, used + 1)
            Ok(cursor) => state.output_charge = Some(cursor)
          }
          used += 1
          continue
        }
        match advance_bounded_output_row_charge(state.output_charge.unwrap()) {
          Err(OutputCapture(issue)) =>
            return @bounded.Failed(Capture(issue), progress, used + 1)
          Err(OutputWorkspace) =>
            return @bounded.Failed(Rows(RowLimit), progress, used + 1)
          Ok(false) => {
            used += 1
            continue
          }
          Ok(true) => state.output_charge = None
        }
        release_slots(state.workspace, 2 + state.checked_row.length())
        state.checked_row = []
        state.row += 1
        state.phase = BeginRow
        progress += 1
        used += 1
      }
      FinishOutput => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidExecution, progress, used)
        }
        state.output = None
        let rows = match finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(Capture(issue), progress, used + 1)
        }
        state.rows.val = Some(rows)
        state.phase = Terminal
        used += 1
        guard state.port is Some(port) else {
          return @bounded.Failed(InvalidExecution, progress, used)
        }
        return match complete_trusted_output(port, ()) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(Completion(issue), progress, used)
        }
      }
      Terminal => return @bounded.Failed(InvalidExecution, progress, used)
    }
  }
  @bounded.Continue(progress, used)
}

///|
pub fn start_bounded_values(
  engine : @bounded.Control,
  generated : GeneratedSequence,
  max_rows : Int,
  input_values : ValueLimits,
  output_values : ValueLimits,
  max_work : Int,
  max_frames : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[BoundedValuesExecution, BoundedValuesIssue] {
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
    @lower.sequence_step(generated.sequence, step) is Some(@lower.ValuesStep(_)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_values_row_count(node) is Some(count) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidExecution)
  }
  let width = @schema.field_count(schema)
  if count > max_rows ||
    count > input_values.max_nodes ||
    width > max_entries - 2 {
    return Err(InputLimit)
  }
  let input_budget = match value_budget(input_values) {
    Ok(value) => value
    Err(issue) => return Err(Capture(issue))
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
  let port_preparation = match
    start_trusted_output_preparation(
      generated_completion_preparation(generated),
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      Some([]),
    ) {
    Ok(value) => value
    Err(issue) => {
      cancel_admitted_output(output) |> ignore
      return Err(Completion(issue))
    }
  }
  let state : BoundedValuesState = {
    owner,
    step,
    schema,
    count,
    width,
    input_values: input_budget,
    admitted_limits: {
      max_nodes: output_values.max_nodes,
      max_depth: output_values.max_depth,
      max_text_bytes: output_values.max_text_bytes,
    },
    control: { remaining: max_work, max_frames, },
    workspace: row_workspace(max_entries),
    output: Some(output),
    rows,
    live,
    accepted,
    port: None,
    port_preparation: Some(port_preparation),
    phase: PrepareCompletionPort,
    name: 0,
    row: 0,
    column: 0,
    checked_row: [],
    pending_input: None,
    input_measure: None,
    output_recheck: None,
    output_charge: None,
  }
  let (session, token) = @bounded.start(
    engine,
    state,
    bounded_values_step,
    cleanup_bounded_values_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ state, session, token: Some(token), accepted, })
}

///|
pub fn advance_bounded_values(
  value : BoundedValuesExecution,
  quantum : Int,
) -> Result[BoundedValuesPoll, BoundedValuesIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(BoundedValuesContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(BoundedValuesComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(BoundedValuesFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(BoundedValuesStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_bounded_values(
  value : BoundedValuesExecution,
) -> Result[Bool, BoundedValuesIssue] {
  let changed = match @bounded.cleanup(value.session) {
    Ok(changed) => changed
    Err(issue) => return Err(Execution(issue))
  }
  if !@bounded.cleanup_pending(value.session) &&
    (
      value.state.workspace.live != 0 ||
      value.state.input_measure is Some(_) ||
      value.state.output_recheck is Some(_) ||
      value.state.output_charge is Some(_) ||
      value.state.port_preparation is Some(_)
    ) {
    return Err(InvalidExecution)
  }
  Ok(changed)
}
