///|
pub(all) struct Limits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  value_limits : @value.Limits
}

///|
pub(all) enum Issue {
  InvalidLimits
  InvalidContractIdentity
  InvalidPhase
  InvalidNodeOrder
  InvalidEdgeOrder
  InvalidPropertyOrder
  EncodingLimit
  ValueOrder(@value.CompleteOrderIssue)
} derive(Eq, Debug)

///|
priv enum Phase {
  Nodes
  NodeProperties
  Edges
  EdgeProperties
  Finished
} derive(Eq)

///|
struct Builder {
  writer : @encode.Writer
  limits : Limits
  mut phase : Phase
  mut previous_node : String?
  mut previous_edge : (String, String, String)?
  mut previous_property : String?
  mut edge_source : @value.Value?
  mut edge_label : @value.Value?
}

///|
fn valid_hex(value : String) -> Bool {
  if value.length() != 71 || !value.has_prefix("sha256:") {
    return false
  }
  for index in 7..<value.length() {
    let unit = value[index].to_int()
    if !((unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)) {
      return false
    }
  }
  true
}

///|
fn order_key(
  value : @value.CheckedValue,
  limits : @value.Limits,
) -> Result[String, Issue] {
  @value.complete_order_key(value, limits).map_err(issue => ValueOrder(issue))
}

///|
fn compare_edge_key(
  left : (String, String, String),
  right : (String, String, String),
) -> Int {
  let source = @canonical.compare_utf16(left.0, right.0)
  if source != 0 {
    return source
  }
  let target = @canonical.compare_utf16(left.1, right.1)
  if target != 0 {
    return target
  }
  @canonical.compare_utf16(left.2, right.2)
}

///|
fn write_value(builder : Builder, value : @value.Value) -> Result[Unit, Issue] {
  try {
    @value.emit_wire_value(value, builder.writer)
    Ok(())
  } catch {
    _ => Err(EncodingLimit)
  }
}

///|
pub fn prepare(
  graph_contract_cid : String,
  limits : Limits,
) -> Result[Builder, Issue] {
  if limits.max_bytes < 0 ||
    limits.max_nodes < 0 ||
    limits.max_depth < 0 ||
    limits.value_limits.max_nodes < 0 ||
    limits.value_limits.max_depth < 0 ||
    limits.value_limits.max_text_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !valid_hex(graph_contract_cid) {
    return Err(InvalidContractIdentity)
  }
  try {
    let writer = @encode.hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    )
    @encode.begin_array(writer)
    @encode.string_value(writer, "actql-graph-snapshot/0.1")
    @encode.string_value(writer, graph_contract_cid)
    @encode.begin_array(writer)
    Ok({
      writer,
      limits,
      phase: Nodes,
      previous_node: None,
      previous_edge: None,
      previous_property: None,
      edge_source: None,
      edge_label: None,
    })
  } catch {
    _ => Err(EncodingLimit)
  }
}

///|
pub fn begin_node(
  builder : Builder,
  identity : @value.CheckedValue,
) -> Result[Unit, Issue] {
  if builder.phase != Nodes {
    return Err(InvalidPhase)
  }
  let key = match order_key(identity, builder.limits.value_limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if builder.previous_node is Some(previous) &&
    @canonical.compare_utf16(previous, key) >= 0 {
    return Err(InvalidNodeOrder)
  }
  try {
    @encode.begin_object(builder.writer)
    @encode.key(builder.writer, "id")
    match write_value(builder, identity.value) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @encode.key(builder.writer, "props")
    @encode.begin_object(builder.writer)
  } catch {
    _ => return Err(EncodingLimit)
  }
  builder.previous_node = Some(key)
  builder.previous_property = None
  builder.phase = NodeProperties
  Ok(())
}

///|
pub fn append_property(
  builder : Builder,
  name : String,
  value : @value.CheckedValue,
) -> Result[Unit, Issue] {
  if builder.phase != NodeProperties && builder.phase != EdgeProperties {
    return Err(InvalidPhase)
  }
  if builder.previous_property is Some(previous) &&
    @canonical.compare_utf16(previous, name) >= 0 {
    return Err(InvalidPropertyOrder)
  }
  try {
    @encode.key(builder.writer, name)
    match write_value(builder, value.value) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
  } catch {
    _ => return Err(EncodingLimit)
  }
  builder.previous_property = Some(name)
  Ok(())
}

///|
pub fn end_node(builder : Builder) -> Result[Unit, Issue] {
  if builder.phase != NodeProperties {
    return Err(InvalidPhase)
  }
  try {
    @encode.end_object(builder.writer)
    @encode.end_object(builder.writer)
  } catch {
    _ => return Err(EncodingLimit)
  }
  builder.phase = Nodes
  Ok(())
}

///|
pub fn end_nodes(builder : Builder) -> Result[Unit, Issue] {
  if builder.phase != Nodes {
    return Err(InvalidPhase)
  }
  try {
    @encode.end_array(builder.writer)
    @encode.begin_array(builder.writer)
  } catch {
    _ => return Err(EncodingLimit)
  }
  builder.phase = Edges
  Ok(())
}

///|
pub fn begin_edge(
  builder : Builder,
  source : @value.CheckedValue,
  target : @value.CheckedValue,
  label : @value.CheckedValue?,
) -> Result[Unit, Issue] {
  if builder.phase != Edges {
    return Err(InvalidPhase)
  }
  let source_key = match order_key(source, builder.limits.value_limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let target_key = match order_key(target, builder.limits.value_limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let label_key = match label {
    Some(value) =>
      match order_key(value, builder.limits.value_limits) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    None => "[\"null\"]"
  }
  let key = (source_key, target_key, label_key)
  if builder.previous_edge is Some(previous) &&
    compare_edge_key(previous, key) >= 0 {
    return Err(InvalidEdgeOrder)
  }
  try {
    @encode.begin_object(builder.writer)
    @encode.key(builder.writer, "dst")
    match write_value(builder, target.value) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @encode.key(builder.writer, "props")
    @encode.begin_object(builder.writer)
  } catch {
    _ => return Err(EncodingLimit)
  }
  builder.previous_edge = Some(key)
  builder.previous_property = None
  builder.edge_source = Some(source.value)
  builder.edge_label = match label {
    Some(value) => Some(value.value)
    None => Some(@value.null_value())
  }
  builder.phase = EdgeProperties
  Ok(())
}

///|
pub fn end_edge(builder : Builder) -> Result[Unit, Issue] {
  if builder.phase != EdgeProperties ||
    builder.edge_source is None ||
    builder.edge_label is None {
    return Err(InvalidPhase)
  }
  try {
    @encode.end_object(builder.writer)
    @encode.key(builder.writer, "rel")
    match write_value(builder, builder.edge_label.unwrap()) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @encode.key(builder.writer, "src")
    match write_value(builder, builder.edge_source.unwrap()) {
      Ok(_) => ()
      Err(issue) => return Err(issue)
    }
    @encode.end_object(builder.writer)
  } catch {
    _ => return Err(EncodingLimit)
  }
  builder.edge_source = None
  builder.edge_label = None
  builder.phase = Edges
  Ok(())
}

///|
pub fn finish(builder : Builder) -> Result[String, Issue] {
  if builder.phase != Edges {
    return Err(InvalidPhase)
  }
  builder.phase = Finished
  try {
    @encode.end_array(builder.writer)
    @encode.end_array(builder.writer)
    Ok("sha256:" + @encode.finish_hash(builder.writer))
  } catch {
    _ => Err(EncodingLimit)
  }
}
