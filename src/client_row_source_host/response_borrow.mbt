///|
/// Verify the original checked preparation before an installed provider's
/// pure preparer may supply it to the ordinary Host. Equal body/CID values
/// are not a substitute for the original requirement and declared view.
pub fn check_row_acquisition_original(
  value : RowAcquisition,
  declaration : RowDeclaration,
  requirement : @planning.QueryRequirement,
) -> Result[Unit, RowHostIssue] {
  if !physical_equal(value.configuration.requirement, requirement) {
    return Err(ForeignDeclaration)
  }
  let source_ref = @planning.query_requirement_source(requirement).0
  guard row_declaration_view(declaration, source_ref) is Some(view) &&
    physical_equal(value.preparation.view, view) else {
    return Err(ForeignDeclaration)
  }
  Ok(())
}

///|
/// One non-reissuable response-reader borrow of the existing accounted run.
/// This is not a Run, reservation, credential grant or cleanup acknowledgement.
pub struct RowRunResponseBorrow {
  priv run : RowRun
  priv selection : RowResponseSelection
  priv mut cleanup_state : RowResponseCleanupState
}

///|
priv enum RowResponseCleanupState {
  Unbound
  Bound
  GrowingWorkspace
  RetiringWorkspace
  WorkspaceReturned
}

///|
pub enum RowResponseSelection {
  QueryResponse(RowAcquisition)
  InputResponse(RowInputAcquisition)
}

///|
pub fn borrow_row_run_responses(
  run : RowRun,
  acquisition : RowAcquisition,
) -> Result[RowRunResponseBorrow, RowHostIssue] {
  guard !run.closed &&
    !run.response_borrowed &&
    run.physical is Some(_) &&
    run.page_charge is None &&
    run.attempt.state is Reading(_) &&
    run.configuration is DirectConfiguration(configuration) else {
    return Err(InvalidState)
  }
  if !row_response_configuration_matches(
      configuration,
      acquisition.configuration,
    ) {
    return Err(ForeignDeclaration)
  }
  run.response_borrowed = true
  Ok({ run, selection: QueryResponse(acquisition), cleanup_state: Unbound, })
}

///|
pub fn borrow_row_input_run_responses(
  run : RowRun,
  acquisition : RowInputAcquisition,
) -> Result[RowRunResponseBorrow, RowHostIssue] {
  guard !run.closed &&
    !run.response_borrowed &&
    run.physical is Some(_) &&
    run.page_charge is None &&
    run.attempt.state is Reading(_) &&
    run.configuration is InputConfiguration(original) &&
    physical_equal(original, acquisition) else {
    return Err(InvalidState)
  }
  run.response_borrowed = true
  Ok({ run, selection: InputResponse(acquisition), cleanup_state: Unbound, })
}

///|
pub fn check_row_run_response_borrow_current(
  value : RowRunResponseBorrow,
) -> Result[Unit, RowHostIssue] {
  if value.cleanup_state is GrowingWorkspace ||
    value.cleanup_state is RetiringWorkspace {
    return Err(InvalidState)
  }
  let run = value.run
  let selected = match (run.configuration, value.selection) {
    (DirectConfiguration(original), QueryResponse(acquisition)) =>
      row_response_configuration_matches(original, acquisition.configuration)
    (InputConfiguration(original), InputResponse(acquisition)) =>
      physical_equal(original, acquisition)
    _ => false
  }
  guard !run.closed &&
    run.response_borrowed &&
    run.physical is Some(_) &&
    run.attempt.state is Reading(_) &&
    selected else {
    return Err(InvalidState)
  }
  Ok(())
}

///|
/// Borrow the SAME stored original selection after its one physical cleanup
/// observer is bound. This consumes nothing and creates no acquisition.
pub fn row_run_response_selection(
  value : RowRunResponseBorrow,
) -> Result[RowResponseSelection, RowHostIssue] {
  match check_row_run_response_borrow_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.cleanup_state is Bound else { return Err(InvalidState) }
  Ok(value.selection)
}

///|
/// Install this reader's original physical-stop observation before its I/O.
/// Logical abort/close keeps the same observer for cleanup; it does not require
/// a Reading state after the owner has already closed admission.
pub fn bind_row_run_response_borrow_cleanup(
  value : RowRunResponseBorrow,
  cleanup : () -> Bool,
) -> Result[Unit, RowHostIssue] {
  match check_row_run_response_borrow_current(value) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  guard value.cleanup_state is Unbound &&
    value.run.page_charge is None &&
    value.run.physical is Some(physical) &&
    physical.cleanup_confirmed is None else {
    return Err(InvalidState)
  }
  value.cleanup_state = Bound
  physical.cleanup_confirmed = Some(cleanup)
  Ok(())
}

///|
/// The actual charged response bounds its next native constructor. Grow the
/// SAME original reservation before decoding, retaining all previous native
/// outputs and failed children. Missing capacity or a copied borrow cannot
/// start another attempt or bypass the original reader's cleanup observer.
pub fn grow_row_run_response_capacity(
  value : RowRunResponseBorrow,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, RowHostIssue] {
  grow_row_run_response_capacity_at_phase(value, capacity, ChargedPage)
}

///|
/// Reserve the SAME original reader's constructor backing before an announced
/// IPC body exists. An announcement is not a received page, transfer charge,
/// row, evidence or physical cleanup. Only the already-started, cleanup-bound
/// original provider borrow may enter; a live page ticket keeps its separate
/// charged-response entrance above.
pub fn grow_row_run_response_construction_capacity(
  value : RowRunResponseBorrow,
  capacity : @execution.ExecutionCapacity,
) -> Result[Unit, RowHostIssue] {
  grow_row_run_response_capacity_at_phase(value, capacity, BeforePage)
}

///|
priv enum RowResponseCapacityPhase {
  BeforePage
  ChargedPage
}

///|
fn grow_row_run_response_capacity_at_phase(
  value : RowRunResponseBorrow,
  capacity : @execution.ExecutionCapacity,
  phase : RowResponseCapacityPhase,
) -> Result[Unit, RowHostIssue] {
  match check_row_run_response_borrow_current(value) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard value.cleanup_state is Bound &&
    value.run.physical is Some(physical) &&
    physical.provider_capacity is Some(previous) else {
    return Err(InvalidState)
  }
  // Borrow the original Option; do not allocate another ticket/holder or
  // promote an untrusted announced length to received-byte evidence.
  let expected_charge = value.run.page_charge
  match (phase, expected_charge) {
    (BeforePage, None) => ()
    (ChargedPage, Some(charge)) if !charge.consumed => ()
    _ => return Err(InvalidState)
  }
  if @execution.execution_capacity_retained_bytes(capacity) <
    @execution.execution_capacity_retained_bytes(previous) ||
    @execution.execution_capacity_execution_bytes(capacity) <
    @execution.execution_capacity_execution_bytes(previous) {
    return Err(Physical(InvalidCharge))
  }
  // The reader reuses its SAME immutable peak quote for a smaller response.
  // With a live charge, keep the existing cheap original-state/ticket path.
  // An announcement has no received ticket: re-enter the original Resource
  // current fence even when the immutable capacity itself is unchanged.
  if phase is ChargedPage && physical_equal(capacity, previous) {
    return Ok(())
  }
  let (retained, execution) = match value.selection {
    QueryResponse(acquisition) =>
      match
        (if row_acquisition_is_listing(acquisition) {
          row_listing_capacity_sum(
            row_acquisition_retained_capacity(acquisition),
            row_acquisition_execution_capacity(acquisition),
            physical.execution_scratch,
            Some(capacity),
          )
        } else {
          row_provider_capacity_sum(
            row_acquisition_retained_capacity(acquisition),
            row_acquisition_execution_capacity(acquisition),
            physical.execution_scratch,
            Some(capacity),
          )
        }) {
        Err(issue) => return Err(issue)
        Ok(value) => value
      }
    InputResponse(acquisition) => {
      guard row_input_acquisition_capacity(acquisition, Some(capacity))
        is Some(combined) else {
        return Err(Physical(InvalidLimits))
      }
      let retained = @execution.execution_capacity_retained_bytes(combined)
      let execution = @execution.execution_capacity_execution_bytes(combined)
      if physical.execution_scratch > 9223372036854775807L - execution {
        return Err(Physical(InvalidLimits))
      }
      (retained, execution + physical.execution_scratch)
    }
  }
  // Resource current may synchronously close/reenter this RowRun. Fence the
  // original borrow before that callback and retain any successful new debit
  // even when its post-callback Row state is no longer usable.
  value.cleanup_state = GrowingWorkspace
  let result = @resources.grow_execution_reservation_capacity(
    physical.ledger,
    physical.reservation,
    retained,
    execution,
  )
  value.cleanup_state = Bound
  match result {
    Err(issue) => return Err(Physical(issue))
    Ok(_) => physical.provider_capacity = Some(capacity)
  }
  match (expected_charge, value.run.page_charge) {
    (None, None) => ()
    (Some(original), Some(current)) if physical_equal(original, current) &&
      !original.consumed => ()
    _ => return Err(InvalidState)
  }
  check_row_run_response_borrow_current(value)
}

///|
// This direct provider capture keeps its Source, evidence and original cleanup
// observer. Whole-input, keyed and listing lifetimes do not use this cut.
fn row_response_workspace_capture_current(value : RowRunResponseBorrow) -> Bool {
  let run = value.run
  !run.closed &&
  run.response_borrowed &&
  run.attempt.state is Captured(_) &&
  value.selection is QueryResponse(acquisition) &&
  run.configuration is DirectConfiguration(configuration) &&
  row_response_configuration_matches(configuration, acquisition.configuration) &&
  !row_acquisition_is_listing(acquisition)
}

///|
/// Return only the selected provider's transient execution workspace, after
/// the SAME bound reader confirms its actual retirement. Retain its declared
/// live frame, Source backing, original observer and all other reservation
/// obligations for final Row cleanup. A logical stop is insufficient.
pub fn retire_row_run_response_workspace(
  value : RowRunResponseBorrow,
) -> Result[Unit, RowHostIssue] {
  guard row_response_workspace_capture_current(value) else {
    return Err(InvalidState)
  }
  if value.cleanup_state is WorkspaceReturned {
    return Ok(())
  }
  guard value.cleanup_state is Bound &&
    value.selection is QueryResponse(acquisition) &&
    value.run.physical is Some(physical) &&
    physical.provider_capacity is Some(provider) &&
    physical.cleanup_confirmed is Some(confirm) else {
    return Err(InvalidState)
  }
  // Compute the absolute remainder from immutable original declarations, not
  // from a previously reduced amount. Keep all acquisition/evidence workspace
  // and the complete provider R; only the retired provider E-R is returned.
  let provider_retained = @execution.execution_capacity_retained_bytes(provider)
  let base = row_acquisition_execution_capacity(acquisition)
  if provider_retained > 9223372036854775807L - base ||
    physical.execution_scratch > 9223372036854775807L - base - provider_retained {
    return Err(Physical(InvalidLimits))
  }
  let remaining = base + provider_retained + physical.execution_scratch
  // Synchronous external observers may reenter. A throwing observer leaves
  // this cut fenced, while the unchanged final Row cleanup remains usable.
  value.cleanup_state = RetiringWorkspace
  let retired = confirm()
  if !row_response_workspace_capture_current(value) || !retired {
    value.cleanup_state = Bound
    return Err(Evidence(UnverifiedTransport))
  }
  match
    @resources.reduce_execution_reservation(
      physical.ledger,
      physical.reservation,
      remaining,
    ) {
    Err(issue) => {
      value.cleanup_state = Bound
      Err(Physical(issue))
    }
    Ok(_) => {
      // The original resource current callback may have closed the Source.
      // Returned retired workspace is monotonic: never restore an old amount
      // or clear the original cleanup observer after that callback.
      value.cleanup_state = WorkspaceReturned
      if row_response_workspace_capture_current(value) {
        Ok(())
      } else {
        Err(InvalidState)
      }
    }
  }
}

///|
// Only the actual reserved listing constructor retains this original. A
// foreign/equal configuration, report wire or cursor cannot substitute it.
fn row_response_configuration_matches(
  actual : RowHostConfiguration,
  original : RowHostConfiguration,
) -> Bool {
  physical_equal(actual, original) ||
  (
    actual.listing_rows is Some(ReportListingRows(_, reports)) &&
    reports.original_configuration is Some(retained) &&
    physical_equal(retained, original)
  )
}
