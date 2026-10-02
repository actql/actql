///|
pub(all) enum Mode {
  DeclaredNodes
} derive(Eq, Debug)

///|
pub(all) struct Limits {
  max_input_rows : Int
  max_nodes : Int
  max_edges : Int
  max_value_bytes : Int
  max_total_value_bytes : Int
  max_retained_value_bytes : Int
  max_value_nodes : Int
  max_value_depth : Int
  max_contract_work : Int
  max_work : Int
  max_workspace_slots : Int
} derive(Eq, Debug)

///|
pub(all) enum Issue {
  InvalidLimits
  WrongCarrier
  InvalidIdentity
  InvalidProperties
  InputRowLimit
  NodeLimit
  EdgeLimit
  ValueLimit
  RetainedValueLimit
  WorkLimit
  WorkspaceLimit
  DuplicateNodeKey
  DuplicateEdgeKey
  MissingEndpoint
  Closed
} derive(Eq, Debug)

///|
priv struct Node {
  property_definition : Int
  identity_order_key : String
  typed_key : Array[@value.CheckedValue]
  identity : @value.CheckedValue
  properties : Array[@value.CheckedValue]
}

///|
priv struct Edge {
  property_definition : Int
  identity_order_key : String
  identity : @value.CheckedValue
  typed_key : Array[@value.CheckedValue]
  source : Int
  target : Int
  properties : Array[@value.CheckedValue]
}

///|
/// Private mutable construction state. No partial value escapes on failure.
struct Builder {
  graph : @carrier.Graph
  mode : Mode
  limits : Limits
  nodes : Array[Node]
  edges : Array[Edge]
  node_keys : Map[String, Int]
  node_payloads : Map[String, String]
  edge_keys : Map[String, Int]
  edge_payloads : Map[String, String]
  excluded_edge_keys : Array[(String, Int)]
  mut input_rows : Int
  mut value_bytes : Int
  mut retained_value_bytes : Int
  mut work : Int
  mut workspace_slots : Int
  mut open : Bool
  mut owns_private : Bool
}

///|
/// Immutable, typed graph material. Arrays are owned by the consumed builder
/// and are never exposed for mutation.
struct Storage {
  graph : @carrier.Graph
  mode : Mode
  limits : Limits
  nodes : Array[Node]
  edges : Array[Edge]
  node_keys : Map[String, Int]
  edge_keys : Map[String, Int]
  input_rows : Int
  value_bytes : Int
  retained_value_bytes : Int
  work : Int
  workspace_slots : Int
}

///|
fn valid_limits(limits : Limits) -> Bool {
  limits.max_input_rows >= 0 &&
  limits.max_nodes >= 0 &&
  limits.max_edges >= 0 &&
  limits.max_value_bytes >= 0 &&
  limits.max_total_value_bytes >= 0 &&
  limits.max_retained_value_bytes >= 0 &&
  limits.max_value_nodes >= 0 &&
  limits.max_value_depth >= 0 &&
  limits.max_contract_work >= 0 &&
  limits.max_work >= 0 &&
  limits.max_workspace_slots >= 0
}

///|
pub fn prepare(
  contract : @carrier.Carrier,
  mode : Mode,
  limits : Limits,
) -> Result[Builder, Issue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  guard contract is @carrier.GraphValue(graph) else { return Err(WrongCarrier) }
  Ok({
    graph,
    mode,
    limits,
    nodes: [],
    edges: [],
    node_keys: Map([]),
    node_payloads: Map([]),
    edge_keys: Map([]),
    edge_payloads: Map([]),
    excluded_edge_keys: [],
    input_rows: 0,
    value_bytes: 0,
    retained_value_bytes: 0,
    work: 0,
    workspace_slots: 0,
    open: true,
    owns_private: true,
  })
}

///|
fn fail(builder : Builder, issue : Issue) -> Result[Unit, Issue] {
  builder.open = false
  Err(issue)
}

///|
fn contract_equal(
  builder : Builder,
  left : @contract.Contract,
  right : @contract.Contract,
) -> Bool {
  @contract.type_equal(left, right, builder.limits.max_contract_work) catch {
    _ => false
  }
}

///|
fn values_match(
  builder : Builder,
  knowledge : @carrier.Knowledge,
  values : Array[@value.CheckedValue],
) -> Bool {
  if values.length() != @carrier.field_count(knowledge) {
    return false
  }
  for index, value in values {
    guard @carrier.field_at(knowledge, index).unwrap().contract
      is Some(expected) else {
      return false
    }
    if !contract_equal(builder, expected, value.contract) {
      return false
    }
  }
  true
}

///|
fn encoded_values(
  builder : Builder,
  values : Array[@value.CheckedValue],
  pending_bytes : Int,
  pending_work : Int,
) -> Result[(String, Int, Int), Issue] {
  if pending_work > builder.limits.max_work - builder.work {
    return Err(WorkLimit)
  }
  let remaining_work = builder.limits.max_work - builder.work - pending_work
  let node_limit = Int::min(builder.limits.max_value_nodes, remaining_work)
  if node_limit < 1 {
    return Err(WorkLimit)
  }
  if pending_bytes > builder.limits.max_total_value_bytes - builder.value_bytes {
    return Err(ValueLimit)
  }
  let remaining = builder.limits.max_total_value_bytes -
    builder.value_bytes -
    pending_bytes
  let cap = Int::min(builder.limits.max_value_bytes, remaining)
  if cap < 0 {
    return Err(ValueLimit)
  }
  try {
    let out = @encode.writer(cap, node_limit, builder.limits.max_value_depth)
    @encode.begin_array(out)
    for value in values {
      @value.emit_wire_value(value.value, out)
    }
    @encode.end_array(out)
    let (text, bytes, nodes, _) = @encode.finish_text_usage(out)
    Ok((text, bytes, nodes))
  } catch {
    _ =>
      if node_limit < builder.limits.max_value_nodes {
        Err(WorkLimit)
      } else {
        Err(ValueLimit)
      }
  }
}

///|

///|
fn reserve(
  builder : Builder,
  rows : Int,
  nodes : Int,
  edges : Int,
  bytes : Int,
  retained_bytes : Int,
  work : Int,
  slots : Int,
) -> Issue? {
  if rows > builder.limits.max_input_rows - builder.input_rows {
    return Some(InputRowLimit)
  }
  if nodes > builder.limits.max_nodes - builder.nodes.length() {
    return Some(NodeLimit)
  }
  if edges > builder.limits.max_edges - builder.edges.length() {
    return Some(EdgeLimit)
  }
  if bytes > builder.limits.max_total_value_bytes - builder.value_bytes {
    return Some(ValueLimit)
  }
  if retained_bytes >
    builder.limits.max_retained_value_bytes - builder.retained_value_bytes {
    return Some(RetainedValueLimit)
  }
  if work > builder.limits.max_work - builder.work {
    return Some(WorkLimit)
  }
  if slots > builder.limits.max_workspace_slots - builder.workspace_slots {
    return Some(WorkspaceLimit)
  }
  None
}

///|
fn node_slots(properties : Int) -> Int {
  // Node record, identity key, payload key, index entry, and retained values.
  4 + properties
}

///|
fn edge_slots(properties : Int) -> Int {
  // Edge record, identity key, payload key, index entry, endpoints and values.
  6 + properties
}

///|
fn append_node_record(
  builder : Builder,
  identity : @value.CheckedValue,
  properties : Array[@value.CheckedValue],
  property_definition : Int,
  typed_key : Array[@value.CheckedValue],
  initial_work : Int,
) -> Result[Unit, Issue] {
  let (key, key_bytes, key_work) = match
    encoded_values(builder, [identity], 0, 1 + initial_work) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let (payload, payload_bytes, payload_work) = match
    encoded_values(builder, properties, key_bytes, key_work + 1 + initial_work) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let bytes = key_bytes + payload_bytes
  if builder.node_keys.get(key) is Some(_) {
    return fail(builder, DuplicateNodeKey)
  }
  let slots = node_slots(properties.length()) + typed_key.length() + 1
  let work = key_work + payload_work + 1 + initial_work
  match reserve(builder, 1, 1, 0, bytes, bytes, work, slots) {
    Some(issue) => return fail(builder, issue)
    None => ()
  }
  let index = builder.nodes.length()
  builder.nodes.push({
    identity,
    properties: properties.copy(),
    property_definition,
    identity_order_key: key,
    typed_key: typed_key.copy(),
  })
  builder.node_keys[key] = index
  builder.node_payloads[key] = payload
  builder.input_rows += 1
  builder.value_bytes += bytes
  builder.retained_value_bytes += bytes
  builder.work += work
  builder.workspace_slots += slots
  Ok(())
}

///|

///|
pub fn finish(builder : Builder) -> Result[Storage, Issue] {
  if !builder.open || !builder.owns_private {
    return Err(Closed)
  }
  builder.open = false
  builder.owns_private = false
  for (key, bytes) in builder.excluded_edge_keys {
    builder.edge_keys.remove(key) |> ignore
    builder.retained_value_bytes -= bytes
    builder.workspace_slots -= 3
  }
  builder.excluded_edge_keys.clear()
  Ok({
    graph: builder.graph,
    mode: builder.mode,
    limits: builder.limits,
    nodes: builder.nodes,
    edges: builder.edges,
    node_keys: builder.node_keys,
    edge_keys: builder.edge_keys,
    input_rows: builder.input_rows,
    value_bytes: builder.value_bytes,
    retained_value_bytes: builder.retained_value_bytes,
    work: builder.work,
    workspace_slots: builder.workspace_slots,
  })
}

///|
pub fn cancel(builder : Builder) -> Bool {
  if !builder.owns_private {
    return false
  }
  builder.open = false
  builder.owns_private = false
  builder.nodes.clear()
  builder.edges.clear()
  builder.node_keys.clear()
  builder.node_payloads.clear()
  builder.edge_keys.clear()
  builder.edge_payloads.clear()
  builder.excluded_edge_keys.clear()
  builder.retained_value_bytes = 0
  builder.workspace_slots = 0
  true
}

///|
pub fn builder_node_count(builder : Builder) -> Int {
  builder.nodes.length()
}

///|
pub fn builder_edge_count(builder : Builder) -> Int {
  builder.edges.length()
}

///|
pub fn builder_retained_value_bytes(builder : Builder) -> Int {
  builder.retained_value_bytes
}

///|
pub fn builder_workspace_slots(builder : Builder) -> Int {
  builder.workspace_slots
}

///|
pub fn builder_measured_input_value_bytes(builder : Builder) -> Int {
  builder.value_bytes
}

///|
pub fn builder_construction_work(builder : Builder) -> Int {
  builder.work
}

///|
pub fn mode(value : Storage) -> Mode {
  value.mode
}

///|
pub fn carrier(value : Storage) -> @carrier.Carrier {
  @carrier.graph_carrier(value.graph)
}

///|
pub fn node_count(value : Storage) -> Int {
  value.nodes.length()
}

///|
pub fn edge_count(value : Storage) -> Int {
  value.edges.length()
}

///|
pub fn input_row_count(value : Storage) -> Int {
  value.input_rows
}

///|
pub fn retained_value_bytes(value : Storage) -> Int {
  value.retained_value_bytes
}

///|
pub fn measured_input_value_bytes(value : Storage) -> Int {
  value.value_bytes
}

///|
pub fn construction_work(value : Storage) -> Int {
  value.work
}

///|
pub fn retained_workspace_slots(value : Storage) -> Int {
  value.workspace_slots
}

///|
/// Dispose private material whose completed generation was never handed off.
pub fn discard(value : Storage) -> Unit {
  value.nodes.clear()
  value.edges.clear()
  value.node_keys.clear()
  value.edge_keys.clear()
}

///|
/// Resolve an admitted identity through the immutable construction index.
/// The index and its canonical keys were admitted while the graph was built;
/// lookup does not construct a second index or scan all nodes.
pub fn node_index(
  value : Storage,
  identity : @value.CheckedValue,
) -> Result[Int?, Issue] {
  match property_lookup_scope(value, identity, edge=false) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let expected = @carrier.graph_identity(value.graph)
  let same = @contract.type_equal(
    expected,
    identity.contract,
    value.limits.max_contract_work,
  ) catch {
    _ => false
  }
  if !same {
    return Err(InvalidIdentity)
  }
  try {
    let out = @encode.writer(
      value.limits.max_value_bytes,
      value.limits.max_value_nodes,
      value.limits.max_value_depth,
    )
    @encode.begin_array(out)
    @value.emit_wire_value(identity.value, out)
    @encode.end_array(out)
    Ok(value.node_keys.get(@encode.finish(out)))
  } catch {
    _ => Err(ValueLimit)
  }
}

///|
pub fn node_identity(value : Storage, index : Int) -> @value.CheckedValue? {
  value.nodes.get(index).map(node => node.identity)
}

///|
pub fn node_property(
  value : Storage,
  node : Int,
  property : Int,
) -> @value.CheckedValue? {
  value.nodes.get(node).bind(entry => entry.properties.get(property))
}

///|
pub fn edge_endpoints(value : Storage, index : Int) -> (Int, Int)? {
  value.edges.get(index).map(edge => (edge.source, edge.target))
}

///|
pub fn edge_property(
  value : Storage,
  edge : Int,
  property : Int,
) -> @value.CheckedValue? {
  value.edges.get(edge).bind(entry => entry.properties.get(property))
}
