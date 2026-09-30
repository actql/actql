///|
priv enum GraphDiffPhase {
  Kernel
  Emit
  Finish
}

///|
priv struct GraphDiffState {
  left : GraphReadSource
  right : GraphReadSource
  core : @diff.Preparation
  mut phase : GraphDiffPhase
  mut pending : @value.CheckedValue?
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut remaining_work : Int
}

///|
struct GraphDiffExecution {
  session : @bounded.Session[
    GraphDiffState,
    @execution.CompletedOutput,
    GraphDiffIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum GraphDiffPoll {
  GraphDiffContinue(progress~ : Int64, work~ : Int64)
  GraphDiffComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  GraphDiffFailed(GraphDiffIssue, progress~ : Int64, work~ : Int64)
  GraphDiffStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum GraphDiffIssue {
  InvalidGraphDiffKernel
  GraphDiffInputUnavailable
  GraphDiffWorkLimit
  GraphDiffCore(@diff.Issue)
  GraphDiffOutput(@execution.CaptureIssue)
  GraphDiffCompletion(@execution.TrustedOutputIssue)
  GraphDiffExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
pub fn graph_diff_max_noninterruptible_value_nodes(
  value : GraphDiffExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn graph_diff_max_noninterruptible_value_bytes(
  value : GraphDiffExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
fn graph_diff_step(
  state : GraphDiffState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, GraphDiffIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graph_read_available(state.left) || !graph_read_available(state.right) {
      return @bounded.Failed(GraphDiffInputUnavailable, progress, used)
    }
    match state.phase {
      Kernel => {
        if state.remaining_work < 1 {
          return @bounded.Failed(GraphDiffWorkLimit, progress, used)
        }
        let permitted = Int::min(quantum - used, state.remaining_work)
        match @diff.advance(state.core, permitted) {
          Err(issue) =>
            return @bounded.Failed(GraphDiffCore(issue), progress, used)
          Ok(@diff.Continue(progress=made, work~)) => {
            let actual = work.to_int()
            state.remaining_work -= actual
            used += actual
            progress += made.to_int()
          }
          Ok(@diff.Failed(issue, progress=made, work~)) => {
            let actual = work.to_int()
            state.remaining_work -= actual
            used += actual
            progress += made.to_int()
            return @bounded.Failed(GraphDiffCore(issue), progress, used)
          }
          Ok(@diff.Complete(delta, progress=made, work~)) => {
            let actual = work.to_int()
            state.remaining_work -= actual
            used += actual
            progress += made.to_int()
            state.pending = Some(@diff.value(delta))
            state.phase = Emit
          }
        }
      }
      Emit => {
        if state.remaining_work < 1 {
          return @bounded.Failed(GraphDiffWorkLimit, progress, used)
        }
        state.remaining_work -= 1
        used += 1
        guard state.output is Some(output) && state.pending is Some(delta) else {
          return @bounded.Failed(InvalidGraphDiffKernel, progress, used)
        }
        match @execution.append_admitted_output(output, [delta]) {
          Ok(_) => {
            state.pending = None
            state.phase = Finish
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(GraphDiffOutput(issue), progress, used)
        }
      }
      Finish => {
        if state.remaining_work < 1 {
          return @bounded.Failed(GraphDiffWorkLimit, progress, used)
        }
        state.remaining_work -= 1
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphDiffKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(rows) => rows
          Err(issue) =>
            return @bounded.Failed(GraphDiffOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(GraphDiffCompletion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_graph_diff_state(state : GraphDiffState) -> Bool {
  @diff.cleanup(state.core) |> ignore
  state.pending = None
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
pub fn start_graph_diff(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  left_read : @graph.ProducerRead,
  right_read : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[GraphDiffExecution, GraphDiffIssue] {
  if limits.max_work < 0 {
    return Err(GraphDiffWorkLimit)
  }
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphRelationStep(prepared)) &&
    @lower.graph_relation_kind(prepared) == @lower.GraphDiffRelation &&
    @lower.graph_relation_diff_contract(prepared) is Some(delta_contract) &&
    @lower.graph_relation_graph_contract_cid(prepared)
    is Some(graph_contract_cid) &&
    @graph.producer_read_matches_operation_input(left_read, owner, step, 0) &&
    @graph.producer_read_matches_operation_input(right_read, owner, step, 1) &&
    @graph.producer_read_storage(left_read) is Some(left) &&
    @graph.producer_read_storage(right_read) is Some(right) else {
    return Err(InvalidGraphDiffKernel)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(output) => output
    Err(issue) => return Err(GraphDiffOutput(issue))
  }
  let core = match
    @diff.prepare(left, right, delta_contract, graph_contract_cid, {
      max_workspace_slots,
      max_output_nodes: limits.max_nodes,
      max_output_text_bytes: limits.max_text_bytes,
      max_output_depth: limits.max_depth,
      max_identity_bytes: limits.max_text_bytes,
      max_identity_nodes: limits.max_nodes,
      max_identity_depth: limits.max_depth,
      value_limits: {
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_text_bytes: limits.max_text_bytes,
      },
    }) {
    Ok(core) => core
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(GraphDiffCore(issue))
    }
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let port = match
    @execution.prepare_trusted_output_port(
      preparation,
      @pipeline.Step(step),
      max_entries,
      max_name_bytes,
      fn(_) { if live.val { rows.val } else { None } },
      inputs~,
    ) {
    Ok(port) => port
    Err(issue) => {
      @diff.cleanup(core) |> ignore
      @execution.cancel_admitted_output(output) |> ignore
      return Err(GraphDiffCompletion(issue))
    }
  }
  let state : GraphDiffState = {
    left: Stored(left_read),
    right: Stored(right_read),
    core,
    phase: Kernel,
    pending: None,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    remaining_work: limits.max_work,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    graph_diff_step,
    cleanup_graph_diff_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({
    session,
    token: Some(token),
    accepted,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
/// Execute the same bounded diff kernel over two exact retained Graph reads.
pub fn start_graph_diff_view(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  left : @lifecycle.ProducerView,
  right : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[GraphDiffExecution, GraphDiffIssue] {
  if limits.max_work < 0 {
    return Err(GraphDiffWorkLimit)
  }
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphRelationStep(prepared)) &&
    @lower.graph_relation_kind(prepared) == @lower.GraphDiffRelation &&
    @lower.graph_relation_diff_contract(prepared) is Some(delta_contract) &&
    @lower.graph_relation_graph_contract_cid(prepared)
    is Some(graph_contract_cid) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_input_count(node) == 2 &&
    @lower.node_input_target(node, 0) is Some(left_target) &&
    @lower.node_input_target(node, 1) is Some(right_target) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), left_target)
    is Some(@carrier.GraphValue(left_graph)) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), right_target)
    is Some(@carrier.GraphValue(right_graph)) &&
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
    return Err(InvalidGraphDiffKernel)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(output) => output
    Err(issue) => return Err(GraphDiffOutput(issue))
  }
  let core = match
    @diff.prepare_view(
      left,
      left_graph,
      right,
      right_graph,
      delta_contract,
      graph_contract_cid,
      {
        max_workspace_slots,
        max_output_nodes: limits.max_nodes,
        max_output_text_bytes: limits.max_text_bytes,
        max_output_depth: limits.max_depth,
        max_identity_bytes: limits.max_text_bytes,
        max_identity_nodes: limits.max_nodes,
        max_identity_depth: limits.max_depth,
        value_limits: {
          max_nodes: limits.max_nodes,
          max_depth: limits.max_depth,
          max_text_bytes: limits.max_text_bytes,
        },
      },
    ) {
    Ok(core) => core
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(GraphDiffCore(issue))
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
    Ok(port) => port
    Err(issue) => {
      @diff.cleanup(core) |> ignore
      @execution.cancel_admitted_output(output) |> ignore
      return Err(GraphDiffCompletion(issue))
    }
  }
  let state : GraphDiffState = {
    left: Viewed(left),
    right: Viewed(right),
    core,
    phase: Kernel,
    pending: None,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    remaining_work: limits.max_work,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    graph_diff_step,
    cleanup_graph_diff_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({
    session,
    token: Some(token),
    accepted,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
pub fn advance_graph_diff(
  value : GraphDiffExecution,
  quantum : Int,
) -> Result[GraphDiffPoll, GraphDiffIssue] {
  guard value.token is Some(token) else {
    return Err(GraphDiffExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraphDiffExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(GraphDiffContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(GraphDiffComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(GraphDiffFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(GraphDiffStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn graph_diff_stopped(value : GraphDiffExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn graph_diff_cleanup_pending(value : GraphDiffExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_graph_diff(
  value : GraphDiffExecution,
) -> Result[Bool, GraphDiffIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    GraphDiffExecutionIssue(issue)
  })
}
