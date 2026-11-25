///|
// Mechanical public catalogue projection through the existing canonical Owner.
// The caller retains the original Json and funds these constructors before
// entry. Encoder bounds are not capacity, permission or Source admission.
fn relation_declaration_projection_wire(
  value : Json,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RowHostIssue] {
  try {
    let canonical = @identity.from_json(
      value,
      max_nodes,
      max_depth,
      max_bytes,
      data_keys=true,
    )
    Ok(@identity.stringify_value(canonical, max_bytes, max_nodes, max_depth))
  } catch {
    _ => Err(InvalidSpecification)
  }
}

///|
/// Translate only the public catalogue's schema/facts/request fields to the
/// EXISTING Relation restore input. Unknown fields remain for its strict
/// admission; private destination names cannot be injected by public DATA.
/// This does not install an environment, select a physical source or issue any
/// authority. All hosts use the same original declaration/restore Owner.
pub fn project_relation_declaration_input(
  entry : Json,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, RowHostIssue] {
  if max_bytes <= 0 || max_nodes <= 0 || max_depth <= 0 {
    return Err(InvalidSpecification)
  }
  guard entry is Object(fields) && fields.get("views") is Some(Array(views)) else {
    return Err(InvalidSpecification)
  }
  let saved = []
  for view in views {
    guard view is Object(fields) else { return Err(InvalidSpecification) }
    let projected : Map[String, Json] = Map([])
    for key, value in fields {
      if key == "schema" {
        let wire = match
          relation_declaration_projection_wire(
            value, max_bytes, max_nodes, max_depth,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        projected["schema_wire"] = Json::string(wire)
        projected["schema_cid"] = Json::string(
          "sha256:" + @sha.hex(@utf8.encode(wire)),
        )
      } else if ["request_schema", "facts", "acquisition", "resource_identity"].contains(
          key,
        ) {
        let wire = match
          relation_declaration_projection_wire(
            value, max_bytes, max_nodes, max_depth,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        projected[key + "_wire"] = Json::string(wire)
      } else if key.has_suffix("_wire") || key == "schema_cid" {
        projected["public_input_field:" + key] = value
      } else {
        projected[key] = value
      }
    }
    saved.push(Json::object(projected))
  }
  relation_declaration_projection_wire(
    Json::object(Map([("views", Json::array(saved))])),
    max_bytes,
    max_nodes,
    max_depth,
  )
}

///|
/// A complete saved Relation schema, not observed rows or physical type names.
pub(all) struct RowRelationViewSpec {
  resource : String
  resource_kind : String
  schema_wire : String
  schema_cid : String
  request_schema_wire : String?
  facts_wire : String?
  acquisition_wire : String?
}

///|
pub fn generate_relation_row_declaration(
  connector_id : String,
  connector_registration : String,
  connector_version : String,
  views : Array[RowRelationViewSpec],
  limits : RowDeclarationLimits,
  classifications? : Array[@environment.DataClassification]? = None,
) -> Result[RowDeclaration, RowHostIssue] {
  generate_relation_row_declaration_with_resource_identities(
    connector_id,
    connector_registration,
    connector_version,
    views,
    limits,
    classifications,
    None,
  )
}

///|
// The original public constructor has no additional identity input. Saved
// relation specifications may carry the existing static SourceView contract;
// it is admitted under the same cumulative declaration bounds, never authority.
fn generate_relation_row_declaration_with_resource_identities(
  connector_id : String,
  connector_registration : String,
  connector_version : String,
  views : Array[RowRelationViewSpec],
  limits : RowDeclarationLimits,
  classifications : Array[@environment.DataClassification]?,
  resource_identity_wires : Array[String?]?,
) -> Result[RowDeclaration, RowHostIssue] {
  if limits.max_bytes < 1 ||
    limits.max_nodes < 1 ||
    limits.max_depth < 1 ||
    views.is_empty() ||
    views.length() > limits.max_views {
    return Err(InvalidSpecification)
  }
  if resource_identity_wires is Some(values) &&
    values.length() != views.length() {
    return Err(InvalidSpecification)
  }
  let specs = []
  let bodies = []
  let requests = []
  let resource_identities = []
  let mut bytes = limits.max_bytes
  let mut nodes = limits.max_nodes
  let mut work = limits.max_nodes
  for view_index, view in views {
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
    let identity_wire = match resource_identity_wires {
      Some(values) => values[view_index]
      None => None
    }
    match identity_wire {
      None => resource_identities.push(None)
      Some(wire) => {
        let (body, used_bytes, used_nodes, identity_work) = match
          relation_resource_identity_body(
            wire,
            view.resource_kind,
            schema,
            bytes,
            nodes,
            limits.max_depth,
            work,
          ) {
          Ok(value) => value
          Err(issue) => return Err(issue)
        }
        bytes -= used_bytes
        nodes -= used_nodes
        work -= identity_work
        resource_identities.push(Some(body))
      }
    }
    let request_bodies = []
    for
      index, wire in [
        view.request_schema_wire,
        view.facts_wire,
        view.acquisition_wire,
      ] {
      if index == 2 && wire is None {
        // An absent acquisition declaration does not consume a synthetic input.
        request_bodies.push(Json::null())
        continue
      }
      let wire = match wire {
        Some(wire) => wire
        None if index == 0 =>
          "{\"type\":\"object\",\"nullable\":false,\"additional_properties\":false,\"fields\":{}}"
        None => "{}"
      }
      let source = match
        @source.parse_json(wire, {
          max_input_bytes: bytes,
          max_nodes: nodes,
          max_depth: limits.max_depth,
        }) {
        Ok(source) => source
        Err(_) => return Err(InvalidSpecification)
      }
      let cursor = match
        @decode.admit(source, {
          max_nodes: nodes,
          max_depth: limits.max_depth,
          max_string_bytes: bytes,
          max_total_string_bytes: bytes,
        }) {
        Ok(cursor) => cursor
        Err(_) => return Err(InvalidSpecification)
      }
      if @decode.object_length(cursor) is None {
        return Err(InvalidContracts)
      }
      if index == 0 {
        guard @contract.read_checked(cursor, {
            max_nodes: nodes,
            max_depth: limits.max_depth,
            max_text_bytes: bytes,
          })
          is Ok(contract) &&
          !contract.nullable &&
          contract.shape is @contract.Object(fields) &&
          @contract.field_count(fields) <= limits.max_fields else {
          return Err(InvalidContracts)
        }
      }
      let body = @json.parse(wire) catch {
        _ => return Err(InvalidSpecification)
      }
      let canonical = @identity.from_json(body, nodes, limits.max_depth, bytes) catch {
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
      // Preserve cumulative budgets across all views and their declarations.
      nodes -= @decode.admission_usage(cursor).nodes
      bytes -= measured
      // The shared declaration emitter expects nested contract objects in
      // canonical key order too. Source specification JSON order is not an
      // identity input; preserve values while using the admitted canonical body.
      let canonical_wire = @identity.stringify_value(
        canonical,
        measured,
        limits.max_nodes,
        limits.max_depth,
      ) catch {
        _ => return Err(InvalidSpecification)
      }
      let canonical_body = @json.parse(canonical_wire) catch {
        _ => return Err(InvalidSpecification)
      }
      request_bodies.push(canonical_body)
    }
    requests.push(
      (
        request_bodies[0],
        request_bodies[1],
        if view.acquisition_wire is Some(_) {
          Some(request_bodies[2])
        } else {
          None
        },
      ),
    )
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
    Some(requests),
    classifications,
    Some(resource_identities),
    limits,
  ).map_err(issue => Declaration(issue))
}

///|
let relation_restore_limits : RowDeclarationLimits = {
  ..declaration_limits,
  max_fields: 1024,
}

///|
/// Project the exact checked CSV fields and optional ordered key into the
/// same view specification used by Relation restoration. No physical path,
/// Source capability, or permission is supplied by the schema projection.
pub fn project_local_csv_relation_view(
  resource : String,
  column_names : Array[String],
  integer_columns : Array[Bool],
  keys : Array[String],
) -> Result[RowRelationViewSpec, RowHostIssue] {
  let limits = relation_restore_limits
  let width = column_names.length()
  guard width > 0 &&
    width <= limits.max_fields &&
    width == integer_columns.length() &&
    keys.length() <= width else {
    return Err(InvalidSpecification)
  }
  let schema : Map[String, Json] = Map([])
  for index in 0..<width {
    let name = column_names[index]
    if name.is_empty() || name.contains("\u0000") || schema.contains(name) {
      return Err(InvalidSpecification)
    }
    let kind = if integer_columns[index] { "int64" } else { "string" }
    schema[name] = Json::object(
      Map([("nullable", Json::boolean(false)), ("type", Json::string(kind))]),
    )
  }
  let key_fields : Map[String, Unit] = Map([])
  for key in keys {
    if !schema.contains(key) || key_fields.contains(key) {
      return Err(InvalidSpecification)
    }
    key_fields[key] = ()
  }
  let facts : Json = if keys.is_empty() {
    Json::object(Map([]))
  } else {
    {
      "relation_keys": {
        "candidate_keys": Json::array([Json::array(keys.map(Json::string))]),
      },
    }
  }
  let schema_wire = match
    relation_declaration_projection_wire(
      Json::object(schema),
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(issue)
  }
  let facts_wire = match
    relation_declaration_projection_wire(
      facts,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(wire) => wire
    Err(issue) => return Err(issue)
  }
  Ok({
    resource,
    resource_kind: "record",
    schema_wire,
    schema_cid: "sha256:" + @sha.hex(@utf8.encode(schema_wire)),
    request_schema_wire: None,
    facts_wire: Some(facts_wire),
    acquisition_wire: None,
  })
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
  let limits = relation_restore_limits
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
  let classifications : Array[@environment.DataClassification] = []
  let resource_identities = []
  for view in views {
    guard view is Object(entries) &&
      entries.length() >= 4 &&
      entries.length() <= 9 &&
      spec_text(view, "resource") is Some(resource) &&
      spec_text(view, "resource_kind") is Some(resource_kind) &&
      spec_text(view, "schema_wire") is Some(schema_wire) &&
      spec_text(view, "schema_cid") is Some(schema_cid) else {
      return Err(InvalidSpecification)
    }
    for name in entries.keys() {
      if ![
          "resource", "resource_kind", "schema_wire", "schema_cid", "request_schema_wire",
          "facts_wire", "acquisition_wire", "data_classification", "resource_identity_wire",
        ].contains(name) {
        return Err(InvalidSpecification)
      }
    }
    let classification = match entries.get("data_classification") {
      None | Some(String("unknown")) => @environment.Unknown
      Some(String("public")) => @environment.Public
      Some(String("internal")) => @environment.Internal
      Some(String("confidential")) => @environment.Confidential
      Some(String("restricted")) => @environment.Restricted
      _ => return Err(InvalidSpecification)
    }
    classifications.push(classification)
    match entries.get("resource_identity_wire") {
      None => resource_identities.push(None)
      Some(String(wire)) => resource_identities.push(Some(wire))
      _ => return Err(InvalidSpecification)
    }
    let optional = []
    for name in ["request_schema_wire", "facts_wire", "acquisition_wire"] {
      match entries.get(name) {
        None => optional.push(None)
        Some(String(wire)) => optional.push(Some(wire))
        _ => return Err(InvalidSpecification)
      }
    }
    specs.push({
      resource,
      resource_kind,
      schema_wire,
      schema_cid,
      request_schema_wire: optional[0],
      facts_wire: optional[1],
      acquisition_wire: optional[2],
    })
  }
  let declaration = match
    generate_relation_row_declaration_with_resource_identities(
      connector_id,
      connector_registration,
      connector_version,
      specs,
      // Preserve the admitted original range. The installed caller already
      // owns reconstruction; explicit generator limits remain independent.
      { ..limits, max_views: views.length(), },
      Some(classifications),
      Some(resource_identities),
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
