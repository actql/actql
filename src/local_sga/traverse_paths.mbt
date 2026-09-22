///|
priv struct TraversalPath {
  nodes : Array[Int]
  edges : Array[Int]
}

///|
priv enum TraversePathsPhase {
  ResolveStarts
  SortStarts
  BeginDepth
  ScanEdge
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
  schema : @schema.Schema
  prepared : @lower.PreparedGraphTraverse
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
  mut sort_index : Int
  mut sort_cursor : Int
  frontier : Array[TraversalPath]
  next_frontier : Array[TraversalPath]
  mut depth : Int
  mut path_index : Int
  mut edge_occurrence : Int
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
  TraversePathsKeyOrder(@value.KeyOrderIssue)
  TraversePathsOutput(@execution.CaptureIssue)
  TraversePathsCompletion(@execution.TrustedOutputIssue)
  TraversePathsExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

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
    if state.direction != @graph_type.Both || from == to || to != current {
      return None
    }
    Some((from, edge))
  } else if state.direction == @graph_type.Incoming {
    if to == current {
      Some((from, edge))
    } else {
      None
    }
  } else if state.direction == @graph_type.Outgoing {
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
fn traversal_edge_type_matches(state : TraversePathsState, edge : Int) -> Bool {
  match @lower.graph_traverse_hop_type_count(state.prepared, 0) {
    None => true
    Some(0) => false
    Some(count) => {
      guard @storage.edge_label(state.source, edge)
        is Some(Some({ value: @value.Text(actual), .. })) else {
        return false
      }
      for index in 0..<count {
        if @lower.graph_traverse_hop_type_at(state.prepared, 0, index) ==
          Some(actual) {
          return true
        }
      }
      false
    }
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
    if !@graph.producer_read_available(state.input) {
      return @bounded.Failed(TraversePathsInputUnavailable, progress, used)
    }
    match state.phase {
      ResolveStarts =>
        if state.start_scan <
          @lower.graph_traverse_start_id_count(state.prepared) {
          used += 1
          guard @lower.graph_traverse_start_id_at(
              state.prepared,
              state.start_scan,
            )
            is Some(identity) else {
            return @bounded.Failed(InvalidTraversePathsKernel, progress, used)
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
          let occurrences = if state.direction == @graph_type.Both {
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
              !path_contains_node(path, node) &&
              traversal_edge_type_matches(state, edge) {
              let next_slots = path.nodes.length() + path.edges.length() + 3
              if next_slots > state.max_workspace_slots - state.workspace_slots {
                return @bounded.Failed(
                  TraversePathsWorkspaceLimit,
                  progress,
                  used,
                )
              }
              if state.depth + 1 >= state.minimum_depth &&
                state.emitted + state.next_frontier.length() >= state.max_rows {
                return @bounded.Failed(TraversePathsOutputLimit, progress, used)
              }
              let nodes = path.nodes.copy()
              let edges = path.edges.copy()
              nodes.push(node)
              edges.push(edge)
              let next = { nodes, edges, }
              state.workspace_slots += next_slots
              state.next_frontier.push(next)
            }
          }
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
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphTraverseStep(prepared)) &&
    @lower.graph_traverse_emits_paths(prepared) &&
    !@lower.graph_traverse_patterned(prepared) &&
    @lower.graph_traverse_bounds(prepared) is Some((minimum, maximum)) &&
    minimum <= 2147483647L &&
    maximum <= 2147483647L &&
    @lower.graph_traverse_start_id_count(prepared) > 0 &&
    @lower.graph_traverse_start_relation_field(prepared) is None &&
    @lower.graph_traverse_start_predicate(prepared) is None &&
    @lower.graph_traverse_hop_direction(prepared, 0) is Some(direction) &&
    @lower.graph_traverse_hop_edge_predicate(prepared, 0) is None &&
    @lower.graph_traverse_hop_node_predicate(prepared, 0) is None &&
    @graph.producer_read_storage(input) is Some(source) &&
    (direction != @graph_type.Both || @storage.edge_count(source) <= 1073741823) &&
    max_rows >= 0 &&
    max_workspace_slots >= 0 else {
    return Err(InvalidTraversePathsKernel)
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
  if node_count > max_workspace_slots {
    @execution.cancel_admitted_output(output) |> ignore
    return Err(TraversePathsWorkspaceLimit)
  }
  let state : TraversePathsState = {
    input,
    source,
    schema: @lower.graph_traverse_output_schema(prepared),
    prepared,
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
    phase: ResolveStarts,
    start_scan: 0,
    start_selected: Array::make(node_count, false),
    sort_index: 0,
    sort_cursor: 0,
    frontier: [],
    next_frontier: [],
    depth: 0,
    path_index: 0,
    edge_occurrence: 0,
    emit_index: 0,
    column: 0,
    values: [],
    emitted: 0,
    workspace_slots: node_count,
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
