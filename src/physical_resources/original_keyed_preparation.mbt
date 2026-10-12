///|
// The existing opaque census authenticates its own single captured child.
// This is a phase/lifetime prerequisite, not capture evidence or byte funding.
// Local still checks its exact Row capture against these nominal tokens.
pub fn original_ledger_captured_preparation_available(
  identity : OriginalLedgerIdentity,
) -> Bool {
  guard original_ledger_preparation_available(identity) &&
    identity.ledger.original_inventory is Some(value) &&
    value.reservations.length() == 1 && value.holdings.length() == 1 else {
    return false
  }
  original_captured_prefix_available(
    identity.ledger, value.reservations[0], value.holdings[0],
  )
}
