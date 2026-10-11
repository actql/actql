///|
pub fn Journal::accept_with_initial_catalog_use(
  _self : Journal,
  _request : @remote.DispatchRequest,
  _original_run_ledger : @resources.Ledger,
  _envelope : NativeInitialCatalogUseEnvelope,
) -> Result[
  (
    @remote.DispatchAcceptance,
    @remote.DispatchRecord,
    NativeInitialCatalogUseCustody?,
  ),
  NativeInitialCatalogUseFailure,
] {
  Err({ issue: Journal(UnsupportedTarget), custody: None, })
}

///|
pub fn Journal::claim_initial_catalog_use(
  _self : Journal,
  _request : @remote.DispatchRequest,
) -> Result[NativeInitialCatalogUseClaim, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}

///|
pub fn Journal::retain_initial_catalog_use(
  _self : Journal,
  _claim : NativeInitialCatalogUseClaim,
  _original_grant : @credential.RemoteCredentialGrant,
  _original_use : @credential.RemoteCredentialUse,
) -> Result[Unit, NativeRemoteJournalIssue] {
  Err(UnsupportedTarget)
}
