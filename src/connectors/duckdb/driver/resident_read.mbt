///|
pub fn borrow_resident_table(
  run : @strategy.CapturedDAG,
  table : @strategy.ResidentTable,
  task : Int,
  max_entries : Int,
  max_name_bytes : Int,
  max_sql_bytes : Int,
  input_index? : Int = 0,
  view_name? : String = "owned_input",
) -> Result[@strategy.ResidentRead, @strategy.RunIssue] {
  @strategy.borrow_resident_table(
    run,
    table,
    task,
    max_entries,
    max_name_bytes,
    fn(imported, input) {
      @compute.prepare_duckdb_resident_read(
        imported, input, view_name, max_entries, max_sql_bytes,
      ).map_err(issue => NativePreparation(issue))
    },
    input_index~,
  )
}

///|
pub fn prepare_resident_inputs(
  run : @strategy.CapturedDAG,
  environment : @strategy.ResidentEnvironment,
  task : Int,
  tables : Array[@strategy.ResidentTable],
  compute : @duckdb.FixedCompute,
  max_entries : Int,
  max_name_bytes : Int,
  max_sql_bytes : Int,
) -> Result[@strategy.ResidentInputs, @strategy.RunIssue] {
  @strategy.prepare_resident_inputs(
    run,
    environment,
    task,
    tables,
    compute,
    max_entries,
    max_name_bytes,
    max_sql_bytes,
    fn(port, imported, input, remaining) {
      guard @duckdb.fixed_query_input_table(
          @duckdb.fixed_compute_query(compute),
          port,
        )
        is Some(name) else {
        return Err(ForeignCandidate)
      }
      @compute.prepare_duckdb_resident_read(
        imported, input, name, max_entries, remaining,
      ).map_err(issue => NativePreparation(issue))
    },
  )
}
