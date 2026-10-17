///|
/// Static Mapping DATA held beside the same original Form/Relation. Current,
/// Preview, claim, response holding and actual cleanup remain separate duties.
pub struct RecordUpdateMapping {
  priv original : RecordDeclaration
  priv mapping : @rows.RowMapping
}

///|
pub fn prepare_record_update_mapping(
  original : RecordDeclaration,
  resource : String,
  sources : Array[@rows.RowMappingSource],
  approval : String,
  limits : @rows.RowDeclarationLimits,
) -> Result[RecordUpdateMapping, @rows.RowMappingIssue] {
  if original.declaration.connector_registration != "kintone" ||
    limits.max_fields <= 0 ||
    sources.length() > limits.max_fields {
    return Err(InvalidSpecification)
  }
  let writable = []
  for source in sources {
    guard @catalog.record_write_field_contract(original.catalog, source.target)
      is Some(_) else {
      return Err(FieldNotWritable(source.target))
    }
    writable.push(source.target)
  }
  match
    @rows.prepare_relation_row_write_mapping(
      original.declaration,
      resource,
      "$id",
      {
        kind: @rows.RelationUpdate,
        writable_fields: writable,
        required_fields: [],
        permission: "kintone:records:update",
        approval,
      },
      sources,
      limits,
    ) {
    Ok(mapping) => Ok({ original, mapping, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn record_update_mapping(value : RecordUpdateMapping) -> @rows.RowMapping {
  value.mapping
}

///|
pub fn record_update_mapping_matches_declaration(
  value : RecordUpdateMapping,
  original : RecordDeclaration,
) -> Bool {
  physical_equal(value.original, original)
}

///|
/// The physical caller still binds request/response to its original authorized
/// claim. A matched ID/revision/request is neither permission nor Effect commit.
pub fn record_update_mapping_matches_request(
  value : RecordUpdateMapping,
  request : @catalog.RecordUpdateRequest,
) -> Bool {
  guard value.original.declaration.views.search_by(view => {
      view.resource == value.mapping.resource
    })
    is Some(index) else {
    return false
  }
  let expected = value.original.declaration.views[index].fields.filter(name => {
    name != "$id"
  })
  @catalog.record_update_request_values(request).all(pair => {
    let (target, write) = pair
    let page = @catalog.original_record_target_page(target)
    let names = @catalog.record_page_columns(page)
    let written = @catalog.record_write_values_fields(write)
    @catalog.record_page_uses_catalog(page, value.original.catalog) &&
    names.length() == expected.length() &&
    names.all(name => expected.contains(name)) &&
    @catalog.record_write_values_match_catalog(write, value.original.catalog) &&
    written.all(name => value.mapping.write_fields.contains(name)) &&
    value.mapping.write_fields.all(name => {
      written.contains(name) || value.mapping.omittable.contains(name)
    })
  })
}
