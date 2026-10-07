///|
/// A complete saved Relation schema, not observed rows or physical type names.
pub(all) struct RowRelationViewSpec {
  resource : String
  resource_kind : String
  schema_wire : String
  schema_cid : String
}

///|
pub fn generate_relation_row_declaration(
  connector_id : String,
  connector_registration : String,
  connector_version : String,
  views : Array[RowRelationViewSpec],
  limits : RowDeclarationLimits,
) -> Result[RowDeclaration, RowHostIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    views.is_empty() ||
    views.length() > limits.max_views {
    return Err(InvalidSpecification)
  }
  let specs = []
  let bodies = []
  let mut bytes = limits.max_bytes
  let mut nodes = limits.max_nodes
  let mut work = limits.max_nodes
  for view in views {
    if @publication.validate_result_schema_wire(
        view.schema_cid,
        view.schema_wire,
        bytes,
        nodes,
        limits.max_depth,
      )
      is Err(_) {
      return Err(InvalidContracts)
    }
    let source = match
      @source.parse_json(view.schema_wire, {
        max_input_bytes: bytes,
        max_nodes: nodes,
        max_depth: limits.max_depth,
      }) {
      Ok(value) => value
      Err(_) => return Err(InvalidSpecification)
    }
    let cursor = match
      @decode.admit(source, {
        max_nodes: nodes,
        max_depth: limits.max_depth,
        max_string_bytes: bytes,
        max_total_string_bytes: bytes,
      }) {
      Ok(value) => value
      Err(_) => return Err(InvalidSpecification)
    }
    let usage = @decode.admission_usage(cursor)
    // Each map is measured before per-field admission, with cumulative bounds
    // across views. Output construction has its own existing envelope limit.
    let map = @json.parse(view.schema_wire) catch {
      _ => return Err(InvalidSpecification)
    }
    let canonical = @identity.from_json(map, nodes, limits.max_depth, bytes) catch {
      _ => return Err(InvalidSpecification)
    }
    let measured = @identity.measure_value(
      canonical,
      bytes,
      nodes,
      limits.max_depth,
    ) catch {
      _ => return Err(InvalidSpecification)
    }
    let (schema, used_work) = match
      @environment.read_relation_schema_fields(
        cursor,
        bytes,
        nodes,
        limits.max_depth,
        work,
      ) {
      Ok(value) => value
      Err(_) => return Err(InvalidContracts)
    }
    if @schema.field_count(schema) > limits.max_fields {
      return Err(InvalidSpecification)
    }
    nodes -= usage.nodes
    work -= used_work
    bytes -= measured
    let fields = @schema.fields(schema).map(field => {
      name: @schema.field_reference_name(field),
      // These descriptors supply names only to shared declaration generation.
      // The exact admitted contracts/presence below supply the carrier body.
      value_type: "schema",
      nullable: field.contract.nullable,
    })
    specs.push({
      resource: view.resource,
      resource_kind: view.resource_kind,
      fields,
    })
    bodies.push(
      object([
        ("fields", map),
        ("version", "actql-relation-schema/0.1".to_json()),
      ]),
    )
  }
  generate_row_declaration_impl(
    connector_id,
    connector_registration,
    connector_version,
    specs,
    Some(bodies),
    limits,
  ).map_err(issue => Declaration(issue))
}

///|
/// Restore a Host-installed view from saved common schema material. The
/// specification is bounded before JSON reconstruction; restored bytes must
/// reproduce the original Catalog if an expected identity is supplied.
pub fn restore_relation_row_declaration(
  connector_id : String,
  connector_registration : String,
  connector_version : String,
  views_json : String,
  expected_catalog_cid : String?,
) -> Result[RowDeclaration, RowHostIssue] {
  let limits : RowDeclarationLimits = {
    ..declaration_limits,
    max_fields: 1024,
  }
  let source = match
    @source.parse_json(views_json, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  if @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    })
    is Err(_) {
    return Err(InvalidSpecification)
  }
  let parsed = @json.parse(views_json) catch {
    _ => return Err(InvalidSpecification)
  }
  guard parsed is Object(root) &&
    root.length() == 1 &&
    root.get("views") is Some(Array(views)) else {
    return Err(InvalidSpecification)
  }
  let specs = []
  for view in views {
    guard view is Object(entries) &&
      entries.length() == 4 &&
      spec_text(view, "resource") is Some(resource) &&
      spec_text(view, "resource_kind") is Some(resource_kind) &&
      spec_text(view, "schema_wire") is Some(schema_wire) &&
      spec_text(view, "schema_cid") is Some(schema_cid) else {
      return Err(InvalidSpecification)
    }
    specs.push({ resource, resource_kind, schema_wire, schema_cid, })
  }
  let declaration = match
    generate_relation_row_declaration(
      connector_id, connector_registration, connector_version, specs, limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if expected_catalog_cid is Some(expected) &&
    expected != declaration.catalog_cid {
    return Err(ForeignDeclaration)
  }
  Ok(declaration)
}
