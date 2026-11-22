///|
/// The original Form, key, and field rules stay together through lookup.
pub struct RecordKeyUpsertMapping {
  priv mut self : RecordKeyUpsertMapping?
  priv original : RecordDeclaration
  priv key : String
  priv mapping : @rows.RowMapping
  priv fields : Array[@rows.RowMappingSource]
}

///|
/// Bind the actual Form key and required create fields to the retained
/// Relation. Both physical branches require their original permissions.
pub fn prepare_record_key_upsert_mapping(
  original : RecordDeclaration,
  resource : String,
  key : String,
  sources : Array[@rows.RowMappingSource],
  limits : @rows.RowDeclarationLimits,
) -> Result[RecordKeyUpsertMapping, @rows.RowMappingIssue] {
  if original.declaration.connector_registration != "kintone" ||
    limits.max_fields <= 0 ||
    sources.length() > limits.max_fields {
    return Err(InvalidSpecification)
  }
  if key.length() > limits.max_bytes {
    return Err(OutputLimit)
  }
  guard @catalog.require_record_text_lookup_key(original.catalog, key) is Ok(_) else {
    return Err(InvalidSpecification)
  }
  guard @catalog.record_write_field_contract(original.catalog, key) is Some(_) else {
    return Err(FieldNotWritable(key))
  }
  let required = match
    @catalog.record_create_required_fields(
      original.catalog,
      limits.max_fields,
      limits.max_nodes,
    ) {
    Ok(value) => value.filter(name => name != key)
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
  let mapping = match
    @rows.prepare_relation_row_write_mapping(
      original.declaration,
      resource,
      key,
      {
        kind: @rows.RelationKeyUpsert(
          native_identity="$id",
          update_permission="kintone:records:update",
        ),
        writable_fields: writable,
        required_fields: required,
        permission: "kintone:records:create",
        approval: "required",
      },
      sources,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let selected : RecordKeyUpsertMapping = {
    self: None,
    original,
    key,
    mapping,
    fields: sources.copy(),
  }
  selected.self = Some(selected)
  Ok(selected)
}

///|
/// Immutable Mapping body and its schema facts; authority remains with the Host.
pub fn record_key_upsert_mapping(
  value : RecordKeyUpsertMapping,
) -> @rows.RowMapping {
  value.mapping
}
