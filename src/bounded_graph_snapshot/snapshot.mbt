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
  ValueOrder(@value.CompleteOrderIssue)
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
struct Preparation {
  storage : @storage.Storage
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
fn required_workspace(storage : @storage.Storage) -> Int? {
  guard checked_multiply(@storage.node_count(storage), 5) is Some(nodes) &&
    checked_multiply(@storage.edge_count(storage), 7) is Some(edges) else {
    return None
  }
  checked_add(nodes, edges)
}

///|
fn graph(value : @storage.Storage) -> @carrier.Graph? {
  match @storage.carrier(value) {
    @carrier.GraphValue(graph) => Some(graph)
    _ => None
  }
}

///|
fn order_key(
  value : @value.CheckedValue,
  limits : @value.Limits,
) -> Result[String, Issue] {
  @value.complete_order_key(value, limits).map_err(issue => ValueOrder(issue))
}

///|
pub fn prepare(
  storage : @storage.Storage,
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
  guard graph(storage) is Some(_) &&
    required_workspace(storage) is Some(required) else {
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
    storage,
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
  guard graph(value.storage) is Some(graph) else { return Err(InvalidGraph) }
  let mut used = 0
  let mut progress = 0
  while used < quantum {
    match value.phase {
      BuildNodeKeys => {
        if value.cursor >= @storage.node_count(value.storage) {
          value.node_sort = match
            @sort.prepare(
              value.node_keys,
              @storage.node_count(value.storage) * 2,
            ) {
            Ok(sort) => Some(sort)
            Err(issue) => return Err(Sort(issue))
          }
          value.phase = SortNodes
          continue
        }
        guard @storage.node_identity(value.storage, value.cursor)
          is Some(identity) else {
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
        if value.cursor >= @storage.node_count(value.storage) {
          value.phase = EndNodes
          continue
        }
        guard sorted_node(value) is Some(node) &&
          @storage.node_identity(value.storage, node) is Some(identity) else {
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
          @storage.node_property(value.storage, node, value.property)
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
        if value.cursor >= @storage.edge_count(value.storage) {
          value.edge_sort = match
            @sort.prepare(
              value.edge_keys,
              @storage.edge_count(value.storage) * 2,
            ) {
            Ok(sort) => Some(sort)
            Err(issue) => return Err(Sort(issue))
          }
          value.phase = SortEdges
          continue
        }
        guard @storage.edge_endpoints(value.storage, value.cursor)
          is Some((source, target)) &&
          @storage.node_identity(value.storage, source) is Some(source_id) &&
          @storage.node_identity(value.storage, target) is Some(target_id) &&
          @storage.edge_label(value.storage, value.cursor) is Some(label) else {
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
        let label_key = match label {
          Some(label) =>
            match order_key(label, value.limits.value_limits) {
              Ok(key) => key
              Err(issue) => return Err(issue)
            }
          None => "[\"null\"]"
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
        if value.cursor >= @storage.edge_count(value.storage) {
          value.phase = Finish
          continue
        }
        guard sorted_edge(value) is Some(edge) &&
          @storage.edge_endpoints(value.storage, edge) is Some((source, target)) &&
          @storage.node_identity(value.storage, source) is Some(source_id) &&
          @storage.node_identity(value.storage, target) is Some(target_id) &&
          @storage.edge_label(value.storage, edge) is Some(label) else {
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
          @storage.edge_property(value.storage, edge, value.property)
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
