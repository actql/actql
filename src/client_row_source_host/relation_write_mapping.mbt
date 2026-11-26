///|
/// Closed operation DATA for a Mapping of the original declared Relation.
/// Static support does not issue a current grant, Preview or dispatch claim.
pub(all) enum RowRelationWriteKind {
  RelationCreate
  RelationUpdate
  /// Original physical identity field and the additional update permission.
  RelationKeyUpsert(native_identity~ : String, update_permission~ : String)
} derive(Eq, Debug)

///|
/// The connector supplies its original writable/required facts. Common checks
/// them against the retained Relation; it does not derive provider permission
/// or writable support merely from a readable carrier.
pub(all) struct RowRelationWriteSpec {
  kind : RowRelationWriteKind
  writable_fields : Array[String]
  required_fields : Array[String]
  permission : String
  approval : String
} derive(Eq, Debug)

///|
/// Copied names from this Owner's immutable Mapping body, not escaped mutable
/// declaration or metadata arrays. This is schema DATA, not a current grant.
pub fn row_mapping_target_fields(
  mapping : RowMapping,
  limits : RowDeclarationLimits,
) -> Result[Array[String], RowMappingIssue] {
  if limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 ||
    limits.max_fields <= 0 {
    return Err(InvalidSpecification)
  }
  let (_, cursor, _, _) = match
    mapping_read_original(
      mapping.body,
      limits.max_bytes,
      limits.max_nodes,
      limits.max_depth,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(cursor) is Ok(object) &&
    @decode.lookup(object, "target_schema") is Some(target) else {
    return Err(InvalidSpecification)
  }
  let contract = match
    @contract.read_checked(target, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_text_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidSpecification)
  }
  guard contract.shape is @contract.Object(fields) else {
    return Err(InvalidSpecification)
  }
  if @contract.field_count(fields) > limits.max_fields {
    return Err(OutputLimit)
  }
  Ok(@contract.fields(fields).map(field => field.name))
}

///|
/// Preserve the complete original closed Relation Contract, including nested
/// Array/Decimal meaning, instead of rebuilding it from scalar type labels.
/// Existing scalar/collection create Mappings keep their original API/bytes.
pub fn prepare_relation_row_write_mapping(
  declaration : RowDeclaration,
  resource : String,
  primary_identity : String,
  spec : RowRelationWriteSpec,
  sources : Array[RowMappingSource],
  limits : RowDeclarationLimits,
) -> Result[RowMapping, RowMappingIssue] {
  prepare_relation_row_write_mapping_original(
    declaration, resource, primary_identity, spec, sources, limits,
  )
}

///|
fn prepare_relation_row_write_mapping_original(
  declaration : RowDeclaration,
  resource : String,
  primary_identity : String,
  spec : RowRelationWriteSpec,
  sources : Array[RowMappingSource],
  limits : RowDeclarationLimits,
  tuple? : (FileMappingKind, Array[String])? = None,
) -> Result[RowMapping, RowMappingIssue] {
  let ordered = tuple.map(value => value.1)
  let delete = tuple is Some((FileDelete, _))
  let upsert = tuple is Some((FileUpsert, _))
  if limits.max_fields <= 0 ||
    sources.length() > limits.max_fields ||
    spec.writable_fields.length() > limits.max_fields ||
    spec.required_fields.length() > limits.max_fields ||
    spec.permission.is_empty() ||
    (spec.approval != "none" && spec.approval != "required") ||
    !distinct(spec.writable_fields) ||
    !distinct(spec.required_fields) ||
    spec.writable_fields.contains(primary_identity) ||
    !spec.required_fields.all(name => spec.writable_fields.contains(name)) ||
    (spec.kind == RelationUpdate && !upsert && !spec.required_fields.is_empty()) {
    return Err(InvalidSpecification)
  }
  let (resource_kind, schema) = match
    mapping_original_relation(
      declaration,
      resource,
      primary_identity,
      limits,
      ordered_key=ordered,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @schema.from_object(schema) is Ok(relation) else {
    return Err(InvalidSpecification)
  }
  if sources.is_empty() && !delete {
    return Err(EmptyWrite)
  }
  if ordered is Some(fields) {
    if !relation_file_tuple_key_valid(relation, fields) ||
      fields.any(field => spec.writable_fields.contains(field)) {
      return Err(InvalidSpecification)
    }
  }
  let mut remaining = limits.max_bytes
  if spec.kind is RelationKeyUpsert(native_identity~, update_permission~) {
    guard @schema.lookup_reference(relation, native_identity) is Some(field) &&
      !field.contract.nullable &&
      @contract.key_comparable(field.contract, field.contract) &&
      native_identity != primary_identity &&
      !spec.writable_fields.contains(native_identity) &&
      !update_permission.is_empty() &&
      update_permission != spec.permission else {
      return Err(InvalidSpecification)
    }
    for name in [native_identity, update_permission] {
      if name.length() > remaining {
        return Err(OutputLimit)
      }
      let bytes = @utf8.encode(name).length()
      if bytes > remaining {
        return Err(OutputLimit)
      }
      remaining -= bytes
    }
  }
  let names = [
    resource,
    ..ordered.unwrap_or([primary_identity]),
    spec.permission,
    ..spec.writable_fields,
    ..spec.required_fields,
  ]
  for name in names {
    if name.length() > remaining {
      return Err(OutputLimit)
    }
    let bytes = @utf8.encode(name).length()
    if bytes > remaining {
      return Err(OutputLimit)
    }
    remaining -= bytes
  }
  for name in spec.writable_fields {
    if @schema.lookup_reference(relation, name) is None {
      return Err(FieldNotWritable(name))
    }
  }
  let targets = []
  for source in sources {
    for name in [source.target, source.field] {
      if name.length() > remaining {
        return Err(OutputLimit)
      }
      let bytes = @utf8.encode(name).length()
      if bytes > remaining {
        return Err(OutputLimit)
      }
      remaining -= bytes
    }
    if targets.contains(source.target) {
      return Err(DuplicateField(source.target))
    }
    if !spec.writable_fields.contains(source.target) {
      return Err(FieldNotWritable(source.target))
    }
    guard @schema.lookup_reference(relation, source.target) is Some(field) else {
      return Err(FieldNotWritable(source.target))
    }
    let valid = match source.null_behavior {
      "reject" => true
      "write_null" => field.contract.nullable
      "omit" => !spec.required_fields.contains(source.target)
      _ => false
    }
    if !valid || source.field.is_empty() {
      return Err(InvalidNullBehavior(source.target))
    }
    targets.push(source.target)
  }
  for name in spec.required_fields {
    if !targets.contains(name) {
      return Err(MissingRequiredField(name))
    }
  }
  let written = targets.copy()
  written.sort_by((a, b) => {
    if key_before(a, b) {
      -1
    } else if key_before(b, a) {
      1
    } else {
      0
    }
  })
  let required = spec.required_fields.copy()
  required.sort_by((a, b) => {
    if key_before(a, b) {
      -1
    } else if key_before(b, a) {
      1
    } else {
      0
    }
  })
  let row_mapping = sources.map(source => {
    (
      source.target,
      object([
        ("field", source.field.to_json()),
        ("null_behavior", source.null_behavior.to_json()),
      ]),
    )
  })
  let (kind, selector) = match tuple {
    Some((FileUpdate, _)) => ("update", "match_tuple")
    Some((FileDelete, _)) => ("delete", "match_tuple")
    Some((FileUpsert, _)) => ("upsert", "key_tuple")
    Some((FileCreate, _)) => return Err(InvalidSpecification)
    None =>
      match spec.kind {
        RelationCreate => ("create", "none")
        RelationUpdate => ("update", "id")
        RelationKeyUpsert(..) => ("upsert", "key")
      }
  }
  let permission = spec.permission
  let provider_identity = match spec.kind {
    RelationKeyUpsert(native_identity~, ..) => native_identity
    _ => primary_identity
  }
  let approval = spec.approval
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
  let target_ref = "connector://" + declaration.connector_id + "/" + resource
  let primary = match ordered {
    Some(fields) => file_tuple_identity_body(fields)
    None => primary_identity.to_json()
  }
  try {
    let request_key = if ordered is Some(_) ||
      spec.kind is RelationKeyUpsert(..) {
      primary
    } else {
      Json::null()
    }
    let request_cid = canonical_cid(
      object(
        [
          ("resource", resource.to_json()),
          ("kind", kind.to_json()),
          ("key", request_key),
          ..if spec.kind is RelationKeyUpsert(..) {
            [("native_identity", provider_identity.to_json())]
          } else {
            []
          },
          ("target_schema", target_schema),
          ("write_fields", Json::array(written.map(name => name.to_json()))),
          ("row_mapping", object(row_mapping)),
        ],
      ),
      limits,
    )
    let mapping_ref = "mapping:" +
      declaration.connector_id +
      "/" +
      resource +
      "/" +
      kind +
      "-" +
      request_cid[7:23].to_owned() +
      ".v1"
    let target_schema_identity = canonical_cid(target_schema, limits)
    let identity = if ordered is Some(_) {
      // The tuple Mapping binds the complete ordered identity and typed
      // original target. A field of the tuple is never a scalar row identity.
      canonical_cid(
        object([
          ("kind", "file_mock_tuple".to_json()),
          ("provider_namespace", declaration.connector_registration.to_json()),
          ("resource_kind", resource_kind.to_json()),
          ("target_ref", target_ref.to_json()),
          ("target_schema_identity", target_schema_identity.to_json()),
          ("primary_identity", primary),
          ("boundary_topology", "connector_connection".to_json()),
        ]),
        limits,
      )
    } else {
      canonical_cid(
        object([
          ("version", "actql.resource_identity/0.1".to_json()),
          ("provider_namespace", declaration.connector_registration.to_json()),
          ("resource_kind", resource_kind.to_json()),
          ("provider_id_field", provider_identity.to_json()),
          ("output_field", provider_identity.to_json()),
          ("boundary_topology", "connector_connection".to_json()),
        ]),
        limits,
      )
    }
    let (mapping, mapping_cid) = seal(
      [
        (
          "schema",
          if ordered is Some(_) {
            "actql.mapping_contract/0.2".to_json()
          } else {
            "actql.mapping_contract/0.1".to_json()
          },
        ),
        ("version", declaration.connector_version.to_json()),
        ("mapping_ref", mapping_ref.to_json()),
        ("target_ref", target_ref.to_json()),
        ("connector_manifest_cid", declaration.manifest_entry_cid.to_json()),
        ("resource_identity_cid", identity.to_json()),
        ("target_schema", target_schema),
        ("target_schema_identity", target_schema_identity.to_json()),
        ("primary_identity", primary),
        ("writable_fields", Json::array(written.map(name => name.to_json()))),
        ("required_fields", Json::array(required.map(name => name.to_json()))),
        ("conversions", Json::array([])),
        (
          "permission_rules",
          Json::array([
            object([
              ("effect_kind", kind.to_json()),
              ("selector_class", selector.to_json()),
              ("write_fields", Json::array(written.map(name => name.to_json()))),
              (
                "permissions",
                if spec.kind is RelationKeyUpsert(update_permission~, ..) {
                  Json::array([
                    permission.to_json(),
                    update_permission.to_json(),
                  ])
                } else {
                  Json::array([permission.to_json()])
                },
              ),
            ]),
          ]),
        ),
        ("required_permissions", Json::array([])),
        ("minimum_approval", approval.to_json()),
        ("row_mapping", object(row_mapping)),
      ],
      "mapping_contract_cid",
      limits,
    )
    Ok({
      resource,
      mapping_ref,
      mapping_cid,
      body: canonical_text(mapping, limits),
      write_fields: written,
      omittable: sources
      .filter(source => source.null_behavior == "omit")
      .map(source => source.target),
    })
  } catch {
    _ => Err(OutputLimit)
  }
}
