///|
priv enum GraftPhase {
  CopyNodes
  CopyEdges
  Finish
}

///|
priv struct GraftState {
  inputs : Array[@graph.ProducerRead]
  sources : Array[@storage.Storage]
  mut output : @graph.OutputBuilder?
  node_fields : Int
  edge_fields : Int
  mut input_index : Int
  mut phase : GraftPhase
  mut record_index : Int
}

///|
struct GraftExecution {
  session : @bounded.Session[GraftState, @graph.Completed, GraftIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
}

///|
pub enum GraftPoll {
  GraftContinue(progress~ : Int64, work~ : Int64)
  GraftComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  GraftFailed(GraftIssue, progress~ : Int64, work~ : Int64)
  GraftStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum GraftIssue {
  InvalidGraftKernel
  InvalidGraftLimits
  GraftInputUnavailable
  GraftOutput(@graph.Issue)
  GraftExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn graft_source(state : GraftState) -> @storage.Storage? {
  state.sources.get(state.input_index)
}

///|
fn graft_inputs_available(state : GraftState) -> Bool {
  for input in state.inputs {
    if !@graph.producer_read_available(input) {
      return false
    }
  }
  true
}

///|
fn advance_graft_source(state : GraftState) -> Unit {
  state.input_index += 1
  state.phase = CopyNodes
  state.record_index = 0
  if state.input_index >= state.sources.length() {
    state.phase = Finish
  }
}

///|
fn graft_step(
  state : GraftState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, GraftIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graft_inputs_available(state) {
      return @bounded.Failed(GraftInputUnavailable, progress, used)
    }
    match state.phase {
      CopyNodes => {
        guard graft_source(state) is Some(source) else {
          return @bounded.Failed(InvalidGraftKernel, progress, used)
        }
        if state.record_index < @storage.node_count(source) {
          guard state.output is Some(output) else {
            return @bounded.Failed(InvalidGraftKernel, progress, used)
          }
          match
            copy_graph_node(
              source,
              output,
              state.node_fields,
              state.record_index,
            ) {
            Ok(_) => {
              state.record_index += 1
              used += 1
              progress += 1
            }
            Err(Unavailable) =>
              return @bounded.Failed(GraftInputUnavailable, progress, used)
            Err(GraphCopyIssue::Output(issue)) =>
              return @bounded.Failed(GraftOutput(issue), progress, used)
          }
        } else {
          state.phase = CopyEdges
          state.record_index = 0
        }
      }
      CopyEdges => {
        guard graft_source(state) is Some(source) else {
          return @bounded.Failed(InvalidGraftKernel, progress, used)
        }
        if state.record_index < @storage.edge_count(source) {
          guard state.output is Some(output) else {
            return @bounded.Failed(InvalidGraftKernel, progress, used)
          }
          match
            copy_graph_edge(
              source,
              output,
              state.edge_fields,
              state.record_index,
            ) {
            Ok(_) => {
              state.record_index += 1
              used += 1
              progress += 1
            }
            Err(Unavailable) =>
              return @bounded.Failed(GraftInputUnavailable, progress, used)
            Err(GraphCopyIssue::Output(issue)) =>
              return @bounded.Failed(GraftOutput(issue), progress, used)
          }
        } else {
          advance_graft_source(state)
        }
      }
      Finish => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraftKernel, progress, used)
        }
        state.output = None
        return match @graph.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(GraftOutput(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_graft_state(state : GraftState) -> Bool {
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  true
}

///|
pub fn start_graft(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@graph.ProducerRead],
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[GraftExecution, GraftIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphStructuralStep(_)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "SGA.graft" &&
    inputs.length() == 2 else {
    return Err(InvalidGraftKernel)
  }
  let sources = []
  for index, input in inputs {
    guard @graph.producer_read_matches_operation_input(
        input, owner, step, index,
      ) &&
      @graph.producer_read_storage(input) is Some(source) else {
      return Err(GraftInputUnavailable)
    }
    sources.push(source)
  }
  guard @storage.carrier(sources[0]) is @carrier.GraphValue(contract) else {
    return Err(GraftInputUnavailable)
  }
  if limits.max_value_nodes < 1 || limits.max_value_nodes > (2147483647 - 1) / 4 {
    return Err(InvalidGraftLimits)
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
    Err(issue) => return Err(GraftOutput(issue))
  }
  let state : GraftState = {
    inputs: inputs.copy(),
    sources,
    output: Some(output),
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    input_index: 0,
    phase: CopyNodes,
    record_index: 0,
  }
  let (session, token) = @bounded.start(
    control, state, graft_step, cleanup_graft_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes * 4 + 1,
  })
}

///|
pub fn graft_max_noninterruptible_value_nodes(value : GraftExecution) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn advance_graft(
  value : GraftExecution,
  quantum : Int,
) -> Result[GraftPoll, GraftIssue] {
  guard value.token is Some(token) else {
    return Err(GraftExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraftExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(GraftContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(GraftComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(GraftFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(GraftStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn graft_stopped(value : GraftExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn graft_cleanup_pending(value : GraftExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_graft(value : GraftExecution) -> Result[Bool, GraftIssue] {
  @bounded.cleanup(value.session).map_err(issue => GraftExecutionIssue(issue))
}
