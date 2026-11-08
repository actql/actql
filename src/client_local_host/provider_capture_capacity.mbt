///|
/// Seal the same ordinary acquisition and trusted declaration into the existing
/// installed Ledger-planning projection. No JS arithmetic or new Ledger owner.
pub fn installed_provider_row_capture_capacity(
  selected : @row_source_host.RowAcquisition,
  declaration : @execution.ExecutionCapacity?,
) -> ClientInstalledCaptureCapacity? {
  guard declaration is Some(provider) &&
    @row_source_host.row_acquisition_provider_capacity(selected, declaration)
    is Some(complete) else {
    return None
  }
  Some({
    requirement: @row_source_host.row_acquisition_requirement(selected),
    retained_bytes: @execution.execution_capacity_retained_bytes(complete),
    execution_bytes: @execution.execution_capacity_execution_bytes(complete),
    original_input: true,
    acquisition: Some(selected),
    provider: Some((selected, provider)),
  })
}

///|
/// Check original correspondence before the trusted caller starts that same
/// reader. Equal counts, requirement CID or a copied declaration do not match.
/// This predicate issues no reservation, permission or cleanup acknowledgement.
pub fn installed_provider_row_capture_capacity_matches(
  capacity : ClientInstalledCaptureCapacity,
  selected : @row_source_host.RowAcquisition,
  declaration : @execution.ExecutionCapacity,
) -> Bool {
  capacity.provider is Some((original, provider)) &&
  physical_equal(original, selected) &&
  physical_equal(provider, declaration) &&
  physical_equal(
    capacity.requirement,
    @row_source_host.row_acquisition_requirement(selected),
  )
}

///|
/// Borrowed Query read/Plan/provider correspondence only. This is not a
/// current observation, start claim, capacity supplier or cleanup ACK. Native
/// checks it before publishing a holder that will retire this exact child.
pub fn installed_source_read_provider_matches(
  read : ClientInstalledSourceRead,
  acquisition : @row_source_host.RowAcquisition,
  provider : @execution.ExecutionCapacity,
) -> Bool {
  guard read.original is Some(original) &&
    physical_equal(original, read) &&
    read.ledger is Some(ledger) &&
    read.whole_input is None &&
    read.acquisition is Some(selected) &&
    physical_equal(selected, acquisition) &&
    read.managed_run is Some((parent, occurrence)) &&
    parent.original is Some(original_parent) &&
    physical_equal(parent, original_parent) &&
    parent.ledger is Some(parent_ledger) &&
    physical_equal(ledger, parent_ledger) &&
    parent.reads.get(occurrence) is Some(Some(original_read)) &&
    physical_equal(original_read, read) else {
    return false
  }
  let capacity = match parent.preparation {
    Some(PlannedEffectManaged(_, plan)) =>
      installed_effect_source_capture_index(plan, occurrence).bind(index => {
        plan.captures.get(index)
      })
    Some(PureManaged(_, _)) =>
      parent.captured_preparation.bind(plan => plan.captures.get(occurrence))
    _ => None
  }
  match capacity {
    Some(original) =>
      installed_provider_row_capture_capacity_matches(
        original, acquisition, provider,
      )
    None => false
  }
}
