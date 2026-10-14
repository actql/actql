///|
// DATA-only prerequisite for original admission before a live Scope exists.
// Expected limits must come from the independently checked original Run/Host
// installation, never the saved document. This compares configuration only:
// it does not authenticate Store/journal custody, validate all token accounting,
// construct a Ledger, reset usage, issue a claim or permit send/restoration.
// The original Host funds document/tree admission and these transient frames
// before calling. Logical limits and a successful comparison are not funding.
pub fn check_original_current_state_document_configuration(
  document : OriginalCurrentStateDocument,
  limits : LedgerLimits,
  quantity_limits : QuantityAmounts?,
) -> Result[Unit, OriginalStateDocumentIssue] {
  if document.source is None {
    return Err(Terminal)
  }
  if document.state.limits != limits ||
    document.state.quantity_limits != quantity_limits {
    return Err(InvalidRecord)
  }
  // Consumed and uncertain observations can exceed an installed allowance.
  // Preserve the original facts; do not reject them into a fresh zero-usage
  // Ledger or infer new remaining capacity from matching configuration.
  Ok(())
}
