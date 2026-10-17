///|
fn delete_mapping_read_original(
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
fn delete_mapping_original_identity(
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
/// A bounded metadata projection of the original declared Relation. This
/// creates existing Mapping DATA only: the provider must independently own its
/// record-id meaning, observation, permissions, current checks and cleanup.
/// No proposed value or writable field is introduced for DELETE.
pub fn prepare_row_delete_mapping(
  declaration : RowDeclaration,
  resource : String,
  primary_identity : String,
  permission : String,
  approval : String,
  limits : RowDeclarationLimits,
) -> Result[RowMapping, RowMappingIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_views <= 0 {
    return Err(InvalidSpecification)
  }
  if primary_identity.is_empty() ||
    permission.is_empty() ||
    (approval != "none" && approval != "required") ||
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
    delete_mapping_read_original(
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
    !delete_mapping_original_identity(
      view,
      "contract_cid",
      selected.view_cid,
      limits,
    ) {
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
      delete_mapping_read_original(
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
      !delete_mapping_original_identity(
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
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(OutputLimit)
  }
  let schema_wire = try {
    @contract.emit_checked(schema, writer)
    @encode.finish(writer)
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      return Err(OutputLimit)
    }
  }
  let target_schema = @json.parse(schema_wire) catch {
    _ => return Err(InvalidSpecification)
  }
  try {
    let request_cid = canonical_cid(
      object([
        ("resource", resource.to_json()),
        ("kind", "delete".to_json()),
        ("key", Json::null()),
        ("target_schema", target_schema),
        ("write_fields", Json::array([])),
        ("row_mapping", object([])),
      ]),
      limits,
    )
    let mapping_ref = "mapping:" +
      declaration.connector_id +
      "/" +
      resource +
      "/delete-" +
      request_cid[7:23].to_owned() +
      ".v1"
    let identity = canonical_cid(
      object([
        ("version", "actql.resource_identity/0.1".to_json()),
        ("provider_namespace", declaration.connector_registration.to_json()),
        ("resource_kind", resource_kind.to_json()),
        ("provider_id_field", primary_identity.to_json()),
        ("output_field", primary_identity.to_json()),
        ("boundary_topology", "connector_connection".to_json()),
      ]),
      limits,
    )
    let (mapping, mapping_cid) = seal(
      [
        ("schema", "actql.mapping_contract/0.1".to_json()),
        ("version", declaration.connector_version.to_json()),
        ("mapping_ref", mapping_ref.to_json()),
        (
          "target_ref",
          ("connector://" + declaration.connector_id + "/" + resource).to_json(),
        ),
        ("connector_manifest_cid", declaration.manifest_entry_cid.to_json()),
        ("resource_identity_cid", identity.to_json()),
        ("target_schema", target_schema),
        (
          "target_schema_identity",
          canonical_cid(target_schema, limits).to_json(),
        ),
        ("primary_identity", primary_identity.to_json()),
        ("writable_fields", Json::array([])),
        ("required_fields", Json::array([])),
        ("conversions", Json::array([])),
        (
          "permission_rules",
          Json::array([
            object([
              ("effect_kind", "delete".to_json()),
              ("selector_class", "id".to_json()),
              ("write_fields", Json::array([])),
              ("permissions", Json::array([permission.to_json()])),
            ]),
          ]),
        ),
        ("required_permissions", Json::array([])),
        ("minimum_approval", approval.to_json()),
        ("row_mapping", object([])),
      ],
      "mapping_contract_cid",
      limits,
    )
    Ok({
      resource,
      mapping_ref,
      mapping_cid,
      body: canonical_text(mapping, limits),
      write_fields: [],
      omittable: [],
    })
  } catch {
    _ => Err(OutputLimit)
  }
}
