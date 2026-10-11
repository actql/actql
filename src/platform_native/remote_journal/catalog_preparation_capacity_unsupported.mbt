///|
pub fn Journal::read_catalog_preparation_capacity(
  _self : Journal,
  _custody : NativeInitialCatalogUseCustody,
  _required : NativeInitialCatalogUseEnvelope,
) -> Result[Unit, NativeInitialCatalogUseIssue] {
  Err(Journal(UnsupportedTarget))
}
