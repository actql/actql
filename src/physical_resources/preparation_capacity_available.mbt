///|
/// Diagnostic scalars for this same original token, not a reservation or grant.
/// Available includes this token's existing debit, excluding other live owners.
/// No imported callback runs and no mutable Ledger or token escapes.
pub fn[I, P] preparation_capacity_available(
  owner : PreparationCapacity[I, P],
  input : I,
) -> Result[(Int64, Int64), PreparationCapacityIssue] {
  guard owner.input is Some(original) &&
    physical_equal(original, input) &&
    physical_equal(owner.ledger, owner.reservation.reservation.owner) else {
    return Err(ForeignOriginal)
  }
  let token = owner.reservation.reservation
  if !token.open || owner.phase == Closed {
    return Err(Retired)
  }
  let usage = owner.ledger.usage
  Ok(
    (
      owner.ledger.limits.retained_bytes -
      usage.held_bytes -
      usage.reserved_retention_bytes +
      token.retention,
      owner.ledger.limits.execution_bytes -
      usage.reserved_execution_bytes +
      token.execution,
    ),
  )
}
