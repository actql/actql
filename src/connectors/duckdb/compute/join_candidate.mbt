///|
/// Compilation is separate from the bounded input preflight so that the Host
/// charges planning work before any input scan. The SQL and physical input names
/// are private to this connector-owned preparation.
priv struct DuckDBJoinPreparation {
  request : @connector.FixedComputeRequest
  query : @duckdb.NativeInnerJoin
  compilation : @duckdb.NativeQueryLimits
}

///|
fn compute_input_tables(owner : @lower.BoundPrepared) -> Array[String] {
  let count = @lower.preparation_input_count(@lower.bound_preparation(owner))
  Array::makei(count, index => {
    if count == 1 {
      "owned_input"
    } else {
      "owned_input_" + index.to_string()
    }
  })
}

///|
fn check_duckdb_compute_static(
  owner : @lower.BoundPrepared,
  compilation : @duckdb.NativeQueryLimits,
) -> Result[Unit, @duckdb.NativeQueryIssue] {
  @duckdb.check_fixed_compute_static(
    owner,
    compute_input_tables(owner),
    compilation,
  )
}

///|
fn compile_duckdb_join_candidate(
  request : @connector.FixedComputeRequest,
  compilation : @duckdb.NativeQueryLimits,
) -> Result[DuckDBJoinPreparation, DuckDBComputeCandidateIssue] {
  if @connector.fixed_compute_request_has_supplied_input(request) {
    return Err(Request(UnsupportedInputShape))
  }
  let owner = @connector.fixed_compute_request_owner(request)
  @duckdb.compile_fixed_inner_join(
    owner,
    "main",
    compute_input_tables(owner),
    compilation,
  )
  .map(query => { request, query, compilation, })
  .map_err(issue => Compilation(issue))
}

///|
/// Called after the common Host has admitted the bounded preflight work. The
/// request and compiled owner cannot be exchanged between these two phases.
fn bind_duckdb_join_candidate(
  registration : @connector.CapabilityRegistration,
  preparation : DuckDBJoinPreparation,
  validation : @execution.FixedJoinValidationLimits,
  output_ceiling : Int,
  estimates : Array[@cost.SerialEstimateLine],
  quantities : @connector.QueryQuantities,
  max_entries : Int,
) -> Result[
  @connector.PreparedCompute[@duckdb.FixedCompute],
  DuckDBComputeCandidateIssue,
] {
  guard duckdb_completed_fixed_inputs(preparation.request) is Some(inputs) else {
    return Err(Request(UnsupportedInputShape))
  }
  let imported = match
    @duckdb.prepare_fixed_join_inputs(
      preparation.query,
      inputs,
      validation,
      preparation.compilation.max_entries,
      preparation.compilation.max_sql_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(JoinPreparation(issue))
  }
  let compute = match
    @duckdb.prepare_fixed_join_compute(imported, output_ceiling) {
    Ok(value) => value
    Err(issue) => return Err(Compilation(issue))
  }
  duckdb_bound_compute_candidate(
    registration,
    preparation.request,
    compute,
    estimates,
    quantities,
    max_entries,
  )
}
