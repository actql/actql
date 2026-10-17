///|
pub(all) struct MappingSource {
  target : String
  field : String
  null_behavior : String
} derive(Eq, Debug)

///|
pub(all) struct MappingLimits {
  max_properties : Int
  max_fields : Int
  max_name_bytes : Int
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum MappingIssue {
  InvalidLimits
  BudgetExceeded
  InvalidBinding
  InvalidWrite
  DuplicateField(String)
  Property(PropertyIssue)
  InvalidNullBehavior(String)
  Body(WriteBodyIssue)
} derive(Eq, Debug)

///|
/// Provider-owned derivation of existing mapping_contract DATA. The Host must
/// admit it beside the original Common declaration/manifest, not trust a CID
/// or this candidate as a permission, current observation or executable Run.
pub struct ExecutionMapping {
  priv catalog : PropertyCatalog
  operation : RecordWriteOperation
  priv names : Array[String]
  priv sources : Array[MappingSource]
  mapping_ref : String
  mapping_cid : String
  priv document : @encode.EncodedDocument
}

///|
pub fn execution_mapping_body(mapping : ExecutionMapping) -> String {
  @encode.document_text(mapping.document)
}

///|
pub fn execution_mapping_fields(mapping : ExecutionMapping) -> Array[String] {
  mapping.names.copy()
}

///|
fn mapping_cid_valid(cid : String) -> Bool {
  if !cid.has_prefix("sha256:") || cid.length() != 71 {
    return false
  }
  for index in 7..<71 {
    let unit = cid[index]
    if !((unit >= '0' && unit <= '9') || (unit >= 'a' && unit <= 'f')) {
      return false
    }
  }
  true
}

///|
fn mapping_identifier(value : String, max_bytes : Int) -> Bool {
  !value.is_empty() &&
  value.length() <= max_bytes &&
  @utf8.encode(value).length() <= max_bytes &&
  @canonical.validate_scalar_text(value) is Ok(_)
}

///|
fn mapping_document(
  limits : MappingLimits,
  emit : (@encode.Writer) -> Unit raise @encode.EncodeFailure,
) -> Result[@encode.EncodedDocument, MappingIssue] {
  let writer = @encode.writer(
    limits.max_bytes,
    limits.max_nodes,
    limits.max_depth,
  ) catch {
    _ => return Err(BudgetExceeded)
  }
  try {
    emit(writer)
    Ok(@encode.finish_document(writer))
  } catch {
    _ => {
      @encode.cancel_writer(writer)
      Err(BudgetExceeded)
    }
  }
}

///|
fn mapping_strings(
  writer : @encode.Writer,
  values : Array[String],
) -> Unit raise @encode.EncodeFailure {
  @encode.begin_array(writer)
  for value in values {
    @encode.string_value(writer, value)
  }
  @encode.end_array(writer)
}

///|
/// The manifest CID must be taken by the Host from its actual Common-issued
/// RowDeclaration. The provider derives only a canonical candidate; Common
/// checks that exact manifest/schema/permission rule when preparing the Run.
pub fn prepare_execution_mapping(
  catalog : PropertyCatalog,
  connector_id : String,
  manifest_cid : String,
  resource : String,
  operation : RecordWriteOperation,
  fields : Array[String],
  sources : Array[MappingSource],
  limits : MappingLimits,
) -> Result[ExecutionMapping, MappingIssue] {
  if limits.max_properties <= 0 ||
    limits.max_fields <= 0 ||
    limits.max_name_bytes <= 0 ||
    limits.max_bytes <= 0 ||
    limits.max_nodes <= 0 ||
    limits.max_depth <= 0 {
    return Err(InvalidLimits)
  }
  if catalog.properties.length() > limits.max_properties ||
    fields.length() >= limits.max_fields ||
    sources.length() > limits.max_fields {
    return Err(BudgetExceeded)
  }
  if !mapping_identifier(connector_id, limits.max_name_bytes) ||
    !mapping_identifier(resource, limits.max_name_bytes) ||
    !mapping_cid_valid(manifest_cid) {
    return Err(InvalidBinding)
  }
  if fields.is_empty() {
    return Err(InvalidWrite)
  }
  let names = fields.copy()
  let selected : Map[String, Bool] = Map([])
  for name in names {
    if selected.contains(name) {
      return Err(DuplicateField(name))
    }
    if name == "id" {
      return Err(InvalidWrite)
    }
    selected[name] = true
    match require_property_write(catalog, name) {
      Ok(_) => ()
      Err(issue) => return Err(Property(issue))
    }
  }
  names.sort_by(@canonical.compare_utf16)
  let (kind, selector, key) = match operation {
    Create => ("create", "none", None)
    Update => ("update", "id", None)
    Upsert(key) => {
      match require_unique_property(catalog, key) {
        Ok(_) => ()
        Err(issue) => return Err(Property(issue))
      }
      if key == "id" {
        return Err(InvalidWrite)
      }
      match require_property_write(catalog, key) {
        Ok(_) => ()
        Err(issue) => return Err(Property(issue))
      }
      ("upsert", "key", Some(key))
    }
  }
  if kind != "create" && !sources.is_empty() {
    return Err(InvalidWrite)
  }
  if kind == "create" && sources.length() != names.length() {
    return Err(InvalidWrite)
  }
  let source_names : Map[String, Bool] = Map([])
  for source in sources {
    if !selected.contains(source.target) || source_names.contains(source.target) {
      return Err(DuplicateField(source.target))
    }
    source_names[source.target] = true
    if source.field.is_empty() ||
      source.field.length() > limits.max_name_bytes ||
      @utf8.encode(source.field).length() > limits.max_name_bytes ||
      @canonical.validate_scalar_text(source.field) is Err(_) {
      return Err(InvalidWrite)
    }
    guard property_contract(catalog, source.target) is Ok(contract) else {
      return Err(InvalidWrite)
    }
    if !(source.null_behavior == "reject" ||
      source.null_behavior == "omit" ||
      (source.null_behavior == "write_null" && contract.nullable)) {
      return Err(InvalidNullBehavior(source.target))
    }
  }
  let described = names.copy()
  if key is Some(name) && !selected.contains(name) {
    described.push(name)
  }
  let entries = [
    ("id", @contract.primitive(@contract.StringType, nullable=false)),
  ]
  for name in described {
    match property_contract(catalog, name) {
      Ok(contract) => entries.push((name, contract))
      Err(issue) => return Err(Property(issue))
    }
  }
  let schema = match
    @contract.object_contract(
      entries,
      nullable=false,
      max_fields=limits.max_fields,
      max_name_bytes=limits.max_name_bytes,
    ) {
    Ok(value) => value
    Err(@contract.ConstructionLimit) => return Err(BudgetExceeded)
    Err(_) => return Err(InvalidWrite)
  }
  let schema = match
    mapping_document(limits, writer => @contract.emit_checked(schema, writer)) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let schema_cid = "sha256:" +
    @sha.hex(@utf8.encode(@encode.document_text(schema)))
  let sorted_sources = sources.copy()
  sorted_sources.sort_by((a, b) => @canonical.compare_utf16(a.target, b.target))
  let rows = match
    mapping_document(limits, writer => {
      @encode.begin_ordered_object(writer)
      for source in sorted_sources {
        @encode.ordered_key(writer, source.target)
        @encode.begin_ordered_object(writer)
        @encode.ordered_key(writer, "field")
        @encode.string_value(writer, source.field)
        @encode.ordered_key(writer, "null_behavior")
        @encode.string_value(writer, source.null_behavior)
        @encode.end_object(writer)
      }
      @encode.end_object(writer)
    }) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let request_identity = match
    mapping_document(limits, writer => {
      @encode.begin_ordered_object(writer)
      @encode.ordered_key(writer, "key")
      match key {
        Some(value) => @encode.string_value(writer, value)
        None => @encode.null_value(writer)
      }
      @encode.ordered_key(writer, "kind")
      @encode.string_value(writer, kind)
      @encode.ordered_key(writer, "resource")
      @encode.string_value(writer, resource)
      @encode.ordered_key(writer, "row_mapping")
      @encode.emit_document(writer, rows)
      @encode.ordered_key(writer, "target_schema")
      @encode.emit_document(writer, schema)
      @encode.ordered_key(writer, "write_fields")
      mapping_strings(writer, names)
      @encode.end_object(writer)
    }) {
    Ok(value) => @sha.hex(@utf8.encode(@encode.document_text(value)))
    Err(issue) => return Err(issue)
  }
  let mapping_ref = "mapping:" +
    connector_id +
    "/" +
    resource +
    "/" +
    kind +
    "-" +
    request_identity[:16].to_owned() +
    ".v1"
  let identity = match
    mapping_document(limits, writer => {
      @encode.begin_ordered_object(writer)
      @encode.ordered_key(writer, "boundary_topology")
      @encode.string_value(writer, "connector_connection")
      @encode.ordered_key(writer, "output_field")
      @encode.string_value(writer, "id")
      @encode.ordered_key(writer, "provider_id_field")
      @encode.string_value(writer, "id")
      @encode.ordered_key(writer, "provider_namespace")
      @encode.string_value(writer, "hubspot")
      @encode.ordered_key(writer, "resource_kind")
      @encode.string_value(writer, "object")
      @encode.ordered_key(writer, "version")
      @encode.string_value(writer, "actql.resource_identity/0.1")
      @encode.end_object(writer)
    }) {
    Ok(value) =>
      "sha256:" + @sha.hex(@utf8.encode(@encode.document_text(value)))
    Err(issue) => return Err(issue)
  }
  let emit = (writer : @encode.Writer, own_cid : String?) => {
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "connector_manifest_cid")
    @encode.string_value(writer, manifest_cid)
    @encode.ordered_key(writer, "conversions")
    @encode.begin_array(writer)
    @encode.end_array(writer)
    if own_cid is Some(cid) {
      @encode.ordered_key(writer, "mapping_contract_cid")
      @encode.string_value(writer, cid)
    }
    @encode.ordered_key(writer, "mapping_ref")
    @encode.string_value(writer, mapping_ref)
    @encode.ordered_key(writer, "minimum_approval")
    @encode.string_value(writer, "none")
    @encode.ordered_key(writer, "permission_rules")
    @encode.begin_array(writer)
    @encode.begin_ordered_object(writer)
    @encode.ordered_key(writer, "effect_kind")
    @encode.string_value(writer, kind)
    @encode.ordered_key(writer, "permissions")
    mapping_strings(writer, ["hubspot:objects:batch-" + kind])
    @encode.ordered_key(writer, "selector_class")
    @encode.string_value(writer, selector)
    @encode.ordered_key(writer, "write_fields")
    mapping_strings(writer, names)
    @encode.end_object(writer)
    @encode.end_array(writer)
    @encode.ordered_key(writer, "primary_identity")
    @encode.string_value(writer, "id")
    @encode.ordered_key(writer, "required_fields")
    mapping_strings(writer, [])
    @encode.ordered_key(writer, "required_permissions")
    mapping_strings(writer, [])
    @encode.ordered_key(writer, "resource_identity_cid")
    @encode.string_value(writer, identity)
    @encode.ordered_key(writer, "row_mapping")
    @encode.emit_document(writer, rows)
    @encode.ordered_key(writer, "schema")
    @encode.string_value(writer, "actql.mapping_contract/0.1")
    @encode.ordered_key(writer, "target_ref")
    @encode.string_value(writer, "connector://" + connector_id + "/" + resource)
    @encode.ordered_key(writer, "target_schema")
    @encode.emit_document(writer, schema)
    @encode.ordered_key(writer, "target_schema_identity")
    @encode.string_value(writer, schema_cid)
    @encode.ordered_key(writer, "version")
    @encode.string_value(writer, "hubspot/0.1")
    @encode.ordered_key(writer, "writable_fields")
    mapping_strings(writer, names)
    @encode.end_object(writer)
  }
  let mapping_cid = match
    mapping_document(limits, writer => emit(writer, None)) {
    Ok(value) =>
      "sha256:" + @sha.hex(@utf8.encode(@encode.document_text(value)))
    Err(issue) => return Err(issue)
  }
  let document = match
    mapping_document(limits, writer => emit(writer, Some(mapping_cid))) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    catalog,
    operation,
    names,
    sources: sorted_sources,
    mapping_ref,
    mapping_cid,
    document,
  })
}

///|
pub fn recheck_execution_mapping(
  mapping : ExecutionMapping,
  current : PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, PropertyIssue] {
  recheck_property_catalog(mapping.catalog, current, max_properties)
}

///|
/// Only omission explicitly named by this original create Mapping is allowed.
/// Parsing and retained writer documents overlap; this is not funding evidence.
pub fn prepare_execution_write_body(
  mapping : ExecutionMapping,
  current : PropertyCatalog,
  bytes : Bytes,
  max_properties : Int,
  limits : WriteBodyLimits,
) -> Result[WriteBody, MappingIssue] {
  if !write_body_limits_valid(limits) {
    return Err(Body(InvalidLimits))
  }
  if bytes.length() > limits.max_input_bytes ||
    mapping.names.length() > limits.max_fields {
    return Err(Body(BudgetExceeded))
  }
  match recheck_execution_mapping(mapping, current, max_properties) {
    Ok(_) => ()
    Err(issue) => return Err(Property(issue))
  }
  let source = match
    @source.parse_json_bytes(bytes, {
      max_input_bytes: limits.max_input_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        Body(
          match issue.issue {
            InputLimit | NodeLimit | DepthLimit => BudgetExceeded
            _ => InvalidBody
          },
        ),
      )
  }
  let cursor = match
    @decode.admit(source, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_input_bytes,
      max_total_string_bytes: limits.max_input_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(Body(InvalidBody))
  }
  guard @decode.open_object(cursor) is Ok(object) else {
    return Err(Body(InvalidBody))
  }
  let selected = []
  for name in mapping.names {
    match @decode.field(object, name) {
      Missing =>
        if !mapping.sources.any(value => {
            value.target == name && value.null_behavior == "omit"
          }) {
          return Err(Body(MissingField(name)))
        }
      _ => selected.push(name)
    }
  }
  match prepare_write_body(current, selected, bytes, limits) {
    Ok(value) => Ok(value)
    Err(issue) => Err(Body(issue))
  }
}
