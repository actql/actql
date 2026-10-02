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
  KeyOrder(@value.KeyOrderIssue)
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
  mut previous_edge : String?
  mut previous_property : String?
  mut edge_source : @value.Value?
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
