///|
priv struct TraversalPath {
  nodes : Array[Int]
  edges : Array[Int]
}

///|
priv enum TraversePathStarts {
  LiteralPathStarts
  RelationPathStarts(@execution.ProducerRead, Int)
  PredicatePathStarts(@lower.Expression)
}

///|
priv enum TraversePathsPhase {
  ResolveStarts
  PrepareStartPredicate
  EvaluateStartPredicate
  SortStarts
  BeginDepth
  ScanEdge
  ScanHopEdgeTypes
  PrepareHopEdgePredicate
  EvaluateHopEdgePredicate
  PrepareHopNodePredicate
  EvaluateHopNodePredicate
  AddPath
  SortPaths
  EmitPath
  ReadField
  CommitRow
  Finish
}

///|
priv struct TraversePathsState {
  input : @graph.ProducerRead
  source : @storage.Storage
  graph : @carrier.Graph
  schema : @schema.Schema
  prepared : @lower.PreparedGraphTraverse
  starts : TraversePathStarts
  direction : @graph_type.Direction
  minimum_depth : Int
  maximum_depth : Int
  max_rows : Int
  max_workspace_slots : Int
  value_limits : @value.Limits
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : TraversePathsPhase
  mut start_scan : Int
  start_selected : Array[Bool]
  start_predicate_fields : Int
  edge_predicate_fields : Int
  node_predicate_fields : Int
  predicate_workspace : Int
  mut predicate_work_remaining : Int
  predicate_input : Map[String, @execution.Value]
  mut predicate_execution : @execution.PredicateExpressionExecution?
  mut predicate_field : Int
  mut sort_index : Int
  mut sort_cursor : Int
  frontier : Array[TraversalPath]
  next_frontier : Array[TraversalPath]
  mut depth : Int
  mut path_index : Int
  mut edge_occurrence : Int
  mut candidate_node : Int
  mut candidate_edge : Int
  mut edge_type_index : Int
  mut emit_index : Int
  mut column : Int
  mut values : Array[@value.CheckedValue]
  mut emitted : Int
  mut workspace_slots : Int
}

///|
priv struct TraversePathsExecution {
  session : @bounded.Session[
    TraversePathsState,
    @execution.CompletedOutput,
    TraversePathsIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
priv enum TraversePathsPoll {
  TraversePathsContinue(progress~ : Int64, work~ : Int64)
  TraversePathsComplete(
    @execution.CompletedOutput,
    progress~ : Int64,
    work~ : Int64
  )
  TraversePathsFailed(TraversePathsIssue, progress~ : Int64, work~ : Int64)
  TraversePathsStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum TraversePathsIssue {
  InvalidTraversePathsKernel
  TraversePathsInputUnavailable
  TraversePathsStartMissing
  TraversePathsOutputLimit
  TraversePathsWorkspaceLimit
  TraversePathsPredicate(@execution.EvalIssueKind)
  TraversePathsKeyOrder(@value.KeyOrderIssue)
  TraversePathsOutput(@execution.CaptureIssue)
  TraversePathsCompletion(@execution.TrustedOutputIssue)
  TraversePathsExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn traverse_path_start_count(state : TraversePathsState) -> Int {
  match state.starts {
    LiteralPathStarts => @lower.graph_traverse_start_id_count(state.prepared)
    RelationPathStarts(input, _) => @execution.producer_read_row_count(input)
    PredicatePathStarts(_) => @storage.node_count(state.source)
  }
}

///|
fn traverse_path_start_at(
  state : TraversePathsState,
  index : Int,
) -> @value.CheckedValue? {
  match state.starts {
    LiteralPathStarts =>
      @lower.graph_traverse_start_id_at(state.prepared, index)
    RelationPathStarts(input, column) =>
      @execution.producer_read_checked_cell(
        input,
        index,
        column,
        state.value_limits,
      )
    PredicatePathStarts(_) => None
  }
}

///|
fn traverse_path_starts_available(state : TraversePathsState) -> Bool {
  match state.starts {
    LiteralPathStarts => true
    RelationPathStarts(input, _) => @execution.producer_read_available(input)
    PredicatePathStarts(_) => true
  }
}

///|
fn traversal_path_slots(value : TraversalPath) -> Int? {
  let nodes = value.nodes.length()
  let edges = value.edges.length()
  if nodes > 2147483647 - edges - 1 {
    None
  } else {
    Some(nodes + edges + 1)
  }
}

///|
fn path_contains_node(value : TraversalPath, node : Int) -> Bool {
  value.nodes.any(item => item == node)
}

///|
fn path_edge_identity_value(
  source : @storage.Storage,
  edge : Int,
) -> @value.Value? {
  guard @storage.edge_endpoints(source, edge) is Some((from, to)) &&
    @storage.node_identity(source, from) is Some(from_id) &&
    @storage.node_identity(source, to) is Some(to_id) &&
    @storage.edge_label(source, edge) is Some(label) &&
    @value.object_value([
      ("src", from_id.value),
      ("dst", to_id.value),
      (
        "rel",
        match label {
          Some(value) => value.value
          None => @value.null_value()
        },
      ),
    ])
    is Some(identity) else {
    return None
  }
  Some(identity)
}

///|
fn compare_traversal_paths(
  state : TraversePathsState,
  left : TraversalPath,
  right : TraversalPath,
) -> Result[Int, TraversePathsIssue] {
  let mut index = 0
  while index < left.nodes.length() && index < right.nodes.length() {
    guard @storage.node_identity(state.source, left.nodes[index])
      is Some(left_id) &&
      @storage.node_identity(state.source, right.nodes[index]) is Some(right_id) else {
      return Err(TraversePathsInputUnavailable)
    }
    let compared = match @value.compare_key_values(left_id, right_id) {
      Ok(value) => value
      Err(issue) => return Err(TraversePathsKeyOrder(issue))
    }
    if compared != 0 {
      return Ok(compared)
    }
    index += 1
  }
  if left.nodes.length() != right.nodes.length() {
    return Ok(left.nodes.length() - right.nodes.length())
  }
  index = 0
  while index < left.edges.length() && index < right.edges.length() {
    guard @storage.edge_endpoints(state.source, left.edges[index])
      is Some((left_source, left_target)) &&
      @storage.edge_endpoints(state.source, right.edges[index])
      is Some((right_source, right_target)) &&
      @storage.node_identity(state.source, left_source) is Some(left_source_id) &&
      @storage.node_identity(state.source, right_source)
      is Some(right_source_id) &&
      @storage.node_identity(state.source, left_target) is Some(left_target_id) &&
      @storage.node_identity(state.source, right_target)
      is Some(right_target_id) &&
      @storage.edge_label(state.source, left.edges[index]) is Some(left_label) &&
      @storage.edge_label(state.source, right.edges[index]) is Some(right_label) else {
      return Err(TraversePathsInputUnavailable)
    }
    for
      pair in [
        (left_source_id, right_source_id),
        (left_target_id, right_target_id),
      ] {
      let compared = match @value.compare_key_values(pair.0, pair.1) {
        Ok(value) => value
        Err(issue) => return Err(TraversePathsKeyOrder(issue))
      }
      if compared != 0 {
        return Ok(compared)
      }
    }
    let compared = match (left_label, right_label) {
      (None, None) => 0
      (None, Some(_)) => -1
      (Some(_), None) => 1
      (Some(left), Some(right)) =>
        match @value.compare_key_values(left, right) {
          Ok(value) => value
          Err(issue) => return Err(TraversePathsKeyOrder(issue))
        }
    }
    if compared != 0 {
      return Ok(compared)
    }
    index += 1
  }
  Ok(left.edges.length() - right.edges.length())
}

///|
fn traversal_neighbor(
  state : TraversePathsState,
  path : TraversalPath,
  occurrence : Int,
) -> (Int, Int)? {
  guard traverse_path_direction(state) is Some(direction) else { return None }
  let edge_count = @storage.edge_count(state.source)
  let edge = if occurrence < edge_count {
    occurrence
  } else {
    occurrence - edge_count
  }
  guard edge >= 0 &&
    edge < edge_count &&
    @storage.edge_endpoints(state.source, edge) is Some((from, to)) else {
    return None
  }
  let current = path.nodes[path.nodes.length() - 1]
  if occurrence >= edge_count {
    if direction != @graph_type.Both || from == to || to != current {
      return None
    }
    Some((from, edge))
  } else if direction == @graph_type.Incoming {
    if to == current {
      Some((from, edge))
    } else {
      None
    }
  } else if direction == @graph_type.Outgoing {
    if from == current {
      Some((to, edge))
    } else {
      None
    }
  } else if from == current {
    Some((to, edge))
  } else {
    None
  }
}

///|
fn traverse_path_hop(state : TraversePathsState) -> Int {
  if @lower.graph_traverse_patterned(state.prepared) {
    state.depth
  } else {
    0
  }
}

///|
fn traverse_path_direction(
  state : TraversePathsState,
) -> @graph_type.Direction? {
  if @lower.graph_traverse_patterned(state.prepared) {
    @lower.graph_traverse_hop_direction(
      state.prepared,
      traverse_path_hop(state),
    )
  } else {
    Some(state.direction)
  }
}

///|
fn traverse_path_edge_type_count(state : TraversePathsState) -> Int? {
  @lower.graph_traverse_hop_type_count(state.prepared, traverse_path_hop(state))
}

///|
fn traverse_path_edge_type_matches(
  state : TraversePathsState,
  edge : Int,
  index : Int,
) -> Bool {
  guard @lower.graph_traverse_hop_type_at(
      state.prepared,
      traverse_path_hop(state),
      index,
    )
    is Some(expected) &&
    @storage.edge_label(state.source, edge)
    is Some(Some({ value: @value.Text(actual), .. })) else {
    return false
  }
  actual == expected
}

///|
fn traverse_path_edge_predicate(
  state : TraversePathsState,
) -> @lower.Expression? {
  @lower.graph_traverse_hop_edge_predicate(
    state.prepared,
    traverse_path_hop(state),
  )
}

///|
fn traverse_path_node_predicate(
  state : TraversePathsState,
) -> @lower.Expression? {
  @lower.graph_traverse_hop_node_predicate(
    state.prepared,
    traverse_path_hop(state),
  )
}

///|
fn prepare_traverse_path_predicates(
  state : TraversePathsState,
  edge : Int,
  node : Int,
) -> Unit {
  state.candidate_edge = edge
  state.candidate_node = node
  state.predicate_field = 0
  state.predicate_input.clear()
  state.phase = if traverse_path_edge_predicate(state) is Some(_) {
    PrepareHopEdgePredicate
  } else {
    PrepareHopNodePredicate
  }
}

///|
fn prepare_traverse_path_candidate(
  state : TraversePathsState,
  edge : Int,
  node : Int,
) -> Unit {
  state.candidate_edge = edge
  state.candidate_node = node
  match traverse_path_edge_type_count(state) {
    Some(0) => state.phase = ScanEdge
    Some(_) => {
      state.edge_type_index = 0
      state.phase = ScanHopEdgeTypes
    }
    None => prepare_traverse_path_predicates(state, edge, node)
  }
}

///|
fn traverse_path_value(
  state : TraversePathsState,
  path : TraversalPath,
  field : @schema.Field,
) -> @value.CheckedValue? {
  match field.name {
    @schema.Unqualified("start_id") =>
      @storage.node_identity(state.source, path.nodes[0]).bind(identity => {
        @value.recheck_runtime_value(
          identity.value,
          field.contract,
          state.value_limits,
        )
      })
    @schema.Unqualified("end_id") =>
      @storage.node_identity(state.source, path.nodes[path.nodes.length() - 1]).bind(identity => {
          @value.recheck_runtime_value(
            identity.value,
            field.contract,
            state.value_limits,
          )
        },
      )
    @schema.Unqualified("hop_count") =>
      @value.checked_number_value(
        path.edges.length().to_double(),
        field.contract,
      )
    @schema.Unqualified("node_ids") => {
      let values : Array[@value.Value] = []
      for node in path.nodes {
        guard @storage.node_identity(state.source, node) is Some(identity) else {
          return None
        }
        values.push(identity.value)
      }
      @value.recheck_runtime_value(
        @value.array_value(values),
        field.contract,
        state.value_limits,
      )
    }
    @schema.Unqualified("edge_ids") => {
      let values : Array[@value.Value] = []
      for edge in path.edges {
        guard path_edge_identity_value(state.source, edge) is Some(identity) else {
          return None
        }
        values.push(identity)
      }
      @value.recheck_runtime_value(
        @value.array_value(values),
        field.contract,
        state.value_limits,
      )
    }
    _ => None
  }
}

///|
fn traverse_paths_step(
  state : TraversePathsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, TraversePathsIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@graph.producer_read_available(state.input) ||
      !traverse_path_starts_available(state) {
      return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
    }
    match state.phase {
      ResolveStarts =>
        if state.start_scan < traverse_path_start_count(state) {
          used += 1
          guard traverse_path_start_at(state, state.start_scan)
            is Some(identity) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          match @storage.node_index(state.source, identity) {
            Err(_) =>
              return @bounded.Failed(
                TraversePathsInputUnavailable,
                progress,
                used,
              )
            Ok(None) =>
              return @bounded.Failed(TraversePathsStartMissing, progress, used)
            Ok(Some(node)) => state.start_selected[node] = true
          }
          state.start_scan += 1
        } else {
          state.start_scan = 0
          state.phase = SortStarts
        }
      PrepareStartPredicate =>
        if state.start_scan >= @storage.node_count(state.source) {
          state.start_scan = 0
          state.phase = SortStarts
        } else if state.predicate_field < state.start_predicate_fields {
          used += 1
          guard graph_node_predicate_binding(
              state.graph,
              state.source,
              state.start_scan,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard state.starts is PredicatePathStarts(predicate) else {
            return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
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
                TraversePathsPredicate(issue.kind),
                progress,
                used,
              )
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateStartPredicate
            }
          }
        }
      EvaluateStartPredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              TraversePathsPredicate(issue.kind),
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
            state.start_selected[state.start_scan] = selected
            state.start_scan += 1
            state.predicate_field = 0
            state.phase = PrepareStartPredicate
          }
        }
      }
      SortStarts =>
        if state.start_scan < state.start_selected.length() {
          used += 1
          if state.start_selected[state.start_scan] {
            let path = { nodes: [state.start_scan], edges: [], }
            guard traversal_path_slots(path) is Some(slots) &&
              slots <= state.max_workspace_slots - state.workspace_slots else {
              return @bounded.Failed(
                TraversePathsWorkspaceLimit,
                progress,
                used,
              )
            }
            if state.minimum_depth == 0 &&
              state.frontier.length() >= state.max_rows {
              return @bounded.Failed(TraversePathsOutputLimit, progress, used)
            }
            state.workspace_slots += slots
            state.frontier.push(path)
          }
          state.start_scan += 1
        } else {
          state.depth = 0
          state.path_index = 0
          state.edge_occurrence = 0
          state.emit_index = 0
          state.phase = if state.minimum_depth == 0 {
            EmitPath
          } else {
            BeginDepth
          }
        }
      BeginDepth =>
        if state.depth >= state.maximum_depth || state.frontier.is_empty() {
          state.phase = Finish
        } else {
          state.path_index = 0
          state.edge_occurrence = 0
          state.phase = ScanEdge
        }
      ScanEdge =>
        if state.path_index >= state.frontier.length() {
          state.sort_index = 1
          state.sort_cursor = 1
          state.phase = SortPaths
        } else {
          guard traverse_path_direction(state) is Some(direction) else {
            return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
          }
          let occurrences = if direction == @graph_type.Both {
            @storage.edge_count(state.source) * 2
          } else {
            @storage.edge_count(state.source)
          }
          if state.edge_occurrence >= occurrences {
            state.path_index += 1
            state.edge_occurrence = 0
          } else {
            used += 1
            let path = state.frontier[state.path_index]
            let occurrence = state.edge_occurrence
            state.edge_occurrence += 1
            if traversal_neighbor(state, path, occurrence) is Some((node, edge)) &&
              !path_contains_node(path, node) {
              prepare_traverse_path_candidate(state, edge, node)
            }
          }
        }
      ScanHopEdgeTypes => {
        guard traverse_path_edge_type_count(state) is Some(type_count) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        let matches = traverse_path_edge_type_matches(
          state,
          state.candidate_edge,
          state.edge_type_index,
        )
        state.edge_type_index += 1
        used += 1
        if matches {
          prepare_traverse_path_predicates(
            state,
            state.candidate_edge,
            state.candidate_node,
          )
        } else if state.edge_type_index >= type_count {
          state.phase = ScanEdge
        }
      }
      PrepareHopEdgePredicate =>
        if state.predicate_field < state.edge_predicate_fields {
          used += 1
          guard graph_edge_predicate_binding(
              state.graph,
              state.source,
              state.candidate_edge,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard traverse_path_edge_predicate(state) is Some(predicate) else {
            return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
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
                TraversePathsPredicate(issue.kind),
                progress,
                used,
              )
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateHopEdgePredicate
            }
          }
        }
      EvaluateHopEdgePredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              TraversePathsPredicate(issue.kind),
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
            state.predicate_field = 0
            state.phase = if !selected {
              ScanEdge
            } else {
              PrepareHopNodePredicate
            }
          }
        }
      }
      PrepareHopNodePredicate =>
        if traverse_path_node_predicate(state) is None {
          state.phase = AddPath
        } else if state.predicate_field < state.node_predicate_fields {
          used += 1
          guard graph_node_predicate_binding(
              state.graph,
              state.source,
              state.candidate_node,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard traverse_path_node_predicate(state) is Some(predicate) else {
            return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
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
                TraversePathsPredicate(issue.kind),
                progress,
                used,
              )
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateHopNodePredicate
            }
          }
        }
      EvaluateHopNodePredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              TraversePathsPredicate(issue.kind),
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
            state.predicate_field = 0
            state.phase = if selected { AddPath } else { ScanEdge }
          }
        }
      }
      AddPath => {
        used += 1
        guard state.frontier.get(state.path_index) is Some(path) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        let next_slots = path.nodes.length() + path.edges.length() + 3
        if next_slots > state.max_workspace_slots - state.workspace_slots {
          return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
        }
        if state.depth + 1 >= state.minimum_depth &&
          state.emitted + state.next_frontier.length() >= state.max_rows {
          return @bounded.Failed(TraversePathsOutputLimit, progress, used)
        }
        let nodes = path.nodes.copy()
        let edges = path.edges.copy()
        nodes.push(state.candidate_node)
        edges.push(state.candidate_edge)
        state.workspace_slots += next_slots
        state.next_frontier.push({ nodes, edges, })
        state.phase = ScanEdge
      }
      SortPaths =>
        if state.sort_index >= state.next_frontier.length() {
          for path in state.frontier {
            state.workspace_slots -= traversal_path_slots(path).unwrap()
          }
          state.frontier.clear()
          for path in state.next_frontier {
            state.frontier.push(path)
          }
          state.next_frontier.clear()
          state.depth += 1
          state.emit_index = 0
          state.phase = if state.depth >= state.minimum_depth {
            EmitPath
          } else {
            BeginDepth
          }
        } else if state.sort_cursor > 0 {
          used += 1
          let compared = match
            compare_traversal_paths(
              state,
              state.next_frontier[state.sort_cursor - 1],
              state.next_frontier[state.sort_cursor],
            ) {
            Ok(value) => value
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
          if compared > 0 {
            let swap = state.next_frontier[state.sort_cursor - 1]
            state.next_frontier[state.sort_cursor - 1] = state.next_frontier[state.sort_cursor]
            state.next_frontier[state.sort_cursor] = swap
            state.sort_cursor -= 1
          } else {
            state.sort_index += 1
            state.sort_cursor = state.sort_index
          }
        } else {
          state.sort_index += 1
          state.sort_cursor = state.sort_index
        }
      EmitPath =>
        if state.emit_index >= state.frontier.length() {
          state.phase = BeginDepth
        } else {
          state.column = 0
          state.values = []
          state.phase = ReadField
        }
      ReadField => {
        used += 1
        guard state.frontier.get(state.emit_index) is Some(path) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        if state.column < @schema.field_count(state.schema) {
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            traverse_path_value(state, path, field) is Some(value) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          state.values.push(value)
          state.column += 1
        } else {
          state.phase = CommitRow
        }
      }
      CommitRow => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.emitted += 1
            state.emit_index += 1
            progress += 1
            state.phase = EmitPath
          }
          Err(issue) =>
            return @bounded.Failed(TraversePathsOutput(issue), progress, used)
        }
      }
      Finish => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(TraversePathsOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(TraversePathsCompletion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_traverse_paths_state(state : TraversePathsState) -> Bool {
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
fn start_traverse_paths(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[TraversePathsExecution, TraversePathsIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphTraverseStep(prepared)) else {
    return Err(InvalidTraversePathsKernel)
  }
  let hop_count = @lower.graph_traverse_hop_count(prepared)
  let patterned = @lower.graph_traverse_patterned(prepared)
  let bounds = if patterned {
    Some((hop_count.to_int64(), hop_count.to_int64()))
  } else {
    @lower.graph_traverse_bounds(prepared)
  }
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.graph_traverse_emits_paths(prepared) &&
    bounds is Some((minimum, maximum)) &&
    minimum <= 2147483647L &&
    maximum <= 2147483647L &&
    hop_count > 0 &&
    @lower.graph_traverse_hop_direction(prepared, 0) is Some(direction) &&
    @graph.producer_read_storage(input) is Some(source) &&
    (direction != @graph_type.Both || @storage.edge_count(source) <= 1073741823) &&
    max_rows >= 0 &&
    max_workspace_slots >= 0 else {
    return Err(InvalidTraversePathsKernel)
  }
  for hop in 0..<hop_count {
    guard @lower.graph_traverse_hop_direction(prepared, hop) is Some(_) else {
      return Err(InvalidTraversePathsKernel)
    }
  }
  guard @storage.carrier(source) is @carrier.GraphValue(graph) else {
    return Err(InvalidTraversePathsKernel)
  }
  let starts = match
    (
      @lower.graph_traverse_start_relation_field(prepared),
      @lower.graph_traverse_start_predicate(prepared),
    ) {
    (None, None) => {
      guard @lower.graph_traverse_start_id_count(prepared) > 0 else {
        return Err(InvalidTraversePathsKernel)
      }
      LiteralPathStarts
    }
    (Some(field), None) => {
      let mut selector = None
      for candidate in inputs {
        if @execution.producer_read_matches_operation_input(
            candidate, owner, step, 1,
          ) {
          selector = Some(candidate)
          break
        }
      }
      guard selector is Some(selector) else {
        return Err(InvalidTraversePathsKernel)
      }
      let schema = @execution.producer_read_schema(selector)
      let mut column = -1
      for index in 0..<@schema.field_count(schema) {
        if @schema.field_at(schema, index).map(value => value.name) ==
          Some(field) {
          column = index
          break
        }
      }
      guard column >= 0 else { return Err(InvalidTraversePathsKernel) }
      RelationPathStarts(selector, column)
    }
    (None, Some(predicate)) => PredicatePathStarts(predicate)
    _ => return Err(InvalidTraversePathsKernel)
  }
  let max_rows = match @lower.graph_traverse_output_guard(prepared) {
    Some(limit) if limit < max_rows.to_int64() => limit.to_int()
    _ => max_rows
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(TraversePathsOutput(issue))
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
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(TraversePathsCompletion(issue))
    }
  }
  let node_count = @storage.node_count(source)
  let start_predicate_fields = match starts {
    PredicatePathStarts(_) => graph_node_predicate_binding_count(graph)
    _ => 0
  }
  let mut has_edge_predicate = false
  let mut has_node_predicate = false
  for hop in 0..<hop_count {
    if @lower.graph_traverse_hop_edge_predicate(prepared, hop) is Some(_) {
      has_edge_predicate = true
    }
    if @lower.graph_traverse_hop_node_predicate(prepared, hop) is Some(_) {
      has_node_predicate = true
    }
  }
  let edge_predicate_fields = if has_edge_predicate {
    graph_edge_predicate_binding_count(graph)
  } else {
    0
  }
  let node_predicate_fields = if has_node_predicate {
    graph_node_predicate_binding_count(graph)
  } else {
    0
  }
  let predicate_workspace_width = Int::max(
    start_predicate_fields,
    Int::max(edge_predicate_fields, node_predicate_fields),
  )
  if node_count > max_workspace_slots ||
    predicate_workspace_width > max_workspace_slots - node_count {
    @execution.cancel_admitted_output(output) |> ignore
    return Err(TraversePathsWorkspaceLimit)
  }
  let state : TraversePathsState = {
    input,
    source,
    graph,
    schema: @lower.graph_traverse_output_schema(prepared),
    prepared,
    starts,
    direction,
    minimum_depth: minimum.to_int(),
    maximum_depth: maximum.to_int(),
    max_rows,
    max_workspace_slots,
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: match starts {
      PredicatePathStarts(_) => PrepareStartPredicate
      _ => ResolveStarts
    },
    start_scan: 0,
    start_selected: Array::make(node_count, false),
    start_predicate_fields,
    edge_predicate_fields,
    node_predicate_fields,
    predicate_workspace: max_workspace_slots -
    node_count -
    predicate_workspace_width,
    predicate_work_remaining: limits.max_work,
    predicate_input: Map([]),
    predicate_execution: None,
    predicate_field: 0,
    sort_index: 0,
    sort_cursor: 0,
    frontier: [],
    next_frontier: [],
    depth: 0,
    path_index: 0,
    edge_occurrence: 0,
    candidate_node: -1,
    candidate_edge: -1,
    edge_type_index: 0,
    emit_index: 0,
    column: 0,
    values: [],
    emitted: 0,
    workspace_slots: node_count + predicate_workspace_width,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    traverse_paths_step,
    cleanup_traverse_paths_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
fn advance_traverse_paths(
  value : TraversePathsExecution,
  quantum : Int,
) -> Result[TraversePathsPoll, TraversePathsIssue] {
  guard value.token is Some(token) else {
    return Err(TraversePathsExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(TraversePathsExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(TraversePathsContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(TraversePathsComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(TraversePathsFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(TraversePathsStopped(reason, progress~, work~))
    }
  }
}

///|
fn traverse_paths_stopped(value : TraversePathsExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
fn traverse_paths_cleanup_pending(value : TraversePathsExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
fn cleanup_traverse_paths(
  value : TraversePathsExecution,
) -> Result[Bool, TraversePathsIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    TraversePathsExecutionIssue(issue)
  })
}
