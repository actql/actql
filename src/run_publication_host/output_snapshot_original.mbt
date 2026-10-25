///|
/// Read the already completed logical wire witness only under the exact live
/// Run and Result occurrence retained by this export. Equal names/CIDs or a
/// second consumer cannot relabel the producer. These are execution bounds,
/// never an allocation grant; the Local publication owner funds construction.
pub fn PublicationOutputExport::snapshot_original_extent(
  self : PublicationOutputExport,
  run : @strategy.CapturedDAG,
  occurrence : @execution.ManagedResultOccurrence,
) -> Result[(Int, Int, Int), PublicationOutputExportIssue] {
  if !self.matches_captured_run(run) {
    return Err(InvalidState)
  }
  let actual = match self.retained {
    Some(Cells(borrow)) => @strategy.captured_result_borrow_occurrence(borrow)
    Some(Any(borrow)) => @strategy.captured_any_result_borrow_occurrence(borrow)
    None => return Err(InvalidState)
  }
  if !@execution.managed_result_occurrence_same(actual, occurrence) {
    return Err(InvalidState)
  }
  guard self.receipt is Some(receipt) && self.artifact is Some(_) else {
    return Err(InvalidState)
  }
  Ok(
    @execution.logical_relation_usage(
      @execution.completed_relation_export_identity(receipt),
    ),
  )
}
