///|
// Existing Resource-owner bookkeeping, not another Ledger, byte grant or
// scheduler. T is the existing installer's actual opaque provider binding,
// never a provider name, configuration, CID or caller-constructed packet.
pub struct ModelIoAdmission[T] {
  mut installation : T?
  active_limit : Int
  unsettled_limit : Int
  mut active : Int
  mut unsettled : Int
  duties : Array[ModelIoTicket[T]]
  mut closing : Bool
}

///|
// The original attempt's zero-byte census holding records responsibility,
// NOT the price of this ticket, references, backing or physical response.
// Complete control/physical capacity must already be funded separately.
pub struct ModelIoTicket[T] {
  mut owner : ModelIoAdmission[T]?
  mut origin : OriginalLedgerIdentity?
  mut reservation : Reservation?
  mut census : Holding?
  slot : Int
  attempt : Int
  mut active : Bool
}

///|
pub(all) enum ModelIoAdmissionIssue {
  InvalidLimits
  ForeignInstallation
  ForeignTicket
  InvalidAttempt
  AdmissionClosing
  ActiveExhausted
  HoldingExhausted
  DuplicateAttempt
  IoAlreadyRetired
  CleanupPending
  TicketRetired
  Resource(LedgerIssue)
} derive(Eq, Debug)

///|
// Counts use the current ModelResponseProfile's independently declared
// active_slots/unsettled_slots domain (1..4), not quantities or attempts.
// The trusted existing installer must supply this exact original binding
// once and share the resulting admission across its Runs. No public Node
// factory, profile/body admission or authority is issued by these functions.
pub fn issue_model_io_admission[T](
  installation : T,
  active_slots : Int,
  unsettled_slots : Int,
) -> Result[ModelIoAdmission[T], ModelIoAdmissionIssue] {
  if active_slots < 1 || active_slots > 4 ||
    unsettled_slots < 1 || unsettled_slots > 4 {
    return Err(InvalidLimits)
  }
  Ok({
    installation: Some(installation),
    active_limit: active_slots,
    unsettled_limit: unsettled_slots,
    active: 0,
    unsettled: 0,
    duties: [],
    closing: false,
  })
}

///|
fn model_io_installation_matches[T](
  value : ModelIoAdmission[T],
  installation : T,
) -> Bool {
  value.installation is Some(original) && physical_equal(original, installation)
}

///|
// This is current Owner-local count DATA, not available execution authority.
pub fn model_io_admission_counts[T](
  value : ModelIoAdmission[T],
  installation : T,
) -> (Int, Int)? {
  if model_io_installation_matches(value, installation) {
    Some((value.active, value.unsettled))
  } else {
    None
  }
}

///|
pub fn claim_model_io_admission[T](
  value : ModelIoAdmission[T],
  installation : T,
  origin : OriginalLedgerIdentity,
  reservation : Reservation,
  slot : Int,
  attempt : Int,
) -> Result[ModelIoTicket[T], ModelIoAdmissionIssue] {
  if !model_io_installation_matches(value, installation) {
    return Err(ForeignInstallation)
  }
  if value.closing {
    return Err(AdmissionClosing)
  }
  if slot < 0 || attempt < 1 || reservation.serial < 0 {
    return Err(InvalidAttempt)
  }
  if !original_ledger_inventory_available(origin) ||
    !physical_equal(origin.ledger, reservation.owner) || !reservation.open {
    return Err(ForeignTicket)
  }
  for ticket in value.duties {
    if ticket.reservation is Some(original) && physical_equal(original, reservation) {
      return Err(DuplicateAttempt)
    }
    if ticket.origin is Some(original) && physical_equal(original, origin) &&
      ticket.slot == slot && ticket.attempt == attempt {
      return Err(DuplicateAttempt)
    }
  }
  if value.active >= value.active_limit {
    return Err(ActiveExhausted)
  }
  if value.unsettled >= value.unsettled_limit {
    return Err(HoldingExhausted)
  }
  // Keep this obligation visible in the ORIGINAL Run's existing census even
  // when its response bytes are accounted by other original reservations.
  // Failed admission changes neither the shared counts nor another Run.
  let census = match retain_allocation(origin.ledger, reservation, 0L) {
    Ok(value) => value
    Err(issue) => return Err(Resource(issue))
  }
  let ticket : ModelIoTicket[T] = {
    owner: Some(value),
    origin: Some(origin),
    reservation: Some(reservation),
    census: Some(census),
    slot,
    attempt,
    active: true,
  }
  value.duties.push(ticket)
  value.active += 1
  value.unsettled += 1
  Ok(ticket)
}

///|
fn check_model_io_ticket[T](
  value : ModelIoAdmission[T],
  installation : T,
  origin : OriginalLedgerIdentity,
  ticket : ModelIoTicket[T],
  slot : Int,
  attempt : Int,
) -> Result[Unit, ModelIoAdmissionIssue] {
  if !model_io_installation_matches(value, installation) {
    return Err(ForeignInstallation)
  }
  guard ticket.owner is Some(owner) && ticket.origin is Some(original) &&
    ticket.reservation is Some(reservation) && ticket.census is Some(census) else {
    return Err(TicketRetired)
  }
  guard origin.ledger.original_inventory is Some(inventory) &&
    physical_equal(inventory.identity, origin) &&
    physical_equal(inventory.bootstrap, origin.bootstrap) &&
    capacity_reservation_open(origin.bootstrap) else {
    return Err(ForeignTicket)
  }
  if !physical_equal(owner, value) || !physical_equal(original, origin) ||
    ticket.slot != slot || ticket.attempt != attempt ||
    !physical_equal(reservation.owner, origin.ledger) ||
    census.reservation_serial != reservation.serial ||
    !holding_available(origin.ledger, census) ||
    !value.duties.any(original => physical_equal(original, ticket)) {
    return Err(ForeignTicket)
  }
  // Closing refuses new borrowing but never erases existing cleanup custody.
  // Park/mutation checks remain in the existing Ledger release operation.
  Ok(())
}

///|
// Resource retirement, NOT a physical ACK issuer. Only the existing Model
// Owner may call after its original physical port actually acknowledged I/O
// quiescence. Promise completion or cancellation acceptance is insufficient.
pub fn settle_model_io_after_owner_ack[T](
  value : ModelIoAdmission[T],
  installation : T,
  origin : OriginalLedgerIdentity,
  ticket : ModelIoTicket[T],
  slot : Int,
  attempt : Int,
) -> Result[Unit, ModelIoAdmissionIssue] {
  match check_model_io_ticket(value, installation, origin, ticket, slot, attempt) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !ticket.active {
    return Err(IoAlreadyRetired)
  }
  ticket.active = false
  value.active -= 1
  // Store/Journal, raw/SDK/decoder aliases and Unknown custody remain held.
  Ok(())
}

///|
// Call only after original Store/Journal confirmation and actual owning
// cleanup/alias retirement, not after merely observing a response. This is
// not a persisted ACK or permission factory and must not be a Node export.
pub fn settle_model_holding_after_owner_ack[T](
  value : ModelIoAdmission[T],
  installation : T,
  origin : OriginalLedgerIdentity,
  ticket : ModelIoTicket[T],
  slot : Int,
  attempt : Int,
) -> Result[Unit, ModelIoAdmissionIssue] {
  match check_model_io_ticket(value, installation, origin, ticket, slot, attempt) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if ticket.active {
    return Err(CleanupPending)
  }
  let census = ticket.census.unwrap()
  match release_allocation(origin.ledger, census) {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  let mut index = 0
  while !physical_equal(value.duties[index], ticket) {
    index += 1
  }
  let last = value.duties.pop().unwrap()
  if index < value.duties.length() {
    value.duties[index] = last
  }
  value.unsettled -= 1
  // A retired escaped ticket cannot retain the original multi-Run graph.
  ticket.owner = None
  ticket.origin = None
  ticket.reservation = None
  ticket.census = None
  Ok(())
}

///|
// Graceful close: no new borrowing, existing duties unchanged. Final view
// detachment is not release of a process/module/native baseline.
pub fn close_model_io_admission[T](
  value : ModelIoAdmission[T],
  installation : T,
) -> Result[Bool, ModelIoAdmissionIssue] {
  if !model_io_installation_matches(value, installation) {
    return Err(ForeignInstallation)
  }
  value.closing = true
  if value.active != 0 || value.unsettled != 0 || !value.duties.is_empty() {
    return Ok(false)
  }
  value.installation = None
  Ok(true)
}
