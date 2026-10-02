///|
/// Only the definition and its admitted key contribute to element identity.
/// Properties, labels and edge endpoints remain snapshot content.
fn emit_property_key_type(
  contract : @contract.Contract,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_object(out)
  match contract.shape {
    @contract.Number => {
      @encode.key(out, "kind")
      @encode.string_value(out, "number")
    }
    @contract.Text(_) => {
      @encode.key(out, "kind")
      @encode.string_value(out, "string")
    }
    @contract.Boolean => {
      @encode.key(out, "kind")
      @encode.string_value(out, "boolean")
    }
    @contract.Date => {
      @encode.key(out, "kind")
      @encode.string_value(out, "date")
    }
    @contract.Timestamp => {
      @encode.key(out, "kind")
      @encode.string_value(out, "timestamp")
    }
    @contract.Decimal(precision~, scale~) => {
      @encode.key(out, "kind")
      @encode.string_value(out, "decimal")
      @encode.key(out, "precision")
      @encode.number_value(out, precision.to_double())
      @encode.key(out, "scale")
      @encode.number_value(out, scale.to_double())
    }
    @contract.ResourceRef(resource_kind~) => {
      @encode.key(out, "kind")
      @encode.string_value(out, "resource_ref")
      @encode.key(out, "resource_kind")
      @encode.string_value(out, resource_kind)
    }
    @contract.ArtifactRef(media_type~) => {
      @encode.key(out, "kind")
      @encode.string_value(out, "artifact_ref")
      @encode.key(out, "media_type")
      match media_type {
        Some(value) => @encode.string_value(out, value)
        None => @encode.null_value(out)
      }
    }
    _ => raise @encode.InvalidStructure
  }
  @encode.end_object(out)
}

///|
fn emit_property_key(
  value : @value.CheckedValue,
  out : @encode.Writer,
) -> Unit raise @encode.EncodeFailure {
  match value.value {
    @value.Decimal(decimal) => {
      @encode.begin_object(out)
      @encode.key(out, "coefficient")
      @encode.string_value(out, decimal.coefficient)
      @encode.end_object(out)
    }
    @value.Reference(reference) => {
      // Reference identity follows the existing admitted reference owner,
      // not the mutable availability or authorization envelope.
      @encode.begin_object(out)
      @encode.key(out, "identity")
      @encode.string_value(out, @value.reference_identity_cid(reference))
      @encode.end_object(out)
    }
    _ => @value.emit_wire_value(value.value, out)
  }
}

///|
/// None means a validated NULL key, which is excluded from the graph.
/// The existing encoder/parser/admitter bound every identity conversion.
fn property_identity(
  builder : Builder,
  profile : @carrier.PropertyGraphDefinition,
  definition : @carrier.PropertyNodeDefinition,
  keys : Array[@value.CheckedValue],
  pending_work : Int,
) -> Result[(@value.CheckedValue?, Int), Issue] {
  let types = @carrier.property_definition_keys(definition)
  if types.length() != keys.length() {
    return Err(InvalidIdentity)
  }
  let mut absent = false
  for index, key in keys {
    if !contract_equal(
        builder,
        types[index],
        @contract.with_nullability(key.contract, false),
      ) {
      return Err(InvalidIdentity)
    }
    match key.value {
      @value.Null => absent = true
      @value.Reference(reference) =>
        if !@value.reference_available(reference) {
          return Err(InvalidIdentity)
        }
      _ => ()
    }
  }
  if pending_work < 0 || pending_work > builder.limits.max_work - builder.work {
    return Err(WorkLimit)
  }
  let remaining = builder.limits.max_work - builder.work - pending_work
  if keys.length() > remaining {
    return Err(WorkLimit)
  }
  if absent {
    return Ok((None, keys.length()))
  }
  let limit = Int::min(
    builder.limits.max_value_nodes,
    remaining - keys.length(),
  )
  let cap = Int::min(
    builder.limits.max_value_bytes,
    builder.limits.max_total_value_bytes - builder.value_bytes,
  )
  try {
    let out = @encode.writer(cap, limit, builder.limits.max_value_depth)
    @encode.begin_object(out)
    @encode.key(out, "definition")
    @encode.string_value(out, @carrier.property_definition_name(definition))
    @encode.key(out, "domain")
    @encode.string_value(out, @carrier.property_graph_domain(profile))
    @encode.key(out, "key")
    @encode.begin_array(out)
    for key in keys {
      emit_property_key(key, out)
    }
    @encode.end_array(out)
    @encode.key(out, "key_types")
    @encode.begin_array(out)
    for contract in types {
      emit_property_key_type(contract, out)
    }
    @encode.end_array(out)
    @encode.end_object(out)
    let (text, _, nodes, _) = @encode.finish_text_usage(out)
    // Each of the four bounded passes visits the same identity document.
    // Charge the conversion once to construction, including key validation.
    if nodes > (remaining - keys.length()) / 4 {
      return Err(WorkLimit)
    }
    let source = match
      @source.parse_json(text, {
        max_input_bytes: cap,
        max_nodes: nodes,
        max_depth: builder.limits.max_value_depth,
      }) {
      Ok(value) => value
      Err(_) => return Err(ValueLimit)
    }
    let cursor = match
      @decode.admit(source, {
        max_nodes: nodes,
        max_depth: builder.limits.max_value_depth,
        max_string_bytes: cap,
        max_total_string_bytes: cap,
      }) {
      Ok(value) => value
      Err(_) => return Err(ValueLimit)
    }
    let admitted = match
      @value.admit(@carrier.graph_identity(builder.graph), cursor, {
        max_nodes: nodes,
        max_depth: builder.limits.max_value_depth,
        max_text_bytes: cap,
      }) {
      Ok(value) => value
      Err(_) => return Err(ValueLimit)
    }
    Ok((Some(admitted), nodes * 4 + keys.length()))
  } catch {
    _ =>
      if limit < builder.limits.max_value_nodes {
        Err(WorkLimit)
      } else {
        Err(ValueLimit)
      }
  }
}

///|
fn exclude_property_row(
  builder : Builder,
  values : Array[@value.CheckedValue],
  work : Int,
) -> Result[Unit, Issue] {
  // Exclusion does not exempt an input row from byte and work admission.
  let (_, bytes, used) = match encoded_values(builder, values, 0, work + 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  match reserve(builder, 1, 0, 0, bytes, 0, work + used + 1, 0) {
    Some(issue) => fail(builder, issue)
    None => {
      builder.input_rows += 1
      builder.value_bytes += bytes
      builder.work += work + used + 1
      Ok(())
    }
  }
}

///|
pub fn append_property_node(
  builder : Builder,
  definition_index : Int,
  keys : Array[@value.CheckedValue],
  properties : Array[@value.CheckedValue],
) -> Result[Unit, Issue] {
  if !builder.open {
    return Err(Closed)
  }
  let profile = @carrier.graph_property_definition(builder.graph)
  guard @carrier.property_graph_node_at(profile, definition_index)
    is Some(definition) else {
    return fail(builder, InvalidIdentity)
  }
  if !values_match(
      builder,
      @carrier.property_definition_properties(definition),
      properties,
    ) {
    return fail(builder, InvalidProperties)
  }
  let (identity, work) = match
    property_identity(builder, profile, definition, keys, 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  match identity {
    None => exclude_property_row(builder, [..keys, ..properties], work)
    Some(identity) =>
      append_node_record(
        builder, identity, properties, definition_index, keys, work,
      )
  }
}

///|
pub fn append_property_edge(
  builder : Builder,
  definition_index : Int,
  keys : Array[@value.CheckedValue],
  source_keys : Array[@value.CheckedValue],
  target_keys : Array[@value.CheckedValue],
  properties : Array[@value.CheckedValue],
) -> Result[Unit, Issue] {
  if !builder.open {
    return Err(Closed)
  }
  let profile = @carrier.graph_property_definition(builder.graph)
  guard @carrier.property_graph_edge_at(profile, definition_index) is Some(edge) else {
    return fail(builder, InvalidIdentity)
  }
  let definition = @carrier.property_edge_element(edge)
  if !values_match(
      builder,
      @carrier.property_definition_properties(definition),
      properties,
    ) {
    return fail(builder, InvalidProperties)
  }
  let (identity, initial_work) = match
    property_identity(builder, profile, definition, keys, 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  let mut work = initial_work
  guard identity is Some(identity) else {
    return exclude_property_row(
      builder,
      [..keys, ..source_keys, ..target_keys, ..properties],
      work,
    )
  }
  let (key, key_bytes, key_work) = match
    encoded_values(builder, [identity], 0, work + 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  work += key_work
  // Uniqueness precedes endpoint exclusion, including earlier excluded rows.
  if builder.edge_keys.contains(key) {
    return fail(builder, DuplicateEdgeKey)
  }
  let (source_name, target_name) = @carrier.property_edge_endpoints(edge)
  let source_definition = @carrier.property_graph_node_named(
    profile, source_name,
  ).unwrap()
  let target_definition = @carrier.property_graph_node_named(
    profile, target_name,
  ).unwrap()
  let (source, source_work) = match
    property_identity(
      builder,
      profile,
      source_definition,
      source_keys,
      work + 1,
    ) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  work += source_work
  let (target, target_work) = match
    property_identity(
      builder,
      profile,
      target_definition,
      target_keys,
      work + 1,
    ) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  work += target_work
  let mut bytes = key_bytes
  let mut source_index = None
  let mut target_index = None
  if source is Some(source) {
    let (key, size, used) = match
      encoded_values(builder, [source], bytes, work + 1) {
      Ok(value) => value
      Err(issue) => return fail(builder, issue)
    }
    bytes += size
    work += used
    source_index = builder.node_keys.get(key)
  }
  if target is Some(target) {
    let (key, size, used) = match
      encoded_values(builder, [target], bytes, work + 1) {
      Ok(value) => value
      Err(issue) => return fail(builder, issue)
    }
    bytes += size
    work += used
    target_index = builder.node_keys.get(key)
  }
  let (payload, payload_bytes, payload_work) = match
    encoded_values(builder, properties, bytes, work + 1) {
    Ok(value) => value
    Err(issue) => return fail(builder, issue)
  }
  bytes += payload_bytes
  work += payload_work + 1
  match (source_index, target_index) {
    (Some(source), Some(target)) => {
      let retained = key_bytes + payload_bytes
      let slots = edge_slots(properties.length(), false) + keys.length() + 3
      match reserve(builder, 1, 0, 1, bytes, retained, work, slots) {
        Some(issue) => return fail(builder, issue)
        None => ()
      }
      builder.edge_keys[key] = builder.edges.length()
      builder.edge_payloads[key] = payload
      builder.edges.push({
        property_definition: Some(definition_index),
        identity_order_key: Some(key),
        identity: Some(identity),
        typed_key: Some(keys.copy()),
        source,
        target,
        label: None,
        properties: properties.copy(),
      })
      builder.retained_value_bytes += retained
      builder.workspace_slots += slots
    }
    _ => {
      // The existing index owns a temporary uniqueness tombstone, not an edge.
      match reserve(builder, 1, 0, 0, bytes, key_bytes, work, 3) {
        Some(issue) => return fail(builder, issue)
        None => ()
      }
      builder.edge_keys[key] = -1
      builder.excluded_edge_keys.push((key, key_bytes))
      builder.retained_value_bytes += key_bytes
      builder.workspace_slots += 3
    }
  }
  builder.input_rows += 1
  builder.value_bytes += bytes
  builder.work += work
  Ok(())
}

///|
pub fn node_definition_index(value : Storage, index : Int) -> Int? {
  value.nodes.get(index).bind(node => node.property_definition)
}

///|
pub fn node_typed_key(
  value : Storage,
  index : Int,
) -> Array[@value.CheckedValue]? {
  value.nodes.get(index).bind(node => node.typed_key.map(keys => keys.copy()))
}

///|
/// Read one admitted key component without allocating a complete tuple. Its
/// reference evidence must not be reconstructed from the projected identity.
pub fn node_typed_key_at(
  value : Storage,
  index : Int,
  component : Int,
) -> @value.CheckedValue? {
  value.nodes
  .get(index)
  .bind(node => node.typed_key.bind(keys => keys.get(component)))
}

///|
pub fn edge_definition_index(value : Storage, index : Int) -> Int? {
  value.edges.get(index).bind(edge => edge.property_definition)
}

///|
pub fn edge_typed_key(
  value : Storage,
  index : Int,
) -> Array[@value.CheckedValue]? {
  value.edges.get(index).bind(edge => edge.typed_key.map(keys => keys.copy()))
}

///|
pub fn edge_typed_key_at(
  value : Storage,
  index : Int,
  component : Int,
) -> @value.CheckedValue? {
  value.edges
  .get(index)
  .bind(edge => edge.typed_key.bind(keys => keys.get(component)))
}

///|
pub fn edge_identity(value : Storage, index : Int) -> @value.CheckedValue? {
  value.edges.get(index).bind(edge => edge.identity)
}

///|
/// The canonical identity token is already retained by the uniqueness index.
/// Its array wrapper is common to every token and does not change ordering.
/// No identity re-encoding or property comparison is performed during a read.
pub fn node_identity_order_key(value : Storage, index : Int) -> String? {
  value.nodes.get(index).bind(node => node.identity_order_key)
}

///|
pub fn edge_identity_order_key(value : Storage, index : Int) -> String? {
  value.edges.get(index).bind(edge => edge.identity_order_key)
}

///|
// Lookup is a comparison inside one admitted definition domain, not a mapping
// between domains and not reference authorization. Do not turn an incompatible
// scoped identity into a normal "not found" answer.
fn property_lookup_scope(
  value : Storage,
  identity : @value.CheckedValue,
  edge~ : Bool,
) -> Result[Unit, Issue] {
  let profile = @carrier.graph_property_definition(value.graph)
  guard identity.value is @value.Object(fields) &&
    @value.element_count(fields) == 4 &&
    @value.element_at(fields, 0) is Some(("definition", @value.Text(name))) &&
    @value.element_at(fields, 1) is Some(("domain", @value.Text(domain))) &&
    @value.element_at(fields, 2) is Some(("key", @value.Array(keys))) &&
    @value.element_at(fields, 3) is Some(("key_types", @value.Array(types))) &&
    domain == @carrier.property_graph_domain(profile) else {
    return Err(InvalidIdentity)
  }
  let definition = if edge {
    @carrier.property_graph_edge_named(profile, name).map(edge => {
      @carrier.property_edge_element(edge)
    })
  } else {
    @carrier.property_graph_node_named(profile, name)
  }
  guard definition is Some(definition) &&
    @carrier.property_definition_name(definition) == name else {
    return Err(InvalidIdentity)
  }
  let contracts = @carrier.property_definition_keys(definition)
  if @value.element_count(keys) != contracts.length() ||
    @value.element_count(types) != contracts.length() {
    return Err(InvalidIdentity)
  }
  try {
    // One bounded encoding per complete descriptor array; no second graph index.
    let expected = @encode.writer(
      value.limits.max_value_bytes,
      value.limits.max_value_nodes,
      value.limits.max_value_depth,
    )
    @encode.begin_array(expected)
    for contract in contracts {
      emit_property_key_type(contract, expected)
    }
    @encode.end_array(expected)
    let actual = @encode.writer(
      value.limits.max_value_bytes,
      value.limits.max_value_nodes,
      value.limits.max_value_depth,
    )
    @value.emit_wire_value(@value.element_at(fields, 3).unwrap().1, actual)
    if @encode.finish(expected) != @encode.finish(actual) {
      return Err(InvalidIdentity)
    }
    for index in 0..<contracts.length() {
      guard @value.element_at(keys, index) is Some(key) &&
        property_lookup_key(key, contracts[index], value.limits) else {
        return Err(InvalidIdentity)
      }
    }
    Ok(())
  } catch {
    _ => Err(ValueLimit)
  }
}

///|
// Semantic key tokens differ from full reference/decimal envelopes. Check
// their scalar domain without granting dereference rights or minting identity.
fn property_lookup_key(
  key : @value.Value,
  contract : @contract.Contract,
  limits : Limits,
) -> Bool {
  let value = match (key, contract.shape) {
    (@value.Text(_), @contract.Date) | (@value.Text(_), @contract.Timestamp) =>
      // These types use text on the wire but opaque admitted runtime values.
      // Reuse their actual wire admission rather than inventing date parsing.
      try {
        let out = @encode.writer(
          limits.max_value_bytes,
          limits.max_value_nodes,
          limits.max_value_depth,
        )
        @value.emit_wire_value(key, out)
        guard @source.parse_json(@encode.finish(out), {
            max_input_bytes: limits.max_value_bytes,
            max_nodes: limits.max_value_nodes,
            max_depth: limits.max_value_depth,
          })
          is Ok(source) else {
          return false
        }
        guard @decode.admit(source, {
            max_nodes: limits.max_value_nodes,
            max_depth: limits.max_value_depth,
            max_string_bytes: limits.max_value_bytes,
            max_total_string_bytes: limits.max_value_bytes,
          })
          is Ok(cursor) else {
          return false
        }
        return @value.admit(contract, cursor, {
            max_nodes: limits.max_value_nodes,
            max_depth: limits.max_value_depth,
            max_text_bytes: limits.max_value_bytes,
          })
          is Ok(_)
      } catch {
        _ => return false
      }
    (@value.Object(fields), @contract.Decimal(precision~, scale~)) => {
      guard @value.element_count(fields) == 1 &&
        @value.element_at(fields, 0) is Some(("coefficient", @value.Text(text))) &&
        @value.decimal_from_coefficient(text, precision, scale) is Some(value) else {
        return false
      }
      value
    }
    (@value.Object(fields), @contract.ResourceRef(_))
    | (@value.Object(fields), @contract.ArtifactRef(_)) => {
      guard @value.element_count(fields) == 1 &&
        @value.element_at(fields, 0) is Some(("identity", @value.Text(cid))) &&
        cid.has_prefix("sha256:") &&
        cid.length() == 71 else {
        return false
      }
      // A syntactically valid identity token is usable for comparison only.
      // Existing admitted records still own reference authorization.
      return cid.to_array()[7:]
        .iter()
        .all(character => {
          (character >= '0' && character <= '9') ||
          (character >= 'a' && character <= 'f')
        })
    }
    _ => key
  }
  @value.recheck_runtime_value(value, contract, {
    max_nodes: limits.max_value_nodes,
    max_depth: limits.max_value_depth,
    max_text_bytes: limits.max_value_bytes,
  })
  is Some(_)
}

///|
pub fn edge_identity_index(
  value : Storage,
  identity : @value.CheckedValue,
) -> Result[Int?, Issue] {
  match property_lookup_scope(value, identity, edge=true) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !(@contract.type_equal(
      identity.contract,
      @carrier.graph_identity(value.graph),
      value.limits.max_contract_work,
    ) catch {
      _ => false
    }) {
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
    Ok(value.edge_keys.get(@encode.finish(out)))
  } catch {
    _ => Err(ValueLimit)
  }
}
