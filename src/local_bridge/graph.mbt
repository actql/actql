///|
priv enum RowsToGraphPhase {
  BeginNode
  ReadNodeProperties
  CommitNode
  BeginEdge
  ReadEdgeSource
  ReadEdgeTarget
  ReadEdgeLabel
  ReadEdgeProperties
  CheckEdgeSource
  CheckEdgeTarget
  CommitEdge
  FinishGraph
}

///|
priv struct RowsToGraphState {
  nodes : @execution.ProducerRead
  edges : @execution.ProducerRead
  mut output : @graph.OutputBuilder?
  value_limits : @value.Limits
  node_identity : Int
  node_properties : Array[Int]
  edge_source : Int
  edge_target : Int
  edge_label : Int?
  edge_properties : Array[Int]
  mut phase : RowsToGraphPhase
  mut row : Int
  mut field : Int
  mut identity : @value.CheckedValue?
  mut source : @value.CheckedValue?
  mut target : @value.CheckedValue?
  mut label : @value.CheckedValue?
  mut properties : Array[@value.CheckedValue]
}

///|
struct RowsToGraphExecution {
  session : @bounded.Session[
    RowsToGraphState,
    @graph.Completed,
    GraphBridgeIssue,
  ]
  mut token : @bounded.Token?
}

///|
pub enum RowsToGraphPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@graph.Completed, progress~ : Int64, work~ : Int64)
  Failed(GraphBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
priv enum GraphRowsPhase {
  BeginRecord
  ReadField
  CommitRow
  FinishRows
}

///|
priv struct GraphRowsState {
  input : @graph.ProducerRead
  source : @graph_storage.Storage
  graph : @carrier.Graph
  operation : @projection.Operation
  schema : @schema.Schema
  value_limits : @value.Limits
  mut output : @execution.AdmittedOutput?
  rows : Ref[@execution.AdmittedOutputRows?]
  live : Ref[Bool]
  accepted : Ref[Bool]
  port : @execution.TrustedOutputPort[Unit]
  mut phase : GraphRowsPhase
  mut record : Int
  mut column : Int
  mut values : Array[@value.CheckedValue]
}

///|
struct GraphRowsExecution {
  session : @bounded.Session[
    GraphRowsState,
    @execution.CompletedOutput,
    GraphBridgeIssue,
  ]
  mut token : @bounded.Token?
  accepted : Ref[Bool]
}

///|
pub enum GraphRowsPoll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(@execution.CompletedOutput, progress~ : Int64, work~ : Int64)
  Failed(GraphBridgeIssue, progress~ : Int64, work~ : Int64)
  Stopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum GraphBridgeIssue {
  InvalidGraphKernel
  GraphInputUnavailable
  InvalidGraphRecord(Int)
  GraphWorkspaceLimit
  GraphRelationOutput(@execution.CaptureIssue)
  GraphCompletion(@execution.TrustedOutputIssue)
  GraphExecution(@bounded.Issue)
} derive(Eq, Debug)

///|
fn relation_field_index(
  input : @execution.ProducerRead,
  name : @schema.FieldName,
) -> Int? {
  let schema = @execution.producer_read_schema(input)
  for index in 0..<@schema.field_count(schema) {
    if @schema.field_at(schema, index).unwrap().name == name {
      return Some(index)
    }
  }
  None
}

///|
fn graph_checked_cell(
  input : @execution.ProducerRead,
  row : Int,
  column : Int,
  limits : @value.Limits,
) -> @value.CheckedValue? {
  @execution.producer_read_checked_cell(input, row, column, limits)
}

///|
fn rows_to_graph_step(
  state : RowsToGraphState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, GraphBridgeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@execution.producer_read_available(state.nodes) ||
      !@execution.producer_read_available(state.edges) {
      return @bounded.Failed(GraphInputUnavailable, progress, used)
    }
    match state.phase {
      BeginNode =>
        if state.row < @execution.producer_read_row_count(state.nodes) {
          guard graph_checked_cell(
              state.nodes,
              state.row,
              state.node_identity,
              state.value_limits,
            )
            is Some(identity) else {
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          }
          state.identity = Some(identity)
          state.properties = []
          state.field = 0
          state.phase = ReadNodeProperties
          used += 1
        } else {
          state.row = 0
          state.phase = BeginEdge
        }
      ReadNodeProperties =>
        if state.field < state.node_properties.length() {
          guard graph_checked_cell(
              state.nodes,
              state.row,
              state.node_properties[state.field],
              state.value_limits,
            )
            is Some(property) else {
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          }
          state.properties.push(property)
          state.field += 1
          used += 1
        } else {
          state.phase = CommitNode
        }
      CommitNode => {
        guard state.output is Some(output) && state.identity is Some(identity) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        used += 1
        match @graph.append_node(output, identity, state.properties) {
          Err(_) =>
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          Ok(_) => {
            state.identity = None
            state.properties = []
            state.row += 1
            state.phase = BeginNode
            progress += 1
          }
        }
      }
      BeginEdge =>
        if state.row < @execution.producer_read_row_count(state.edges) {
          state.source = None
          state.target = None
          state.label = None
          state.properties = []
          state.field = 0
          state.phase = ReadEdgeSource
        } else {
          state.phase = FinishGraph
        }
      ReadEdgeSource => {
        guard graph_checked_cell(
            state.edges,
            state.row,
            state.edge_source,
            state.value_limits,
          )
          is Some(source) else {
          return @bounded.Failed(InvalidGraphRecord(state.row), progress, used)
        }
        state.source = Some(source)
        state.phase = ReadEdgeTarget
        used += 1
      }
      ReadEdgeTarget => {
        guard graph_checked_cell(
            state.edges,
            state.row,
            state.edge_target,
            state.value_limits,
          )
          is Some(target) else {
          return @bounded.Failed(InvalidGraphRecord(state.row), progress, used)
        }
        state.target = Some(target)
        state.phase = match state.edge_label {
          None => ReadEdgeProperties
          Some(_) => ReadEdgeLabel
        }
        used += 1
      }
      ReadEdgeLabel => {
        guard state.edge_label is Some(column) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        match
          graph_checked_cell(state.edges, state.row, column, state.value_limits) {
          Some({ value: @value.Null, .. }) => state.label = None
          Some(value) => state.label = Some(value)
          None =>
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
        }
        state.phase = ReadEdgeProperties
        used += 1
      }
      ReadEdgeProperties =>
        if state.field < state.edge_properties.length() {
          guard graph_checked_cell(
              state.edges,
              state.row,
              state.edge_properties[state.field],
              state.value_limits,
            )
            is Some(property) else {
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          }
          state.properties.push(property)
          state.field += 1
          used += 1
        } else {
          state.phase = CheckEdgeSource
        }
      CheckEdgeSource => {
        guard state.output is Some(output) && state.source is Some(source) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        used += 1
        match @graph.contains_declared_node(output, source) {
          Err(_) =>
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          Ok(false) => {
            state.source = None
            state.target = None
            state.label = None
            state.properties = []
            state.row += 1
            state.phase = BeginEdge
            progress += 1
          }
          Ok(true) => state.phase = CheckEdgeTarget
        }
      }
      CheckEdgeTarget => {
        guard state.output is Some(output) && state.target is Some(target) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        used += 1
        match @graph.contains_declared_node(output, target) {
          Err(_) =>
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          Ok(false) => {
            state.source = None
            state.target = None
            state.label = None
            state.properties = []
            state.row += 1
            state.phase = BeginEdge
            progress += 1
          }
          Ok(true) => state.phase = CommitEdge
        }
      }
      CommitEdge => {
        guard state.output is Some(output) &&
          state.source is Some(source) &&
          state.target is Some(target) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        used += 1
        match
          @graph.append_edge(
            output,
            source,
            target,
            state.label,
            state.properties,
          ) {
          Err(_) =>
            return @bounded.Failed(
              InvalidGraphRecord(state.row),
              progress,
              used,
            )
          Ok(_) => {
            state.source = None
            state.target = None
            state.label = None
            state.properties = []
            state.row += 1
            state.phase = BeginEdge
            progress += 1
          }
        }
      }
      FinishGraph => {
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
fn cleanup_rows_to_graph_state(state : RowsToGraphState) -> Bool {
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  state.identity = None
  state.source = None
  state.target = None
  state.label = None
  state.properties = []
  true
}

///|
pub fn start_rows_to_graph(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  inputs : Array[@execution.ProducerRead],
  limits : @graph_storage.Limits,
  storage_bytes : Int64,
  max_workspace_slots : Int,
  available : () -> Bool,
) -> Result[RowsToGraphExecution, GraphBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard inputs.length() == 2 &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.GraphConstructionStep(graph)) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.operation(node) == "BRIDGE.rows.to_graph" &&
    @execution.producer_read_matches_operation_input(inputs[0], owner, step, 0) &&
    @execution.producer_read_matches_operation_input(inputs[1], owner, step, 1) else {
    return Err(InvalidGraphKernel)
  }
  let node_property_count = @lower.graph_construction_node_property_count(graph)
  let edge_property_count = @lower.graph_construction_edge_property_count(graph)
  if max_workspace_slots < 0 ||
    node_property_count > max_workspace_slots ||
    edge_property_count > max_workspace_slots - node_property_count ||
    8 > max_workspace_slots - node_property_count - edge_property_count {
    return Err(GraphWorkspaceLimit)
  }
  guard relation_field_index(
      inputs[0],
      @lower.graph_construction_node_identity(graph),
    )
    is Some(node_identity) &&
    relation_field_index(
      inputs[1],
      @lower.graph_construction_edge_source(graph),
    )
    is Some(edge_source) &&
    relation_field_index(
      inputs[1],
      @lower.graph_construction_edge_target(graph),
    )
    is Some(edge_target) else {
    return Err(InvalidGraphKernel)
  }
  let edge_label = match @lower.graph_construction_edge_label(graph) {
    None => None
    Some(name) =>
      match relation_field_index(inputs[1], name) {
        Some(index) => Some(index)
        None => return Err(InvalidGraphKernel)
      }
  }
  let node_properties : Array[Int] = []
  for index in 0..<node_property_count {
    guard @lower.graph_construction_node_property_at(graph, index) is Some(name) &&
      relation_field_index(inputs[0], name) is Some(column) else {
      return Err(InvalidGraphKernel)
    }
    node_properties.push(column)
  }
  let edge_properties : Array[Int] = []
  for index in 0..<edge_property_count {
    guard @lower.graph_construction_edge_property_at(graph, index) is Some(name) &&
      relation_field_index(inputs[1], name) is Some(column) else {
      return Err(InvalidGraphKernel)
    }
    edge_properties.push(column)
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
  let state : RowsToGraphState = {
    nodes: inputs[0],
    edges: inputs[1],
    output: Some(output),
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
    node_identity,
    node_properties,
    edge_source,
    edge_target,
    edge_label,
    edge_properties,
    phase: BeginNode,
    row: 0,
    field: 0,
    identity: None,
    source: None,
    target: None,
    label: None,
    properties: [],
  }
  let (session, token) = @bounded.start(
    control, state, rows_to_graph_step, cleanup_rows_to_graph_state, @graph.discard_completed,
  )
  Ok({ session, token: Some(token), })
}

///|
pub fn advance_rows_to_graph(
  value : RowsToGraphExecution,
  quantum : Int,
) -> Result[RowsToGraphPoll, GraphBridgeIssue] {
  guard value.token is Some(token) else {
    return Err(GraphExecution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraphExecution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_rows_to_graph(
  value : RowsToGraphExecution,
) -> Result[Bool, GraphBridgeIssue] {
  @bounded.cleanup(value.session).map_err(issue => GraphExecution(issue))
}

///|
pub fn rows_to_graph_cleanup_pending(value : RowsToGraphExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
fn graph_role_names(
  graph : @carrier.Graph,
) -> (
  @schema.FieldName?,
  @schema.FieldName?,
  @schema.FieldName?,
  @schema.FieldName?,
) {
  match @carrier.graph_names(graph) {
    None => (None, None, None, None)
    Some(names) => {
      let (node, source, target, label) = @carrier.graph_row_fields(names)
      (Some(node), Some(source), Some(target), label)
    }
  }
}

///|
fn graph_property_index(
  properties : @carrier.Knowledge,
  name : @schema.FieldName,
) -> Int? {
  for index in 0..<@carrier.field_count(properties) {
    if @carrier.field_at(properties, index).unwrap().name == name {
      return Some(index)
    }
  }
  None
}

///|
fn graph_node_field(
  state : GraphRowsState,
  expected : @schema.Field,
) -> @value.CheckedValue? {
  let (node_alias, _, _, _) = graph_role_names(state.graph)
  let source = if expected.name == @schema.Unqualified("id") ||
    node_alias == Some(expected.name) {
    @graph_storage.node_identity(state.source, state.record)
  } else {
    match
      graph_property_index(
        @carrier.graph_node_properties(state.graph),
        expected.name,
      ) {
      Some(property) =>
        @graph_storage.node_property(state.source, state.record, property)
      None => None
    }
  }
  match source {
    Some(checked) =>
      @value.recheck_runtime_value(
        checked.value,
        expected.contract,
        state.value_limits,
      )
    None => None
  }
}

///|
fn graph_edge_field(
  state : GraphRowsState,
  expected : @schema.Field,
) -> @value.CheckedValue? {
  guard @graph_storage.edge_endpoints(state.source, state.record)
    is Some((source, target)) else {
    return None
  }
  let (_, source_alias, target_alias, label_alias) = graph_role_names(
    state.graph,
  )
  let value = if expected.name == @schema.Unqualified("src") ||
    source_alias == Some(expected.name) {
    @graph_storage.node_identity(state.source, source)
  } else if expected.name == @schema.Unqualified("dst") ||
    target_alias == Some(expected.name) {
    @graph_storage.node_identity(state.source, target)
  } else if expected.name == @schema.Unqualified("rel") ||
    label_alias == Some(expected.name) {
    return match @graph_storage.edge_label(state.source, state.record) {
      Some(Some(label)) =>
        @value.recheck_runtime_value(
          label.value,
          expected.contract,
          state.value_limits,
        )
      Some(None) => @value.checked_null_value(expected.contract)
      None => None
    }
  } else {
    match
      graph_property_index(
        @carrier.graph_edge_properties(state.graph),
        expected.name,
      ) {
      Some(property) =>
        @graph_storage.edge_property(state.source, state.record, property)
      None => None
    }
  }
  match value {
    Some(checked) =>
      @value.recheck_runtime_value(
        checked.value,
        expected.contract,
        state.value_limits,
      )
    None => None
  }
}

///|
fn graph_row_count(state : GraphRowsState) -> Int {
  if state.operation == @projection.NodeRows {
    @graph_storage.node_count(state.source)
  } else {
    @graph_storage.edge_count(state.source)
  }
}

///|
fn graph_rows_step(
  state : GraphRowsState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@execution.CompletedOutput, GraphBridgeIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !@graph.producer_read_available(state.input) {
      return @bounded.Failed(GraphInputUnavailable, progress, used)
    }
    match state.phase {
      BeginRecord =>
        if state.record < graph_row_count(state) {
          state.column = 0
          state.values = []
          state.phase = ReadField
        } else {
          state.phase = FinishRows
        }
      ReadField =>
        if state.column < @schema.field_count(state.schema) {
          guard @schema.field_at(state.schema, state.column) is Some(expected) &&
            (if state.operation == @projection.NodeRows {
              graph_node_field(state, expected)
            } else {
              graph_edge_field(state, expected)
            })
            is Some(value) else {
            return @bounded.Failed(
              InvalidGraphRecord(state.record),
              progress,
              used,
            )
          }
          state.values.push(value)
          state.column += 1
          used += 1
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        used += 1
        match @execution.append_admitted_output(output, state.values) {
          Err(issue) =>
            return @bounded.Failed(GraphRelationOutput(issue), progress, used)
          Ok(_) => {
            state.values = []
            state.record += 1
            state.phase = BeginRecord
            progress += 1
          }
        }
      }
      FinishRows => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        state.output = None
        let rows = match @execution.finish_admitted_output(output) {
          Ok(value) => value
          Err(issue) =>
            return @bounded.Failed(GraphRelationOutput(issue), progress, used)
        }
        state.rows.val = Some(rows)
        return match @execution.complete_trusted_output(state.port, ()) {
          Ok(completed) => @bounded.Complete(completed, progress, used)
          Err(issue) => @bounded.Failed(GraphCompletion(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_graph_rows_state(state : GraphRowsState) -> Bool {
  if state.output is Some(output) {
    @execution.cancel_admitted_output(output) |> ignore
    state.output = None
  }
  state.values = []
  if !state.accepted.val {
    state.rows.val = None
    state.live.val = false
  }
  true
}

///|
pub fn start_graph_to_rows(
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
) -> Result[GraphRowsExecution, GraphBridgeIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.CarrierProjectionStep(projection)) &&
    @graph.producer_read_matches_operation_input(input, owner, step, 0) &&
    @graph.producer_read_storage(input) is Some(source) &&
    @graph_storage.carrier(source) is @carrier.GraphValue(graph) &&
    @lower.preparation_schema_at(
      @lower.bound_preparation(owner),
      @pipeline.Step(step),
    )
    is Some(schema) else {
    return Err(InvalidGraphKernel)
  }
  let operation = @lower.carrier_projection_operation(projection)
  if operation != @projection.NodeRows && operation != @projection.EdgeRows {
    return Err(InvalidGraphKernel)
  }
  let width = @schema.field_count(schema)
  if max_workspace_slots < 0 ||
    width > max_workspace_slots ||
    width == 2147483647 {
    return Err(GraphWorkspaceLimit)
  }
  let output = match
    @execution.prepare_admitted_output(
      owner,
      @pipeline.Step(step),
      max_rows,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(GraphRelationOutput(issue))
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
      return Err(GraphCompletion(issue))
    }
  }
  let state : GraphRowsState = {
    input,
    source,
    graph,
    operation,
    schema,
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
    phase: BeginRecord,
    record: 0,
    column: 0,
    values: [],
  }
  let (session, token) = @bounded.start(
    control,
    state,
    graph_rows_step,
    cleanup_graph_rows_state,
    _output => {
      state.live.val = false
      true
    },
  )
  Ok({ session, token: Some(token), accepted, })
}

///|
pub fn advance_graph_to_rows(
  value : GraphRowsExecution,
  quantum : Int,
) -> Result[GraphRowsPoll, GraphBridgeIssue] {
  guard value.token is Some(token) else {
    return Err(GraphExecution(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraphExecution(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(Continue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      value.accepted.val = true
      Ok(Complete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(Failed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(Stopped(reason, progress~, work~))
    }
  }
}

///|
pub fn cleanup_graph_to_rows(
  value : GraphRowsExecution,
) -> Result[Bool, GraphBridgeIssue] {
  @bounded.cleanup(value.session).map_err(issue => GraphExecution(issue))
}

///|
pub fn graph_to_rows_cleanup_pending(value : GraphRowsExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}
