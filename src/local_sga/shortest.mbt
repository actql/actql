///|
priv enum ShortestPhase {
  InitializeEndpointSelection
  ResolveSourceEndpoints
  ResolveTargetEndpoints
  PrepareEndpointPredicate
  EvaluateEndpointPredicate
  CollectSourceEndpoints
  CollectTargetEndpoints
  InitializeEndpointScratch
  PrepareEndpointSort
  PrepareEndpointMerge
  MergeEndpointNodes
  CopyEndpointNodes
  InitializeNodes
  FinishOffsets
  ScanDegrees
  ScanDegreeTypes
  BuildOffsets
  InitializeEdges
  CopyCursors
  FillEdges
  FillEdgeTypes
  InitializeSortScratch
  PrepareSortNode
  PrepareSortMerge
  MergeEdges
  CopySortedEdges
  ValidateWeight
  PreparePair
  ResetSearch
  StartSearch
  ScanNeighbor
  ExploreWeightedPath
  CompareWeightedNodes
  CompareWeightedEdges
  CopyWeightedBest
  BacktrackWeightedPath
  FinishWeightedPair
  PreparePath
  ReconstructPath
  ReverseNodes
  ReverseEdges
  SelectNearestPath
  ReadField
  BuildNodeIds
  BuildEdgeIds
  FinalizePathValue
  CommitRow
  FinishPair
  FinishNearestSource
  Finish
}

///|
priv enum ShortestEndpoints {
  SingleShortestEndpoint(@value.CheckedValue)
  LiteralShortestEndpoints
  RelationShortestEndpoints(@execution.ProducerRead, Int)
  PredicateShortestEndpoints(@lower.Expression)
}

///|
priv struct ShortestState {
  input : @graph.ProducerRead
  source : @storage.Storage
  schema : @schema.Schema
  value_limits : @value.Limits
  prepared : @lower.PreparedGraphShortest
  direction : @graph_type.Direction
  selection : @graph_type.PathSelection
  sources : ShortestEndpoints
  targets : ShortestEndpoints
  max_hops : Int
  output_guard : Int64?
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : ShortestPhase
  mut index : Int
  mut source_node : Int
  mut target_node : Int
  mut source_pair : Int
  mut target_pair : Int
  mut endpoint_side : @schema.Side
  mut queue_index : Int
  mut neighbor_index : Int
  mut path_cursor : Int
  mut reverse_index : Int
  mut row_column : Int
  mut edge_type_index : Int
  mut sort_node : Int
  mut sort_width : Int
  mut sort_left : Int
  mut sort_middle : Int
  mut sort_right : Int
  mut sort_left_at : Int
  mut sort_right_at : Int
  mut sort_merge_at : Int
  mut sort_copy_at : Int
  mut has_path : Bool
  mut best_path : Bool
  mut best_source_node : Int
  mut best_target_node : Int
  weight_property : Int?
  mut path_cost : Double
  mut path_overrange : Bool
  mut pair_best : Bool
  mut pair_best_cost : Double
  mut pair_best_overrange : Bool
  mut best_path_cost : Double
  mut best_path_overrange : Bool
  mut weighted_copy_at : Int
  mut weighted_compare_at : Int
  mut key_component : Int
  mut key_comparison : @value.BoundedKeyComparison?
  degree : Array[Int]
  start : Array[Int]
  cursor : Array[Int]
  neighbor : Array[Int]
  edge : Array[Int]
  sort_neighbor : Array[Int]
  sort_edge : Array[Int]
  source_selected : Array[Bool]
  target_selected : Array[Bool]
  source_nodes : Array[Int]
  target_nodes : Array[Int]
  endpoint_scratch : Array[Int?]
  graph : @carrier.Graph
  predicate_workspace : Int
  mut predicate_work_remaining : Int
  predicate_input : Map[String, @execution.Value]
  mut predicate_execution : @execution.PredicateExpressionExecution?
  mut predicate_field : Int
  depth : Array[Int]
  predecessor : Array[Int]
  predecessor_edge : Array[Int]
  queue : Array[Int]
  edge_weight : Array[Double]
  visited : Array[Bool]
  path_next : Array[Int]
  path_costs : Array[Double]
  path_overranges : Array[Bool]
  mut path_nodes : Array[Int]
  mut path_edges : Array[Int]
  mut pair_best_nodes : Array[Int]
  mut pair_best_edges : Array[Int]
  mut best_path_nodes : Array[Int]
  mut best_path_edges : Array[Int]
  mut emitted_rows : Int64
  mut values : Array[@value.CheckedValue]
  mut value_items : @value.ArrayBuilder?
  mut value_item : Int
  mut value_nodes_remaining : Int
  value_item_attempts : Ref[Int]
}

///|
struct ShortestExecution {
  session : @bounded.Session[
    ShortestState,
    @execution.CompletedOutput,
    ShortestIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  value_item_attempts : Ref[Int]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum ShortestPoll {
  ShortestContinue(progress~ : Int64, work~ : Int64)
  ShortestComplete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  ShortestFailed(ShortestIssue, progress~ : Int64, work~ : Int64)
  ShortestStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum ShortestIssue {
  UnsupportedShortestKernel
  ShortestInputUnavailable
  ShortestEndpointMissing
  ShortestOutputLimit
  ShortestWorkspaceLimit
  ShortestInvalidWeight
  ShortestCostOverrange
  ShortestPredicate(@execution.EvalIssueKind)
  ShortestKeyOrder(@value.KeyOrderIssue)
  ShortestStorage(@storage.Issue)
  ShortestOutput(@execution.CaptureIssue)
  ShortestCompletion(@execution.TrustedOutputIssue)
  ShortestExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn checked_shortest_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn checked_shortest_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn shortest_workspace(
  nodes : Int,
  edges : Int,
  both : Bool,
  retain_best_path : Bool,
  weighted : Bool,
) -> Int? {
  let directed_edges = if both {
    checked_shortest_multiply(edges, 2)
  } else {
    Some(edges)
  }
  guard directed_edges is Some(directed_edges) &&
    checked_shortest_multiply(nodes, if weighted { 19 } else { 14 })
    is Some(node_slots) &&
    checked_shortest_multiply(directed_edges, if weighted { 6 } else { 4 })
    is Some(edge_slots) &&
    checked_shortest_add(node_slots, edge_slots) is Some(base) &&
    checked_shortest_multiply(nodes, if retain_best_path { 2 } else { 0 })
    is Some(best_slots) &&
    checked_shortest_add(base, best_slots) is Some(graph_slots) &&
    checked_shortest_add(nodes, 1) is Some(node_value_slots) &&
    checked_shortest_multiply(edges, 4) is Some(edge_value_items) &&
    checked_shortest_add(edge_value_items, 1) is Some(edge_value_slots) &&
    checked_shortest_add(
      graph_slots,
      if node_value_slots > edge_value_slots {
        node_value_slots
      } else {
        edge_value_slots
      },
    )
    is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn shortest_reserve_value_nodes(state : ShortestState, nodes : Int) -> Bool {
  if nodes < 0 || nodes > state.value_nodes_remaining {
    false
  } else {
    state.value_nodes_remaining -= nodes
    true
  }
}

///|
fn shortest_weight_property(
  graph : @carrier.Graph,
  name : @schema.FieldName,
) -> Int? {
  let properties = @carrier.graph_edge_properties(graph)
  for index in 0..<@carrier.field_count(properties) {
    if @carrier.field_at(properties, index).unwrap().name == name {
      return Some(index)
    }
  }
  None
}

///|
fn shortest_endpoint_count(state : ShortestState, side : @schema.Side) -> Int {
  let endpoints = if side == @schema.Left {
    state.sources
  } else {
    state.targets
  }
  match endpoints {
    SingleShortestEndpoint(_) => 1
    LiteralShortestEndpoints =>
      @lower.graph_shortest_endpoint_id_count(state.prepared, side)
    RelationShortestEndpoints(input, _) =>
      @execution.producer_read_row_count(input)
    PredicateShortestEndpoints(_) => @storage.node_count(state.source)
  }
}

///|
fn shortest_endpoint_at(
  state : ShortestState,
  side : @schema.Side,
  index : Int,
) -> @value.CheckedValue? {
  let endpoints = if side == @schema.Left {
    state.sources
  } else {
    state.targets
  }
  match endpoints {
    SingleShortestEndpoint(value) => if index == 0 { Some(value) } else { None }
    LiteralShortestEndpoints =>
      @lower.graph_shortest_endpoint_id_at(state.prepared, side, index)
    RelationShortestEndpoints(input, column) =>
      @execution.producer_read_checked_cell(
        input,
        index,
        column,
        state.value_limits,
      )
    PredicateShortestEndpoints(_) => None
  }
}

///|
fn shortest_endpoint_definition(
  state : ShortestState,
  side : @schema.Side,
) -> ShortestEndpoints {
  if side == @schema.Left {
    state.sources
  } else {
    state.targets
  }
}

///|
fn shortest_endpoints_available(endpoints : ShortestEndpoints) -> Bool {
  match endpoints {
    RelationShortestEndpoints(input, _) =>
      @execution.producer_read_available(input)
    _ => true
  }
}

///|
fn shortest_endpoint_selection(state : ShortestState) -> Array[Bool] {
  if state.endpoint_side == @schema.Left {
    state.source_selected
  } else {
    state.target_selected
  }
}

///|
fn shortest_retain_nearest_path(state : ShortestState) -> Unit {
  if !state.best_path ||
    shortest_cost_is_better(
      state.path_cost,
      state.path_overrange,
      state.path_edges.length(),
      state.best_path_cost,
      state.best_path_overrange,
      state.best_path_edges.length(),
    ) {
    let previous_nodes = state.best_path_nodes
    let previous_edges = state.best_path_edges
    state.best_path_nodes = state.path_nodes
    state.best_path_edges = state.path_edges
    state.path_nodes = previous_nodes
    state.path_edges = previous_edges
    state.path_nodes.clear()
    state.path_edges.clear()
    state.best_source_node = state.source_node
    state.best_target_node = state.target_node
    state.best_path_cost = state.path_cost
    state.best_path_overrange = state.path_overrange
    state.best_path = true
  }
}

///|
fn shortest_cost_is_better(
  candidate : Double,
  candidate_overrange : Bool,
  candidate_hops : Int,
  current : Double,
  current_overrange : Bool,
  current_hops : Int,
) -> Bool {
  if candidate_overrange != current_overrange {
    return !candidate_overrange
  }
  if !candidate_overrange && candidate != current {
    return candidate < current
  }
  candidate_hops < current_hops
}

///|
fn shortest_prepare_nearest_output(state : ShortestState) -> Bool {
  if !state.best_path {
    return false
  }
  let scratch_nodes = state.path_nodes
  let scratch_edges = state.path_edges
  state.path_nodes = state.best_path_nodes
  state.path_edges = state.best_path_edges
  state.best_path_nodes = scratch_nodes
  state.best_path_edges = scratch_edges
  state.best_path_nodes.clear()
  state.best_path_edges.clear()
  state.source_node = state.best_source_node
  state.target_node = state.best_target_node
  state.path_cost = state.best_path_cost
  state.path_overrange = state.best_path_overrange
  state.best_path = false
  state.row_column = 0
  state.values = []
  state.phase = ReadField
  true
}

///|
fn shortest_compare_edge_identities_step(
  state : ShortestState,
  left : Int,
  right : Int,
) -> Result[Int?, ShortestIssue] {
  guard @storage.edge_endpoints(state.source, left)
    is Some((left_source, left_target)) &&
    @storage.edge_endpoints(state.source, right)
    is Some((right_source, right_target)) &&
    @storage.node_identity(state.source, left_source) is Some(left_source_id) &&
    @storage.node_identity(state.source, right_source) is Some(right_source_id) &&
    @storage.node_identity(state.source, left_target) is Some(left_target_id) &&
    @storage.node_identity(state.source, right_target) is Some(right_target_id) &&
    @storage.edge_label(state.source, left) is Some(left_label) &&
    @storage.edge_label(state.source, right) is Some(right_label) else {
    return Err(ShortestInputUnavailable)
  }
  let pair = match state.key_component {
    0 => Some((left_source_id, right_source_id))
    1 => Some((left_target_id, right_target_id))
    2 =>
      match (left_label, right_label) {
        (None, None) => return shortest_finish_key_component(state, 0, true)
        (None, Some(_)) => return shortest_finish_key_component(state, -1, true)
        (Some(_), None) => return shortest_finish_key_component(state, 1, true)
        (Some(a), Some(b)) => Some((a, b))
      }
    _ => None
  }
  guard pair is Some((a, b)) else { return Err(ShortestInputUnavailable) }
  match shortest_compare_values_step(state, a, b) {
    Ok(Some(order)) =>
      shortest_finish_key_component(state, order, state.key_component == 2)
    other => other
  }
}

///|
fn shortest_begin_weighted_copy(state : ShortestState) -> Unit {
  state.pair_best_nodes.clear()
  state.pair_best_edges.clear()
  state.weighted_copy_at = 0
  state.phase = CopyWeightedBest
}

///|
fn shortest_begin_endpoint_side(
  state : ShortestState,
  side : @schema.Side,
) -> Unit {
  state.endpoint_side = side
  state.index = 0
  state.predicate_field = 0
  state.predicate_input.clear()
  state.phase = match shortest_endpoint_definition(state, side) {
    PredicateShortestEndpoints(_) => PrepareEndpointPredicate
    _ =>
      if side == @schema.Left {
        ResolveSourceEndpoints
      } else {
        ResolveTargetEndpoints
      }
  }
}

///|
fn shortest_finish_endpoint_side(state : ShortestState) -> Unit {
  if state.endpoint_side == @schema.Left {
    shortest_begin_endpoint_side(state, @schema.Right)
  } else {
    state.index = 0
    state.phase = CollectSourceEndpoints
  }
}

///|
fn shortest_endpoint_nodes(
  state : ShortestState,
  side : @schema.Side,
) -> Array[Int] {
  if side == @schema.Left {
    state.source_nodes
  } else {
    state.target_nodes
  }
}

///|
fn shortest_compare_nodes_step(
  state : ShortestState,
  left : Int,
  right : Int,
) -> Result[Int?, ShortestIssue] {
  guard @storage.node_identity(state.source, left) is Some(left_id) &&
    @storage.node_identity(state.source, right) is Some(right_id) else {
    return Err(ShortestInputUnavailable)
  }
  shortest_compare_values_step(state, left_id, right_id)
}

///|
fn shortest_prepare_endpoint_merge(state : ShortestState) -> Unit {
  let nodes = shortest_endpoint_nodes(state, state.endpoint_side)
  let end = nodes.length()
  state.sort_middle = Int::min(state.sort_left + state.sort_width, end)
  state.sort_right = Int::min(state.sort_middle + state.sort_width, end)
  state.sort_left_at = state.sort_left
  state.sort_right_at = state.sort_middle
  state.sort_merge_at = state.sort_left
  state.phase = MergeEndpointNodes
}

///|
fn shortest_emit_endpoint_node(state : ShortestState, take_left : Bool) -> Unit {
  let nodes = shortest_endpoint_nodes(state, state.endpoint_side)
  let at = if take_left {
    let at = state.sort_left_at
    state.sort_left_at += 1
    at
  } else {
    let at = state.sort_right_at
    state.sort_right_at += 1
    at
  }
  state.endpoint_scratch[state.sort_merge_at] = Some(nodes[at])
  state.sort_merge_at += 1
}

///|
fn shortest_compare_values_step(
  state : ShortestState,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
) -> Result[Int?, ShortestIssue] {
  let comparison = match state.key_comparison {
    Some(value) => value
    None => {
      let value = match @value.start_bounded_key_comparison(left, right) {
        Ok(value) => value
        Err(issue) => return Err(ShortestKeyOrder(issue))
      }
      state.key_comparison = Some(value)
      value
    }
  }
  match @value.advance_bounded_key_comparison(comparison, 1) {
    Ok(@value.KeyComparisonContinue(_)) => Ok(None)
    Ok(@value.KeyComparisonComplete(order~, ..)) => {
      state.key_comparison = None
      Ok(Some(order))
    }
    Err(issue) => {
      state.key_comparison = None
      Err(ShortestKeyOrder(issue))
    }
  }
}

///|
fn shortest_finish_key_component(
  state : ShortestState,
  order : Int,
  last : Bool,
) -> Result[Int?, ShortestIssue] {
  if order != 0 || last {
    state.key_component = 0
    Ok(Some(order))
  } else {
    state.key_component += 1
    Ok(None)
  }
}

///|
fn shortest_compare_edges_step(
  state : ShortestState,
  left_at : Int,
  right_at : Int,
) -> Result[Int?, ShortestIssue] {
  let left_node = state.neighbor[left_at]
  let right_node = state.neighbor[right_at]
  guard @storage.node_identity(state.source, left_node) is Some(left_id) &&
    @storage.node_identity(state.source, right_node) is Some(right_id) else {
    return Err(ShortestInputUnavailable)
  }
  if state.key_component == 0 {
    return match shortest_compare_values_step(state, left_id, right_id) {
      Ok(Some(order)) => shortest_finish_key_component(state, order, false)
      other => other
    }
  }
  let left_edge = state.edge[left_at]
  let right_edge = state.edge[right_at]
  guard @storage.edge_endpoints(state.source, left_edge)
    is Some((left_source, left_target)) &&
    @storage.edge_endpoints(state.source, right_edge)
    is Some((right_source, right_target)) &&
    @storage.node_identity(state.source, left_source) is Some(left_source_id) &&
    @storage.node_identity(state.source, right_source) is Some(right_source_id) &&
    @storage.node_identity(state.source, left_target) is Some(left_target_id) &&
    @storage.node_identity(state.source, right_target) is Some(right_target_id) &&
    @storage.edge_label(state.source, left_edge) is Some(left_label) &&
    @storage.edge_label(state.source, right_edge) is Some(right_label) else {
    return Err(ShortestInputUnavailable)
  }
  let pair = match state.key_component {
    1 => Some((left_source_id, right_source_id))
    2 => Some((left_target_id, right_target_id))
    3 =>
      match (left_label, right_label) {
        (None, None) => return shortest_finish_key_component(state, 0, true)
        (None, Some(_)) => return shortest_finish_key_component(state, -1, true)
        (Some(_), None) => return shortest_finish_key_component(state, 1, true)
        (Some(a), Some(b)) => Some((a, b))
      }
    _ => None
  }
  guard pair is Some((a, b)) else { return Err(ShortestInputUnavailable) }
  match shortest_compare_values_step(state, a, b) {
    Ok(Some(order)) =>
      shortest_finish_key_component(state, order, state.key_component == 3)
    other => other
  }
}

///|
fn shortest_emit_sorted_edge(state : ShortestState, take_left : Bool) -> Unit {
  let at = if take_left {
    let at = state.sort_left_at
    state.sort_left_at += 1
    at
  } else {
    let at = state.sort_right_at
    state.sort_right_at += 1
    at
  }
  state.sort_neighbor[state.sort_merge_at] = state.neighbor[at]
  state.sort_edge[state.sort_merge_at] = state.edge[at]
  state.sort_merge_at += 1
}

///|
fn shortest_edge_count(state : ShortestState) -> Int {
  if state.direction == @graph_type.Both {
    @storage.edge_count(state.source) * 2
  } else {
    @storage.edge_count(state.source)
  }
}

///|
fn shortest_edge_type_count(state : ShortestState) -> Int? {
  @lower.graph_shortest_type_count(state.prepared)
}

///|
fn shortest_edge_type_matches(
  state : ShortestState,
  edge : Int,
  type_index : Int,
) -> Bool {
  guard @lower.graph_shortest_type_at(state.prepared, type_index)
    is Some(expected) else {
    return false
  }
  match @storage.edge_label(state.source, edge) {
    Some(Some({ value: @value.Text(actual), .. })) => actual == expected
    _ => false
  }
}

///|
fn shortest_oriented_endpoints(
  state : ShortestState,
  occurrence : Int,
) -> (Int, Int, Int)? {
  let count = @storage.edge_count(state.source)
  let edge = if occurrence < count { occurrence } else { occurrence - count }
  guard edge >= 0 &&
    edge < count &&
    @storage.edge_endpoints(state.source, edge) is Some((source, target)) else {
    return None
  }
  if state.direction == @graph_type.Incoming || occurrence >= count {
    Some((target, source, edge))
  } else {
    Some((source, target, edge))
  }
}

///|
fn shortest_path_value(
  state : ShortestState,
  field : @schema.Field,
) -> @value.CheckedValue? {
  match field.name {
    @schema.Unqualified("source_id") =>
      @storage.node_identity(state.source, state.source_node).bind(identity => {
        @value.recheck_runtime_value(
          identity.value,
          field.contract,
          state.value_limits,
        )
      })
    @schema.Unqualified("target_id") =>
      @storage.node_identity(state.source, state.target_node).bind(identity => {
        @value.recheck_runtime_value(
          identity.value,
          field.contract,
          state.value_limits,
        )
      })
    @schema.Unqualified("total_cost") =>
      if state.path_overrange {
        None
      } else {
        @value.checked_number_value(state.path_cost, field.contract)
      }
    @schema.Unqualified("hop_count") =>
      @value.checked_number_value(
        state.path_edges.length().to_double(),
        field.contract,
      )
    @schema.Unqualified("node_ids") | @schema.Unqualified("edge_ids") => None
    _ => None
  }
}

///|
fn shortest_path_value_minimum_nodes(
  state : ShortestState,
  field : @schema.Field,
) -> Int? {
  match field.name {
    @schema.Unqualified("node_ids") =>
      checked_shortest_add(1, state.path_nodes.length())
    @schema.Unqualified("edge_ids") =>
      checked_shortest_multiply(state.path_edges.length(), 4).bind(count => {
        checked_shortest_add(1, count)
      })
    _ => None
  }
}

///|
fn shortest_step(
  state : ShortestState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, ShortestIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@graph.producer_read_available(state.input) ||
      !shortest_endpoints_available(state.sources) ||
      !shortest_endpoints_available(state.targets) {
      return @bounded.Failed(ShortestInputUnavailable, progress, used)
    }
    match state.phase {
      InitializeEndpointSelection =>
        if state.index < @storage.node_count(state.source) {
          state.source_selected.push(false)
          state.target_selected.push(false)
          state.index += 1
          used += 1
        } else {
          shortest_begin_endpoint_side(state, @schema.Left)
        }
      ResolveSourceEndpoints =>
        if state.index < shortest_endpoint_count(state, @schema.Left) {
          used += 1
          guard shortest_endpoint_at(state, @schema.Left, state.index)
            is Some(identity) else {
            return @bounded.Failed(UnsupportedShortestKernel, progress, used)
          }
          guard @value.recheck_runtime_value(
              identity.value,
              @carrier.graph_identity(state.graph),
              state.value_limits,
            )
            is Some(identity) else {
            return @bounded.Failed(
              ShortestKeyOrder(@value.InvalidKey),
              progress,
              used,
            )
          }
          match @storage.node_index(state.source, identity) {
            Err(issue) =>
              return @bounded.Failed(ShortestStorage(issue), progress, used)
            Ok(None) =>
              return @bounded.Failed(ShortestEndpointMissing, progress, used)
            Ok(Some(node)) => state.source_selected[node] = true
          }
          state.index += 1
        } else {
          shortest_finish_endpoint_side(state)
        }
      ResolveTargetEndpoints =>
        if state.index < shortest_endpoint_count(state, @schema.Right) {
          used += 1
          guard shortest_endpoint_at(state, @schema.Right, state.index)
            is Some(identity) else {
            return @bounded.Failed(UnsupportedShortestKernel, progress, used)
          }
          guard @value.recheck_runtime_value(
              identity.value,
              @carrier.graph_identity(state.graph),
              state.value_limits,
            )
            is Some(identity) else {
            return @bounded.Failed(
              ShortestKeyOrder(@value.InvalidKey),
              progress,
              used,
            )
          }
          match @storage.node_index(state.source, identity) {
            Err(issue) =>
              return @bounded.Failed(ShortestStorage(issue), progress, used)
            Ok(None) =>
              return @bounded.Failed(ShortestEndpointMissing, progress, used)
            Ok(Some(node)) => state.target_selected[node] = true
          }
          state.index += 1
        } else {
          shortest_finish_endpoint_side(state)
        }
      PrepareEndpointPredicate =>
        if state.index >= @storage.node_count(state.source) {
          shortest_finish_endpoint_side(state)
        } else if state.predicate_field <
          graph_node_predicate_binding_count(state.graph) {
          used += 1
          guard graph_node_predicate_binding(
              state.graph,
              state.source,
              state.index,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard shortest_endpoint_definition(state, state.endpoint_side)
            is PredicateShortestEndpoints(predicate) else {
            return @bounded.Failed(UnsupportedShortestKernel, progress, used)
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
                ShortestPredicate(issue.kind),
                progress,
                used,
              )
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateEndpointPredicate
            }
          }
        }
      EvaluateEndpointPredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(UnsupportedShortestKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(
              ShortestPredicate(issue.kind),
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
            shortest_endpoint_selection(state)[state.index] = selected
            state.index += 1
            state.predicate_field = 0
            state.predicate_input.clear()
            state.phase = PrepareEndpointPredicate
          }
        }
      }
      CollectSourceEndpoints =>
        if state.index < state.source_selected.length() {
          if state.source_selected[state.index] {
            state.source_nodes.push(state.index)
          }
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = CollectTargetEndpoints
        }
      CollectTargetEndpoints =>
        if state.index < state.target_selected.length() {
          if state.target_selected[state.index] {
            state.target_nodes.push(state.index)
          }
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = InitializeEndpointScratch
        }
      InitializeEndpointScratch => {
        let scratch = Int::max(
          state.source_nodes.length(),
          state.target_nodes.length(),
        )
        if state.index < scratch {
          state.endpoint_scratch.push(None)
          state.index += 1
          used += 1
        } else {
          state.endpoint_side = @schema.Left
          state.sort_width = 1
          state.phase = PrepareEndpointSort
        }
      }
      PrepareEndpointSort => {
        let nodes = shortest_endpoint_nodes(state, state.endpoint_side)
        if state.sort_width >= nodes.length() {
          if state.endpoint_side == @schema.Left {
            state.endpoint_side = @schema.Right
            state.sort_width = 1
          } else {
            state.index = 0
            state.phase = InitializeNodes
          }
        } else {
          state.sort_left = 0
          state.phase = PrepareEndpointMerge
        }
        used += 1
      }
      PrepareEndpointMerge => {
        let nodes = shortest_endpoint_nodes(state, state.endpoint_side)
        if state.sort_left >= nodes.length() {
          state.sort_copy_at = 0
          state.phase = CopyEndpointNodes
        } else {
          shortest_prepare_endpoint_merge(state)
        }
        used += 1
      }
      MergeEndpointNodes => {
        let nodes = shortest_endpoint_nodes(state, state.endpoint_side)
        if state.sort_left_at < state.sort_middle &&
          state.sort_right_at < state.sort_right {
          match
            shortest_compare_nodes_step(
              state,
              nodes[state.sort_left_at],
              nodes[state.sort_right_at],
            ) {
            Ok(Some(order)) => shortest_emit_endpoint_node(state, order <= 0)
            Ok(None) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else if state.sort_left_at < state.sort_middle {
          shortest_emit_endpoint_node(state, true)
        } else if state.sort_right_at < state.sort_right {
          shortest_emit_endpoint_node(state, false)
        } else {
          state.sort_left = state.sort_right
          state.phase = PrepareEndpointMerge
        }
        used += 1
      }
      CopyEndpointNodes => {
        let nodes = shortest_endpoint_nodes(state, state.endpoint_side)
        if state.sort_copy_at < nodes.length() {
          guard state.endpoint_scratch[state.sort_copy_at] is Some(node) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          nodes[state.sort_copy_at] = node
          state.endpoint_scratch[state.sort_copy_at] = None
          state.sort_copy_at += 1
          used += 1
        } else {
          state.sort_width = if state.sort_width > nodes.length() / 2 {
            nodes.length()
          } else {
            state.sort_width * 2
          }
          state.phase = PrepareEndpointSort
        }
      }
      InitializeNodes =>
        if state.index < @storage.node_count(state.source) {
          state.degree.push(0)
          state.start.push(0)
          state.cursor.push(0)
          state.depth.push(-1)
          state.predecessor.push(-1)
          state.predecessor_edge.push(-1)
          if state.weight_property is Some(_) {
            state.visited.push(false)
          }
          state.index += 1
          used += 1
        } else {
          state.phase = FinishOffsets
        }
      FinishOffsets => {
        state.start.push(0)
        state.index = 0
        state.phase = ScanDegrees
        used += 1
      }
      ScanDegrees =>
        if state.index < shortest_edge_count(state) {
          guard shortest_oriented_endpoints(state, state.index)
            is Some((source, _, _)) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          match shortest_edge_type_count(state) {
            None => {
              state.degree[source] += 1
              state.index += 1
            }
            Some(0) => state.index += 1
            Some(_) => {
              state.edge_type_index = 0
              state.phase = ScanDegreeTypes
            }
          }
          used += 1
        } else {
          state.index = 0
          state.phase = BuildOffsets
        }
      ScanDegreeTypes => {
        guard shortest_oriented_endpoints(state, state.index)
          is Some((source, _, edge)) &&
          shortest_edge_type_count(state) is Some(type_count) else {
          return @bounded.Failed(ShortestInputUnavailable, progress, used)
        }
        let matches = shortest_edge_type_matches(
          state,
          edge,
          state.edge_type_index,
        )
        state.edge_type_index += 1
        used += 1
        if matches {
          state.degree[source] += 1
          state.index += 1
          state.phase = ScanDegrees
        } else if state.edge_type_index >= type_count {
          state.index += 1
          state.phase = ScanDegrees
        }
      }
      BuildOffsets =>
        if state.index < @storage.node_count(state.source) {
          state.start[state.index + 1] = state.start[state.index] +
            state.degree[state.index]
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = InitializeEdges
        }
      InitializeEdges =>
        if state.index < shortest_edge_count(state) {
          state.neighbor.push(-1)
          state.edge.push(-1)
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = CopyCursors
        }
      CopyCursors =>
        if state.index < @storage.node_count(state.source) {
          state.cursor[state.index] = state.start[state.index]
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = FillEdges
        }
      FillEdges =>
        if state.index < shortest_edge_count(state) {
          guard shortest_oriented_endpoints(state, state.index)
            is Some((source, target, edge)) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          match shortest_edge_type_count(state) {
            None => {
              let at = state.cursor[source]
              state.neighbor[at] = target
              state.edge[at] = edge
              state.cursor[source] = at + 1
              state.index += 1
            }
            Some(0) => state.index += 1
            Some(_) => {
              state.edge_type_index = 0
              state.phase = FillEdgeTypes
            }
          }
          used += 1
        } else {
          state.index = 0
          state.phase = InitializeSortScratch
        }
      FillEdgeTypes => {
        guard shortest_oriented_endpoints(state, state.index)
          is Some((source, target, edge)) &&
          shortest_edge_type_count(state) is Some(type_count) else {
          return @bounded.Failed(ShortestInputUnavailable, progress, used)
        }
        let matches = shortest_edge_type_matches(
          state,
          edge,
          state.edge_type_index,
        )
        state.edge_type_index += 1
        used += 1
        if matches {
          let at = state.cursor[source]
          state.neighbor[at] = target
          state.edge[at] = edge
          state.cursor[source] = at + 1
          state.index += 1
          state.phase = FillEdges
        } else if state.edge_type_index >= type_count {
          state.index += 1
          state.phase = FillEdges
        }
      }
      InitializeSortScratch =>
        if state.index < shortest_edge_count(state) {
          state.sort_neighbor.push(-1)
          state.sort_edge.push(-1)
          state.index += 1
          used += 1
        } else {
          state.sort_node = 0
          state.phase = PrepareSortNode
        }
      PrepareSortNode =>
        if state.sort_node >= @storage.node_count(state.source) {
          if state.weight_property is Some(_) {
            state.index = 0
            state.phase = ValidateWeight
          } else {
            state.source_pair = 0
            state.target_pair = 0
            state.phase = PreparePair
          }
        } else {
          let begin = state.start[state.sort_node]
          let end = state.start[state.sort_node + 1]
          if end - begin < 2 {
            state.sort_node += 1
          } else {
            state.sort_width = 1
            state.sort_left = begin
            state.phase = PrepareSortMerge
          }
          used += 1
        }
      PrepareSortMerge => {
        let begin = state.start[state.sort_node]
        let end = state.start[state.sort_node + 1]
        let length = end - begin
        if state.sort_width >= length {
          state.sort_node += 1
          state.phase = PrepareSortNode
        } else if state.sort_left >= end {
          state.sort_copy_at = begin
          state.phase = CopySortedEdges
        } else {
          state.sort_middle = if state.sort_left > end - state.sort_width {
            end
          } else {
            state.sort_left + state.sort_width
          }
          state.sort_right = if state.sort_middle > end - state.sort_width {
            end
          } else {
            state.sort_middle + state.sort_width
          }
          state.sort_left_at = state.sort_left
          state.sort_right_at = state.sort_middle
          state.sort_merge_at = state.sort_left
          state.phase = MergeEdges
        }
        used += 1
      }
      MergeEdges => {
        if state.sort_left_at < state.sort_middle &&
          state.sort_right_at < state.sort_right {
          match
            shortest_compare_edges_step(
              state,
              state.sort_left_at,
              state.sort_right_at,
            ) {
            Ok(Some(order)) => shortest_emit_sorted_edge(state, order <= 0)
            Ok(None) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        } else if state.sort_left_at < state.sort_middle {
          shortest_emit_sorted_edge(state, true)
        } else if state.sort_right_at < state.sort_right {
          shortest_emit_sorted_edge(state, false)
        } else {
          state.sort_left = state.sort_right
          state.phase = PrepareSortMerge
        }
        used += 1
      }
      CopySortedEdges => {
        let begin = state.start[state.sort_node]
        let end = state.start[state.sort_node + 1]
        let length = end - begin
        if state.sort_copy_at < end {
          state.neighbor[state.sort_copy_at] = state.sort_neighbor[state.sort_copy_at]
          state.edge[state.sort_copy_at] = state.sort_edge[state.sort_copy_at]
          state.sort_copy_at += 1
          used += 1
        } else {
          state.sort_width = if state.sort_width > length / 2 {
            length
          } else {
            state.sort_width * 2
          }
          state.sort_left = begin
          state.phase = PrepareSortMerge
        }
      }
      ValidateWeight => {
        guard state.weight_property is Some(property) else {
          return @bounded.Failed(UnsupportedShortestKernel, progress, used)
        }
        if state.index < @storage.edge_count(state.source) {
          used += 1
          guard @storage.edge_property(state.source, state.index, property)
            is Some({ value: @value.Number(weight), .. }) &&
            !weight.is_nan() &&
            !weight.is_inf() &&
            weight >= 0.0 else {
            return @bounded.Failed(ShortestInvalidWeight, progress, used)
          }
          state.edge_weight.push(weight)
          state.index += 1
        } else {
          state.source_pair = 0
          state.target_pair = 0
          state.phase = PreparePair
        }
      }
      PreparePair =>
        if state.source_pair >= state.source_nodes.length() {
          if state.selection == @graph_type.NearestPair &&
            shortest_prepare_nearest_output(state) {
            ()
          } else {
            state.phase = Finish
          }
        } else if state.target_pair >= state.target_nodes.length() {
          if state.selection == @graph_type.NearestPerSource &&
            shortest_prepare_nearest_output(state) {
            ()
          } else {
            state.source_pair += 1
            state.target_pair = 0
            used += 1
          }
        } else {
          state.source_node = state.source_nodes[state.source_pair]
          state.target_node = state.target_nodes[state.target_pair]
          state.index = 0
          state.queue.clear()
          state.path_nodes.clear()
          state.path_edges.clear()
          state.path_next.clear()
          state.path_costs.clear()
          state.path_overranges.clear()
          state.pair_best_nodes.clear()
          state.pair_best_edges.clear()
          state.path_cost = 0.0
          state.path_overrange = false
          state.pair_best = false
          state.pair_best_cost = 0.0
          state.pair_best_overrange = false
          state.values = []
          state.neighbor_index = 0
          state.phase = ResetSearch
          used += 1
        }
      ResetSearch =>
        if state.index < state.depth.length() {
          state.depth[state.index] = -1
          state.predecessor[state.index] = -1
          state.predecessor_edge[state.index] = -1
          state.index += 1
          used += 1
        } else {
          state.phase = StartSearch
        }
      StartSearch => {
        if state.weight_property is Some(_) {
          state.path_nodes.push(state.source_node)
          state.path_next.push(state.start[state.source_node])
          state.path_costs.push(0.0)
          state.path_overranges.push(false)
          state.visited[state.source_node] = true
          state.path_cost = 0.0
          state.path_overrange = false
          state.phase = ExploreWeightedPath
        } else {
          state.depth[state.source_node] = 0
          state.queue.push(state.source_node)
          state.queue_index = 0
          state.has_path = state.source_node == state.target_node
          state.phase = if state.has_path { PreparePath } else { ScanNeighbor }
        }
        used += 1
      }
      ScanNeighbor =>
        if state.queue_index >= state.queue.length() {
          state.phase = FinishPair
        } else {
          let current = state.queue[state.queue_index]
          let begin = state.start[current]
          let end = state.start[current + 1]
          if state.neighbor_index >= end - begin {
            state.queue_index += 1
            state.neighbor_index = 0
          } else {
            let at = begin + state.neighbor_index
            state.neighbor_index += 1
            let next = state.neighbor[at]
            if state.depth[next] < 0 && state.depth[current] < state.max_hops {
              state.depth[next] = state.depth[current] + 1
              state.predecessor[next] = current
              state.predecessor_edge[next] = state.edge[at]
              state.queue.push(next)
              if next == state.target_node {
                state.has_path = true
                state.phase = PreparePath
              }
            }
          }
          used += 1
        }
      ExploreWeightedPath => {
        guard !state.path_nodes.is_empty() &&
          state.path_nodes.last() is Some(current) &&
          state.path_next.last() is Some(next_at) else {
          return @bounded.Failed(ShortestInputUnavailable, progress, used)
        }
        if current == state.target_node {
          if !state.pair_best ||
            shortest_cost_is_better(
              state.path_cost,
              state.path_overrange,
              state.path_edges.length(),
              state.pair_best_cost,
              state.pair_best_overrange,
              state.pair_best_edges.length(),
            ) {
            shortest_begin_weighted_copy(state)
          } else if state.path_overrange == state.pair_best_overrange &&
            (state.path_overrange || state.path_cost == state.pair_best_cost) &&
            state.path_edges.length() == state.pair_best_edges.length() {
            state.weighted_compare_at = 0
            state.phase = CompareWeightedNodes
          } else {
            state.phase = BacktrackWeightedPath
          }
        } else if state.path_edges.length() >= state.max_hops ||
          next_at >= state.start[current + 1] {
          state.phase = BacktrackWeightedPath
        } else {
          let depth = state.path_nodes.length() - 1
          state.path_next[depth] = next_at + 1
          let next = state.neighbor[next_at]
          let edge = state.edge[next_at]
          if next < 0 || edge < 0 || edge >= state.edge_weight.length() {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          if !state.visited[next] {
            let overrange = state.path_overrange
            let cost = if overrange {
              state.path_cost
            } else {
              state.path_cost + state.edge_weight[edge]
            }
            let overrange = overrange || cost.is_inf()
            state.visited[next] = true
            state.path_nodes.push(next)
            state.path_edges.push(edge)
            state.path_next.push(state.start[next])
            state.path_costs.push(
              if overrange {
                state.path_cost
              } else {
                cost
              },
            )
            state.path_overranges.push(overrange)
            state.path_cost = if overrange { state.path_cost } else { cost }
            state.path_overrange = overrange
          }
          used += 1
        }
      }
      CompareWeightedNodes =>
        if state.weighted_compare_at >= state.path_nodes.length() {
          state.weighted_compare_at = 0
          state.phase = CompareWeightedEdges
        } else {
          let index = state.weighted_compare_at
          guard state.pair_best_nodes.get(index) is Some(other) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          match
            shortest_compare_nodes_step(state, state.path_nodes[index], other) {
            Err(issue) => return @bounded.Failed(issue, progress, used)
            Ok(Some(order)) if order < 0 => shortest_begin_weighted_copy(state)
            Ok(Some(order)) if order > 0 => state.phase = BacktrackWeightedPath
            Ok(Some(_)) => state.weighted_compare_at += 1
            Ok(None) => ()
          }
          used += 1
        }
      CompareWeightedEdges =>
        if state.weighted_compare_at >= state.path_edges.length() {
          state.phase = BacktrackWeightedPath
        } else {
          let index = state.weighted_compare_at
          guard state.pair_best_edges.get(index) is Some(other) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          match
            shortest_compare_edge_identities_step(
              state,
              state.path_edges[index],
              other,
            ) {
            Err(issue) => return @bounded.Failed(issue, progress, used)
            Ok(Some(order)) if order < 0 => shortest_begin_weighted_copy(state)
            Ok(Some(order)) if order > 0 => state.phase = BacktrackWeightedPath
            Ok(Some(_)) => state.weighted_compare_at += 1
            Ok(None) => ()
          }
          used += 1
        }
      CopyWeightedBest =>
        if state.weighted_copy_at < state.path_nodes.length() {
          state.pair_best_nodes.push(state.path_nodes[state.weighted_copy_at])
          state.weighted_copy_at += 1
          used += 1
        } else {
          let edge_at = state.weighted_copy_at - state.path_nodes.length()
          if edge_at < state.path_edges.length() {
            state.pair_best_edges.push(state.path_edges[edge_at])
            state.weighted_copy_at += 1
            used += 1
          } else {
            state.pair_best = true
            state.pair_best_cost = state.path_cost
            state.pair_best_overrange = state.path_overrange
            state.phase = BacktrackWeightedPath
          }
        }
      BacktrackWeightedPath =>
        if state.path_nodes.length() <= 1 {
          state.visited[state.source_node] = false
          state.phase = FinishWeightedPair
        } else {
          guard state.path_nodes.pop() is Some(node) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          state.visited[node] = false
          ignore(state.path_edges.pop())
          ignore(state.path_next.pop())
          ignore(state.path_costs.pop())
          ignore(state.path_overranges.pop())
          guard state.path_costs.last() is Some(cost) &&
            state.path_overranges.last() is Some(overrange) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          state.path_cost = cost
          state.path_overrange = overrange
          state.phase = ExploreWeightedPath
          used += 1
        }
      FinishWeightedPair => {
        if state.pair_best {
          let nodes = state.path_nodes
          let edges = state.path_edges
          state.path_nodes = state.pair_best_nodes
          state.path_edges = state.pair_best_edges
          state.pair_best_nodes = nodes
          state.pair_best_edges = edges
          state.path_cost = state.pair_best_cost
          state.path_overrange = state.pair_best_overrange
          state.has_path = true
          state.row_column = 0
          state.phase = if state.selection == @graph_type.EachPair {
            ReadField
          } else {
            SelectNearestPath
          }
        } else {
          state.has_path = false
          state.phase = FinishPair
        }
        used += 1
      }
      PreparePath => {
        state.path_cursor = state.target_node
        state.path_nodes.push(state.target_node)
        state.phase = if state.target_node == state.source_node {
          ReverseNodes
        } else {
          ReconstructPath
        }
        used += 1
      }
      ReconstructPath => {
        let edge = state.predecessor_edge[state.path_cursor]
        let node = state.predecessor[state.path_cursor]
        if edge < 0 || node < 0 {
          return @bounded.Failed(ShortestInputUnavailable, progress, used)
        }
        state.path_edges.push(edge)
        state.path_nodes.push(node)
        state.path_cursor = node
        if node == state.source_node {
          state.reverse_index = 0
          state.phase = ReverseNodes
        }
        used += 1
      }
      ReverseNodes => {
        let opposite = state.path_nodes.length() - 1 - state.reverse_index
        if state.reverse_index < opposite {
          let saved = state.path_nodes[state.reverse_index]
          state.path_nodes[state.reverse_index] = state.path_nodes[opposite]
          state.path_nodes[opposite] = saved
          state.reverse_index += 1
          used += 1
        } else {
          state.reverse_index = 0
          state.phase = ReverseEdges
        }
      }
      ReverseEdges => {
        let opposite = state.path_edges.length() - 1 - state.reverse_index
        if state.reverse_index < opposite {
          let saved = state.path_edges[state.reverse_index]
          state.path_edges[state.reverse_index] = state.path_edges[opposite]
          state.path_edges[opposite] = saved
          state.reverse_index += 1
          used += 1
        } else {
          state.path_cost = state.path_edges.length().to_double()
          state.path_overrange = false
          if state.selection == @graph_type.EachPair {
            state.row_column = 0
            state.phase = ReadField
          } else {
            state.phase = SelectNearestPath
          }
        }
      }
      SelectNearestPath => {
        shortest_retain_nearest_path(state)
        state.phase = FinishPair
        used += 1
      }
      ReadField =>
        if state.path_overrange {
          return @bounded.Failed(ShortestCostOverrange, progress, used)
        } else if state.row_column < @schema.field_count(state.schema) {
          guard @schema.field_at(state.schema, state.row_column) is Some(field) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          match field.name {
            @schema.Unqualified("node_ids") => {
              guard shortest_path_value_minimum_nodes(state, field)
                is Some(nodes) &&
                nodes <= state.value_limits.max_nodes &&
                @value.prepare_array_value(state.path_nodes.length())
                is Some(builder) else {
                return @bounded.Failed(ShortestOutputLimit, progress, used)
              }
              state.value_items = Some(builder)
              state.value_item = 0
              state.value_nodes_remaining = state.value_limits.max_nodes
              guard shortest_reserve_value_nodes(state, 1) else {
                return @bounded.Failed(ShortestOutputLimit, progress, used)
              }
              state.phase = BuildNodeIds
            }
            @schema.Unqualified("edge_ids") => {
              guard shortest_path_value_minimum_nodes(state, field)
                is Some(nodes) &&
                nodes <= state.value_limits.max_nodes &&
                @value.prepare_array_value(state.path_edges.length())
                is Some(builder) else {
                return @bounded.Failed(ShortestOutputLimit, progress, used)
              }
              state.value_items = Some(builder)
              state.value_item = 0
              state.value_nodes_remaining = state.value_limits.max_nodes
              guard shortest_reserve_value_nodes(state, 1) else {
                return @bounded.Failed(ShortestOutputLimit, progress, used)
              }
              state.phase = BuildEdgeIds
            }
            _ => {
              guard shortest_path_value(state, field) is Some(value) else {
                return @bounded.Failed(ShortestInputUnavailable, progress, used)
              }
              state.values.push(value)
              state.row_column += 1
              used += 1
            }
          }
        } else {
          state.phase = CommitRow
        }
      BuildNodeIds => {
        if state.value_item == state.path_nodes.length() {
          state.phase = FinalizePathValue
          continue
        }
        guard shortest_reserve_value_nodes(state, 1) else {
          return @bounded.Failed(ShortestOutputLimit, progress, used)
        }
        used += 1
        if @bounded.stop_requested(reader) is Some(reason) {
          return @bounded.Stopped(reason, progress, used)
        }
        let node = state.path_nodes[state.value_item]
        guard state.value_items is Some(builder) &&
          @storage.node_identity(state.source, node) is Some(identity) &&
          @value.append_array_item(builder, identity.value) else {
          return @bounded.Failed(ShortestInputUnavailable, progress, used)
        }
        state.value_item_attempts.val += 1
        state.value_item += 1
      }
      BuildEdgeIds => {
        if state.value_item == state.path_edges.length() {
          state.phase = FinalizePathValue
          continue
        }
        guard shortest_reserve_value_nodes(state, 4) else {
          return @bounded.Failed(ShortestOutputLimit, progress, used)
        }
        used += 1
        if @bounded.stop_requested(reader) is Some(reason) {
          return @bounded.Stopped(reason, progress, used)
        }
        let edge = state.path_edges[state.value_item]
        guard state.value_items is Some(builder) &&
          @storage.edge_endpoints(state.source, edge) is Some((source, target)) &&
          @storage.node_identity(state.source, source) is Some(source_id) &&
          @storage.node_identity(state.source, target) is Some(target_id) &&
          @storage.edge_label(state.source, edge) is Some(label) &&
          @value.object_value([
            ("src", source_id.value),
            ("dst", target_id.value),
            (
              "rel",
              match label {
                Some(value) => value.value
                None => @value.null_value()
              },
            ),
          ])
          is Some(identity) &&
          @value.append_array_item(builder, identity) else {
          return @bounded.Failed(ShortestInputUnavailable, progress, used)
        }
        state.value_item_attempts.val += 1
        state.value_item += 1
      }
      FinalizePathValue => {
        guard state.value_items is Some(builder) &&
          @value.finish_array_value(builder) is Some(array) &&
          @schema.field_at(state.schema, state.row_column) is Some(field) &&
          @value.recheck_runtime_value(
            array,
            field.contract,
            state.value_limits,
          )
          is Some(value) else {
          return @bounded.Failed(ShortestOutputLimit, progress, used)
        }
        state.values.push(value)
        state.value_items = None
        state.value_item = 0
        state.value_nodes_remaining = 0
        state.row_column += 1
        state.phase = ReadField
        used += 1
      }
      CommitRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(UnsupportedShortestKernel, progress, used)
        }
        if state.output_guard is Some(guard_rows) &&
          state.emitted_rows >= guard_rows {
          return @bounded.Failed(ShortestOutputLimit, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.values = []
            state.value_items = None
            state.emitted_rows += 1L
            state.phase = match state.selection {
              @graph_type.EachPair => FinishPair
              @graph_type.NearestPerSource => FinishNearestSource
              @graph_type.NearestPair => Finish
            }
            progress += 1
            used += 1
          }
          Err(issue) =>
            return @bounded.Failed(ShortestOutput(issue), progress, used)
        }
      }
      FinishPair => {
        state.target_pair += 1
        state.phase = PreparePair
        used += 1
      }
      FinishNearestSource => {
        state.source_pair += 1
        state.target_pair = 0
        state.phase = PreparePair
        used += 1
      }
      Finish => {
        guard state.output is Some(output) else {
          return @bounded.Failed(UnsupportedShortestKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(ShortestOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        used += 1
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) =>
            @bounded.Failed(ShortestCompletion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_shortest_state(state : ShortestState) -> Bool {
  state.key_comparison = None
  state.key_component = 0
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
  state.degree.clear()
  state.start.clear()
  state.cursor.clear()
  state.neighbor.clear()
  state.edge.clear()
  state.sort_neighbor.clear()
  state.sort_edge.clear()
  state.source_selected.clear()
  state.target_selected.clear()
  state.source_nodes.clear()
  state.target_nodes.clear()
  state.endpoint_scratch.clear()
  state.predicate_input.clear()
  state.depth.clear()
  state.predecessor.clear()
  state.predecessor_edge.clear()
  state.queue.clear()
  state.edge_weight.clear()
  state.visited.clear()
  state.path_next.clear()
  state.path_costs.clear()
  state.path_overranges.clear()
  state.path_nodes.clear()
  state.path_edges.clear()
  state.pair_best_nodes.clear()
  state.pair_best_edges.clear()
  state.best_path_nodes.clear()
  state.best_path_edges.clear()
  state.values = []
  state.value_items = None
  true
}

///|
fn prepare_shortest_endpoints(
  prepared : @lower.PreparedGraphShortest,
  side : @schema.Side,
  owner : @lower.BoundPrepared,
  step : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[ShortestEndpoints, ShortestIssue] {
  if @lower.graph_shortest_endpoint_single(prepared, side) is Some(value) {
    return Ok(SingleShortestEndpoint(value))
  }
  if @lower.graph_shortest_endpoint_id_count(prepared, side) > 0 &&
    @lower.graph_shortest_endpoint_relation_field(prepared, side) is None &&
    @lower.graph_shortest_endpoint_predicate(prepared, side) is None &&
    @lower.graph_shortest_endpoint_input_port(prepared, side) is None {
    return Ok(LiteralShortestEndpoints)
  }
  if @lower.graph_shortest_endpoint_predicate(prepared, side) is Some(predicate) &&
    @lower.graph_shortest_endpoint_relation_field(prepared, side) is None &&
    @lower.graph_shortest_endpoint_input_port(prepared, side) is None {
    return Ok(PredicateShortestEndpoints(predicate))
  }
  guard @lower.graph_shortest_endpoint_relation_field(prepared, side)
    is Some(field) &&
    @lower.graph_shortest_endpoint_input_port(prepared, side) is Some(port) else {
    return Err(UnsupportedShortestKernel)
  }
  for input in inputs {
    if @execution.producer_read_matches_operation_input(
        input, owner, step, port,
      ) {
      let schema = @execution.producer_read_schema(input)
      for column in 0..<@schema.field_count(schema) {
        if @schema.field_at(schema, column).map(value => value.name) ==
          Some(field) {
          return Ok(RelationShortestEndpoints(input, column))
        }
      }
      return Err(UnsupportedShortestKernel)
    }
  }
  Err(UnsupportedShortestKernel)
}

///|
/// Start the bounded shortest-path kernel for scalar, literal,
/// Relation-backed, or predicate-selected endpoints.
pub fn start_shortest(
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
) -> Result[ShortestExecution, ShortestIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphShortestStep(prepared)) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(source) &&
    @lower.graph_shortest_max_hops(prepared) is Some(max_hops) else {
    return Err(UnsupportedShortestKernel)
  }
  let sources = match
    prepare_shortest_endpoints(prepared, @schema.Left, owner, step, inputs) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let targets = match
    prepare_shortest_endpoints(prepared, @schema.Right, owner, step, inputs) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let nodes = @storage.node_count(source)
  let edges = @storage.edge_count(source)
  let direction = @lower.graph_shortest_direction(prepared)
  let selection = @lower.graph_shortest_selection(prepared)
  guard @storage.carrier(source) is @carrier.GraphValue(graph) else {
    return Err(ShortestInputUnavailable)
  }
  let weight_property = match @lower.graph_shortest_weight(prepared) {
    None => None
    Some(name) =>
      match shortest_weight_property(graph, name) {
        Some(index) => Some(index)
        None => return Err(UnsupportedShortestKernel)
      }
  }
  let predicate_fields = if sources is PredicateShortestEndpoints(_) ||
    targets is PredicateShortestEndpoints(_) {
    graph_node_predicate_binding_count(graph)
  } else {
    0
  }
  guard max_rows >= 0 &&
    shortest_workspace(
      nodes,
      edges,
      direction == @graph_type.Both,
      selection != @graph_type.EachPair,
      weight_property is Some(_),
    )
    is Some(workspace) &&
    predicate_fields <= max_workspace_slots - workspace else {
    return Err(ShortestWorkspaceLimit)
  }
  if @lower.graph_shortest_output_guard(prepared) is Some(guard_rows) &&
    guard_rows < 1L {
    return Err(ShortestOutputLimit)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ShortestOutput(issue))
  }
  let rows : Ref[@execution.AdmittedOutputRows?] = Ref(None)
  let live = Ref(true)
  let accepted = Ref(false)
  let value_item_attempts = Ref(0)
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
      return Err(ShortestCompletion(issue))
    }
  }
  let state : ShortestState = {
    input,
    source,
    schema: @lower.graph_shortest_output_schema(prepared),
    prepared,
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    direction,
    selection,
    sources,
    targets,
    max_hops,
    output_guard: @lower.graph_shortest_output_guard(prepared),
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: InitializeEndpointSelection,
    index: 0,
    source_node: -1,
    target_node: -1,
    source_pair: 0,
    target_pair: 0,
    endpoint_side: @schema.Left,
    queue_index: 0,
    neighbor_index: 0,
    path_cursor: -1,
    reverse_index: 0,
    row_column: 0,
    edge_type_index: 0,
    sort_node: 0,
    sort_width: 1,
    sort_left: 0,
    sort_middle: 0,
    sort_right: 0,
    sort_left_at: 0,
    sort_right_at: 0,
    sort_merge_at: 0,
    sort_copy_at: 0,
    has_path: false,
    best_path: false,
    best_source_node: -1,
    best_target_node: -1,
    weight_property,
    path_cost: 0.0,
    path_overrange: false,
    pair_best: false,
    pair_best_cost: 0.0,
    pair_best_overrange: false,
    best_path_cost: 0.0,
    best_path_overrange: false,
    weighted_copy_at: 0,
    weighted_compare_at: 0,
    key_component: 0,
    key_comparison: None,
    degree: [],
    start: [],
    cursor: [],
    neighbor: [],
    edge: [],
    sort_neighbor: [],
    sort_edge: [],
    source_selected: [],
    target_selected: [],
    source_nodes: [],
    target_nodes: [],
    endpoint_scratch: [],
    graph,
    predicate_workspace: max_workspace_slots - workspace - predicate_fields,
    predicate_work_remaining: limits.max_work,
    predicate_input: Map([]),
    predicate_execution: None,
    predicate_field: 0,
    depth: [],
    predecessor: [],
    predecessor_edge: [],
    queue: [],
    edge_weight: [],
    visited: [],
    path_next: [],
    path_costs: [],
    path_overranges: [],
    path_nodes: [],
    path_edges: [],
    pair_best_nodes: [],
    pair_best_edges: [],
    best_path_nodes: [],
    best_path_edges: [],
    emitted_rows: 0L,
    values: [],
    value_items: None,
    value_item: 0,
    value_nodes_remaining: 0,
    value_item_attempts,
  }
  let (session, token) = @bounded.start(
    control,
    state,
    shortest_step,
    cleanup_shortest_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({
    session,
    token: Some(token),
    accepted,
    value_item_attempts,
    max_noninterruptible_value_nodes: limits.max_nodes,
    max_noninterruptible_value_bytes: limits.max_text_bytes,
  })
}

///|
pub fn shortest_max_noninterruptible_value_nodes(
  value : ShortestExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn shortest_max_noninterruptible_value_bytes(
  value : ShortestExecution,
) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
/// Report path value items constructed after output-limit preflight.
pub fn shortest_value_item_attempts(value : ShortestExecution) -> Int {
  value.value_item_attempts.val
}

///|
pub fn advance_shortest(
  value : ShortestExecution,
  quantum : Int,
) -> Result[ShortestPoll, ShortestIssue] {
  guard value.token is Some(token) else {
    return Err(ShortestExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(ShortestExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(ShortestContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(ShortestComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(ShortestFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(ShortestStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn shortest_stopped(value : ShortestExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn shortest_cleanup_pending(value : ShortestExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_shortest(
  value : ShortestExecution,
) -> Result[Bool, ShortestIssue] {
  @bounded.cleanup(value.session).map_err(issue => ShortestExecutionIssue(issue))
}
