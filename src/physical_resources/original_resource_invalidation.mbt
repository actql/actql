///|
// One intent on the original park, not a COMMIT receipt, permission, resource
// token, separate Owner or Ledger. The original Run funds this control and
// both reference directions before use, including Unknown/cleanup overlap.
struct OriginalResourceInvalidationRequest[T] {
  mut park : OriginalResourcePark[T]?
}

///|
pub fn[T] begin_original_resource_invalidation(
  park : OriginalResourcePark[T],
  origin : T,
) -> Result[OriginalResourceInvalidationRequest[T], OriginalReadIssue] {
  guard original_resource_park_current(park, origin) is Some(_) else {
    return Err(ChangedOriginalState)
  }
  if park.invalidation is Some(_) {
    return Err(SpentClaim)
  }
  let request : OriginalResourceInvalidationRequest[T] = { park: Some(park), }
  park.invalidation = Some(request)
  Ok(request)
}

///|
// Exact nominal request/park/currentness, not data equality or a caller Bool.
// Pending/Unknown COMMIT leaves this original request unchanged and current.
pub fn[T] original_resource_invalidation_current(
  request : OriginalResourceInvalidationRequest[T],
  park : OriginalResourcePark[T],
  origin : T,
) -> OriginalResourceInvalidationRequest[T]? {
  guard request.park is Some(original) &&
    physical_equal(original, park) &&
    park.invalidation is Some(current) &&
    physical_equal(current, request) &&
    original_resource_park_current(park, origin) is Some(_) else {
    return None
  }
  Some(request)
}

///|
// INTERNAL compiled transition: the existing trusted Host/journal Owner must
// first authenticate its actual installation handle and exact four-reference
// confirmed-COMMIT receipt, then recheck original lifecycle synchronously.
// Do not export this as a general Node/public unpark or receipt factory. This
// function authenticates the Resource intent only, NOT that external COMMIT.
// Resource handoff/fence release grants no send/approval/egress authority and
// does not require a new Allow, including legitimate pending-approval cleanup.
pub fn[T] consume_original_resource_invalidation(
  request : OriginalResourceInvalidationRequest[T],
  park : OriginalResourcePark[T],
  origin : T,
) -> Result[Unit, OriginalReadIssue] {
  if request.park is None {
    return Err(SpentClaim)
  }
  guard original_resource_invalidation_current(request, park, origin) is Some(_) else {
    return Err(ChangedOriginalState)
  }
  let consumer = park.consumer.unwrap()
  let claim = consumer.claim.unwrap()
  let inventory = park.fence.unwrap().identity.ledger.original_inventory.unwrap()
  // No await/callback or resource charge between these checks and removal.
  // Restore only the exact prior phase; no usage/serial/Unknown reset/refund.
  claim.phase = park.previous.unwrap()
  inventory.park = None
  request.park = None
  park.invalidation = None
  park.previous = None
  park.state_write_work = None
  park.fence = None
  park.origin = None
  park.consumer = None
  Ok(())
}
