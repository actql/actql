///|
/// Connector-owned physical preparations for one exact resource generation.
/// Keys are checked graph producer positions, never content CIDs or table names.
struct DuckDBResidentStore {
  environment : @strategy.ResidentEnvironment
  imports : Map[Int, @duckdb.ResidentImport]
}

///|
pub fn prepare_resident_store(
  environment : @strategy.ResidentEnvironment,
) -> DuckDBResidentStore {
  { environment, imports: Map([]), }
}

///|
pub fn resident_store_environment(
  store : DuckDBResidentStore,
) -> @strategy.ResidentEnvironment {
  store.environment
}

///|
pub fn resident_store_import(
  store : DuckDBResidentStore,
  table : @strategy.ResidentTable,
) -> @duckdb.ResidentImport? {
  if !physical_equal(
      store.environment,
      @strategy.resident_table_environment(table),
    ) {
    return None
  }
  store.imports
  .get(@strategy.resident_table_producer(table))
  .filter(imported => {
    physical_equal(
      @duckdb.resident_import_storage(imported),
      @strategy.resident_table_storage(table),
    )
  })
}

///|
pub fn close_resident_store(
  run : @strategy.CapturedDAG,
  store : DuckDBResidentStore,
  confirmed : Bool,
) -> Result[Unit, @resources.LedgerIssue] {
  match @strategy.close_resident_environment(run, store.environment) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  if confirmed {
    match @strategy.settle_resident_environment(run, store.environment) {
      Err(issue) => return Err(issue)
      Ok(_) => store.imports.clear()
    }
  }
  Ok(())
}

///|
/// Transport-side handle pairs an exact common allocation with its owning store.
struct DuckDBResidentTable {
  store : DuckDBResidentStore
  table : @strategy.ResidentTable
}

///|
pub fn bind_resident_table(
  store : DuckDBResidentStore,
  table : @strategy.ResidentTable,
) -> DuckDBResidentTable? {
  resident_store_import(store, table).map(_ => { store, table, })
}

///|
pub fn resident_table_handle(
  table : DuckDBResidentTable,
) -> @strategy.ResidentTable {
  table.table
}

///|
pub fn resident_table_import(
  table : DuckDBResidentTable,
) -> @duckdb.ResidentImport? {
  resident_store_import(table.store, table.table)
}
