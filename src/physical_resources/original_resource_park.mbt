///|
// The fence belongs to the existing original census. No serial/generation,
// amount, saved wire or journal fact is created by freezing resource mutation.
// Both reference directions belong to the same funded original lifetime.
priv struct OriginalResourceParkFence {
  identity : OriginalLedgerIdentity
}

///|
// Opaque restriction, not a Store/journal receipt or permission to resume/send.
// The same original consumer and origin are retained; a copied CID is not it.
// Actual journal COMMIT receipt admission/resumption is not implemented here.
// Until that closed bridge exists, a production caller cannot unpark this
// token. Tests of private retirement are not durable invalidation evidence.
struct OriginalResourcePark[T] {
  mut consumer : FundedReadConsumer[T]?
  mut origin : T?
  mut fence : OriginalResourceParkFence?
  mut previous : FundedReadPhase[T]?
  // One prepaid codec operation, not a capacity/send or journal grant. This
  // reference is resident in normal parks too and belongs in their inventory.
  mut state_write_work : Int?
  // One outstanding invalidation intent; not a committed journal receipt.
  // Its resident None and any live bidirectional borrow must be funded.
  mut invalidation : OriginalResourceInvalidationRequest[T]?
}

///|
// Every resource mutator calls this BEFORE changing the same Owner. Physical
// observations refused here stay with the original producer/journal until
// exact cut invalidation; they must not be discarded or turned into zero.
pub fn check_original_resources_mutable(
  ledger : Ledger,
) -> Result[Unit, LedgerIssue] {
  match check_imported_child_ledger(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  check_original_resources_mutable_current(ledger)
}

///|
// Only the same synchronous owner may use this after its original current
// callback. No external callback, mutation or await belongs between the two.
fn check_original_resources_mutable_current(
  ledger : Ledger,
) -> Result[Unit, LedgerIssue] {
  if ledger.original_inventory is Some(inventory) && inventory.park is Some(_) {
    Err(ResourceParked)
  } else {
    Ok(())
  }
}

///|
// Restrict the actual same-Ledger consumer, including after handoff, rather
// than comparing a historical admitted aggregate. The original installation
// funds the census reference/fence/control and all concurrent snapshots before
// entry. This does not adopt a byte coefficient or prove Model/Entry park.
pub fn[T] park_original_resource_consumer(
  consumer : FundedReadConsumer[T],
  origin : T,
) -> Result[OriginalResourcePark[T], OriginalReadIssue] {
  park_original_resource_consumer_impl(consumer, origin, false)
}

///|
// The existing Run funds Writer/control/backing overlap before this entry.
// Only logical encoding work is admitted here, on its actual original Ledger
// BEFORE freezing it. This supplies no physical coefficient or Store authority.
pub fn[T] park_original_resource_consumer_for_state_write(
  consumer : FundedReadConsumer[T],
  origin : T,
) -> Result[OriginalResourcePark[T], OriginalReadIssue] {
  park_original_resource_consumer_impl(consumer, origin, true)
}

///|
fn[T] park_original_resource_consumer_impl(
  consumer : FundedReadConsumer[T],
  origin : T,
  write_state : Bool,
) -> Result[OriginalResourcePark[T], OriginalReadIssue] {
  guard consumer.claim is Some(claim) else { return Err(SpentClaim) }
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  let phase_matches = match claim.phase {
    ConsumerStarted(current)
    | ConsumerHandedOff(current)
    | ConsumerStopping(current) => physical_equal(current, consumer)
    _ => false
  }
  let ledger = claim.descriptor.ledger
  guard phase_matches &&
    ledger.original_inventory is Some(inventory) &&
    !inventory.closing &&
    inventory.read_claimed &&
    physical_equal(inventory.bootstrap, claim.descriptor.bootstrap) &&
    capacity_reservation_open(inventory.bootstrap) &&
    capacity_reservation_open(claim.read) else {
    return Err(ChangedOriginalState)
  }
  if inventory.park is Some(_) {
    return Err(Resource(ResourceParked))
  }
  let state_write_work = if write_state {
    let n = inventory.reservations.length()
    let h = inventory.holdings.length()
    let d = inventory.delegations.length()
    if n > inventory.max_reservations ||
      h > inventory.max_holdings ||
      d > inventory.max_delegations ||
      n > 2147483631 ||
      h > 2147483631 - n ||
      d > 2147483631 - n - h {
      return Err(IncompleteInventory)
    }
    // Nine header blocks and seven container/close blocks. The current
    // census already includes the read token; do not append it a second time.
    let work = 16 + n + h + d
    match charge_planning(ledger, work) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => ()
    }
    Some(work)
  } else {
    None
  }
  let fence : OriginalResourceParkFence = { identity: inventory.identity, }
  let value : OriginalResourcePark[T] = {
    consumer: Some(consumer),
    origin: Some(origin),
    fence: Some(fence),
    previous: Some(claim.phase),
    state_write_work,
    invalidation: None,
  }
  // No await or mutating callback between checks and this synchronous fence.
  inventory.park = Some(fence)
  claim.phase = ConsumerParked(consumer, value)
  Ok(value)
}

///|
pub fn[T] original_resource_park_current(
  value : OriginalResourcePark[T],
  origin : T,
) -> OriginalResourcePark[T]? {
  guard value.consumer is Some(consumer) &&
    value.origin is Some(original) &&
    value.fence is Some(fence) &&
    value.previous is Some(_) &&
    physical_equal(original, origin) &&
    consumer.claim is Some(claim) &&
    physical_equal(original, claim.descriptor.origin) &&
    claim.descriptor.ledger.original_inventory is Some(inventory) &&
    physical_equal(fence.identity, inventory.identity) &&
    inventory.park is Some(current) &&
    physical_equal(fence, current) &&
    !inventory.closing &&
    capacity_reservation_open(inventory.bootstrap) &&
    capacity_reservation_open(claim.read) else {
    return None
  }
  if claim.phase is ConsumerParked(current, park) &&
    physical_equal(current, consumer) &&
    physical_equal(park, value) {
    Some(value)
  } else {
    None
  }
}

///|
// Read a parked token against a consumer's existing actual Ledger, without
// exposing its origin or creating a second token. This is not Model membership,
// quiescence, journal invalidation, funding or send permission.
pub fn[T] original_resource_park_current_for_ledger(
  value : OriginalResourcePark[T],
  ledger : Ledger,
) -> OriginalResourcePark[T]? {
  guard value.fence is Some(fence) &&
    value.origin is Some(origin) &&
    physical_equal(fence.identity.ledger, ledger) else {
    return None
  }
  original_resource_park_current(value, origin)
}

///|
// Borrow only the original opaque origin, never its Ledger/reservations. This
// is not proof that A's Model/Entry or Store ACK is parked/authenticated.
pub fn[T] original_resource_park_origin(value : OriginalResourcePark[T]) -> T? {
  guard value.origin is Some(origin) &&
    original_resource_park_current(value, origin) is Some(_) else {
    return None
  }
  Some(origin)
}

///|
// This retires only an escaped stale control AFTER actual original census and
// bootstrap/read cleanup. It cannot unpark a live Owner, supply a COMMIT receipt
// or treat a caller cleanup Bool as that evidence. The eventual exact journal
// invalidation consumer will retire these same borrows as part of resumption.
pub fn[T] retire_original_resource_park(
  value : OriginalResourcePark[T],
) -> Result[Unit, OriginalReadIssue] {
  guard value.fence is Some(fence) && value.consumer is Some(consumer) else {
    return Err(SpentClaim)
  }
  if fence.identity.ledger.original_inventory is Some(_) ||
    capacity_reservation_open(fence.identity.bootstrap) ||
    consumer.claim is Some(_) {
    return Err(CleanupPending)
  }
  value.previous = None
  value.state_write_work = None
  if value.invalidation is Some(request) {
    request.park = None
  }
  value.invalidation = None
  value.fence = None
  value.origin = None
  value.consumer = None
  Ok(())
}
