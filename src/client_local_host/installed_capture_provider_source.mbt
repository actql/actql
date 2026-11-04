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
  if owner.preparation is Some(PreparationContentManaged(_, _)) {
    return begin_installed_content_original_source_read(
      owner, prepared, request, declaration, occurrence,
    )
  }
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

///|
/// Borrow the SAME pending DuckDB capture retained by the checked Plan.
/// No Row read token, new query, capacity quote or read permission is issued.
pub fn installed_managed_duckdb_capture(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientProgram,
  request : @publication_host.ClientRequestIdentity,
  occurrence : Int,
) -> Result[
  (@planning.QueryRequirement, ClientInstalledCaptureCapacity),
  ClientInstalledManagedRunIssue,
] {
  match require_installed_managed_run(owner) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  match check_installed_managed_run_binding(owner, prepared, request) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  guard owner.preparation is Some(PureManaged(_, original)) &&
    physical_equal(original, prepared) &&
    physical_equal(owner.request, request) &&
    owner.captured_preparation is Some(plan) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    plan.captures.get(occurrence) is Some(capacity) &&
    !capacity.original_input &&
    capacity.acquisition is None &&
    capacity.provider is None else {
    return Err(ForeignOriginal)
  }
  Ok((capacity.requirement, capacity))
}

///|
/// The selected Content Plan already owns this original Direct acquisition
/// and capacity. Keep the existing Source read slot/current/retirement owner;
/// no new query, source declaration or quote is produced here.
fn begin_installed_content_original_source_read(
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
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.preparation is Some(PreparationContentManaged(_, actual)) &&
    physical_equal(actual, prepared) &&
    physical_equal(owner.request, request) &&
    owner.content is KeyedContent(selected, _) &&
    physical_equal(selected.prepared, prepared) &&
    occurrence == selected.direct_stage &&
    selected.direct_input == 0 &&
    selected.direct.original_input &&
    selected.direct.provider is None &&
    selected.direct.acquisition is Some(acquisition) else {
    return Err(ForeignOriginal)
  }
  let capacity = selected.direct
  let requirement = capacity.requirement
  match
    @row_source_host.check_row_acquisition_original(
      acquisition, declaration, requirement,
    ) {
    Err(_) => return Err(ForeignOriginal)
    Ok(_) => ()
  }
  let read = match begin_installed_managed_run_source_read(owner, occurrence) {
    Err(issue) => return Err(issue)
    Ok(value) => value
  }
  // Current may synchronously retire or replace the selected Run payload.
  // Preserve the original read on refusal, but publish no stale tuple.
  guard owner.preparation is Some(PreparationContentManaged(_, actual)) &&
    physical_equal(actual, prepared) &&
    physical_equal(owner.request, request) &&
    owner.content is KeyedContent(original, _) &&
    physical_equal(original, selected) &&
    owner.reads.get(occurrence) is Some(Some(original_read)) &&
    physical_equal(original_read, read) else {
    return Err(ForeignOriginal)
  }
  read.requirement = Some(requirement)
  read.acquisition = Some(acquisition)
  read.declaration = Some(declaration)
  Ok((read, requirement, acquisition, capacity))
}
