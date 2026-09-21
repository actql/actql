///|
priv enum SubgraphPhase {
  InitializeSelection
  InitializeSelector
  BeginNode
  CompareNodeIdentity
  VerifySelector
  PrepareNodePredicate
  EvaluateNodePredicate
  BeginEdge
  PrepareEdgePredicate
  EvaluateEdgePredicate
  FinishSubgraph
}

///|
priv struct SubgraphState {
  input : @graph.ProducerRead
  selector_input : @execution.ProducerRead?
  source : @storage.Storage
  graph : @carrier.Graph
  prepared : @lower.PreparedGraphSubgraph
  mut output : @graph.OutputBuilder?
  selected : Array[Bool]
  selector_values : Array[@value.CheckedValue]
  selector_found : Array[Bool]
  node_fields : Int
  edge_fields : Int
  node_predicate : @lower.Expression?
  edge_predicate : @lower.Expression?
  edge_literal : Bool?
  value_limits : @value.Limits
  predicate_workspace : Int
  mut predicate_work_remaining : Int
  predicate_input : Map[String, @execution.Value]
  mut predicate_execution : @execution.PredicateExpressionExecution?
  mut phase : SubgraphPhase
  mut node : Int
  mut selector : Int
  mut selector_row : Int
  selector_column : Int
  mut node_selected : Bool
  mut edge : Int
  mut predicate_field : Int
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
  MissingSubgraphNodeIdentity(Int)
  SubgraphPredicate(@execution.EvalIssueKind)
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
fn select_subgraph_node(
  state : SubgraphState,
  selected : Bool,
) -> Result[Unit, SubgraphIssue] {
  if selected {
    match copy_subgraph_node(state, state.node) {
      Ok(_) => state.selected[state.node] = true
      Err(issue) => return Err(issue)
    }
  }
  state.node += 1
  state.phase = BeginNode
  Ok(())
}

///|
fn select_subgraph_edge(
  state : SubgraphState,
  selected : Bool,
) -> Result[Unit, SubgraphIssue] {
  if selected {
    match copy_subgraph_edge(state, state.edge) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  }
  state.edge += 1
  state.phase = BeginEdge
  Ok(())
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
    let selector_unavailable = match state.selector_input {
      Some(input) => !@execution.producer_read_available(input)
      None => false
    }
    if !@graph.producer_read_available(state.input) || selector_unavailable {
      return @bounded.Failed(SubgraphInputUnavailable, progress, used)
    }
    match state.phase {
      InitializeSelection =>
        if state.selected.length() < @storage.node_count(state.source) {
          state.selected.push(false)
          used += 1
        } else {
          state.phase = InitializeSelector
          state.node = 0
        }
      InitializeSelector => {
        let count = match state.selector_input {
          Some(input) => @execution.producer_read_row_count(input)
          None =>
            @lower.graph_subgraph_literal_id_count(state.prepared).unwrap_or(0)
        }
        if state.selector_row < count {
          used += 1
          let value = match state.selector_input {
            Some(input) =>
              match
                @execution.producer_read_checked_cell(
                  input,
                  state.selector_row,
                  state.selector_column,
                  state.value_limits,
                ) {
                Some(value) => value
                None =>
                  return @bounded.Failed(
                    SubgraphInputUnavailable,
                    progress,
                    used,
                  )
              }
            None =>
              match
                @lower.graph_subgraph_literal_id_at(
                  state.prepared,
                  state.selector_row,
                ) {
                Some(value) => value
                None =>
                  return @bounded.Failed(
                    SubgraphInputUnavailable,
                    progress,
                    used,
                  )
              }
          }
          state.selector_values.push(value)
          state.selector_found.push(false)
          state.selector_row += 1
        } else {
          state.phase = BeginNode
        }
      }
      BeginNode =>
        if state.node < @storage.node_count(state.source) {
          match state.node_predicate {
            Some(_) => {
              state.predicate_field = 0
              state.predicate_input.clear()
              state.phase = PrepareNodePredicate
            }
            None => {
              state.selector = 0
              state.node_selected = false
              state.phase = CompareNodeIdentity
            }
          }
        } else {
          state.selector = 0
          state.phase = VerifySelector
        }
      CompareNodeIdentity => {
        let selector_count = state.selector_values.length()
        if state.selector >= selector_count {
          match select_subgraph_node(state, state.node_selected) {
            Ok(_) => if state.node_selected { progress += 1 }
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else {
          guard @storage.node_identity(state.source, state.node)
            is Some(identity) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          used += 1
          match
            @value.compare_key_values(
              identity,
              state.selector_values[state.selector],
            ) {
            Err(issue) =>
              return @bounded.Failed(SubgraphKeyOrder(issue), progress, used)
            Ok(0) => {
              state.selector_found[state.selector] = true
              state.node_selected = true
            }
            Ok(_) => ()
          }
          state.selector += 1
        }
      }
      VerifySelector =>
        if state.selector < state.selector_found.length() {
          used += 1
          if !state.selector_found[state.selector] {
            return @bounded.Failed(
              MissingSubgraphNodeIdentity(state.selector),
              progress,
              used,
            )
          }
          state.selector += 1
        } else {
          state.edge = 0
          state.phase = BeginEdge
        }
      PrepareNodePredicate =>
        if state.predicate_field <
          graph_node_predicate_binding_count(state.graph) {
          used += 1
          guard graph_node_predicate_binding(
              state.graph,
              state.source,
              state.node,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard state.node_predicate is Some(predicate) else {
            return @bounded.Failed(InvalidSubgraphKernel, progress, used)
          }
          match
            @execution.start_predicate_expression(
              predicate,
              state.predicate_input,
              state.predicate_work_remaining,
              state.value_limits.max_nodes,
              state.predicate_workspace,
            ) {
            Err(issue) =>
              return @bounded.Failed(
                SubgraphPredicate(issue.kind),
                progress,
                used,
              )
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateNodePredicate
            }
          }
        }
      EvaluateNodePredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidSubgraphKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              SubgraphPredicate(issue.kind),
              progress,
              used,
            )
          }
          Ok(@execution.PredicateExpressionContinue) => ()
          Ok(@execution.PredicateExpressionComplete(selected)) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            state.predicate_input.clear()
            match select_subgraph_node(state, selected) {
              Ok(_) => if selected { progress += 1 }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          }
        }
      }
      BeginEdge =>
        if state.edge < @storage.edge_count(state.source) {
          guard @storage.edge_endpoints(state.source, state.edge)
            is Some((source, target)) &&
            state.selected.get(source) is Some(source_selected) &&
            state.selected.get(target) is Some(target_selected) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          used += 1
          if source_selected && target_selected {
            match state.edge_literal {
              Some(selected) =>
                match select_subgraph_edge(state, selected) {
                  Ok(_) => if selected { progress += 1 }
                  Err(issue) => return @bounded.Failed(issue, progress, used)
                }
              None => {
                state.predicate_field = 0
                state.predicate_input.clear()
                state.phase = PrepareEdgePredicate
              }
            }
          } else {
            state.edge += 1
          }
        } else {
          state.phase = FinishSubgraph
        }
      PrepareEdgePredicate =>
        if state.predicate_field <
          graph_edge_predicate_binding_count(state.graph) {
          used += 1
          guard graph_edge_predicate_binding(
              state.graph,
              state.source,
              state.edge,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(SubgraphInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard state.edge_predicate is Some(predicate) else {
            return @bounded.Failed(InvalidSubgraphKernel, progress, used)
          }
          match
            @execution.start_predicate_expression(
              predicate,
              state.predicate_input,
              state.predicate_work_remaining,
              state.value_limits.max_nodes,
              state.predicate_workspace,
            ) {
            Err(issue) =>
              return @bounded.Failed(
                SubgraphPredicate(issue.kind),
                progress,
                used,
              )
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateEdgePredicate
            }
          }
        }
      EvaluateEdgePredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidSubgraphKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              SubgraphPredicate(issue.kind),
              progress,
              used,
            )
          }
          Ok(@execution.PredicateExpressionContinue) => ()
          Ok(@execution.PredicateExpressionComplete(selected)) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            state.predicate_input.clear()
            match select_subgraph_edge(state, selected) {
              Ok(_) => if selected { progress += 1 }
              Err(issue) => return @bounded.Failed(issue, progress, used)
            }
          }
        }
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
  if state.predicate_execution is Some(execution) {
    @execution.cancel_predicate_expression(execution) |> ignore
    state.predicate_execution = None
  }
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  state.selected.clear()
  state.selector_values.clear()
  state.selector_found.clear()
  state.predicate_input.clear()
  true
}

///|
pub fn start_subgraph(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  selector_input : @execution.ProducerRead?,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[SubgraphExecution, SubgraphIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphSubgraphStep(prepared)) &&
    (
      @lower.graph_subgraph_literal_id_count(prepared) is Some(_) ||
      @lower.graph_subgraph_relation_selector_field(prepared) is Some(_) ||
      @lower.graph_subgraph_node_predicate(prepared) is Some(_)
    ) &&
    (
      @lower.graph_subgraph_literal_edge_predicate(prepared) is Some(_) ||
      @lower.graph_subgraph_edge_predicate(prepared) is Some(_)
    ) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidSubgraphKernel)
  }
  let relation_field = @lower.graph_subgraph_relation_selector_field(prepared)
  let mut selector_column = -1
  match (relation_field, selector_input) {
    (Some(field), Some(selector)) => {
      let schema = @execution.producer_read_schema(selector)
      for column in 0..<@schema.field_count(schema) {
        if @schema.field_at(schema, column).map(value => value.name) ==
          Some(field) {
          selector_column = column
        }
      }
      if !@execution.producer_read_matches_operation_input(
          selector, owner, step, 1,
        ) ||
        selector_column < 0 {
        return Err(InvalidSubgraphKernel)
      }
    }
    (None, None) => ()
    _ => return Err(InvalidSubgraphKernel)
  }
  guard @graph.producer_read_storage(input) is Some(source) &&
    @storage.carrier(source) is @carrier.GraphValue(contract) else {
    return Err(SubgraphInputUnavailable)
  }
  if limits.max_value_nodes < 1 || limits.max_value_nodes > (2147483647 - 1) / 4 {
    return Err(InvalidSubgraphLimits)
  }
  let nodes = @storage.node_count(source)
  let selector_count = match selector_input {
    Some(selector) => @execution.producer_read_row_count(selector)
    None => @lower.graph_subgraph_literal_id_count(prepared).unwrap_or(0)
  }
  let node_predicate = @lower.graph_subgraph_node_predicate(prepared)
  let edge_literal = @lower.graph_subgraph_literal_edge_predicate(prepared)
  let edge_predicate = if edge_literal is Some(_) {
    None
  } else {
    @lower.graph_subgraph_edge_predicate(prepared)
  }
  let predicate_fields = Int::max(
    if node_predicate is Some(_) {
      graph_node_predicate_binding_count(contract)
    } else {
      0
    },
    if edge_predicate is Some(_) {
      graph_edge_predicate_binding_count(contract)
    } else {
      0
    },
  )
  if nodes > limits.max_workspace_slots ||
    selector_count > (limits.max_workspace_slots - nodes) / 2 ||
    predicate_fields > limits.max_workspace_slots - nodes - selector_count * 2 {
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
    selector_input,
    source,
    graph: contract,
    prepared,
    output: Some(output),
    selected: [],
    selector_values: [],
    selector_found: [],
    node_fields: @carrier.field_count(@carrier.graph_node_properties(contract)),
    edge_fields: @carrier.field_count(@carrier.graph_edge_properties(contract)),
    node_predicate,
    edge_predicate,
    edge_literal,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    predicate_workspace: limits.max_workspace_slots -
    nodes -
    selector_count * 2 -
    predicate_fields,
    predicate_work_remaining: limits.max_work,
    predicate_input: Map([]),
    predicate_execution: None,
    phase: InitializeSelection,
    node: 0,
    selector: 0,
    selector_row: 0,
    selector_column,
    node_selected: false,
    edge: 0,
    predicate_field: 0,
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
