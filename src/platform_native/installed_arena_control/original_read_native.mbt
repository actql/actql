///|
/// Private installed profile inputs only. Positive declarations do not prove
/// byte adequacy or complete process funding. The original child allowance
/// bounds their simultaneous reservations; ordinary profile remains absent.
pub(all) struct InstalledArenaOriginalReadBudget {
  bootstrap_retained : Int64
  bootstrap_execution : Int64
  workspace_execution : Int64
  read_retained : Int64
  read_execution : Int64
}

///|
pub(all) enum InstalledArenaOriginalReadIssue {
  Domain(@bootstrap.NativeBackedExecutionIssue)
  Child(@resources.ImportedChildLedgerIssue)
  Read(@resources.OriginalReadIssue)
  Buffer(@buffers.BufferIssue)
}

///|
/// One joined original, registered before child admission or any reservation.
/// No raw Ledger, independent pair/loan input, or physical Boolean is exposed.
struct InstalledArenaOriginalRead {
  domain : InstalledArenaDomain
  mut live : @bootstrap.NativeBackedLiveChild[
    InstalledArenaHost,
    InstalledArenaDomain,
    InstalledArenaOriginalRead,
  ]?
  mut frame : @resources.ImportedChildLedger?
  mut ledger : @resources.Ledger?
  mut bootstrap : @resources.CapacityReservation?
  mut inventory : @resources.OriginalLedgerIdentity?
  mut workspace : @buffers.WorkspaceLoan?
  mut claim : @resources.FundedReadClaim[InstalledArenaOriginalRead]?
  mut pair : @buffers.OriginalWorkspaceRead[InstalledArenaOriginalRead]?
  // The same read Owner retains its one issued consumer through physical ACK.
  // This is not another cleanup controller or a reissued available read pair.
  mut consumer : InstalledArenaOriginalReadConsumer?
  // Only the exact original C-context retirement observation sets this cell.
  // Escaped retired WorkspaceLoans capture this cell, not the parent graph.
  physical_retired : Ref[Bool]
  mut owns_read : Bool
  mut child_started : Bool
  mut read_settled : Bool
  mut inventory_finished : Bool
  mut report_complete : Bool
  mut ready : Bool
  mut closing : Bool
  mut closed : Bool
}

///|
pub(all) enum InstalledArenaOriginalReadAcquisition {
  ReadyOriginalRead(InstalledArenaOriginalRead)
  PendingOriginalRead(
    InstalledArenaOriginalRead,
    InstalledArenaOriginalReadIssue
  )
}

///|
/// Existing parent context only; the separate VM/channel entry is unchanged.
/// Same-domain SQLite or another attempt cannot share this physical purpose.
pub fn InstalledArenaHost::prepare_domain_original_read(
  self : InstalledArenaHost,
  domain : InstalledArenaDomain,
  budget : InstalledArenaOriginalReadBudget,
) -> Result[
  InstalledArenaOriginalReadAcquisition,
  InstalledArenaOriginalReadIssue,
] {
  match self.require_domain_read_current(domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  if domain.crypto_component is Some(_) ||
    domain.sqlite_library is Some(_) ||
    domain.live_channel is Some(_) ||
    domain.original_read is Some(_) ||
    domain.retained_execution is Some(_) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.AlreadyConsumed)))
  }
  if budget.bootstrap_retained <= 0L ||
    budget.bootstrap_execution <= 0L ||
    budget.workspace_execution <= 0L ||
    budget.read_retained <= 0L ||
    budget.read_execution <= 0L {
    return Err(Read(@resources.InvalidBootstrap))
  }
  let record : InstalledArenaOriginalRead = {
    domain,
    live: None,
    frame: None,
    ledger: None,
    bootstrap: None,
    inventory: None,
    workspace: None,
    claim: None,
    pair: None,
    consumer: None,
    physical_retired: Ref(false),
    owns_read: false,
    child_started: false,
    read_settled: false,
    inventory_finished: false,
    report_complete: false,
    ready: false,
    closing: false,
    closed: false,
  }
  domain.original_read = Some(record)
  match record.prepare_original(budget) {
    Err(issue) => Ok(PendingOriginalRead(record, issue))
    Ok(_) => {
      record.ready = true
      Ok(ReadyOriginalRead(record))
    }
  }
}

///|
fn InstalledArenaOriginalRead::prepare_original(
  self : InstalledArenaOriginalRead,
  budget : InstalledArenaOriginalReadBudget,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  let domain = self.domain
  let host = domain.host
  let backing = domain.backing
  let original = domain.domain.unwrap()
  let live = match
    backing.prepare_backed_read_live_child(host, original, domain, self) {
    Err(issue) => return Err(Domain(issue))
    Ok(@bootstrap.LiveChildPending(live, issue)) => {
      self.live = Some(live)
      self.owns_read = true
      return Err(Domain(issue))
    }
    Ok(@bootstrap.LiveChildReady(live)) => live
  }
  self.live = Some(live)
  self.owns_read = true
  match backing.admit_backed_live_child(host, live, self) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  let frame = match
    backing.prepare_backed_original_read_ledger(host, live, self) {
    Err(@bootstrap.Domain(issue)) => return Err(Domain(issue))
    Err(@bootstrap.Child(issue)) => return Err(Child(issue))
    Ok(value) => value
  }
  self.frame = Some(frame)
  match @resources.start_imported_child_ledger(frame) {
    Err(issue) => return Err(Child(issue))
    Ok(_) => self.child_started = true
  }
  let ledger = match @resources.take_imported_original_child_ledger(frame) {
    Err(issue) => return Err(Child(issue))
    Ok(value) => value
  }
  self.ledger = Some(ledger)
  // First serial -1, before every workspace/read token, including zero bytes.
  let bootstrap = match
    @resources.reserve_capacity(
      ledger,
      budget.bootstrap_retained,
      budget.bootstrap_execution,
    ) {
    Err(issue) => return Err(Read(@resources.Resource(issue)))
    Ok(value) => value
  }
  self.bootstrap = Some(bootstrap)
  // This closed slice has one workspace and one read reservation, no holding
  // or delegated child. These counts do not prove a numerical byte profile.
  let inventory = match
    @resources.begin_original_ledger_inventory(ledger, bootstrap, 2, 0, 0) {
    Err(issue) => return Err(Read(issue))
    Ok(value) => value
  }
  self.inventory = Some(inventory)
  let retired = self.physical_retired
  let workspace = match
    @buffers.reserve_workspace(
      ledger,
      budget.workspace_execution,
      () => retired.val,
      () => retired.val,
    ) {
    Err(issue) => return Err(Buffer(issue))
    Ok(value) => value
  }
  self.workspace = Some(workspace)
  let descriptor = match
    @resources.issue_recorded_original_ledger_descriptor(inventory, self) {
    Err(issue) => return Err(Read(issue))
    Ok(value) => value
  }
  let claim = match
    @resources.fund_original_read(
      ledger,
      self,
      descriptor,
      budget.read_retained,
      budget.read_execution,
    ) {
    Err(issue) => return Err(Read(issue))
    Ok(value) => value
  }
  self.claim = Some(claim)
  let pair = match
    @buffers.issue_workspace_original_read(claim, self, workspace) {
    Err(issue) => return Err(Read(issue))
    Ok(value) => value
  }
  self.pair = Some(pair)
  match host.require_domain_read_current(domain) {
    Err(issue) => Err(Domain(issue))
    Ok(_) => Ok(())
  }
}

///|
fn InstalledArenaHost::original_domain_read(
  self : InstalledArenaHost,
  record : InstalledArenaOriginalRead,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  if !physical_equal(record.domain.host, self) ||
    !self.domains.any(domain => physical_equal(domain, record.domain)) ||
    !(record.domain.original_read is Some(original) &&
    physical_equal(original, record)) {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ForeignOriginal)))
  }
  Ok(())
}

///|
/// A bounded borrow from this joined carrier. Consumers retain this original
/// through Root/Reader/returned Bytes and recheck after physical operations.
pub fn InstalledArenaHost::require_domain_original_read_current(
  self : InstalledArenaHost,
  record : InstalledArenaOriginalRead,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.original_domain_read(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !record.ready || record.closing || record.closed {
    return Err(Read(@resources.CleanupPending))
  }
  match self.require_domain_read_current(record.domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  guard record.pair is Some(pair) &&
    record.workspace is Some(workspace) &&
    record.claim is Some(claim) else {
    return Err(Read(@resources.IncompleteInventory))
  }
  if !@buffers.workspace_original_read_matches(pair, claim, record, workspace) {
    return Err(Read(@resources.ChangedOriginalState))
  }
  Ok(())
}

///|
pub fn InstalledArenaHost::borrow_domain_original_read(
  self : InstalledArenaHost,
  record : InstalledArenaOriginalRead,
) -> Result[
  (
    @buffers.OriginalWorkspaceRead[InstalledArenaOriginalRead],
    @buffers.WorkspaceLoan,
  ),
  InstalledArenaOriginalReadIssue,
] {
  match self.require_domain_original_read_current(record) {
    Err(issue) => Err(issue)
    Ok(_) => Ok((record.pair.unwrap(), record.workspace.unwrap()))
  }
}

///|
/// The consumer supplies only the joined original, not another domain whose
/// metadata resembles it. Bracket input construction and escaped outputs too.
pub fn InstalledArenaHost::enter_domain_original_read(
  self : InstalledArenaHost,
  record : InstalledArenaOriginalRead,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.require_domain_original_read_current(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  self.enter_domain_read(record.domain).map_err(issue => Domain(issue))
}

///|
pub fn InstalledArenaHost::enter_domain_original_read_cleanup(
  self : InstalledArenaHost,
  record : InstalledArenaOriginalRead,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.original_domain_read(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !record.owns_read || record.closed {
    return Err(Read(@resources.CleanupPending))
  }
  record.closing = true
  record.ready = false
  self.enter_domain_read_cleanup(record.domain).map_err(issue => Domain(issue))
}

///|
pub fn InstalledArenaHost::leave_domain_original_read(
  self : InstalledArenaHost,
  record : InstalledArenaOriginalRead,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.original_domain_read(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if !record.owns_read || record.closed {
    return Err(Read(@resources.CleanupPending))
  }
  self.leave_domain_read(record.domain).map_err(issue => Domain(issue))
}

///|
/// Same original cleanup only. No caller ACK, replacement context, second
/// Ledger, or retries of start/admission. C waits for scopes and last aliases;
/// its exact close ACK precedes workspace/read/census settlement and reporting.
pub fn InstalledArenaHost::close_domain_original_read(
  self : InstalledArenaHost,
  record : InstalledArenaOriginalRead,
) -> Result[Unit, InstalledArenaOriginalReadIssue] {
  match self.original_domain_read(record) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if record.closed {
    return Ok(())
  }
  // Component/Library users belong to this same Read, not a parent-close ACK.
  // Keep the original claim and frame usable for their explicit cleanup first.
  if record.domain.crypto_component is Some(component) && !component.closed {
    return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
  }
  record.closing = true
  record.ready = false
  // Preparation refused before publishing a live access. This carrier owns
  // no context/borrow: do not stop another original access to this domain.
  if !record.owns_read {
    record.closed = true
    return Ok(())
  }
  let domain = record.domain
  let original = match self.original_read_domain(domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(value) => value
  }
  if !record.read_settled && record.claim is Some(claim) {
    match @resources.stop_funded_read(claim) {
      Err(issue) => return Err(Read(issue))
      Ok(_) => ()
    }
  }
  if record.frame is Some(frame) {
    match @resources.stop_imported_child_ledger(frame) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => ()
    }
  }
  // Common return may remain pending because this live projection still owns
  // the same use. Observe physical retirement explicitly, never from Err alone.
  if !record.physical_retired.val {
    // The same Ledger can retain immutable usage snapshots allocated during
    // this Read. Copy only its stopped control DATA outside every child frame
    // before asking C to retire that frame. Escaped old aliases remain BUSY.
    if original_read_control_scope_clear_ffi() != 1 {
      return Err(Domain(@bootstrap.Bootstrap(@bootstrap.ReadersPending)))
    }
    if record.frame is Some(frame) {
      match @resources.relocate_imported_child_cleanup_usage(frame) {
        Err(issue) => return Err(Child(issue))
        Ok(_) => ()
      }
    }
    if record.consumer is Some(view) && view.working_snapshot_pending {
      match
        @resources.relocate_funded_read_consumer_cleanup_state(
          view.consumer,
          record,
        ) {
        Err(issue) => return Err(Read(issue))
        Ok(_) => view.working_snapshot_pending = false
      }
    }
    let context_close = domain.backing.close_backed_read_context(
      self, original, domain,
    )
    match
      domain.backing.require_backed_read_context_retired(self, original, domain) {
      Err(_) =>
        return match context_close {
          Err(issue) => Err(Domain(issue))
          Ok(_) => Err(Read(@resources.CleanupPending))
        }
      Ok(_) => record.physical_retired.val = true
    }
  }
  if record.workspace is Some(workspace) {
    match @buffers.close_workspace(workspace) {
      Err(issue) => return Err(Buffer(issue))
      Ok(_) => ()
    }
  }
  if record.claim is Some(claim) {
    if !record.read_settled {
      match @resources.settle_funded_read(claim, true) {
        Err(issue) => return Err(Read(issue))
        Ok(_) => record.read_settled = true
      }
    }
    if record.pair is Some(pair) && record.workspace is Some(workspace) {
      match @buffers.retire_workspace_original_read(pair, record, workspace) {
        Err(issue) => return Err(Read(issue))
        Ok(_) => record.pair = None
      }
    }
  }
  if !record.inventory_finished {
    if record.inventory is Some(_) && record.ledger is Some(ledger) {
      match @resources.finish_original_ledger_inventory(ledger, true) {
        Err(issue) => return Err(Read(issue))
        Ok(false) => return Err(Read(@resources.CleanupPending))
        Ok(true) => record.inventory_finished = true
      }
    } else if record.bootstrap is Some(bootstrap) &&
      record.ledger is Some(ledger) {
      match @resources.settle_capacity(ledger, bootstrap) {
        Err(issue) => return Err(Read(@resources.Resource(issue)))
        Ok(_) => record.inventory_finished = true
      }
    }
  }
  if !record.report_complete &&
    record.child_started &&
    record.frame is Some(frame) {
    match @resources.report_imported_child_ledger(frame) {
      Err(issue) => return Err(Child(issue))
      Ok(_) => record.report_complete = true
    }
  }
  if record.live is Some(live) {
    match
      domain.backing.retire_backed_live_child_after_owner_ack(
        self, live, record,
      ) {
      Err(issue) => return Err(Domain(issue))
      Ok(_) => record.live = None
    }
  }
  match domain.backing.close_backed_read_context(self, original, domain) {
    Err(issue) => return Err(Domain(issue))
    Ok(_) => ()
  }
  record.frame = None
  record.ledger = None
  record.bootstrap = None
  record.inventory = None
  record.workspace = None
  record.claim = None
  record.consumer = None
  record.closed = true
  Ok(())
}

///|
extern "C" fn original_read_control_scope_clear_ffi() -> Int = "actql_bootstrap_control_scope_clear"
