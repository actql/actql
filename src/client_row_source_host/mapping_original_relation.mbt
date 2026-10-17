///|
fn mapping_read_original(
  wire : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[(Json, @decode.Cursor, Int, Int), RowMappingIssue] {
  if wire.length() > max_bytes {
    return Err(OutputLimit)
  }
  let bytes = @utf8.encode(wire).length()
  if bytes > max_bytes {
    return Err(OutputLimit)
  }
  let source = match
    @source.parse_json(wire, { max_input_bytes: bytes, max_nodes, max_depth, }) {
    Ok(value) => value
    Err(_) => return Err(OutputLimit)
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes,
      max_depth,
      max_string_bytes: bytes,
      max_total_string_bytes: bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(OutputLimit)
  }
  let json = @json.parse(wire) catch { _ => return Err(InvalidSpecification) }
  Ok((json, cursor, bytes, @decode.admission_usage(cursor).nodes))
}

///|
fn mapping_original_identity(
  original : Json,
  identity_field : String,
  expected : String,
  limits : RowDeclarationLimits,
) -> Bool {
  guard original is Object(fields) else { return false }
  let preimage = []
  for name, value in fields {
    if name != identity_field {
      preimage.push((name, value))
    }
  }
  try canonical_cid(object(preimage), limits) == expected catch {
    _ => false
  }
}

///|
// Read only the original declaration/View/carrier correspondence. Callers
// keep operation-specific writable facts, permissions and execution Owners.
fn mapping_original_relation(
  declaration : RowDeclaration,
  resource : String,
  primary_identity : String,
  limits : RowDeclarationLimits,
) -> Result[(String, @contract.Contract), RowMappingIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_views <= 0 {
    return Err(InvalidSpecification)
  }
  if primary_identity.is_empty() ||
    declaration.views.length() > limits.max_views {
    return Err(InvalidSpecification)
  }
  let selected_index = match
    declaration.views.search_by(view => view.resource == resource) {
    Some(index) => index
    None => return Err(NotWritable(resource))
  }
  let selected = declaration.views[selected_index]
  guard declaration.view_bodies.get(selected_index) is Some(view_wire) else {
    return Err(InvalidSpecification)
  }
  let (view, _, view_bytes, view_nodes) = match
    mapping_read_original(
      view_wire,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let resource_kind = match spec_text(view, "resource_kind") {
    Some(value) if valid_name(value, 64) => value
    _ => return Err(InvalidSpecification)
  }
  if spec_text(view, "contract_cid") != Some(selected.view_cid) ||
    !mapping_original_identity(view, "contract_cid", selected.view_cid, limits) {
    return Err(InvalidSpecification)
  }
  guard view is Object(view_fields) &&
    view_fields.get("output") is Some(Object(output)) &&
    output.get("schema") is Some(schema_reference) &&
    ref_cid(schema_reference) == selected.carrier_schema_cid &&
    spec_text(view, "connector_id") == Some(declaration.connector_id) &&
    spec_text(view, "connector_version") == Some(declaration.connector_version) &&
    selected.source_ref ==
    "connector://" + declaration.connector_id + "/" + resource + "#records" else {
    return Err(InvalidSpecification)
  }
  let mut remaining_bytes = limits.max_bytes - view_bytes
  let mut remaining_nodes = limits.max_nodes - view_nodes
  let mut selected_schema : @contract.Contract? = None
  for wire in declaration.contracts {
    let (original, cursor, bytes, nodes) = match
      mapping_read_original(
        wire,
        remaining_bytes,
        remaining_nodes,
        limits.max_depth,
      ) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    remaining_bytes -= bytes
    remaining_nodes -= nodes
    let envelope = match @decode.open_object(cursor) {
      Ok(value) => value
      Err(_) => return Err(InvalidSpecification)
    }
    guard @decode.lookup(envelope, "cid") is Some(identity) &&
      @decode.text(identity) == Ok(selected.carrier_schema_cid) else {
      continue
    }
    if selected_schema is Some(_) ||
      @decode.lookup(envelope, "kind").map(@decode.text) !=
      Some(Ok("carrier_schema")) ||
      !mapping_original_identity(
        original,
        "cid",
        selected.carrier_schema_cid,
        limits,
      ) {
      return Err(InvalidSpecification)
    }
    guard @decode.lookup(envelope, "body") is Some(body) &&
      @decode.open_object(body) is Ok(object) else {
      return Err(InvalidSpecification)
    }
    let schema = if @decode.lookup(object, "version") is Some(version) {
      guard @decode.text(version) == Ok("actql-relation-schema/0.1") &&
        @decode.lookup(object, "fields") is Some(fields) else {
        return Err(InvalidSpecification)
      }
      match
        @environment.read_relation_schema_fields(
          fields,
          limits.max_bytes,
          limits.max_nodes,
          limits.max_depth,
          limits.max_nodes,
        ) {
        Ok((schema, _)) => schema
        Err(_) => return Err(InvalidSpecification)
      }
    } else {
      let contract = match
        @contract.read_checked(body, {
          max_nodes: limits.max_nodes,
          max_depth: limits.max_depth,
          max_text_bytes: limits.max_bytes,
        }) {
        Ok(value) => value
        Err(_) => return Err(InvalidSpecification)
      }
      match @schema.from_object(contract) {
        Ok(value) => value
        Err(_) => return Err(InvalidSpecification)
      }
    }
    if @schema.field_count(schema) > limits.max_fields {
      return Err(OutputLimit)
    }
    guard @schema.lookup_reference(schema, primary_identity) is Some(primary) &&
      !primary.contract.nullable &&
      @contract.key_comparable(primary.contract, primary.contract) else {
      return Err(InvalidSpecification)
    }
    // A closed object cannot silently strengthen conditional field presence.
    // An unrepresentable original refuses this Mapping, not all Relation use.
    selected_schema = @schema.as_object(schema)
    if selected_schema is None {
      return Err(InvalidSpecification)
    }
  }
  guard selected_schema is Some(schema) else {
    return Err(InvalidSpecification)
  }
  Ok((resource_kind, schema))
}
