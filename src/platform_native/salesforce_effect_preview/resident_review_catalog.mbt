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
  let binding = catalog.binding
  binding.site_key == site_key &&
  binding.site_generation.to_string() == site_generation &&
  binding.run_invocation_cid == invocation_cid &&
  binding.dispatch_request_cid == dispatch_cid
}
