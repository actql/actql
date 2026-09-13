///|
/// Provider preparation for one exact canonical requirement. Location is supplied
/// by trusted Host binding; it neither changes that requirement nor grants I/O.
struct DuckDBQueryPreparation {
  requirement : QueryRequirement
  broad : @duckdb.BroadScan
  native : Result[
    (@duckdb.NativeScan, @duckdb.NativeRootGuard),
    DuckDBNativeIssue,
  ]
}

///|
pub(all) enum DuckDBNativeIssue {
  Compilation(@duckdb.NativeQueryIssue)
  RootGuard(@duckdb.NativeRootGuardIssue)
}

///|
pub fn prepare_duckdb_query(
  requirement : QueryRequirement,
  database_schema : String,
  table : String,
  max_columns : Int,
  limits : @duckdb.NativeQueryLimits,
) -> Result[DuckDBQueryPreparation, @duckdb.NativeQueryIssue] {
  let owner = @query.query_sequence_owner(requirement.material.owner)
  let broad = match
    @duckdb.prepare_broad_scan(
      owner,
      0,
      database_schema,
      table,
      max_columns,
      limits.max_sql_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let native = match
    @duckdb.compile_native_filter_select(owner, database_schema, table, limits) {
    Err(issue) => Err(DuckDBNativeIssue::Compilation(issue))
    Ok(query) =>
      match
        @duckdb.prepare_native_root_guard(
          query,
          requirement.guards.max_value_bytes,
        ) {
        Err(issue) => Err(RootGuard(issue))
        Ok(witness) =>
          match
            @duckdb.prepare_native_scan(
              query,
              max_columns,
              limits.max_sql_bytes,
            ) {
            Err(issue) => Err(Compilation(issue))
            Ok(scan) => Ok((scan, witness))
          }
      }
  }
  Ok({ requirement, broad, native, })
}

///|
pub fn duckdb_query_requirement(
  value : DuckDBQueryPreparation,
) -> QueryRequirement {
  value.requirement
}

///|
pub fn duckdb_query_broad_scan(
  value : DuckDBQueryPreparation,
) -> @duckdb.BroadScan {
  value.broad
}

///|
/// Compiler/root compatibility only. A native candidate must bind this
/// preparation through the common registration and cost comparison. Native
/// acquisition guards, Host authority, read-view validation, physical limits
/// and completion evidence remain separate admission duties. A Local-only
/// fragment's limits are not inherited by this native acquisition realization;
/// explicitly selected common contracts still cannot be waived.
pub fn duckdb_query_native_preparation(
  value : DuckDBQueryPreparation,
) -> Result[(@duckdb.NativeScan, @duckdb.NativeRootGuard), DuckDBNativeIssue] {
  value.native
}

///|
/// Execute the separately selected broad realization's Local residual. Exact
/// input ownership, all input guards and existing fragment budgets are checked
/// by the shared query/engine path. No native failure triggers this operation.
pub fn execute_duckdb_broad_residual(
  value : DuckDBQueryPreparation,
  input : @execution.CapturedRows,
  limits : @execution.SequenceExecutionLimits,
  measurement : @query.QueryGuardMeasureLimits,
) -> Result[
  (@execution.CompletedSequence, (Int, Int, Int)),
  @query.QueryGuardIssue,
] {
  let sequence = value.requirement.material.owner
  let receipt = match @query.bind_query_receipt(sequence, input) {
    Ok(receipt) => receipt
    Err(issue) => return Err(Execution(issue))
  }
  @query.execute_query_receipt_guarded(
    sequence,
    receipt,
    limits,
    max_output_rows=value.requirement.guards.max_rows,
    max_value_bytes=value.requirement.guards.max_value_bytes,
    measurement,
  )
}
