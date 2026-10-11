///|
/// Trusted Host-declared byte envelopes, not measured RSS or a send grant.
/// No defaults or cost coefficients are selected here. The installed Host must
/// supply its reviewed disk/container and simultaneous scratch bounds from the
/// original Run policy before this private preparation path can be enabled.
pub(all) struct NativeInitialCatalogUseEnvelope {
  record_bytes : Int64
  retained_bytes : Int64
  workspace_bytes : Int64
}

///|
fn initial_catalog_use_envelope_valid(
  value : NativeInitialCatalogUseEnvelope,
) -> Bool {
  value.record_bytes > 0L &&
  value.retained_bytes >= value.record_bytes &&
  value.workspace_bytes > 0L
}

///|
/// This projection retains an existing Ledger reservation through failed or
/// uncertain persistence. It is not another capacity Owner or permission.
/// The caller must keep this original responsibility through confirmed cleanup;
/// no public settlement shortcut is supplied by this preparation unit.
#warnings("-struct_never_constructed")
struct NativeInitialCatalogUseCustody {
  ledger : @resources.Ledger
  reservation : @resources.CapacityReservation
  dispatch_cid : String
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
pub fn initial_catalog_use_custody_pending(
  value : NativeInitialCatalogUseCustody,
) -> Bool {
  @resources.capacity_reservation_open(value.reservation)
}

///|
/// Informational projections of the same charged original responsibility.
/// Neither exposes a settlement handle or a send permission.
pub fn initial_catalog_use_custody_usage(
  value : NativeInitialCatalogUseCustody,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(value.ledger)
}

///|
pub fn initial_catalog_use_custody_dispatch(
  value : NativeInitialCatalogUseCustody,
) -> String {
  value.dispatch_cid
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
