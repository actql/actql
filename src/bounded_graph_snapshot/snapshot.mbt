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
  InvalidSnapshotBody
  SnapshotContractMismatch
  SnapshotIdentityMismatch
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
  mut builder : @identity.Builder?
  mut output_tail : String?
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
pub fn workspace_slots_view(
  view : @lifecycle.ProducerView,
  graph : @carrier.Graph,
) -> Int? {
  required_workspace(Viewed(view, graph))
}

///|
fn graph(value : @storage.Storage) -> @carrier.Graph? {
  match @storage.carrier(value) {
    @carrier.GraphValue(graph) => Some(graph)
    _ => None
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
  let caps : @contract_graph.Limits = {
    max_bytes: limits.max_identity_bytes,
    max_nodes: limits.max_identity_nodes,
    max_depth: limits.max_identity_depth,
  }
  guard @contract_graph.admit(@carrier.graph_carrier(graph), caps)
    is Ok(expected) else {
    return Err(InvalidGraph)
  }
  if graph_contract_cid != @contract_graph.cid(expected) {
    return Err(SnapshotContractMismatch)
  }
  // Every entry point checks the view's actual admitted definition. An expected
  // contract cannot relabel a foreign producer before its records are read.
  prepare_property_view(view, graph, limits)
}

///|
fn valid_snapshot_limits(limits : Limits) -> Bool {
  limits.max_workspace_slots >= 0 &&
  limits.max_identity_bytes >= 0 &&
  limits.max_identity_nodes >= 0 &&
  limits.max_identity_depth >= 0 &&
  limits.value_limits.max_nodes >= 0 &&
  limits.value_limits.max_depth >= 0 &&
  limits.value_limits.max_text_bytes >= 0
}

///|
fn prepare_source(
  source : SnapshotSource,
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Preparation, Issue] {
  if !valid_snapshot_limits(limits) {
    return Err(InvalidLimits)
  }
  guard source_graph(source) is Some(graph) &&
    required_workspace(source) is Some(required) else {
    return Err(InvalidGraph)
  }
  if required > limits.max_workspace_slots {
    return Err(WorkspaceLimit)
  }
  let identity_limits : @identity.Limits = {
    max_bytes: limits.max_identity_bytes,
    max_nodes: limits.max_identity_nodes,
    max_depth: limits.max_identity_depth,
    value_limits: limits.value_limits,
  }
  let checked = match
    @contract_graph.admit(@carrier.graph_carrier(graph), {
      max_bytes: limits.max_identity_bytes,
      max_nodes: limits.max_identity_nodes,
      max_depth: limits.max_identity_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidGraph)
  }
  if graph_contract_cid != "" &&
    graph_contract_cid != @contract_graph.cid(checked) {
    return Err(SnapshotContractMismatch)
  }
  let builder = match @identity.prepare_property(checked, identity_limits) {
    Ok(value) => value
    Err(issue) => return Err(Identity(issue))
  }
  Ok({
    source,
    builder: Some(builder),
    output_tail: None,
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
  guard value.builder is Some(builder) else { return Err(Terminal) }
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
            @sort.prepare_deferred(value.node_keys, node_count * 2) {
            Ok(sort) => Some(sort)
            Err(issue) => return Err(Sort(issue))
          }
          value.phase = SortNodes
          continue
        }
        let key = match
          source_property_order_key(value.source, value.cursor, edge=false) {
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
        let keys = match
          source_property_keys(value.source, graph, node, edge=false) {
          Ok(keys) => keys
          Err(issue) => return Err(issue)
        }
        match @identity.begin_property_node(builder, identity, keys) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.property = 0
        value.phase = HashNodeProperties
        used += 1
        progress += 1
      }
      HashNodeProperties => {
        guard sorted_node(value) is Some(node) &&
          source_properties(value.source, graph, node, edge=false)
          is Some(properties) else {
          return Err(InvalidGraph)
        }
        let count = @carrier.field_count(properties)
        if value.property >= count {
          value.phase = HashNodeEnd
          continue
        }
        guard sorted_node(value) is Some(node) &&
          @carrier.field_at(properties, value.property) is Some(field) &&
          source_node_property(value.source, node, value.property)
          is Some(property) else {
          return Err(InvalidGraph)
        }
        match
          @identity.append_property(
            builder,
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
        match @identity.end_node(builder) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.cursor += 1
        value.phase = HashNodeBegin
        used += 1
        progress += 1
      }
      EndNodes => {
        match @identity.end_nodes(builder) {
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
            @sort.prepare_deferred(value.edge_keys, edge_count * 2) {
            Ok(sort) => Some(sort)
            Err(issue) => return Err(Sort(issue))
          }
          value.phase = SortEdges
          continue
        }
        let key = match
          source_property_order_key(value.source, value.cursor, edge=true) {
          Ok(key) => key
          Err(issue) => return Err(issue)
        }
        value.edge_keys.push([key])
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
          source_node_identity(value.source, target) is Some(target_id) else {
          return Err(InvalidGraph)
        }
        guard source_property_edge_identity(value.source, edge)
          is Some(identity) else {
          return Err(InvalidGraph)
        }
        let keys = match
          source_property_keys(value.source, graph, edge, edge=true) {
          Ok(keys) => keys
          Err(issue) => return Err(issue)
        }
        match
          @identity.begin_property_edge(
            builder, identity, keys, source_id, target_id,
          ) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.property = 0
        value.phase = HashEdgeProperties
        used += 1
        progress += 1
      }
      HashEdgeProperties => {
        guard sorted_edge(value) is Some(edge) &&
          source_properties(value.source, graph, edge, edge=true)
          is Some(properties) else {
          return Err(InvalidGraph)
        }
        let count = @carrier.field_count(properties)
        if value.property >= count {
          value.phase = HashEdgeEnd
          continue
        }
        guard sorted_edge(value) is Some(edge) &&
          @carrier.field_at(properties, value.property) is Some(field) &&
          source_edge_property(value.source, edge, value.property)
          is Some(property) else {
          return Err(InvalidGraph)
        }
        match
          @identity.append_property(
            builder,
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
        match @identity.end_property_edge(builder) {
          Ok(_) => ()
          Err(issue) => return Err(Identity(issue))
        }
        value.cursor += 1
        value.phase = HashEdgeBegin
        used += 1
        progress += 1
      }
      Finish => {
        let (cid, tail) = match @identity.finish_property(builder) {
          Ok(cid) => cid
          Err(issue) => return Err(Identity(issue))
        }
        guard value.node_sort is Some(node_sort) &&
          value.edge_sort is Some(edge_sort) else {
          return Err(InvalidGraph)
        }
        value.phase = Finished
        value.builder = None
        value.output_tail = Some(tail)
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
pub fn cleanup(value : Snapshot) -> Bool {
  @sort.cleanup(value.node_sort) && @sort.cleanup(value.edge_sort)
}

///|
pub fn cancel(value : Preparation) -> Bool {
  value.builder = None
  value.output_tail = None
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
