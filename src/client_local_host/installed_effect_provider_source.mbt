///|
/// The same managed Plan selects the Source's declaration, requirement,
/// acquisition and complete reader capacity before its original child starts.
/// The returned tuple is DATA on that existing owner, not another Resource
/// issuer, grant, permission or physical cleanup acknowledgement.
pub fn begin_installed_effect_managed_source_read(
  owner : ClientInstalledManagedRun,
  declaration : @row_source_host.RowDeclaration,
  occurrence : Int,
) -> Result[
  (
    ClientInstalledSourceRead,
    @planning.QueryRequirement,
    @row_source_host.RowAcquisition,
    ClientInstalledCaptureCapacity,
  ),
  ClientInstalledManagedRunIssue,
] {
  guard owner.preparation is Some(PlannedEffectManaged(_, original_plan)) else {
    return Err(Unsupported)
  }
  let prepared = original_plan.prepared
  let request = owner.request
  let plan = match
    installed_effect_managed_operation_plan(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(plan) => plan
  }
  let (selected, requirement, acquisition, capacity) = match
    prepared_installed_effect_managed_source(plan, occurrence) {
    Err(issue) => return Err(issue)
    Ok(original) => original
  }
  guard physical_equal(selected, declaration) &&
    capacity.provider is Some((original, provider)) &&
    physical_equal(original, acquisition) &&
    installed_provider_row_capture_capacity_matches(
      capacity, acquisition, provider,
    ) else {
    return Err(ForeignOriginal)
  }
  // The Run retains this same partially attached read before any later
  // current check can fail. Failure never issues a replacement read or Root.
  let read = match begin_installed_managed_run_source_read(owner, occurrence) {
    Err(issue) => return Err(issue)
    Ok(read) => read
  }
  match
    attach_installed_source_read_acquisition(
      read, declaration, requirement, acquisition, occurrence, 0,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  match installed_effect_managed_operation_plan(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(original) if physical_equal(original, plan) => ()
    Ok(_) => return Err(ForeignOriginal)
  }
  Ok((read, requirement, acquisition, capacity))
}
