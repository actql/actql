///|
// A physical sub-scope of the same one-shot consuming execution. An attempted
// foreign call is cleanup-only until its actual result is retained here.
priv enum InstalledArenaOriginalReadConsumerScope {
  ConsumerScopeNew
  ConsumerScopeOpen
  ConsumerScopeLeft
  ConsumerScopeCleanupOnly
} derive(Eq)

///|
/// The existing read Owner's issued consuming view. The original read keeps
/// this reference until its existing physical close/settlement succeeds.
/// No Ledger, copied descriptor, second reservation or cleanup state escapes.
struct InstalledArenaOriginalReadConsumer {
  host : InstalledArenaHost
  read : InstalledArenaOriginalRead
  consumer : @resources.FundedReadConsumer[InstalledArenaOriginalRead]
  workspace : @buffers.WorkspaceLoan
  initial_retained_bytes : Int64
  initial_execution_bytes : Int64
  mut retained_bytes : Int64
  mut execution_bytes : Int64
  // A control relocation duty, never a physical retirement acknowledgement.
  mut working_snapshot_pending : Bool
  mut scope : InstalledArenaOriginalReadConsumerScope
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
    initial_retained_bytes: retained_bytes,
    initial_execution_bytes: execution_bytes,
    retained_bytes,
    execution_bytes,
    working_snapshot_pending: false,
    scope: ConsumerScopeNew,
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
  if view.scope == ConsumerScopeCleanupOnly ||
    !read.ready ||
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
  self.enter_original_consumer_scope(view)
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
  let normal = view.scope == ConsumerScopeOpen
  // An interruption or failed leave must never publish a reusable sub-scope.
  view.scope = ConsumerScopeCleanupOnly
  match self.leave_domain_original_read(view.read) {
    Err(issue) => Err(issue)
    Ok(_) => {
      if normal {
        view.scope = ConsumerScopeLeft
      }
      Ok(())
    }
  }
}

///|
fn InstalledArenaHost::enter_original_consumer_scope(
  self : InstalledArenaHost,
  view : InstalledArenaOriginalReadConsumer,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  view.scope = ConsumerScopeCleanupOnly
  match self.enter_domain_read(view.read.domain) {
    Err(issue) => Err(Domain(issue))
    Ok(_) => {
      view.scope = ConsumerScopeOpen
      Ok(())
    }
  }
}

///|
/// Resume only this same consuming execution after an actual successful leave.
/// This enters no second Resource claim, ticket, reservation or logical read.
/// A failed/unknown physical entry or leave remains cleanup-only permanently.
pub fn InstalledArenaHost::resume_domain_original_read_consumer_scope(
  self : InstalledArenaHost,
  view : InstalledArenaOriginalReadConsumer,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.require_domain_original_read_consumer_current(view) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if view.scope != ConsumerScopeLeft {
    return Err(Read(@resources.SpentClaim))
  }
  self.enter_original_consumer_scope(view)
}

///|
/// Extend this SAME entered Read consumer before constructing its complete
/// next coexistence envelope. Core mutates the original reservation, not a
/// second token/Root or a handed-off capacity. This does not acquire a mapping:
/// the actual Native domain and constructor backing remain separate duties.
pub fn InstalledArenaHost::grow_domain_original_read_consumer_capacity(
  self : InstalledArenaHost,
  view : InstalledArenaOriginalReadConsumer,
  retained_bytes : Int64,
  execution_bytes : Int64,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.original_domain_read_consumer(view) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let read = view.read
  if view.scope != ConsumerScopeOpen ||
    !read.ready ||
    read.closing ||
    read.closed ||
    view.workspace.closing ||
    view.workspace.stopped ||
    view.workspace.cleaned ||
    view.workspace.settled {
    return Err(Read(@resources.CleanupPending))
  }
  if retained_bytes < view.retained_bytes ||
    execution_bytes < view.execution_bytes {
    return Err(Read(@resources.Resource(@resources.InvalidCharge)))
  }
  // Retain this cleanup duty before the fallible Resource call can construct
  // or publish a child-owned snapshot, including a partial/refused outcome.
  view.working_snapshot_pending = true
  // The imported original's current callback is inside the one Resource
  // mutation. Do not repeat it in a pre-check or replace its nominal binding.
  match
    @resources.grow_funded_read_consumer_capacity(
      view.consumer,
      read,
      retained_bytes,
      execution_bytes,
    ) {
    Err(issue) => return Err(Read(issue))
    Ok(_) => ()
  }
  view.retained_bytes = retained_bytes
  view.execution_bytes = execution_bytes
  Ok(())
}

///|
/// Fund the next original constructor peak, then obtain actual backing on its
/// SAME Native domain. Repeated phases take a maximum over the original base;
/// they do not accumulate temporary peaks or refund an earlier reservation.
pub fn InstalledArenaHost::prepare_domain_original_read_construction(
  self : InstalledArenaHost,
  read : InstalledArenaOriginalRead,
  retained_bytes : Int64,
  execution_bytes : Int64,
  contiguous_bytes : Int64,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  guard physical_equal(read.domain.host, self) &&
    read.consumer is Some(view) &&
    read.domain.domain is Some(domain) &&
    retained_bytes >= 0L &&
    execution_bytes >= 0L &&
    contiguous_bytes > 0L &&
    retained_bytes <= 9223372036854775807L - view.initial_retained_bytes &&
    execution_bytes <= 9223372036854775807L - view.initial_execution_bytes else {
    return Err(Read(@resources.Resource(@resources.InvalidCharge)))
  }
  let retained = Int64::max(
    view.retained_bytes,
    view.initial_retained_bytes + retained_bytes,
  )
  let execution = Int64::max(
    view.execution_bytes,
    view.initial_execution_bytes + execution_bytes,
  )
  match
    self.grow_domain_original_read_consumer_capacity(view, retained, execution) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  // A logical resize alone is never successful physical acquisition. The
  // original consumer and pending supplier receipt stay cleanup-only on error.
  match
    read.domain.backing.prepare_backed_read_working(
      self,
      domain,
      read.domain,
      contiguous_bytes,
    ) {
    Err(issue) => {
      view.scope = ConsumerScopeCleanupOnly
      Err(Domain(issue))
    }
    Ok(_) => Ok(())
  }
}
