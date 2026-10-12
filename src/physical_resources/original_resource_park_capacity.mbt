///|
// Check the original already funded read envelope while the exact consumer is
// parked. The preparation predicate intentionally remains Reading/Written-only.
// This is non-consuming and does not reserve, restore, unpark or permit sends.
// The installed caller supplies a justified COMPLETE simultaneous envelope,
// including all retained users, metadata/decode/directory and cleanup overlap;
// repeated component checks cannot each claim the full original allowance.
pub fn[T] original_resource_park_read_capacity_covers(
  park : OriginalResourcePark[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  guard original_resource_park_current(park, origin) is Some(_) &&
    park.consumer is Some(consumer) &&
    consumer.claim is Some(claim) else {
    return false
  }
  // Inspect scalar facts of the existing read token rather than constructing
  // a fresh census/snapshot just to check its already reserved envelope.
  claim.read.reservation.serial == claim.read_state.serial &&
  capacity_reservation_matches(
    claim.descriptor.ledger,
    claim.read,
    claim.read_state.retention,
    claim.read_state.execution,
  ) &&
  capacity_reservation_covers(
    claim.descriptor.ledger,
    claim.read,
    retained_bytes,
    execution_bytes,
  )
}
