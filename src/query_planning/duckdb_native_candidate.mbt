///|
/// Two-receipt work scopes. Validation and query transfers are distinct, even
/// when the two row sets happen to be equal. Retention is not a receipt discount.
pub(all) enum DuckDBNativeWork {
  SessionAndCatalog
  ValidationScan
  ValidationTransfer
  ValidationAdmission
  SqlFilterSelect
  NativeTransfer
  NativeAdmission
  DemandMeasurement
  ObservationCapture
  Retention
  Cleanup
} derive(Eq, Debug)

///|
pub fn duckdb_native_work_at(index : Int) -> DuckDBNativeWork? {
  match index {
    0 => Some(SessionAndCatalog)
    1 => Some(ValidationScan)
    2 => Some(ValidationTransfer)
    3 => Some(ValidationAdmission)
    4 => Some(SqlFilterSelect)
    5 => Some(NativeTransfer)
    6 => Some(NativeAdmission)
    7 => Some(DemandMeasurement)
    8 => Some(ObservationCapture)
    9 => Some(Retention)
    10 => Some(Cleanup)
    _ => None
  }
}

///|
/// Exact compiled realization, not a discharged source-validation obligation.
/// It does not select the Local residual's fragment contract.
struct DuckDBNativePreparation {
  requirement : QueryRequirement
  scan : @duckdb.NativeScan
  root : @duckdb.NativeRootGuard
}

///|
pub(all) enum DuckDBNativeCandidateIssue {
  Unsupported(DuckDBNativeIssue)
  Planning(QueryPlanningIssue)
}

///|
pub fn duckdb_native_candidate(
  registration : CapabilityRegistration,
  prepared : DuckDBQueryPreparation,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : QueryQuantities,
  max_entries : Int,
) -> Result[
  PreparedAcquisition[DuckDBNativePreparation],
  DuckDBNativeCandidateIssue,
] {
  let (scan, root) = match prepared.native {
    Ok(value) => value
    Err(issue) => return Err(Unsupported(issue))
  }
  if !valid_quantity(quantities.transfer_bytes) ||
    !valid_quantity(quantities.retained_bytes) ||
    !valid_quantity(quantities.money_units) {
    return Err(Planning(NegativeQuantity))
  }
  let duration = match @cost.assess_serial(11, estimates, max_entries) {
    Ok(duration) => duration
    Err(issue) => return Err(Planning(Cost(issue)))
  }
  bind_acquisition_candidate(
    registration,
    prepared.requirement,
    { requirement: prepared.requirement, scan, root, },
    duration,
    quantities,
  ).map_err(issue => Planning(issue))
}

///|
pub fn duckdb_native_preparation_scan(
  value : DuckDBNativePreparation,
) -> @duckdb.NativeScan {
  value.scan
}
