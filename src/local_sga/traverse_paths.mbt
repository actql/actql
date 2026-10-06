///|
priv struct TraversalPath {
  nodes : Array[Int]
  edges : Array[Int]
}

///|
priv enum TraversePathStarts {
  LiteralPathStarts
  RelationPathStarts(@execution.ProducerRead, Int)
}

///|
priv enum TraversePathsPhase {
  InitializeStartSelection
  ResolveStarts
  CollectStarts
  SortStarts
  BeginStart
  InitializeNodeDepths
  SeedStart
  BeginDepth
  ScanEdge
  CheckCandidateNode
  ScanHopEdgeTypes
  BeginEdgePredicate
  BeginNodePredicate
  PreparePredicate
  EvaluatePredicate
  AddPath
  CopyPathNodes
  CopyPathEdges
  CommitPath
  SortPaths
  ComparePathNodes
  ComparePathEdges
  EmitPath
  CollectNodeDepth
  SortNodeOutput
  EmitNode
  ReadField
  BuildNodeIds
  BuildEdgeIds
  FinalizePathValue
  CommitRow
  Finish
}

///|
priv enum TraversePredicateKind {
  EdgePredicate
  NodePredicate
} derive(Eq)

///|
priv struct TraversePathsState {
  source : GraphReadSource
  graph : @carrier.Graph
  schema : @schema.Schema
  prepared : @lower.PreparedGraphTraverse
  starts : TraversePathStarts
  direction : @graph_type.Direction
  minimum_depth : Int
  maximum_depth : Int
  max_rows : Int
  max_paths : Int
  mut searched_paths : Int
  emit_nodes : Bool
  max_workspace_slots : Int
  value_limits : @value.Limits
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : TraversePathsPhase
  mut start_scan : Int
  mut start_selected : Array[Bool]
  start_nodes : Array[Int]
  mut sort_index : Int
  mut sort_cursor : Int
  mut compare_index : Int
  mut comparison_unit : Int
  mut member_index : Int
  mut copy_index : Int
  mut frontier : Array[TraversalPath]
  mut next_frontier : Array[TraversalPath]
  mut frontier_slots : Int
  mut next_frontier_slots : Int
  mut pending_nodes : Array[Int]
  mut pending_edges : Array[Int]
  mut pending_slots : Int
  mut depth : Int
  mut path_index : Int
  mut edge_occurrence : Int
  mut candidate_node : Int
  mut candidate_edge : Int
  mut edge_type_index : Int
  mut predicate_kind : TraversePredicateKind
  mut predicate_field : Int
  mut predicate_slots : Int
  predicate_input : Map[String, @execution.Value]
  mut predicate_execution : @execution.PredicateExpressionExecution?
  mut predicate_work_remaining : Int
  mut emit_index : Int
  mut column : Int
  mut values : Array[@value.CheckedValue]
  mut value_items : @value.ArrayBuilder?
  mut value_item : Int
  mut value_nodes_remaining : Int
  mut row_value_slots : Int
  value_item_attempts : Ref[Int]
  predicate_starts : Ref[Int]
  mut emitted : Int
  node_depths : Array[Int]
  node_order : Array[Int]
  mut workspace_slots : Int
  mut workspace_peak : Int
  mut control_work_remaining : Int
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
  private_entries : () -> Int
  workspace_usage : () -> (Int, Int)
  value_item_attempts : Ref[Int]
  predicate_starts : Ref[Int]
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
  TraversePathsSearchLimit
  InvalidTraversePathsKernel
  TraversePathsInputUnavailable
  TraversePathsStartMissing
  TraversePathsOutputLimit
  TraversePathsWorkspaceLimit
  TraversePathsWorkLimit
  TraversePathsKeyOrder(@value.KeyOrderIssue)
  TraversePathsPredicate(@execution.EvalIssueKind)
  TraversePathsOutput(@execution.CaptureIssue)
  TraversePathsCompletion(@execution.TrustedOutputIssue)
  TraversePathsExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn traverse_path_start_count(state : TraversePathsState) -> Int {
  match state.starts {
    LiteralPathStarts => @lower.graph_traverse_start_id_count(state.prepared)
    RelationPathStarts(input, _) => @execution.producer_read_row_count(input)
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
  }
}

///|
fn traverse_path_starts_available(state : TraversePathsState) -> Bool {
  match state.starts {
    LiteralPathStarts => true
    RelationPathStarts(input, _) => @execution.producer_read_available(input)
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
fn path_edge_identity_value(
  source : GraphReadSource,
  edge : Int,
) -> @value.Value? {
  graph_read_edge_identity(source, edge).map(identity => identity.value)
}

///|
fn compare_traversal_edges(
  state : TraversePathsState,
  left : Int,
  right : Int,
) -> Result[Int?, TraversePathsIssue] {
  guard graph_read_edge_identity_order_key(state.source, left) is Some(left) &&
    graph_read_edge_identity_order_key(state.source, right) is Some(right) else {
    return Err(TraversePathsInputUnavailable)
  }
  let (order, next) = graph_identity_compare_unit(
    left,
    right,
    state.comparison_unit,
  )
  state.comparison_unit = next
  Ok(order)
}

///|
fn compare_traversal_node_ids(
  state : TraversePathsState,
  _left : @value.CheckedValue,
  _right : @value.CheckedValue,
  left_index : Int,
  right_index : Int,
) -> Result[Int?, @value.KeyOrderIssue] {
  guard graph_read_node_identity_order_key(state.source, left_index)
    is Some(left) &&
    graph_read_node_identity_order_key(state.source, right_index) is Some(right) else {
    return Err(@value.InvalidKey)
  }
  let (order, next) = graph_identity_compare_unit(
    left,
    right,
    state.comparison_unit,
  )
  state.comparison_unit = next
  Ok(order)
}

///|
fn finish_traverse_path_comparison(
  state : TraversePathsState,
  order : Int,
) -> Unit {
  if order > 0 {
    let swap = state.next_frontier[state.sort_cursor - 1]
    state.next_frontier[state.sort_cursor - 1] = state.next_frontier[state.sort_cursor]
    state.next_frontier[state.sort_cursor] = swap
    state.sort_cursor -= 1
  } else {
    state.sort_index += 1
    state.sort_cursor = state.sort_index
  }
  state.compare_index = 0
  state.phase = SortPaths
}

///|
fn traverse_path_value_minimum_nodes(
  path : TraversalPath,
  field : @schema.Field,
) -> Int? {
  match field.name {
    @schema.Unqualified("node_ids") =>
      if path.nodes.length() > 2147483646 {
        None
      } else {
        Some(path.nodes.length() + 1)
      }
    @schema.Unqualified("edge_ids") =>
      if path.edges.length() > 2147483646 / 4 {
        None
      } else {
        Some(path.edges.length() * 4 + 1)
      }
    _ => None
  }
}

///|
fn traverse_path_row_minimum_nodes(
  state : TraversePathsState,
  path : TraversalPath,
) -> Int? {
  let mut total = 1
  for column in 0..<@schema.field_count(state.schema) {
    let field = @schema.field_at(state.schema, column).unwrap()
    let nodes = traverse_path_value_minimum_nodes(path, field).unwrap_or(1)
    if nodes > 2147483647 - total {
      return None
    }
    total += nodes
  }
  Some(total)
}

///|
fn reserve_traverse_path_value_nodes(
  state : TraversePathsState,
  nodes : Int,
) -> Bool {
  if nodes < 0 || nodes > state.value_nodes_remaining {
    false
  } else {
    state.value_nodes_remaining -= nodes
    true
  }
}

///|
fn traversal_neighbor(
  state : TraversePathsState,
  path : TraversalPath,
  occurrence : Int,
) -> (Int, Int)? {
  guard traverse_path_direction(state) is Some(direction) else { return None }
  let edge_count = graph_read_edge_count(state.source).unwrap_or(-1)
  let edge = if occurrence < edge_count {
    occurrence
  } else {
    occurrence - edge_count
  }
  guard edge >= 0 &&
    edge < edge_count &&
    graph_read_edge_endpoints(state.source, edge) is Some((from, to)) else {
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
  let definition = @carrier.graph_definition(state.graph)
  guard @lower.graph_traverse_hop_type_at(
      state.prepared,
      traverse_path_hop(state),
      index,
    )
    is Some(expected) &&
    graph_read_edge_definition(state.source, edge) is Some(element) &&
    @carrier.graph_edge_at(definition, element) is Some(element) else {
    return false
  }
  @carrier.graph_element_definition_has_label(
    @carrier.graph_edge_element(element),
    expected,
  )
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
    None => state.phase = BeginEdgePredicate
  }
}

///|
fn traverse_path_predicate_binding(
  state : TraversePathsState,
) -> (String, @execution.Value)? {
  let hop = traverse_path_hop(state)
  let fields = match state.predicate_kind {
    EdgePredicate => @lower.graph_traverse_hop_edge_fields(state.prepared, hop)
    NodePredicate => @lower.graph_traverse_hop_node_fields(state.prepared, hop)
  }
  guard fields is Some(fields) &&
    @carrier.field_at(fields, state.predicate_field) is Some(field) &&
    field.contract is Some(contract) else {
    return None
  }
  let value = match state.predicate_kind {
    EdgePredicate =>
      graph_read_edge_definition(state.source, state.candidate_edge).bind(definition => {
        @lower.graph_traverse_hop_edge_property_position(
          state.prepared,
          hop,
          definition,
          state.predicate_field,
        ).bind(index => {
          graph_read_edge_property(state.source, state.candidate_edge, index)
        })
      })
    NodePredicate =>
      graph_read_node_definition(state.source, state.candidate_node).bind(definition => {
        @lower.graph_traverse_hop_node_property_position(
          state.prepared,
          hop,
          definition,
          state.predicate_field,
        ).bind(index => {
          graph_read_node_property(state.source, state.candidate_node, index)
        })
      })
  }
  value.bind(checked => {
    @value.recheck_runtime_value(checked.value, contract, state.value_limits).map(value => {
        (@schema.reference_name(field.name), @execution.capture(value.value))
      },
    )
  })
}

///|
fn traverse_path_value(
  state : TraversePathsState,
  path : TraversalPath,
  field : @schema.Field,
) -> @value.CheckedValue? {
  match field.name {
    @schema.Unqualified("start_id") =>
      graph_read_node_identity(state.source, path.nodes[0]).bind(identity => {
        @value.recheck_runtime_value(
          identity.value,
          field.contract,
          state.value_limits,
        )
      })
    @schema.Unqualified("end_id") =>
      graph_read_node_identity(
        state.source,
        path.nodes[path.nodes.length() - 1],
      ).bind(identity => {
        @value.recheck_runtime_value(
          identity.value,
          field.contract,
          state.value_limits,
        )
      })
    @schema.Unqualified("hop_count") =>
      @value.checked_number_value(
        path.edges.length().to_double(),
        field.contract,
      )
    @schema.Unqualified("node_ids") | @schema.Unqualified("edge_ids") => None
    _ => None
  }
}

///|
fn traverse_node_value(
  state : TraversePathsState,
  field : @schema.Field,
) -> @value.CheckedValue? {
  let identity = match field.name {
    @schema.Unqualified("start_id") =>
      state.start_nodes
      .get(state.start_scan - 1)
      .bind(index => graph_read_node_identity(state.source, index))
    @schema.Unqualified("node_id") =>
      state.node_order
      .get(state.emit_index)
      .bind(index => graph_read_node_identity(state.source, index))
    @schema.Unqualified("depth") =>
      return state.node_order
        .get(state.emit_index)
        .bind(index => {
          state.node_depths
          .get(index)
          .bind(depth => {
            @value.checked_number_value(depth.to_double(), field.contract)
          })
        })
    _ => None
  }
  identity.bind(value => {
    @value.recheck_runtime_value(
      value.value,
      field.contract,
      state.value_limits,
    )
  })
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
    if !graph_read_available(state.source) ||
      !traverse_path_starts_available(state) {
      return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
    }
    if used >= state.control_work_remaining {
      return @bounded.Failed(TraversePathsWorkLimit, progress, used)
    }
    match state.phase {
      InitializeStartSelection =>
        if state.start_selected.length() <
          graph_read_node_count(state.source).unwrap_or(-1) {
          state.start_selected.push(false)
          used += 1
        } else {
          state.phase = ResolveStarts
        }
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
          guard @value.recheck_runtime_value(
              identity.value,
              @carrier.graph_identity(state.graph),
              state.value_limits,
            )
            is Some(identity) else {
            return @bounded.Failed(
              TraversePathsKeyOrder(@value.InvalidKey),
              progress,
              used,
            )
          }
          match graph_read_node_index(state.source, identity) {
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
          state.phase = CollectStarts
        }
      CollectStarts =>
        if state.start_scan < state.start_selected.length() {
          used += 1
          if state.start_selected[state.start_scan] {
            // The Boolean selection and canonical start indices overlap until
            // the scan is complete. Admit the new entry before appending it.
            if state.workspace_slots >= state.max_workspace_slots {
              return @bounded.Failed(
                TraversePathsWorkspaceLimit,
                progress,
                used,
              )
            }
            state.workspace_slots += 1
            state.workspace_peak = Int::max(
              state.workspace_peak,
              state.workspace_slots,
            )
            state.start_nodes.push(state.start_scan)
          }
          state.start_scan += 1
        } else {
          state.start_selected = []
          state.workspace_slots -= graph_read_node_count(state.source).unwrap_or(
            -1,
          )
          state.sort_index = 1
          state.sort_cursor = 1
          state.phase = SortStarts
        }
      SortStarts =>
        if state.sort_index >= state.start_nodes.length() {
          state.start_scan = 0
          state.phase = BeginStart
        } else if state.sort_cursor > 0 {
          used += 1
          guard graph_read_node_identity(
              state.source,
              state.start_nodes[state.sort_cursor - 1],
            )
            is Some(left) &&
            graph_read_node_identity(
              state.source,
              state.start_nodes[state.sort_cursor],
            )
            is Some(right) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          let order = match
            compare_traversal_node_ids(
              state,
              left,
              right,
              state.start_nodes[state.sort_cursor - 1],
              state.start_nodes[state.sort_cursor],
            ) {
            Ok(value) => value
            Err(issue) =>
              return @bounded.Failed(
                TraversePathsKeyOrder(issue),
                progress,
                used,
              )
          }
          if order is Some(order) {
            if order > 0 {
              let swap = state.start_nodes[state.sort_cursor - 1]
              state.start_nodes[state.sort_cursor - 1] = state.start_nodes[state.sort_cursor]
              state.start_nodes[state.sort_cursor] = swap
              state.sort_cursor -= 1
            } else {
              state.sort_index += 1
              state.sort_cursor = state.sort_index
            }
          }
        } else {
          state.sort_index += 1
          state.sort_cursor = state.sort_index
        }
      BeginStart =>
        if state.start_scan >= state.start_nodes.length() {
          state.phase = Finish
        } else if state.emit_nodes {
          state.phase = InitializeNodeDepths
        } else {
          state.phase = SeedStart
        }
      InitializeNodeDepths =>
        if state.node_depths.length() <
          graph_read_node_count(state.source).unwrap_or(-1) {
          used += 1
          if state.workspace_slots >= state.max_workspace_slots {
            return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
          }
          state.node_depths.push(-1)
          state.workspace_slots += 1
          state.workspace_peak = Int::max(
            state.workspace_peak,
            state.workspace_slots,
          )
        } else {
          state.phase = SeedStart
        }
      SeedStart => {
        if state.searched_paths >= state.max_paths {
          return @bounded.Failed(TraversePathsSearchLimit, progress, used)
        }
        let path = { nodes: [state.start_nodes[state.start_scan]], edges: [], }
        guard traversal_path_slots(path) is Some(slots) &&
          slots <= state.max_workspace_slots - state.workspace_slots else {
          return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
        }
        if !state.emit_nodes &&
          state.minimum_depth == 0 &&
          state.emitted >= state.max_rows {
          return @bounded.Failed(TraversePathsOutputLimit, progress, used)
        }
        state.workspace_slots += slots
        state.workspace_peak = Int::max(
          state.workspace_peak,
          state.workspace_slots,
        )
        state.frontier_slots = slots
        state.frontier.push(path)
        state.searched_paths += 1
        state.start_scan += 1
        state.depth = 0
        state.path_index = 0
        state.edge_occurrence = 0
        state.emit_index = 0
        state.phase = if state.minimum_depth == 0 {
          if state.emit_nodes {
            CollectNodeDepth
          } else {
            EmitPath
          }
        } else {
          BeginDepth
        }
      }
      BeginDepth =>
        if state.depth >= state.maximum_depth || state.frontier.is_empty() {
          state.workspace_slots -= state.frontier_slots
          state.frontier = []
          state.frontier_slots = 0
          if state.emit_nodes {
            state.sort_index = 1
            state.sort_cursor = 1
            state.phase = SortNodeOutput
          } else {
            state.phase = BeginStart
          }
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
            graph_read_edge_count(state.source).unwrap_or(-1) * 2
          } else {
            graph_read_edge_count(state.source).unwrap_or(-1)
          }
          if state.edge_occurrence >= occurrences {
            state.path_index += 1
            state.edge_occurrence = 0
          } else {
            used += 1
            let path = state.frontier[state.path_index]
            let occurrence = state.edge_occurrence
            state.edge_occurrence += 1
            if traversal_neighbor(state, path, occurrence) is Some((node, edge)) {
              state.candidate_node = node
              state.candidate_edge = edge
              state.member_index = 0
              state.phase = CheckCandidateNode
            }
          }
        }
      CheckCandidateNode => {
        guard state.frontier.get(state.path_index) is Some(path) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        let mode = @lower.graph_traverse_property_path_mode(state.prepared)
        let members = if mode == @graph_type.Trail {
          path.edges.length()
        } else {
          path.nodes.length()
        }
        if mode == @graph_type.Walk {
          used += 1
          prepare_traverse_path_candidate(
            state,
            state.candidate_edge,
            state.candidate_node,
          )
        } else if state.member_index < members {
          used += 1
          let repeated = if mode == @graph_type.Trail {
            path.edges[state.member_index] == state.candidate_edge
          } else {
            path.nodes[state.member_index] == state.candidate_node
          }
          if repeated {
            state.phase = ScanEdge
          } else {
            state.member_index += 1
          }
        } else {
          prepare_traverse_path_candidate(
            state,
            state.candidate_edge,
            state.candidate_node,
          )
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
          state.phase = BeginEdgePredicate
        } else if state.edge_type_index >= type_count {
          state.phase = ScanEdge
        }
      }
      BeginEdgePredicate => {
        let hop = traverse_path_hop(state)
        if @lower.graph_traverse_hop_edge_predicate(state.prepared, hop)
          is Some(_) {
          state.predicate_kind = EdgePredicate
          state.predicate_field = 0
          state.phase = PreparePredicate
        } else {
          state.phase = BeginNodePredicate
        }
      }
      BeginNodePredicate => {
        let hop = traverse_path_hop(state)
        if @lower.graph_traverse_hop_node_predicate(state.prepared, hop)
          is Some(_) {
          state.predicate_kind = NodePredicate
          state.predicate_field = 0
          state.phase = PreparePredicate
        } else {
          state.phase = AddPath
        }
      }
      PreparePredicate => {
        let hop = traverse_path_hop(state)
        let fields = match state.predicate_kind {
          EdgePredicate =>
            @lower.graph_traverse_hop_edge_fields(state.prepared, hop)
          NodePredicate =>
            @lower.graph_traverse_hop_node_fields(state.prepared, hop)
        }
        guard fields is Some(fields) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        if state.predicate_field < @carrier.field_count(fields) {
          used += 1
          if state.workspace_slots >= state.max_workspace_slots {
            return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
          }
          guard traverse_path_predicate_binding(state) is Some((name, value)) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
          state.predicate_slots += 1
          state.workspace_slots += 1
          state.workspace_peak = Int::max(
            state.workspace_peak,
            state.workspace_slots,
          )
        } else {
          let predicate = match state.predicate_kind {
            EdgePredicate =>
              @lower.graph_traverse_hop_edge_predicate(state.prepared, hop)
            NodePredicate =>
              @lower.graph_traverse_hop_node_predicate(state.prepared, hop)
          }
          guard predicate is Some(predicate) else {
            return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
          }
          match
            @execution.start_predicate_expression(
              predicate,
              state.predicate_input,
              state.predicate_work_remaining,
              state.value_limits.max_nodes,
              state.max_workspace_slots - state.workspace_slots,
            ) {
            Err(issue) =>
              return @bounded.Failed(
                TraversePathsPredicate(issue.kind),
                progress,
                used,
              )
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.predicate_starts.val += 1
              state.phase = EvaluatePredicate
            }
          }
        }
      }
      EvaluatePredicate => {
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
            state.workspace_slots -= state.predicate_slots
            state.predicate_slots = 0
            if !selected {
              state.phase = ScanEdge
            } else if state.predicate_kind == EdgePredicate {
              state.phase = BeginNodePredicate
            } else {
              state.phase = AddPath
            }
          }
        }
      }
      AddPath => {
        if state.searched_paths >= state.max_paths {
          return @bounded.Failed(TraversePathsSearchLimit, progress, used)
        }
        used += 1
        guard state.frontier.get(state.path_index) is Some(path) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        let next_slots = path.nodes.length() + path.edges.length() + 3
        if next_slots > state.max_workspace_slots - state.workspace_slots {
          return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
        }
        if !state.emit_nodes &&
          state.depth + 1 >= state.minimum_depth &&
          state.emitted + state.next_frontier.length() >= state.max_rows {
          return @bounded.Failed(TraversePathsOutputLimit, progress, used)
        }
        state.workspace_slots += next_slots
        state.workspace_peak = Int::max(
          state.workspace_peak,
          state.workspace_slots,
        )
        state.pending_slots = next_slots
        state.pending_nodes = []
        state.pending_edges = []
        state.copy_index = 0
        state.phase = CopyPathNodes
      }
      CopyPathNodes => {
        guard state.frontier.get(state.path_index) is Some(path) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        used += 1
        if state.copy_index < path.nodes.length() {
          state.pending_nodes.push(path.nodes[state.copy_index])
          state.copy_index += 1
        } else {
          state.pending_nodes.push(state.candidate_node)
          state.copy_index = 0
          state.phase = CopyPathEdges
        }
      }
      CopyPathEdges => {
        guard state.frontier.get(state.path_index) is Some(path) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        used += 1
        if state.copy_index < path.edges.length() {
          state.pending_edges.push(path.edges[state.copy_index])
          state.copy_index += 1
        } else {
          state.pending_edges.push(state.candidate_edge)
          state.phase = CommitPath
        }
      }
      CommitPath => {
        used += 1
        let nodes = state.pending_nodes
        let edges = state.pending_edges
        state.pending_nodes = []
        state.pending_edges = []
        state.next_frontier.push({ nodes, edges, })
        state.searched_paths += 1
        state.next_frontier_slots += state.pending_slots
        state.pending_slots = 0
        state.phase = ScanEdge
      }
      SortPaths =>
        if state.sort_index >= state.next_frontier.length() {
          state.workspace_slots -= state.frontier_slots
          state.frontier = state.next_frontier
          state.frontier_slots = state.next_frontier_slots
          state.next_frontier = []
          state.next_frontier_slots = 0
          state.depth += 1
          state.emit_index = 0
          state.phase = if state.depth >= state.minimum_depth {
            if state.emit_nodes {
              CollectNodeDepth
            } else {
              EmitPath
            }
          } else {
            BeginDepth
          }
        } else if state.sort_cursor > 0 {
          state.compare_index = 0
          state.phase = ComparePathNodes
        } else {
          state.sort_index += 1
          state.sort_cursor = state.sort_index
        }
      ComparePathNodes => {
        let left = state.next_frontier[state.sort_cursor - 1]
        let right = state.next_frontier[state.sort_cursor]
        if state.compare_index < left.nodes.length() &&
          state.compare_index < right.nodes.length() {
          used += 1
          guard graph_read_node_identity(
              state.source,
              left.nodes[state.compare_index],
            )
            is Some(left_id) &&
            graph_read_node_identity(
              state.source,
              right.nodes[state.compare_index],
            )
            is Some(right_id) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          let order = match
            compare_traversal_node_ids(
              state,
              left_id,
              right_id,
              left.nodes[state.compare_index],
              right.nodes[state.compare_index],
            ) {
            Ok(value) => value
            Err(issue) =>
              return @bounded.Failed(
                TraversePathsKeyOrder(issue),
                progress,
                used,
              )
          }
          if order is Some(order) {
            if order != 0 {
              finish_traverse_path_comparison(state, order)
            } else {
              state.compare_index += 1
            }
          }
        } else if left.nodes.length() != right.nodes.length() {
          finish_traverse_path_comparison(
            state,
            left.nodes.length() - right.nodes.length(),
          )
        } else {
          state.compare_index = 0
          state.phase = ComparePathEdges
        }
      }
      ComparePathEdges => {
        let left = state.next_frontier[state.sort_cursor - 1]
        let right = state.next_frontier[state.sort_cursor]
        if state.compare_index < left.edges.length() &&
          state.compare_index < right.edges.length() {
          used += 1
          let order = match
            compare_traversal_edges(
              state,
              left.edges[state.compare_index],
              right.edges[state.compare_index],
            ) {
            Ok(value) => value
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
          if order is Some(order) {
            if order != 0 {
              finish_traverse_path_comparison(state, order)
            } else {
              state.compare_index += 1
            }
          }
        } else {
          finish_traverse_path_comparison(
            state,
            left.edges.length() - right.edges.length(),
          )
        }
      }
      CollectNodeDepth =>
        if state.emit_index >= state.frontier.length() {
          state.phase = BeginDepth
        } else {
          used += 1
          guard state.frontier.get(state.emit_index) is Some(path) &&
            path.nodes.last() is Some(node) &&
            state.node_depths.get(node) is Some(depth) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          // This is output deduplication only. Never remove exploration states
          // because another eligible path has reached the same node.
          if depth < 0 {
            if state.node_order.length() >= state.max_rows - state.emitted {
              return @bounded.Failed(TraversePathsOutputLimit, progress, used)
            }
            if state.workspace_slots >= state.max_workspace_slots {
              return @bounded.Failed(
                TraversePathsWorkspaceLimit,
                progress,
                used,
              )
            }
            state.node_order.push(node)
            state.workspace_slots += 1
            state.workspace_peak = Int::max(
              state.workspace_peak,
              state.workspace_slots,
            )
            state.node_depths[node] = state.depth
          } else if state.depth < depth {
            state.node_depths[node] = state.depth
          }
          state.emit_index += 1
        }
      SortNodeOutput =>
        if state.sort_index >= state.node_order.length() {
          state.emit_index = 0
          state.phase = EmitNode
        } else if state.sort_cursor > 0 {
          used += 1
          let left_index = state.node_order[state.sort_cursor - 1]
          let right_index = state.node_order[state.sort_cursor]
          guard graph_read_node_identity(state.source, left_index) is Some(left) &&
            graph_read_node_identity(state.source, right_index) is Some(right) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          let order = match
            compare_traversal_node_ids(
              state, left, right, left_index, right_index,
            ) {
            Ok(value) => value
            Err(issue) =>
              return @bounded.Failed(
                TraversePathsKeyOrder(issue),
                progress,
                used,
              )
          }
          if order is Some(order) {
            if order > 0 {
              state.node_order[state.sort_cursor - 1] = right_index
              state.node_order[state.sort_cursor] = left_index
              state.sort_cursor -= 1
            } else {
              state.sort_index += 1
              state.sort_cursor = state.sort_index
            }
          }
        } else {
          state.sort_index += 1
          state.sort_cursor = state.sort_index
        }
      EmitNode =>
        if state.emit_index >= state.node_order.length() {
          state.workspace_slots -= state.node_depths.length() +
            state.node_order.length()
          state.node_depths.clear()
          state.node_order.clear()
          state.phase = BeginStart
        } else {
          state.column = 0
          state.values = []
          state.phase = ReadField
        }
      EmitPath =>
        if state.emit_index >= state.frontier.length() {
          state.phase = BeginDepth
        } else {
          guard state.frontier.get(state.emit_index) is Some(path) &&
            traverse_path_row_minimum_nodes(state, path) is Some(nodes) &&
            nodes <= state.value_limits.max_nodes else {
            return @bounded.Failed(TraversePathsOutputLimit, progress, used)
          }
          state.column = 0
          state.values = []
          state.phase = ReadField
        }
      ReadField =>
        if state.column < @schema.field_count(state.schema) {
          guard @schema.field_at(state.schema, state.column) is Some(field) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          match field.name {
            @schema.Unqualified("node_ids") => {
              guard state.frontier.get(state.emit_index) is Some(path) else {
                return @bounded.Failed(
                  TraversePathsInputUnavailable,
                  progress,
                  used,
                )
              }
              guard traverse_path_value_minimum_nodes(path, field)
                is Some(nodes) &&
                nodes <= state.value_limits.max_nodes else {
                return @bounded.Failed(TraversePathsOutputLimit, progress, used)
              }
              if nodes > state.max_workspace_slots - state.workspace_slots {
                return @bounded.Failed(
                  TraversePathsWorkspaceLimit,
                  progress,
                  used,
                )
              }
              guard @value.prepare_array_value(path.nodes.length())
                is Some(builder) else {
                return @bounded.Failed(TraversePathsOutputLimit, progress, used)
              }
              state.workspace_slots += nodes
              state.workspace_peak = Int::max(
                state.workspace_peak,
                state.workspace_slots,
              )
              state.row_value_slots += nodes
              state.value_items = Some(builder)
              state.value_item = 0
              state.value_nodes_remaining = state.value_limits.max_nodes
              guard reserve_traverse_path_value_nodes(state, 1) else {
                return @bounded.Failed(TraversePathsOutputLimit, progress, used)
              }
              state.phase = BuildNodeIds
            }
            @schema.Unqualified("edge_ids") => {
              guard state.frontier.get(state.emit_index) is Some(path) else {
                return @bounded.Failed(
                  TraversePathsInputUnavailable,
                  progress,
                  used,
                )
              }
              guard traverse_path_value_minimum_nodes(path, field)
                is Some(nodes) &&
                nodes <= state.value_limits.max_nodes else {
                return @bounded.Failed(TraversePathsOutputLimit, progress, used)
              }
              if nodes > state.max_workspace_slots - state.workspace_slots {
                return @bounded.Failed(
                  TraversePathsWorkspaceLimit,
                  progress,
                  used,
                )
              }
              guard @value.prepare_array_value(path.edges.length())
                is Some(builder) else {
                return @bounded.Failed(TraversePathsOutputLimit, progress, used)
              }
              state.workspace_slots += nodes
              state.workspace_peak = Int::max(
                state.workspace_peak,
                state.workspace_slots,
              )
              state.row_value_slots += nodes
              state.value_items = Some(builder)
              state.value_item = 0
              state.value_nodes_remaining = state.value_limits.max_nodes
              guard reserve_traverse_path_value_nodes(state, 1) else {
                return @bounded.Failed(TraversePathsOutputLimit, progress, used)
              }
              state.phase = BuildEdgeIds
            }
            _ => {
              used += 1
              let value = if state.emit_nodes {
                traverse_node_value(state, field)
              } else {
                state.frontier
                .get(state.emit_index)
                .bind(path => traverse_path_value(state, path, field))
              }
              guard value is Some(value) else {
                return @bounded.Failed(
                  TraversePathsInputUnavailable,
                  progress,
                  used,
                )
              }
              state.values.push(value)
              state.column += 1
            }
          }
        } else {
          state.phase = CommitRow
        }
      BuildNodeIds => {
        guard state.frontier.get(state.emit_index) is Some(path) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        if state.value_item == path.nodes.length() {
          state.phase = FinalizePathValue
        } else {
          used += 1
          guard reserve_traverse_path_value_nodes(state, 1) &&
            state.value_items is Some(builder) &&
            graph_read_node_identity(state.source, path.nodes[state.value_item])
            is Some(identity) &&
            @value.append_array_item(builder, identity.value) else {
            return @bounded.Failed(TraversePathsOutputLimit, progress, used)
          }
          state.value_item += 1
          state.value_item_attempts.val += 1
        }
      }
      BuildEdgeIds => {
        guard state.frontier.get(state.emit_index) is Some(path) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        if state.value_item == path.edges.length() {
          state.phase = FinalizePathValue
        } else {
          used += 1
          guard reserve_traverse_path_value_nodes(state, 4) &&
            state.value_items is Some(builder) &&
            path_edge_identity_value(state.source, path.edges[state.value_item])
            is Some(identity) &&
            @value.append_array_item(builder, identity) else {
            return @bounded.Failed(TraversePathsOutputLimit, progress, used)
          }
          state.value_item += 1
          state.value_item_attempts.val += 1
        }
      }
      FinalizePathValue => {
        used += 1
        guard state.value_items is Some(builder) &&
          @value.finish_array_value(builder) is Some(array) &&
          @schema.field_at(state.schema, state.column) is Some(field) &&
          @value.recheck_runtime_value(
            array,
            field.contract,
            state.value_limits,
          )
          is Some(value) else {
          return @bounded.Failed(TraversePathsOutputLimit, progress, used)
        }
        state.values.push(value)
        state.value_items = None
        state.value_item = 0
        state.value_nodes_remaining = 0
        state.column += 1
        state.phase = ReadField
      }
      CommitRow => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.workspace_slots -= state.row_value_slots
            state.row_value_slots = 0
            state.values = []
            state.emitted += 1
            state.emit_index += 1
            progress += 1
            state.phase = if state.emit_nodes { EmitNode } else { EmitPath }
          }
          Err(issue) =>
            return @bounded.Failed(TraversePathsOutput(issue), progress, used)
        }
      }
      Finish => {
        used += 1
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
  state.control_work_remaining -= used
  @bounded.Continue(progress, used)
}

///|
fn cleanup_traverse_paths_state(state : TraversePathsState) -> Bool {
  if state.predicate_execution is Some(execution) {
    @execution.cancel_predicate_expression(execution) |> ignore
    state.predicate_execution = None
  }
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.start_selected.clear()
  state.start_nodes.clear()
  state.frontier.clear()
  state.next_frontier.clear()
  state.pending_nodes.clear()
  state.pending_edges.clear()
  state.node_depths.clear()
  state.node_order.clear()
  state.values.clear()
  state.value_items = None
  state.predicate_input.clear()
  state.predicate_slots = 0
  state.comparison_unit = 0
  state.workspace_slots = 0
  true
}

///|
fn traverse_paths_private_entries(state : TraversePathsState) -> Int {
  let mut count = state.start_selected.length() +
    state.start_nodes.length() +
    state.pending_nodes.length() +
    state.pending_edges.length() +
    state.node_depths.length() +
    state.node_order.length() +
    state.values.length() +
    state.predicate_slots
  for path in state.frontier {
    count += path.nodes.length() + path.edges.length() + 1
  }
  for path in state.next_frontier {
    count += path.nodes.length() + path.edges.length() + 1
  }
  if state.value_items is Some(_) {
    count += 1
  }
  count
}

///|
fn start_traverse_paths_read(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  source : GraphReadSource,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
  max_paths? : Int = max_workspace_slots,
) -> Result[TraversePathsExecution, TraversePathsIssue] {
  let owner = @lower.sequence_owner(sequence)
  if limits.max_work < 0 {
    return Err(TraversePathsWorkLimit)
  }
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
    bounds is Some((minimum, maximum)) &&
    minimum <= 2147483647L &&
    maximum <= 2147483647L &&
    hop_count > 0 &&
    @lower.graph_traverse_hop_direction(prepared, 0) is Some(direction) &&
    (match source {
      Accumulated(_) => false
      Stored(read) =>
        @graph.producer_read_matches_operation_input(read, owner, step, 0)
      Viewed(view) =>
        @lifecycle.producer_read_reference_matches_operation_input(
          @lifecycle.producer_view_read_reference(view),
          owner,
          step,
          0,
        )
    }) &&
    graph_read_node_count(source) is Some(_) &&
    (
      direction != @graph_type.Both ||
      graph_read_edge_count(source).unwrap_or(2147483647) <= 1073741823
    ) &&
    max_rows >= 0 &&
    max_paths >= 0 &&
    max_workspace_slots >= 0 else {
    return Err(InvalidTraversePathsKernel)
  }
  for hop in 0..<hop_count {
    guard @lower.graph_traverse_hop_direction(prepared, hop) is Some(_) else {
      return Err(InvalidTraversePathsKernel)
    }
  }
  guard @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_input_target(node, 0) is Some(target) &&
    @lower.preparation_carrier_at(@lower.bound_preparation(owner), target)
    is Some(@carrier.GraphValue(graph)) else {
    return Err(InvalidTraversePathsKernel)
  }
  let starts = match @lower.graph_traverse_start_relation_field(prepared) {
    None => {
      guard @lower.graph_traverse_start_id_count(prepared) > 0 else {
        return Err(InvalidTraversePathsKernel)
      }
      LiteralPathStarts
    }
    Some(field) => {
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
  let value_item_attempts = Ref(0)
  let predicate_starts = Ref(0)
  let port_result = match source {
    Accumulated(_) => return Err(InvalidTraversePathsKernel)
    Stored(read) if @lifecycle.producer_read_reference_matches_input(
        @graph.producer_read_carrier_reference(read),
        owner,
        0,
      ) => {
      let retained_inputs = [
        @execution.trusted_output_carrier_input(
          @graph.producer_read_carrier_reference(read),
        ),
      ]
      for input in inputs {
        retained_inputs.push(@execution.trusted_output_relation_input(input))
      }
      @execution.prepare_trusted_output_port_with_inputs(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs=retained_inputs,
      )
    }
    Stored(_) =>
      @execution.prepare_trusted_output_port(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs~,
      )
    Viewed(view) => {
      guard inputs.length() + 1 == @lower.node_input_count(node) else {
        @execution.cancel_admitted_output(output) |> ignore
        return Err(InvalidTraversePathsKernel)
      }
      let retained_inputs = [
        @execution.trusted_output_carrier_input(
          @lifecycle.producer_view_read_reference(view),
        ),
      ]
      for port in 1..<@lower.node_input_count(node) {
        let mut found = None
        for input in inputs {
          if @execution.producer_read_matches_operation_input(
              input, owner, step, port,
            ) {
            found = Some(input)
            break
          }
        }
        guard found is Some(input) else {
          @execution.cancel_admitted_output(output) |> ignore
          return Err(InvalidTraversePathsKernel)
        }
        retained_inputs.push(@execution.trusted_output_relation_input(input))
      }
      @execution.prepare_trusted_output_port_with_inputs(
        preparation,
        @pipeline.Step(step),
        max_entries,
        max_name_bytes,
        fn(_) { if live.val { rows.val } else { None } },
        inputs=retained_inputs,
      )
    }
  }
  let port = match port_result {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(TraversePathsCompletion(issue))
    }
  }
  let node_count = graph_read_node_count(source).unwrap_or(-1)
  if node_count > max_workspace_slots {
    @execution.cancel_admitted_output(output) |> ignore
    return Err(TraversePathsWorkspaceLimit)
  }
  let state : TraversePathsState = {
    source,
    graph,
    schema: @lower.graph_traverse_output_schema(prepared),
    prepared,
    starts,
    direction,
    minimum_depth: minimum.to_int(),
    maximum_depth: maximum.to_int(),
    max_rows,
    max_paths,
    searched_paths: 0,
    emit_nodes: !@lower.graph_traverse_emits_paths(prepared),
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
    phase: InitializeStartSelection,
    start_scan: 0,
    start_selected: [],
    start_nodes: [],
    sort_index: 0,
    sort_cursor: 0,
    compare_index: 0,
    comparison_unit: 0,
    member_index: 0,
    copy_index: 0,
    frontier: [],
    next_frontier: [],
    frontier_slots: 0,
    next_frontier_slots: 0,
    pending_nodes: [],
    pending_edges: [],
    pending_slots: 0,
    depth: 0,
    path_index: 0,
    edge_occurrence: 0,
    candidate_node: -1,
    candidate_edge: -1,
    edge_type_index: 0,
    predicate_kind: EdgePredicate,
    predicate_field: 0,
    predicate_slots: 0,
    predicate_input: Map([]),
    predicate_execution: None,
    predicate_work_remaining: limits.max_work,
    emit_index: 0,
    column: 0,
    values: [],
    value_items: None,
    value_item: 0,
    value_nodes_remaining: 0,
    row_value_slots: 0,
    value_item_attempts,
    predicate_starts,
    emitted: 0,
    node_depths: [],
    node_order: [],
    workspace_slots: node_count,
    workspace_peak: node_count,
    control_work_remaining: limits.max_work,
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
  Ok({
    session,
    token: Some(token),
    accepted,
    private_entries: fn() { traverse_paths_private_entries(state) },
    workspace_usage: fn() { (state.workspace_slots, state.workspace_peak) },
    value_item_attempts,
    predicate_starts,
  })
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
  max_paths? : Int = max_workspace_slots,
) -> Result[TraversePathsExecution, TraversePathsIssue] {
  start_traverse_paths_read(
    control,
    preparation,
    sequence,
    step,
    Stored(input),
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
    max_paths~,
  )
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
fn traverse_paths_private_entry_count(value : TraversePathsExecution) -> Int {
  (value.private_entries)()
}

///|
fn traverse_paths_workspace_usage(value : TraversePathsExecution) -> (Int, Int) {
  (value.workspace_usage)()
}

///|
fn traverse_paths_value_item_attempts(value : TraversePathsExecution) -> Int {
  value.value_item_attempts.val
}

///|
fn traverse_paths_predicate_starts(value : TraversePathsExecution) -> Int {
  value.predicate_starts.val
}

///|
fn cleanup_traverse_paths(
  value : TraversePathsExecution,
) -> Result[Bool, TraversePathsIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    TraversePathsExecutionIssue(issue)
  })
}
