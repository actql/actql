///|
priv enum SubgraphPhase {
  InitializeSelection
  BeginNode
  CompareNodeIdentity
  CopyEdges
  FinishSubgraph
}

///|
priv struct SubgraphState {
  input : @graph.ProducerRead
  source : @storage.Storage
  prepared : @lower.PreparedGraphSubgraph
  mut output : @graph.OutputBuilder?
  selected : Array[Bool]
  node_fields : Int
  edge_fields : Int
  mut phase : SubgraphPhase
  mut node : Int
  mut selector : Int
  mut edge : Int
}

///|
struct SubgraphExecution {
  session : @bounded.Session[SubgraphState, @graph.Completed, SubgraphIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
}

///|
pub enum SubgraphPoll {
  SubgraphContinue(progress~ : Int64, work~ : Int64)
  SubgraphComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  SubgraphFailed(SubgraphIssue, progress~ : Int64, work~ : Int64)
  SubgraphStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum SubgraphIssue {
  InvalidSubgraphKernel
  InvalidSubgraphLimits
  SubgraphInputUnavailable
  SubgraphKeyOrder(@value.KeyOrderIssue)
  SubgraphOutput(@graph.Issue)
  SubgraphExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn copy_subgraph_node(
  state : SubgraphState,
  index : Int,
) -> Result[Unit, SubgraphIssue] {
  guard state.output is Some(output) else { return Err(InvalidSubgraphKernel) }
  match copy_graph_node(state.source, output, state.node_fields, index) {
    Ok(_) => Ok(())
    Err(Unavailable) => Err(SubgraphInputUnavailable)
    Err(GraphCopyIssue::Output(issue)) => Err(SubgraphOutput(issue))
  }
}

///|
fn copy_subgraph_edge(
  state : SubgraphState,
  index : Int,
) -> Result[Unit, SubgraphIssue] {
  guard state.output is Some(output) else { return Err(InvalidSubgraphKernel) }
  match copy_graph_edge(state.source, output, state.edge_fields, index) {
    Ok(_) => Ok(())
    Err(Unavailable) => Err(SubgraphInputUnavailable)
    Err(GraphCopyIssue::Output(issue)) => Err(SubgraphOutput(issue))
  }
}

///|
fn subgraph_step(
  state : SubgraphState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, SubgraphIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@graph.producer_read_available(state.input) {
      return @bounded.Failed(SubgraphInputUnavailable, progress, used)
    }
    match state.phase {
      InitializeSelection =>
        if state.selected.length() < @storage.node_count(state.source) {
          state.selected.push(false)
          used += 1
        } else {
          state.phase = BeginNode
          state.node = 0
        }
      BeginNode =>
        if state.node < @storage.node_count(state.source) {
          state.selector = 0
          state.phase = CompareNodeIdentity
        } else {
          state.edge = 0
          state.phase = CopyEdges
        }
      CompareNodeIdentity => {
        guard @lower.graph_subgraph_literal_id_count(state.prepared)
          is Some(selector_count) &&
          @storage.node_identity(state.source, state.node) is Some(identity) else {
          return @bounded.Failed(SubgraphInputUnavailable, progress, used)
        }
        if state.selector >= selector_count {
          state.node += 1
          state.phase = BeginNode
          continue
        }
        guard @lower.graph_subgraph_literal_id_at(
            state.prepared,
            state.selector,
          )
          is Some(selected_identity) else {
          return @bounded.Failed(SubgraphInputUnavailable, progress, used)
        }
        state.selector += 1
        used += 1
        match @value.compare_key_values(identity, selected_identity) {
          Err(issue) =>
            return @bounded.Failed(SubgraphKeyOrder(issue), progress, used)
          Ok(0) =>
            match copy_subgraph_node(state, state.node) {
              Ok(_) => {
                state.selected[state.node] = true
                state.node += 1
                state.phase = BeginNode
                progress += 1
              }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          Ok(_) => ()
        }
      }
      CopyEdges =>
        if state.edge < @storage.edge_count(state.source) {
          guard @storage.edge_endpoints(state.source, state.edge)
            is Some((source, target)) &&
            state.selected.get(source) is Some(source_selected) &&
            state.selected.get(target) is Some(target_selected) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          if source_selected && target_selected {
            match copy_subgraph_edge(state, state.edge) {
              Ok(_) => progress += 1
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          }
          state.edge += 1
          used += 1
        } else {
          state.phase = FinishSubgraph
        }
      FinishSubgraph => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidSubgraphKernel, progress, used)
        }
        state.output = None
        return match @graph.finish_output(output) {
          Ok(value) => @bounded.Complete(value, progress, used)
          Err(issue) => @bounded.Failed(SubgraphOutput(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_subgraph_state(state : SubgraphState) -> Bool {
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  state.selected.clear()
  true
}

///|
pub fn start_subgraph(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[SubgraphExecution, SubgraphIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphSubgraphStep(prepared)) &&
    @lower.graph_subgraph_literal_id_count(prepared) is Some(_) &&
    !@lower.graph_subgraph_has_edge_predicate(prepared) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidSubgraphKernel)
  }
  guard @graph.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.GraphValue(contract) else {
    return Err(SubgraphInputUnavailable)
  }
  if limits.max_value_nodes < 1 || limits.max_value_nodes > (2147483647 - 1) / 4 {
    return Err(InvalidSubgraphLimits)
  }
  let nodes = @storage.node_count(source)
  if nodes > limits.max_workspace_slots {
    return Err(InvalidSubgraphLimits)
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
    Err(issue) => return Err(SubgraphOutput(issue))
  }
  let state : SubgraphState = {
    input,
    source,
    prepared,
    output: Some(output),
    selected: [],
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    phase: InitializeSelection,
    node: 0,
    selector: 0,
    edge: 0,
  }
  let (session, token) = @bounded.start(
    control, state, subgraph_step, cleanup_subgraph_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes * 4 + 1,
  })
}

///|
pub fn subgraph_max_noninterruptible_value_nodes(
  value : SubgraphExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn advance_subgraph(
  value : SubgraphExecution,
  quantum : Int,
) -> Result[SubgraphPoll, SubgraphIssue] {
  guard value.token is Some(token) else {
    return Err(SubgraphExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(SubgraphExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(SubgraphContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(SubgraphComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(SubgraphFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(SubgraphStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn subgraph_cleanup_pending(value : SubgraphExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_subgraph(
  value : SubgraphExecution,
) -> Result[Bool, SubgraphIssue] {
  @bounded.cleanup(value.session).map_err(issue => SubgraphExecutionIssue(issue))
}
