///|
/// Disjoint serial scopes for broad acquisition; setup includes catalog and
/// read-transaction work. The SQL scan, receipt transport and Local residual
/// must not hide one another's costs. Missing estimates remain unknown.
pub(all) enum DuckDBBroadWork {
  SessionAndCatalog
  SourceScan
  ReceiptTransfer
  ReceiptConversion
  LocalResidual
  ObservationCapture
  Retention
  Cleanup
} derive(Eq, Debug)

///|
pub fn duckdb_broad_work_at(index : Int) -> DuckDBBroadWork? {
  match index {
    0 => Some(SessionAndCatalog)
    1 => Some(SourceScan)
    2 => Some(ReceiptTransfer)
    3 => Some(ReceiptConversion)
    4 => Some(LocalResidual)
    5 => Some(ObservationCapture)
    6 => Some(Retention)
    7 => Some(Cleanup)
    _ => None
  }
}

///|
pub fn duckdb_broad_candidate(
  registration : @connector.CapabilityRegistration,
  prepared : DuckDBQueryPreparation,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[PreparedAcquisition[DuckDBQueryPreparation], QueryPlanningIssue] {
  if !@connector.valid_quantity(quantities.transfer_bytes) ||
    !@connector.valid_quantity(quantities.retained_bytes) ||
    !@connector.valid_quantity(quantities.money_units) {
    return Err(NegativeQuantity)
  }
  match @cost.assess_serial(8, estimates, max_entries) {
    Err(issue) => Err(Cost(issue))
    Ok(duration) =>
      bind_acquisition_candidate(
        registration,
        prepared.requirement,
        prepared,
        duration,
        quantities,
      )
  }
}
