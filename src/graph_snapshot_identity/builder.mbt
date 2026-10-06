///|
/// A distinct snapshot preimage on the same bounded writer and phase owner.
/// The schema retains definition-scoped labels and key/property contracts;
/// records retain original typed key evidence as well as projected identity.
/// Output drains are provisional bytes, never permission to publish.
pub fn prepare(
  contract : @graph.CheckedContract,
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
  try {
    let writer = @encode.buffered_hashing_writer(
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
      limits.max_bytes,
    )
    @encode.begin_array(writer)
    @encode.string_value(writer, "actql-graph-snapshot/0.1")
    @encode.string_value(writer, @graph.cid(contract))
    @graph.emit_checked_graph(contract, writer)
    @encode.begin_array(writer)
    Ok({
      writer,
      limits,
      phase: Nodes,
      previous_node: None,
      previous_edge: None,
      previous_property: None,
      edge_source: None,
    })
  } catch {
    _ => Err(EncodingLimit)
  }
}

///|
fn property_order_key(
  builder : Builder,
  identity : @value.CheckedValue,
) -> Result[String, Issue] {
  try {
    let out = @encode.writer(
      builder.limits.max_bytes,
      builder.limits.value_limits.max_nodes,
      builder.limits.value_limits.max_depth,
    )
    @encode.begin_array(out)
    guard @value.json_payload(identity.value) is Some(payload) else {
      return Err(InvalidContractIdentity)
    }
    @value.emit_wire_value(payload, out)
    @encode.end_array(out)
    Ok(@encode.finish(out))
  } catch {
    _ => Err(EncodingLimit)
  }
}

///|
fn write_property_keys(
  builder : Builder,
  keys : Array[@value.CheckedValue],
) -> Result[Unit, Issue] {
  try {
    @encode.key(builder.writer, "key")
    @encode.begin_array(builder.writer)
    for key in keys {
      @value.emit_checked_wire_value(key, builder.writer)
    }
    @encode.end_array(builder.writer)
    @encode.key(builder.writer, "props")
    @encode.begin_object(builder.writer)
    Ok(())
  } catch {
    _ => Err(EncodingLimit)
  }
}

///|
pub fn begin_node(
  builder : Builder,
  identity : @value.CheckedValue,
  keys : Array[@value.CheckedValue],
) -> Result[Unit, Issue] {
  if builder.phase != Nodes {
    return Err(InvalidPhase)
  }
  let key = match property_order_key(builder, identity) {
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
    guard @value.json_payload(identity.value) is Some(payload) else {
      return Err(InvalidContractIdentity)
    }
    @value.emit_wire_value(payload, builder.writer)
  } catch {
    _ => return Err(EncodingLimit)
  }
  match write_property_keys(builder, keys) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  builder.previous_node = Some(key)
  builder.previous_property = None
  builder.phase = NodeProperties
  Ok(())
}

///|
pub fn begin_edge(
  builder : Builder,
  identity : @value.CheckedValue,
  keys : Array[@value.CheckedValue],
  source : @value.CheckedValue,
  target : @value.CheckedValue,
) -> Result[Unit, Issue] {
  if builder.phase != Edges {
    return Err(InvalidPhase)
  }
  let key = match property_order_key(builder, identity) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if builder.previous_edge is Some(previous) &&
    @canonical.compare_utf16(previous, key) >= 0 {
    return Err(InvalidEdgeOrder)
  }
  try {
    @encode.begin_object(builder.writer)
    @encode.key(builder.writer, "dst")
    guard @value.json_payload(target.value) is Some(target_payload) &&
      @value.json_payload(identity.value) is Some(identity_payload) &&
      @value.json_payload(source.value) is Some(_) else {
      return Err(InvalidContractIdentity)
    }
    @value.emit_wire_value(target_payload, builder.writer)
    @encode.key(builder.writer, "id")
    @value.emit_wire_value(identity_payload, builder.writer)
  } catch {
    _ => return Err(EncodingLimit)
  }
  match write_property_keys(builder, keys) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  builder.previous_edge = Some(key)
  builder.previous_property = None
  builder.edge_source = @value.json_payload(source.value)
  builder.phase = EdgeProperties
  Ok(())
}

///|
pub fn end_edge(builder : Builder) -> Result[Unit, Issue] {
  if builder.phase != EdgeProperties || builder.edge_source is None {
    return Err(InvalidPhase)
  }
  try {
    @encode.end_object(builder.writer)
    @encode.key(builder.writer, "src")
    @value.emit_wire_value(builder.edge_source.unwrap(), builder.writer)
    @encode.end_object(builder.writer)
  } catch {
    _ => return Err(EncodingLimit)
  }
  builder.edge_source = None
  builder.phase = Edges
  Ok(())
}

///|
pub fn drain_output(builder : Builder) -> Result[String, Issue] {
  if builder.phase == Finished {
    return Err(InvalidPhase)
  }
  Ok(@encode.drain_hash_output(builder.writer)) catch {
    _ => Err(EncodingLimit)
  }
}

///|
/// Return the digest and final provisional suffix only after complete emission.
/// The consumer must finish its existing storage/publication owner separately.
pub fn finish(builder : Builder) -> Result[(String, String), Issue] {
  if builder.phase != Edges {
    return Err(InvalidPhase)
  }
  builder.phase = Finished
  try {
    @encode.end_array(builder.writer)
    @encode.end_array(builder.writer)
    let tail = @encode.drain_hash_output(builder.writer)
    Ok(("sha256:" + @encode.finish_hash(builder.writer), tail))
  } catch {
    _ => Err(EncodingLimit)
  }
}
