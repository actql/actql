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
  // The native compiler is currently unary. Multi-input requests must never
  // enter comparison as apparently executable native candidates.
  if request.inputs.length() != 1 {
    return Err(UnsupportedInputShape)
  }
  let compiled = match
    @duckdb.prepare_fixed_compute(request.inputs[0], table, compilation) {
    Err(issue) => return Err(Compilation(issue))
    Ok(value) => value
  }
  duckdb_bound_compute_candidate(
    registration, request, compiled, estimates, quantities, max_entries,
  )
}

///|
/// Common registration/selection for an exactly bound native realization.
/// The eight work categories include totals for every input import; multiple
/// ports do not imply a shared transfer or a shared retention credit.
pub fn duckdb_bound_compute_candidate(
  registration : CapabilityRegistration,
  request : FixedComputeRequest,
  compiled : @duckdb.FixedCompute,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : QueryQuantities,
  max_entries : Int,
) -> Result[PreparedCompute[@duckdb.FixedCompute], FixedComputeIssue] {
  if request.capacity.common_fragment is Some(_) {
    return Err(CommonFragmentUnsupported)
  }
  if !physical_equal(
      @duckdb.fixed_query_owner(@duckdb.fixed_compute_query(compiled)),
      request.owner,
    ) ||
    !@duckdb.fixed_compute_inputs_match(compiled, request.inputs) {
    return Err(ForeignPreparation)
  }
  bind_compute_candidate(
    registration, request, compiled, 8, estimates, quantities, max_entries,
  )
}
