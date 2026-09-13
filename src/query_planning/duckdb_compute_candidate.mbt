///|
/// Serial inventory: session/table setup, import transfer, import conversion,
/// native computation, result transfer, result conversion, retention, cleanup.
/// Compilation/selection is not native completion or a consumer-budget waiver.
pub fn duckdb_fixed_compute_candidate(
  registration : CapabilityRegistration,
  request : FixedComputeRequest,
  table : String,
  compilation : @duckdb.NativeQueryLimits,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : QueryQuantities,
  max_entries : Int,
) -> Result[PreparedCompute[@duckdb.FixedCompute], FixedComputeIssue] {
  // No exact fragment work/live accounting is implemented by this native
  // profile. Reject before compilation/comparison; never relabel a common
  // contract as Local-only or substitute DuckDB memory/time measurements.
  if request.capacity.common_fragment is Some(_) {
    return Err(CommonFragmentUnsupported)
  }
  let compiled = match
    @duckdb.prepare_fixed_compute(request.input, table, compilation) {
    Err(issue) => return Err(Compilation(issue))
    Ok(value) => value
  }
  bind_compute_candidate(
    registration, request, compiled, 8, estimates, quantities, max_entries,
  )
}
