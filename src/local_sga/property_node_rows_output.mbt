///|
priv enum PropertyNodeRowsOutputPhase {
  ReadNodeRow
  AppendNodeRow
  AcknowledgeNodeRow
  FinishNodeRows
}

///|
priv struct PropertyNodeRowsOutputState {
  cursor : PropertyNodeRowsExecution
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : PropertyNodeRowsOutputPhase
  mut pending : @execution.ConditionalRow?
  mut control_work_remaining : Int
}

///|
struct PropertyNodeRowsOutputExecution {
  session : @bounded.Session[
    PropertyNodeRowsOutputState,
    @execution.CompletedOutput,
    PropertyNodeRowsOutputIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum PropertyNodeRowsOutputPoll {
  NodeRowsOutputContinue(progress~ : Int64, work~ : Int64)
  NodeRowsOutputComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  NodeRowsOutputFailed(
    PropertyNodeRowsOutputIssue,
    progress~ : Int64,
    work~ : Int64
  )
  NodeRowsOutputStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum PropertyNodeRowsOutputIssue {
  InvalidNodeRowsOutput
  NodeRowsOutputInput(PropertyNodeRowsIssue)
  NodeRowsOutputCapture(@execution.CaptureIssue)
  NodeRowsOutputCompletion(@execution.TrustedOutputIssue)
  NodeRowsOutputWorkLimit
  NodeRowsOutputExecution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn property_node_rows_output_step(
  state : PropertyNodeRowsOutputState,
  quantum : Int,
  _reader : @bounded.Reader,
) -> @bounded.KernelStep[
  @execution.CompletedOutput,
  PropertyNodeRowsOutputIssue,
] {
  if state.control_work_remaining == 0 {
    return @bounded.Failed(NodeRowsOutputWorkLimit, 0, 0)
  }
  let mut spent = 1
  match state.phase {
    ReadNodeRow => {
      let available = Int::min(quantum, state.control_work_remaining)
      let polled = match advance_property_node_rows(state.cursor, available) {
        Ok(value) => value
        Err(issue) => return @bounded.Failed(NodeRowsOutputInput(issue), 0, 0)
      }
      let reported = match polled {
        PropertyNodeRowsContinue(work~)
        | PropertyNodeRowsRow(_, work~)
        | PropertyNodeRowsComplete(work~)
        | PropertyNodeRowsFailed(_, work~)
        | PropertyNodeRowsStopped(work~) => work
      }
      if reported < 0L || reported > available.to_int64() {
        return @bounded.Failed(NodeRowsOutputWorkLimit, 0, 0)
      }
      spent = Int::max(reported.to_int(), 1)
      state.control_work_remaining -= spent
      match polled {
        PropertyNodeRowsContinue(..) => @bounded.Continue(1, spent)
        PropertyNodeRowsRow(row, ..) => {
          state.pending = Some(row)
          state.phase = AppendNodeRow
          @bounded.Continue(1, spent)
        }
        PropertyNodeRowsComplete(..) => {
          state.phase = FinishNodeRows
          @bounded.Continue(1, spent)
        }
        PropertyNodeRowsFailed(issue, ..) =>
          @bounded.Failed(NodeRowsOutputInput(issue), 0, spent)
        PropertyNodeRowsStopped(..) =>
          @bounded.Failed(NodeRowsOutputInput(Closed), 0, spent)
      }
    }
    AppendNodeRow => {
      state.control_work_remaining -= 1
      guard state.output is Some(output) && state.pending is Some(row) else {
        return @bounded.Failed(InvalidNodeRowsOutput, 0, 1)
      }
      match
        @execution.append_admitted_output_presence(
          output,
          @execution.conditional_relation_row(row),
        ) {
        Ok(_) => {
          state.phase = AcknowledgeNodeRow
          @bounded.Continue(1, 1)
        }
        Err(issue) => @bounded.Failed(NodeRowsOutputCapture(issue), 0, 1)
      }
    }
    AcknowledgeNodeRow => {
      state.control_work_remaining -= 1
      guard state.pending is Some(row) else {
        return @bounded.Failed(InvalidNodeRowsOutput, 0, 1)
      }
      match acknowledge_property_node_rows_row(state.cursor, row) {
        Ok(true) => {
          state.pending = None
          state.phase = ReadNodeRow
          @bounded.Continue(1, 1)
        }
        Ok(false) => @bounded.Continue(1, 1)
        Err(issue) => @bounded.Failed(NodeRowsOutputInput(issue), 0, 1)
      }
    }
    FinishNodeRows => {
      state.control_work_remaining -= 1
      guard state.output is Some(output) else {
        return @bounded.Failed(InvalidNodeRowsOutput, 0, 1)
      }
      state.output = None
      let rows = match @execution.finish_admitted_output(output) {
        Ok(value) => value
        Err(issue) => return @bounded.Failed(NodeRowsOutputCapture(issue), 0, 1)
      }
      state.rows.val = Some(rows)
      match @execution.complete_trusted_output(state.port, ()) {
        Ok(value) => @bounded.Complete(value, 1, 1)
        Err(issue) => @bounded.Failed(NodeRowsOutputCompletion(issue), 0, 1)
      }
    }
  }
}

///|
fn cleanup_property_node_rows_output_state(
  state : PropertyNodeRowsOutputState,
) -> Bool {
  cancel_property_node_rows(state.cursor) |> ignore
  // The cursor is synchronous. A cleanup retry can drain its bounded child
  // without releasing the acquired Graph before the child stops.
  match advance_property_node_rows(state.cursor, 1) {
    Ok(PropertyNodeRowsStopped(..))
    | Ok(PropertyNodeRowsComplete(..))
    | Ok(PropertyNodeRowsFailed(_, ..))
    | Err(Closed) => ()
    _ => return false
  }
  match cleanup_property_node_rows(state.cursor) {
    Ok(true) => ()
    _ => return false
  }
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.pending = None
  true
}

///|
fn discard_unstarted_property_node_rows_cursor(
  cursor : PropertyNodeRowsExecution,
) -> Unit {
  cancel_property_node_rows(cursor) |> ignore
  advance_property_node_rows(cursor, 1) |> ignore
  cleanup_property_node_rows(cursor) |> ignore
}

///|
fn start_property_node_rows_output_read(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  cursor : PropertyNodeRowsExecution,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.TrustedOutputInput],
) -> Result[PropertyNodeRowsOutputExecution, PropertyNodeRowsOutputIssue] {
  let owner = @lower.sequence_owner(sequence)
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => {
      discard_unstarted_property_node_rows_cursor(cursor)
      return Err(NodeRowsOutputCapture(issue))
    }
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    @execution.prepare_trusted_output_port_with_inputs(
      preparation,
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs~,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      discard_unstarted_property_node_rows_cursor(cursor)
      return Err(NodeRowsOutputCompletion(issue))
    }
  }
  let state : PropertyNodeRowsOutputState = {
    cursor,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: ReadNodeRow,
    pending: None,
    control_work_remaining: limits.max_work,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    property_node_rows_output_step,
    cleanup_property_node_rows_output_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn start_property_node_rows_output_view(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  plan : @projection.CheckedPropertyNodeRows,
  view : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[PropertyNodeRowsOutputExecution, PropertyNodeRowsOutputIssue] {
  let owner = @lower.sequence_owner(sequence)
  let cursor = match
    start_property_node_rows_view(
      plan,
      owner,
      step,
      view,
      max_rows,
      limits,
      limits.max_work,
      max_workspace_slots,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NodeRowsOutputInput(issue))
  }
  start_property_node_rows_output_read(
    control,
    preparation,
    sequence,
    step,
    cursor,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    [
      @execution.trusted_output_carrier_input(
        @lifecycle.producer_view_read_reference(view),
      ),
    ],
  )
}

///|
/// A fused Graph constructor can hand its private completed Graph to this
/// projection while the original Relation inputs remain exact task inputs.
pub fn start_property_node_rows_output_stored(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  plan : @projection.CheckedPropertyNodeRows,
  read : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[PropertyNodeRowsOutputExecution, PropertyNodeRowsOutputIssue] {
  let owner = @lower.sequence_owner(sequence)
  let cursor = match
    start_property_node_rows_stored(
      plan,
      owner,
      step,
      read,
      max_rows,
      limits,
      limits.max_work,
      max_workspace_slots,
    ) {
    Ok(value) => value
    Err(issue) => return Err(NodeRowsOutputInput(issue))
  }
  start_property_node_rows_output_read(
    control,
    preparation,
    sequence,
    step,
    cursor,
    max_rows,
    limits,
    max_entries,
    max_name_bytes,
    inputs.map(@execution.trusted_output_relation_input),
  )
}

///|
pub fn advance_property_node_rows_output(
  value : PropertyNodeRowsOutputExecution,
  quantum : Int,
) -> Result[PropertyNodeRowsOutputPoll, PropertyNodeRowsOutputIssue] {
  guard value.token is Some(token) else {
    return Err(NodeRowsOutputExecution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(NodeRowsOutputExecution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(NodeRowsOutputContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(NodeRowsOutputComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(NodeRowsOutputFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(NodeRowsOutputStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn property_node_rows_output_cleanup_pending(
  value : PropertyNodeRowsOutputExecution,
) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_property_node_rows_output(
  value : PropertyNodeRowsOutputExecution,
) -> Result[Bool, PropertyNodeRowsOutputIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    NodeRowsOutputExecution(issue)
  })
}
