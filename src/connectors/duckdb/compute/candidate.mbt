///|
/// DuckDB compilation diagnostics stay with the connector, not the shared request.
pub(all) enum DuckDBComputeCandidateIssue {
  Request(@connector.FixedComputeIssue)
  Compilation(@duckdb.NativeQueryIssue)
  JoinPreparation(@duckdb.FixedJoinInputIssue)
}

///|
/// Managed-profile unary native candidate. It retains the common fixed
/// capacity and cost comparison but never constructs a legacy ProducerRead or
/// logical content receipt.
pub fn[T] duckdb_managed_fixed_compute_candidate(
  registration : @connector.CapabilityRegistration,
  request : @connector.ManagedFixedComputeRequest[T],
  table : String,
  compilation : @duckdb.NativeQueryLimits,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @connector.PreparedManagedCompute[T, @duckdb.ManagedFixedQuery[T]],
  DuckDBComputeCandidateIssue,
] {
  if @connector.managed_fixed_compute_request_capacity(request).common_fragment
    is Some(_) {
    return Err(Request(CommonFragmentUnsupported))
  }
  if @connector.managed_fixed_compute_request_input_count(request) != 1 {
    return Err(Request(UnsupportedInputShape))
  }
  let compiled = match
    @duckdb.prepare_managed_fixed_request_query(request, table, compilation) {
    Err(issue) => return Err(Compilation(issue))
    Ok(value) => value
  }
  @connector.bind_managed_compute_candidate(
    registration, request, compiled, 8, estimates, quantities, max_entries,
  ).map_err(issue => Request(issue))
}

///|
/// Serial inventory: session/table setup, import transfer, import conversion,
/// native computation, result transfer, result conversion, retention, cleanup.
/// Compilation/selection is not native completion or a consumer-budget waiver.
pub fn duckdb_fixed_compute_candidate(
  registration : @connector.CapabilityRegistration,
  request : @connector.FixedComputeRequest,
  table : String,
  compilation : @duckdb.NativeQueryLimits,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @connector.PreparedCompute[@duckdb.FixedCompute],
  DuckDBComputeCandidateIssue,
] {
  // No exact fragment work/live accounting is implemented by this native
  // profile. Reject before compilation/comparison; never relabel a common
  // contract as Local-only or substitute DuckDB memory/time measurements.
  if @connector.fixed_compute_request_capacity(request).common_fragment
    is Some(_) {
    return Err(Request(CommonFragmentUnsupported))
  }
  // The native compiler is currently unary. Multi-input requests must never
  // enter comparison as apparently executable native candidates.
  if @connector.fixed_compute_request_inputs(request).length() != 1 {
    return Err(Request(UnsupportedInputShape))
  }
  let compiled = match
    @duckdb.prepare_fixed_compute(
      @connector.fixed_compute_request_inputs(request)[0],
      table,
      compilation,
    ) {
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
  registration : @connector.CapabilityRegistration,
  request : @connector.FixedComputeRequest,
  compiled : @duckdb.FixedCompute,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @connector.PreparedCompute[@duckdb.FixedCompute],
  DuckDBComputeCandidateIssue,
] {
  if @connector.fixed_compute_request_capacity(request).common_fragment
    is Some(_) {
    return Err(Request(CommonFragmentUnsupported))
  }
  if !physical_equal(
      @duckdb.fixed_query_owner(@duckdb.fixed_compute_query(compiled)),
      @connector.fixed_compute_request_owner(request),
    ) ||
    !@duckdb.fixed_compute_inputs_match(
      compiled,
      @connector.fixed_compute_request_inputs(request),
    ) {
    return Err(Request(ForeignPreparation))
  }
  @connector.bind_compute_candidate(
    registration, request, compiled, 8, estimates, quantities, max_entries,
  ).map_err(issue => Request(issue))
}
