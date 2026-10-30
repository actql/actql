///|
/// The same original Form and Relation beside a CREATE Mapping. Required
/// fields and immutable write/omit inventories remain DATA, not permission,
/// a targeted Preview, an insertion claim or provider default values.
pub struct RecordCreateMapping {
  priv mut self : RecordCreateMapping?
  priv original : RecordDeclaration
  priv mapping : @rows.RowMapping
  priv written_fields : Array[String]
  priv omitted_fields : Array[String]
  priv required_fields : Array[String]
}

///|
pub fn prepare_record_create_mapping(
  original : RecordDeclaration,
  resource : String,
  sources : Array[@rows.RowMappingSource],
  approval : String,
  limits : @rows.RowDeclarationLimits,
) -> Result[RecordCreateMapping, @rows.RowMappingIssue] {
  if original.declaration.connector_registration != "kintone" ||
    limits.max_fields <= 0 ||
    sources.length() > limits.max_fields {
    return Err(InvalidSpecification)
  }
  let required = match
    @catalog.record_create_required_fields(
      original.catalog,
      limits.max_fields,
      limits.max_nodes,
    ) {
    Ok(value) => value
    Err(@catalog.FieldUnavailable(name)) => return Err(FieldNotWritable(name))
    Err(@catalog.BudgetExceeded) => return Err(OutputLimit)
    Err(_) => return Err(InvalidSpecification)
  }
  let writable = []
  for source in sources {
    guard @catalog.record_write_field_contract(original.catalog, source.target)
      is Some(_) else {
      return Err(FieldNotWritable(source.target))
    }
    writable.push(source.target)
  }
  for name in required {
    if !writable.contains(name) {
      return Err(MissingRequiredField(name))
    }
  }
  match
    @rows.prepare_relation_row_write_mapping(
      original.declaration,
      resource,
      "$id",
      {
        kind: @rows.RelationCreate,
        writable_fields: writable,
        required_fields: required,
        permission: "kintone:records:create",
        approval,
      },
      sources,
      limits,
    ) {
    Ok(mapping) => {
      let result : RecordCreateMapping = {
        self: None,
        original,
        mapping,
        written_fields: mapping.write_fields.copy(),
        omitted_fields: mapping.omittable.copy(),
        required_fields: required.copy(),
      }
      result.self = Some(result)
      Ok(result)
    }
    Err(issue) => Err(issue)
  }
}

///|
/// The original constructor result, not a copy retaining its private fields.
/// This nominal check is DATA provenance, not permission or current authority.
pub fn record_create_mapping_is_original(value : RecordCreateMapping) -> Bool {
  value.self is Some(original) && physical_equal(original, value)
}

///|
pub fn record_create_mapping(value : RecordCreateMapping) -> @rows.RowMapping {
  value.mapping
}

///|
pub fn record_create_mapping_matches_declaration(
  value : RecordCreateMapping,
  original : RecordDeclaration,
) -> Bool {
  record_create_mapping_is_original(value) &&
  physical_equal(value.original, original)
}

///|
/// Only the same physical original Form and complete intended field inventory
/// correspond. Omitted optional fields stay omitted; no default is injected.
pub fn record_create_mapping_matches_request(
  value : RecordCreateMapping,
  request : @catalog.RecordCreateRequest,
) -> Bool {
  record_create_mapping_is_original(value) &&
  @catalog.record_create_request_is_original(request) &&
  @catalog.record_create_request_values(request).all(write => {
    let written = @catalog.record_write_values_fields(write)
    @catalog.record_write_values_match_catalog(write, value.original.catalog) &&
    written.all(name => value.written_fields.contains(name)) &&
    value.written_fields.all(name => {
      written.contains(name) || value.omitted_fields.contains(name)
    }) &&
    value.required_fields.all(name => written.contains(name))
  })
}

///|
/// Logical resource from this same original Mapping, not a resource grant.
pub fn record_create_mapping_resource(
  mapping : RecordCreateMapping,
) -> Result[String, RecordCreateExecutionIssue] {
  if !record_create_mapping_is_original(mapping) {
    return Err(MappingMismatch)
  }
  Ok(mapping.mapping.resource)
}
