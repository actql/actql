///|
/// Read the original funded eligibility without consuming it. Equal saved
/// bytes in another Journal, a failed acceptance, or an already consumed row
/// cannot replace this nominal custody. This grants no Host/Provider access.
pub fn Journal::read_funded_initial_catalog_use(
  self : Journal,
  custody : NativeInitialCatalogUseCustody,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if self.retiring {
    return Err(CleanupPending)
  }
  if !physical_equal(self, custody.journal) ||
    !custody.accepted ||
    custody.cleanup_started ||
    custody.removal_confirmed ||
    !@resources.capacity_reservation_open(custody.reservation) {
    return Err(StateCollision)
  }
  // Reuse Site admission rather than declaring saved generation/runtime current.
  match @remote.prepare_dispatch_acceptance(self.control, custody.request) {
    Ok(_) => ()
    Err(issue) => return Err(Protocol(issue))
  }
  match self.require_initial_catalog_use(custody.request, 0L) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  match self.cancellation_requested(custody.request) {
    Ok(false) => Ok(())
    Ok(true) => Err(StateCollision)
    Err(issue) => Err(issue)
  }
}

///|
/// Claim only the request retained by the original acceptance Owner. The
/// existing claim transaction repeats admission, cancellation and revision
/// checks; a successful read is never a substitute for its actual commit.
pub fn Journal::claim_funded_initial_catalog_use(
  self : Journal,
  custody : NativeInitialCatalogUseCustody,
) -> Result[NativeInitialCatalogUseClaim, NativeRemoteJournalIssue] {
  match self.read_funded_initial_catalog_use(custody) {
    Ok(_) => self.claim_initial_catalog_use(custody.request)
    Err(issue) => Err(issue)
  }
}
