///|
// Plan the same selected Source envelope before acquisition. The complete
// supplementary declaration stays with its original checked requirement, so
// existing Compute/Content ledger preparation sees it before Source start.
// This DATA composition neither reserves nor transfers any resource debt.
pub fn installed_listing_row_capture_capacity(
  selected : @row_source_host.RowAcquisition,
  declaration : @execution.ExecutionCapacity?,
) -> ClientInstalledCaptureCapacity? {
  guard declaration is Some(report) &&
    @row_source_host.row_acquisition_listing_capacity(selected, declaration)
    is Some(complete) else {
    return None
  }
  Some({
    requirement: @row_source_host.row_acquisition_requirement(selected),
    original_input: true,
    acquisition: Some(selected),
    // Same original provider-pair layout as ordinary Query captures. Row's
    // own composition includes its actual report/original binding once.
    provider: Some((selected, report)),
    retained_bytes: @execution.execution_capacity_retained_bytes(complete),
    execution_bytes: @execution.execution_capacity_execution_bytes(complete),
  })
}
