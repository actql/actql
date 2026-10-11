///|
/// No nominal Native custody can be issued on this target.
type NativeInitialCatalogUseCustody

///|
pub fn initial_catalog_use_custody_pending(
  _value : NativeInitialCatalogUseCustody,
) -> Bool {
  false
}

///|
pub fn initial_catalog_use_custody_dispatch(
  _value : NativeInitialCatalogUseCustody,
) -> String {
  abort("Native initial custody is unavailable on this target")
}

///|
pub fn initial_catalog_use_custody_usage(
  _value : NativeInitialCatalogUseCustody,
) -> @resources.LedgerUsage {
  abort("Native initial custody is unavailable on this target")
}

///|
pub fn initial_catalog_use_custody_matches_ledger(
  _value : NativeInitialCatalogUseCustody,
  _ledger : @resources.Ledger,
) -> Bool {
  false
}

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

///|
pub fn Journal::cleanup_initial_catalog_use(
  _self : Journal,
  _custody : NativeInitialCatalogUseCustody,
) -> Result[Unit, NativeInitialCatalogUseIssue] {
  Err(Journal(UnsupportedTarget))
}
