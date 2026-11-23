///|
/// An input-bound view of one existing backed child, not another resource or
/// physical cleanup Owner. Only a fresh nominal live projection can issue it.
/// The same physical issuer retains its original frame and performs its ACK.
struct BackedInitializationAdmission[I] {
  mut original : BackedInitializationAdmission[I]?
  mut input : I?
  frame : ImportedChildLedger
  owner_retired : () -> Bool
  mut transitioning : Bool
  mut host_taken : Bool
  mut preparation_selected : Bool
  mut cleanup_phase : BackedInitializationCleanupPhase
}

///|
priv enum BackedInitializationCleanupPhase {
  AwaitingUsageReport
  CleanupUsageAcknowledged
  InputAliasRetired
}

///|
/// Select initialization before any child frame/start/take. The runtime is
/// this SAME original input; equal DATA, a started Read frame, callbacks and
/// numerical limits cannot supply the association or another allowance.
/// Optional acquisition belongs only to this nominal growable child's physical
/// issuer. It survives the initialized Request continuation on the same frame.
pub fn[P, C, I] prepare_backed_initialization_admission(
  projection : BackedExecutionLiveProjection[P, C, I],
  input : I,
  acquire_window? : ((Int64, Int64) -> Result[Unit, LedgerIssue])? = None,
) -> Result[BackedInitializationAdmission[I], ImportedChildLedgerIssue] {
  match backed_live_projection_original(projection, input) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  let frame = match
    prepare_backed_original_child_ledger(projection, input, acquire_window~) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  let owner : BackedInitializationAdmission[I] = {
    original: None,
    input: Some(input),
    frame,
    // This captured nominal projection is changed only by the existing
    // after-owner-ACK retirement. No caller supplies a Boolean or callback.
    owner_retired: () => projection.retired_after_owner_ack,
    transitioning: false,
    host_taken: false,
    preparation_selected: false,
    cleanup_phase: AwaitingUsageReport,
  }
  owner.original = Some(owner)
  Ok(owner)
}

///|
fn[I] backed_initialization_original(
  owner : BackedInitializationAdmission[I],
) -> Result[Unit, ImportedChildLedgerIssue] {
  guard owner.original is Some(original) && physical_equal(original, owner) else {
    return Err(ForeignOriginal)
  }
  if owner.transitioning {
    Err(Unknown)
  } else {
    Ok(())
  }
}

///|
pub fn[I] check_backed_initialization_input(
  owner : BackedInitializationAdmission[I],
  input : I,
) -> Result[Unit, ImportedChildLedgerIssue] {
  match backed_initialization_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.cleanup_phase is InputAliasRetired || (owner.owner_retired)() {
    return Err(Unavailable)
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
/// Trusted Native preparation assembly starts/takes the same child once, then
/// installs its actual funded bootstrap census before the Host body takes it.
/// Failure keeps this original frame with its physical issuer. This cannot
/// convert a completed Request/Read and is never a JavaScript Ledger getter.
pub fn[I] start_backed_initialization_admission(
  owner : BackedInitializationAdmission[I],
) -> Result[Ledger, ImportedChildLedgerIssue] {
  match backed_initialization_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.cleanup_phase is InputAliasRetired || (owner.owner_retired)() {
    return Err(Unavailable)
  }
  owner.transitioning = true
  let outcome = match start_imported_child_ledger(owner.frame) {
    Err(issue) => Err(issue)
    Ok(_) => take_imported_original_child_ledger(owner.frame)
  }
  owner.transitioning = false
  outcome
}

///|
/// Consume the actual prepared input/census for the shared Host body, without
/// starting or taking its physical child again. No caller-supplied Ledger,
/// slot counts, scalar allowance or cleanup observation enters this handoff.
pub fn[I] take_backed_initialization_admission(
  owner : BackedInitializationAdmission[I],
  input : I,
) -> Result[Ledger, ImportedChildLedgerIssue] {
  take_backed_initialization_for_host(owner, input, false)
}

///|
fn[I] take_backed_initialization_for_host(
  owner : BackedInitializationAdmission[I],
  input : I,
  request : Bool,
) -> Result[Ledger, ImportedChildLedgerIssue] {
  match check_backed_initialization_input(owner, input) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.host_taken || owner.preparation_selected != request {
    return Err(AlreadyConsumed)
  }
  let frame = owner.frame
  guard frame.taken && frame.ledger is Some(ledger) else {
    return Err(Unavailable)
  }
  if request {
    // The Request itself owns the FIRST working reservation/census. An
    // initialized Source bootstrap cannot become this pristine continuation.
    if !backed_request_ledger_pristine(ledger) {
      return Err(Unavailable)
    }
    owner.host_taken = true
    owner.transitioning = true
    let current = check_imported_child_admission(ledger)
    owner.transitioning = false
    match current {
      Err(issue) => return Err(Resource(issue))
      Ok(_) => ()
    }
    if !backed_request_ledger_pristine(ledger) {
      return Err(Unavailable)
    }
    return Ok(ledger)
  }
  guard ledger.original_inventory is Some(inventory) &&
    physical_equal(inventory.bootstrap.reservation.owner, ledger) &&
    original_ledger_inventory_available(inventory.identity) &&
    !inventory.closing &&
    original_ledger_has_only_bootstrap(ledger, inventory.bootstrap) else {
    return Err(Unavailable)
  }
  owner.host_taken = true
  owner.transitioning = true
  let current = check_imported_child_admission(ledger)
  owner.transitioning = false
  match current {
    Err(issue) => return Err(Resource(issue))
    Ok(_) => ()
  }
  // The original current callback may begin retirement or change the census.
  // A later success cannot restore this same one-shot handoff or replace it.
  guard ledger.original_inventory is Some(selected) &&
    physical_equal(selected, inventory) &&
    original_ledger_inventory_available(inventory.identity) &&
    !inventory.closing &&
    original_ledger_has_only_bootstrap(ledger, inventory.bootstrap) else {
    return Err(Unavailable)
  }
  Ok(ledger)
}

///|
/// Trusted physical issuer only. Retain this same frame before entering the
/// shared Host body; its existing stop/C-context/report duties are not moved
/// into the portable body or replaced with Node's cleanup ordering.
pub fn[I] backed_initialization_original_frame(
  owner : BackedInitializationAdmission[I],
  input : I,
) -> Result[ImportedChildLedger, ImportedChildLedgerIssue] {
  match backed_initialization_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.input is Some(original) && physical_equal(original, input) else {
    return Err(ForeignOriginal)
  }
  Ok(owner.frame)
}

///|
/// Original publication history only, for the physical issuer's existing
/// partial-start cleanup. It supplies no currentness, new take or ACK.
pub fn[I] backed_initialization_ledger_published(
  owner : BackedInitializationAdmission[I],
  input : I,
) -> Result[Bool, ImportedChildLedgerIssue] {
  match backed_initialization_original_frame(owner, input) {
    Err(issue) => Err(issue)
    Ok(frame) => Ok(frame.ledger is Some(_))
  }
}

///|
fn backed_initialization_cleanup_quiescent(
  ledger : Ledger,
) -> Result[Unit, ImportedChildLedgerIssue] {
  // Zero-sized original identities still require their own retirement.
  if !continuation_quiescent(ledger) {
    return Err(Unavailable)
  }
  if ledger.original_inventory is Some(inventory) && inventory.park is Some(_) {
    return Err(Resource(ResourceParked))
  }
  Ok(())
}

///|
/// Report the stopped, quiescent original ledger to its existing parent.
/// Only its acknowledged report can release a later alias with uncertain
/// transfer history. The report keeps the same debt and grants no physical ACK.
pub fn[I] report_backed_initialization_cleanup_usage(
  owner : BackedInitializationAdmission[I],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match backed_initialization_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.cleanup_phase is CleanupUsageAcknowledged {
    return Ok(())
  }
  if owner.cleanup_phase is InputAliasRetired || (owner.owner_retired)() {
    return Err(Unavailable)
  }
  let frame = owner.frame
  if frame.stop_outcome is Some(issue) {
    return Err(issue)
  }
  guard frame.stop_attempted && frame.ledger is Some(ledger) else {
    return Err(Unavailable)
  }
  match backed_initialization_cleanup_quiescent(ledger) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  owner.transitioning = true
  let result = report_imported_child_ledger(frame)
  owner.transitioning = false
  match result {
    Err(issue) => Err(issue)
    Ok(_) => {
      owner.cleanup_phase = CleanupUsageAcknowledged
      Ok(())
    }
  }
}

///|
/// The common Host has already retired its selected body and all borrowers.
/// Logical stop keeps Native cleanup/report possible; only the SAME physical
/// owner's actual after-ACK retirement permits releasing this input alias.
pub fn[I] cleanup_backed_initialization_admission(
  owner : BackedInitializationAdmission[I],
) -> Result[Unit, ImportedChildLedgerIssue] {
  match backed_initialization_original(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if owner.cleanup_phase is InputAliasRetired {
    return Ok(())
  }
  let frame = owner.frame
  if frame.pending_report is Some(_) {
    return Err(frame.pending_report_issue.unwrap_or(Unknown))
  }
  if frame.stop_outcome is Some(issue) {
    return Err(issue)
  }
  if frame.ledger is Some(ledger) {
    // Unknown is historical debt once the exact stopped ledger has been
    // reported. An acknowledged physical retirement alone cannot proxy it.
    if ledger_usage(ledger).uncertain_transfer_bytes != 0L &&
      owner.cleanup_phase is AwaitingUsageReport {
      return Err(Unavailable)
    }
    match backed_initialization_cleanup_quiescent(ledger) {
      Err(issue) => return Err(issue)
      Ok(_) => ()
    }
  }
  if (owner.owner_retired)() {
    owner.input = None
    owner.cleanup_phase = InputAliasRetired
    return Ok(())
  }
  owner.transitioning = true
  let outcome = stop_imported_child_ledger(owner.frame)
  owner.transitioning = false
  match outcome {
    Err(issue) => Err(issue)
    Ok(_) => Err(Unavailable)
  }
}
