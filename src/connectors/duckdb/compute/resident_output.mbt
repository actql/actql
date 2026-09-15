///|
/// Connector-private physical materialization plan. This is neither successful
/// execution evidence nor permission to publish a retained copy.
struct DuckDBResidentOutput {
  table_name : String
  query : @duckdb.ResidentQuery
  limits : DuckDBComputeLimits
  max_sql_bytes : Int
}

///|
pub(all) enum DuckDBResidentOutputIssue {
  Read(@execution.ProducerReadIssue)
  Preparation(@duckdb.NativeQueryIssue)
}

///|
pub fn prepare_duckdb_resident_output(
  query : @duckdb.FixedQuery,
  ordinal : Int,
  limits : DuckDBComputeLimits,
  max_sql_bytes : Int,
) -> Result[DuckDBResidentOutput, @duckdb.NativeQueryIssue] {
  let table_name = "resident_" + ordinal.to_string()
  @duckdb.prepare_resident_query(query, table_name, max_sql_bytes).map(query => {
    table_name,
    query,
    limits,
    max_sql_bytes,
  })
}

///|
/// Transport-facing access stays within the concrete connector package group.
pub fn duckdb_resident_output_query(
  output : DuckDBResidentOutput,
) -> @duckdb.ResidentQuery {
  output.query
}

///|
pub fn duckdb_resident_output_cleanup(
  output : DuckDBResidentOutput,
  imported : @duckdb.ResidentImport,
) -> Result[String, @duckdb.NativeQueryIssue] {
  @duckdb.resident_import_drop_sql(imported, output.max_sql_bytes)
}

///|
/// Common completion validates exact task/input ownership before invoking this
/// operation. It shares the completed storage rather than copying or admitting
/// the rows again; live resident ownership is installed by the common driver.
pub fn bind_duckdb_resident_output(
  plan : DuckDBResidentOutput,
  output : @execution.CompletedOutput,
) -> Result[@duckdb.ResidentImport, DuckDBResidentOutputIssue] {
  let storage = match
    @execution.prepare_producer_storage(
      output,
      plan.limits.metadata_work,
      plan.limits.completion_name_bytes,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Read(issue))
  }
  @duckdb.prepare_resident_import(
    storage,
    plan.table_name,
    plan.limits.completion_entries,
    plan.max_sql_bytes,
  ).map_err(issue => Preparation(issue))
}
