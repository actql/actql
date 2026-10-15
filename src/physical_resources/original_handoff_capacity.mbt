///|
// Observe this same entered/handed-off read token, not the historical initial
// aggregate and not another reservation. Physical acquisition still needs a
// complete trusted simultaneous envelope and the original caller's currentness.
pub fn[T] funded_read_consumer_handed_off_capacity_covers(
  value : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  guard funded_read_consumer_handed_off_origin(value) is Some(current) &&
    physical_equal(current, origin) &&
    value.claim is Some(claim) else {
    return false
  }
  capacity_reservation_covers(
    claim.descriptor.ledger,
    claim.read,
    retained_bytes,
    execution_bytes,
  )
}
