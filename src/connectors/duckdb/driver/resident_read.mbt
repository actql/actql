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
    fn(table, input) {
      let imported = @strategy.resident_table_import(table)
      @compute.prepare_duckdb_resident_read(
        imported, input, view_name, max_entries, max_sql_bytes,
      )
      .map(_ => ())
      .map_err(issue => preparation_failure(issue))
    },
    input_index~,
  )
}

///|
struct DuckDBResidentInputs {
  leases : @strategy.ResidentInputs
  plans : Array[@compute.DuckDBResidentRead]
}

///|
pub fn resident_inputs_read_plans(
  inputs : DuckDBResidentInputs,
) -> Array[@compute.DuckDBResidentRead] {
  inputs.plans.copy()
}

///|
pub fn cancel_resident_inputs(
  inputs : DuckDBResidentInputs,
) -> Result[Unit, @resources.LedgerIssue] {
  @strategy.cancel_resident_inputs(inputs.leases)
}

///|
pub fn prepare_resident_inputs(
  run : @strategy.CapturedDAG,
  environment : @strategy.ResidentEnvironment,
  task : Int,
  tables : Array[@strategy.ResidentTable],
  choice : @connector.FixedComputeChoice,
  prepared : @connector.PreparedCompute[@duckdb.FixedCompute],
  max_entries : Int,
  max_name_bytes : Int,
  max_sql_bytes : Int,
) -> Result[DuckDBResidentInputs, @strategy.RunIssue] {
  guard @connector.fixed_compute_choice_payload(choice, prepared)
    is Some(compute) else {
    return Err(ForeignCandidate)
  }
  let plans = []
  @strategy.prepare_resident_inputs(
    run,
    environment,
    task,
    tables,
    @connector.prepared_compute_candidate(prepared),
    max_entries,
    max_name_bytes,
    max_sql_bytes,
    fn(port, table, input, remaining) {
      let imported = @strategy.resident_table_import(table)
      guard @duckdb.fixed_compute_import(compute, port) is Some(fixed) &&
        physical_equal(@duckdb.fixed_import_input(fixed), input) else {
        return Err(ForeignCandidate)
      }
      guard @duckdb.fixed_query_input_table(
          @duckdb.fixed_compute_query(compute),
          port,
        )
        is Some(name) else {
        return Err(ForeignCandidate)
      }
      let plan = match
        @compute.prepare_duckdb_resident_read(
          imported, input, name, max_entries, remaining,
        ) {
        Ok(plan) => plan
        Err(issue) => return Err(preparation_failure(issue))
      }
      guard @compute.duckdb_resident_read_matches(plan, imported, input) &&
        @compute.duckdb_resident_read_bytes(plan, remaining) is Some(bytes) else {
        return Err(ForeignCandidate)
      }
      plans.push(plan)
      Ok(bytes)
    },
  ).map(leases => { leases, plans, })
}
