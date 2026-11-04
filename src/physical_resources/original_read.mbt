///|
// Private preparation material. This is not a persistence codec, a replacement
// Ledger, or a grant derived from a caller's serialized aggregate. Origin must
// be the existing checked Run/Host owner's opaque binding, not decoded JSON.
struct OriginalLedgerDescriptor[T] {
  origin : T
  ledger : Ledger
  bootstrap : CapacityReservation
  bootstrap_state : OriginalReservationSnapshot
  state : OriginalLedgerSnapshot
  reservations : Array[(Reservation, OriginalReservationSnapshot)]
  holdings : Array[(Holding, Bool)]
  delegations : Array[
    (ExecutionDelegation, (Int, Int, Int, Int64, Int64, Int, Int, Int)),
  ]
  mut claimed : Bool
}

///|
priv struct OriginalLedgerSnapshot {
  limits : LedgerLimits
  usage : LedgerUsage
  delegated : (Int, Int, Int)
  quantity_limits : QuantityAmounts?
  quantities : QuantityUsage
  next_capacity_serial : Int?
  next_attempt_serial : Int?
  next_holding_serial : Int?
} derive(Eq)

///|
priv struct OriginalReservationSnapshot {
  serial : Int
  transfer : Int64
  retention : Int64
  execution : Int64
  open : Bool
  attempt_reserved : Bool
  attempt_started : Bool
  cleanup_pending : Bool
  quantities : QuantityAmounts?
  uncertain_quantities : QuantityAmounts?
  observed_quantities : (Bool, Bool, Bool)
  completed_output : (Int?, Int64, Int64)?
} derive(Eq)

///|
priv enum FundedReadPhase[T] {
  Reading
  Writing(OriginalStateWrite[T])
  Written
  Preparing(FundedReadConsumer[T])
  ConsumerStarted(FundedReadConsumer[T])
  HandedOff
  ConsumerHandedOff(FundedReadConsumer[T])
  Stopping
  ConsumerStopping(FundedReadConsumer[T])
  ConsumerParked(FundedReadConsumer[T], OriginalResourcePark[T])
  Reclaimed
}

///|
struct FundedReadClaim[T] {
  descriptor : OriginalLedgerDescriptor[T]
  read : CapacityReservation
  read_state : OriginalReservationSnapshot
  admitted : OriginalLedgerSnapshot
  mut phase : FundedReadPhase[T]
  // None preserves the singular snapshot/SpentClaim protocol exactly.
  mut children : OriginalReadChildren[T]?
}

///|
// One original read admits only one early preparation. This opaque borrowed
// control is not a new reservation, owner or permission to dispatch a Model.
// Its representation and overlap belong to the already funded read envelope.
struct FundedReadConsumer[T] {
  mut claim : FundedReadClaim[T]?
}

///|
pub(all) enum OriginalReadIssue {
  InvalidBootstrap
  IncompleteInventory
  ForeignOrigin
  ChangedOriginalState
  SpentClaim
  CleanupPending
  Resource(LedgerIssue)
} derive(Eq, Debug)

///|
fn original_ledger_snapshot(ledger : Ledger) -> OriginalLedgerSnapshot {
  {
    limits: ledger.limits,
    usage: ledger.usage,
    delegated: (
      ledger.delegated_planning,
      ledger.delegated_attempts,
      ledger.delegated_holdings,
    ),
    quantity_limits: ledger.quantity_limits,
    quantities: ledger.quantity_usage,
    next_capacity_serial: ledger.next_capacity_serial,
    next_attempt_serial: ledger.next_attempt_serial,
    next_holding_serial: ledger.next_holding_serial,
  }
}

///|
fn original_reservation_snapshot(
  reservation : Reservation,
) -> OriginalReservationSnapshot {
  {
    serial: reservation.serial,
    transfer: reservation.transfer,
    retention: reservation.retention,
    execution: reservation.execution,
    open: reservation.open,
    attempt_reserved: reservation.attempt_reserved,
    attempt_started: reservation.attempt_started,
    cleanup_pending: reservation.cleanup_pending,
    quantities: reservation.quantities,
    uncertain_quantities: reservation.uncertain_quantities,
    observed_quantities: reservation.observed_quantities,
    completed_output: reservation.completed_output,
  }
}

///|
fn original_delegation_snapshot(
  value : ExecutionDelegation,
) -> (Int, Int, Int, Int64, Int64, Int, Int, Int) {
  (
    value.planning,
    value.attempts,
    value.holdings,
    value.transferred,
    value.uncertain,
    value.reserved_attempts,
    value.live_reservations,
    value.live_delegations,
  )
}

///|
pub fn original_read_bootstrap_available(
  ledger : Ledger,
  bootstrap : CapacityReservation,
) -> Bool {
  physical_equal(ledger, bootstrap.reservation.owner) &&
  bootstrap.reservation.open &&
  bootstrap.reservation.retention > 0L &&
  bootstrap.reservation.execution > 0L
}

///|
fn[T] issue_original_ledger_descriptor_from_slots(
  ledger : Ledger,
  origin : T,
  bootstrap : CapacityReservation,
  reservations : OriginalTokenSlots[Reservation],
  holdings : OriginalTokenSlots[Holding],
  delegations : OriginalTokenSlots[ExecutionDelegation],
  max_items : Int,
) -> Result[OriginalLedgerDescriptor[T], OriginalReadIssue] {
  if !physical_equal(ledger, bootstrap.reservation.owner) {
    return Err(Resource(ForeignOwner))
  }
  if !bootstrap.reservation.open ||
    bootstrap.reservation.retention <= 0L ||
    bootstrap.reservation.execution <= 0L {
    return Err(InvalidBootstrap)
  }
  guard ledger.original_inventory is Some(inventory) &&
    physical_equal(inventory.bootstrap, bootstrap) &&
    !inventory.closing else {
    return Err(IncompleteInventory)
  }
  // Bound all scans before comparing the supplied private test inventory.
  if max_items < 0 ||
    reservations.length() > max_items ||
    holdings.length() > max_items - reservations.length() ||
    delegations.length() > max_items - reservations.length() - holdings.length() {
    return Err(IncompleteInventory)
  }
  // Even zero-byte and settled tokens must originate in this original census.
  // The byte sums below are additional consistency checks, not the issuer.
  if reservations.length() != inventory.reservations.length() ||
    holdings.length() != inventory.holdings.length() ||
    delegations.length() != inventory.delegations.length() ||
    !reservations.all(token => {
      inventory.reservations.any(original => physical_equal(token, original))
    }) ||
    !holdings.all(token => {
      inventory.holdings.any(original => physical_equal(token, original))
    }) ||
    !delegations.all(token => {
      inventory.delegations.any(original => physical_equal(token, original))
    }) {
    return Err(IncompleteInventory)
  }
  // The authoritative finite census belongs to this same Ledger, not JS.
  let usage = ledger.usage
  let mut transfer = usage.reserved_transfer_bytes
  let mut retention = usage.reserved_retention_bytes -
    bootstrap.reservation.retention
  let mut execution = usage.reserved_execution_bytes -
    bootstrap.reservation.execution
  let mut quantities = ledger.quantity_usage.reserved
  for index in 0..<reservations.length() {
    let value = reservations[index]
    if !physical_equal(ledger, value.owner) {
      return Err(Resource(ForeignOwner))
    }
    if physical_equal(value, bootstrap.reservation) {
      return Err(IncompleteInventory)
    }
    for previous in 0..<index {
      if physical_equal(value, reservations[previous]) {
        return Err(IncompleteInventory)
      }
    }
    if value.open {
      if value.transfer < 0L ||
        value.transfer > transfer ||
        value.retention < 0L ||
        value.retention > retention ||
        value.execution < 0L ||
        value.execution > execution {
        return Err(IncompleteInventory)
      }
      transfer -= value.transfer
      retention -= value.retention
      execution -= value.execution
      if value.quantities is Some(amount) {
        if !valid_quantities(amount) ||
          amount.tokens > quantities.tokens ||
          amount.cost_units > quantities.cost_units ||
          amount.duration_ms > quantities.duration_ms {
          return Err(IncompleteInventory)
        }
        quantities = subtract_quantities(quantities, amount)
      }
    }
  }
  if transfer != 0L ||
    retention != 0L ||
    execution != 0L ||
    quantities != zero_quantities() {
    return Err(IncompleteInventory)
  }
  let mut held = usage.held_bytes
  for index in 0..<holdings.length() {
    let value = holdings[index]
    if !physical_equal(ledger, value.owner) {
      return Err(Resource(ForeignOwner))
    }
    for previous in 0..<index {
      if physical_equal(value, holdings[previous]) {
        return Err(IncompleteInventory)
      }
    }
    if value.live {
      if value.bytes < 0L || value.bytes > held {
        return Err(IncompleteInventory)
      }
      held -= value.bytes
    }
  }
  let mut planning = ledger.delegated_planning
  let mut attempts = ledger.delegated_attempts
  let mut delegated_holdings = ledger.delegated_holdings
  for index in 0..<delegations.length() {
    let value = delegations[index]
    if !physical_equal(ledger, value.owner) ||
      !reservations.any(token => physical_equal(token, value.reservation)) {
      return Err(IncompleteInventory)
    }
    for previous in 0..<index {
      if physical_equal(value, delegations[previous]) {
        return Err(IncompleteInventory)
      }
    }
    if value.reservation.open {
      let p = value.limits.planning_work - value.planning
      let a = value.limits.attempts - value.attempts - value.reserved_attempts
      let h = value.limits.holdings - value.holdings
      if p < 0 ||
        p > planning ||
        a < 0 ||
        a > attempts ||
        h < 0 ||
        h > delegated_holdings {
        return Err(IncompleteInventory)
      }
      planning -= p
      attempts -= a
      delegated_holdings -= h
    }
  }
  if held != 0L || planning != 0 || attempts != 0 || delegated_holdings != 0 {
    return Err(IncompleteInventory)
  }
  Ok({
    origin,
    ledger,
    bootstrap,
    bootstrap_state: original_reservation_snapshot(bootstrap.reservation),
    state: original_ledger_snapshot(ledger),
    reservations: reservations.map(token => {
      (token, original_reservation_snapshot(token))
    }),
    holdings: holdings.map(token => (token, token.live)),
    delegations: delegations.map(token => {
      (token, original_delegation_snapshot(token))
    }),
    claimed: false,
  })
}

///|
fn[T] original_tokens_match(
  value : OriginalLedgerDescriptor[T],
  completed_outputs? : Bool = false,
) -> Bool {
  value.ledger.original_inventory is Some(inventory) &&
  !inventory.closing &&
  original_reservation_snapshot(value.bootstrap.reservation) ==
  value.bootstrap_state &&
  value.reservations.all(pair => {
    let (token, snapshot) = pair
    original_reservation_snapshot(token) == snapshot ||
    (
      completed_outputs &&
      original_completed_output_matches(value.ledger, token, snapshot)
    )
  }) &&
  value.holdings.all(pair => {
    let (token, live) = pair
    token.live == live
  }) &&
  value.delegations.all(pair => {
    let (token, snapshot) = pair
    original_delegation_snapshot(token) == snapshot
  })
}

///|
// Only a handed-off consumer may observe the original producer's completed
// output instead of its earlier unused reservation. Initial read admission,
// restoration and bootstrap validation continue to require exact snapshots.
// The completion is recorded by Resource on the SAME token; its separately
// retained output must still belong to the original inventory and be live.
// Pending scratch is not acknowledged or released by this observation.
fn original_completed_output_matches(
  ledger : Ledger,
  token : Reservation,
  before : OriginalReservationSnapshot,
) -> Bool {
  guard physical_equal(token.owner, ledger) &&
    token.serial == before.serial &&
    before.open &&
    before.completed_output is None &&
    before.quantities is None &&
    before.uncertain_quantities is None &&
    token.completed_output is Some((holding, bytes, scratch)) &&
    scratch >= 0L &&
    scratch <= before.execution &&
    token.execution >= 0L &&
    token.execution <= scratch &&
    token.transfer == 0L &&
    token.retention == 0L &&
    token.quantities is None &&
    token.uncertain_quantities is None &&
    token.observed_quantities == before.observed_quantities &&
    ledger.original_inventory is Some(inventory) else {
    return false
  }
  match holding {
    None => bytes == 0L
    Some(serial) =>
      inventory.holdings.any(output => {
        physical_equal(output.owner, ledger) &&
        output.serial == serial &&
        output.reservation_serial == token.serial &&
        output.bytes == bytes &&
        output.live
      })
  }
}

///|
pub fn[T] fund_original_read(
  ledger : Ledger,
  origin : T,
  descriptor : OriginalLedgerDescriptor[T],
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[FundedReadClaim[T], OriginalReadIssue] {
  if !physical_equal(ledger, descriptor.ledger) {
    return Err(Resource(ForeignOwner))
  }
  if !physical_equal(origin, descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if descriptor.claimed || !capacity_reservation_open(descriptor.bootstrap) {
    return Err(SpentClaim)
  }
  guard ledger.original_inventory is Some(inventory) && !inventory.read_claimed else {
    return Err(SpentClaim)
  }
  if original_ledger_snapshot(ledger) != descriptor.state ||
    !original_tokens_match(descriptor) {
    return Err(ChangedOriginalState)
  }
  let read = match reserve_capacity(ledger, retained_bytes, execution_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  descriptor.claimed = true
  inventory.read_claimed = true
  Ok({
    descriptor,
    read,
    read_state: original_reservation_snapshot(read.reservation),
    admitted: original_ledger_snapshot(ledger),
    phase: Reading,
    children: None,
  })
}

///|
pub fn[T] funded_read_available(claim : FundedReadClaim[T], origin : T) -> Bool {
  (claim.phase is Reading || claim.phase is Written) &&
  funded_read_state_matches(claim, origin)
}

///|
fn[T] funded_read_state_matches(claim : FundedReadClaim[T], origin : T) -> Bool {
  check_original_resources_mutable(claim.descriptor.ledger) is Ok(_) &&
  physical_equal(origin, claim.descriptor.origin) &&
  capacity_reservation_open(claim.read) &&
  capacity_reservation_open(claim.descriptor.bootstrap) &&
  original_reservation_snapshot(claim.read.reservation) == claim.read_state &&
  original_ledger_snapshot(claim.descriptor.ledger) == claim.admitted &&
  original_tokens_match(claim.descriptor)
}

///|
// Validate before allocating this control or any consuming Execution. The
// complete envelope includes this control and all concurrently retained users.
// A positive envelope alone is not a proof of its physical adequacy.
pub fn[T] claim_funded_read_preparation(
  claim : FundedReadClaim[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[FundedReadConsumer[T], OriginalReadIssue] {
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if !(claim.phase is Reading || claim.phase is Written) {
    return Err(SpentClaim)
  }
  if retained_bytes <= 0L || execution_bytes <= 0L {
    return Err(Resource(InvalidCharge))
  }
  if !funded_read_state_matches(claim, origin) {
    return Err(ChangedOriginalState)
  }
  if claim.read.reservation.retention < retained_bytes {
    return Err(Resource(RetentionLimit))
  }
  if claim.read.reservation.execution < execution_bytes {
    return Err(Resource(ExecutionLimit))
  }
  let consumer : FundedReadConsumer[T] = { claim: Some(claim), }
  claim.phase = Preparing(consumer)
  Ok(consumer)
}

///|
pub fn[T] funded_read_consumer_available(
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  guard consumer.claim is Some(claim) else { return false }
  if claim.children is Some(_) {
    return original_read_child_available(
      claim, consumer, origin, retained_bytes, execution_bytes,
    )
  }

  funded_read_claim_has_active_consumer(claim, consumer) &&
  retained_bytes > 0L &&
  execution_bytes > 0L &&
  funded_read_state_matches(claim, origin) &&
  claim.read.reservation.retention >= retained_bytes &&
  claim.read.reservation.execution >= execution_bytes
}

///|
// Only the issued early consumer can continue its original handoff. Failure
// keeps this same control retryable; success does not refund or reset anything.
pub fn[T] handoff_funded_read_consumer_capacity(
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[(Ledger, CapacityReservation), OriginalReadIssue] {
  guard consumer.claim is Some(claim) else { return Err(SpentClaim) }
  if claim.children is Some(_) {
    return handoff_original_read_child_capacity(
      claim, consumer, origin, retained_bytes, execution_bytes,
    )
  }

  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if !(claim.phase is ConsumerStarted(current) &&
    physical_equal(current, consumer)) {
    return Err(SpentClaim)
  }
  if !funded_read_state_matches(claim, origin) {
    return Err(ChangedOriginalState)
  }
  let ledger = claim.descriptor.ledger
  let capacity = match
    reserve_capacity(ledger, retained_bytes, execution_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  claim.phase = ConsumerHandedOff(consumer)
  Ok((ledger, capacity))
}

///|
// This transfers the same physical Ledger, including unknown and spent serials.
// It neither settles read custody nor grants a fresh send/quantity allowance.
pub fn[T] handoff_funded_read(
  claim : FundedReadClaim[T],
  origin : T,
) -> Result[Ledger, OriginalReadIssue] {
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if !(claim.phase is Reading || claim.phase is Written) {
    return Err(SpentClaim)
  }
  if !funded_read_available(claim, origin) {
    return Err(ChangedOriginalState)
  }
  claim.phase = HandedOff
  Ok(claim.descriptor.ledger)
}

///|
// A consumer must fund its finite derivation transition before constructing a
// new projection. This checks the original read token, not aggregate free space.
// The caller's full read profile must still include overlapping authentication
// and codec scratch; this predicate does not reinterpret their charge as slack.
// retained_bytes is the complete simultaneous read-phase envelope, not a
// remaining balance or a separate allowance for each repeated invocation.
pub fn[T] funded_read_preparation_available(
  claim : FundedReadClaim[T],
  origin : T,
  execution_bytes : Int64,
  retained_bytes? : Int64 = 0L,
) -> Bool {
  retained_bytes >= 0L &&
  execution_bytes >= 0L &&
  funded_read_available(claim, origin) &&
  claim.read.reservation.retention >= retained_bytes &&
  claim.read.reservation.execution >= execution_bytes
}

///|
// Admit the consuming owner's reviewed byte projection before transferring
// this original Ledger. Insufficient capacity leaves the read claim usable;
// success transfers both the exact Ledger and its new opaque byte token.
// The read/bootstrap custody remains separate and no quantity/send is granted.
pub fn[T] handoff_funded_read_capacity(
  claim : FundedReadClaim[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[(Ledger, CapacityReservation), OriginalReadIssue] {
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if !(claim.phase is Reading || claim.phase is Written) {
    return Err(SpentClaim)
  }
  if !funded_read_available(claim, origin) {
    return Err(ChangedOriginalState)
  }
  let ledger = claim.descriptor.ledger
  let capacity = match
    reserve_capacity(ledger, retained_bytes, execution_bytes) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  claim.phase = HandedOff
  Ok((ledger, capacity))
}

///|
pub fn[T] stop_funded_read(
  claim : FundedReadClaim[T],
) -> Result[Unit, OriginalReadIssue] {
  if claim.children is Some(_) {
    return stop_original_read_children(claim)
  }
  match check_original_resources_mutable(claim.descriptor.ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  match claim.phase {
    Reading | Written | HandedOff => claim.phase = Stopping
    Writing(writer) => cancel_original_state_write(writer)
    Preparing(consumer)
    | ConsumerStarted(consumer)
    | ConsumerHandedOff(consumer) => claim.phase = ConsumerStopping(consumer)
    ConsumerParked(_, _) => return Err(Resource(ResourceParked))
    Stopping | ConsumerStopping(_) | Reclaimed => ()
  }
  Ok(())
}

///|
// Existing owning cleanup supplies the physical acknowledgement. Failed close,
// cancellation request and read completion must pass false, retaining both
// reservations. Handoff leaves this custody with that same owning cleanup.
pub fn[T] settle_funded_read(
  claim : FundedReadClaim[T],
  physical_cleanup_complete : Bool,
) -> Result[Unit, OriginalReadIssue] {
  if claim.children is Some(_) {
    if !physical_cleanup_complete {
      stop_original_read_children(claim) |> ignore
      return Err(CleanupPending)
    }
    let group = claim.children.unwrap()
    if group.busy {
      return Err(CleanupPending)
    }
    group.busy = true
    defer leave_original_read_children(group)
    return finish_original_read_children(claim)
  }
  if claim.phase is Reclaimed {
    return Err(SpentClaim)
  }
  if claim.phase is ConsumerParked(_, _) {
    return Err(Resource(ResourceParked))
  }
  // A live encoding cursor still borrows the census/read graph. Explicit stop
  // or cancellation retires it before physical owning cleanup can settle read.
  if physical_cleanup_complete && claim.phase is Writing(_) {
    return Err(CleanupPending)
  }
  if !physical_cleanup_complete {
    match stop_funded_read(claim) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
    return Err(CleanupPending)
  }
  let ledger = claim.descriptor.ledger
  // Validate read custody before retiring snapshots. Root/bootstrap custody
  // remains live until the original Run confirms all child cleanup separately.
  if reservation_check(ledger, claim.read.reservation) is Err(issue) {
    return Err(Resource(issue))
  }
  claim.descriptor.reservations.clear()
  claim.descriptor.reservations.shrink_to_fit()
  claim.descriptor.holdings.clear()
  claim.descriptor.holdings.shrink_to_fit()
  claim.descriptor.delegations.clear()
  claim.descriptor.delegations.shrink_to_fit()
  settle_capacity(ledger, claim.read).unwrap()
  // Failed cleanup retains both directions. A retired escaped consumer must
  // not keep the original graph alive after its reservation has been returned.
  match claim.phase {
    Preparing(consumer)
    | ConsumerStarted(consumer)
    | ConsumerHandedOff(consumer)
    | ConsumerStopping(consumer) => consumer.claim = None
    ConsumerParked(_, _) => abort("parked original cleanup was not admitted")
    _ => ()
  }
  // The original Run's final cleanup retires the census/bootstrap separately.
  // Another live child or a zero-byte holding still prevents that return.
  claim.phase = Reclaimed
  Ok(())
}

///|
// Original Run finalization is separate from this read child's physical
// cleanup. Do not expose the descriptor's Ledger just to close its census.
// Both read retirement and the original owning Run's separate acknowledgement
// are required; the existing finalizer also checks every recorded live child,
// including zero-byte tokens/holdings. Unknown quantities and spent serials
// are neither cleared nor recreated. Pending returns retain the same custody.
pub fn[T] finish_funded_read_inventory(
  claim : FundedReadClaim[T],
  origin : T,
  original_run_cleanup_complete : Bool,
) -> Result[Bool, OriginalReadIssue] {
  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if !(claim.phase is Reclaimed) {
    return Err(CleanupPending)
  }
  finish_original_ledger_inventory(
    claim.descriptor.ledger,
    original_run_cleanup_complete,
  )
}

///|
// A bounded borrow of the original opaque binding; no Ledger or token escapes.
// Retired controls return None. Availability and current fences are checked by
// the consuming Host, so this is neither send permission nor restored authority.
pub fn[T] funded_read_consumer_origin(consumer : FundedReadConsumer[T]) -> T? {
  guard consumer.claim is Some(claim) else { return None }
  if claim.children is Some(_) {
    return original_read_child_origin(claim, consumer, false)
  }

  if funded_read_claim_has_active_consumer(claim, consumer) &&
    funded_read_state_matches(claim, claim.descriptor.origin) {
    Some(claim.descriptor.origin)
  } else {
    None
  }
}

///|
pub fn[T] stop_funded_read_consumer(
  consumer : FundedReadConsumer[T],
) -> Result[Unit, OriginalReadIssue] {
  if consumer.claim is Some(claim) && claim.children is Some(_) {
    return stop_original_read_child(claim, consumer)
  }
  if consumer.claim is Some(claim) &&
    funded_read_claim_has_consumer(claim, consumer) {
    return stop_funded_read(claim)
  }
  Ok(())
}

///|
pub fn[T] settle_funded_read_consumer(
  consumer : FundedReadConsumer[T],
  physical_cleanup_complete : Bool,
) -> Result[Unit, OriginalReadIssue] {
  guard consumer.claim is Some(claim) else { return Err(SpentClaim) }
  if claim.children is Some(_) {
    return settle_original_read_child(
      claim, consumer, physical_cleanup_complete,
    )
  }

  if !funded_read_claim_has_consumer(claim, consumer) {
    return Err(SpentClaim)
  }
  settle_funded_read(claim, physical_cleanup_complete)
}

///|
fn[T] funded_read_claim_has_active_consumer(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
) -> Bool {
  if claim.children is Some(_) {
    return original_read_child(claim, consumer)
      .map(child => child.phase == Declared || child.phase == Entered)
      .unwrap_or(false)
  }
  match claim.phase {
    Preparing(current) | ConsumerStarted(current) =>
      physical_equal(current, consumer)
    _ => false
  }
}

///|
fn[T] funded_read_claim_has_consumer(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
) -> Bool {
  if claim.children is Some(_) {
    return original_read_child(claim, consumer)
      .map(child => child.phase != Reclaimed)
      .unwrap_or(false)
  }
  match claim.phase {
    Preparing(current)
    | ConsumerStarted(current)
    | ConsumerHandedOff(current)
    | ConsumerStopping(current) => physical_equal(current, consumer)
    ConsumerParked(current, _) => physical_equal(current, consumer)
    _ => false
  }
}

///|
// The early IO control and consuming Execution are separate allocation sites.
// Claiming the read once does not permit an aliased ticket to start twice.
// This synchronous transition precedes the consuming Execution allocation.
pub fn[T] enter_funded_read_consumer(
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, OriginalReadIssue] {
  guard consumer.claim is Some(claim) else { return Err(SpentClaim) }
  if claim.children is Some(_) {
    return enter_original_read_child(
      claim, consumer, origin, retained_bytes, execution_bytes,
    )
  }

  if !physical_equal(origin, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if !(claim.phase is Preparing(current) && physical_equal(current, consumer)) {
    return Err(SpentClaim)
  }
  if !funded_read_consumer_available(
      consumer, origin, retained_bytes, execution_bytes,
    ) {
    return Err(ChangedOriginalState)
  }
  claim.phase = ConsumerStarted(consumer)
  Ok(())
}
