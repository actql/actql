///|
pub fn Journal::read_funded_initial_catalog_use(
  _self : Journal,
  _custody : NativeInitialCatalogUseCustody,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::claim_funded_initial_catalog_use(
  _self : Journal,
  _custody : NativeInitialCatalogUseCustody,
) -> Result[NativeInitialCatalogUseClaim, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}
