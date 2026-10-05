///|
/// Incremental import of typed immutable cells. This imports material only;
/// successful execution must still be proven by an installed output verifier.
priv enum AdmittedOutputPhase {
  BeginRow
  ReadCell
  AdmitCell
  MeasureName
  MeasureValue
  CommitRow
  Seal
}

///|
priv struct AdmittedOutputState {
  output : AdmittedOutput
  count : Int
  read : (Int, Int) -> @admitted.Value?
  workspace : RowWorkspace
  max_work : Int
  mut work : Int
  mut row : Int
  mut column : Int
  mut cells : Array[@admitted.Value]
  mut pending : @admitted.Value?
  mut measure : SteppedValueMeasure?
  mut admission : @admitted.RecheckCursor?
  mut phase : AdmittedOutputPhase
  mut material : AdmittedOutputRows?
  mut reclaimed : Bool
}

///|
struct AdmittedOutputPreparation {
  state : AdmittedOutputState
  session : @bounded.Session[
    AdmittedOutputState,
    AdmittedOutputRows,
    CaptureIssue,
  ]
  mut token : @bounded.Token
  control : @bounded.Control
  mut accepted : Bool
}

///|
pub enum AdmittedOutputPoll {
  AdmittedOutputContinue(work~ : Int64)
  AdmittedOutputComplete(AdmittedOutputRows, work~ : Int64)
  AdmittedOutputFailed(CaptureIssue, work~ : Int64)
  AdmittedOutputStopped(work~ : Int64)
}

///|
fn discard_admitted_output_state(state : AdmittedOutputState) -> Bool {
  if state.reclaimed {
    return true
  }
  if state.measure is Some(cursor) {
    clear_stepped_measure(cursor)
    state.measure = None
  }
  if state.admission is Some(cursor) {
    @admitted.cancel_recheck_runtime_value(cursor)
    state.admission = None
  }
  state.pending = None
  state.cells.clear()
  state.output.buffer.rows.clear()
  state.output.buffer.open = false
  state.output.buffer.reading = false
  release_slots(state.workspace, state.workspace.live)
  state.material = None
  state.reclaimed = true
  workspace_healthy(state.workspace)
}

///|
fn advance_admitted_output_state(
  state : AdmittedOutputState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[AdmittedOutputRows, CaptureIssue] {
  let mut used = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, used, used)
    }
    if !state.output.buffer.open {
      return @bounded.Failed(ClosedCapture, used, used)
    }
    if state.work >= state.max_work {
      return @bounded.Failed(CaptureLimit, used, used)
    }
    state.work += 1
    used += 1
    let buffer = state.output.buffer
    let width = @schema.field_count(buffer.schema)
    match state.phase {
      BeginRow => {
        if state.row == state.count {
          state.phase = Seal
          continue
        }
        if state.row >= buffer.max_rows ||
          width == 2147483647 ||
          !reserve_slots(state.workspace, width + 1) ||
          !charge_node(buffer.budget, 1) {
          return @bounded.Failed(CaptureLimit, used, used)
        }
        state.cells = []
        state.column = 0
        state.phase = if width == 0 { CommitRow } else { ReadCell }
      }
      ReadCell => {
        guard (state.read)(state.row, state.column) is Some(value) else {
          return @bounded.Failed(InvalidCheckedRow, used, used)
        }
        if !buffer.open {
          return @bounded.Failed(ClosedCapture, used, used)
        }
        let field = @schema.field_at(buffer.schema, state.column).unwrap()
        guard @admitted.start_recheck_runtime_value(value, field.contract, {
            max_nodes: buffer.budget.limits.max_nodes - buffer.budget.nodes,
            max_depth: buffer.budget.limits.max_depth,
            max_text_bytes: buffer.budget.limits.max_text_bytes -
            buffer.budget.text,
          })
          is Some(cursor) else {
          return @bounded.Failed(InvalidCheckedRow, used, used)
        }
        state.admission = Some(cursor)
        state.phase = AdmitCell
      }
      AdmitCell => {
        match
          @admitted.advance_recheck_runtime_value(state.admission.unwrap()) {
          @admitted.RecheckContinue => continue
          @admitted.RecheckFailed =>
            return @bounded.Failed(InvalidCheckedRow, used, used)
          @admitted.RecheckComplete(checked, _, _) =>
            state.pending = Some(checked.value)
        }
        state.admission = None
        let field = @schema.field_at(buffer.schema, state.column).unwrap()
        let cursor = {
          frames: [],
          workspace: state.workspace,
          workspace_failed: false,
        }
        if !push_stepped_measure(
            cursor,
            SteppedTextNext(@schema.reference_name(field.name), 0),
          ) {
          return @bounded.Failed(CaptureLimit, used, used)
        }
        state.measure = Some(cursor)
        state.phase = MeasureName
      }
      MeasureName | MeasureValue => {
        let cursor = state.measure.unwrap()
        match advance_stepped_measure_result(cursor, buffer.budget) {
          SteppedMeasureContinue => ()
          SteppedMeasureLimit | SteppedMeasureWorkspaceLimit =>
            return @bounded.Failed(CaptureLimit, used, used)
          SteppedMeasureComplete => {
            state.measure = None
            if state.phase is MeasureName {
              guard start_stepped_measure_result(
                  Captured(state.pending.unwrap()),
                  state.workspace,
                )
                is Some(value) else {
                return @bounded.Failed(CaptureLimit, used, used)
              }
              state.measure = Some(value)
              state.phase = MeasureValue
            } else {
              state.cells.push(state.pending.unwrap())
              state.pending = None
              state.column += 1
              state.phase = if state.column == width {
                CommitRow
              } else {
                ReadCell
              }
            }
          }
        }
      }
      CommitRow => {
        buffer.rows.push(state.cells)
        state.cells = []
        state.row += 1
        state.phase = BeginRow
      }
      Seal => {
        buffer.reading = false
        match finish_admitted_output(state.output) {
          Ok(rows) => {
            state.material = Some(rows)
            return @bounded.Complete(rows, used, used)
          }
          Err(issue) => return @bounded.Failed(issue, used, used)
        }
      }
    }
  }
  @bounded.Continue(used, used)
}

///|
/// Capacity is checked before any row read or row allocation. Nested values
/// use the existing incremental admission and measurement cursors.
pub fn start_admitted_output_preparation(
  output : AdmittedOutput,
  count : Int,
  max_step_work : Int,
  max_workspace_slots : Int,
  read : (Int, Int) -> @admitted.Value?,
) -> Result[AdmittedOutputPreparation, CaptureIssue] {
  if count < 0 || max_step_work < 0 || max_workspace_slots < 0 {
    return Err(InvalidCaptureLimits)
  }
  if !output.buffer.open ||
    output.buffer.reading ||
    !output.buffer.rows.is_empty() {
    return Err(ClosedCapture)
  }
  if count > output.buffer.max_rows {
    return Err(CaptureLimit)
  }
  output.buffer.reading = true
  let state : AdmittedOutputState = {
    output,
    count,
    read,
    workspace: row_workspace(max_workspace_slots),
    max_work: max_step_work,
    work: 0,
    row: 0,
    column: 0,
    cells: [],
    pending: None,
    measure: None,
    admission: None,
    phase: BeginRow,
    material: None,
    reclaimed: false,
  }
  let control = @bounded.control()
  let (session, token) = @bounded.start(
    control,
    state,
    advance_admitted_output_state,
    discard_admitted_output_state,
    _ => discard_admitted_output_state(state),
  )
  Ok({ state, session, token, control, accepted: false, })
}

///|
pub fn advance_admitted_output_preparation(
  value : AdmittedOutputPreparation,
  quantum : Int,
) -> Result[AdmittedOutputPoll, @bounded.Issue] {
  match @bounded.advance(value.session, value.token, quantum) {
    Err(issue) => Err(issue)
    Ok(@bounded.ContinueWith(token, work~, ..)) => {
      value.token = token
      Ok(AdmittedOutputContinue(work~))
    }
    Ok(@bounded.Completed(rows, work~, ..)) => {
      value.accepted = true
      Ok(AdmittedOutputComplete(rows, work~))
    }
    Ok(@bounded.FailedWith(issue, work~, ..)) =>
      Ok(AdmittedOutputFailed(issue, work~))
    Ok(@bounded.StoppedWith(_, work~, ..)) => Ok(AdmittedOutputStopped(work~))
  }
}

///|
pub fn cancel_admitted_output_preparation(
  value : AdmittedOutputPreparation,
) -> Bool {
  @bounded.request_cancel(value.control)
}

///|
pub fn cleanup_admitted_output_preparation(
  value : AdmittedOutputPreparation,
) -> Result[Bool, @bounded.Issue] {
  if value.state.reclaimed {
    return Ok(true)
  }
  @bounded.cleanup(value.session)
}

///|
/// The common session must have accepted completion; a pending kernel value
/// rejected by cancellation is not successful material.
pub fn admitted_output_preparation_rows(
  value : AdmittedOutputPreparation,
) -> AdmittedOutputRows? {
  if value.state.reclaimed || !value.accepted {
    None
  } else {
    value.state.material
  }
}

///|
/// Transfer accepted immutable rows to the enclosing execution owner once.
/// This is material custody only, not Compute completion. Retiring this import
/// afterwards must not clear the row containers now owned by the recipient.
pub fn take_admitted_output_preparation_rows(
  value : AdmittedOutputPreparation,
) -> AdmittedOutputRows? {
  guard !value.state.reclaimed &&
    value.accepted &&
    value.state.material is Some(rows) else {
    return None
  }
  value.state.material = None
  value.state.pending = None
  value.state.cells.clear()
  release_slots(value.state.workspace, value.state.workspace.live)
  value.state.reclaimed = true
  value.accepted = false
  Some(rows)
}
