///|
priv enum ReachPhase {
  InitializeNodes
  ScanDegrees
  BuildOffsets
  InitializeEdges
  FillEdges
  FindStart
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
priv struct ReachState {
  input : @graph.ProducerRead
  source : @storage.Storage
  schema : @schema.Schema
  start : @value.CheckedValue
  direction : @graph_type.Direction
  edge_type : String?
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
  mut neighbor_index : Int
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
  ReachKeyOrder(@value.KeyOrderIssue)
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
  guard checked_reach_multiply(nodes, 10) is Some(node_slots) &&
    checked_reach_multiply(edges, 2) is Some(edge_slots) &&
    checked_reach_add(node_slots, 2) is Some(node_slots) &&
    checked_reach_add(node_slots, edge_slots) is Some(graph_slots) &&
    checked_reach_add(graph_slots, width) is Some(total) else {
    return None
  }
  Some(total)
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
  if depth < 0 {
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
fn reach_edge_allowed(state : ReachState, edge : Int) -> Bool {
  guard state.edge_type is Some(expected) else { return true }
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
    return @value.recheck_runtime_value(
      state.start.value,
      field.contract,
      state.value_limits,
    )
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
    if !@graph.producer_read_available(state.input) {
      return @bounded.Failed(ReachInputUnavailable, progress, used)
    }
    match state.phase {
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
          if reach_edge_allowed(state, state.index) {
            state.out_degree[source] += 1
            state.in_degree[target] += 1
          }
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.out_start.push(0)
          state.in_start.push(0)
          state.phase = BuildOffsets
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
          if reach_edge_allowed(state, state.index) {
            let out = state.out_cursor[source]
            let incoming = state.in_cursor[target]
            state.out_edges[out] = target
            state.in_edges[incoming] = source
            state.out_cursor[source] = out + 1
            state.in_cursor[target] = incoming + 1
          }
          state.index += 1
          used += 1
        } else {
          state.index = 0
          state.phase = FindStart
        }
      FindStart =>
        if state.index < @storage.node_count(state.source) {
          used += 1
          guard @storage.node_identity(state.source, state.index)
            is Some(identity) else {
            return @bounded.Failed(ReachInputUnavailable, progress, used)
          }
          match @value.compare_key_values(identity, state.start) {
            Err(issue) =>
              return @bounded.Failed(ReachKeyOrder(issue), progress, used)
            Ok(0) => {
              state.depth[state.index] = 0
              state.queue.push(state.index)
              if state.minimum_depth == 0 {
                state.selected.push(state.index)
                state.scratch.push(None)
              }
              state.index = 0
              state.phase = PopNode
            }
            Ok(_) => state.index += 1
          }
        } else {
          return @bounded.Failed(ReachStartMissing, progress, used)
        }
      PopNode =>
        if state.index >= state.queue.length() {
          state.width = 1
          state.phase = PrepareSort
        } else {
          state.current_node = state.queue[state.index]
          state.index += 1
          state.neighbor_index = state.out_start[state.current_node]
          state.phase = if state.depth[state.current_node] >= state.max_depth {
            PopNode
          } else {
            ScanOutgoing
          }
          used += 1
        }
      ScanOutgoing => {
        let enabled = state.direction != @graph_type.Incoming
        let end = state.out_start[state.current_node + 1]
        if !enabled || state.neighbor_index >= end {
          state.neighbor_index = state.in_start[state.current_node]
          state.phase = ScanIncoming
        } else {
          let node = state.out_edges[state.neighbor_index]
          state.neighbor_index += 1
          used += 1
          match visit_reach_neighbor(state, node) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
        }
      }
      ScanIncoming => {
        let enabled = state.direction != @graph_type.Outgoing
        let end = state.in_start[state.current_node + 1]
        if !enabled || state.neighbor_index >= end {
          state.phase = PopNode
        } else {
          let node = state.in_edges[state.neighbor_index]
          state.neighbor_index += 1
          used += 1
          match visit_reach_neighbor(state, node) {
            Ok(_) => ()
            Err(issue) => return @bounded.Failed(issue, progress, used)
          }
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
          state.phase = Finish
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
  start : @value.CheckedValue,
  direction : @graph_type.Direction,
  edge_type : String?,
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
  guard minimum_depth >= 0 &&
    max_depth >= minimum_depth &&
    max_rows >= 0 &&
    nodes <= max_rows else {
    return Err(ReachOutputLimit)
  }
  guard reach_workspace(nodes, edges, @schema.field_count(schema))
    is Some(workspace) &&
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
    schema,
    start,
    direction,
    edge_type,
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
    phase: InitializeNodes,
    index: 0,
    current_node: -1,
    neighbor_index: 0,
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
    @lower.graph_reach_start(prepared),
    @lower.graph_reach_direction(prepared),
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
