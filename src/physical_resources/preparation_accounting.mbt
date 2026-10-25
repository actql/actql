///|
/// Read-only scalar snapshot of this original preparation's existing Ledger.
/// No Ledger, reservation, Resource or mutable usage record escapes. Peak is
/// the Ledger's retention peak; execution has no stored peak counter, so tests
/// must call their sequence of observations an observed maximum, not peakE.
pub fn[I, P] preparation_capacity_accounting(
  owner : PreparationCapacity[I, P],
) -> (Int64, Int64, Int64, Int64, Int64, Int64) {
  let usage = owner.ledger.usage
  (
    usage.reserved_retention_bytes,
    usage.reserved_execution_bytes,
    usage.held_bytes,
    usage.peak_retention_bytes,
    if owner.reservation.reservation.open {
      owner.reservation.reservation.retention
    } else {
      0L
    },
    if owner.reservation.reservation.open {
      owner.reservation.reservation.execution
    } else {
      0L
    },
  )
}
