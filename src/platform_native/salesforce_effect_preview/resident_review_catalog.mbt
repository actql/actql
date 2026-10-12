///|
/// Catalog custody is specific to the original Run and consumer dispatch.
/// A matching declaration or mapping does not turn another observation's
/// scope into this one. This check grants no Provider or Effect authority.
fn native_review_catalog_matches_original(
  catalog : @catalog.CatalogObservation,
  site_key : String,
  site_generation : String,
  invocation_cid : String,
  dispatch_cid : String,
) -> Bool {
  native_review_catalog_binding_matches_original(
    catalog.binding,
    site_key,
    site_generation,
    invocation_cid,
    dispatch_cid,
  )
}

///|
fn native_review_catalog_binding_matches_original(
  binding : @catalog.CatalogExecutionBinding,
  site_key : String,
  site_generation : String,
  invocation_cid : String,
  dispatch_cid : String,
) -> Bool {
  match binding {
    @catalog.SiteCatalog(original) =>
      original.site_key == site_key &&
      original.site_generation.to_string() == site_generation &&
      original.run_invocation_cid == invocation_cid &&
      original.dispatch_request_cid == dispatch_cid
    @catalog.DirectLocalCatalog(_) => false
  }
}

///|
/// Resident creation uses the original Site Catalog. A Direct Local origin
/// alone cannot supply the missing Site/dispatch custody.
fn native_resident_catalog_create_origin(
  binding : @catalog.CatalogExecutionBinding,
) -> Result[String, NativeResidentEffectWriteIssue] {
  match binding {
    @catalog.SiteCatalog(original) => Ok(original.resource_origin)
    @catalog.DirectLocalCatalog(_) => Err(ForeignRequest)
  }
}
