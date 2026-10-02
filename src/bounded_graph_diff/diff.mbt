///|
pub(all) struct Limits {
  max_workspace_slots : Int
  max_output_nodes : Int
  max_output_text_bytes : Int
  max_output_depth : Int
  max_identity_bytes : Int
  max_identity_nodes : Int
  max_identity_depth : Int
  value_limits : @value.Limits
}

///|
pub(all) enum Issue {
  InvalidLimits
  InvalidGraph
  InvalidDeltaContract
  UnsupportedGraphOperation
  WorkspaceLimit
  OutputLimit
  Snapshot(@snapshot.Issue)
  Comparison(@value.CompleteEqualityIssue)
  Terminal
} derive(Eq, Debug)

///|
pub enum Poll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(Delta, progress~ : Int64, work~ : Int64)
  Failed(Issue, progress~ : Int64, work~ : Int64)
}

///|
struct Delta {
  value : @value.CheckedValue
  base_cid : String
  target_cid : String
}

///|
priv enum Phase {
  SnapshotLeft
  SnapshotRight
  SelectNode
  CompareNodeProperty
  SelectEdge
  CompareEdgeProperty
  BuildRecord
  Assemble
  Finished
} derive(Eq)

///|
priv enum PendingAction {
  NodeAdd(Int)
  NodeRemove(Int)
  NodeUpdate(Int, Int, Bool)
  EdgeAdd(Int)
  EdgeRemove(Int)
  EdgeUpdate(Int, Int, Bool)
}

///|
priv enum ComparePropertyPoll {
  CompareContinue(Int)
  CompareComplete(Bool, Int)
  CompareFailed(Issue, Int)
}

///|
priv enum DiffSource {
  Stored(@storage.Storage)
  Viewed(@lifecycle.ProducerView, @carrier.Graph)
}

///|
struct Preparation {
  left : DiffSource
  right : DiffSource
  delta_contract : @contract.Contract
  graph_contract_cid : String
  limits : Limits
  mut left_preparation : @snapshot.Preparation?
  mut right_preparation : @snapshot.Preparation?
  mut left_snapshot : @snapshot.Snapshot?
  mut right_snapshot : @snapshot.Snapshot?
  node_add : @value.ArrayBuilder
  node_remove : @value.ArrayBuilder
  node_update : @value.ArrayBuilder
  edge_add : @value.ArrayBuilder
  edge_remove : @value.ArrayBuilder
  edge_update : @value.ArrayBuilder
  node_record_contract : @contract.Contract
  node_update_contract : @contract.Contract
  edge_record_contract : @contract.Contract
  edge_update_contract : @contract.Contract
  mut phase : Phase
  mut left_cursor : Int
  mut right_cursor : Int
  mut property : Int
  mut comparison : @value.CompleteEquality?
  mut pending : PendingAction?
  mut properties : @value.ObjectBuilder?
  mut before : @value.Value?
  mut output_nodes : Int
  mut output_text : Int
}

///|
fn checked_add(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || right > 2147483647 - left {
    None
  } else {
    Some(left + right)
  }
}

///|
fn graph(value : @storage.Storage) -> @carrier.Graph? {
  match @storage.carrier(value) {
    @carrier.GraphValue(graph) => Some(graph)
    _ => None
  }
}

///|
fn source_graph(source : DiffSource) -> @carrier.Graph? {
  match source {
    Stored(storage) => graph(storage)
    Viewed(_, graph) => Some(graph)
  }
}

///|
fn source_node_count(source : DiffSource) -> Int? {
  match source {
    Stored(storage) => Some(@storage.node_count(storage))
    Viewed(view, _) => @lifecycle.producer_view_node_count(view)
  }
}

///|
fn source_edge_count(source : DiffSource) -> Int? {
  match source {
    Stored(storage) => Some(@storage.edge_count(storage))
    Viewed(view, _) => @lifecycle.producer_view_edge_count(view)
  }
}

///|
fn source_node_identity(
  source : DiffSource,
  index : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(storage) => @storage.node_identity(storage, index)
    Viewed(view, _) =>
      @lifecycle.producer_view_node_identity(view, index).to_option()
  }
}

///|
fn source_node_property(
  source : DiffSource,
  node : Int,
  property : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(storage) => @storage.node_property(storage, node, property)
    Viewed(view, _) =>
      @lifecycle.producer_view_node_property(view, node, property).to_option()
  }
}

///|
fn source_edge_endpoints(source : DiffSource, index : Int) -> (Int, Int)? {
  match source {
    Stored(storage) => @storage.edge_endpoints(storage, index)
    Viewed(view, _) =>
      @lifecycle.producer_view_edge_endpoints(view, index).to_option()
  }
}

///|
fn source_edge_label(source : DiffSource, index : Int) -> @value.CheckedValue?? {
  match source {
    Stored(storage) => @storage.edge_label(storage, index)
    Viewed(view, _) =>
      @lifecycle.producer_view_edge_label(view, index).to_option()
  }
}

///|
fn source_edge_property(
  source : DiffSource,
  edge : Int,
  property : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(storage) => @storage.edge_property(storage, edge, property)
    Viewed(view, _) =>
      @lifecycle.producer_view_edge_property(view, edge, property).to_option()
  }
}

///|
fn source_workspace_slots(source : DiffSource) -> Int? {
  match source {
    Stored(storage) => @snapshot.workspace_slots(storage)
    Viewed(view, graph) => @snapshot.workspace_slots_view(view, graph)
  }
}

///|
fn prepare_snapshot(
  source : DiffSource,
  graph_contract_cid : String,
  limits : @snapshot.Limits,
) -> Result[@snapshot.Preparation, @snapshot.Issue] {
  match source {
    Stored(storage) => @snapshot.prepare(storage, graph_contract_cid, limits)
    Viewed(view, graph) =>
      @snapshot.prepare_view(view, graph, graph_contract_cid, limits)
  }
}

///|
fn object_field(
  value : @contract.Contract,
  name : String,
) -> @contract.Contract? {
  guard value.shape is @contract.Object(fields) else { return None }
  for index in 0..<@contract.field_count(fields) {
    let field = @contract.field_at(fields, index).unwrap()
    if field.name == name {
      return Some(field.contract)
    }
  }
  None
}

///|
fn array_item(value : @contract.Contract) -> @contract.Contract? {
  match value.shape {
    @contract.Array(item, ..) => Some(item)
    _ => None
  }
}

///|
fn action_contracts(
  delta : @contract.Contract,
  name : String,
) -> (@contract.Contract, @contract.Contract)? {
  guard object_field(delta, name) is Some(actions) &&
    object_field(actions, "add").bind(array_item) is Some(record) &&
    object_field(actions, "remove").bind(array_item) is Some(removed) &&
    object_field(actions, "update").bind(array_item) is Some(update) &&
    (@contract.type_equal(record, removed, 100000) catch { _ => false }) else {
    return None
  }
  Some((record, update))
}

///|
fn text(value : String, limit : Int) -> @value.Value? {
  @value.text_value(value, limit)
}

///|
fn empty_actions() -> @value.Value? {
  @value.object_value([
    ("add", @value.array_value([])),
    ("remove", @value.array_value([])),
    ("update", @value.array_value([])),
  ])
}

///|
fn delta_value(
  base_cid : String,
  target_cid : String,
  graph_contract_cid : String,
  nodes : @value.Value,
  edges : @value.Value,
  text_limit : Int,
) -> @value.Value? {
  guard text("actql-graph-delta/0.1", text_limit) is Some(version) &&
    text(base_cid, text_limit) is Some(base) &&
    text(target_cid, text_limit) is Some(target) &&
    text(graph_contract_cid, text_limit) is Some(graph_contract) else {
    return None
  }
  @value.object_value([
    ("version", version),
    ("base_graph_cid", base),
    ("target_graph_cid", target),
    ("graph_contract_cid", graph_contract),
    ("nodes", nodes),
    ("edges", edges),
  ])
}

///|
fn minimum_usage(
  contract : @contract.Contract,
  graph_contract_cid : String,
  limits : Limits,
) -> (Int, Int)? {
  guard empty_actions() is Some(nodes) &&
    empty_actions() is Some(edges) &&
    delta_value(
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      "sha256:0000000000000000000000000000000000000000000000000000000000000000",
      graph_contract_cid,
      nodes,
      edges,
      limits.max_output_text_bytes,
    )
    is Some(value) &&
    @value.recheck_runtime_value_usage(value, contract, {
      max_nodes: limits.max_output_nodes,
      max_depth: limits.max_output_depth,
      max_text_bytes: limits.max_output_text_bytes,
    })
    is Some((_, nodes, text)) else {
    return None
  }
  Some((nodes, text))
}

///|
pub fn prepare(
  left : @storage.Storage,
  right : @storage.Storage,
  delta_contract : @contract.Contract,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  prepare_source(
    Stored(left),
    Stored(right),
    delta_contract,
    graph_contract_cid,
    limits,
  )
}

///|
pub fn prepare_view(
  left : @lifecycle.ProducerView,
  left_graph : @carrier.Graph,
  right : @lifecycle.ProducerView,
  right_graph : @carrier.Graph,
  delta_contract : @contract.Contract,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  prepare_source(
    Viewed(left, left_graph),
    Viewed(right, right_graph),
    delta_contract,
    graph_contract_cid,
    limits,
  )
}

///|
fn prepare_source(
  left : DiffSource,
  right : DiffSource,
  delta_contract : @contract.Contract,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  if limits.max_workspace_slots < 0 ||
    limits.max_output_nodes < 0 ||
    limits.max_output_text_bytes < 0 ||
    limits.max_output_depth < 0 ||
    limits.max_identity_bytes < 0 ||
    limits.max_identity_nodes < 0 ||
    limits.max_identity_depth < 0 {
    return Err(InvalidLimits)
  }
  // The historical delta schema identifies edges by endpoint tuples. It is not
  // an implementation of the current independent-key Graph contract.
  guard source_graph(left) is Some(left_graph) &&
    source_graph(right) is Some(right_graph) else {
    return Err(InvalidGraph)
  }
  if @carrier.graph_property_definition(left_graph) is Some(_) ||
    @carrier.graph_property_definition(right_graph) is Some(_) {
    return Err(UnsupportedGraphOperation)
  }
  guard source_graph(left) is Some(_) &&
    source_graph(right) is Some(_) &&
    action_contracts(delta_contract, "nodes")
    is Some((node_record_contract, node_update_contract)) &&
    action_contracts(delta_contract, "edges")
    is Some((edge_record_contract, edge_update_contract)) &&
    source_workspace_slots(left) is Some(left_slots) &&
    source_workspace_slots(right) is Some(right_slots) &&
    source_node_count(left) is Some(left_nodes) &&
    source_node_count(right) is Some(right_nodes) &&
    source_edge_count(left) is Some(left_edges) &&
    source_edge_count(right) is Some(right_edges) &&
    checked_add(left_nodes, right_nodes) is Some(node_actions) &&
    checked_add(left_edges, right_edges) is Some(edge_actions) &&
    checked_add(left_slots, right_slots) is Some(snapshot_slots) &&
    checked_add(snapshot_slots, node_actions) is Some(with_nodes) &&
    checked_add(with_nodes, edge_actions) is Some(action_slots) &&
    source_graph(left) is Some(common) &&
    checked_add(
      @carrier.field_count(@carrier.graph_node_properties(common)),
      @carrier.field_count(@carrier.graph_edge_properties(common)),
    )
    is Some(property_slots) &&
    checked_add(property_slots, property_slots) is Some(update_slots) &&
    checked_add(action_slots, update_slots) is Some(with_updates) &&
    checked_add(with_updates, 12) is Some(required_workspace) else {
    return Err(InvalidGraph)
  }
  if required_workspace > limits.max_workspace_slots {
    return Err(WorkspaceLimit)
  }
  guard minimum_usage(delta_contract, graph_contract_cid, limits)
    is Some((output_nodes, output_text)) else {
    return Err(OutputLimit)
  }
  let snapshot_limits : @snapshot.Limits = {
    max_workspace_slots: limits.max_workspace_slots,
    max_identity_bytes: limits.max_identity_bytes,
    max_identity_nodes: limits.max_identity_nodes,
    max_identity_depth: limits.max_identity_depth,
    value_limits: limits.value_limits,
  }
  let left_preparation = match
    prepare_snapshot(left, graph_contract_cid, snapshot_limits) {
    Ok(value) => value
    Err(issue) => return Err(Snapshot(issue))
  }
  guard @value.prepare_array_value(node_actions) is Some(node_add) &&
    @value.prepare_array_value(node_actions) is Some(node_remove) &&
    @value.prepare_array_value(node_actions) is Some(node_update) &&
    @value.prepare_array_value(edge_actions) is Some(edge_add) &&
    @value.prepare_array_value(edge_actions) is Some(edge_remove) &&
    @value.prepare_array_value(edge_actions) is Some(edge_update) else {
    return Err(InvalidLimits)
  }
  Ok({
    left,
    right,
    delta_contract,
    graph_contract_cid,
    limits,
    left_preparation: Some(left_preparation),
    right_preparation: None,
    left_snapshot: None,
    right_snapshot: None,
    node_add,
    node_remove,
    node_update,
    edge_add,
    edge_remove,
    edge_update,
    node_record_contract,
    node_update_contract,
    edge_record_contract,
    edge_update_contract,
    phase: SnapshotLeft,
    left_cursor: 0,
    right_cursor: 0,
    property: 0,
    comparison: None,
    pending: None,
    properties: None,
    before: None,
    output_nodes,
    output_text,
  })
}

///|
fn schedule(value : Preparation, pending : PendingAction) -> Unit {
  value.pending = Some(pending)
  value.properties = None
  value.property = 0
  value.before = None
  value.phase = BuildRecord
}

///|
fn node_property_count(value : Preparation) -> Int {
  source_graph(value.left)
  .map(graph => @carrier.field_count(@carrier.graph_node_properties(graph)))
  .unwrap_or(0)
}

///|
fn edge_property_count(value : Preparation) -> Int {
  source_graph(value.left)
  .map(graph => @carrier.field_count(@carrier.graph_edge_properties(graph)))
  .unwrap_or(0)
}

///|
fn pending_record(value : Preparation) -> (DiffSource, Int, Bool, Bool)? {
  match value.pending {
    Some(NodeAdd(index)) => Some((value.right, index, false, false))
    Some(NodeRemove(index)) => Some((value.left, index, false, false))
    Some(NodeUpdate(left, right, after)) =>
      if after {
        Some((value.right, right, false, true))
      } else {
        Some((value.left, left, false, false))
      }
    Some(EdgeAdd(index)) => Some((value.right, index, true, false))
    Some(EdgeRemove(index)) => Some((value.left, index, true, false))
    Some(EdgeUpdate(left, right, after)) =>
      if after {
        Some((value.right, right, true, true))
      } else {
        Some((value.left, left, true, false))
      }
    None => None
  }
}

///|
fn property_knowledge(storage : DiffSource, edge : Bool) -> @carrier.Knowledge? {
  guard source_graph(storage) is Some(graph) else { return None }
  if edge {
    Some(@carrier.graph_edge_properties(graph))
  } else {
    Some(@carrier.graph_node_properties(graph))
  }
}

///|
fn property_value(
  storage : DiffSource,
  record : Int,
  property : Int,
  edge : Bool,
) -> @value.CheckedValue? {
  if edge {
    source_edge_property(storage, record, property)
  } else {
    source_node_property(storage, record, property)
  }
}

///|
fn finish_record(
  value : Preparation,
  storage : DiffSource,
  record : Int,
  edge : Bool,
) -> @value.Value? {
  guard value.properties is Some(properties) &&
    @value.finish_object_value(properties) is Some(props) else {
    return None
  }
  value.properties = None
  if edge {
    guard source_edge_endpoints(storage, record) is Some((source, target)) &&
      source_node_identity(storage, source) is Some(source_id) &&
      source_node_identity(storage, target) is Some(target_id) &&
      source_edge_label(storage, record) is Some(label) else {
      return None
    }
    @value.object_value([
      ("dst", target_id.value),
      ("props", props),
      (
        "rel",
        match label {
          Some(label) => label.value
          None => @value.null_value()
        },
      ),
      ("src", source_id.value),
    ])
  } else {
    source_node_identity(storage, record).bind(identity => {
      @value.object_value([("id", identity.value), ("props", props)])
    })
  }
}

///|
fn account_and_append(
  value : Preparation,
  item : @value.Value,
  contract : @contract.Contract,
  output : @value.ArrayBuilder,
) -> Bool {
  let remaining_nodes = value.limits.max_output_nodes - value.output_nodes
  let remaining_text = value.limits.max_output_text_bytes - value.output_text
  if remaining_nodes < 0 || remaining_text < 0 {
    return false
  }
  guard @value.recheck_runtime_value_usage(item, contract, {
      max_nodes: remaining_nodes,
      max_depth: value.limits.max_output_depth,
      max_text_bytes: remaining_text,
    })
    is Some((_, nodes, text)) &&
    @value.append_array_item(output, item) else {
    return false
  }
  value.output_nodes += nodes
  value.output_text += text
  true
}

///|
fn finish_pending_record(value : Preparation, record : @value.Value) -> Bool {
  match value.pending {
    Some(NodeAdd(_)) =>
      account_and_append(
        value,
        record,
        value.node_record_contract,
        value.node_add,
      )
    Some(NodeRemove(_)) =>
      account_and_append(
        value,
        record,
        value.node_record_contract,
        value.node_remove,
      )
    Some(EdgeAdd(_)) =>
      account_and_append(
        value,
        record,
        value.edge_record_contract,
        value.edge_add,
      )
    Some(EdgeRemove(_)) =>
      account_and_append(
        value,
        record,
        value.edge_record_contract,
        value.edge_remove,
      )
    Some(NodeUpdate(left, right, false)) => {
      value.before = Some(record)
      value.pending = Some(NodeUpdate(left, right, true))
      value.property = 0
      true
    }
    Some(EdgeUpdate(left, right, false)) => {
      value.before = Some(record)
      value.pending = Some(EdgeUpdate(left, right, true))
      value.property = 0
      true
    }
    Some(NodeUpdate(_, _, true)) => {
      guard value.before is Some(before) &&
        @value.object_value([("after", record), ("before", before)])
        is Some(update) else {
        return false
      }
      value.before = None
      account_and_append(
        value,
        update,
        value.node_update_contract,
        value.node_update,
      )
    }
    Some(EdgeUpdate(_, _, true)) => {
      guard value.before is Some(before) &&
        @value.object_value([("after", record), ("before", before)])
        is Some(update) else {
        return false
      }
      value.before = None
      account_and_append(
        value,
        update,
        value.edge_update_contract,
        value.edge_update,
      )
    }
    None => false
  }
}

///|
fn after_pending(value : Preparation) -> Unit {
  match value.pending {
    Some(NodeAdd(_)) => {
      value.right_cursor += 1
      value.phase = SelectNode
    }
    Some(NodeRemove(_)) => {
      value.left_cursor += 1
      value.phase = SelectNode
    }
    Some(NodeUpdate(_, _, true)) => {
      value.left_cursor += 1
      value.right_cursor += 1
      value.phase = SelectNode
    }
    Some(EdgeAdd(_)) => {
      value.right_cursor += 1
      value.phase = SelectEdge
    }
    Some(EdgeRemove(_)) => {
      value.left_cursor += 1
      value.phase = SelectEdge
    }
    Some(EdgeUpdate(_, _, true)) => {
      value.left_cursor += 1
      value.right_cursor += 1
      value.phase = SelectEdge
    }
    _ => ()
  }
  value.pending = None
  value.property = 0
}

///|
fn compare_property(
  value : Preparation,
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  quantum : Int,
) -> ComparePropertyPoll {
  let comparison = match value.comparison {
    Some(comparison) => comparison
    None =>
      match
        @value.start_complete_equality(left, right, value.limits.value_limits) {
        Ok(comparison) => {
          value.comparison = Some(comparison)
          comparison
        }
        Err(issue) => return CompareFailed(Comparison(issue), 0)
      }
  }
  match @value.advance_complete_equality(comparison, quantum) {
    @value.EqualityContinue(work~) => CompareContinue(work)
    @value.EqualityComplete(equal~, work~) => {
      value.comparison = None
      CompareComplete(equal, work)
    }
    @value.EqualityFailed(issue, work~) => {
      value.comparison = None
      CompareFailed(Comparison(issue), work)
    }
  }
}

///|
fn select_node(value : Preparation) -> Issue? {
  guard value.left_snapshot is Some(left) && value.right_snapshot is Some(right) else {
    return Some(InvalidGraph)
  }
  if value.left_cursor >= @snapshot.node_count(left) {
    if value.right_cursor >= @snapshot.node_count(right) {
      value.left_cursor = 0
      value.right_cursor = 0
      value.phase = SelectEdge
    } else {
      guard @snapshot.node_at(right, value.right_cursor) is Some(index) else {
        return Some(InvalidGraph)
      }
      schedule(value, NodeAdd(index))
    }
    return None
  }
  if value.right_cursor >= @snapshot.node_count(right) {
    guard @snapshot.node_at(left, value.left_cursor) is Some(index) else {
      return Some(InvalidGraph)
    }
    schedule(value, NodeRemove(index))
    return None
  }
  guard @snapshot.node_key_at(left, value.left_cursor) is Some(left_key) &&
    @snapshot.node_key_at(right, value.right_cursor) is Some(right_key) &&
    @snapshot.node_at(left, value.left_cursor) is Some(left_index) &&
    @snapshot.node_at(right, value.right_cursor) is Some(right_index) else {
    return Some(InvalidGraph)
  }
  let compared = @canonical.compare_utf16(left_key, right_key)
  if compared < 0 {
    schedule(value, NodeRemove(left_index))
  } else if compared > 0 {
    schedule(value, NodeAdd(right_index))
  } else {
    value.property = 0
    value.phase = CompareNodeProperty
  }
  None
}

///|
fn select_edge(value : Preparation) -> Issue? {
  guard value.left_snapshot is Some(left) && value.right_snapshot is Some(right) else {
    return Some(InvalidGraph)
  }
  if value.left_cursor >= @snapshot.edge_count(left) {
    if value.right_cursor >= @snapshot.edge_count(right) {
      value.phase = Assemble
    } else {
      guard @snapshot.edge_at(right, value.right_cursor) is Some(index) else {
        return Some(InvalidGraph)
      }
      schedule(value, EdgeAdd(index))
    }
    return None
  }
  if value.right_cursor >= @snapshot.edge_count(right) {
    guard @snapshot.edge_at(left, value.left_cursor) is Some(index) else {
      return Some(InvalidGraph)
    }
    schedule(value, EdgeRemove(index))
    return None
  }
  guard @snapshot.property_edge_key_at(left, value.left_cursor)
    is Some(left_key) &&
    @snapshot.property_edge_key_at(right, value.right_cursor) is Some(right_key) &&
    @snapshot.edge_at(left, value.left_cursor) is Some(left_index) &&
    @snapshot.edge_at(right, value.right_cursor) is Some(right_index) else {
    return Some(InvalidGraph)
  }
  let compared = @canonical.compare_utf16(left_key, right_key)
  if compared < 0 {
    schedule(value, EdgeRemove(left_index))
  } else if compared > 0 {
    schedule(value, EdgeAdd(right_index))
  } else {
    value.property = 0
    value.phase = CompareEdgeProperty
  }
  None
}

///|
fn finish_actions(
  add : @value.ArrayBuilder,
  remove : @value.ArrayBuilder,
  update : @value.ArrayBuilder,
) -> @value.Value? {
  guard @value.finish_bounded_array_value(add) is Some(add) &&
    @value.finish_bounded_array_value(remove) is Some(remove) &&
    @value.finish_bounded_array_value(update) is Some(update) else {
    return None
  }
  @value.object_value([("add", add), ("remove", remove), ("update", update)])
}

///|
pub fn advance(value : Preparation, quantum : Int) -> Result[Poll, Issue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  if value.phase == Finished {
    return Err(Terminal)
  }
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    match value.phase {
      SnapshotLeft => {
        guard value.left_preparation is Some(preparation) else {
          return Err(InvalidGraph)
        }
        match @snapshot.advance(preparation, quantum - used) {
          Ok(@snapshot.Continue(progress=made, work~)) => {
            progress += made.to_int()
            used += work.to_int()
          }
          Ok(@snapshot.Complete(snapshot, progress=made, work~)) => {
            progress += made.to_int()
            used += work.to_int()
            value.left_preparation = None
            value.left_snapshot = Some(snapshot)
            let snapshot_limits : @snapshot.Limits = {
              max_workspace_slots: value.limits.max_workspace_slots,
              max_identity_bytes: value.limits.max_identity_bytes,
              max_identity_nodes: value.limits.max_identity_nodes,
              max_identity_depth: value.limits.max_identity_depth,
              value_limits: value.limits.value_limits,
            }
            value.right_preparation = match
              prepare_snapshot(
                value.right,
                value.graph_contract_cid,
                snapshot_limits,
              ) {
              Ok(preparation) => Some(preparation)
              Err(issue) =>
                return Ok(
                  Failed(
                    Snapshot(issue),
                    progress=progress.to_int64(),
                    work=used.to_int64(),
                  ),
                )
            }
            value.phase = SnapshotRight
          }
          Err(issue) =>
            return Ok(
              Failed(
                Snapshot(issue),
                progress=progress.to_int64(),
                work=used.to_int64(),
              ),
            )
        }
      }
      SnapshotRight => {
        guard value.right_preparation is Some(preparation) else {
          return Err(InvalidGraph)
        }
        match @snapshot.advance(preparation, quantum - used) {
          Ok(@snapshot.Continue(progress=made, work~)) => {
            progress += made.to_int()
            used += work.to_int()
          }
          Ok(@snapshot.Complete(snapshot, progress=made, work~)) => {
            progress += made.to_int()
            used += work.to_int()
            value.right_preparation = None
            value.right_snapshot = Some(snapshot)
            value.phase = SelectNode
          }
          Err(issue) =>
            return Ok(
              Failed(
                Snapshot(issue),
                progress=progress.to_int64(),
                work=used.to_int64(),
              ),
            )
        }
      }
      SelectNode => {
        used += 1
        match select_node(value) {
          Some(issue) =>
            return Ok(
              Failed(issue, progress=progress.to_int64(), work=used.to_int64()),
            )
          None => ()
        }
      }
      CompareNodeProperty => {
        guard value.left_snapshot is Some(left_snapshot) &&
          value.right_snapshot is Some(right_snapshot) &&
          @snapshot.node_at(left_snapshot, value.left_cursor)
          is Some(left_index) &&
          @snapshot.node_at(right_snapshot, value.right_cursor)
          is Some(right_index) else {
          return Err(InvalidGraph)
        }
        if value.property >= node_property_count(value) {
          value.left_cursor += 1
          value.right_cursor += 1
          value.phase = SelectNode
          continue
        }
        guard source_node_property(value.left, left_index, value.property)
          is Some(left) &&
          source_node_property(value.right, right_index, value.property)
          is Some(right) else {
          return Err(InvalidGraph)
        }
        match compare_property(value, left, right, quantum - used) {
          CompareContinue(work) => used += work
          CompareComplete(true, work) => {
            used += work
            value.property += 1
          }
          CompareComplete(false, work) => {
            used += work
            schedule(value, NodeUpdate(left_index, right_index, false))
          }
          CompareFailed(issue, work) => {
            used += work
            return Ok(
              Failed(issue, progress=progress.to_int64(), work=used.to_int64()),
            )
          }
        }
      }
      SelectEdge => {
        used += 1
        match select_edge(value) {
          Some(issue) =>
            return Ok(
              Failed(issue, progress=progress.to_int64(), work=used.to_int64()),
            )
          None => ()
        }
      }
      CompareEdgeProperty => {
        guard value.left_snapshot is Some(left_snapshot) &&
          value.right_snapshot is Some(right_snapshot) &&
          @snapshot.edge_at(left_snapshot, value.left_cursor)
          is Some(left_index) &&
          @snapshot.edge_at(right_snapshot, value.right_cursor)
          is Some(right_index) else {
          return Err(InvalidGraph)
        }
        if value.property >= edge_property_count(value) {
          value.left_cursor += 1
          value.right_cursor += 1
          value.phase = SelectEdge
          continue
        }
        guard source_edge_property(value.left, left_index, value.property)
          is Some(left) &&
          source_edge_property(value.right, right_index, value.property)
          is Some(right) else {
          return Err(InvalidGraph)
        }
        match compare_property(value, left, right, quantum - used) {
          CompareContinue(work) => used += work
          CompareComplete(true, work) => {
            used += work
            value.property += 1
          }
          CompareComplete(false, work) => {
            used += work
            schedule(value, EdgeUpdate(left_index, right_index, false))
          }
          CompareFailed(issue, work) => {
            used += work
            return Ok(
              Failed(issue, progress=progress.to_int64(), work=used.to_int64()),
            )
          }
        }
      }
      BuildRecord => {
        guard pending_record(value)
          is Some((storage, record, edge, building_after)) &&
          property_knowledge(storage, edge) is Some(knowledge) else {
          return Err(InvalidGraph)
        }
        if value.properties is None {
          guard @value.prepare_object_value(@carrier.field_count(knowledge))
            is Some(properties) else {
            return Err(InvalidGraph)
          }
          value.properties = Some(properties)
          used += 1
          continue
        }
        if value.property < @carrier.field_count(knowledge) {
          guard @carrier.field_at(knowledge, value.property) is Some(field) &&
            property_value(storage, record, value.property, edge)
            is Some(property) &&
            value.properties is Some(properties) &&
            @value.append_object_field(
              properties,
              @schema.reference_name(field.name),
              property.value,
            ) else {
            return Err(InvalidGraph)
          }
          value.property += 1
          used += 1
          progress += 1
          continue
        }
        guard finish_record(value, storage, record, edge) is Some(record_value) &&
          finish_pending_record(value, record_value) else {
          return Ok(
            Failed(
              OutputLimit,
              progress=progress.to_int64(),
              work=(used + 1).to_int64(),
            ),
          )
        }
        used += 1
        progress += 1
        if !building_after &&
          (
            value.pending is Some(NodeUpdate(_, _, true)) ||
            value.pending is Some(EdgeUpdate(_, _, true))
          ) {
          continue
        }
        after_pending(value)
      }
      Assemble => {
        guard value.left_snapshot is Some(left) &&
          value.right_snapshot is Some(right) &&
          finish_actions(value.node_add, value.node_remove, value.node_update)
          is Some(nodes) &&
          finish_actions(value.edge_add, value.edge_remove, value.edge_update)
          is Some(edges) &&
          delta_value(
            @snapshot.cid(left),
            @snapshot.cid(right),
            value.graph_contract_cid,
            nodes,
            edges,
            value.limits.max_output_text_bytes,
          )
          is Some(delta) &&
          @value.recheck_runtime_value_usage(delta, value.delta_contract, {
            max_nodes: value.limits.max_output_nodes,
            max_depth: value.limits.max_output_depth,
            max_text_bytes: value.limits.max_output_text_bytes,
          })
          is Some((checked, nodes, text)) &&
          nodes == value.output_nodes &&
          text == value.output_text else {
          return Ok(
            Failed(
              OutputLimit,
              progress=progress.to_int64(),
              work=(used + 1).to_int64(),
            ),
          )
        }
        value.phase = Finished
        used += 1
        progress += 1
        return Ok(
          Complete(
            {
              value: checked,
              base_cid: @snapshot.cid(left),
              target_cid: @snapshot.cid(right),
            },
            progress=progress.to_int64(),
            work=used.to_int64(),
          ),
        )
      }
      Finished => return Err(Terminal)
    }
  }
  Ok(Continue(progress=progress.to_int64(), work=used.to_int64()))
}

///|
pub fn value(delta : Delta) -> @value.CheckedValue {
  delta.value
}

///|
pub fn base_cid(delta : Delta) -> String {
  delta.base_cid
}

///|
pub fn target_cid(delta : Delta) -> String {
  delta.target_cid
}

///|
pub fn cleanup(value : Preparation) -> Bool {
  if value.left_preparation is Some(preparation) {
    @snapshot.cancel(preparation) |> ignore
    value.left_preparation = None
  }
  if value.right_preparation is Some(preparation) {
    @snapshot.cancel(preparation) |> ignore
    value.right_preparation = None
  }
  if value.left_snapshot is Some(snapshot) {
    @snapshot.cleanup(snapshot) |> ignore
    value.left_snapshot = None
  }
  if value.right_snapshot is Some(snapshot) {
    @snapshot.cleanup(snapshot) |> ignore
    value.right_snapshot = None
  }
  if value.phase != Finished {
    for
      builder in [
        value.node_add,
        value.node_remove,
        value.node_update,
        value.edge_add,
        value.edge_remove,
        value.edge_update,
      ] {
      @value.cancel_array_value(builder) |> ignore
    }
    if value.properties is Some(properties) {
      @value.cancel_object_value(properties) |> ignore
      value.properties = None
    }
  }
  true
}
