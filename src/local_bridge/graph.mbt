///|
struct RowsToGraphExecution {
  session : @bounded.Session[
    GraphConstructionState,
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
priv enum GraphRowsSource {
  Stored(@graph.ProducerRead, @graph_storage.Storage)
  Viewed(@lifecycle.ProducerView)
}

///|
priv struct GraphRowsState {
  source : GraphRowsSource
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
  mut control_work_remaining : Int?
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
  GraphControlWorkLimit
  GraphRelationOutput(@execution.CaptureIssue)
  GraphCompletion(@execution.TrustedOutputIssue)
  GraphExecution(@bounded.Issue)
  GraphSnapshot(@snapshot.Issue)
  GraphSnapshotOutput(@graph.Issue)
} derive(Eq, Debug)

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
/// The common constructor accepts only the admitted definition-scoped contract.
/// Historical endpoint-tuple sequences are not executable through this entry.
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
  start_rows_to_property_graph(
    control,
    sequence,
    step,
    inputs,
    limits,
    storage_bytes,
    max_workspace_slots,
    available,
    control_work_limit~,
  )
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
fn graph_rows_source_available(source : GraphRowsSource) -> Bool {
  match source {
    Stored(input, _) => @graph.producer_read_available(input)
    Viewed(view) =>
      @lifecycle.producer_view_node_count(view) is Some(_) &&
      @lifecycle.producer_view_edge_count(view) is Some(_)
  }
}

///|
fn graph_rows_node_count(source : GraphRowsSource) -> Int? {
  match source {
    Stored(_, storage) => Some(@graph_storage.node_count(storage))
    Viewed(view) => @lifecycle.producer_view_node_count(view)
  }
}

///|
fn graph_rows_edge_count(source : GraphRowsSource) -> Int? {
  match source {
    Stored(_, storage) => Some(@graph_storage.edge_count(storage))
    Viewed(view) => @lifecycle.producer_view_edge_count(view)
  }
}

///|
fn graph_rows_node_identity(
  source : GraphRowsSource,
  node : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(_, storage) => @graph_storage.node_identity(storage, node)
    Viewed(view) =>
      match @lifecycle.producer_view_node_identity(view, node) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_rows_node_property(
  source : GraphRowsSource,
  node : Int,
  property : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(_, storage) => @graph_storage.node_property(storage, node, property)
    Viewed(view) =>
      match @lifecycle.producer_view_node_property(view, node, property) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_rows_edge_endpoints(
  source : GraphRowsSource,
  edge : Int,
) -> (Int, Int)? {
  match source {
    Stored(_, storage) => @graph_storage.edge_endpoints(storage, edge)
    Viewed(view) =>
      match @lifecycle.producer_view_edge_endpoints(view, edge) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_rows_edge_label(
  source : GraphRowsSource,
  edge : Int,
) -> @value.CheckedValue?? {
  match source {
    Stored(_, storage) => @graph_storage.edge_label(storage, edge)
    Viewed(view) =>
      match @lifecycle.producer_view_edge_label(view, edge) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_rows_edge_property(
  source : GraphRowsSource,
  edge : Int,
  property : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(_, storage) => @graph_storage.edge_property(storage, edge, property)
    Viewed(view) =>
      match @lifecycle.producer_view_edge_property(view, edge, property) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_node_field(
  state : GraphRowsState,
  expected : @schema.Field,
) -> @value.CheckedValue? {
  let (node_alias, _, _, _) = graph_role_names(state.graph)
  let source = if expected.name == @schema.Unqualified("id") ||
    node_alias == Some(expected.name) {
    graph_rows_node_identity(state.source, state.record)
  } else {
    match
      graph_property_index(
        @carrier.graph_node_properties(state.graph),
        expected.name,
      ) {
      Some(property) =>
        graph_rows_node_property(state.source, state.record, property)
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
  guard graph_rows_edge_endpoints(state.source, state.record)
    is Some((source, target)) else {
    return None
  }
  let (_, source_alias, target_alias, label_alias) = graph_role_names(
    state.graph,
  )
  let value = if expected.name == @schema.Unqualified("src") ||
    source_alias == Some(expected.name) {
    graph_rows_node_identity(state.source, source)
  } else if expected.name == @schema.Unqualified("dst") ||
    target_alias == Some(expected.name) {
    graph_rows_node_identity(state.source, target)
  } else if expected.name == @schema.Unqualified("rel") ||
    label_alias == Some(expected.name) {
    return match graph_rows_edge_label(state.source, state.record) {
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
        graph_rows_edge_property(state.source, state.record, property)
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
    graph_rows_node_count(state.source).unwrap_or(0)
  } else {
    graph_rows_edge_count(state.source).unwrap_or(0)
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
    if !graph_rows_source_available(state.source) {
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
          if !charge_graph_rows_work(state) {
            return @bounded.Failed(GraphControlWorkLimit, progress, used)
          }
          used += 1
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
        } else {
          state.phase = CommitRow
        }
      CommitRow => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphKernel, progress, used)
        }
        if !charge_graph_rows_work(state) {
          return @bounded.Failed(GraphControlWorkLimit, progress, used)
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
fn charge_graph_rows_work(state : GraphRowsState) -> Bool {
  match state.control_work_remaining {
    None => true
    Some(remaining) =>
      if remaining <= 0 {
        false
      } else {
        state.control_work_remaining = Some(remaining - 1)
        true
      }
  }
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
fn start_graph_to_rows_common(
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
  inputs : Array[@execution.ProducerRead]?,
  control_work_limit : Int?,
) -> Result[GraphRowsExecution, GraphBridgeIssue] {
  if control_work_limit is Some(limit) && limit < 0 {
    return Err(GraphControlWorkLimit)
  }
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
      inputs?,
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(GraphCompletion(issue))
    }
  }
  let state : GraphRowsState = {
    source: Stored(input, source),
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
    control_work_remaining: control_work_limit,
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
  control_work_limit? : Int? = None,
) -> Result[GraphRowsExecution, GraphBridgeIssue] {
  start_graph_to_rows_common(
    control,
    preparation,
    sequence,
    step,
    input,
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    Some(inputs),
    control_work_limit,
  )
}

///|
/// Project a Graph produced from common Carrier inputs. The bridge does not
/// invent Relation provenance for those inputs; the enclosing managed
/// completion binds the exact common input set after provider execution.
pub fn start_graph_to_rows_from_carrier_inputs(
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
  control_work_limit? : Int? = None,
) -> Result[GraphRowsExecution, GraphBridgeIssue] {
  start_graph_to_rows_common(
    control,
    preparation,
    sequence,
    step,
    input,
    max_rows,
    limits,
    max_workspace_slots,
    max_entries,
    max_name_bytes,
    None,
    control_work_limit,
  )
}

///|
pub fn start_graph_view_to_rows(
  control : @bounded.Control,
  preparation : @execution.CompletionPreparation,
  sequence : @lower.PreparedSequence,
  step : Int,
  input : @lifecycle.ProducerView,
  max_rows : Int,
  limits : @execution.ValueLimits,
  max_workspace_slots : Int,
  max_entries : Int,
  max_name_bytes : Int,
  control_work_limit? : Int? = None,
) -> Result[GraphRowsExecution, GraphBridgeIssue] {
  if control_work_limit is Some(limit) && limit < 0 {
    return Err(GraphControlWorkLimit)
  }
  let owner = @lower.sequence_owner(sequence)
  guard physical_equal(
      @execution.completion_preparation_owner(preparation),
      owner,
    ) &&
    @lower.sequence_step(sequence, step)
    is Some(@lower.CarrierProjectionStep(projection)) &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(input),
      owner,
      step,
      0,
    ) &&
    @lifecycle.producer_view_kind(input) == @carrier.GraphKind &&
    @lower.carrier_projection_input_carrier(projection)
    is @carrier.GraphValue(graph) &&
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
    ) {
    Ok(value) => value
    Err(issue) => {
      @execution.cancel_admitted_output(output) |> ignore
      return Err(GraphCompletion(issue))
    }
  }
  let state : GraphRowsState = {
    source: Viewed(input),
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
    control_work_remaining: control_work_limit,
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
