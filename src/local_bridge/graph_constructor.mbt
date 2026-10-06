///|
/// Current construction and snapshot reload share the existing bounded session,
/// Graph output builder and retention owner. No historical tuple constructor.
priv enum GraphConstructionState {
  GraphConstruction(GraphState)
  GraphSnapshotReload(GraphSnapshotState)
}

///|
priv enum GraphReadPhase {
  BeginElement
  ReadKeys
  ReadSource
  ReadTarget
  ReadProperties
  CommitElement
  VerifyInputs
  FinishGraph
}

///|
priv struct GraphRowBinding {
  input : Int
  definition : Int
  edge : Bool
  keys : Array[Int]
  source : Array[Int]
  target : Array[Int]
  properties : Array[Int]
}

///|
priv struct GraphState {
  inputs : Array[@execution.ProducerRead]
  bindings : Array[GraphRowBinding]
  value_limits : @value.Limits
  mut output : @graph.OutputBuilder?
  mut element : Int
  mut row : Int
  mut column : Int
  mut phase : GraphReadPhase
  mut keys : Array[@value.CheckedValue]
  mut source : Array[@value.CheckedValue]
  mut target : Array[@value.CheckedValue]
  mut properties : Array[@value.CheckedValue]
  mut control_work_remaining : Int?
}

///|
fn graph_construction_step(
  state : GraphConstructionState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, GraphBridgeIssue] {
  match state {
    GraphConstruction(value) => bounded_graph_step(value, quantum, reader)
    GraphSnapshotReload(value) =>
      graph_snapshot_reload_step(value, quantum, reader)
  }
}

///|
fn cleanup_graph_construction_state(state : GraphConstructionState) -> Bool {
  match state {
    GraphConstruction(value) => {
      if value.output is Some(output) {
        @graph.cancel_output(output) |> ignore
        value.output = None
      }
      value.keys = []
      value.source = []
      value.target = []
      value.properties = []
      true
    }
    GraphSnapshotReload(value) => cleanup_graph_snapshot_reload(value)
  }
}

///|
fn graph_step(
  state : GraphState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, GraphBridgeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    match state.phase {
      BeginElement => {
        used += 1
        if state.element == state.bindings.length() {
          state.column = 0
          state.phase = VerifyInputs
          continue
        }
        let binding = state.bindings[state.element]
        let input = state.inputs[binding.input]
        if !@execution.producer_read_available(input) {
          return @bounded.Failed(GraphInputUnavailable, progress, used)
        }
        if state.row == @execution.producer_read_row_count(input) {
          state.element += 1
          state.row = 0
        } else {
          state.column = 0
          state.phase = ReadKeys
        }
      }
      ReadKeys | ReadSource | ReadTarget | ReadProperties => {
        let binding = state.bindings[state.element]
        let input = state.inputs[binding.input]
        if !@execution.producer_read_available(input) {
          return @bounded.Failed(GraphInputUnavailable, progress, used)
        }
        let (columns, values, next) = match state.phase {
          ReadKeys => (binding.keys, state.keys, ReadSource)
          ReadSource => (binding.source, state.source, ReadTarget)
          ReadTarget => (binding.target, state.target, ReadProperties)
          _ => (binding.properties, state.properties, CommitElement)
        }
        if state.column == columns.length() {
          state.column = 0
          state.phase = next
        } else {
          used += 1
          guard graph_checked_cell(
              input,
              state.row,
              columns[state.column],
              state.value_limits,
            )
            is Some(value) else {
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          }
          values.push(value)
          state.column += 1
        }
      }
      CommitElement => {
        used += 1
        let binding = state.bindings[state.element]
        if !@execution.producer_read_available(state.inputs[binding.input]) {
          return @bounded.Failed(GraphInputUnavailable, progress, used)
        }
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        // The shared builder validates all keys/properties, registers duplicate
        // edge keys, then excludes missing endpoints. No semijoin can hide a
        // duplicate definition key before this boundary.
        let appended = if binding.edge {
          @graph.append_edge(
            output,
            binding.definition,
            state.keys,
            state.source,
            state.target,
            state.properties,
          )
        } else {
          @graph.append_node(
            output,
            binding.definition,
            state.keys,
            state.properties,
          )
        }
        match appended {
          Err(_) =>
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          Ok(_) => ()
        }
        state.keys = []
        state.source = []
        state.target = []
        state.properties = []
        state.row += 1
        state.phase = BeginElement
        progress += 1
      }
      VerifyInputs => {
        used += 1
        if state.column == state.inputs.length() {
          state.phase = FinishGraph
        } else {
          if !@execution.producer_read_available(state.inputs[state.column]) {
            return @bounded.Failed(GraphInputUnavailable, progress, used)
          }
          state.column += 1
        }
      }
      FinishGraph => {
        used += 1
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        state.output = None
        return match @graph.finish_output(output) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(_) => @bounded.Failed(InvalidGraphKernel, progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn bounded_graph_step(
  state : GraphState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, GraphBridgeIssue] {
  if @bounded.stop_requested(reader) is Some(reason) {
    return @bounded.Stopped(reason, 0, 0)
  }
  let bounded_quantum = match state.control_work_remaining {
    None => quantum
    Some(remaining) => {
      if remaining < 1 {
        return @bounded.Failed(GraphControlWorkLimit, 0, 0)
      }
      Int::min(quantum, remaining)
    }
  }
  let result = graph_step(state, bounded_quantum, reader)
  let charged = match result {
    @bounded.Continue(_, work)
    | @bounded.Complete(_, _, work)
    | @bounded.Failed(_, _, work)
    | @bounded.Stopped(_, _, work) => work
  }
  if state.control_work_remaining is Some(remaining) {
    state.control_work_remaining = Some(remaining - charged)
  }
  result
}

///|
/// Interpret only a checked new-profile construction. Exact use-site bindings
/// are mandatory; externally supplied rows cannot claim another occurrence.
pub fn start_rows_to_graph(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@execution.ProducerRead],
  limits : @graph_storage.Limits,
  storage_bytes : Int64,
  max_workspace_slots : Int,
  available : () -> Bool,
  control_work_limit? : Int? = None,
) -> Result[RowsToGraphExecution, GraphBridgeIssue] {
  if control_work_limit is Some(limit) && limit < 0 {
    return Err(GraphControlWorkLimit)
  }
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphConstructionStep(prepared)) else {
    return Err(InvalidGraphKernel)
  }
  let n = @lower.graph_construction_node_count(prepared)
  let e = @lower.graph_construction_edge_count(prepared)
  if inputs.length() != n + e {
    return Err(InvalidGraphKernel)
  }
  if max_workspace_slots < 16 {
    return Err(GraphWorkspaceLimit)
  }
  for index, input in inputs {
    if !@execution.producer_read_matches_operation_input(
        input, owner, step, index,
      ) {
      return Err(InvalidGraphKernel)
    }
    if !@execution.producer_read_available(input) {
      return Err(GraphInputUnavailable)
    }
  }
  // Account for the copied column maps and the maximum live row buffers. The
  // Graph builder separately accounts for its retained indexes and values.
  let mut remaining = max_workspace_slots - 16
  if inputs.length() > remaining {
    return Err(GraphWorkspaceLimit)
  }
  remaining -= inputs.length()
  let mut row_slots = 0
  let bindings : Array[GraphRowBinding] = []
  for index in 0..<(n + e) {
    let (element, source, target) = if index < n {
      (@lower.graph_construction_node_at(prepared, index).unwrap(), [], [])
    } else {
      let edge = @lower.graph_construction_edge_at(prepared, index - n).unwrap()
      let (source, target) = @lower.graph_edge_binding_keys(edge)
      (@lower.graph_edge_binding_element(edge), source, target)
    }
    let keys = @lower.graph_binding_keys(element)
    let properties = @lower.graph_binding_properties(element)
    let mut columns = 0
    for
      count in [
        keys.length(),
        source.length(),
        target.length(),
        properties.length(),
      ] {
      if count > remaining {
        return Err(GraphWorkspaceLimit)
      }
      remaining -= count
      columns += count
    }
    if remaining < 7 {
      return Err(GraphWorkspaceLimit)
    }
    remaining -= 7
    row_slots = Int::max(row_slots, columns)
    bindings.push({
      input: @lower.graph_binding_input(element),
      definition: if index < n {
        index
      } else {
        index - n
      },
      edge: index >= n,
      keys,
      source,
      target,
      properties,
    })
  }
  if row_slots > remaining {
    return Err(GraphWorkspaceLimit)
  }
  let output = match
    @graph.prepare_output(
      owner,
      @pipeline.Step(step),
      @graph_storage.DeclaredNodes,
      limits,
      storage_bytes,
      available,
    ) {
    Ok(value) => value
    Err(_) => return Err(InvalidGraphKernel)
  }
  let state : GraphState = {
    inputs: inputs.copy(),
    bindings,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    output: Some(output),
    element: 0,
    row: 0,
    column: 0,
    phase: BeginElement,
    keys: [],
    source: [],
    target: [],
    properties: [],
    control_work_remaining: control_work_limit,
  }
  let (session, token) = @bounded.start(
    control,
    GraphConstruction(state),
    graph_construction_step,
    cleanup_graph_construction_state,
    @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}
