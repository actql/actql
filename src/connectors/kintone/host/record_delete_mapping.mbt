///|
/// Existing Mapping DATA held beside the same original Form/declaration.
/// This is not a new Site, dispatch issuer, current proof or release Owner.
pub struct RecordDeleteMapping {
  priv original : RecordDeclaration
  priv mapping : @rows.RowMapping
}

///|
pub fn prepare_record_delete_mapping(
  original : RecordDeclaration,
  resource : String,
  approval : String,
  limits : @rows.RowDeclarationLimits,
) -> Result[RecordDeleteMapping, @rows.RowMappingIssue] {
  if original.declaration.connector_registration != "kintone" {
    return Err(InvalidSpecification)
  }
  match
    @rows.prepare_row_delete_mapping(
      original.declaration,
      resource,
      "$id",
      "kintone:records:delete",
      approval,
      limits,
    ) {
    Ok(mapping) => Ok({ original, mapping, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn record_delete_mapping(
  original : RecordDeleteMapping,
) -> @rows.RowMapping {
  original.mapping
}

///|
pub fn record_delete_mapping_matches_declaration(
  mapping : RecordDeleteMapping,
  original : RecordDeclaration,
) -> Bool {
  physical_equal(mapping.original, original)
}

///|
/// Same original App/Form correspondence only. Equal decoded Form bytes or a
/// Record Number cannot reconstruct the Catalog retained by a mutation page.
/// Authority, Preview/version/current and the durable claim remain separate.
pub fn record_delete_mapping_matches_request(
  mapping : RecordDeleteMapping,
  request : @catalog.RecordDeleteRequest,
) -> Bool {
  @catalog.record_delete_request_targets(request).all(target => {
    record_delete_mapping_page_matches(
      mapping,
      @catalog.original_record_target_page(target),
    )
  })
}

///|
fn record_delete_mapping_page_matches(
  mapping : RecordDeleteMapping,
  page : @catalog.OriginalRecordPage,
) -> Bool {
  guard mapping.original.declaration.views.search_by(view => {
      view.resource == mapping.mapping.resource
    })
    is Some(index) else {
    return false
  }
  let expected = mapping.original.declaration.views[index].fields.filter(name => {
    name != "$id"
  })
  let names = @catalog.record_page_columns(page)
  names.length() == expected.length() &&
  names.all(name => expected.contains(name)) &&
  @catalog.record_page_uses_catalog(page, mapping.original.catalog)
}
