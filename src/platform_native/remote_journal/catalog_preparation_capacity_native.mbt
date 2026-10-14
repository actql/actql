///|
/// Inspect preparation coverage on the actual accepted custody, including a
/// consumed original stamp. This read never grants initial eligibility, claims
/// another use, reconciles a Provider outcome or completes cleanup. The trusted
/// Host must supply the entire simultaneous record/control/workspace envelope;
/// no numeric layout or budget is selected here.
pub fn Journal::read_catalog_preparation_capacity(
  self : Journal,
  custody : NativeInitialCatalogUseCustody,
  required : NativeInitialCatalogUseEnvelope,
) -> Result[Unit, NativeInitialCatalogUseIssue] {
  if self.closed {
    return Err(Journal(Closed))
  }
  if self.retiring {
    return Err(Journal(CleanupPending))
  }
  if !physical_equal(self, custody.journal) ||
    !custody.accepted ||
    custody.cleanup_started ||
    custody.removal_confirmed {
    return Err(Journal(StateCollision))
  }
  if !initial_catalog_use_envelope_valid(required) ||
    !@resources.capacity_reservation_covers(
      custody.ledger,
      custody.reservation,
      required.record_bytes + required.control_bytes,
      required.workspace_bytes,
    ) {
    return Err(Capacity(@resources.InvalidCharge))
  }
  match @remote.prepare_dispatch_acceptance(self.control, custody.request) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(Protocol(issue)))
  }
  match self.require(custody.request) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  let expected = match @remote.dispatch_request_json(custody.request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Journal(Protocol(issue)))
  }
  if expected.length().to_int64() > required.record_bytes {
    return Err(Capacity(@resources.InvalidCharge))
  }
  let saved = match
    self.database.read("site_initial_catalog_use", custody.dispatch_cid) {
    Ok(value) => value
    Err(issue) => return Err(Journal(Physical(issue)))
  }
  // The existing exact row predicate permits only original revision 0 or 1.
  // Revision 1 proves no unsent outcome and is never converted back to 0.
  if !initial_catalog_use_cleanup_row_matches(
      expected,
      saved.body,
      saved.revision,
    ) {
    return Err(Journal(StateCollision))
  }
  match self.cancellation_requested(custody.request) {
    Ok(false) => ()
    Ok(true) => return Err(Journal(StateCollision))
    Err(issue) => return Err(Journal(issue))
  }
  match @remote.prepare_dispatch_acceptance(self.control, custody.request) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(Protocol(issue)))
  }
  if custody.cleanup_started ||
    custody.removal_confirmed ||
    !@resources.capacity_reservation_covers(
      custody.ledger,
      custody.reservation,
      required.record_bytes + required.control_bytes,
      required.workspace_bytes,
    ) {
    return Err(Journal(StateCollision))
  }
  Ok(())
}
