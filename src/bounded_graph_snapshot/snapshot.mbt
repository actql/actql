///|
pub(all) struct Limits {
  max_workspace_slots : Int
  max_identity_bytes : Int
  max_identity_nodes : Int
  max_identity_depth : Int
  value_limits : @value.Limits
}

///|
pub(all) enum Issue {
  InvalidLimits
  InvalidGraph
  WorkspaceLimit
  KeyOrder(@value.KeyOrderIssue)
  Sort(@sort.Issue)
  Identity(@identity.Issue)
  Terminal
} derive(Eq, Debug)

///|
pub enum Poll {
  Continue(progress~ : Int64, work~ : Int64)
  Complete(Snapshot, progress~ : Int64, work~ : Int64)
}

///|
priv enum Phase {
  BuildNodeKeys
  SortNodes
  HashNodeBegin
  HashNodeProperties
  HashNodeEnd
  EndNodes
  BuildEdgeKeys
  SortEdges
  HashEdgeBegin
  HashEdgeProperties
  HashEdgeEnd
  Finish
  Finished
} derive(Eq)

///|
priv enum SnapshotSource {
  Stored(@storage.Storage)
  Viewed(@lifecycle.ProducerView, @carrier.Graph)
}

///|
struct Preparation {
  source : SnapshotSource
  limits : Limits
  builder : @identity.Builder
  node_keys : Array[Array[String]]
  edge_keys : Array[Array[String]]
  mut node_sort : @sort.Sort?
  mut edge_sort : @sort.Sort?
  mut phase : Phase
  mut cursor : Int
  mut property : Int
}

///|
struct Snapshot {
  cid : String
  node_sort : @sort.Sort
  edge_sort : @sort.Sort
}

///|
fn checked_multiply(left : Int, right : Int) -> Int? {
  if left < 0 || right < 0 || (left != 0 && right > 2147483647 / left) {
    None
  } else {
    Some(left * right)
  }
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
fn source_node_count(source : SnapshotSource) -> Int? {
  match source {
    Stored(storage) => Some(@storage.node_count(storage))
    Viewed(view, _) => @lifecycle.producer_view_node_count(view)
  }
}

///|
fn source_edge_count(source : SnapshotSource) -> Int? {
  match source {
    Stored(storage) => Some(@storage.edge_count(storage))
    Viewed(view, _) => @lifecycle.producer_view_edge_count(view)
  }
}

///|
fn source_graph(source : SnapshotSource) -> @carrier.Graph? {
  match source {
    Stored(storage) => graph(storage)
    Viewed(_, graph) => Some(graph)
  }
}

///|
fn source_node_identity(
  source : SnapshotSource,
  index : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(storage) => @storage.node_identity(storage, index)
    Viewed(view, _) =>
      match @lifecycle.producer_view_node_identity(view, index) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn source_node_property(
  source : SnapshotSource,
  node : Int,
  property : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(storage) => @storage.node_property(storage, node, property)
    Viewed(view, _) =>
      match @lifecycle.producer_view_node_property(view, node, property) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn source_edge_endpoints(source : SnapshotSource, edge : Int) -> (Int, Int)? {
  match source {
    Stored(storage) => @storage.edge_endpoints(storage, edge)
    Viewed(view, _) =>
      match @lifecycle.producer_view_edge_endpoints(view, edge) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn source_edge_label(
  source : SnapshotSource,
  edge : Int,
) -> @value.CheckedValue?? {
  match source {
    Stored(storage) => @storage.edge_label(storage, edge)
    Viewed(view, _) =>
      match @lifecycle.producer_view_edge_label(view, edge) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn source_edge_property(
  source : SnapshotSource,
  edge : Int,
  property : Int,
) -> @value.CheckedValue? {
  match source {
    Stored(storage) => @storage.edge_property(storage, edge, property)
    Viewed(view, _) =>
      match @lifecycle.producer_view_edge_property(view, edge, property) {
        Ok(value) => Some(value)
        Err(_) => None
      }
  }
}

///|
fn required_workspace(source : SnapshotSource) -> Int? {
  guard source_node_count(source) is Some(node_count) &&
    source_edge_count(source) is Some(edge_count) &&
    checked_multiply(node_count, 5) is Some(nodes) &&
    checked_multiply(edge_count, 7) is Some(edges) else {
    return None
  }
  checked_add(nodes, edges)
}

///|
pub fn workspace_slots(storage : @storage.Storage) -> Int? {
  required_workspace(Stored(storage))
}

///|
fn graph(value : @storage.Storage) -> @carrier.Graph? {
  match @storage.carrier(value) {
    @carrier.GraphValue(graph) => Some(graph)
    _ => None
  }
}

///|
/// Canonical typed ID order: the declared type's non-null comparison, not
/// the canonical key encoding. An edge label present under a nullable label
/// contract is still ordered by its value.
fn order_key(
  value : @value.CheckedValue,
  _limits : @value.Limits,
) -> Result[String, Issue] {
  @value.typed_key_order_text(value).map_err(issue => KeyOrder(issue))
}

///|
/// Absent and null labels sort before present labels.
fn label_order_key(
  label : @value.CheckedValue?,
  limits : @value.Limits,
) -> Result[String, Issue] {
  match label {
    None => Ok("0")
    Some(value) =>
      if value.value is Null {
        Ok("0")
      } else {
        order_key(value, limits).map(key => "1" + key)
      }
  }
}

///|
pub fn prepare(
  storage : @storage.Storage,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  prepare_source(Stored(storage), graph_contract_cid, limits)
}

///|
pub fn prepare_view(
  view : @lifecycle.ProducerView,
  graph : @carrier.Graph,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  prepare_source(Viewed(view, graph), graph_contract_cid, limits)
}

///|
fn prepare_source(
  source : SnapshotSource,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  if limits.max_workspace_slots < 0 ||
    limits.max_identity_bytes < 0 ||
    limits.max_identity_nodes < 0 ||
    limits.max_identity_depth < 0 ||
    limits.value_limits.max_nodes < 0 ||
    limits.value_limits.max_depth < 0 ||
    limits.value_limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard source_graph(source) is Some(_) &&
    required_workspace(source) is Some(required) else {
    return Err(InvalidGraph)
  }
  if required > limits.max_workspace_slots {
    return Err(WorkspaceLimit)
  }
  let builder = match
    @identity.prepare(graph_contract_cid, {
      max_bytes: limits.max_identity_bytes,
      max_nodes: limits.max_identity_nodes,
      max_depth: limits.max_identity_depth,
      value_limits: limits.value_limits,
    }) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  Ok({
    source,
    limits,
    builder,
    node_keys: [],
    edge_keys: [],
    node_sort: None,
    edge_sort: None,
    phase: BuildNodeKeys,
    cursor: 0,
    property: 0,
  })
}

///|
fn advance_sort(
  value : Preparation,
  sort : @sort.Sort,
  quantum : Int,
  next : Phase,
) -> Result[(Int, Int), Issue] {
  match @sort.advance(sort, quantum) {
    Ok(@sort.Continue(progress~, work~)) =>
      Ok((progress.to_int(), work.to_int()))
    Ok(@sort.Complete(progress~, work~)) => {
      value.phase = next
      value.cursor = 0
      Ok((progress.to_int(), work.to_int()))
    }
    Err(issue) => Err(Sort(issue))
  }
}

///|
fn sorted_node(value : Preparation) -> Int? {
  value.node_sort.bind(sort => @sort.index_at(sort, value.cursor))
}

///|
fn sorted_edge(value : Preparation) -> Int? {
  value.edge_sort.bind(sort => @sort.index_at(sort, value.cursor))
}

///|
pub fn advance(value : Preparation, quantum : Int) -> Result[Poll, Issue] {
  if quantum < 1 {
    return Err(InvalidLimits)
  }
  if value.phase == Finished {
    return Err(Terminal)
  }
  guard source_graph(value.source) is Some(graph) &&
    source_node_count(value.source) is Some(node_count) &&
    source_edge_count(value.source) is Some(edge_count) else {
    return Err(InvalidGraph)
  }
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    match value.phase {
      BuildNodeKeys => {
        if value.cursor >= node_count {
          value.node_sort = match
            @sort.prepare(value.node_keys, node_count * 2) {
            Ok(sort) => Some(sort)
            Err(issue) => return Err(Sort(issue))
          }
          value.phase = SortNodes
          continue
        }
        guard source_node_identity(value.source, value.cursor) is Some(identity) else {
          return Err(InvalidGraph)
        }
        let key = match order_key(identity, value.limits.value_limits) {
          Ok(key) => key
          Err(issue) => return Err(issue)
        }
        value.node_keys.push([key])
        value.cursor += 1
        used += 1
        progress += 1
      }
      SortNodes => {
        guard value.node_sort is Some(sort) else { return Err(InvalidGraph) }
        match advance_sort(value, sort, quantum - used, HashNodeBegin) {
          Ok((made, work)) => {
            progress += made
            used += work
          }
          Err(issue) => return Err(issue)
        }
        if used >= quantum {
          break
        }
      }
      HashNodeBegin => {
        if value.cursor >= node_count {
          value.phase = EndNodes
          continue
        }
        guard sorted_node(value) is Some(node) &&
          source_node_identity(value.source, node) is Some(identity) else {
          return Err(InvalidGraph)
        }
        match @identity.begin_node(value.builder, identity) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.property = 0
        value.phase = HashNodeProperties
        used += 1
        progress += 1
      }
      HashNodeProperties => {
        let count = @carrier.field_count(@carrier.graph_node_properties(graph))
        if value.property >= count {
          value.phase = HashNodeEnd
          continue
        }
        guard sorted_node(value) is Some(node) &&
          @carrier.field_at(
            @carrier.graph_node_properties(graph),
            value.property,
          )
          is Some(field) &&
          source_node_property(value.source, node, value.property)
          is Some(property) else {
          return Err(InvalidGraph)
        }
        match
          @identity.append_property(
            value.builder,
            @schema.reference_name(field.name),
            property,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.property += 1
        used += 1
        progress += 1
      }
      HashNodeEnd => {
        match @identity.end_node(value.builder) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.cursor += 1
        value.phase = HashNodeBegin
        used += 1
        progress += 1
      }
      EndNodes => {
        match @identity.end_nodes(value.builder) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.cursor = 0
        value.phase = BuildEdgeKeys
        used += 1
        progress += 1
      }
      BuildEdgeKeys => {
        if value.cursor >= edge_count {
          value.edge_sort = match
            @sort.prepare(value.edge_keys, edge_count * 2) {
            Ok(sort) => Some(sort)
            Err(issue) => return Err(Sort(issue))
          }
          value.phase = SortEdges
          continue
        }
        guard source_edge_endpoints(value.source, value.cursor)
          is Some((source, target)) &&
          source_node_identity(value.source, source) is Some(source_id) &&
          source_node_identity(value.source, target) is Some(target_id) &&
          source_edge_label(value.source, value.cursor) is Some(label) else {
          return Err(InvalidGraph)
        }
        let source_key = match order_key(source_id, value.limits.value_limits) {
          Ok(key) => key
          Err(issue) => return Err(issue)
        }
        let target_key = match order_key(target_id, value.limits.value_limits) {
          Ok(key) => key
          Err(issue) => return Err(issue)
        }
        let label_key = match
          label_order_key(label, value.limits.value_limits) {
          Ok(key) => key
          Err(issue) => return Err(issue)
        }
        value.edge_keys.push([source_key, target_key, label_key])
        value.cursor += 1
        used += 1
        progress += 1
      }
      SortEdges => {
        guard value.edge_sort is Some(sort) else { return Err(InvalidGraph) }
        match advance_sort(value, sort, quantum - used, HashEdgeBegin) {
          Ok((made, work)) => {
            progress += made
            used += work
          }
          Err(issue) => return Err(issue)
        }
        if used >= quantum {
          break
        }
      }
      HashEdgeBegin => {
        if value.cursor >= edge_count {
          value.phase = Finish
          continue
        }
        guard sorted_edge(value) is Some(edge) &&
          source_edge_endpoints(value.source, edge) is Some((source, target)) &&
          source_node_identity(value.source, source) is Some(source_id) &&
          source_node_identity(value.source, target) is Some(target_id) &&
          source_edge_label(value.source, edge) is Some(label) else {
          return Err(InvalidGraph)
        }
        match @identity.begin_edge(value.builder, source_id, target_id, label) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.property = 0
        value.phase = HashEdgeProperties
        used += 1
        progress += 1
      }
      HashEdgeProperties => {
        let count = @carrier.field_count(@carrier.graph_edge_properties(graph))
        if value.property >= count {
          value.phase = HashEdgeEnd
          continue
        }
        guard sorted_edge(value) is Some(edge) &&
          @carrier.field_at(
            @carrier.graph_edge_properties(graph),
            value.property,
          )
          is Some(field) &&
          source_edge_property(value.source, edge, value.property)
          is Some(property) else {
          return Err(InvalidGraph)
        }
        match
          @identity.append_property(
            value.builder,
            @schema.reference_name(field.name),
            property,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.property += 1
        used += 1
        progress += 1
      }
      HashEdgeEnd => {
        match @identity.end_edge(value.builder) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.cursor += 1
        value.phase = HashEdgeBegin
        used += 1
        progress += 1
      }
      Finish => {
        let cid = match @identity.finish(value.builder) {
          Ok(cid) => cid
          Err(issue) => return Err(Identity(issue))
        }
        guard value.node_sort is Some(node_sort) &&
          value.edge_sort is Some(edge_sort) else {
          return Err(InvalidGraph)
        }
        value.phase = Finished
        used += 1
        progress += 1
        return Ok(
          Complete(
            { cid, node_sort, edge_sort, },
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
pub fn cid(value : Snapshot) -> String {
  value.cid
}

///|
pub fn node_count(value : Snapshot) -> Int {
  @sort.count(value.node_sort)
}

///|
pub fn node_at(value : Snapshot, index : Int) -> Int? {
  @sort.index_at(value.node_sort, index)
}

///|
pub fn node_key_at(value : Snapshot, index : Int) -> String? {
  @sort.key_component_at(value.node_sort, index, 0)
}

///|
pub fn edge_count(value : Snapshot) -> Int {
  @sort.count(value.edge_sort)
}

///|
pub fn edge_at(value : Snapshot, index : Int) -> Int? {
  @sort.index_at(value.edge_sort, index)
}

///|
pub fn edge_key_at(value : Snapshot, index : Int) -> (String, String, String)? {
  guard @sort.key_component_at(value.edge_sort, index, 0) is Some(source) &&
    @sort.key_component_at(value.edge_sort, index, 1) is Some(target) &&
    @sort.key_component_at(value.edge_sort, index, 2) is Some(label) else {
    return None
  }
  Some((source, target, label))
}

///|
pub fn cleanup(value : Snapshot) -> Bool {
  @sort.cleanup(value.node_sort) && @sort.cleanup(value.edge_sort)
}

///|
pub fn cancel(value : Preparation) -> Bool {
  value.node_keys.clear()
  value.edge_keys.clear()
  if value.node_sort is Some(sort) {
    @sort.cleanup(sort) |> ignore
    value.node_sort = None
  }
  if value.edge_sort is Some(sort) {
    @sort.cleanup(sort) |> ignore
    value.edge_sort = None
  }
  value.phase = Finished
  true
}
