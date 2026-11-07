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
    capacity.acquisition is Some(original) &&
    physical_equal(original, acquisition) &&
    physical_equal(capacity.requirement, requirement) else {
    return Err(ForeignOriginal)
  }
  // Base installed row reads (including the original Mock file reader) use
  // the Plan's complete acquisition capture. A provider-backed reader must
  // additionally retain its same selected provider capacity; neither branch
  // admits caller numbers or substitutes another equal acquisition.
  if capacity.provider is Some((_, provider)) &&
    !installed_provider_row_capture_capacity_matches(
      capacity, acquisition, provider,
    ) {
    return Err(ForeignOriginal)
  }
  // The Run retains this same partially attached read before any later
  // current check can fail. Failure never issues a replacement read or Root.
  guard plan.direct_occurrences is Some(selected) &&
    installed_direct_occurrences_match_owner(selected, Effect(prepared)) &&
    @publication_host.client_direct_acquisition_occurrence_at(
      selected, occurrence,
    )
    is Some((stage, input, task)) &&
    task == occurrence else {
    return Err(ForeignOriginal)
  }
  let read = match
    begin_installed_managed_run_source_read_at(owner, stage, input, task) {
    Err(issue) => return Err(issue)
    Ok(read) => read
  }
  match
    attach_installed_source_read_acquisition(
      read, declaration, requirement, acquisition, stage, input,
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
