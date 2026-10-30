///|
/// Borrow the original Row acquisition retained by this Pure Plan. The
/// existing Run owns admission/current/cleanup; this tuple creates no query,
/// declaration, provider quote, permission or replacement resource owner.
pub fn begin_installed_managed_capture_source_read(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
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
  guard owner.preparation is Some(PureManaged(_, original)) &&
    physical_equal(original, prepared) &&
    physical_equal(owner.request, request) &&
    owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    plan.captures.get(occurrence) is Some(capacity) &&
    capacity.original_input &&
    capacity.acquisition is Some(acquisition) else {
    return Err(ForeignOriginal)
  }
  // A base Row Plan retains its actual acquisition without an extra provider
  // recipe. When a provider was selected, keep its original binding in full;
  // absence cannot replace a selected recipe or manufacture physical backing.
  if capacity.provider is Some((selected, provider)) &&
    (
      !physical_equal(selected, acquisition) ||
      !installed_provider_row_capture_capacity_matches(
        capacity, acquisition, provider,
      )
    ) {
    return Err(ForeignOriginal)
  }
  let requirement = capacity.requirement
  match
    @row_source_host.check_row_acquisition_original(
      acquisition, declaration, requirement,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  // This existing constructor crosses current once and retains the partial
  // read on the original Run before any following refusal can escape.
  let read = match begin_installed_managed_capture_read(owner, occurrence) {
    Err(issue) => return Err(issue)
    Ok(read) => read
  }
  // Current may reenter. Recheck the captured originals without another
  // callback or reconstructing the acquisition after that same boundary.
  guard owner.preparation is Some(PureManaged(_, original)) &&
    physical_equal(original, prepared) &&
    physical_equal(owner.request, request) &&
    owner.captured_preparation is Some(original_plan) &&
    physical_equal(original_plan, plan) &&
    plan.captures.get(occurrence) is Some(original_capacity) &&
    physical_equal(original_capacity, capacity) else {
    return Err(ForeignOriginal)
  }
  read.declaration = Some(declaration)
  Ok((read, requirement, acquisition, capacity))
}
