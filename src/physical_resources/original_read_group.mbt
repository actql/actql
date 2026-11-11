///|
// Closed child state on the EXISTING read claim, not another Ledger/Owner.
// Origins and allowances are retained before the first child enters. The
// original admitted snapshot is immutable and is checked at first entry;
// later planned children observe the same live census, never a new snapshot.
priv enum OriginalReadChildPhase {
  Declared
  Entered
  HandedOff
  Stopping
  Reclaimed
} derive(Eq)

///|
priv struct OriginalReadChild[T] {
  consumer : FundedReadConsumer[T]
  origin : T
  // Existing child peaks, initially the declared input envelope. An entered
  // child may grow them only together with this SAME shared Read token.
  mut retained_bytes : Int64
  mut execution_bytes : Int64
  mut phase : OriginalReadChildPhase
  // A capacity returned by a reentrant/refused handoff stays here until its
  // original cleanup; success transfers it to the existing Model startup.
  mut partial_capacity : CapacityReservation?
}

///|
priv struct OriginalReadChildren[T] {
  members : Array[OriginalReadChild[T]]
  mut started : Bool
  mut busy : Bool
}

///|
/// Representation DATA for the claim's resident child reference, one closed
/// Array, its entries and existing consumer controls. The actual caller backs
/// this on the SAME preparation before construction. No byte price or grant.
pub fn original_read_children_construction_slots(
  count : Int,
) -> (Int64, Int64, Int64)? {
  if count < 1 {
    return None
  }
  if count == 1 {
    return Some((0L, 1L, 0L))
  }
  let n = count.to_int64()
  // Group1H1R2W; TWO Array old/new envelopes, each3H(13+3n)R2W;
  // each entry1H3R3W and its existing consumer1H1R. The resident
  // claim slot plus its Some add1H2R1W; each possible partial capacity Some
  // adds1H1R1W. Values/Graphs and physical buffers are borrowed.
  guard @preparation_counts.preparation_array_slots(2L, 2L * n, true)
    is Some((h, r, w)) else {
    return None
  }
  Some((h + 2L + 3L * n, r + 3L + 5L * n, w + 3L + 4L * n))
}

///|
/// Declare the compiler-selected children once, before any consumer enters.
/// This partitions the EXISTING read allowance; it creates no reservation,
/// attempt, dispatch permission or mutable Ledger projection.
pub fn[T] claim_funded_read_preparations(
  claim : FundedReadClaim[T],
  original : T,
  origins : Array[T],
  retained_bytes : Array[Int64],
  execution_bytes : Array[Int64],
) -> Result[Array[FundedReadConsumer[T]], OriginalReadIssue] {
  if !physical_equal(original, claim.descriptor.origin) {
    return Err(ForeignOrigin)
  }
  if claim.children is Some(_) ||
    !(claim.phase is Reading || claim.phase is Written) {
    return Err(SpentClaim)
  }
  if origins.length() < 2 ||
    origins.length() != retained_bytes.length() ||
    origins.length() != execution_bytes.length() ||
    !physical_equal(origins[0], original) {
    return Err(ForeignOrigin)
  }
  let mut r = 0L
  let mut e = 0L
  for index, origin in origins {
    if retained_bytes[index] <= 0L ||
      execution_bytes[index] <= 0L ||
      retained_bytes[index] > 9223372036854775807L - r ||
      execution_bytes[index] > 9223372036854775807L - e {
      return Err(Resource(InvalidCharge))
    }
    for previous in 0..<index {
      if physical_equal(origin, origins[previous]) {
        return Err(ForeignOrigin)
      }
    }
    r += retained_bytes[index]
    e += execution_bytes[index]
  }
  if r > claim.read.reservation.retention {
    return Err(Resource(RetentionLimit))
  }
  if e > claim.read.reservation.execution {
    return Err(Resource(ExecutionLimit))
  }
  if !funded_read_state_matches(claim, original) {
    return Err(ChangedOriginalState)
  }
  let members : Array[OriginalReadChild[T]] = []
  let consumers : Array[FundedReadConsumer[T]] = []
  for index, origin in origins {
    let consumer : FundedReadConsumer[T] = { claim: Some(claim), }
    members.push({
      consumer,
      origin,
      retained_bytes: retained_bytes[index],
      execution_bytes: execution_bytes[index],
      phase: Declared,
      partial_capacity: None,
    })
    consumers.push(consumer)
  }
  claim.children = Some({ members, started: false, busy: false, })
  // Retain the same one claimed read. The per-child states above own its
  // bounded handoffs; the singular state machine remains unchanged otherwise.
  claim.phase = Preparing(consumers[0])
  Ok(consumers)
}

///|
fn[T] original_read_child(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
) -> OriginalReadChild[T]? {
  guard claim.children is Some(group) else { return None }
  for item in group.members {
    if physical_equal(item.consumer, consumer) {
      return Some(item)
    }
  }
  None
}

///|
fn[T] original_read_children_current(claim : FundedReadClaim[T]) -> Bool {
  guard claim.children is Some(group) &&
    !(claim.phase is Reclaimed) &&
    claim.descriptor.ledger.original_inventory is Some(_) else {
    return false
  }
  if !group.started {
    return funded_read_state_matches(claim, claim.descriptor.origin)
  }
  // A declared Run may now spend real work/attempts and retain its own output.
  // Keep the first snapshot untouched. Only this same original census/read
  // and its originally recorded producer transitions may remain live here.
  check_original_resources_mutable(claim.descriptor.ledger) is Ok(_) &&
  original_read_children_snapshot_matches(claim)
}

///|
// Callback-free half of the existing group current boundary. A live planned
// child may have spent work or obtained its own recorded output; the original
// descriptor and bootstrap snapshots must still match without refreshing them.
fn[T] original_read_children_snapshot_matches(
  claim : FundedReadClaim[T],
) -> Bool {
  claim.children is Some(_) &&
  !(claim.phase is Reclaimed) &&
  check_original_resources_mutable_current(claim.descriptor.ledger) is Ok(_) &&
  capacity_reservation_open(claim.read) &&
  capacity_reservation_open(claim.descriptor.bootstrap) &&
  original_reservation_snapshot(claim.read.reservation) == claim.read_state &&
  original_tokens_match(claim.descriptor, completed_outputs=true)
}

///|
// The entered child's next absolute input/body peak adds only its own delta
// to the original shared Read. Other children and earlier peaks stay charged.
// No slot, Ledger, quantity allowance, first snapshot or cleanup owner is new.
fn[T] grow_original_read_child_capacity(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, OriginalReadIssue] {
  guard claim.children is Some(group) &&
    original_read_child(claim, consumer) is Some(child) else {
    return Err(SpentClaim)
  }
  if !physical_equal(child.origin, origin) {
    return Err(ForeignOrigin)
  }
  if child.phase != Entered {
    return Err(SpentClaim)
  }
  if group.busy {
    return Err(CleanupPending)
  }
  if retained_bytes < child.retained_bytes ||
    execution_bytes < child.execution_bytes {
    return Err(Resource(InvalidCharge))
  }
  let token = claim.read.reservation
  let retained_delta = retained_bytes - child.retained_bytes
  let execution_delta = execution_bytes - child.execution_bytes
  if retained_delta > 9223372036854775807L - token.retention ||
    execution_delta > 9223372036854775807L - token.execution {
    return Err(Resource(InvalidCharge))
  }
  let retained = token.retention + retained_delta
  let execution = token.execution + execution_delta
  group.busy = true
  defer leave_original_read_children(group)
  if !group.started || !original_read_children_snapshot_matches(claim) {
    return Err(ChangedOriginalState)
  }
  // Fence the same group before its one external current callback. A stop
  // during current wins before resize; no nested grow/handoff can enter.
  let current_result = reservation_check(claim.descriptor.ledger, token)
  if child.phase != Entered {
    return Err(CleanupPending)
  }
  match current_result {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if !original_read_children_snapshot_matches(claim) {
    return Err(ChangedOriginalState)
  }
  let result = resize_capacity_reservation_current(
    claim.descriptor.ledger,
    claim.read,
    retained,
    execution,
  )
  if result is Ok(_) {
    // An actual imported backing acquisition may itself reenter stop. Retain
    // a successful resize before refusing its constructor, never refund it.
    child.retained_bytes = retained_bytes
    child.execution_bytes = execution_bytes
    claim.read_state = original_reservation_snapshot(token)
    if child.phase != Entered || !original_read_children_snapshot_matches(claim) {
      return Err(CleanupPending)
    }
  }
  result.map_err(issue => Resource(issue))
}

///|
fn[T] original_read_child_available(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Bool {
  guard original_read_child(claim, consumer) is Some(child) &&
    physical_equal(child.origin, origin) &&
    retained_bytes > 0L &&
    execution_bytes > 0L &&
    retained_bytes <= child.retained_bytes &&
    execution_bytes <= child.execution_bytes else {
    return false
  }
  original_read_children_current(claim) &&
  claim.descriptor.ledger.original_inventory is Some(inventory) &&
  !inventory.closing &&
  (child.phase == Declared || child.phase == Entered)
}

///|
fn[T] leave_original_read_children(group : OriginalReadChildren[T]) -> Unit {
  group.busy = false
}

///|
fn[T] enter_original_read_child(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, OriginalReadIssue] {
  guard claim.children is Some(group) &&
    original_read_child(claim, consumer) is Some(child) else {
    return Err(SpentClaim)
  }
  if !physical_equal(child.origin, origin) {
    return Err(ForeignOrigin)
  }
  if child.phase != Declared {
    return Err(SpentClaim)
  }
  if group.busy {
    return Err(CleanupPending)
  }
  group.busy = true
  defer leave_original_read_children(group)
  if !original_read_child_available(
      claim, consumer, origin, retained_bytes, execution_bytes,
    ) ||
    child.phase != Declared {
    return Err(ChangedOriginalState)
  }
  group.started = true
  child.phase = Entered
  Ok(())
}

///|
fn[T] handoff_original_read_child_capacity(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
  origin : T,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[(Ledger, CapacityReservation), OriginalReadIssue] {
  guard claim.children is Some(group) &&
    original_read_child(claim, consumer) is Some(child) else {
    return Err(SpentClaim)
  }
  if !physical_equal(child.origin, origin) {
    return Err(ForeignOrigin)
  }
  if child.phase != Entered {
    return Err(SpentClaim)
  }
  if group.busy {
    return Err(CleanupPending)
  }
  group.busy = true
  defer leave_original_read_children(group)
  if !original_read_children_current(claim) || child.phase != Entered {
    return Err(ChangedOriginalState)
  }
  guard claim.descriptor.ledger.original_inventory is Some(inventory) &&
    !inventory.closing else {
    return Err(ChangedOriginalState)
  }
  let ledger = claim.descriptor.ledger
  let capacity = match
    reserve_capacity(ledger, retained_bytes, execution_bytes) {
    Err(issue) => return Err(Resource(issue))
    Ok(value) => value
  }
  child.partial_capacity = Some(capacity)
  // Current may synchronously request stop. Keep the exact returned token
  // before observing that reentry; it is not an unissued or refunded child.
  if child.phase != Entered || inventory.closing {
    return Err(ChangedOriginalState)
  }
  child.phase = HandedOff
  child.partial_capacity = None
  Ok((ledger, capacity))
}

///|
fn[T] stop_original_read_child(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
) -> Result[Unit, OriginalReadIssue] {
  guard claim.children is Some(group) &&
    original_read_child(claim, consumer) is Some(child) else {
    return Err(SpentClaim)
  }
  if group.busy {
    if child.phase != Reclaimed {
      child.phase = Stopping
    }
    return Err(CleanupPending)
  }
  group.busy = true
  defer leave_original_read_children(group)
  match check_original_resources_mutable(claim.descriptor.ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if child.phase != Reclaimed {
    child.phase = Stopping
  }
  Ok(())
}

///|
fn[T] stop_original_read_children(
  claim : FundedReadClaim[T],
) -> Result[Unit, OriginalReadIssue] {
  guard claim.children is Some(group) else { return Err(SpentClaim) }
  if group.busy {
    for child in group.members {
      if child.phase != Reclaimed {
        child.phase = Stopping
      }
    }
    return Err(CleanupPending)
  }
  group.busy = true
  defer leave_original_read_children(group)
  match check_original_resources_mutable(claim.descriptor.ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  for child in group.members {
    if child.phase != Reclaimed {
      child.phase = Stopping
    }
  }
  Ok(())
}

///|
fn[T] finish_original_read_children(
  claim : FundedReadClaim[T],
) -> Result[Unit, OriginalReadIssue] {
  guard claim.children is Some(group) else { return Err(SpentClaim) }
  if !group.members.all(child => {
      child.phase == Reclaimed && child.partial_capacity is None
    }) {
    return Err(CleanupPending)
  }
  let ledger = claim.descriptor.ledger
  match check_original_resources_mutable(ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if reservation_check(ledger, claim.read.reservation) is Err(issue) {
    return Err(Resource(issue))
  }
  // No live child can use these read snapshots now. The original census,
  // actual usage and unknown obligations remain with the same Ledger.
  claim.descriptor.reservations.clear()
  claim.descriptor.reservations.shrink_to_fit()
  claim.descriptor.holdings.clear()
  claim.descriptor.holdings.shrink_to_fit()
  claim.descriptor.delegations.clear()
  claim.descriptor.delegations.shrink_to_fit()
  match settle_capacity(ledger, claim.read) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  for child in group.members {
    child.consumer.claim = None
  }
  group.members.clear()
  group.members.shrink_to_fit()
  claim.children = None
  claim.phase = Reclaimed
  Ok(())
}

///|
fn[T] settle_original_read_child(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
  physical_cleanup_complete : Bool,
) -> Result[Unit, OriginalReadIssue] {
  guard claim.children is Some(group) &&
    original_read_child(claim, consumer) is Some(child) else {
    return Err(SpentClaim)
  }
  if group.busy {
    return Err(CleanupPending)
  }
  group.busy = true
  defer leave_original_read_children(group)
  match check_original_resources_mutable(claim.descriptor.ledger) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  if !physical_cleanup_complete {
    child.phase = Stopping
    return Err(CleanupPending)
  }
  if child.partial_capacity is Some(capacity) {
    match settle_capacity(claim.descriptor.ledger, capacity) {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => child.partial_capacity = None
    }
  }
  child.phase = Reclaimed
  if group.members.all(item => item.phase == Reclaimed) {
    finish_original_read_children(claim)
  } else {
    Ok(())
  }
}

///|
fn[T] original_read_child_origin(
  claim : FundedReadClaim[T],
  consumer : FundedReadConsumer[T],
  handed_off : Bool,
) -> T? {
  guard original_read_child(claim, consumer) is Some(child) else { return None }
  if !original_read_children_current(claim) {
    return None
  }
  if (handed_off && child.phase == HandedOff) ||
    (!handed_off && (child.phase == Declared || child.phase == Entered)) {
    Some(child.origin)
  } else {
    None
  }
}
