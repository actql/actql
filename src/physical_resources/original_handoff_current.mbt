///|
/// Observe only this existing consumer's handed-off lifetime. The Model may
/// have spent work/quantities or acquired further resources, so its current
/// aggregate is not the initial read snapshot. The original bootstrap, input
/// tokens and exact read reservation must still be live and unchanged, except
/// that the same producer reservation may have completed into its still-live
/// original output holding. That transition grants no new capacity or ACK.
/// This is not a new read claim, restored Ledger or dispatch permission.
pub fn[T] funded_read_consumer_handed_off_origin(
  value : FundedReadConsumer[T],
) -> T? {
  if value.claim is Some(claim) && claim.children is Some(_) {
    return original_read_child_origin(claim, value, true)
  }
  guard value.claim is Some(claim) &&
    claim.phase is ConsumerHandedOff(current) &&
    physical_equal(current, value) &&
    check_original_resources_mutable(claim.descriptor.ledger) is Ok(_) &&
    capacity_reservation_open(claim.read) &&
    capacity_reservation_open(claim.descriptor.bootstrap) &&
    original_reservation_snapshot(claim.read.reservation) == claim.read_state &&
    original_tokens_match(claim.descriptor, completed_outputs=true) else {
    return None
  }
  Some(claim.descriptor.origin)
}
