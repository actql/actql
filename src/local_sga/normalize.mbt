///|
priv enum NormalizePhase {
  CopyNodes
  CopyEdges
  Finish
}

///|
priv struct NormalizeState {
  input : @graph.ProducerRead?
  source : @storage.Storage?
  view : @lifecycle.ProducerView?
  node_count : Int
  edge_count : Int
  mut output : @graph.OutputBuilder?
  node_fields : Int
  edge_fields : Int
  mut phase : NormalizePhase
  mut index : Int
}

///|
struct NormalizeExecution {
  session : @bounded.Session[NormalizeState, @graph.Completed, NormalizeIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
}

///|
pub enum NormalizePoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@graph.Completed, progress~ : Int64, work~ : Int64)
  Failed(NormalizeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum NormalizeIssue {
  InvalidKernel
  InvalidLimits
  InputUnavailable
  Output(@graph.Issue)
  Execution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn copy_node(
  state : NormalizeState,
  index : Int,
) -> Result[Unit, NormalizeIssue] {
  guard state.output is Some(output) else { return Err(InvalidKernel) }
  let copied = match state.view {
    Some(view) => copy_graph_view_node(view, output, state.node_fields, index)
    None =>
      match state.source {
        Some(source) =>
          copy_graph_node(source, output, state.node_fields, index)
        None => Err(Unavailable)
      }
  }
  match copied {
    Ok(_) => Ok(())
    Err(Unavailable) => Err(InputUnavailable)
    Err(GraphCopyIssue::Output(issue)) => Err(Output(issue))
  }
}

///|
fn copy_edge(
  state : NormalizeState,
  index : Int,
) -> Result[Unit, NormalizeIssue] {
  guard state.output is Some(output) else { return Err(InvalidKernel) }
  let copied = match state.view {
    Some(view) => copy_graph_view_edge(view, output, state.edge_fields, index)
    None =>
      match state.source {
        Some(source) =>
          copy_graph_edge(source, output, state.edge_fields, index)
        None => Err(Unavailable)
      }
  }
  match copied {
    Ok(_) => Ok(())
    Err(Unavailable) => Err(InputUnavailable)
    Err(GraphCopyIssue::Output(issue)) => Err(Output(issue))
  }
}

///|
fn normalize_step(
  state : NormalizeState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, NormalizeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !(match state.view {
        Some(view) =>
          @lifecycle.producer_read_reference_available(
            @lifecycle.producer_view_read_reference(view),
          )
        None => state.input.map(@graph.producer_read_available).unwrap_or(false)
      }) {
      return @bounded.Failed(InputUnavailable, progress, used)
    }
    match state.phase {
      CopyNodes =>
        if state.index < state.node_count {
          match copy_node(state, state.index) {
            Ok(_) => {
              state.index += 1
              used += 1
              progress += 1
            }
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = CopyEdges
          state.index = 0
        }
      CopyEdges =>
        if state.index < state.edge_count {
          match copy_edge(state, state.index) {
            Ok(_) => {
              state.index += 1
              used += 1
              progress += 1
            }
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          state.phase = Finish
        }
      Finish => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidKernel, progress, used)
        }
        state.output = None
        return match @graph.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(Output(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_state(state : NormalizeState) -> Bool {
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  true
}

///|
pub fn start_normalize(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[NormalizeExecution, NormalizeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.GraphBasicStep(_)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "SGA.normalize" &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidKernel)
  }
  guard @graph.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.GraphValue(contract) else {
    return Err(InputUnavailable)
  }
  if limits.max_value_nodes < 1 || limits.max_value_nodes > (2147483647 - 1) / 4 {
    return Err(InvalidLimits)
  }
  let output = match
    @graph.prepare_output(
      owner,
      @pipeline.Step(step),
      @storage.mode(source),
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  let max_noninterruptible_value_nodes = limits.max_value_nodes * 4 + 1
  let state : NormalizeState = {
    input: Some(input),
    source: Some(source),
    view: None,
    node_count: @storage.node_count(source),
    edge_count: @storage.edge_count(source),
    output: Some(output),
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    phase: CopyNodes,
    index: 0,
  }
  let (session, token) = @bounded.start(
    control, state, normalize_step, cleanup_state, @graph.discard_completed,
  )
  Ok({ session, token: Some(token), max_noninterruptible_value_nodes, })
}

///|
/// Execute the same normalization against an exact immutable managed view.
pub fn start_normalize_view(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[NormalizeExecution, NormalizeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step) is Some(@lower.GraphBasicStep(_)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "SGA.normalize" &&
    @lower.node_input_target(node, 0) is Some(target) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
    is Some(@carrier.GraphValue(contract)) &&
    @lifecycle.producer_view_kind(input) == @carrier.GraphKind &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_view_node_count(input) is Some(node_count) &&
    @lifecycle.producer_view_edge_count(input) is Some(edge_count) else {
    return Err(InvalidKernel)
  }
  if limits.max_value_nodes < 1 || limits.max_value_nodes > (2147483647 - 1) / 4 {
    return Err(InvalidLimits)
  }
  let output = match
    @graph.prepare_output(
      owner,
      @pipeline.Step(step),
      @storage.DeclaredNodes,
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Output(issue))
  }
  let state : NormalizeState = {
    input: None,
    source: None,
    view: Some(input),
    node_count,
    edge_count,
    output: Some(output),
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    phase: CopyNodes,
    index: 0,
  }
  let (session, token) = @bounded.start(
    control, state, normalize_step, cleanup_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes * 4 + 1,
  })
}

///|
pub fn normalize_max_noninterruptible_value_nodes(
  value : NormalizeExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn advance_normalize(
  value : NormalizeExecution,
  quantum : Int,
) -> Result[NormalizePoll, NormalizeIssue] {
  guard value.token is Some(token) else {
    return Err(Execution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(Execution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn normalize_stopped(value : NormalizeExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn normalize_cleanup_pending(value : NormalizeExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_normalize(
  value : NormalizeExecution,
) -> Result[Bool, NormalizeIssue] {
  @bounded.cleanup(value.session).map_err(issue => Execution(issue))
}
