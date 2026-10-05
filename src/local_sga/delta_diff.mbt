///|
priv enum DeltaDiffPhase {
  GeneratingDelta
  StartingDeltaRows
  ImportingDeltaRows
  CompletingDeltaRows
}

///|
priv struct DeltaDiffState {
  left : @lifecycle.ProducerView
  right : @lifecycle.ProducerView
  kernel : @delta.Preparation
  mut output : @execution.AdmittedOutput?
  port : @execution.TrustedOutputPort[Unit]
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  workspace : Int
  mut phase : DeltaDiffPhase
  mut remaining : Int
  mut value : @value.CheckedValue?
  mut importing : @execution.AdmittedOutputPreparation?
  mut import_work : Int64
}

///|
struct DeltaDiffExecution {
  session : @bounded.Session[
    DeltaDiffState,
    @execution.CompletedOutput,
    DeltaDiffIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub(all) enum DeltaDiffIssue {
  InvalidDeltaDiffKernel
  DeltaDiffInputUnavailable
  DeltaDiffWorkLimit
  DeltaDiffKernel(@delta.Issue)
  DeltaDiffOutput(@execution.CaptureIssue)
  DeltaDiffCompletion(@execution.TrustedOutputIssue)
  DeltaDiffExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
pub enum DeltaDiffPoll {
  DeltaDiffContinue(progress~ : Int64, work~ : Int64)
  DeltaDiffComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  DeltaDiffFailed(DeltaDiffIssue, progress~ : Int64, work~ : Int64)
  DeltaDiffStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
fn delta_diff_step(
  state : DeltaDiffState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, DeltaDiffIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  if !graph_read_available(Viewed(state.left)) ||
    !graph_read_available(Viewed(state.right)) {
    return @bounded.Failed(DeltaDiffInputUnavailable, 0, 0)
  }
  if state.remaining < 1 {
    return @bounded.Failed(DeltaDiffWorkLimit, 0, 0)
  }
  let budget = Int::min(quantum, state.remaining)
  match state.phase {
    GeneratingDelta => {
      guard state.output is Some(output) else {
        return @bounded.Failed(InvalidDeltaDiffKernel, 0, 0)
      }
      let poll = match @delta.advance(state.kernel, budget) {
        Ok(poll) => poll
        Err(issue) => return @bounded.Failed(DeltaDiffKernel(issue), 0, 0)
      }
      let (progress, work) = match poll {
        @delta.Continue(progress~, work~)
        | @delta.Complete(_, progress~, work~)
        | @delta.Failed(_, progress~, work~) => (progress, work)
      }
      if poll is @delta.Complete(result, ..) {
        state.value = Some(@delta.value(result))
        @delta.cleanup(state.kernel) |> ignore
        state.phase = StartingDeltaRows
      }
      if work < 0L ||
        work > budget.to_int64() ||
        progress < 0L ||
        progress > work ||
        (poll is @delta.Continue(..) && work == 0L) {
        return @bounded.Failed(InvalidDeltaDiffKernel, 0, 0)
      }
      state.remaining -= work.to_int()
      if !@execution.admitted_output_charge_control_work(output, work.to_int()) {
        return @bounded.Failed(
          DeltaDiffWorkLimit,
          progress.to_int(),
          work.to_int(),
        )
      }
      match poll {
        @delta.Failed(issue, ..) =>
          @bounded.Failed(
            DeltaDiffKernel(issue),
            progress.to_int(),
            work.to_int(),
          )
        _ => @bounded.Continue(progress.to_int(), work.to_int())
      }
    }
    StartingDeltaRows => {
      state.remaining -= 1
      guard state.value is Some(value) &&
        state.output is Some(output) &&
        @execution.admitted_output_charge_control_work(output, 1) else {
        return @bounded.Failed(DeltaDiffWorkLimit, 0, 1)
      }
      match
        @execution.start_admitted_output_preparation(
          output,
          1,
          state.remaining,
          state.workspace,
          (row, column) => {
            if row == 0 && column == 0 {
              Some(value.value)
            } else {
              None
            }
          },
        ) {
        Err(issue) => @bounded.Failed(DeltaDiffOutput(issue), 0, 1)
        Ok(active) => {
          state.importing = Some(active)
          state.output = None
          state.phase = ImportingDeltaRows
          @bounded.Continue(0, 1)
        }
      }
    }
    ImportingDeltaRows => {
      guard state.importing is Some(active) else {
        return @bounded.Failed(InvalidDeltaDiffKernel, 0, 0)
      }
      let poll = match
        @execution.advance_admitted_output_preparation(active, budget) {
        Ok(poll) => poll
        Err(issue) =>
          return @bounded.Failed(DeltaDiffExecutionIssue(issue), 0, 0)
      }
      let total = match poll {
        @execution.AdmittedOutputContinue(work~)
        | @execution.AdmittedOutputComplete(_, work~)
        | @execution.AdmittedOutputFailed(_, work~)
        | @execution.AdmittedOutputStopped(work~) => work
      }
      let work = total - state.import_work
      if work < 0L ||
        work > budget.to_int64() ||
        (poll is @execution.AdmittedOutputContinue(..) && work == 0L) {
        return @bounded.Failed(InvalidDeltaDiffKernel, 0, 0)
      }
      state.import_work = total
      state.remaining -= work.to_int()
      match poll {
        @execution.AdmittedOutputContinue(..) =>
          @bounded.Continue(0, work.to_int())
        @execution.AdmittedOutputFailed(issue, ..) =>
          @bounded.Failed(DeltaDiffOutput(issue), 0, work.to_int())
        @execution.AdmittedOutputStopped(..) =>
          @bounded.Failed(InvalidDeltaDiffKernel, 0, work.to_int())
        @execution.AdmittedOutputComplete(_, ..) => {
          guard @execution.take_admitted_output_preparation_rows(active)
            is Some(rows) else {
            return @bounded.Failed(InvalidDeltaDiffKernel, 0, work.to_int())
          }
          state.rows.val = Some(rows)
          state.importing = None
          state.value = None
          @delta.cleanup(state.kernel) |> ignore
          state.phase = CompletingDeltaRows
          @bounded.Continue(1, work.to_int())
        }
      }
    }
    CompletingDeltaRows => {
      state.remaining -= 1
      match @execution.complete_trusted_output(state.port, ()) {
        Ok(output) => @bounded.Complete(output, 0, 1)
        Err(issue) => @bounded.Failed(DeltaDiffCompletion(issue), 0, 1)
      }
    }
  }
}

///|
fn cleanup_delta_diff_state(state : DeltaDiffState) -> Bool {
  @delta.cleanup(state.kernel) |> ignore
  if state.importing is Some(active) {
    @execution.cancel_admitted_output_preparation(active) |> ignore
    // Establish stopping before cleanup even when the outer control stopped
    // between two import polls. No new value read occurs after cancellation.
    @execution.advance_admitted_output_preparation(active, 1) |> ignore
    if @execution.cleanup_admitted_output_preparation(active) is Err(_) {
      return false
    }
    state.importing = None
  }
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.value = None
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
pub fn start_delta_diff_views(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  left : @lifecycle.ProducerView,
  right : @lifecycle.ProducerView,
  max_rows : Int,
  values : @execution.ValueLimits,
  limits : @delta.Limits,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit : Int,
) -> Result[DeltaDiffExecution, DeltaDiffIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step) is Some(@lower.GraphDeltaStep(delta)) &&
    @graph_type.delta_operation(@lower.graph_delta_checked(delta))
    is @graph_type.Difference &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) &&
    @schema.field_count(schema) == 1 &&
    @schema.field_at(schema, 0) is Some(field) &&
    field.name == @schema.Unqualified("delta") &&
    @lifecycle.producer_view_kind(left) == @carrier.GraphKind &&
    @lifecycle.producer_view_kind(right) == @carrier.GraphKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(left),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(right),
      owner,
      step,
      1,
    ) else {
    return Err(InvalidDeltaDiffKernel)
  }
  if control_work_limit < 0 {
    return Err(DeltaDiffWorkLimit)
  }
  let graph = @graph_type.delta_graph(@lower.graph_delta_checked(delta))
  let kernel = match
    @delta.prepare_view(
      left,
      @graph_contract.graph(graph),
      right,
      @graph_contract.graph(graph),
      field.contract,
      @graph_contract.cid(graph),
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(DeltaDiffKernel(issue))
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      values,
    ) {
    Ok(value) => value
    Err(issue) => {
      @delta.cleanup(kernel) |> ignore
      return Err(DeltaDiffOutput(issue))
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
      inputs=[
        @execution.trusted_output_carrier_input(
          @lifecycle.producer_view_read_reference(left),
        ),
        @execution.trusted_output_carrier_input(
          @lifecycle.producer_view_read_reference(right),
        ),
      ],
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      @delta.cleanup(kernel) |> ignore
      return Err(DeltaDiffCompletion(issue))
    }
  }
  let state : DeltaDiffState = {
    left,
    right,
    kernel,
    output: Some(output),
    port,
    rows,
    live,
    accepted,
    workspace: limits.max_workspace_slots,
    phase: GeneratingDelta,
    remaining: Int::min(control_work_limit, values.max_work),
    value: None,
    importing: None,
    import_work: 0L,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    delta_diff_step,
    cleanup_delta_diff_state,
    _ => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_delta_diff(
  value : DeltaDiffExecution,
  quantum : Int,
) -> Result[DeltaDiffPoll, DeltaDiffIssue] {
  guard value.token is Some(token) else {
    return Err(DeltaDiffExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(DeltaDiffExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(DeltaDiffContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(DeltaDiffComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(DeltaDiffFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(DeltaDiffStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn delta_diff_cleanup_pending(value : DeltaDiffExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_delta_diff(
  value : DeltaDiffExecution,
) -> Result[Bool, DeltaDiffIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    DeltaDiffExecutionIssue(issue)
  })
}
