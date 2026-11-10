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

///|
/// Immutable variant and owner correspondence only; opening a physical read
/// remains the separate current-fenced managed read entrance.
pub fn installed_effect_managed_source_input_kind(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  occurrence : Int,
) -> Result[String, ClientInstalledManagedRunIssue] {
  guard owner.original is Some(original) &&
    physical_equal(original, owner) &&
    owner.ledger is Some(_) &&
    physical_equal(owner.request, request) &&
    owner.preparation is Some(PlannedEffectManaged(_, plan)) &&
    physical_equal(plan.prepared, prepared) &&
    physical_equal(plan.request, request) &&
    plan.whole_sources.get(occurrence) is Some(selected) else {
    return Err(ForeignOriginal)
  }
  Ok(if selected is Some(_) { "whole-input" } else { "query" })
}

///|
pub fn begin_installed_effect_managed_whole_source_read(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
  declaration : @row_source_host.RowDeclaration,
  occurrence : Int,
) -> Result[
  (
    ClientInstalledSourceRead,
    @sourceviews.SourceAcquisition,
    @row_source_host.RowInputAcquisition,
    ClientInstalledWholeSourceCapacity,
  ),
  ClientInstalledManagedRunIssue,
] {
  let plan = match
    installed_effect_managed_operation_plan(owner, prepared, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard plan.whole_sources.get(occurrence) is Some(Some((selected, source))) &&
    physical_equal(selected, declaration) &&
    plan.direct_occurrences is Some(coordinates) &&
    @publication_host.client_direct_acquisition_occurrence_at(
      coordinates, occurrence,
    )
    is Some((stage, input, task)) &&
    @publication_host.client_source_acquisition_matches_effect_program(
      prepared,
      stage,
      input,
      source.original,
    ) &&
    @row_source_host.check_row_input_acquisition_original(
      source.acquisition,
      declaration,
      source.original,
    )
    is Ok(_) else {
    return Err(ForeignOriginal)
  }
  let read = match
    begin_installed_managed_run_source_read_owned(
      owner,
      occurrence,
      Some((stage, input, task)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  read.declaration = Some(declaration)
  read.whole_input = Some(source)
  let ledger = match
    require_installed_effect_operation_plan(owner, prepared, request) {
    Ok((current, ledger)) if physical_equal(current, plan) => ledger
    Ok(_) => return Err(ForeignOriginal)
    Err(issue) => return Err(issue)
  }
  guard check_installed_source_read_retained_ledger(read, ledger) is Ok(_) &&
    read.whole_input is Some(actual_source) &&
    physical_equal(actual_source, source) &&
    read.declaration is Some(actual_declaration) &&
    physical_equal(actual_declaration, declaration) else {
    return Err(ForeignOriginal)
  }
  Ok((read, source.original, source.acquisition, source))
}

///|
/// Borrow this Plan's one admitted Ledger after every selected Source has
/// attached its exact original read. No caller capacity number is a proof.
pub fn installed_effect_managed_sources_ledger(
  owner : ClientInstalledManagedRun,
  prepared : @publication_host.PreparedClientEffectComputation,
  request : @publication_host.ClientRequestIdentity,
) -> Result[@resources.Ledger, ClientInstalledManagedRunIssue] {
  let (plan, ledger) = match
    require_installed_effect_operation_plan(owner, prepared, request) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if owner.reads.length() != plan.whole_sources.length() {
    return Err(ForeignOriginal)
  }
  for occurrence, selected in plan.whole_sources {
    if owner.reads[occurrence] is Some(read) {
      guard check_installed_source_read_retained_ledger(read, ledger) is Ok(_) &&
        read.managed_run is Some((original_owner, original_slot)) &&
        physical_equal(original_owner, owner) &&
        original_slot == occurrence else {
        return Err(ForeignOriginal)
      }
    }
    match selected {
      Some((declaration, source)) => {
        guard owner.reads[occurrence] is Some(read) &&
          read.original is Some(original) &&
          physical_equal(original, read) &&
          read.ledger is Some(actual_ledger) &&
          physical_equal(actual_ledger, ledger) &&
          read.declaration is Some(actual_declaration) &&
          physical_equal(actual_declaration, declaration) &&
          read.whole_input is Some(actual_source) &&
          physical_equal(actual_source, source) &&
          read.requirement is None &&
          read.acquisition is None else {
          return Err(ForeignOriginal)
        }
      }
      None => {
        guard installed_effect_source_capture_index(plan, occurrence)
          is Some(index) &&
          plan.captures.get(index) is Some(capacity) else {
          return Err(ForeignOriginal)
        }
        if capacity.original_input {
          guard installed_effect_source_row_index(plan, occurrence) is Some(row) &&
            owner.reads[occurrence] is Some(read) &&
            read.declaration is Some(declaration) &&
            physical_equal(declaration, plan.declarations[row]) &&
            read.requirement is Some(requirement) &&
            physical_equal(requirement, capacity.requirement) &&
            read.acquisition is Some(acquisition) &&
            capacity.acquisition is Some(original) &&
            physical_equal(acquisition, original) else {
            return Err(ForeignOriginal)
          }
        } else if owner.reads[occurrence] is Some(_) {
          return Err(ForeignOriginal)
        }
      }
    }
  }
  if !installed_effect_managed_limits_fit(owner, plan, ledger) {
    return Err(InsufficientCapacity)
  }
  Ok(ledger)
}
