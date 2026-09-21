///|
priv enum ReachPhase {
  InitializeStartSelection
  ResolveStarts
  PrepareStartPredicate
  EvaluateStartPredicate
  PrepareHopEdgePredicate
  EvaluateHopEdgePredicate
  PrepareHopNodePredicate
  EvaluateHopNodePredicate
  ScanHopEdgeTypes
  VisitHopNeighbor
  CollectStarts
  InitializeNodes
  ScanDegrees
  ScanDegreeTypes
  BuildOffsets
  InitializeEdges
  FillEdges
  FillEdgeTypes
  PrepareStartSort
  PrepareStartMerge
  StartMerge
  CompareStartMerge
  CopyStartPass
  StartNext
  ResetDepth
  CopyPatternFrontier
  PopNode
  ScanOutgoing
  ScanIncoming
  PrepareSort
  PrepareMerge
  Merge
  CompareMerge
  CopyPass
  SelectRow
  ReadField
  CommitRow
  Finish
}

///|
priv enum ReachStarts {
  SingleReachStart(@value.CheckedValue)
  TraversalReachStarts(@lower.PreparedGraphTraverse)
  TraversalRelationStarts(@execution.ProducerRead, Int)
  TraversalPredicateStarts(@lower.Expression)
}

///|
priv enum ReachEdgeFilter {
  AllReachEdges
  TraversalReachEdgeTypes(@lower.PreparedGraphTraverse, Int)
}

///|
priv struct ReachState {
  input : @graph.ProducerRead
  source : @storage.Storage
  graph : @carrier.Graph
  schema : @schema.Schema
  starts : ReachStarts
  pattern : @lower.PreparedGraphTraverse?
  direction : @graph_type.Direction
  edge_filter : ReachEdgeFilter
  edge_predicate : @lower.Expression?
  node_predicate : @lower.Expression?
  minimum_depth : Int
  max_depth : Int
  value_limits : @value.Limits
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : ReachPhase
  mut index : Int
  mut current_node : Int
  mut current_start_node : Int
  mut start_node_index : Int
  mut neighbor_index : Int
  mut candidate_edge : Int
  mut candidate_node : Int
  mut neighbor_resume : ReachPhase
  mut pattern_hop : Int
  mut edge_type_index : Int
  mut row_index : Int
  mut column : Int
  out_degree : Array[Int]
  in_degree : Array[Int]
  out_start : Array[Int]
  in_start : Array[Int]
  out_cursor : Array[Int]
  in_cursor : Array[Int]
  out_edges : Array[Int]
  in_edges : Array[Int]
  depth : Array[Int]
  queue : Array[Int]
  selected : Array[Int]
  scratch : Array[Int?]
  start_selected : Array[Bool]
  start_nodes : Array[Int]
  start_scratch : Array[Int?]
  predicate_fields : Int
  predicate_workspace : Int
  mut predicate_work_remaining : Int
  predicate_input : Map[String, @execution.Value]
  mut predicate_execution : @execution.PredicateExpressionExecution?
  mut predicate_field : Int
  mut width : Int
  mut run_start : Int
  mut middle : Int
  mut run_end : Int
  mut left_index : Int
  mut right_index : Int
  mut merge_index : Int
  mut copy_index : Int
  mut values : Array[@value.CheckedValue]
}

///|
struct ReachExecution {
  session : @bounded.Session[ReachState, @execution.CompletedOutput, ReachIssue]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
  max_noninterruptible_value_nodes : Int
  max_noninterruptible_value_bytes : Int
}

///|
pub enum ReachPoll {
  ReachContinue(progress~ : Int64, work~ : Int64)
  ReachComplete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  ReachFailed(ReachIssue, progress~ : Int64, work~ : Int64)
  ReachStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum ReachIssue {
  InvalidReachKernel
  ReachInputUnavailable
  ReachStartMissing
  ReachOutputLimit
  ReachWorkspaceLimit
  ReachPredicate(@execution.EvalIssueKind)
  ReachKeyOrder(@value.KeyOrderIssue)
  ReachGraph(@storage.Issue)
  ReachOutput(@execution.CaptureIssue)
  ReachCompletion(@execution.TrustedOutputIssue)
  ReachExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn checked_reach_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn checked_reach_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
}

///|
fn reach_workspace(nodes : Int, edges : Int, width : Int) -> Int? {
  guard checked_reach_multiply(nodes, 13) is Some(node_slots) &&
    checked_reach_multiply(edges, 2) is Some(edge_slots) &&
    checked_reach_add(node_slots, 2) is Some(node_slots) &&
    checked_reach_add(node_slots, edge_slots) is Some(graph_slots) &&
    checked_reach_add(graph_slots, width) is Some(total) else {
    return None
  }
  Some(total)
}

///|
fn reach_start_count(state : ReachState) -> Int {
  match state.starts {
    SingleReachStart(_) => 1
    TraversalReachStarts(prepared) =>
      @lower.graph_traverse_start_id_count(prepared)
    TraversalRelationStarts(input, _) =>
      @execution.producer_read_row_count(input)
    TraversalPredicateStarts(_) => @storage.node_count(state.source)
  }
}

///|
fn reach_start_at(
  state : ReachState,
  index : Int,
) -> Result[@value.CheckedValue, ReachIssue] {
  match state.starts {
    SingleReachStart(value) =>
      if index == 0 {
        Ok(value)
      } else {
        Err(InvalidReachKernel)
      }
    TraversalReachStarts(prepared) =>
      match @lower.graph_traverse_start_id_at(prepared, index) {
        Some(value) => Ok(value)
        None => Err(InvalidReachKernel)
      }
    TraversalRelationStarts(input, column) =>
      match
        @execution.producer_read_checked_cell(
          input,
          index,
          column,
          state.value_limits,
        ) {
        Some(value) => Ok(value)
        None => Err(ReachInputUnavailable)
      }
    TraversalPredicateStarts(_) => Err(InvalidReachKernel)
  }
}

///|
fn reach_starts_available(state : ReachState) -> Bool {
  match state.starts {
    TraversalRelationStarts(input, _) =>
      @execution.producer_read_available(input)
    _ => true
  }
}

///|
fn capped_reach_run_end(start : Int, width : Int, count : Int) -> Int {
  if start > count - Int::min(width, count) {
    count
  } else {
    Int::min(start + width, count)
  }
}

///|
fn prepare_reach_merge(state : ReachState) -> Unit {
  state.middle = capped_reach_run_end(
    state.run_start,
    state.width,
    state.selected.length(),
  )
  state.run_end = capped_reach_run_end(
    state.middle,
    state.width,
    state.selected.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.phase = Merge
}

///|
fn emit_reach_merge(state : ReachState, take_left : Bool) -> Unit {
  let node = if take_left {
    let node = state.selected[state.left_index]
    state.left_index += 1
    node
  } else {
    let node = state.selected[state.right_index]
    state.right_index += 1
    node
  }
  state.scratch[state.merge_index] = Some(node)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareMerge
  } else {
    state.phase = Merge
  }
}

///|
fn prepare_start_merge(state : ReachState) -> Unit {
  state.middle = capped_reach_run_end(
    state.run_start,
    state.width,
    state.start_nodes.length(),
  )
  state.run_end = capped_reach_run_end(
    state.middle,
    state.width,
    state.start_nodes.length(),
  )
  state.left_index = state.run_start
  state.right_index = state.middle
  state.merge_index = state.run_start
  state.phase = StartMerge
}

///|
fn emit_start_merge(state : ReachState, take_left : Bool) -> Unit {
  let node = if take_left {
    let node = state.start_nodes[state.left_index]
    state.left_index += 1
    node
  } else {
    let node = state.start_nodes[state.right_index]
    state.right_index += 1
    node
  }
  state.start_scratch[state.merge_index] = Some(node)
  state.merge_index += 1
  if state.merge_index >= state.run_end {
    state.run_start = state.run_end
    state.phase = PrepareStartMerge
  } else {
    state.phase = StartMerge
  }
}

///|
fn compare_reach_nodes(
  state : ReachState,
  left : Int,
  right : Int,
) -> Result[Int, ReachIssue] {
  guard @storage.node_identity(state.source, left) is Some(left_value) &&
    @storage.node_identity(state.source, right) is Some(right_value) else {
    return Err(ReachInputUnavailable)
  }
  @value.compare_key_values(left_value, right_value).map_err(issue => {
    ReachKeyOrder(issue)
  })
}

///|
fn visit_reach_neighbor(
  state : ReachState,
  node : Int,
) -> Result[Unit, ReachIssue] {
  guard state.depth.get(node) is Some(depth) &&
    state.depth.get(state.current_node) is Some(parent_depth) else {
    return Err(ReachInputUnavailable)
  }
  if state.pattern is Some(_) {
    let next_depth = state.pattern_hop + 1
    if depth != next_depth {
      state.depth[node] = next_depth
      state.selected.push(node)
      state.scratch.push(None)
    }
  } else if depth < 0 {
    let next_depth = parent_depth + 1
    state.depth[node] = next_depth
    state.queue.push(node)
    if next_depth >= state.minimum_depth {
      state.selected.push(node)
      state.scratch.push(None)
    }
  }
  Ok(())
}

///|
fn reach_direction(state : ReachState) -> @graph_type.Direction? {
  match state.pattern {
    Some(pattern) =>
      @lower.graph_traverse_hop_direction(pattern, state.pattern_hop)
    None => Some(state.direction)
  }
}

///|
fn reach_edge_predicate(state : ReachState) -> @lower.Expression? {
  match state.pattern {
    Some(pattern) =>
      @lower.graph_traverse_hop_edge_predicate(pattern, state.pattern_hop)
    None => state.edge_predicate
  }
}

///|
fn reach_node_predicate(state : ReachState) -> @lower.Expression? {
  match state.pattern {
    Some(pattern) =>
      @lower.graph_traverse_hop_node_predicate(pattern, state.pattern_hop)
    None => state.node_predicate
  }
}

///|
fn reach_pattern_hop_type_count(state : ReachState) -> Int? {
  state.pattern.bind(pattern => {
    @lower.graph_traverse_hop_type_count(pattern, state.pattern_hop)
  })
}

///|
fn reach_pattern_hop_type_matches(
  state : ReachState,
  edge : Int,
  type_index : Int,
) -> Bool {
  guard state.pattern is Some(pattern) &&
    @lower.graph_traverse_hop_type_at(pattern, state.pattern_hop, type_index)
    is Some(expected) else {
    return false
  }
  match @storage.edge_label(state.source, edge) {
    Some(Some({ value: @value.Text(actual), .. })) => actual == expected
    _ => false
  }
}

///|
fn prepare_reach_neighbor_predicate(
  state : ReachState,
  edge : Int,
  node : Int,
  next_phase : ReachPhase,
) -> Unit {
  state.candidate_edge = edge
  state.candidate_node = node
  state.neighbor_resume = next_phase
  state.predicate_field = 0
  state.predicate_input.clear()
  state.phase = if reach_edge_predicate(state) is Some(_) {
    PrepareHopEdgePredicate
  } else {
    PrepareHopNodePredicate
  }
}

///|
fn prepare_reach_neighbor(
  state : ReachState,
  edge : Int,
  node : Int,
  next_phase : ReachPhase,
) -> Unit {
  state.candidate_edge = edge
  state.candidate_node = node
  state.neighbor_resume = next_phase
  match reach_pattern_hop_type_count(state) {
    Some(0) => state.phase = next_phase
    Some(_) => {
      state.edge_type_index = 0
      state.phase = ScanHopEdgeTypes
    }
    None => prepare_reach_neighbor_predicate(state, edge, node, next_phase)
  }
}

///|
fn reach_edge_type_count(state : ReachState) -> Int? {
  match state.edge_filter {
    AllReachEdges => None
    TraversalReachEdgeTypes(prepared, hop) =>
      @lower.graph_traverse_hop_type_count(prepared, hop)
  }
}

///|
fn reach_edge_type_matches(
  state : ReachState,
  edge : Int,
  type_index : Int,
) -> Bool {
  guard state.edge_filter is TraversalReachEdgeTypes(prepared, hop) &&
    @lower.graph_traverse_hop_type_at(prepared, hop, type_index)
    is Some(expected) else {
    return false
  }
  match @storage.edge_label(state.source, edge) {
    Some(Some({ value: @value.Text(actual), .. })) => actual == expected
    _ => false
  }
}

///|
fn checked_reach_value(
  state : ReachState,
  field : @schema.Field,
) -> @value.CheckedValue? {
  if field.name == @schema.Unqualified("start_id") {
    return @storage.node_identity(state.source, state.current_start_node).bind(value => {
      @value.recheck_runtime_value(
        value.value,
        field.contract,
        state.value_limits,
      )
    })
  }
  if field.name == @schema.Unqualified("depth") {
    return @value.checked_number_value(
      state.depth[state.current_node].to_double(),
      field.contract,
    )
  }
  @storage.node_identity(state.source, state.current_node).bind(value => {
    @value.recheck_runtime_value(
      value.value,
      field.contract,
      state.value_limits,
    )
  })
}

///|
fn reach_step(
  state : ReachState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, ReachIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@graph.producer_read_available(state.input) ||
      !reach_starts_available(state) {
      return @bounded.Failed(ReachInputUnavailable, progress, used)
    }
    match state.phase {
      InitializeStartSelection =>
        if state.index < @storage.node_count(state.source) {
          state.start_selected.push(false)
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = match state.starts {
            TraversalPredicateStarts(_) => PrepareStartPredicate
            _ => ResolveStarts
          }
        }
      ResolveStarts =>
        if state.index < reach_start_count(state) {
          used += 1
          let start = match reach_start_at(state, state.index) {
            Ok(value) => value
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
          match @storage.node_index(state.source, start) {
            Err(issue) =>
              return @bounded.Failed(ReachGraph(issue), progress, used)
            Ok(None) =>
              return @bounded.Failed(ReachStartMissing, progress, used)
            Ok(Some(node)) => state.start_selected[node] = true
          }
          state.index += 1
        } else {
          state.index = 0
          state.phase = CollectStarts
        }
      PrepareStartPredicate =>
        if state.index >= @storage.node_count(state.source) {
          state.index = 0
          state.phase = CollectStarts
        } else if state.predicate_field < state.predicate_fields {
          used += 1
          guard graph_node_predicate_binding(
              state.graph,
              state.source,
              state.index,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(ReachInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard state.starts is TraversalPredicateStarts(predicate) else {
            return @bounded.Failed(InvalidReachKernel, progress, used)
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
              return @bounded.Failed(ReachPredicate(issue.kind), progress, used)
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateStartPredicate
            }
          }
        }
      EvaluateStartPredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidReachKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(ReachPredicate(issue.kind), progress, used)
          }
          Ok(@execution.PredicateExpressionContinue) => ()
          Ok(@execution.PredicateExpressionComplete(selected)) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            state.predicate_input.clear()
            state.start_selected[state.index] = selected
            state.index += 1
            state.predicate_field = 0
            state.phase = PrepareStartPredicate
          }
        }
      }
      CollectStarts =>
        if state.index < state.start_selected.length() {
          if state.start_selected[state.index] {
            state.start_nodes.push(state.index)
            state.start_scratch.push(None)
          }
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = InitializeNodes
        }
      InitializeNodes =>
        if state.index < @storage.node_count(state.source) {
          state.out_degree.push(0)
          state.in_degree.push(0)
          state.depth.push(-1)
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = ScanDegrees
        }
      ScanDegrees =>
        if state.index < @storage.edge_count(state.source) {
          guard @storage.edge_endpoints(state.source, state.index)
            is Some((source, target)) else {
            return @bounded.Failed(ReachInputUnavailable, progress, used)
          }
          used += 1
          match reach_edge_type_count(state) {
            None => {
              state.out_degree[source] += 1
              state.in_degree[target] += 1
              state.index += 1
            }
            Some(0) => state.index += 1
            Some(_) => {
              state.edge_type_index = 0
              state.phase = ScanDegreeTypes
            }
          }
        } else {
          state.index = 0
          state.out_start.push(0)
          state.in_start.push(0)
          state.phase = BuildOffsets
        }
      ScanDegreeTypes => {
        guard @storage.edge_endpoints(state.source, state.index)
          is Some((source, target)) &&
          reach_edge_type_count(state) is Some(type_count) else {
          return @bounded.Failed(ReachInputUnavailable, progress, used)
        }
        let matches = reach_edge_type_matches(
          state,
          state.index,
          state.edge_type_index,
        )
        state.edge_type_index += 1
        used += 1
        if matches {
          state.out_degree[source] += 1
          state.in_degree[target] += 1
          state.index += 1
          state.phase = ScanDegrees
        } else if state.edge_type_index >= type_count {
          state.index += 1
          state.phase = ScanDegrees
        }
      }
      BuildOffsets =>
        if state.index < @storage.node_count(state.source) {
          state.out_start.push(
            state.out_start[state.index] + state.out_degree[state.index],
          )
          state.in_start.push(
            state.in_start[state.index] + state.in_degree[state.index],
          )
          state.out_cursor.push(state.out_start[state.index])
          state.in_cursor.push(state.in_start[state.index])
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = InitializeEdges
        }
      InitializeEdges =>
        if state.index < @storage.edge_count(state.source) {
          state.out_edges.push(-1)
          state.in_edges.push(-1)
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = FillEdges
        }
      FillEdges =>
        if state.index < @storage.edge_count(state.source) {
          guard @storage.edge_endpoints(state.source, state.index)
            is Some((source, target)) else {
            return @bounded.Failed(ReachInputUnavailable, progress, used)
          }
          used += 1
          match reach_edge_type_count(state) {
            None => {
              let out = state.out_cursor[source]
              let incoming = state.in_cursor[target]
              state.out_edges[out] = state.index
              state.in_edges[incoming] = state.index
              state.out_cursor[source] = out + 1
              state.in_cursor[target] = incoming + 1
              state.index += 1
            }
            Some(0) => state.index += 1
            Some(_) => {
              state.edge_type_index = 0
              state.phase = FillEdgeTypes
            }
          }
        } else {
          state.index = 0
          state.width = 1
          state.phase = PrepareStartSort
        }
      FillEdgeTypes => {
        guard @storage.edge_endpoints(state.source, state.index)
          is Some((source, target)) &&
          reach_edge_type_count(state) is Some(type_count) else {
          return @bounded.Failed(ReachInputUnavailable, progress, used)
        }
        let matches = reach_edge_type_matches(
          state,
          state.index,
          state.edge_type_index,
        )
        state.edge_type_index += 1
        used += 1
        if matches {
          let out = state.out_cursor[source]
          let incoming = state.in_cursor[target]
          state.out_edges[out] = state.index
          state.in_edges[incoming] = state.index
          state.out_cursor[source] = out + 1
          state.in_cursor[target] = incoming + 1
          state.index += 1
          state.phase = FillEdges
        } else if state.edge_type_index >= type_count {
          state.index += 1
          state.phase = FillEdges
        }
      }
      PrepareStartSort =>
        if state.width >= state.start_nodes.length() {
          state.start_node_index = 0
          state.phase = StartNext
        } else {
          state.run_start = 0
          state.phase = PrepareStartMerge
        }
      PrepareStartMerge =>
        if state.run_start >= state.start_nodes.length() {
          state.copy_index = 0
          state.phase = CopyStartPass
        } else {
          prepare_start_merge(state)
        }
      StartMerge => {
        if state.left_index >= state.middle {
          emit_start_merge(state, false)
        } else if state.right_index >= state.run_end {
          emit_start_merge(state, true)
        } else {
          state.phase = CompareStartMerge
        }
        used += 1
      }
      CompareStartMerge => {
        used += 1
        match
          compare_reach_nodes(
            state,
            state.start_nodes[state.left_index],
            state.start_nodes[state.right_index],
          ) {
          Ok(order) => emit_start_merge(state, order <= 0)
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyStartPass =>
        if state.copy_index < state.start_nodes.length() {
          guard state.start_scratch[state.copy_index] is Some(node) else {
            return @bounded.Failed(InvalidReachKernel, progress, used)
          }
          state.start_nodes[state.copy_index] = node
          state.start_scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.start_nodes.length() / 2 {
            state.start_nodes.length()
          } else {
            state.width * 2
          }
          state.phase = PrepareStartSort
        }
      StartNext =>
        if state.start_node_index >= state.start_nodes.length() {
          state.phase = Finish
        } else {
          state.current_start_node = state.start_nodes[state.start_node_index]
          state.index = 0
          state.queue.clear()
          state.selected.clear()
          state.scratch.clear()
          state.phase = ResetDepth
        }
      ResetDepth =>
        if state.index < state.depth.length() {
          state.depth[state.index] = -1
          state.index += 1
          used += 1
        } else {
          state.depth[state.current_start_node] = 0
          state.queue.push(state.current_start_node)
          if state.minimum_depth == 0 {
            state.selected.push(state.current_start_node)
            state.scratch.push(None)
          }
          state.index = 0
          state.pattern_hop = 0
          state.phase = PopNode
        }
      CopyPatternFrontier =>
        if state.copy_index < state.selected.length() {
          state.queue.push(state.selected[state.copy_index])
          state.copy_index += 1
          used += 1
        } else {
          state.selected.clear()
          state.scratch.clear()
          state.index = 0
          state.pattern_hop += 1
          state.phase = PopNode
        }
      PopNode =>
        if state.index >= state.queue.length() {
          match state.pattern {
            Some(pattern) if state.pattern_hop + 1 <
              @lower.graph_traverse_hop_count(pattern) => {
              state.queue.clear()
              state.copy_index = 0
              state.phase = CopyPatternFrontier
            }
            _ => {
              state.width = 1
              state.phase = PrepareSort
            }
          }
        } else {
          state.current_node = state.queue[state.index]
          state.index += 1
          state.neighbor_index = state.out_start[state.current_node]
          state.phase = if state.pattern is None &&
            state.depth[state.current_node] >= state.max_depth {
            PopNode
          } else {
            ScanOutgoing
          }
          used += 1
        }
      ScanOutgoing => {
        guard reach_direction(state) is Some(direction) else {
          return @bounded.Failed(InvalidReachKernel, progress, used)
        }
        let enabled = direction != @graph_type.Incoming
        let end = state.out_start[state.current_node + 1]
        if !enabled || state.neighbor_index >= end {
          state.neighbor_index = state.in_start[state.current_node]
          state.phase = ScanIncoming
        } else {
          let edge = state.out_edges[state.neighbor_index]
          state.neighbor_index += 1
          used += 1
          guard @storage.edge_endpoints(state.source, edge) is Some((_, node)) else {
            return @bounded.Failed(ReachInputUnavailable, progress, used)
          }
          prepare_reach_neighbor(state, edge, node, ScanOutgoing)
        }
      }
      ScanIncoming => {
        guard reach_direction(state) is Some(direction) else {
          return @bounded.Failed(InvalidReachKernel, progress, used)
        }
        let enabled = direction != @graph_type.Outgoing
        let end = state.in_start[state.current_node + 1]
        if !enabled || state.neighbor_index >= end {
          state.phase = PopNode
        } else {
          let edge = state.in_edges[state.neighbor_index]
          state.neighbor_index += 1
          used += 1
          guard @storage.edge_endpoints(state.source, edge) is Some((node, _)) else {
            return @bounded.Failed(ReachInputUnavailable, progress, used)
          }
          prepare_reach_neighbor(state, edge, node, ScanIncoming)
        }
      }
      ScanHopEdgeTypes => {
        guard reach_pattern_hop_type_count(state) is Some(type_count) else {
          return @bounded.Failed(InvalidReachKernel, progress, used)
        }
        let matches = reach_pattern_hop_type_matches(
          state,
          state.candidate_edge,
          state.edge_type_index,
        )
        state.edge_type_index += 1
        used += 1
        if matches {
          prepare_reach_neighbor_predicate(
            state,
            state.candidate_edge,
            state.candidate_node,
            state.neighbor_resume,
          )
        } else if state.edge_type_index >= type_count {
          state.phase = state.neighbor_resume
        }
      }
      PrepareHopEdgePredicate =>
        if state.predicate_field <
          graph_edge_predicate_binding_count(state.graph) {
          used += 1
          guard graph_edge_predicate_binding(
              state.graph,
              state.source,
              state.candidate_edge,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(ReachInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard reach_edge_predicate(state) is Some(predicate) else {
            return @bounded.Failed(InvalidReachKernel, progress, used)
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
              return @bounded.Failed(ReachPredicate(issue.kind), progress, used)
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateHopEdgePredicate
            }
          }
        }
      EvaluateHopEdgePredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidReachKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(ReachPredicate(issue.kind), progress, used)
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
              state.neighbor_resume
            } else if reach_node_predicate(state) is Some(_) {
              PrepareHopNodePredicate
            } else {
              VisitHopNeighbor
            }
          }
        }
      }
      PrepareHopNodePredicate =>
        if state.predicate_field <
          graph_node_predicate_binding_count(state.graph) {
          used += 1
          guard graph_node_predicate_binding(
              state.graph,
              state.source,
              state.candidate_node,
              state.predicate_field,
            )
            is Some((name, value)) else {
            return @bounded.Failed(ReachInputUnavailable, progress, used)
          }
          state.predicate_input[name] = value
          state.predicate_field += 1
        } else {
          guard reach_node_predicate(state) is Some(predicate) else {
            state.phase = VisitHopNeighbor
            continue
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
              return @bounded.Failed(ReachPredicate(issue.kind), progress, used)
            Ok(execution) => {
              state.predicate_execution = Some(execution)
              state.phase = EvaluateHopNodePredicate
            }
          }
        }
      EvaluateHopNodePredicate => {
        used += 1
        guard state.predicate_execution is Some(execution) else {
          return @bounded.Failed(InvalidReachKernel, progress, used)
        }
        match @execution.advance_predicate_expression(execution) {
          Err(issue) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            return @bounded.Failed(ReachPredicate(issue.kind), progress, used)
          }
          Ok(@execution.PredicateExpressionContinue) => ()
          Ok(@execution.PredicateExpressionComplete(selected)) => {
            state.predicate_work_remaining = @execution.predicate_expression_remaining(
              execution,
            )
            state.predicate_execution = None
            state.predicate_input.clear()
            state.predicate_field = 0
            state.phase = if selected {
              VisitHopNeighbor
            } else {
              state.neighbor_resume
            }
          }
        }
      }
      VisitHopNeighbor => {
        used += 1
        match visit_reach_neighbor(state, state.candidate_node) {
          Ok(_) => state.phase = state.neighbor_resume
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      PrepareSort =>
        if state.width >= state.selected.length() {
          state.row_index = 0
          state.phase = SelectRow
        } else {
          state.run_start = 0
          state.phase = PrepareMerge
        }
      PrepareMerge =>
        if state.run_start >= state.selected.length() {
          state.copy_index = 0
          state.phase = CopyPass
        } else {
          prepare_reach_merge(state)
        }
      Merge => {
        if state.left_index >= state.middle {
          emit_reach_merge(state, false)
        } else if state.right_index >= state.run_end {
          emit_reach_merge(state, true)
        } else {
          state.phase = CompareMerge
        }
        used += 1
      }
      CompareMerge => {
        used += 1
        match
          compare_reach_nodes(
            state,
            state.selected[state.left_index],
            state.selected[state.right_index],
          ) {
          Ok(order) => emit_reach_merge(state, order <= 0)
          Err(issue) => return @bounded.Failed(issue, progress, used)
        }
      }
      CopyPass =>
        if state.copy_index < state.selected.length() {
          guard state.scratch[state.copy_index] is Some(node) else {
            return @bounded.Failed(InvalidReachKernel, progress, used)
          }
          state.selected[state.copy_index] = node
          state.scratch[state.copy_index] = None
          state.copy_index += 1
          used += 1
        } else {
          state.width = if state.width > state.selected.length() / 2 {
            state.selected.length()
          } else {
            state.width * 2
          }
          state.phase = PrepareSort
        }
      SelectRow =>
        if state.row_index >= state.selected.length() {
          state.start_node_index += 1
          state.phase = StartNext
        } else {
          state.current_node = state.selected[state.row_index]
          state.row_index += 1
          state.column = 0
          state.values = []
          state.phase = ReadField
          used += 1
        }
      ReadField =>
        if state.column < @schema.field_count(state.schema) {
          used += 1
          guard @schema.field_at(state.schema, state.column) is Some(field) &&
            checked_reach_value(state, field) is Some(value) else {
            return @bounded.Failed(InvalidReachKernel, progress, used)
          }
          state.values.push(value)
          state.column += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidReachKernel, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.values = []
            state.phase = SelectRow
            progress += 1
          }
          Err(issue) =>
            return @bounded.Failed(ReachOutput(issue), progress, used)
        }
      }
      Finish => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidReachKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(ReachOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) => @bounded.Failed(ReachCompletion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_reach_state(state : ReachState) -> Bool {
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  state.out_degree.clear()
  state.in_degree.clear()
  state.out_start.clear()
  state.in_start.clear()
  state.out_cursor.clear()
  state.in_cursor.clear()
  state.out_edges.clear()
  state.in_edges.clear()
  state.depth.clear()
  state.queue.clear()
  state.selected.clear()
  state.scratch.clear()
  state.start_selected.clear()
  state.start_nodes.clear()
  state.start_scratch.clear()
  state.predicate_input.clear()
  state.predicate_execution = None
  state.values = []
  true
}

///|
fn start_reach_state(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @graph.ProducerRead,
  source : @storage.Storage,
  schema : @schema.Schema,
  starts : ReachStarts,
  pattern : @lower.PreparedGraphTraverse?,
  direction : @graph_type.Direction,
  edge_filter : ReachEdgeFilter,
  edge_predicate : @lower.Expression?,
  node_predicate : @lower.Expression?,
  minimum_depth : Int,
  max_depth : Int,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  inputs : Array[@execution.ProducerRead],
) -> Result[ReachExecution, ReachIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) else {
    return Err(InvalidReachKernel)
  }
  let nodes = @storage.node_count(source)
  let edges = @storage.edge_count(source)
  guard @storage.carrier(source) is @carrier.GraphValue(graph) else {
    return Err(InvalidReachKernel)
  }
  let start_count = match starts {
    SingleReachStart(_) => 1
    TraversalReachStarts(prepared) =>
      @lower.graph_traverse_start_id_count(prepared)
    TraversalRelationStarts(selector, _) =>
      @execution.producer_read_row_count(selector)
    TraversalPredicateStarts(_) => nodes
  }
  let starts_valid = match starts {
    TraversalReachStarts(_) => start_count > 0
    _ => true
  }
  guard minimum_depth >= 0 &&
    max_depth >= minimum_depth &&
    max_rows >= 0 &&
    starts_valid else {
    return Err(ReachOutputLimit)
  }
  let start_predicate_fields = match starts {
    TraversalPredicateStarts(_) => graph_node_predicate_binding_count(graph)
    _ => 0
  }
  let mut has_edge_predicate = edge_predicate is Some(_)
  let mut has_node_predicate = node_predicate is Some(_)
  match pattern {
    Some(prepared) =>
      for hop in 0..<@lower.graph_traverse_hop_count(prepared) {
        if @lower.graph_traverse_hop_edge_predicate(prepared, hop) is Some(_) {
          has_edge_predicate = true
        }
        if @lower.graph_traverse_hop_node_predicate(prepared, hop) is Some(_) {
          has_node_predicate = true
        }
      }
    None => ()
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
  let predicate_fields = Int::max(
    start_predicate_fields,
    Int::max(edge_predicate_fields, node_predicate_fields),
  )
  guard reach_workspace(nodes, edges, @schema.field_count(schema))
    is Some(base_workspace) &&
    checked_reach_add(base_workspace, predicate_fields) is Some(workspace) &&
    workspace <= max_workspace_slots else {
    return Err(ReachWorkspaceLimit)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(ReachOutput(issue))
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
      return Err(ReachCompletion(issue))
    }
  }
  let state : ReachState = {
    input,
    source,
    graph,
    schema,
    starts,
    pattern,
    direction,
    edge_filter,
    edge_predicate,
    node_predicate,
    minimum_depth,
    max_depth,
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
    index: 0,
    current_node: -1,
    current_start_node: -1,
    start_node_index: 0,
    neighbor_index: 0,
    candidate_edge: -1,
    candidate_node: -1,
    neighbor_resume: ScanOutgoing,
    pattern_hop: 0,
    edge_type_index: 0,
    row_index: 0,
    column: 0,
    out_degree: [],
    in_degree: [],
    out_start: [],
    in_start: [],
    out_cursor: [],
    in_cursor: [],
    out_edges: [],
    in_edges: [],
    depth: [],
    queue: [],
    selected: [],
    scratch: [],
    start_selected: [],
    start_nodes: [],
    start_scratch: [],
    predicate_fields,
    predicate_workspace: max_workspace_slots - workspace,
    predicate_work_remaining: limits.max_work,
    predicate_input: Map([]),
    predicate_execution: None,
    predicate_field: 0,
    width: 1,
    run_start: 0,
    middle: 0,
    run_end: 0,
    left_index: 0,
    right_index: 0,
    merge_index: 0,
    copy_index: 0,
    values: [],
  }
  let (session, token) = @bounded.start(
    control,
    state,
    reach_step,
    cleanup_reach_state,
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
pub fn start_reach(
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
) -> Result[ReachExecution, ReachIssue] {
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphReachStep(prepared)) &&
    @lower.graph_reach_max_depth(prepared) is Some(max_depth) &&
    @graph.producer_read_storage(input) is Some(source) else {
    return Err(InvalidReachKernel)
  }
  start_reach_state(
    control,
    preparation,
    sequence,
    step,
    input,
    source,
    @lower.graph_reach_output_schema(prepared),
    SingleReachStart(@lower.graph_reach_start(prepared)),
    None,
    @lower.graph_reach_direction(prepared),
    AllReachEdges,
    None,
    None,
    0,
    max_depth,
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    inputs,
  )
}

///|
pub fn reach_max_noninterruptible_value_nodes(value : ReachExecution) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn reach_max_noninterruptible_value_bytes(value : ReachExecution) -> Int {
  value.max_noninterruptible_value_bytes
}

///|
pub fn advance_reach(
  value : ReachExecution,
  quantum : Int,
) -> Result[ReachPoll, ReachIssue] {
  guard value.token is Some(token) else {
    return Err(ReachExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(ReachExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(ReachContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(ReachComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(ReachFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(ReachStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn reach_stopped(value : ReachExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn reach_cleanup_pending(value : ReachExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_reach(value : ReachExecution) -> Result[Bool, ReachIssue] {
  @bounded.cleanup(value.session).map_err(issue => ReachExecutionIssue(issue))
}
