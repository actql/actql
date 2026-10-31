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
  priv mut cleanup_bound : Bool
}

///|
priv enum RowResponseSelection {
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
  if !physical_equal(configuration, acquisition.configuration) {
    return Err(ForeignDeclaration)
  }
  run.response_borrowed = true
  Ok({ run, selection: QueryResponse(acquisition), cleanup_bound: false, })
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
  Ok({ run, selection: InputResponse(acquisition), cleanup_bound: false, })
}

///|
pub fn check_row_run_response_borrow_current(
  value : RowRunResponseBorrow,
) -> Result[Unit, RowHostIssue] {
  let run = value.run
  let selected = match (run.configuration, value.selection) {
    (DirectConfiguration(original), QueryResponse(acquisition)) =>
      physical_equal(original, acquisition.configuration)
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
  guard !value.cleanup_bound &&
    value.run.page_charge is None &&
    value.run.physical is Some(physical) &&
    physical.cleanup_confirmed is None else {
    return Err(InvalidState)
  }
  value.cleanup_bound = true
  physical.cleanup_confirmed = Some(cleanup)
  Ok(())
}
