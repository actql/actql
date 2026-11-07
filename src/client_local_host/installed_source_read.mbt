///|
/// Consumer of an already issued original Resource child, never a capacity
/// issuer or another Run/cleanup owner. Begin before covered preparation; the
/// physical installation retains this same child through failure and cleanup.
struct ClientInstalledSourceRead {
  mut original : ClientInstalledSourceRead?
  mut child : @resources.ImportedChildLedger?
  mut managed_run : (ClientInstalledManagedRun, Int)?
  mut ledger : @resources.Ledger?
  mut owner : ClientLocalSequenceOwner?
  mut declaration : @row_source_host.RowDeclaration?
  mut requirement : @planning.QueryRequirement?
  mut acquisition : @row_source_host.RowAcquisition?
  mut whole_input : ClientInstalledWholeSourceCapacity?
  mut run : @row_source_host.RowRun?
  mut started : Bool
}

///|
pub(all) enum ClientInstalledSourceReadIssue {
  ForeignOriginal
  AlreadyBound
  AlreadyStarted
  Unbound
  Retired
  CleanupPending
  Import(@resources.ImportedChildLedgerIssue)
  Resource(@resources.LedgerIssue)
  Acquisition(@row_source_host.RowHostIssue)
  ManagedRun(ClientInstalledManagedRunIssue)
}

///|
/// The existing Resource owner admits/takes one same-parent accounting view.
/// No scalar limits, public callback or initial-control credit can enter this
/// consumer. A failed start/take keeps the original child with its issuer.
pub fn begin_installed_source_read(
  child : @resources.ImportedChildLedger,
) -> Result[ClientInstalledSourceRead, ClientInstalledSourceReadIssue] {
  match @resources.start_imported_child_ledger(child) {
    Err(issue) => return Err(Import(issue))
    Ok(_) => ()
  }
  let ledger = match @resources.take_imported_original_child_ledger(child) {
    Err(issue) => return Err(Import(issue))
    Ok(value) => value
  }
  let value : ClientInstalledSourceRead = {
    original: None,
    child: Some(child),
    managed_run: None,
    ledger: Some(ledger),
    owner: None,
    declaration: None,
    requirement: None,
    acquisition: None,
    whole_input: None,
    run: None,
    started: false,
  }
  value.original = Some(value)
  Ok(value)
}

///|
fn require_installed_source_read_original(
  value : ClientInstalledSourceRead,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  guard value.original is Some(original) && physical_equal(original, value) else {
    return Err(ForeignOriginal)
  }
  Ok(())
}

///|
fn require_installed_source_read_current(
  value : ClientInstalledSourceRead,
) -> Result[@resources.Ledger, ClientInstalledSourceReadIssue] {
  match require_installed_source_read_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.ledger is Some(ledger) else { return Err(Retired) }
  if value.managed_run is Some((run, occurrence)) {
    let original = match require_installed_managed_run(run) {
      Err(Ledger(issue)) => return Err(Resource(issue))
      Err(issue) => return Err(ManagedRun(issue))
      Ok(original) => original
    }
    guard physical_equal(original, ledger) &&
      run.reads.get(occurrence) is Some(Some(selected)) &&
      physical_equal(selected, value) else {
      return Err(ForeignOriginal)
    }
    return Ok(ledger)
  }
  guard value.child is Some(child) else { return Err(Retired) }
  match @resources.check_imported_original_child_ledger(child, ledger) {
    Err(issue) => return Err(Import(issue))
    Ok(_) => ()
  }
  match @resources.check_original_resources_mutable(ledger) {
    Err(issue) => Err(Resource(issue))
    Ok(_) => Ok(ledger)
  }
}

///|
/// Currentness before any preparation work, without exposing the child Ledger.
pub fn check_installed_source_read_current(
  value : ClientInstalledSourceRead,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  require_installed_source_read_current(value).map(_ => ())
}

///|
/// Check the existing Run's original Ledger without projecting or replacing
/// this Source child's Ledger. Equal limits or a shared installation do not
/// permit a captured allocation to cross independent Run accounting owners.
pub fn check_installed_source_read_ledger(
  value : ClientInstalledSourceRead,
  expected : @resources.Ledger,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  let original = match require_installed_source_read_current(value) {
    Err(issue) => return Err(issue)
    Ok(original) => original
  }
  if physical_equal(original, expected) {
    Ok(())
  } else {
    Err(ForeignOriginal)
  }
}

///|
fn bind_installed_source_read_owner(
  value : ClientInstalledSourceRead,
  owner : ClientLocalSequenceOwner,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  match require_installed_source_read_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match value.owner {
    None => value.owner = Some(owner)
    Some(Pure(original)) =>
      match owner {
        Pure(selected) if physical_equal(original, selected) => ()
        _ => return Err(AlreadyBound)
      }
    Some(Effect(original)) =>
      match owner {
        Effect(selected) if physical_equal(original, selected) => ()
        _ => return Err(AlreadyBound)
      }
  }
  Ok(())
}

///|
pub fn bind_installed_source_read_program(
  value : ClientInstalledSourceRead,
  prepared : @publication_host.PreparedClientProgram,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  bind_installed_source_read_owner(value, Pure(prepared))
}

///|
pub fn bind_installed_source_read_effect_program(
  value : ClientInstalledSourceRead,
  prepared : @publication_host.PreparedClientEffectComputation,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  bind_installed_source_read_owner(value, Effect(prepared))
}

///|
/// The actual acquisition is created inside the earlier admitted preparation.
/// Keep all original references, rather than re-deriving a selector from CIDs.
pub fn attach_installed_source_read_acquisition(
  value : ClientInstalledSourceRead,
  declaration : @row_source_host.RowDeclaration,
  requirement : @planning.QueryRequirement,
  acquisition : @row_source_host.RowAcquisition,
  stage : Int,
  source_index : Int,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  match require_installed_source_read_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.owner is Some(owner) else { return Err(Unbound) }
  if value.managed_run is Some((run, occurrence)) {
    match installed_managed_run_direct_occurrence(run, occurrence) {
      Some((selected_stage, selected_input, task)) =>
        if stage != selected_stage ||
          source_index != selected_input ||
          task != occurrence {
          return Err(ForeignOriginal)
        }
      None => {
        let selected = match run.preparation {
          Some(PlannedEffectManaged(_, plan)) =>
            plan.direct_occurrences is Some(_)
          _ =>
            match run.captured_preparation {
              Some(plan) => plan.direct_occurrences is Some(_)
              None => false
            }
        }
        if selected || stage != occurrence || source_index != 0 {
          return Err(ForeignOriginal)
        }
      }
    }
  }
  if value.managed_run is Some((run, occurrence)) &&
    run.captured_preparation is Some(plan) {
    guard plan.captures.get(occurrence) is Some(original) &&
      original.acquisition is Some(expected) &&
      physical_equal(expected, acquisition) &&
      physical_equal(original.requirement, requirement) else {
      return Err(ForeignOriginal)
    }
  }
  let matches = match owner {
    Pure(prepared) =>
      @publication_host.client_query_requirement_matches_program(
        prepared, stage, source_index, requirement,
      )
    Effect(prepared) =>
      @publication_host.client_query_requirement_matches_effect_program(
        prepared, stage, source_index, requirement,
      )
  }
  if !matches {
    return Err(ForeignOriginal)
  }
  match
    @row_source_host.check_row_acquisition_original(
      acquisition, declaration, requirement,
    ) {
    Err(issue) => return Err(Acquisition(issue))
    Ok(_) => ()
  }
  if value.acquisition is Some(original) {
    if !physical_equal(original, acquisition) ||
      !(value.declaration is Some(selected) &&
      physical_equal(selected, declaration)) ||
      !(value.requirement is Some(selected) &&
      physical_equal(selected, requirement)) {
      return Err(AlreadyBound)
    }
    return Ok(())
  }
  value.declaration = Some(declaration)
  value.requirement = Some(requirement)
  value.acquisition = Some(acquisition)
  Ok(())
}

///|
/// Source-only entry. There is intentionally no bare-Ledger getter or Compute,
/// Model, Result, Effect or Content-publication constructor on this consumer.
pub fn start_installed_source_read_rows(
  value : ClientInstalledSourceRead,
  acquisition : @row_source_host.RowAcquisition,
  nonce : String,
  original_stop : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> Result[@row_source_host.RowRun, ClientInstalledSourceReadIssue] {
  let ledger = match claim_installed_source_read_start(value, acquisition) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  retain_installed_source_read_run(
    value,
    @row_source_host.start_accounted_row_acquisition(
      acquisition, nonce, original_stop, ledger, transfer_bytes, execution_bytes,
    ),
  )
}

///|
fn claim_installed_source_read_start(
  value : ClientInstalledSourceRead,
  acquisition : @row_source_host.RowAcquisition,
) -> Result[@resources.Ledger, ClientInstalledSourceReadIssue] {
  let ledger = match require_installed_source_read_current(value) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  guard value.acquisition is Some(original) &&
    physical_equal(original, acquisition) else {
    return Err(ForeignOriginal)
  }
  if value.started {
    return Err(AlreadyStarted)
  }
  value.started = true
  Ok(ledger)
}

///|
fn retain_installed_source_read_run(
  value : ClientInstalledSourceRead,
  result : Result[@row_source_host.RowRun, @row_source_host.RowHostIssue],
) -> Result[@row_source_host.RowRun, ClientInstalledSourceReadIssue] {
  match result {
    Err(issue) => Err(Acquisition(issue))
    Ok(run) => {
      value.run = Some(run)
      Ok(run)
    }
  }
}

///|
/// The existing provider capacity semantics, on the same original child only.
pub fn start_installed_source_read_provider_rows(
  value : ClientInstalledSourceRead,
  acquisition : @row_source_host.RowAcquisition,
  capacity : @execution.ExecutionCapacity?,
  nonce : String,
  original_stop : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> Result[@row_source_host.RowRun, ClientInstalledSourceReadIssue] {
  let ledger = match claim_installed_source_read_start(value, acquisition) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  retain_installed_source_read_run(
    value,
    @row_source_host.start_accounted_provider_row_acquisition(
      acquisition, capacity, nonce, original_stop, ledger, transfer_bytes, execution_bytes,
    ),
  )
}

///|
/// Listing reports keep their existing supplementary reservation semantics.
pub fn start_installed_source_read_listing_rows(
  value : ClientInstalledSourceRead,
  acquisition : @row_source_host.RowAcquisition,
  capacity : @execution.ExecutionCapacity?,
  nonce : String,
  original_stop : (@row_source_host.RowAttempt) -> Bool,
  transfer_bytes : Int64,
  execution_bytes : Int64,
) -> Result[@row_source_host.RowRun, ClientInstalledSourceReadIssue] {
  let ledger = match claim_installed_source_read_start(value, acquisition) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  retain_installed_source_read_run(
    value,
    @row_source_host.start_accounted_listing_row_acquisition(
      acquisition, capacity, nonce, original_stop, ledger, transfer_bytes, execution_bytes,
    ),
  )
}

///|
/// Cut only this consumer's managed references after the original RowRun says
/// its own capture/close duty is complete. The physical issuer still retains
/// the child for reporting and its distinct physical ACK; do not stop it here.
pub fn retire_installed_source_read(
  value : ClientInstalledSourceRead,
) -> Result[Unit, ClientInstalledSourceReadIssue] {
  match require_installed_source_read_original(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if value.ledger is None {
    return Ok(())
  }
  if value.run is Some(run) {
    match @row_source_host.close_accounted_row_run(run) {
      Err(issue) => return Err(Acquisition(issue))
      Ok(_) => ()
    }
    match @row_source_host.cleanup_row_capture(run) {
      Err(issue) => return Err(Acquisition(issue))
      Ok(false) => return Err(CleanupPending)
      Ok(true) => ()
    }
  }
  value.run = None
  value.acquisition = None
  value.whole_input = None
  value.requirement = None
  value.declaration = None
  value.owner = None
  value.ledger = None
  value.child = None
  value.managed_run = None
  Ok(())
}
