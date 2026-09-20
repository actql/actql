///|
pub(all) enum Mode {
  DeclaredNodes
  DerivedEndpoints
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
  OpenPropertyContract
  InvalidIdentity
  InvalidLabel
  InvalidProperties
  WrongMode
  InputRowLimit
  NodeLimit
  EdgeLimit
  ValueLimit
  RetainedValueLimit
  WorkLimit
  WorkspaceLimit
  DuplicateNodeConflict
  DuplicateEdgeConflict
  MissingEndpoint
  Closed
} derive(Eq, Debug)

///|
priv struct Node {
  identity : @value.CheckedValue
  properties : Array[@value.CheckedValue]
}

///|
priv struct Edge {
  source : Int
  target : Int
  label : @value.CheckedValue?
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
fn closed_typed_properties(value : @carrier.Knowledge) -> Bool {
  if @carrier.field_set(value) != @carrier.Closed {
    return false
  }
  for index in 0..<@carrier.field_count(value) {
    if @carrier.field_at(value, index).unwrap().contract is None {
      return false
    }
  }
  true
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
  if !closed_typed_properties(@carrier.graph_node_properties(graph)) ||
    !closed_typed_properties(@carrier.graph_edge_properties(graph)) {
    return Err(OpenPropertyContract)
  }
  if mode == DerivedEndpoints &&
    @carrier.field_count(@carrier.graph_node_properties(graph)) != 0 {
    return Err(InvalidProperties)
  }
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
fn encoded_edge_identity(
  builder : Builder,
  source : @value.CheckedValue,
  target : @value.CheckedValue,
  label : @value.CheckedValue?,
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
    @value.emit_wire_value(source.value, out)
    @value.emit_wire_value(target.value, out)
    match label {
      Some(value) => @value.emit_wire_value(value.value, out)
      None => @encode.null_value(out)
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
fn edge_slots(properties : Int, label : Bool) -> Int {
  // Edge record, identity key, payload key, index entry, endpoints and values.
  6 + properties + (if label { 1 } else { 0 })
}

///|
pub fn append_node(
  builder : Builder,
  identity : @value.CheckedValue,
  properties : Array[@value.CheckedValue],
) -> Result[Unit, Issue] {
  if !builder.open {
    return Err(Closed)
  }
  if builder.mode != DeclaredNodes {
    return fail(builder, WrongMode)
  }
  if !contract_equal(
      builder,
      @carrier.graph_identity(builder.graph),
      identity.contract,
    ) {
    return fail(builder, InvalidIdentity)
  }
  if !values_match(
      builder,
      @carrier.graph_node_properties(builder.graph),
      properties,
    ) {
    return fail(builder, InvalidProperties)
  }
  let (key, key_bytes, key_work) = match
    encoded_values(builder, [identity], 0, 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let (payload, payload_bytes, payload_work) = match
    encoded_values(builder, properties, key_bytes, key_work + 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let bytes = key_bytes + payload_bytes
  if builder.node_keys.get(key) is Some(_) {
    if builder.node_payloads.get(key) == Some(payload) {
      match
        reserve(builder, 1, 0, 0, bytes, 0, key_work + payload_work + 1, 0) {
        Some(issue) => return fail(builder, issue)
        None => {
          builder.input_rows += 1
          builder.value_bytes += bytes
          builder.work += key_work + payload_work + 1
          return Ok(())
        }
      }
    }
    return fail(builder, DuplicateNodeConflict)
  }
  let slots = node_slots(properties.length())
  match
    reserve(builder, 1, 1, 0, bytes, bytes, key_work + payload_work + 1, slots) {
    Some(issue) => return fail(builder, issue)
    None => ()
  }
  let index = builder.nodes.length()
  builder.nodes.push({ identity, properties: properties.copy(), })
  builder.node_keys[key] = index
  builder.node_payloads[key] = payload
  builder.input_rows += 1
  builder.value_bytes += bytes
  builder.retained_value_bytes += bytes
  builder.work += key_work + payload_work + 1
  builder.workspace_slots += slots
  Ok(())
}

///|
fn checked_label(builder : Builder, label : @value.CheckedValue?) -> Bool {
  match (@carrier.graph_label_contract(builder.graph), label) {
    (None, None) => true
    (Some(expected), Some(actual)) =>
      contract_equal(builder, expected, actual.contract)
    _ => false
  }
}

///|
/// Checks one endpoint against the declared node universe without admitting an
/// edge. Explicit Graph construction uses this before committing either
/// endpoint closure. The lookup does not mutate builder accounting.
pub fn contains_declared_node(
  builder : Builder,
  identity : @value.CheckedValue,
) -> Result[Bool, Issue] {
  if !builder.open {
    return Err(Closed)
  }
  if builder.mode != DeclaredNodes {
    return Err(WrongMode)
  }
  if !contract_equal(
      builder,
      @carrier.graph_identity(builder.graph),
      identity.contract,
    ) {
    return Err(InvalidIdentity)
  }
  let (key, _, _) = match encoded_values(builder, [identity], 0, 1) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok(builder.node_keys.get(key) is Some(_))
}

///|
pub fn append_edge(
  builder : Builder,
  source : @value.CheckedValue,
  target : @value.CheckedValue,
  label : @value.CheckedValue?,
  properties : Array[@value.CheckedValue],
) -> Result[Unit, Issue] {
  if !builder.open {
    return Err(Closed)
  }
  let identity_contract = @carrier.graph_identity(builder.graph)
  if !contract_equal(builder, identity_contract, source.contract) ||
    !contract_equal(builder, identity_contract, target.contract) {
    return fail(builder, InvalidIdentity)
  }
  if !checked_label(builder, label) {
    return fail(builder, InvalidLabel)
  }
  if !values_match(
      builder,
      @carrier.graph_edge_properties(builder.graph),
      properties,
    ) {
    return fail(builder, InvalidProperties)
  }
  let (source_key, source_bytes, source_work) = match
    encoded_values(builder, [source], 0, 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let (target_key, target_bytes, target_work) = match
    encoded_values(builder, [target], source_bytes, source_work + 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let (edge_key, edge_key_bytes, edge_key_work) = match
    encoded_edge_identity(
      builder,
      source,
      target,
      label,
      source_bytes + target_bytes,
      source_work + target_work + 1,
    ) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let prior_bytes = source_bytes + target_bytes + edge_key_bytes
  let prior_work = source_work + target_work + edge_key_work
  let (payload, payload_bytes, payload_work) = match
    encoded_values(builder, properties, prior_bytes, prior_work + 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let bytes = prior_bytes + payload_bytes
  let work = source_work + target_work + edge_key_work + payload_work + 1
  if builder.edge_keys.get(edge_key) is Some(_) {
    if builder.edge_payloads.get(edge_key) == Some(payload) {
      match reserve(builder, 1, 0, 0, bytes, 0, work, 0) {
        Some(issue) => return fail(builder, issue)
        None => {
          builder.input_rows += 1
          builder.value_bytes += bytes
          builder.work += work
          return Ok(())
        }
      }
    }
    return fail(builder, DuplicateEdgeConflict)
  }
  let source_index = builder.node_keys.get(source_key)
  let target_index = builder.node_keys.get(target_key)
  if builder.mode == DeclaredNodes &&
    (source_index is None || target_index is None) {
    return fail(builder, MissingEndpoint)
  }
  let mut added_nodes = 0
  if source_index is None {
    added_nodes += 1
  }
  if target_index is None && source_key != target_key {
    added_nodes += 1
  }
  let node_slot_count = added_nodes * node_slots(0)
  let slots = node_slot_count +
    edge_slots(properties.length(), label is Some(_))
  let retained_bytes = edge_key_bytes +
    payload_bytes +
    (if source_index is None { source_bytes + 2 } else { 0 }) +
    (if target_index is None && source_key != target_key {
      target_bytes + 2
    } else {
      0
    })
  match
    reserve(builder, 1, added_nodes, 1, bytes, retained_bytes, work, slots) {
    Some(issue) => return fail(builder, issue)
    None => ()
  }
  let empty : Array[@value.CheckedValue] = []
  let actual_source = match source_index {
    Some(index) => index
    None => {
      let index = builder.nodes.length()
      builder.nodes.push({ identity: source, properties: empty, })
      builder.node_keys[source_key] = index
      builder.node_payloads[source_key] = "[]"
      index
    }
  }
  let actual_target = match target_index {
    Some(index) => index
    None =>
      match builder.node_keys.get(target_key) {
        Some(index) => index
        None => {
          let index = builder.nodes.length()
          builder.nodes.push({ identity: target, properties: empty, })
          builder.node_keys[target_key] = index
          builder.node_payloads[target_key] = "[]"
          index
        }
      }
  }
  let edge_index = builder.edges.length()
  builder.edges.push({
    source: actual_source,
    target: actual_target,
    label,
    properties: properties.copy(),
  })
  builder.edge_keys[edge_key] = edge_index
  builder.edge_payloads[edge_key] = payload
  builder.input_rows += 1
  builder.value_bytes += bytes
  builder.retained_value_bytes += retained_bytes
  builder.work += work
  builder.workspace_slots += slots
  Ok(())
}

///|
pub fn finish(builder : Builder) -> Result[Storage, Issue] {
  if !builder.open || !builder.owns_private {
    return Err(Closed)
  }
  builder.open = false
  builder.owns_private = false
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
/// Resolve an admitted edge identity through the immutable construction
/// index. The lookup preserves the typed source, target, and optional label;
/// it does not compare payload properties or scan the edge array.
pub fn edge_index(
  value : Storage,
  source : @value.CheckedValue,
  target : @value.CheckedValue,
  label : @value.CheckedValue?,
) -> Result[Int?, Issue] {
  let expected = @carrier.graph_identity(value.graph)
  let same_source = @contract.type_equal(
    expected,
    source.contract,
    value.limits.max_contract_work,
  ) catch {
    _ => false
  }
  let same_target = @contract.type_equal(
    expected,
    target.contract,
    value.limits.max_contract_work,
  ) catch {
    _ => false
  }
  if !same_source || !same_target {
    return Err(InvalidIdentity)
  }
  match (@carrier.graph_label_contract(value.graph), label) {
    (None, None) => ()
    (Some(expected), Some(actual)) => {
      let same = @contract.type_equal(
        expected,
        actual.contract,
        value.limits.max_contract_work,
      ) catch {
        _ => false
      }
      if !same {
        return Err(InvalidLabel)
      }
    }
    _ => return Err(InvalidLabel)
  }
  try {
    let out = @encode.writer(
      value.limits.max_value_bytes,
      value.limits.max_value_nodes,
      value.limits.max_value_depth,
    )
    @encode.begin_array(out)
    @value.emit_wire_value(source.value, out)
    @value.emit_wire_value(target.value, out)
    match label {
      Some(actual) => @value.emit_wire_value(actual.value, out)
      None => @encode.null_value(out)
    }
    @encode.end_array(out)
    Ok(value.edge_keys.get(@encode.finish(out)))
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
pub fn edge_label(value : Storage, index : Int) -> @value.CheckedValue?? {
  value.edges.get(index).map(edge => edge.label)
}

///|
pub fn edge_property(
  value : Storage,
  edge : Int,
  property : Int,
) -> @value.CheckedValue? {
  value.edges.get(edge).bind(entry => entry.properties.get(property))
}
