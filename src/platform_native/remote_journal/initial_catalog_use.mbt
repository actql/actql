///|
/// Trusted Host-declared byte envelopes, not measured RSS or a send grant.
/// No defaults or cost coefficients are selected here. The installed Host must
/// supply its reviewed disk/container and simultaneous scratch bounds from the
/// original Run policy before this private preparation path can be enabled.
pub(all) struct NativeInitialCatalogUseEnvelope {
  record_bytes : Int64
  control_bytes : Int64
  workspace_bytes : Int64
}

///|
pub(all) enum NativeInitialCatalogUseIssue {
  Journal(NativeRemoteJournalIssue)
  Capacity(@resources.LedgerIssue)
}

///|
pub(all) struct NativeInitialCatalogUseFailure {
  issue : NativeInitialCatalogUseIssue
  custody : NativeInitialCatalogUseCustody?
}

///|
/// Only the successful first claim transaction constructs this nominal value.
/// Lost claim replies cannot reconstruct a new claim from a stored marker.
/// It carries no read/write/approval, sent, or successful-Provider assertion.
#warnings("-struct_never_constructed")
struct NativeInitialCatalogUseClaim {
  journal : Journal
  request : @remote.DispatchRequest
}

///|
pub fn initial_catalog_use_claim_dispatch(
  value : NativeInitialCatalogUseClaim,
) -> String {
  @remote.dispatch_request_identity(value.request)
}

///|
pub fn initial_catalog_use_claim_matches_journal(
  value : NativeInitialCatalogUseClaim,
  journal : Journal,
) -> Bool {
  physical_equal(value.journal, journal)
}

///|
/// Exact row matching is not a physical-cleanup proof or permission to resend.
pub fn initial_catalog_use_cleanup_row_matches(
  expected : Bytes,
  body : Bytes,
  revision : Int64,
) -> Bool {
  (revision == 0L || revision == 1L) && body == expected
}
