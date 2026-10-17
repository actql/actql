///|
/// The original Salesforce Catalog producer already generated and bounded
/// these canonical members from its admitted Describe observation. Keep every
/// member byte and identity; generating a provider-neutral Catalog instead
/// would describe a different declaration. Only the row metadata projection
/// is new, with the existing unknown classification of this producer.
pub fn salesforce_row_declaration(
  declaration : @catalog.StaticDeclaration,
) -> Result[@rows.RowDeclaration, InstalledSalesforceIssue] {
  let views = declaration.views.map(view => {
    @rows.declared_row_view(
      view.resource,
      view.source_ref,
      view.view_cid,
      view.fields,
      view.carrier_schema_cid,
      view.data_policy_cid,
    )
  })
  @rows.project_row_declaration(
    declaration.connector_id,
    connector_registration,
    declaration.connector_version,
    declaration.catalog,
    declaration.catalog_cid,
    declaration.contracts,
    views,
    declaration.view_bodies,
    declaration.manifest_entry,
    declaration.manifest_entry_cid,
  ).map_err(issue => Row(@rows.RowHostIssue::Declaration(issue)))
}

///|
/// The Host bridge accepts only this Site's already-restored opaque
/// Salesforce declaration. It does not accept serialized projection parts,
/// reconstruct an original from equal CIDs, or establish current authority.
pub fn installed_salesforce_row_declaration(
  declaration : InstalledSalesforceDeclaration,
) -> Result[@rows.RowDeclaration, InstalledSalesforceIssue] {
  salesforce_row_declaration(declaration.declaration)
}
