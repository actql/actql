///|
priv suberror PropertySnapshotStop {
  PropertySnapshotStop(Issue)
}

///|
fn snapshot_charge(
  builder : Builder,
  work : Int,
) -> Unit raise PropertySnapshotStop {
  if work < 0 || work > builder.limits.max_work - builder.work {
    raise PropertySnapshotStop(WorkLimit)
  }
  builder.work += work
}

///|
fn snapshot_value(
  builder : Builder,
  contract : @contract.Contract,
  cursor : @decode.Cursor,
  issuer : @value.ReferenceIssuer?,
) -> @value.CheckedValue raise PropertySnapshotStop {
  let remaining = builder.limits.max_work - builder.work
  let limits : @value.Limits = {
    max_nodes: Int::min(builder.limits.max_value_nodes, remaining),
    max_depth: builder.limits.max_value_depth,
    max_text_bytes: builder.limits.max_value_bytes,
  }
  let admitted = match issuer {
    None => @value.admit_usage(contract, cursor, limits)
    Some(issuer) =>
      @value.admit_host_usage(issuer, contract, cursor, limits, {
        max_bytes: builder.limits.max_value_bytes,
        max_nodes: limits.max_nodes,
        max_depth: limits.max_depth,
        max_text_units: builder.limits.max_value_bytes,
      })
  }
  match admitted {
    Ok((value, nodes, _)) => {
      snapshot_charge(builder, nodes)
      value
    }
    Err(_) =>
      raise PropertySnapshotStop(
        if remaining < builder.limits.max_value_nodes {
          WorkLimit
        } else {
          InvalidIdentity
        },
      )
  }
}

///|
fn snapshot_token(
  builder : Builder,
  identity : @value.CheckedValue,
) -> String raise PropertySnapshotStop {
  match encoded_values(builder, [identity], 0, 0) {
    Ok((token, _, work)) => {
      snapshot_charge(builder, work)
      token
    }
    Err(issue) => raise PropertySnapshotStop(issue)
  }
}

///|
fn snapshot_definition(
  builder : Builder,
  identity : @decode.Cursor,
  edge~ : Bool,
) -> (Int, @carrier.PropertyNodeDefinition) raise PropertySnapshotStop {
  let profile = @carrier.graph_property_definition(builder.graph)
  guard @decode.object_length(identity) == Some(4) &&
    @decode.closed_object(identity, ["definition", "domain", "key", "key_types"])
    is Ok(fields) &&
    @decode.lookup(fields, "definition") is Some(name_cursor) &&
    @decode.text(name_cursor) is Ok(name) else {
    raise PropertySnapshotStop(InvalidIdentity)
  }
  let count = if edge {
    @carrier.property_graph_edge_count(profile)
  } else {
    @carrier.property_graph_node_count(profile)
  }
  for index in 0..<count {
    snapshot_charge(builder, 1)
    let definition = if edge {
      @carrier.property_edge_element(
        @carrier.property_graph_edge_at(profile, index).unwrap(),
      )
    } else {
      @carrier.property_graph_node_at(profile, index).unwrap()
    }
    if @carrier.property_definition_name(definition) == name {
      return (index, definition)
    }
  }
  raise PropertySnapshotStop(InvalidIdentity)
}

///|
fn snapshot_keys(
  builder : Builder,
  definition : @carrier.PropertyNodeDefinition,
  keys : @decode.Cursor,
  issuer : @value.ReferenceIssuer?,
) -> Array[@value.CheckedValue] raise PropertySnapshotStop {
  let contracts = @carrier.property_definition_keys(definition)
  if @decode.array_length(keys) != Some(contracts.length()) {
    raise PropertySnapshotStop(InvalidIdentity)
  }
  contracts.mapi((index, contract) => {
    snapshot_value(
      builder,
      contract,
      @decode.element_at(keys, index).unwrap(),
      issuer,
    )
  })
}

///|
fn snapshot_properties(
  builder : Builder,
  definition : @carrier.PropertyNodeDefinition,
  properties : @decode.Cursor,
  issuer : @value.ReferenceIssuer?,
) -> Array[@value.CheckedValue] raise PropertySnapshotStop {
  let schema = @carrier.property_definition_properties(definition)
  let count = @carrier.field_count(schema)
  if @decode.object_length(properties) != Some(count) {
    raise PropertySnapshotStop(InvalidProperties)
  }
  let values = []
  for index in 0..<count {
    let field = @carrier.field_at(schema, index).unwrap()
    let name = @schema.reference_name(field.name)
    guard @decode.field_at(properties, index) is Some((received_name, value)) &&
      name == received_name else {
      raise PropertySnapshotStop(InvalidProperties)
    }
    values.push(snapshot_value(builder, field.contract.unwrap(), value, issuer))
  }
  values
}

///|
fn snapshot_object(
  input : @decode.Cursor,
  names : Array[String],
) -> @decode.ObjectView raise PropertySnapshotStop {
  guard @decode.object_length(input) == Some(names.length()) &&
    @decode.closed_object(input, names) is Ok(object) else {
    raise PropertySnapshotStop(InvalidIdentity)
  }
  object
}

///|
/// Snapshot admission is strict: no NULL-key or missing-endpoint exclusion is
/// permitted, and every identity must equal the existing builder's projection.
pub fn append_property_snapshot_node(
  builder : Builder,
  input : @decode.Cursor,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[Unit, Issue] {
  if !builder.open {
    return Err(Closed)
  }
  try {
    let record = snapshot_object(input, ["id", "key", "props"])
    let identity_at = @decode.lookup(record, "id").unwrap()
    let (index, definition) = snapshot_definition(
      builder,
      identity_at,
      edge=false,
    )
    let identity = snapshot_value(
      builder,
      @carrier.graph_identity(builder.graph),
      identity_at,
      None,
    )
    let token = snapshot_token(builder, identity)
    if builder.nodes.last() is Some(previous) &&
      previous.identity_order_key is Some(previous) &&
      @canonical.compare_utf16(previous, token) >= 0 {
      raise PropertySnapshotStop(InvalidIdentity)
    }
    let keys = snapshot_keys(
      builder,
      definition,
      @decode.lookup(record, "key").unwrap(),
      reference_issuer,
    )
    let properties = snapshot_properties(
      builder,
      definition,
      @decode.lookup(record, "props").unwrap(),
      reference_issuer,
    )
    let before = builder.nodes.length()
    match append_property_node(builder, index, keys, properties) {
      Ok(_) => ()
      Err(issue) => raise PropertySnapshotStop(issue)
    }
    if builder.nodes.length() != before + 1 ||
      builder.nodes[before].identity_order_key != Some(token) {
      raise PropertySnapshotStop(InvalidIdentity)
    }
    Ok(())
  } catch {
    PropertySnapshotStop(issue) => fail(builder, issue)
  }
}

///|
pub fn append_property_snapshot_edge(
  builder : Builder,
  input : @decode.Cursor,
  reference_issuer? : @value.ReferenceIssuer? = None,
) -> Result[Unit, Issue] {
  if !builder.open {
    return Err(Closed)
  }
  try {
    let record = snapshot_object(input, ["dst", "id", "key", "props", "src"])
    let identity_at = @decode.lookup(record, "id").unwrap()
    let (index, definition) = snapshot_definition(
      builder,
      identity_at,
      edge=true,
    )
    let identity = snapshot_value(
      builder,
      @carrier.graph_identity(builder.graph),
      identity_at,
      None,
    )
    let token = snapshot_token(builder, identity)
    if builder.edges.last() is Some(previous) &&
      previous.identity_order_key is Some(previous) &&
      @canonical.compare_utf16(previous, token) >= 0 {
      raise PropertySnapshotStop(InvalidIdentity)
    }
    let keys = snapshot_keys(
      builder,
      definition,
      @decode.lookup(record, "key").unwrap(),
      reference_issuer,
    )
    let properties = snapshot_properties(
      builder,
      definition,
      @decode.lookup(record, "props").unwrap(),
      reference_issuer,
    )
    let source = snapshot_value(
      builder,
      @carrier.graph_identity(builder.graph),
      @decode.lookup(record, "src").unwrap(),
      None,
    )
    let target = snapshot_value(
      builder,
      @carrier.graph_identity(builder.graph),
      @decode.lookup(record, "dst").unwrap(),
      None,
    )
    guard builder.node_keys.get(snapshot_token(builder, source))
      is Some(source_index) &&
      builder.node_keys.get(snapshot_token(builder, target))
      is Some(target_index) &&
      builder.nodes[source_index].typed_key is Some(source_keys) &&
      builder.nodes[target_index].typed_key is Some(target_keys) else {
      raise PropertySnapshotStop(MissingEndpoint)
    }
    // Reuse the admitted endpoint key evidence; identity JSON is not authority.
    let before = builder.edges.length()
    match
      append_property_edge(
        builder, index, keys, source_keys, target_keys, properties,
      ) {
      Ok(_) => ()
      Err(issue) => raise PropertySnapshotStop(issue)
    }
    if builder.edges.length() != before + 1 ||
      builder.edges[before].identity_order_key != Some(token) ||
      builder.edges[before].source != source_index ||
      builder.edges[before].target != target_index {
      raise PropertySnapshotStop(InvalidIdentity)
    }
    Ok(())
  } catch {
    PropertySnapshotStop(issue) => fail(builder, issue)
  }
}
