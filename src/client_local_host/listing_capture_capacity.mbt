///|
// Plan the same selected Source envelope before acquisition. The complete
// supplementary declaration stays with its original checked requirement, so
// existing Compute/Content ledger preparation sees it before Source start.
// This DATA composition neither reserves nor transfers any resource debt.
pub fn installed_listing_row_capture_capacity(
  selected : @row_source_host.RowAcquisition,
  declaration : @execution.ExecutionCapacity?,
) -> ClientInstalledCaptureCapacity? {
  guard @row_source_host.row_acquisition_is_listing(selected) &&
    installed_row_capture_capacity(selected) is Some(original) &&
    declaration is Some(report) else {
    return None
  }
  let retained = @execution.execution_capacity_retained_bytes(report)
  let executing = @execution.execution_capacity_execution_bytes(report)
  if retained <= 0L ||
    executing < retained ||
    retained > 9223372036854775807L - original.retained_bytes ||
    executing > 9223372036854775807L - original.execution_bytes {
    return None
  }
  Some({
    ..original,
    retained_bytes: original.retained_bytes + retained,
    execution_bytes: original.execution_bytes + executing,
  })
}
