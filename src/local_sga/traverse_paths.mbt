///|
priv struct TraversalPath {
  nodes : Array[Int]
  edges : Array[Int]
  cost : ShortestCost?
}

///|
priv enum TraversePathStarts {
  LiteralPathStarts
  RelationPathStarts(@execution.ProducerRead, Int)
  PredicatePathStarts
}

///|
priv enum TraversePathsPhase {
  AdmitShortestWeights
  InitializeTargetSelection
  InitializeStartSelection
  ResolveStarts
  RecheckStartInput
  RecheckStartIdentity
  LookupStart
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
  RecheckPredicateBinding
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
  CommitBoundedRow
  Finish
  SelectShortestPath
  LocateShortestWinner
  CompareShortestWinner
  CopyWinnerNodes
  CopyWinnerEdges
  CheckShortestSelected
  SortShortestOutput
  CompareShortestOutput
}

///|
priv enum TraversePredicateKind {
  EdgePredicate
  NodePredicate
  StartPredicate
  TargetPredicate
} derive(Eq)

///|
priv struct TraversePathsState {
  source : GraphReadSource
  graph : @carrier.Graph
  schema : @schema.Schema
  prepared : @lower.PreparedGraphTraverse
  starts : TraversePathStarts
  targets : TraversePathStarts?
  mut selecting_target : Bool
  target_selected : Array[Bool]
  shortest : @graph_type.CheckedShortest?
  winners : Array[ShortestCandidate]
  mut winner_index : Int
  mut shortest_comparison : ShortestComparison?
  mut shortest_publishing : Bool
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
  mut start_recheck : @value.RecheckCursor?
  mut start_recheck_slots : Int
  mut start_identity : @value.CheckedValue?
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
  mut predicate_recheck : @value.RecheckCursor?
  mut predicate_binding_name : String?
  mut predicate_recheck_slots : Int
  mut predicate_execution : @execution.PredicateExpressionExecution?
  mut predicate_work_remaining : Int
  mut emit_index : Int
  mut column : Int
  mut values : Array[@value.CheckedValue]
  mut row_values : Array[@value.Value]
  mut output_row : @execution.AdmittedOutputRowCursor?
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
  control_work_limit : Int
  mut charged_control_work : Int
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
  shortest_winners : () -> Int
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
  TraversePathsShortest(ShortestCandidateIssue)
} derive(Eq, Debug)

///|
fn traverse_path_start_count(state : TraversePathsState) -> Int {
  match
    (if state.selecting_target { state.targets.unwrap() } else { state.starts }) {
    LiteralPathStarts =>
      if state.selecting_target {
        @graph_type.selector_id_count(
          @lower.graph_traverse_target_selector(state.prepared).unwrap(),
        )
      } else {
        @lower.graph_traverse_start_id_count(state.prepared)
      }
    RelationPathStarts(input, _) => @execution.producer_read_row_count(input)
    PredicatePathStarts => graph_read_node_count(state.source).unwrap_or(0)
  }
}

///|
fn traverse_path_start_recheck(
  state : TraversePathsState,
  index : Int,
) -> @value.RecheckCursor? {
  match
    (if state.selecting_target { state.targets.unwrap() } else { state.starts }) {
    LiteralPathStarts => {
      let identity = if state.selecting_target {
        @lower.graph_traverse_target_selector(state.prepared).bind(selector => {
          @graph_type.selector_id_at(selector, index)
        })
      } else {
        @lower.graph_traverse_start_id_at(state.prepared, index)
      }
      identity.bind(value => {
        @value.start_recheck_runtime_value(
          value.value,
          @carrier.graph_identity(state.graph),
          state.value_limits,
        )
      })
    }
    RelationPathStarts(input, column) =>
      @execution.start_producer_read_cell_recheck(
        input,
        index,
        column,
        state.value_limits,
      )
    PredicatePathStarts => None
  }
}

///|
fn traverse_path_starts_available(state : TraversePathsState) -> Bool {
  let available = fn(starts : TraversePathStarts) {
    match starts {
      LiteralPathStarts | PredicatePathStarts => true
      RelationPathStarts(input, _) => @execution.producer_read_available(input)
    }
  }
  available(state.starts) && state.targets.map(available).unwrap_or(true)
}

///|
fn traversal_path_slots(value : TraversalPath) -> Int? {
  let nodes = value.nodes.length()
  let edges = value.edges.length()
  let extra = if value.cost is Some(_) { 2 } else { 1 }
  if nodes > 2147483647 - edges - extra {
    None
  } else {
    Some(nodes + edges + extra)
  }
}

///|
fn traverse_output_path(state : TraversePathsState) -> TraversalPath? {
  if state.shortest_publishing {
    state.winners.get(state.emit_index).map(winner => winner.path)
  } else {
    state.frontier.get(state.emit_index)
  }
}

///|
fn traverse_paths_state_workspace_usage(
  state : TraversePathsState,
) -> (Int, Int) {
  let extra = match state.output_row {
    Some(row) => @execution.admitted_output_row_workspace_usage(row)
    None => (0, 0)
  }
  (
    state.workspace_slots + extra.0,
    Int::max(state.workspace_peak, state.workspace_slots + extra.1),
  )
}

///|
fn retain_shortest_candidate(state : TraversePathsState) -> Bool {
  let path = state.frontier[state.emit_index]
  let slots = traversal_path_slots(path).unwrap() + 1
  if slots > state.max_workspace_slots - state.workspace_slots {
    return false
  }
  state.pending_slots = slots
  state.workspace_slots += slots
  state.workspace_peak = Int::max(state.workspace_peak, state.workspace_slots)
  state.pending_nodes = []
  state.pending_edges = []
  state.copy_index = 0
  state.phase = CopyWinnerNodes
  true
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
) -> (String, @value.CheckedValue, @contract.Contract)? {
  let hop = traverse_path_hop(state)
  let fields = match state.predicate_kind {
    EdgePredicate => @lower.graph_traverse_hop_edge_fields(state.prepared, hop)
    NodePredicate => @lower.graph_traverse_hop_node_fields(state.prepared, hop)
    StartPredicate => @lower.graph_traverse_start_fields(state.prepared)
    TargetPredicate =>
      @lower.graph_traverse_target_selector(state.prepared).bind(
        @graph_type.selector_fields,
      )
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
    StartPredicate =>
      graph_read_node_definition(state.source, state.candidate_node).bind(definition => {
        @lower.graph_traverse_start_property_position(
          state.prepared,
          definition,
          state.predicate_field,
        ).bind(index => {
          graph_read_node_property(state.source, state.candidate_node, index)
        })
      })
    TargetPredicate =>
      graph_read_node_definition(state.source, state.candidate_node).bind(definition => {
        @lower.graph_traverse_target_selector(state.prepared).bind(selector => {
          @graph_type.selector_property_position(
            selector,
            definition,
            state.predicate_field,
          ).bind(index => {
            graph_read_node_property(state.source, state.candidate_node, index)
          })
        })
      })
  }
  value.map(checked => (@schema.reference_name(field.name), checked, contract))
}

///|
fn traverse_path_value(
  state : TraversePathsState,
  path : TraversalPath,
  field : @schema.Field,
) -> @value.CheckedValue? {
  match field.name {
    @schema.Unqualified("start_id") | @schema.Unqualified("source_id") =>
      graph_read_node_identity(state.source, path.nodes[0]).bind(identity => {
        @value.recheck_runtime_value(
          identity.value,
          field.contract,
          state.value_limits,
        )
      })
    @schema.Unqualified("end_id") | @schema.Unqualified("target_id") =>
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
    @schema.Unqualified("total_cost") =>
      match path.cost {
        Some(FiniteShortestCost(cost)) =>
          @value.checked_number_value(cost, field.contract)
        _ => None
      }
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
fn traverse_uses_output_cursor(state : TraversePathsState) -> Bool {
  state.shortest is Some(_) || @lower.graph_traverse_is_reach(state.prepared)
}

///|
fn charge_traverse_control_work(
  state : TraversePathsState,
  current : Int,
) -> Bool {
  if !traverse_uses_output_cursor(state) {
    return true
  }
  let spent = state.control_work_limit - state.control_work_remaining + current
  guard state.output is Some(output) &&
    @execution.admitted_output_charge_control_work(
      output,
      spent - state.charged_control_work,
    ) else {
    return false
  }
  state.charged_control_work = spent
  true
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
      AdmitShortestWeights => {
        let shortest = state.shortest.unwrap()
        if state.member_index ==
          graph_read_edge_count(state.source).unwrap_or(-1) {
          state.member_index = 0
          state.phase = InitializeTargetSelection
        } else {
          used += 1
          match
            shortest_edge_weight(state.source, shortest, state.member_index) {
            Err(issue) =>
              return @bounded.Failed(
                TraversePathsShortest(issue),
                progress,
                used,
              )
            Ok(_) => state.member_index += 1
          }
        }
      }
      InitializeTargetSelection =>
        if state.target_selected.length() <
          graph_read_node_count(state.source).unwrap_or(-1) {
          state.target_selected.push(false)
          used += 1
        } else {
          state.selecting_target = true
          state.phase = ResolveStarts
        }
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
          if (if state.selecting_target {
              state.targets.unwrap()
            } else {
              state.starts
            })
            is PredicatePathStarts {
            state.candidate_node = state.start_scan
            state.predicate_kind = if state.selecting_target {
              TargetPredicate
            } else {
              StartPredicate
            }
            state.predicate_field = 0
            state.phase = PreparePredicate
            continue
          }
          // Root, cursor and initial continuation are reserved before setup.
          // Literal identities borrow the checked selector; Relation starts
          // first retain the exact receiving-column validation as well.
          if 3 > state.max_workspace_slots - state.workspace_slots {
            return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
          }
          guard traverse_path_start_recheck(state, state.start_scan)
            is Some(cursor) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          state.start_recheck = Some(cursor)
          state.start_recheck_slots = 3
          state.workspace_slots += 3
          state.workspace_peak = Int::max(
            state.workspace_peak,
            state.workspace_slots,
          )
          state.phase = if (if state.selecting_target {
              state.targets.unwrap()
            } else {
              state.starts
            })
            is RelationPathStarts(_, _) {
            RecheckStartInput
          } else {
            RecheckStartIdentity
          }
        } else {
          state.start_scan = 0
          if state.selecting_target {
            state.selecting_target = false
            state.phase = InitializeStartSelection
          } else {
            state.phase = CollectStarts
          }
        }
      RecheckStartInput | RecheckStartIdentity => {
        used += 1
        guard state.start_recheck is Some(cursor) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        let frames = @value.recheck_pending_frames(cursor)
        let available = state.max_workspace_slots -
          (state.workspace_slots - state.start_recheck_slots)
        // Each poll can grow the continuation stack by one. Reserve it before
        // advancing, then release the unused growth without dropping input.
        if available < 3 || frames > available - 3 {
          return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
        }
        let slots = 3 + frames
        state.workspace_slots += slots - state.start_recheck_slots
        state.start_recheck_slots = slots
        state.workspace_peak = Int::max(
          state.workspace_peak,
          state.workspace_slots,
        )
        match @value.advance_recheck_runtime_value(cursor) {
          @value.RecheckContinue => {
            let retained = 2 + @value.recheck_pending_frames(cursor)
            state.workspace_slots -= state.start_recheck_slots - retained
            state.start_recheck_slots = retained
          }
          @value.RecheckFailed =>
            return @bounded.Failed(
              if state.phase is RecheckStartInput {
                TraversePathsInputUnavailable
              } else {
                TraversePathsKeyOrder(@value.InvalidKey)
              },
              progress,
              used,
            )
          @value.RecheckComplete(identity, _, _) => {
            state.start_recheck = None
            if state.phase is RecheckStartInput {
              guard @value.start_recheck_runtime_value(
                  identity.value,
                  @carrier.graph_identity(state.graph),
                  state.value_limits,
                )
                is Some(next) else {
                return @bounded.Failed(
                  TraversePathsKeyOrder(@value.InvalidKey),
                  progress,
                  used,
                )
              }
              state.start_recheck = Some(next)
              state.workspace_slots -= state.start_recheck_slots - 3
              state.start_recheck_slots = 3
              state.phase = RecheckStartIdentity
            } else {
              state.start_identity = Some(identity)
              state.workspace_slots -= state.start_recheck_slots - 1
              state.start_recheck_slots = 1
              state.phase = LookupStart
            }
          }
        }
      }
      LookupStart => {
        used += 1
        guard state.start_identity is Some(identity) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
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
          Ok(Some(node)) =>
            if state.selecting_target {
              state.target_selected[node] = true
            } else {
              state.start_selected[node] = true
            }
        }
        state.start_identity = None
        state.workspace_slots -= state.start_recheck_slots
        state.start_recheck_slots = 0
        state.start_scan += 1
        state.phase = ResolveStarts
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
          if state.shortest is Some(_) {
            state.winner_index = 0
            state.phase = CheckShortestSelected
          } else {
            state.phase = Finish
          }
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
        let path = {
          nodes: [state.start_nodes[state.start_scan]],
          edges: [],
          cost: state.shortest.map(_ => FiniteShortestCost(0.0)),
        }
        guard traversal_path_slots(path) is Some(slots) &&
          slots <= state.max_workspace_slots - state.workspace_slots else {
          return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
        }
        if state.shortest is None &&
          !state.emit_nodes &&
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
          } else if state.shortest is Some(_) {
            SelectShortestPath
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
        let mode = @lower.graph_traverse_graph_path_mode(state.prepared)
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
          StartPredicate => @lower.graph_traverse_start_fields(state.prepared)
          TargetPredicate =>
            @lower.graph_traverse_target_selector(state.prepared).bind(
              @graph_type.selector_fields,
            )
        }
        guard fields is Some(fields) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        if state.predicate_field < @carrier.field_count(fields) {
          used += 1
          // Binding root, cursor and its initial frame. Borrowed property
          // payload remains owned by the live Graph, not a copied value.
          if 3 > state.max_workspace_slots - state.workspace_slots {
            return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
          }
          guard traverse_path_predicate_binding(state)
            is Some((name, value, contract)) &&
            @value.start_recheck_runtime_value(
              value.value,
              contract,
              state.value_limits,
            )
            is Some(cursor) else {
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          }
          state.predicate_binding_name = Some(name)
          state.predicate_recheck = Some(cursor)
          state.predicate_recheck_slots = 3
          state.workspace_slots += 3
          state.workspace_peak = Int::max(
            state.workspace_peak,
            state.workspace_slots,
          )
          state.phase = RecheckPredicateBinding
        } else {
          let predicate = match state.predicate_kind {
            EdgePredicate =>
              @lower.graph_traverse_hop_edge_predicate(state.prepared, hop)
            NodePredicate =>
              @lower.graph_traverse_hop_node_predicate(state.prepared, hop)
            StartPredicate =>
              @lower.graph_traverse_start_predicate(state.prepared)
            TargetPredicate =>
              @lower.graph_traverse_target_predicate(state.prepared)
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
      RecheckPredicateBinding => {
        used += 1
        guard state.predicate_recheck is Some(cursor) &&
          state.predicate_binding_name is Some(name) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        // A frame poll pops one continuation and pushes at most two. Reserve
        // growth before advancing so a nested value never exceeds the limit.
        let frames = @value.recheck_pending_frames(cursor)
        let available = state.max_workspace_slots -
          (state.workspace_slots - state.predicate_recheck_slots)
        if available < 3 || frames > available - 3 {
          return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
        }
        let slots = 3 + frames
        let added = slots - state.predicate_recheck_slots
        state.workspace_slots += added
        state.predicate_recheck_slots = slots
        state.workspace_peak = Int::max(
          state.workspace_peak,
          state.workspace_slots,
        )
        match @value.advance_recheck_runtime_value(cursor) {
          @value.RecheckContinue => {
            let retained = 2 + @value.recheck_pending_frames(cursor)
            state.workspace_slots -= state.predicate_recheck_slots - retained
            state.predicate_recheck_slots = retained
          }
          @value.RecheckFailed =>
            return @bounded.Failed(
              TraversePathsInputUnavailable,
              progress,
              used,
            )
          @value.RecheckComplete(value, _, _) => {
            state.predicate_input[name] = @execution.capture(value.value)
            state.workspace_slots -= state.predicate_recheck_slots - 1
            state.predicate_recheck_slots = 0
            state.predicate_recheck = None
            state.predicate_binding_name = None
            state.predicate_field += 1
            state.predicate_slots += 1
            state.phase = PreparePredicate
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
            if state.predicate_kind == StartPredicate ||
              state.predicate_kind == TargetPredicate {
              if selected {
                if state.selecting_target {
                  state.target_selected[state.start_scan] = true
                } else {
                  state.start_selected[state.start_scan] = true
                }
              }
              state.start_scan += 1
              state.phase = ResolveStarts
            } else if !selected {
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
        let next_slots = path.nodes.length() +
          path.edges.length() +
          3 +
          (if state.shortest is Some(_) { 1 } else { 0 })
        if next_slots > state.max_workspace_slots - state.workspace_slots {
          return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
        }
        if state.shortest is None &&
          !state.emit_nodes &&
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
        let cost = if state.shortest is Some(shortest) {
          let weight = match
            shortest_edge_weight(state.source, shortest, state.candidate_edge) {
            Ok(weight) => weight
            Err(issue) =>
              return @bounded.Failed(
                TraversePathsShortest(issue),
                progress,
                used,
              )
          }
          match
            shortest_cost_add(
              state.frontier[state.path_index].cost.unwrap(),
              weight,
            ) {
            Ok(cost) => Some(cost)
            Err(issue) =>
              return @bounded.Failed(
                TraversePathsShortest(issue),
                progress,
                used,
              )
          }
        } else {
          None
        }
        state.next_frontier.push({ nodes, edges, cost, })
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
            } else if state.shortest is Some(_) {
              SelectShortestPath
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
        if state.emit_index >=
          (if state.shortest_publishing {
            state.winners.length()
          } else {
            state.frontier.length()
          }) {
          state.phase = if state.shortest_publishing {
            Finish
          } else {
            BeginDepth
          }
        } else {
          guard traverse_output_path(state) is Some(path) &&
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
              guard traverse_output_path(state) is Some(path) else {
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
              guard traverse_output_path(state) is Some(path) else {
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
              if traverse_uses_output_cursor(state) {
                let value = if state.emit_nodes {
                  match field.name {
                    @schema.Unqualified("start_id") =>
                      state.start_nodes
                      .get(state.start_scan - 1)
                      .bind(node => graph_read_node_identity(state.source, node))
                      .map(value => value.value)
                    @schema.Unqualified("node_id") =>
                      state.node_order
                      .get(state.emit_index)
                      .bind(node => graph_read_node_identity(state.source, node))
                      .map(value => value.value)
                    @schema.Unqualified("depth") =>
                      state.node_order
                      .get(state.emit_index)
                      .bind(node => state.node_depths.get(node))
                      .bind(depth => @value.number_value(depth.to_double()))
                    _ => None
                  }
                } else {
                  guard traverse_output_path(state) is Some(path) else {
                    return @bounded.Failed(
                      TraversePathsInputUnavailable,
                      progress,
                      used,
                    )
                  }
                  match field.name {
                    @schema.Unqualified("source_id") =>
                      graph_read_node_identity(state.source, path.nodes[0]).map(value => {
                          value.value
                        },
                      )
                    @schema.Unqualified("target_id") =>
                      graph_read_node_identity(
                        state.source,
                        path.nodes.last().unwrap(),
                      ).map(value => value.value)
                    @schema.Unqualified("hop_count") =>
                      @value.number_value(path.edges.length().to_double())
                    @schema.Unqualified("total_cost") =>
                      match path.cost {
                        Some(FiniteShortestCost(cost)) =>
                          @value.number_value(cost)
                        _ => None
                      }
                    _ => None
                  }
                }
                guard value is Some(value) else {
                  return @bounded.Failed(
                    TraversePathsInputUnavailable,
                    progress,
                    used,
                  )
                }
                state.row_values.push(value)
                state.column += 1
                continue
              }
              let value = if state.emit_nodes {
                traverse_node_value(state, field)
              } else {
                traverse_output_path(state).bind(path => {
                  traverse_path_value(state, path, field)
                })
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
        guard traverse_output_path(state) is Some(path) else {
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
        guard traverse_output_path(state) is Some(path) else {
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
          @value.finish_array_value(builder) is Some(array) else {
          return @bounded.Failed(TraversePathsOutputLimit, progress, used)
        }
        if state.shortest is Some(_) {
          // Keep raw immutable material private. The existing row cursor
          // performs both nested contract admission and logical measurement.
          state.row_values.push(array)
        } else {
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            @value.recheck_runtime_value(
              array,
              field.contract,
              state.value_limits,
            )
            is Some(value) else {
            return @bounded.Failed(TraversePathsOutputLimit, progress, used)
          }
          state.values.push(value)
        }
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
        if traverse_uses_output_cursor(state) {
          // The shared row cursor exclusively owns the output while yielding.
          // Charge control before acquiring it and after it releases that lock;
          // never give a later row a fresh operation-wide work budget.
          if !charge_traverse_control_work(state, used) {
            return @bounded.Failed(TraversePathsWorkLimit, progress, used)
          }
          let remaining = state.max_workspace_slots - state.workspace_slots
          match
            @execution.start_admitted_output_row(output, remaining, column => {
              state.row_values.get(column)
            }) {
            Ok(row) => {
              state.output_row = Some(row)
              state.phase = CommitBoundedRow
            }
            Err(@execution.OutputRowWorkspace) =>
              return @bounded.Failed(
                TraversePathsWorkspaceLimit,
                progress,
                used,
              )
            Err(@execution.OutputRowCapture(issue)) =>
              return @bounded.Failed(TraversePathsOutput(issue), progress, used)
          }
          continue
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
      CommitBoundedRow => {
        used += 1
        guard state.output_row is Some(row) else {
          return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
        }
        let result = @execution.advance_admitted_output_row(row)
        state.workspace_peak = traverse_paths_state_workspace_usage(state).1
        match result {
          Ok(false) => ()
          Ok(true) => {
            @execution.cleanup_admitted_output_row(row) |> ignore
            state.output_row = None
            if !charge_traverse_control_work(state, used) {
              return @bounded.Failed(TraversePathsWorkLimit, progress, used)
            }
            state.workspace_slots -= state.row_value_slots
            state.row_value_slots = 0
            state.row_values = []
            state.emitted += 1
            state.emit_index += 1
            progress += 1
            state.phase = if state.emit_nodes { EmitNode } else { EmitPath }
          }
          Err(@execution.OutputRowWorkspace) =>
            return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
          Err(@execution.OutputRowCapture(issue)) =>
            return @bounded.Failed(TraversePathsOutput(issue), progress, used)
        }
      }
      SelectShortestPath =>
        if state.emit_index == state.frontier.length() {
          state.phase = BeginDepth
        } else {
          used += 1
          let path = state.frontier[state.emit_index]
          if state.target_selected[path.nodes.last().unwrap()] {
            state.winner_index = 0
            state.phase = LocateShortestWinner
          } else {
            state.emit_index += 1
          }
        }
      LocateShortestWinner => {
        let path = state.frontier[state.emit_index]
        if state.winner_index == state.winners.length() {
          if state.winners.length() >= state.max_rows {
            return @bounded.Failed(TraversePathsOutputLimit, progress, used)
          }
          if !retain_shortest_candidate(state) {
            return @bounded.Failed(TraversePathsWorkspaceLimit, progress, used)
          }
        } else {
          used += 1
          let winner = state.winners[state.winner_index]
          let same = match
            @graph_type.shortest_selection(state.shortest.unwrap()) {
            @graph_type.EachPair =>
              winner.path.nodes[0] == path.nodes[0] &&
              winner.path.nodes.last() == path.nodes.last()
            @graph_type.NearestPerSource =>
              winner.path.nodes[0] == path.nodes[0]
            @graph_type.NearestPair => true
          }
          if !same {
            state.winner_index += 1
          } else {
            // Only fixed cursor storage is added; its immutable path references
            // borrow existing frontier/winner allocations, not another copy.
            if 8 > state.max_workspace_slots - state.workspace_slots {
              return @bounded.Failed(
                TraversePathsWorkspaceLimit,
                progress,
                used,
              )
            }
            state.workspace_slots += 8
            state.workspace_peak = Int::max(
              state.workspace_peak,
              state.workspace_slots,
            )
            let comparison = prepare_shortest_comparison(
              state.source,
              { path, cost: path.cost.unwrap(), },
              winner,
              state.control_work_remaining - used,
            ).unwrap()
            state.shortest_comparison = Some(comparison)
            state.phase = CompareShortestWinner
          }
        }
      }
      CompareShortestWinner => {
        let comparison = state.shortest_comparison.unwrap()
        match advance_shortest_comparison(comparison, 1) {
          ShortestComparisonContinue(work) => used += work
          ShortestComparisonFailed(issue, work) => {
            used += work
            return @bounded.Failed(TraversePathsShortest(issue), progress, used)
          }
          ShortestComparisonComplete(order, work) => {
            used += work
            cleanup_shortest_comparison(comparison)
            state.shortest_comparison = None
            state.workspace_slots -= 8
            if order < 0 {
              if !retain_shortest_candidate(state) {
                return @bounded.Failed(
                  TraversePathsWorkspaceLimit,
                  progress,
                  used,
                )
              }
            } else {
              state.emit_index += 1
              state.phase = SelectShortestPath
            }
          }
        }
      }
      CopyWinnerNodes => {
        let path = state.frontier[state.emit_index]
        if state.copy_index == path.nodes.length() {
          state.copy_index = 0
          state.phase = CopyWinnerEdges
        } else {
          used += 1
          state.pending_nodes.push(path.nodes[state.copy_index])
          state.copy_index += 1
        }
      }
      CopyWinnerEdges => {
        let original = state.frontier[state.emit_index]
        used += 1
        if state.copy_index == original.edges.length() {
          let path = {
            nodes: state.pending_nodes,
            edges: state.pending_edges,
            cost: original.cost,
          }
          let winner = { path, cost: path.cost.unwrap(), }
          if state.winner_index == state.winners.length() {
            state.winners.push(winner)
          } else {
            state.workspace_slots -= traversal_path_slots(
                state.winners[state.winner_index].path,
              ).unwrap() +
              1
            state.winners[state.winner_index] = winner
          }
          state.pending_nodes = []
          state.pending_edges = []
          state.pending_slots = 0
          state.emit_index += 1
          state.phase = SelectShortestPath
        } else {
          state.pending_edges.push(original.edges[state.copy_index])
          state.copy_index += 1
        }
      }
      CheckShortestSelected =>
        if state.winner_index == state.winners.length() {
          state.sort_index = 1
          state.sort_cursor = 1
          state.phase = SortShortestOutput
        } else {
          used += 1
          // No row has been appended yet, including finite winners from other
          // pairs. Selected overrange rejects the entire occurrence atomically.
          if state.winners[state.winner_index].cost is OverrangeShortestCost {
            return @bounded.Failed(
              TraversePathsShortest(SelectedShortestOverrange),
              progress,
              used,
            )
          }
          state.winner_index += 1
        }
      SortShortestOutput =>
        if state.sort_index == state.winners.length() ||
          state.winners.is_empty() {
          state.shortest_publishing = true
          state.emit_index = 0
          state.phase = EmitPath
        } else if state.sort_cursor == 0 {
          state.sort_index += 1
          state.sort_cursor = state.sort_index
        } else {
          state.compare_index = 0
          state.comparison_unit = 0
          state.phase = CompareShortestOutput
        }
      CompareShortestOutput => {
        used += 1
        let left = state.winners[state.sort_cursor - 1].path
        let right = state.winners[state.sort_cursor].path
        let left_node = if state.compare_index == 0 {
          left.nodes[0]
        } else {
          left.nodes.last().unwrap()
        }
        let right_node = if state.compare_index == 0 {
          right.nodes[0]
        } else {
          right.nodes.last().unwrap()
        }
        guard graph_read_node_identity_order_key(state.source, left_node)
          is Some(left_key) &&
          graph_read_node_identity_order_key(state.source, right_node)
          is Some(right_key) else {
          return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
        }
        let (order, next) = graph_identity_compare_unit(
          left_key,
          right_key,
          state.comparison_unit,
        )
        state.comparison_unit = next
        if order is Some(order) {
          if order == 0 && state.compare_index == 0 {
            state.compare_index = 1
          } else {
            if order > 0 {
              let swap = state.winners[state.sort_cursor - 1]
              state.winners[state.sort_cursor - 1] = state.winners[state.sort_cursor]
              state.winners[state.sort_cursor] = swap
              state.sort_cursor -= 1
            } else {
              state.sort_index += 1
              state.sort_cursor = state.sort_index
            }
            state.phase = SortShortestOutput
          }
        }
      }
      Finish => {
        used += 1
        if !charge_traverse_control_work(state, used) {
          return @bounded.Failed(TraversePathsWorkLimit, progress, used)
        }
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
  if state.start_recheck is Some(cursor) {
    @value.cancel_recheck_runtime_value(cursor)
    state.start_recheck = None
  }
  state.start_identity = None
  state.start_recheck_slots = 0
  if state.predicate_recheck is Some(cursor) {
    @value.cancel_recheck_runtime_value(cursor)
    state.predicate_recheck = None
  }
  state.predicate_binding_name = None
  state.predicate_recheck_slots = 0
  if state.output_row is Some(row) {
    @execution.cleanup_admitted_output_row(row) |> ignore
    state.output_row = None
  }
  if state.shortest_comparison is Some(comparison) {
    cleanup_shortest_comparison(comparison)
    state.shortest_comparison = None
  }
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
  state.target_selected.clear()
  state.winners.clear()
  state.start_nodes.clear()
  state.frontier.clear()
  state.next_frontier.clear()
  state.pending_nodes.clear()
  state.pending_edges.clear()
  state.node_depths.clear()
  state.node_order.clear()
  state.values.clear()
  state.row_values.clear()
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
    state.target_selected.length() +
    state.start_nodes.length() +
    state.pending_nodes.length() +
    state.pending_edges.length() +
    state.node_depths.length() +
    state.node_order.length() +
    state.values.length() +
    state.row_values.length() +
    traverse_paths_state_workspace_usage(state).0 -
    state.workspace_slots +
    state.predicate_slots +
    state.predicate_recheck_slots +
    state.start_recheck_slots
  for path in state.frontier {
    count += path.nodes.length() + path.edges.length() + 1
  }
  for path in state.next_frontier {
    count += path.nodes.length() + path.edges.length() + 1
  }
  for winner in state.winners {
    count += traversal_path_slots(winner.path).unwrap() + 1
  }
  if state.shortest_comparison is Some(_) {
    count += 8
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
  let shortest = @lower.graph_traverse_shortest(prepared)
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
    None =>
      if @lower.graph_traverse_start_predicate(prepared) is Some(_) {
        PredicatePathStarts
      } else {
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
  let targets = match @lower.graph_traverse_target_selector(prepared) {
    None => None
    Some(selector) =>
      Some(
        match @graph_type.selector_form(selector) {
          @graph_type.ExplicitIds => LiteralPathStarts
          @graph_type.NodeWhere => PredicatePathStarts
          @graph_type.RelationIds(field~, ..) => {
            let port = if starts is RelationPathStarts(_, _) { 2 } else { 1 }
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
              return Err(InvalidTraversePathsKernel)
            }
            let schema = @execution.producer_read_schema(input)
            let mut column = -1
            for index in 0..<@schema.field_count(schema) {
              if @schema.field_at(schema, index).map(value => value.name) ==
                Some(field) {
                column = index
                break
              }
            }
            guard column >= 0 else { return Err(InvalidTraversePathsKernel) }
            RelationPathStarts(input, column)
          }
        },
      )
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
  let target_slots = if shortest is Some(_) { node_count } else { 0 }
  if node_count > max_workspace_slots ||
    target_slots > max_workspace_slots - node_count {
    @execution.cancel_admitted_output(output) |> ignore
    return Err(TraversePathsWorkspaceLimit)
  }
  let state : TraversePathsState = {
    source,
    graph,
    schema: @lower.graph_traverse_output_schema(prepared),
    prepared,
    starts,
    targets,
    selecting_target: false,
    target_selected: [],
    shortest,
    winners: [],
    winner_index: 0,
    shortest_comparison: None,
    shortest_publishing: false,
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
    phase: if shortest is Some(shortest) {
      if @graph_type.shortest_weight(shortest) is Some(_) {
        AdmitShortestWeights
      } else {
        InitializeTargetSelection
      }
    } else {
      InitializeStartSelection
    },
    start_scan: 0,
    start_selected: [],
    start_recheck: None,
    start_recheck_slots: 0,
    start_identity: None,
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
    predicate_recheck: None,
    predicate_binding_name: None,
    predicate_recheck_slots: 0,
    predicate_execution: None,
    predicate_work_remaining: limits.max_work,
    emit_index: 0,
    column: 0,
    values: [],
    row_values: [],
    output_row: None,
    value_items: None,
    value_item: 0,
    value_nodes_remaining: 0,
    row_value_slots: 0,
    value_item_attempts,
    predicate_starts,
    emitted: 0,
    node_depths: [],
    node_order: [],
    workspace_slots: node_count + target_slots,
    workspace_peak: node_count + target_slots,
    control_work_remaining: limits.max_work,
    control_work_limit: limits.max_work,
    charged_control_work: 0,
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
    workspace_usage: fn() { traverse_paths_state_workspace_usage(state) },
    value_item_attempts,
    predicate_starts,
    shortest_winners: fn() { state.winners.length() },
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
fn traverse_paths_shortest_winner_count(value : TraversePathsExecution) -> Int {
  (value.shortest_winners)()
}

///|
fn cleanup_traverse_paths(
  value : TraversePathsExecution,
) -> Result[Bool, TraversePathsIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    TraversePathsExecutionIssue(issue)
  })
}
