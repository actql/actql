///|
/// Complete typed counter observation, not a Ledger mutation or authority.
/// Spent planning/attempt/transfer and historical peak are intentionally kept
/// out of this pending-resource projection. Any other nonzero field, including
/// unresolved transfer and zero-byte live tokens, remains pending. A false
/// result proves neither physical stop, pristine serials nor original custody.
pub fn ledger_usage_has_pending_resources(usage : LedgerUsage) -> Bool {
  let pending = {
    ..usage,
    planning_work: 0,
    attempts: 0,
    transferred_bytes: 0L,
    peak_retention_bytes: 0L,
  }
  pending != initial_ledger_usage
}
