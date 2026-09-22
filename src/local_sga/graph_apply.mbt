///|
priv struct ApplyNodeRecord {
  identity : @value.CheckedValue
  properties : Array[@value.CheckedValue]
}

///|
priv struct ApplyEdgeRecord {
  source : @value.CheckedValue
  target : @value.CheckedValue
  label : @value.CheckedValue?
  properties : Array[@value.CheckedValue]
}

///|
priv struct ApplyNodeUpdate {
  after : ApplyNodeRecord
}

///|
priv struct ApplyEdgeUpdate {
  after : ApplyEdgeRecord
}

///|
priv enum GraphApplyPhase {
  SnapshotBase
  ParseActions
  CopyNodes
  AddNodes
  CopyEdges
  AddEdges
  FinishGraph
  SnapshotResult
}

///|
priv enum GraphApplyBase {
  Stored(@graph.ProducerRead, @storage.Storage)
  Viewed(@lifecycle.ProducerView, @carrier.Graph)
}

///|
priv struct GraphApplyState {
  base_read : GraphApplyBase
  delta_read : @execution.ProducerRead
  delta : @value.CheckedValue
  graph_contract_cid : String
  base_cid : String
  target_cid : String
  limits : @storage.Limits
  storage_bytes : Int64
  available : () -> Bool
  owner : @lower.BoundPrepared
  step : Int
  mut phase : GraphApplyPhase
  mut base_snapshot_preparation : @snapshot.Preparation?
  mut base_snapshot : @snapshot.Snapshot?
  mut result_snapshot_preparation : @snapshot.Preparation?
  mut result_snapshot : @snapshot.Snapshot?
  mut output : @graph.OutputBuilder?
  mut completed : @graph.Completed?
  node_add : Map[String, ApplyNodeRecord]
  node_remove : Map[String, ApplyNodeRecord]
  node_update : Map[String, ApplyNodeUpdate]
  edge_add : Map[String, ApplyEdgeRecord]
  edge_remove : Map[String, ApplyEdgeRecord]
  edge_update : Map[String, ApplyEdgeUpdate]
  node_add_order : Array[String]
  edge_add_order : Array[String]
  mut action_list : Int
  mut action_index : Int
  mut previous_action_key : String?
  mut record : Int
}

///|
struct GraphApplyExecution {
  session : @bounded.Session[GraphApplyState, @graph.Completed, GraphApplyIssue]
  mut token : @bounded.Token?
  max_noninterruptible_value_nodes : Int
}

///|
pub enum GraphApplyPoll {
  GraphApplyContinue(progress~ : Int64, work~ : Int64)
  GraphApplyComplete(@graph.Completed, progress~ : Int64, work~ : Int64)
  GraphApplyFailed(GraphApplyIssue, progress~ : Int64, work~ : Int64)
  GraphApplyStopped(@bounded.StopReason, progress~ : Int64, work~ : Int64)
}

///|
pub(all) enum GraphApplyIssue {
  InvalidGraphApplyKernel
  GraphApplyInputUnavailable
  GraphApplyInvalidDelta
  GraphApplyWrongBase
  GraphApplyWrongContract
  GraphApplyWrongTarget
  GraphApplyPrecondition
  GraphApplySnapshot(@snapshot.Issue)
  GraphApplyOutput(@graph.Issue)
  GraphApplyExecutionIssue(@bounded.Issue)
} derive(Eq, Debug)

///|
fn graph_apply_base_available(value : GraphApplyBase) -> Bool {
  match value {
    Stored(read, _) => @graph.producer_read_available(read)
    Viewed(view, _) =>
      @lifecycle.producer_view_node_count(view) is Some(_) &&
      @lifecycle.producer_view_edge_count(view) is Some(_)
  }
}

///|
fn graph_apply_base_graph(value : GraphApplyBase) -> @carrier.Graph? {
  match value {
    Stored(_, storage) =>
      match @storage.carrier(storage) {
        @carrier.GraphValue(graph) => Some(graph)
        _ => None
      }
    Viewed(_, graph) => Some(graph)
  }
}

///|
fn graph_apply_base_node_count(value : GraphApplyBase) -> Int? {
  match value {
    Stored(_, storage) => Some(@storage.node_count(storage))
    Viewed(view, _) => @lifecycle.producer_view_node_count(view)
  }
}

///|
fn graph_apply_base_edge_count(value : GraphApplyBase) -> Int? {
  match value {
    Stored(_, storage) => Some(@storage.edge_count(storage))
    Viewed(view, _) => @lifecycle.producer_view_edge_count(view)
  }
}

///|
fn graph_apply_base_node_identity(
  value : GraphApplyBase,
  index : Int,
) -> @value.CheckedValue? {
  match value {
    Stored(_, storage) => @storage.node_identity(storage, index)
    Viewed(view, _) =>
      match @lifecycle.producer_view_node_identity(view, index) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_apply_base_node_property(
  value : GraphApplyBase,
  node : Int,
  property : Int,
) -> @value.CheckedValue? {
  match value {
    Stored(_, storage) => @storage.node_property(storage, node, property)
    Viewed(view, _) =>
      match @lifecycle.producer_view_node_property(view, node, property) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_apply_base_edge_endpoints(
  value : GraphApplyBase,
  edge : Int,
) -> (Int, Int)? {
  match value {
    Stored(_, storage) => @storage.edge_endpoints(storage, edge)
    Viewed(view, _) =>
      match @lifecycle.producer_view_edge_endpoints(view, edge) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_apply_base_edge_label(
  value : GraphApplyBase,
  edge : Int,
) -> @value.CheckedValue?? {
  match value {
    Stored(_, storage) => @storage.edge_label(storage, edge)
    Viewed(view, _) =>
      match @lifecycle.producer_view_edge_label(view, edge) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_apply_base_edge_property(
  value : GraphApplyBase,
  edge : Int,
  property : Int,
) -> @value.CheckedValue? {
  match value {
    Stored(_, storage) => @storage.edge_property(storage, edge, property)
    Viewed(view, _) =>
      match @lifecycle.producer_view_edge_property(view, edge, property) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn graph_apply_base_node_index(
  value : GraphApplyBase,
  identity : @value.CheckedValue,
) -> Result[Int?, Unit] {
  match value {
    Stored(_, storage) =>
      @storage.node_index(storage, identity).map_err(_ => ())
    Viewed(view, _) =>
      @lifecycle.producer_view_node_index(view, identity).map_err(_ => ())
  }
}

///|
fn graph_apply_base_edge_index(
  value : GraphApplyBase,
  source : @value.CheckedValue,
  target : @value.CheckedValue,
  label : @value.CheckedValue?,
) -> Result[Int?, Unit] {
  match value {
    Stored(_, storage) =>
      @storage.edge_index(storage, source, target, label).map_err(_ => ())
    Viewed(view, _) =>
      @lifecycle.producer_view_edge_index(view, source, target, label).map_err(_ => {
        ()
      })
  }
}

///|
fn apply_object_field(value : @value.Value, name : String) -> @value.Value? {
  guard value is @value.Object(fields) else { return None }
  for index in 0..<@value.element_count(fields) {
    let (field, item) = @value.element_at(fields, index).unwrap()
    if field == name {
      return Some(item)
    }
  }
  None
}

///|
fn apply_text_field(value : @value.Value, name : String) -> String? {
  match apply_object_field(value, name) {
    Some(@value.Text(text)) => Some(text)
    _ => None
  }
}

///|
fn apply_array_count(value : @value.Value) -> Int? {
  match value {
    @value.Array(items) => Some(@value.element_count(items))
    _ => None
  }
}

///|
fn apply_array_item(value : @value.Value, index : Int) -> @value.Value? {
  match value {
    @value.Array(items) => @value.element_at(items, index)
    _ => None
  }
}

///|
fn apply_checked(
  value : @value.Value,
  contract : @contract.Contract,
  limits : @value.Limits,
) -> @value.CheckedValue? {
  @value.recheck_runtime_value(value, contract, limits)
}

///|
fn apply_value_key(
  value : @value.CheckedValue,
  limits : @value.Limits,
) -> String? {
  match @value.complete_order_key(value, limits) {
    Ok(key) => Some(key)
    Err(_) => None
  }
}

///|
fn apply_node_key(value : ApplyNodeRecord, limits : @value.Limits) -> String? {
  apply_value_key(value.identity, limits)
}

///|
fn apply_edge_key(value : ApplyEdgeRecord, limits : @value.Limits) -> String? {
  guard apply_value_key(value.source, limits) is Some(source) &&
    apply_value_key(value.target, limits) is Some(target) else {
    return None
  }
  let label = match value.label {
    Some(label) => apply_value_key(label, limits)
    None => Some("null")
  }
  label.map(label => source + "\u{0}" + target + "\u{0}" + label)
}

///|
fn apply_knowledge_properties(
  raw : @value.Value,
  knowledge : @carrier.Knowledge,
  limits : @value.Limits,
) -> Array[@value.CheckedValue]? {
  guard raw is @value.Object(fields) &&
    @value.element_count(fields) == @carrier.field_count(knowledge) else {
    return None
  }
  let properties = []
  for field_index in 0..<@carrier.field_count(knowledge) {
    guard @carrier.field_at(knowledge, field_index) is Some(field) &&
      field.contract is Some(contract) &&
      apply_object_field(raw, @schema.reference_name(field.name)) is Some(item) &&
      apply_checked(item, contract, limits) is Some(checked) else {
      return None
    }
    properties.push(checked)
  }
  Some(properties)
}

///|
fn apply_node_record(
  raw : @value.Value,
  graph : @carrier.Graph,
  limits : @value.Limits,
) -> ApplyNodeRecord? {
  guard apply_object_field(raw, "id") is Some(identity) &&
    apply_checked(identity, @carrier.graph_identity(graph), limits)
    is Some(identity) &&
    apply_object_field(raw, "props") is Some(properties) &&
    apply_knowledge_properties(
      properties,
      @carrier.graph_node_properties(graph),
      limits,
    )
    is Some(properties) else {
    return None
  }
  Some({ identity, properties, })
}

///|
fn apply_edge_record(
  raw : @value.Value,
  graph : @carrier.Graph,
  limits : @value.Limits,
) -> ApplyEdgeRecord? {
  guard apply_object_field(raw, "src") is Some(source) &&
    apply_checked(source, @carrier.graph_identity(graph), limits)
    is Some(source) &&
    apply_object_field(raw, "dst") is Some(target) &&
    apply_checked(target, @carrier.graph_identity(graph), limits)
    is Some(target) &&
    apply_object_field(raw, "rel") is Some(raw_label) &&
    apply_object_field(raw, "props") is Some(properties) &&
    apply_knowledge_properties(
      properties,
      @carrier.graph_edge_properties(graph),
      limits,
    )
    is Some(properties) else {
    return None
  }
  let label = match (@carrier.graph_label_contract(graph), raw_label) {
    (None, @value.Null) => Some(None)
    (Some(contract), value) =>
      apply_checked(value, contract, limits).map(label => Some(label))
    _ => None
  }
  label.map(label => { source, target, label, properties, })
}

///|
fn apply_values_equal(
  left : @value.CheckedValue,
  right : @value.CheckedValue,
  limits : @value.Limits,
) -> Bool {
  apply_value_key(left, limits) == apply_value_key(right, limits) &&
  apply_value_key(left, limits) is Some(_)
}

///|
fn apply_node_equal(
  left : ApplyNodeRecord,
  right : ApplyNodeRecord,
  limits : @value.Limits,
) -> Bool {
  if !apply_values_equal(left.identity, right.identity, limits) ||
    left.properties.length() != right.properties.length() {
    return false
  }
  for index in 0..<left.properties.length() {
    if !apply_values_equal(
        left.properties[index],
        right.properties[index],
        limits,
      ) {
      return false
    }
  }
  true
}

///|
fn apply_edge_equal(
  left : ApplyEdgeRecord,
  right : ApplyEdgeRecord,
  limits : @value.Limits,
) -> Bool {
  if !apply_values_equal(left.source, right.source, limits) ||
    !apply_values_equal(left.target, right.target, limits) ||
    left.properties.length() != right.properties.length() {
    return false
  }
  match (left.label, right.label) {
    (None, None) => ()
    (Some(left), Some(right)) =>
      if !apply_values_equal(left, right, limits) {
        return false
      }
    _ => return false
  }
  for index in 0..<left.properties.length() {
    if !apply_values_equal(
        left.properties[index],
        right.properties[index],
        limits,
      ) {
      return false
    }
  }
  true
}

///|
fn source_node_record(state : GraphApplyState, index : Int) -> ApplyNodeRecord? {
  guard graph_apply_base_node_identity(state.base_read, index) is Some(identity) else {
    return None
  }
  let properties = []
  guard graph_apply_base_graph(state.base_read) is Some(graph) else {
    return None
  }
  for field in 0..<@carrier.field_count(@carrier.graph_node_properties(graph)) {
    guard graph_apply_base_node_property(state.base_read, index, field)
      is Some(value) else {
      return None
    }
    properties.push(value)
  }
  Some({ identity, properties, })
}

///|
fn source_edge_record(state : GraphApplyState, index : Int) -> ApplyEdgeRecord? {
  guard graph_apply_base_edge_endpoints(state.base_read, index)
    is Some((source, target)) &&
    graph_apply_base_node_identity(state.base_read, source) is Some(source) &&
    graph_apply_base_node_identity(state.base_read, target) is Some(target) &&
    graph_apply_base_edge_label(state.base_read, index) is Some(label) &&
    graph_apply_base_graph(state.base_read) is Some(graph) else {
    return None
  }
  let properties = []
  for field in 0..<@carrier.field_count(@carrier.graph_edge_properties(graph)) {
    guard graph_apply_base_edge_property(state.base_read, index, field)
      is Some(value) else {
      return None
    }
    properties.push(value)
  }
  Some({ source, target, label, properties, })
}

///|
fn apply_action_array(delta : @value.Value, list : Int) -> @value.Value? {
  let (kind, action) = match list {
    0 => ("nodes", "add")
    1 => ("nodes", "remove")
    2 => ("nodes", "update")
    3 => ("edges", "add")
    4 => ("edges", "remove")
    5 => ("edges", "update")
    _ => return None
  }
  apply_object_field(delta, kind).bind(value => {
    apply_object_field(value, action)
  })
}

///|
fn apply_ordered_key(state : GraphApplyState, key : String) -> Bool {
  if state.previous_action_key is Some(previous) && previous >= key {
    return false
  }
  state.previous_action_key = Some(key)
  true
}

///|
fn parse_node_action(
  state : GraphApplyState,
  raw : @value.Value,
  update : Bool,
) -> Bool {
  guard graph_apply_base_graph(state.base_read) is Some(graph) else {
    return false
  }
  let limits : @value.Limits = {
    max_nodes: state.limits.max_value_nodes,
    max_depth: state.limits.max_value_depth,
    max_text_bytes: state.limits.max_value_bytes,
  }
  if update {
    guard apply_object_field(raw, "before") is Some(before_raw) &&
      apply_object_field(raw, "after") is Some(after_raw) &&
      apply_node_record(before_raw, graph, limits) is Some(before) &&
      apply_node_record(after_raw, graph, limits) is Some(after) &&
      apply_node_key(before, limits) is Some(key) &&
      apply_node_key(after, limits) == Some(key) &&
      apply_ordered_key(state, key) &&
      graph_apply_base_node_index(state.base_read, before.identity)
      is Ok(Some(index)) &&
      source_node_record(state, index) is Some(actual) &&
      apply_node_equal(actual, before, limits) &&
      !state.node_add.contains(key) &&
      !state.node_remove.contains(key) &&
      !state.node_update.contains(key) else {
      return false
    }
    state.node_update[key] = { after, }
    return true
  }
  guard apply_node_record(raw, graph, limits) is Some(record) &&
    apply_node_key(record, limits) is Some(key) &&
    apply_ordered_key(state, key) &&
    !state.node_add.contains(key) &&
    !state.node_remove.contains(key) &&
    !state.node_update.contains(key) else {
    return false
  }
  if state.action_list == 0 {
    guard graph_apply_base_node_index(state.base_read, record.identity)
      is Ok(None) else {
      return false
    }
    state.node_add[key] = record
    state.node_add_order.push(key)
  } else {
    guard graph_apply_base_node_index(state.base_read, record.identity)
      is Ok(Some(index)) &&
      source_node_record(state, index) is Some(actual) &&
      apply_node_equal(actual, record, limits) else {
      return false
    }
    state.node_remove[key] = record
  }
  true
}

///|
fn parse_edge_action(
  state : GraphApplyState,
  raw : @value.Value,
  update : Bool,
) -> Bool {
  guard graph_apply_base_graph(state.base_read) is Some(graph) else {
    return false
  }
  let limits : @value.Limits = {
    max_nodes: state.limits.max_value_nodes,
    max_depth: state.limits.max_value_depth,
    max_text_bytes: state.limits.max_value_bytes,
  }
  if update {
    guard apply_object_field(raw, "before") is Some(before_raw) &&
      apply_object_field(raw, "after") is Some(after_raw) &&
      apply_edge_record(before_raw, graph, limits) is Some(before) &&
      apply_edge_record(after_raw, graph, limits) is Some(after) &&
      apply_edge_key(before, limits) is Some(key) &&
      apply_edge_key(after, limits) == Some(key) &&
      apply_ordered_key(state, key) &&
      graph_apply_base_edge_index(
        state.base_read,
        before.source,
        before.target,
        before.label,
      )
      is Ok(Some(index)) &&
      source_edge_record(state, index) is Some(actual) &&
      apply_edge_equal(actual, before, limits) &&
      !state.edge_add.contains(key) &&
      !state.edge_remove.contains(key) &&
      !state.edge_update.contains(key) else {
      return false
    }
    state.edge_update[key] = { after, }
    return true
  }
  guard apply_edge_record(raw, graph, limits) is Some(record) &&
    apply_edge_key(record, limits) is Some(key) &&
    apply_ordered_key(state, key) &&
    !state.edge_add.contains(key) &&
    !state.edge_remove.contains(key) &&
    !state.edge_update.contains(key) else {
    return false
  }
  if state.action_list == 3 {
    guard graph_apply_base_edge_index(
        state.base_read,
        record.source,
        record.target,
        record.label,
      )
      is Ok(None) else {
      return false
    }
    state.edge_add[key] = record
    state.edge_add_order.push(key)
  } else {
    guard graph_apply_base_edge_index(
        state.base_read,
        record.source,
        record.target,
        record.label,
      )
      is Ok(Some(index)) &&
      source_edge_record(state, index) is Some(actual) &&
      apply_edge_equal(actual, record, limits) else {
      return false
    }
    state.edge_remove[key] = record
  }
  true
}

///|
fn parse_one_action(state : GraphApplyState) -> Bool {
  guard apply_action_array(state.delta.value, state.action_list) is Some(items) &&
    apply_array_item(items, state.action_index) is Some(item) else {
    return false
  }
  if state.action_list < 3 {
    parse_node_action(state, item, state.action_list == 2)
  } else {
    parse_edge_action(state, item, state.action_list == 5)
  }
}

///|
fn append_apply_node(
  state : GraphApplyState,
  record : ApplyNodeRecord,
) -> GraphApplyIssue? {
  guard state.output is Some(output) else {
    return Some(InvalidGraphApplyKernel)
  }
  match @graph.append_node(output, record.identity, record.properties) {
    Ok(_) => None
    Err(issue) => Some(GraphApplyOutput(issue))
  }
}

///|
fn append_apply_edge(
  state : GraphApplyState,
  record : ApplyEdgeRecord,
) -> GraphApplyIssue? {
  guard state.output is Some(output) else {
    return Some(InvalidGraphApplyKernel)
  }
  match
    @graph.append_edge(
      output,
      record.source,
      record.target,
      record.label,
      record.properties,
    ) {
    Ok(_) => None
    Err(issue) => Some(GraphApplyOutput(issue))
  }
}

///|
fn graph_apply_step(
  state : GraphApplyState,
  quantum : Int,
  reader : @bounded.Reader,
) -> @bounded.KernelStep[@graph.Completed, GraphApplyIssue] {
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    if @bounded.stop_requested(reader) is Some(reason) {
      return @bounded.Stopped(reason, progress, used)
    }
    if !graph_apply_base_available(state.base_read) ||
      !@execution.producer_read_available(state.delta_read) {
      return @bounded.Failed(GraphApplyInputUnavailable, progress, used)
    }
    match state.phase {
      SnapshotBase => {
        guard state.base_snapshot_preparation is Some(preparation) else {
          return @bounded.Failed(InvalidGraphApplyKernel, progress, used)
        }
        match @snapshot.advance(preparation, quantum - used) {
          Ok(@snapshot.Continue(progress=made, work~)) => {
            progress += made.to_int()
            used += work.to_int()
          }
          Ok(@snapshot.Complete(snapshot, progress=made, work~)) => {
            progress += made.to_int()
            used += work.to_int()
            state.base_snapshot_preparation = None
            if @snapshot.cid(snapshot) != state.base_cid {
              @snapshot.cleanup(snapshot) |> ignore
              return @bounded.Failed(GraphApplyWrongBase, progress, used)
            }
            state.base_snapshot = Some(snapshot)
            state.phase = ParseActions
          }
          Err(issue) =>
            return @bounded.Failed(GraphApplySnapshot(issue), progress, used)
        }
      }
      ParseActions => {
        guard apply_action_array(state.delta.value, state.action_list)
          is Some(items) &&
          apply_array_count(items) is Some(count) else {
          return @bounded.Failed(GraphApplyInvalidDelta, progress, used + 1)
        }
        if state.action_index < count {
          used += 1
          if !parse_one_action(state) {
            return @bounded.Failed(GraphApplyPrecondition, progress, used)
          }
          state.action_index += 1
          progress += 1
          continue
        }
        state.action_list += 1
        state.action_index = 0
        state.previous_action_key = None
        used += 1
        if state.action_list >= 6 {
          state.output = match
            @graph.prepare_output(
              state.owner,
              @pipeline.Step(state.step),
              match state.base_read {
                Stored(_, storage) => @storage.mode(storage)
                Viewed(_, _) => @storage.DeclaredNodes
              },
              state.limits,
              state.storage_bytes,
              state.available,
            ) {
            Ok(output) => Some(output)
            Err(issue) =>
              return @bounded.Failed(GraphApplyOutput(issue), progress, used)
          }
          state.phase = CopyNodes
          state.record = 0
        }
      }
      CopyNodes => {
        guard graph_apply_base_node_count(state.base_read) is Some(node_count) else {
          return @bounded.Failed(GraphApplyInputUnavailable, progress, used)
        }
        if state.record >= node_count {
          state.phase = AddNodes
          state.record = 0
          continue
        }
        guard source_node_record(state, state.record) is Some(record) else {
          return @bounded.Failed(GraphApplyInputUnavailable, progress, used + 1)
        }
        let limits : @value.Limits = {
          max_nodes: state.limits.max_value_nodes,
          max_depth: state.limits.max_value_depth,
          max_text_bytes: state.limits.max_value_bytes,
        }
        guard apply_node_key(record, limits) is Some(key) else {
          return @bounded.Failed(GraphApplyInputUnavailable, progress, used + 1)
        }
        let selected = state.node_update.get(key).map(update => update.after)
        if !state.node_remove.contains(key) {
          match append_apply_node(state, selected.unwrap_or(record)) {
            Some(issue) => return @bounded.Failed(issue, progress, used + 1)
            None => ()
          }
        }
        state.record += 1
        used += 1
        progress += 1
      }
      AddNodes => {
        if state.record >= state.node_add_order.length() {
          state.phase = CopyEdges
          state.record = 0
          continue
        }
        guard state.node_add.get(state.node_add_order[state.record])
          is Some(record) else {
          return @bounded.Failed(InvalidGraphApplyKernel, progress, used + 1)
        }
        match append_apply_node(state, record) {
          Some(issue) => return @bounded.Failed(issue, progress, used + 1)
          None => ()
        }
        state.record += 1
        used += 1
        progress += 1
      }
      CopyEdges => {
        guard graph_apply_base_edge_count(state.base_read) is Some(edge_count) else {
          return @bounded.Failed(GraphApplyInputUnavailable, progress, used)
        }
        if state.record >= edge_count {
          state.phase = AddEdges
          state.record = 0
          continue
        }
        guard source_edge_record(state, state.record) is Some(record) else {
          return @bounded.Failed(GraphApplyInputUnavailable, progress, used + 1)
        }
        let limits : @value.Limits = {
          max_nodes: state.limits.max_value_nodes,
          max_depth: state.limits.max_value_depth,
          max_text_bytes: state.limits.max_value_bytes,
        }
        guard apply_edge_key(record, limits) is Some(key) else {
          return @bounded.Failed(GraphApplyInputUnavailable, progress, used + 1)
        }
        let selected = state.edge_update.get(key).map(update => update.after)
        if !state.edge_remove.contains(key) {
          match append_apply_edge(state, selected.unwrap_or(record)) {
            Some(issue) => return @bounded.Failed(issue, progress, used + 1)
            None => ()
          }
        }
        state.record += 1
        used += 1
        progress += 1
      }
      AddEdges => {
        if state.record >= state.edge_add_order.length() {
          state.phase = FinishGraph
          continue
        }
        guard state.edge_add.get(state.edge_add_order[state.record])
          is Some(record) else {
          return @bounded.Failed(InvalidGraphApplyKernel, progress, used + 1)
        }
        match append_apply_edge(state, record) {
          Some(issue) => return @bounded.Failed(issue, progress, used + 1)
          None => ()
        }
        state.record += 1
        used += 1
        progress += 1
      }
      FinishGraph => {
        guard state.output is Some(output) else {
          return @bounded.Failed(InvalidGraphApplyKernel, progress, used + 1)
        }
        state.output = None
        let completed = match @graph.finish_output(output) {
          Ok(completed) => completed
          Err(issue) =>
            return @bounded.Failed(GraphApplyOutput(issue), progress, used + 1)
        }
        guard @graph.completed_storage(completed) is Some(storage) else {
          @graph.discard_completed(completed) |> ignore
          return @bounded.Failed(GraphApplyInputUnavailable, progress, used + 1)
        }
        let snapshot_limits : @snapshot.Limits = {
          max_workspace_slots: state.limits.max_workspace_slots,
          max_identity_bytes: state.limits.max_value_bytes,
          max_identity_nodes: state.limits.max_value_nodes,
          max_identity_depth: state.limits.max_value_depth,
          value_limits: {
            max_nodes: state.limits.max_value_nodes,
            max_depth: state.limits.max_value_depth,
            max_text_bytes: state.limits.max_value_bytes,
          },
        }
        state.result_snapshot_preparation = match
          @snapshot.prepare(storage, state.graph_contract_cid, snapshot_limits) {
          Ok(preparation) => Some(preparation)
          Err(issue) => {
            @graph.discard_completed(completed) |> ignore
            return @bounded.Failed(
              GraphApplySnapshot(issue),
              progress,
              used + 1,
            )
          }
        }
        state.completed = Some(completed)
        state.phase = SnapshotResult
        used += 1
        progress += 1
      }
      SnapshotResult => {
        guard state.result_snapshot_preparation is Some(preparation) else {
          return @bounded.Failed(InvalidGraphApplyKernel, progress, used)
        }
        match @snapshot.advance(preparation, quantum - used) {
          Ok(@snapshot.Continue(progress=made, work~)) => {
            progress += made.to_int()
            used += work.to_int()
          }
          Ok(@snapshot.Complete(snapshot, progress=made, work~)) => {
            progress += made.to_int()
            used += work.to_int()
            state.result_snapshot_preparation = None
            if @snapshot.cid(snapshot) != state.target_cid {
              @snapshot.cleanup(snapshot) |> ignore
              return @bounded.Failed(GraphApplyWrongTarget, progress, used)
            }
            state.result_snapshot = Some(snapshot)
            guard state.completed is Some(completed) else {
              return @bounded.Failed(InvalidGraphApplyKernel, progress, used)
            }
            state.completed = None
            return @bounded.Complete(completed, progress, used)
          }
          Err(issue) =>
            return @bounded.Failed(GraphApplySnapshot(issue), progress, used)
        }
      }
    }
  }
  @bounded.Continue(progress, used)
}

///|
fn cleanup_graph_apply_state(state : GraphApplyState) -> Bool {
  if state.base_snapshot_preparation is Some(preparation) {
    @snapshot.cancel(preparation) |> ignore
    state.base_snapshot_preparation = None
  }
  if state.base_snapshot is Some(snapshot) {
    @snapshot.cleanup(snapshot) |> ignore
    state.base_snapshot = None
  }
  if state.result_snapshot_preparation is Some(preparation) {
    @snapshot.cancel(preparation) |> ignore
    state.result_snapshot_preparation = None
  }
  if state.result_snapshot is Some(snapshot) {
    @snapshot.cleanup(snapshot) |> ignore
    state.result_snapshot = None
  }
  if state.output is Some(output) {
    @graph.cancel_output(output) |> ignore
    state.output = None
  }
  if state.completed is Some(completed) {
    @graph.discard_completed(completed) |> ignore
    state.completed = None
  }
  true
}

///|
pub fn start_graph_apply(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  base_read : @graph.ProducerRead,
  delta_read : @execution.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[GraphApplyExecution, GraphApplyIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphRelationStep(prepared)) &&
    @lower.graph_relation_kind(prepared) == @lower.ApplyGraphRelation &&
    @lower.graph_relation_apply_field(prepared) is Some(field) &&
    @lower.graph_relation_graph_contract_cid(prepared)
    is Some(graph_contract_cid) &&
    @graph.producer_read_matches_operation_input(base_read, owner, step, 0) &&
    @execution.producer_read_matches_operation_input(delta_read, owner, step, 1) &&
    @graph.producer_read_storage(base_read) is Some(base) &&
    @storage.carrier(base) is @carrier.GraphValue(_) &&
    @execution.producer_read_row_count(delta_read) == 1 else {
    return Err(InvalidGraphApplyKernel)
  }
  let schema = @execution.producer_read_schema(delta_read)
  let mut column = -1
  for index in 0..<@schema.field_count(schema) {
    if @schema.field_at(schema, index).map(item => item.name) ==
      Some(@schema.Unqualified(field)) {
      column = index
    }
  }
  guard column >= 0 &&
    @execution.producer_read_checked_cell(delta_read, 0, column, {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    })
    is Some(delta) &&
    apply_text_field(delta.value, "version") == Some("actql-graph-delta/0.1") &&
    apply_text_field(delta.value, "graph_contract_cid")
    is Some(delta_contract_cid) &&
    apply_text_field(delta.value, "base_graph_cid") is Some(base_cid) &&
    apply_text_field(delta.value, "target_graph_cid") is Some(target_cid) else {
    return Err(GraphApplyInvalidDelta)
  }
  if delta_contract_cid != graph_contract_cid {
    return Err(GraphApplyWrongContract)
  }
  let snapshot_limits : @snapshot.Limits = {
    max_workspace_slots: limits.max_workspace_slots,
    max_identity_bytes: limits.max_value_bytes,
    max_identity_nodes: limits.max_value_nodes,
    max_identity_depth: limits.max_value_depth,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
  }
  let base_snapshot_preparation = match
    @snapshot.prepare(base, graph_contract_cid, snapshot_limits) {
    Ok(preparation) => preparation
    Err(issue) => return Err(GraphApplySnapshot(issue))
  }
  let state : GraphApplyState = {
    base_read: Stored(base_read, base),
    delta_read,
    delta,
    graph_contract_cid,
    base_cid,
    target_cid,
    limits,
    storage_bytes,
    available,
    owner,
    step,
    phase: SnapshotBase,
    base_snapshot_preparation: Some(base_snapshot_preparation),
    base_snapshot: None,
    result_snapshot_preparation: None,
    result_snapshot: None,
    output: None,
    completed: None,
    node_add: Map([]),
    node_remove: Map([]),
    node_update: Map([]),
    edge_add: Map([]),
    edge_remove: Map([]),
    edge_update: Map([]),
    node_add_order: [],
    edge_add_order: [],
    action_list: 0,
    action_index: 0,
    previous_action_key: None,
    record: 0,
  }
  let (session, token) = @bounded.start(
    control, state, graph_apply_step, cleanup_graph_apply_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes,
  })
}

///|
pub fn start_graph_apply_view(
  control : @bounded.Control,
  sequence : @lower.PreparedSequence,
  step : Int,
  base_view : @lifecycle.ProducerView,
  delta_read : @execution.ProducerRead,
  limits : @storage.Limits,
  storage_bytes : Int64,
  available : () -> Bool,
) -> Result[GraphApplyExecution, GraphApplyIssue] {
  let owner = @lower.sequence_owner(sequence)
  guard @lower.sequence_step(sequence, step)
    is Some(@lower.GraphRelationStep(prepared)) &&
    @lower.graph_relation_kind(prepared) == @lower.ApplyGraphRelation &&
    @lower.graph_relation_apply_field(prepared) is Some(field) &&
    @lower.graph_relation_graph_contract_cid(prepared)
    is Some(graph_contract_cid) &&
    @lifecycle.producer_read_reference_matches_operation_input(
      @lifecycle.producer_view_read_reference(base_view),
      owner,
      step,
      0,
    ) &&
    @lower.node_at(@lower.bound_preparation(owner), step) is Some(node) &&
    @lower.node_input_target(node, 0) is Some(@pipeline.Input(base_index)) &&
    @execution.producer_read_matches_operation_input(delta_read, owner, step, 1) &&
    @pipeline.carrier_at(
      @lower.pipeline(@lower.bound_preparation(owner)),
      @pipeline.Input(base_index),
    )
    is Some(@carrier.GraphValue(graph)) &&
    @execution.producer_read_row_count(delta_read) == 1 else {
    return Err(InvalidGraphApplyKernel)
  }
  let schema = @execution.producer_read_schema(delta_read)
  let mut column = -1
  for index in 0..<@schema.field_count(schema) {
    if @schema.field_at(schema, index).map(item => item.name) ==
      Some(@schema.Unqualified(field)) {
      column = index
    }
  }
  guard column >= 0 &&
    @execution.producer_read_checked_cell(delta_read, 0, column, {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    })
    is Some(delta) &&
    apply_text_field(delta.value, "version") == Some("actql-graph-delta/0.1") &&
    apply_text_field(delta.value, "graph_contract_cid")
    is Some(delta_contract_cid) &&
    apply_text_field(delta.value, "base_graph_cid") is Some(base_cid) &&
    apply_text_field(delta.value, "target_graph_cid") is Some(target_cid) else {
    return Err(GraphApplyInvalidDelta)
  }
  if delta_contract_cid != graph_contract_cid {
    return Err(GraphApplyWrongContract)
  }
  let snapshot_limits : @snapshot.Limits = {
    max_workspace_slots: limits.max_workspace_slots,
    max_identity_bytes: limits.max_value_bytes,
    max_identity_nodes: limits.max_value_nodes,
    max_identity_depth: limits.max_value_depth,
    value_limits: {
      max_nodes: limits.max_value_nodes,
      max_depth: limits.max_value_depth,
      max_text_bytes: limits.max_value_bytes,
    },
  }
  let base_snapshot_preparation = match
    @snapshot.prepare_view(
      base_view, graph, graph_contract_cid, snapshot_limits,
    ) {
    Ok(preparation) => preparation
    Err(issue) => return Err(GraphApplySnapshot(issue))
  }
  let state : GraphApplyState = {
    base_read: Viewed(base_view, graph),
    delta_read,
    delta,
    graph_contract_cid,
    base_cid,
    target_cid,
    limits,
    storage_bytes,
    available,
    owner,
    step,
    phase: SnapshotBase,
    base_snapshot_preparation: Some(base_snapshot_preparation),
    base_snapshot: None,
    result_snapshot_preparation: None,
    result_snapshot: None,
    output: None,
    completed: None,
    node_add: Map([]),
    node_remove: Map([]),
    node_update: Map([]),
    edge_add: Map([]),
    edge_remove: Map([]),
    edge_update: Map([]),
    node_add_order: [],
    edge_add_order: [],
    action_list: 0,
    action_index: 0,
    previous_action_key: None,
    record: 0,
  }
  let (session, token) = @bounded.start(
    control, state, graph_apply_step, cleanup_graph_apply_state, @graph.discard_completed,
  )
  Ok({
    session,
    token: Some(token),
    max_noninterruptible_value_nodes: limits.max_value_nodes,
  })
}

///|
pub fn advance_graph_apply(
  value : GraphApplyExecution,
  quantum : Int,
) -> Result[GraphApplyPoll, GraphApplyIssue] {
  guard value.token is Some(token) else {
    return Err(GraphApplyExecutionIssue(@bounded.Terminal))
  }
  match @bounded.advance(value.session, token, quantum) {
    Err(issue) => Err(GraphApplyExecutionIssue(issue))
    Ok(@bounded.ContinueWith(next, progress~, work~)) => {
      value.token = Some(next)
      Ok(GraphApplyContinue(progress~, work~))
    }
    Ok(@bounded.Completed(output, progress~, work~)) => {
      value.token = None
      Ok(GraphApplyComplete(output, progress~, work~))
    }
    Ok(@bounded.FailedWith(issue, progress~, work~)) => {
      value.token = None
      Ok(GraphApplyFailed(issue, progress~, work~))
    }
    Ok(@bounded.StoppedWith(reason, progress~, work~)) => {
      value.token = None
      Ok(GraphApplyStopped(reason, progress~, work~))
    }
  }
}

///|
pub fn graph_apply_max_noninterruptible_value_nodes(
  value : GraphApplyExecution,
) -> Int {
  value.max_noninterruptible_value_nodes
}

///|
pub fn graph_apply_stopped(value : GraphApplyExecution) -> Bool {
  @bounded.session_stopped(value.session)
}

///|
pub fn graph_apply_cleanup_pending(value : GraphApplyExecution) -> Bool {
  @bounded.cleanup_pending(value.session)
}

///|
pub fn cleanup_graph_apply(
  value : GraphApplyExecution,
) -> Result[Bool, GraphApplyIssue] {
  @bounded.cleanup(value.session).map_err(issue => {
    GraphApplyExecutionIssue(issue)
  })
}
