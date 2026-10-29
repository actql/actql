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
