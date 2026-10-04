// Provider-neutral execution Mappings for installed row sources. A connector
// declares, in its own JSON, which Resources it can create rows in: the
// target schema, the primary identity the provider assigns, the fields a
// create writes and must write, and the permission the write needs. The
// common runtime generates (and on every load regenerates) the canonical
// `actql.mapping_contract/0.1` body, so the Host never trusts a
// connector-computed Mapping CID.

///|
pub(all) struct RowWriteSpec {
  resource : String
  resource_kind : String
  primary_identity : String
  fields : Array[RowField]
  create_fields : Array[String]
  required_fields : Array[String]
  permission : String
} derive(Eq, Debug)

///|
/// One target field of a create, written from a field of the Effect's source
/// result. `null_behavior` is "reject", "write_null" or "omit".
pub(all) struct RowMappingSource {
  target : String
  field : String
  null_behavior : String
} derive(Eq, Debug)

///|
pub struct RowMapping {
  resource : String
  mapping_ref : String
  mapping_cid : String
  body : String
  write_fields : Array[String]
  omittable : Array[String]
}

///|
pub(all) enum RowMappingIssue {
  InvalidSpecification
  NotWritable(String)
  EmptyWrite
  DuplicateField(String)
  FieldNotWritable(String)
  MissingRequiredField(String)
  InvalidNullBehavior(String)
  OutputLimit
} derive(Eq, Debug)

///|
fn spec_strings(value : Json?) -> Array[String]? {
  guard value is Some(Array(items)) else { return None }
  let out = []
  for item in items {
    guard item is String(text) else { return None }
    out.push(text)
  }
  Some(out)
}

///|
/// Parse a connector's write specification:
/// `{"writes":[{"resource","resource_kind","primary_identity","fields":[...],
/// "create":{"fields":[...],"required":[...],"permission":"..."}}]}`.
fn parse_row_writes(text : String) -> Array[RowWriteSpec]? {
  let parsed = @json.parse(text) catch { _ => return None }
  guard parsed is Object(root) &&
    root.length() == 1 &&
    root.get("writes") is Some(Array(writes)) else {
    return None
  }
  let specs = []
  for write in writes {
    guard write is Object(entries) &&
      entries.length() == 5 &&
      spec_text(write, "resource") is Some(resource) &&
      spec_text(write, "resource_kind") is Some(resource_kind) &&
      spec_text(write, "primary_identity") is Some(primary_identity) &&
      entries.get("fields") is Some(Array(fields)) &&
      entries.get("create") is Some(Object(create)) &&
      create.length() == 3 &&
      spec_strings(create.get("fields")) is Some(create_fields) &&
      spec_strings(create.get("required")) is Some(required_fields) &&
      create.get("permission") is Some(String(permission)) else {
      return None
    }
    let declared = []
    for field in fields {
      guard field is Object(members) &&
        members.length() == 3 &&
        spec_text(field, "name") is Some(name) &&
        spec_text(field, "type") is Some(value_type) &&
        members.get("nullable") is Some(nullable) else {
        return None
      }
      let flag = match nullable {
        True => true
        False => false
        _ => return None
      }
      declared.push({ name, value_type, nullable: flag, })
    }
    specs.push({
      resource,
      resource_kind,
      primary_identity,
      fields: declared,
      create_fields,
      required_fields,
      permission,
    })
  }
  Some(specs)
}

///|
fn check_write_spec(spec : RowWriteSpec) -> Bool {
  let names = spec.fields.map(field => field.name)
  valid_name(spec.resource, 255) &&
  valid_name(spec.resource_kind, 64) &&
  !spec.fields.is_empty() &&
  spec.fields.all(field => {
    valid_name(field.name, 255) && supported_type(field.value_type)
  }) &&
  names.length() ==
  ({
    let unique = []
    for name in names {
      if !unique.contains(name) {
        unique.push(name)
      }
    }
    unique.length()
  }) &&
  spec.fields.any(field => {
    field.name == spec.primary_identity && !field.nullable
  }) &&
  !spec.create_fields.is_empty() &&
  spec.create_fields.all(name => {
    names.contains(name) && name != spec.primary_identity
  }) &&
  spec.required_fields.all(name => spec.create_fields.contains(name)) &&
  !spec.permission.is_empty() &&
  spec.permission.length() <= 128
}

///|
/// The Mapping of one create from an Effect's source result into a declared
/// writable Resource of `declaration`'s connector.
pub fn prepare_row_mapping(
  declaration : RowDeclaration,
  writes_json : String,
  resource : String,
  sources : Array[RowMappingSource],
) -> Result[RowMapping, RowMappingIssue] {
  guard parse_row_writes(writes_json) is Some(specs) else {
    return Err(InvalidSpecification)
  }
  guard specs.search_by(spec => spec.resource == resource) is Some(index) else {
    return Err(NotWritable(resource))
  }
  let spec = specs[index]
  if !check_write_spec(spec) {
    return Err(InvalidSpecification)
  }
  if sources.is_empty() {
    return Err(EmptyWrite)
  }
  let targets = []
  for source in sources {
    if targets.contains(source.target) {
      return Err(DuplicateField(source.target))
    }
    targets.push(source.target)
    if !spec.create_fields.contains(source.target) {
      return Err(FieldNotWritable(source.target))
    }
    guard spec.fields.search_by(field => field.name == source.target)
      is Some(field_index) else {
      return Err(FieldNotWritable(source.target))
    }
    let field = spec.fields[field_index]
    let valid = match source.null_behavior {
      "reject" => true
      "write_null" => field.nullable
      "omit" => !spec.required_fields.contains(source.target)
      _ => false
    }
    if !valid || source.field.is_empty() {
      return Err(InvalidNullBehavior(source.target))
    }
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
  let schema_fields = [spec.primary_identity, ..written].map(name => {
    let field = spec.fields[spec.fields
      .search_by(item => item.name == name)
      .unwrap()]
    (
      name,
      object([
        ("nullable", Json::boolean(field.nullable)),
        ("type", field.value_type.to_json()),
      ]),
    )
  })
  let target_schema = object([
    ("type", "object".to_json()),
    ("nullable", false.to_json()),
    ("additional_properties", false.to_json()),
    ("fields", object(schema_fields)),
  ])
  let row_mapping = sources.map(source => {
    (
      source.target,
      object([
        ("field", source.field.to_json()),
        ("null_behavior", source.null_behavior.to_json()),
      ]),
    )
  })
  let resource_identity = object([
    ("version", "actql.resource_identity/0.1".to_json()),
    ("provider_namespace", declaration.connector_registration.to_json()),
    ("resource_kind", spec.resource_kind.to_json()),
    ("provider_id_field", spec.primary_identity.to_json()),
    ("output_field", spec.primary_identity.to_json()),
    ("boundary_topology", "connector_connection".to_json()),
  ])
  try {
    let request_identity = canonical_cid(
      object([
        ("resource", resource.to_json()),
        ("kind", "create".to_json()),
        ("key", Json::null()),
        ("target_schema", target_schema),
        ("write_fields", Json::array(written.map(name => name.to_json()))),
        ("row_mapping", object(row_mapping)),
      ]),
      declaration_limits,
    )
    let mapping_ref = "mapping:" +
      declaration.connector_id +
      "/" +
      resource +
      "/create-" +
      request_identity[7:23].to_owned() +
      ".v1"
    let (mapping, mapping_cid) = seal(
      [
        ("schema", "actql.mapping_contract/0.1".to_json()),
        ("mapping_ref", mapping_ref.to_json()),
        ("version", declaration.connector_version.to_json()),
        (
          "target_ref",
          ("connector://" + declaration.connector_id + "/" + resource).to_json(),
        ),
        ("connector_manifest_cid", declaration.manifest_entry_cid.to_json()),
        (
          "resource_identity_cid",
          canonical_cid(resource_identity, declaration_limits).to_json(),
        ),
        ("target_schema", target_schema),
        (
          "target_schema_identity",
          canonical_cid(target_schema, declaration_limits).to_json(),
        ),
        ("primary_identity", spec.primary_identity.to_json()),
        ("writable_fields", Json::array(written.map(name => name.to_json()))),
        ("required_fields", Json::array(required.map(name => name.to_json()))),
        ("conversions", Json::array([])),
        (
          "permission_rules",
          Json::array([
            object([
              ("effect_kind", "create".to_json()),
              ("selector_class", "none".to_json()),
              ("write_fields", Json::array(written.map(name => name.to_json()))),
              ("permissions", Json::array([spec.permission.to_json()])),
            ]),
          ]),
        ),
        ("required_permissions", Json::array([])),
        ("minimum_approval", "none".to_json()),
        ("row_mapping", object(row_mapping)),
      ],
      "mapping_contract_cid",
      declaration_limits,
    )
    let omittable = sources
      .filter(source => source.null_behavior == "omit")
      .map(source => source.target)
    Ok({
      resource,
      mapping_ref,
      mapping_cid,
      body: canonical_text(mapping, declaration_limits),
      write_fields: written,
      omittable,
    })
  } catch {
    _ => Err(OutputLimit)
  }
}
