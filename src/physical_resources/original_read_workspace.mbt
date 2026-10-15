///|
// Borrowed coherence of an already funded read and an already reserved
// workspace. This is not another grant, reservation or execution Owner.
// Both resident references, including None, need the installing envelope.
struct OriginalReadWorkspaceBinding[T] {
  mut claim : FundedReadClaim[T]?
  mut capacity : SharedCapacity?
}

///|
pub fn[T] issue_original_read_workspace_binding(
  claim : FundedReadClaim[T],
  origin : T,
  capacity : SharedCapacity,
) -> Result[OriginalReadWorkspaceBinding[T], OriginalReadIssue] {
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if !physical_equal(capacity.ledger, claim.descriptor.ledger) ||
    !physical_equal(capacity.reservation.owner, claim.descriptor.ledger) {
    return Err(Resource(ForeignOwner))
  }
  if capacity.closing || !reservation_open(capacity.reservation) {
    return Err(CleanupPending)
  }
  if !funded_read_available(claim, origin) {
    return Err(ChangedOriginalState)
  }
  // The workspace must precede descriptor/read issuance. The bootstrap or
  // an equal-sized foreign reservation is not this recorded workspace.
  if !claim.descriptor.reservations.any(pair => {
      physical_equal(pair.0, capacity.reservation)
    }) {
    return Err(IncompleteInventory)
  }
  Ok({ claim: Some(claim), capacity: Some(capacity), })
}

///|
pub fn[T] original_read_workspace_binding_current(
  binding : OriginalReadWorkspaceBinding[T],
  origin : T,
  capacity : SharedCapacity,
) -> Bool {
  guard binding.claim is Some(claim) && binding.capacity is Some(original) else {
    return false
  }
  physical_equal(original, capacity) &&
  !capacity.closing &&
  reservation_open(capacity.reservation) &&
  funded_read_available(claim, origin)
}

///|
// Return only the same existing opaque claim. No Ledger, reservation,
// capacity, Origin getter or serializable restoration authority is exposed.
pub fn[T] borrow_original_read_workspace_claim(
  binding : OriginalReadWorkspaceBinding[T],
  origin : T,
  capacity : SharedCapacity,
) -> FundedReadClaim[T]? {
  if original_read_workspace_binding_current(binding, origin, capacity) {
    binding.claim
  } else {
    None
  }
}

///|
// Retire references only; no stop, settlement, credit or bootstrap return.
// Failed retirement keeps the same graph. The physical Host separately
// verifies its original Loan's actual stop/cleanup/settled observations.
pub fn[T] retire_original_read_workspace_binding(
  binding : OriginalReadWorkspaceBinding[T],
  origin : T,
  capacity : SharedCapacity,
) -> Result[Unit, OriginalReadIssue] {
  guard binding.claim is Some(claim) && binding.capacity is Some(original) else {
    return Err(SpentClaim)
  }
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if !physical_equal(original, capacity) {
    return Err(Resource(ForeignOwner))
  }
  if !(claim.phase is Reclaimed) ||
    !capacity.closing ||
    reservation_open(capacity.reservation) ||
    capacity.allocated != 0L {
    return Err(CleanupPending)
  }
  binding.claim = None
  binding.capacity = None
  Ok(())
}
