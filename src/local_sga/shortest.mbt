///|
priv enum ShortestPhase {
  InitializeNodes
  FinishOffsets
  ScanDegrees
  BuildOffsets
  InitializeEdges
  CopyCursors
  FillEdges
  ResolveEndpoints
  StartSearch
  ScanNeighbor
  PreparePath
  ReconstructPath
  ReverseNodes
  ReverseEdges
  ReadField
  CommitRow
  Finish
}

///|
priv struct ShortestState {
  input : @graph.ProducerRead
  source : @storage.Storage
  schema : @schema.Schema
  value_limits : @value.Limits
  direction : @graph_type.Direction
  source_id : @value.CheckedValue
  target_id : @value.CheckedValue
  max_hops : Int
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : ShortestPhase
  mut index : Int
  mut source_node : Int
  mut target_node : Int
  mut queue_index : Int
  mut neighbor_index : Int
  mut path_cursor : Int
  mut reverse_index : Int
  mut row_column : Int
  mut has_path : Bool
  degree : Array[Int]
  start : Array[Int]
  cursor : Array[Int]
  neighbor : Array[Int]
  edge : Array[Int]
  depth : Array[Int]
  predecessor : Array[Int]
  predecessor_edge : Array[Int]
  queue : Array[Int]
  path_nodes : Array[Int]
  path_edges : Array[Int]
  mut values : Array[@value.CheckedValue]
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
fn shortest_workspace(nodes : Int, edges : Int, both : Bool) -> Int? {
  let directed_edges = if both {
    checked_shortest_multiply(edges, 2)
  } else {
    Some(edges)
  }
  guard directed_edges is Some(directed_edges) &&
    checked_shortest_multiply(nodes, 8) is Some(node_slots) &&
    checked_shortest_multiply(directed_edges, 2) is Some(edge_slots) &&
    checked_shortest_add(node_slots, edge_slots) is Some(total) &&
    checked_shortest_add(total, 1) is Some(total) else {
    return None
  }
  Some(total)
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
      @value.recheck_runtime_value(
        state.source_id.value,
        field.contract,
        state.value_limits,
      )
    @schema.Unqualified("target_id") =>
      @value.recheck_runtime_value(
        state.target_id.value,
        field.contract,
        state.value_limits,
      )
    @schema.Unqualified("total_cost") | @schema.Unqualified("hop_count") =>
      @value.checked_number_value(
        state.path_edges.length().to_double(),
        field.contract,
      )
    @schema.Unqualified("node_ids") => {
      let values : Array[@value.Value] = []
      for node in state.path_nodes {
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
      for edge in state.path_edges {
        guard @storage.edge_endpoints(state.source, edge)
          is Some((source, target)) &&
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
          is Some(identity) else {
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
    if !@graph.producer_read_available(state.input) {
      return @bounded.Failed(ShortestInputUnavailable, progress, used)
    }
    match state.phase {
      InitializeNodes =>
        if state.index < @storage.node_count(state.source) {
          state.degree.push(0)
          state.start.push(0)
          state.cursor.push(0)
          state.depth.push(-1)
          state.predecessor.push(-1)
          state.predecessor_edge.push(-1)
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
          state.degree[source] += 1
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = BuildOffsets
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
          let at = state.cursor[source]
          state.neighbor[at] = target
          state.edge[at] = edge
          state.cursor[source] = at + 1
          state.index += 1
          used += 1
        } else {
          state.phase = ResolveEndpoints
        }
      ResolveEndpoints => {
        let source_node = match
          @storage.node_index(state.source, state.source_id) {
          Ok(Some(value)) => value
          Ok(None) =>
            return @bounded.Failed(ShortestEndpointMissing, progress, used)
          Err(issue) =>
            return @bounded.Failed(ShortestStorage(issue), progress, used)
        }
        let target_node = match
          @storage.node_index(state.source, state.target_id) {
          Ok(Some(value)) => value
          Ok(None) =>
            return @bounded.Failed(ShortestEndpointMissing, progress, used)
          Err(issue) =>
            return @bounded.Failed(ShortestStorage(issue), progress, used)
        }
        state.source_node = source_node
        state.target_node = target_node
        state.phase = StartSearch
        used += 1
      }
      StartSearch => {
        state.depth[state.source_node] = 0
        state.queue.push(state.source_node)
        state.queue_index = 0
        state.has_path = state.source_node == state.target_node
        state.phase = if state.has_path { PreparePath } else { ScanNeighbor }
        used += 1
      }
      ScanNeighbor =>
        if state.queue_index >= state.queue.length() {
          state.phase = Finish
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
          state.row_column = 0
          state.phase = ReadField
        }
      }
      ReadField =>
        if state.row_column < @schema.field_count(state.schema) {
          guard @schema.field_at(state.schema, state.row_column) is Some(field) &&
            shortest_path_value(state, field) is Some(value) else {
            return @bounded.Failed(ShortestInputUnavailable, progress, used)
          }
          state.values.push(value)
          state.row_column += 1
          used += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(UnsupportedShortestKernel, progress, used)
        }
        match @execution.append_admitted_output(output, state.values) {
          Ok(_) => {
            state.values = []
            state.phase = Finish
            progress += 1
            used += 1
          }
          Err(issue) =>
            return @bounded.Failed(ShortestOutput(issue), progress, used)
        }
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
  state.depth.clear()
  state.predecessor.clear()
  state.predecessor_edge.clear()
  state.queue.clear()
  state.path_nodes.clear()
  state.path_edges.clear()
  state.values = []
  true
}

///|
/// Start the bounded scalar, unweighted shortest-path kernel. Selected
/// endpoints, label filters and weighted paths are admitted by later kernels;
/// this implementation rejects them before execution rather than changing
/// their meaning.
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
    @lower.graph_shortest_endpoint_single(prepared, @schema.Left)
    is Some(source_id) &&
    @lower.graph_shortest_endpoint_single(prepared, @schema.Right)
    is Some(target_id) &&
    @lower.graph_shortest_selection(prepared) == @graph_type.EachPair &&
    @lower.graph_shortest_weight(prepared) is None &&
    @lower.graph_shortest_type_count(prepared) is None &&
    @lower.graph_shortest_max_hops(prepared) is Some(max_hops) else {
    return Err(UnsupportedShortestKernel)
  }
  let nodes = @storage.node_count(source)
  let edges = @storage.edge_count(source)
  let direction = @lower.graph_shortest_direction(prepared)
  guard max_rows >= 1 &&
    shortest_workspace(nodes, edges, direction == @graph_type.Both)
    is Some(workspace) &&
    workspace <= max_workspace_slots else {
    return Err(ShortestWorkspaceLimit)
  }
  if @lower.graph_shortest_output_guard(prepared) is Some(guard_rows) &&
    guard_rows < 1L {
    return Err(ShortestOutputLimit)
  }
  let output = match
    @execution.prepare_admitted_output(owner, @pipeline.Step(step), 1, limits) {
    Ok(value) => value
    Err(issue) => return Err(ShortestOutput(issue))
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
      return Err(ShortestCompletion(issue))
    }
  }
  let state : ShortestState = {
    input,
    source,
    schema: @lower.graph_shortest_output_schema(prepared),
    value_limits: {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_text_bytes,
    },
    direction,
    source_id,
    target_id,
    max_hops,
    output: Some(output),
    rows,
    live,
    accepted,
    port,
    phase: InitializeNodes,
    index: 0,
    source_node: -1,
    target_node: -1,
    queue_index: 0,
    neighbor_index: 0,
    path_cursor: -1,
    reverse_index: 0,
    row_column: 0,
    has_path: false,
    degree: [],
    start: [],
    cursor: [],
    neighbor: [],
    edge: [],
    depth: [],
    predecessor: [],
    predecessor_edge: [],
    queue: [],
    path_nodes: [],
    path_edges: [],
    values: [],
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
