///|
/// This projection retains an existing Ledger reservation through failed or
/// uncertain persistence. It is not another capacity Owner or permission.
/// The caller must keep this original responsibility through confirmed cleanup;
/// no public settlement shortcut is supplied by this preparation unit.
#warnings("-struct_never_constructed")
struct NativeInitialCatalogUseCustody {
  ledger : @resources.Ledger
  reservation : @resources.CapacityReservation
  dispatch_cid : String
  journal : Journal
  request : @remote.DispatchRequest
  mut accepted : Bool
  mut cleanup_started : Bool
  mut removal_confirmed : Bool
}

///|
pub fn initial_catalog_use_custody_pending(
  value : NativeInitialCatalogUseCustody,
) -> Bool {
  @resources.capacity_reservation_open(value.reservation)
}

///|
/// Informational projections of the same charged original responsibility.
/// Neither exposes a settlement handle or a send permission.
pub fn initial_catalog_use_custody_usage(
  value : NativeInitialCatalogUseCustody,
) -> @resources.LedgerUsage {
  @resources.ledger_usage(value.ledger)
}

///|
pub fn initial_catalog_use_custody_dispatch(
  value : NativeInitialCatalogUseCustody,
) -> String {
  value.dispatch_cid
}

///|
/// Cleanup checks the original funding owner; equal budget values do not
/// identify the producer's CapturedDAG Ledger.
pub fn initial_catalog_use_custody_matches_ledger(
  value : NativeInitialCatalogUseCustody,
  ledger : @resources.Ledger,
) -> Bool {
  physical_equal(value.ledger, ledger)
}

///|
fn initial_catalog_use_envelope_valid(
  value : NativeInitialCatalogUseEnvelope,
) -> Bool {
  value.record_bytes > 0L &&
  value.control_bytes > 0L &&
  value.record_bytes <= 9223372036854775807L - value.control_bytes &&
  value.workspace_bytes > 0L
}

///|
/// Bind original eligibility to the real initial acceptance transaction. The
/// actual original Run Ledger and reviewed Host envelope are trusted caller
/// inputs, not fields adopted from a candidate dispatch body. Duplicates return
/// no new custody and consume no extra reservation. The normal accept path does
/// not mint this marker, and old records are never backfilled.
pub fn Journal::accept_with_initial_catalog_use(
  self : Journal,
  request : @remote.DispatchRequest,
  original_run_ledger : @resources.Ledger,
  envelope : NativeInitialCatalogUseEnvelope,
) -> Result[
  (
    @remote.DispatchAcceptance,
    @remote.DispatchRecord,
    NativeInitialCatalogUseCustody?,
  ),
  NativeInitialCatalogUseFailure,
] {
  if !initial_catalog_use_envelope_valid(envelope) ||
    envelope.record_bytes > self.max_record_bytes {
    return Err({ issue: Capacity(@resources.InvalidCharge), custody: None, })
  }
  let mut retained : NativeInitialCatalogUseCustody? = None
  let mut capacity_issue : @resources.LedgerIssue? = None
  let result = self.accept_with_initial_custody(
    request,
    Some(_ => {
      let reservation = match
        @resources.reserve_capacity(
          original_run_ledger,
          envelope.record_bytes + envelope.control_bytes,
          envelope.workspace_bytes,
        ) {
        Ok(value) => value
        Err(issue) => {
          capacity_issue = Some(issue)
          return Err(Physical(@sqlite.CapacityExceeded))
        }
      }
      let custody : NativeInitialCatalogUseCustody = {
        ledger: original_run_ledger,
        reservation,
        dispatch_cid: @remote.dispatch_request_identity(request),
        journal: self,
        request,
        accepted: false,
        cleanup_started: false,
        removal_confirmed: false,
      }
      retained = Some(custody)
      // Allocate the private original-body projection only after the envelope is
      // charged. Canonical original request bytes retain all admitted identities;
      // the private row adds neither a public wire contract nor another CID.
      let body = match @remote.dispatch_request_json(request) {
        Ok(value) => @utf8.encode(value)
        Err(issue) => return Err(Protocol(issue))
      }
      if body.length().to_int64() > envelope.record_bytes {
        return Err(Physical(@sqlite.CapacityExceeded))
      }
      match
        self.database.insert(
          "site_initial_catalog_use",
          custody.dispatch_cid,
          body,
        ) {
        Ok(0L) => Ok(())
        Ok(_) => Err(StateCollision)
        Err(issue) => Err(Physical(issue))
      }
    }),
  )
  match result {
    Ok((acceptance, record)) => {
      if retained is Some(custody) {
        custody.accepted = true
      }
      Ok((acceptance, record, retained))
    }
    Err(issue) =>
      Err({
        issue: match capacity_issue {
          Some(value) => Capacity(value)
          None => Journal(issue)
        },
        custody: retained,
      })
  }
}

///|
fn Journal::require_initial_catalog_use(
  self : Journal,
  request : @remote.DispatchRequest,
  revision : Int64,
) -> Result[@sqlite.NativeJournalValue, NativeRemoteJournalIssue] {
  match self.require(request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let expected = match @remote.dispatch_request_json(request) {
    Ok(value) => @utf8.encode(value)
    Err(issue) => return Err(Protocol(issue))
  }
  let value = match
    self.database.read(
      "site_initial_catalog_use",
      @remote.dispatch_request_identity(request),
    ) {
    Ok(value) => value
    Err(issue) => return Err(Physical(issue))
  }
  if value.revision != revision || value.body != expected {
    return Err(StateCollision)
  }
  Ok(value)
}

///|
/// Consume the original eligibility once, before Resource use selection. This
/// marker is irreversible here: missing/claimed/unknown rows never permit a new
/// claim. Current authorization and Credential Resource fences remain required.
pub fn Journal::claim_initial_catalog_use(
  self : Journal,
  request : @remote.DispatchRequest,
) -> Result[NativeInitialCatalogUseClaim, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let result = (fn() {
    // Reuse the actual Site admission Owner; an unchanged stored marker is not
    // evidence that its original generation/runtime is still current.
    match @remote.prepare_dispatch_acceptance(self.control, request) {
      Ok(_) => ()
      Err(issue) => return Err(Protocol(issue))
    }
    let original = match self.require_initial_catalog_use(request, 0L) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    match self.cancellation_requested(request) {
      Ok(false) => ()
      Ok(true) => return Err(StateCollision)
      Err(issue) => return Err(issue)
    }
    match
      self.database.compare_exchange(
        "site_initial_catalog_use",
        @remote.dispatch_request_identity(request),
        0L,
        original.body,
      ) {
      Ok(1L) => Ok(())
      Ok(_) => Err(StateCollision)
      Err(issue) => Err(Physical(issue))
    }
  })()
  match self.finish_effect_checkpoint_mutation(result) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  // Commit uncertainty returns above, never a fresh nominal claim.
  match self.require_initial_catalog_use(request, 1L) {
    Ok(_) => Ok({ journal: self, request, })
    Err(issue) => Err(issue)
  }
}

///|
/// The Resource Owner passes its actual nominal use after durable selection.
/// A candidate grant/use cannot replace the exact original claim and dispatch.
/// Journal confirmation still grants no send or Host permission.
pub fn Journal::retain_initial_catalog_use(
  self : Journal,
  claim : NativeInitialCatalogUseClaim,
  original_grant : @credential.RemoteCredentialGrant,
  original_use : @credential.RemoteCredentialUse,
) -> Result[Unit, NativeRemoteJournalIssue] {
  if self.closed {
    return Err(Closed)
  }
  if !physical_equal(claim.journal, self) ||
    !catalog_use_matches_dispatch(claim.request, original_grant, original_use) {
    return Err(StateCollision)
  }
  match self.require_initial_catalog_use(claim.request, 1L) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  self.retain_effect_catalog_use(claim.request, original_grant, original_use)
}

///|
/// Retire only this nominal control-row responsibility. The private holder
/// calls this after actual Review/Resource, Runtime, borrow and receiver cleanup.
/// This method does not accept a caller boolean as evidence, claim overall
/// physical cleanup, or reconcile an unknown GET as unsent. The formal release
/// fence belongs to this consumer, never the funding producer.
pub fn Journal::cleanup_initial_catalog_use(
  self : Journal,
  custody : NativeInitialCatalogUseCustody,
) -> Result[Unit, NativeInitialCatalogUseIssue] {
  if !physical_equal(self, custody.journal) || !custody.accepted {
    return Err(Journal(StateCollision))
  }
  if !@resources.capacity_reservation_open(custody.reservation) {
    return if custody.removal_confirmed {
      Ok(())
    } else {
      Err(Journal(StateCollision))
    }
  }
  if self.closed {
    return Err(Journal(Closed))
  }
  match self.begin_mutation(true) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  let result = (fn() -> Result[Unit, NativeRemoteJournalIssue] {
    let record = match self.require(custody.request) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if !@remote.remote_runtime_record_released(record) {
      return Err(StateCollision)
    }
    let expected = match @remote.dispatch_request_json(custody.request) {
      Ok(value) => @utf8.encode(value)
      Err(issue) => return Err(Protocol(issue))
    }
    match self.database.read("site_initial_catalog_use", custody.dispatch_cid) {
      Ok(value) => {
        if custody.removal_confirmed ||
          !initial_catalog_use_cleanup_row_matches(
            expected,
            value.body,
            value.revision,
          ) {
          return Err(StateCollision)
        }
        match
          self.database.remove_exact(
            "site_initial_catalog_use",
            custody.dispatch_cid,
            value.revision,
            value.body,
          ) {
          Ok(_) => {
            // Only this actual exact removal starts absence reconciliation.
            // A lost commit reply keeps this same nominal operation pending.
            custody.cleanup_started = true
            Ok(())
          }
          Err(issue) => Err(Physical(issue))
        }
      }
      Err(@sqlite.NotFound) if custody.cleanup_started => Ok(())
      Err(issue) => Err(Physical(issue))
    }
  })()
  match self.finish_effect_checkpoint_mutation(result) {
    Ok(_) => ()
    Err(issue) => return Err(Journal(issue))
  }
  match self.database.read("site_initial_catalog_use", custody.dispatch_cid) {
    Err(@sqlite.NotFound) if custody.cleanup_started =>
      custody.removal_confirmed = true
    Ok(_) => return Err(Journal(StateCollision))
    Err(issue) => return Err(Journal(Physical(issue)))
  }
  // Commit and same-handle absence are confirmed before the exact original
  // Ledger charge is returned. Failed settlement retains that same reservation.
  @resources.settle_capacity(custody.ledger, custody.reservation).map_err(issue => {
    Capacity(issue)
  })
}
