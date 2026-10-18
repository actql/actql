///|
/// The existing read Owner's issued consuming view. The original read keeps
/// this reference until its existing physical close/settlement succeeds.
/// No Ledger, copied descriptor, second reservation or cleanup state escapes.
struct InstalledArenaOriginalReadConsumer {
  host : InstalledArenaHost
  read : InstalledArenaOriginalRead
  consumer : @resources.FundedReadConsumer[InstalledArenaOriginalRead]
  workspace : @buffers.WorkspaceLoan
  retained_bytes : Int64
  execution_bytes : Int64
}

///|
/// Claim the original read once, before allocating a consuming control or
/// execution. These are the caller's complete simultaneous-envelope quotes,
/// not an intake limit, permission or proof of a normal numerical profile.
/// Claiming intentionally makes the old available-pair port unavailable.
pub fn InstalledArenaHost::prepare_domain_original_read_consumer(
  self : InstalledArenaHost,
  read : InstalledArenaOriginalRead,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[InstalledArenaOriginalReadConsumer, InstalledArenaOriginalReadIssue] {
  match self.require_domain_original_read_current(read) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if read.consumer is Some(_) {
    return Err(Read(@resources.SpentClaim))
  }
  guard read.claim is Some(claim) && read.workspace is Some(workspace) else {
    return Err(Read(@resources.IncompleteInventory))
  }
  let consumer = match
    @resources.claim_funded_read_preparation(
      claim, read, retained_bytes, execution_bytes,
    ) {
    Err(issue) => return Err(Read(issue))
    Ok(value) => value
  }
  // The original claim retains the consuming control even if this later
  // managed allocation fails; existing read cleanup still owns that claim.
  let view : InstalledArenaOriginalReadConsumer = {
    host: self,
    read,
    consumer,
    workspace,
    retained_bytes,
    execution_bytes,
  }
  read.consumer = Some(view)
  Ok(view)
}

///|
fn InstalledArenaHost::original_domain_read_consumer(
  self : InstalledArenaHost,
  view : InstalledArenaOriginalReadConsumer,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  if !physical_equal(view.host, self) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  match self.original_domain_read(view.read) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard view.read.consumer is Some(original) &&
    physical_equal(original, view) &&
    view.read.workspace is Some(workspace) &&
    physical_equal(workspace, view.workspace) else {
    return Err(Read(@resources.ForeignOrigin))
  }
  Ok(())
}

///|
/// Preserve the original consumer's snapshot/token/phase checks. Stopping,
/// handoff, changed capacity and retired physical domains cannot resume a read.
/// The old pair's availability is deliberately not reinterpreted or revived.
pub fn InstalledArenaHost::require_domain_original_read_consumer_current(
  self : InstalledArenaHost,
  view : InstalledArenaOriginalReadConsumer,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.original_domain_read_consumer(view) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let read = view.read
  if !read.ready ||
    read.closing ||
    read.closed ||
    view.workspace.closing ||
    view.workspace.stopped ||
    view.workspace.cleaned ||
    view.workspace.settled {
    return Err(Read(@resources.CleanupPending))
  }
  match self.require_domain_read_current(read.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard @resources.funded_read_consumer_origin(view.consumer) is Some(origin) &&
    physical_equal(origin, read) &&
    @resources.funded_read_consumer_available(
      view.consumer,
      read,
      view.retained_bytes,
      view.execution_bytes,
    ) else {
    return Err(Read(@resources.ChangedOriginalState))
  }
  Ok(())
}

///|
/// Only the already recorded original WorkspaceLoan is borrowed. DATA cannot
/// construct this view or supply another loan with an equal byte declaration.
pub fn InstalledArenaHost::borrow_domain_original_read_consumer_workspace(
  self : InstalledArenaHost,
  view : InstalledArenaOriginalReadConsumer,
) -> Result[@buffers.WorkspaceLoan, InstalledArenaOriginalReadIssue] {
  self
  .require_domain_original_read_consumer_current(view)
  .map(_ => view.workspace)
}

///|
/// Enter the consuming phase once before physical work. A failed physical
/// enter retains this same started consumer for original cleanup; it never
/// resets the ticket, creates another claim or retries the protected read.
pub fn InstalledArenaHost::enter_domain_original_read_consumer(
  self : InstalledArenaHost,
  view : InstalledArenaOriginalReadConsumer,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.require_domain_original_read_consumer_current(view) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match
    @resources.enter_funded_read_consumer(
      view.consumer,
      view.read,
      view.retained_bytes,
      view.execution_bytes,
    ) {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  self.enter_domain_read(view.read.domain).map_err(issue => Domain(issue))
}

///|
/// Leave uses registered original identity even after stop/current refusal.
/// This is only the physical scope ACK. Managed material/escaped outputs must
/// still retire before the original read Owner can acknowledge final cleanup.
pub fn InstalledArenaHost::leave_domain_original_read_consumer(
  self : InstalledArenaHost,
  view : InstalledArenaOriginalReadConsumer,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.original_domain_read_consumer(view) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.leave_domain_original_read(view.read)
}
