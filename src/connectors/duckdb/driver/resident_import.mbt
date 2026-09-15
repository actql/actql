///|
/// Concrete table naming and schema compilation stay in the connector. The
/// common boundary selects the exact producer storage, charges planning, and
/// allocates retention only after successful preparation against that storage.
pub fn prepare_resident_table(
  run : @strategy.CapturedDAG,
  environment : @strategy.ResidentEnvironment,
  producer : Int,
  bytes : Int64,
  max_entries : Int,
  max_name_bytes : Int,
  max_sql_bytes : Int,
) -> Result[@strategy.ResidentTable, @strategy.RunIssue] {
  @strategy.prepare_resident_storage(
    run,
    environment,
    producer,
    bytes,
    max_entries,
    max_name_bytes,
    fn(storage, ordinal) {
      @duckdb.prepare_resident_import(
        storage,
        "resident_" + ordinal.to_string(),
        max_entries,
        max_sql_bytes,
      ).map_err(issue => NativePreparation(issue))
    },
  )
}
