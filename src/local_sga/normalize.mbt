///|
priv enum NormalizePhase {
  CopyNodes
  CopyEdges
  Finish
}

///|
priv struct NormalizeState {
  input : @graph.ProducerRead
  source : @storage.Storage
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
  match copy_graph_node(state.source, output, state.node_fields, index) {
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
  match copy_graph_edge(state.source, output, state.edge_fields, index) {
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
    if !@graph.producer_read_available(state.input) {
      return @bounded.Failed(InputUnavailable, progress, used)
    }
    match state.phase {
      CopyNodes =>
        if state.index < @storage.node_count(state.source) {
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
        if state.index < @storage.edge_count(state.source) {
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
    input,
    source,
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
