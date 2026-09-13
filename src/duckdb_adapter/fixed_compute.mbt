///|
/// An owned import and native query agree on the exact receiving preparation.
/// This is a physical realization, not proof of execution or input admission.
struct FixedCompute {
  imported : FixedImport
  query : NativeQuery
}

///|
pub fn prepare_fixed_compute(
  input : @execution.ProducerRead,
  table : String,
  limits : NativeQueryLimits,
) -> Result[FixedCompute, NativeQueryIssue] {
  let imported = match
    prepare_fixed_import(input, table, limits.max_entries, limits.max_sql_bytes) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let query = match
    compile_native_filter_select(
      @execution.producer_read_receiver(input),
      "main",
      table,
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ imported, query, })
}

///|
pub fn fixed_compute_import(value : FixedCompute) -> FixedImport {
  value.imported
}

///|
pub fn fixed_compute_query(value : FixedCompute) -> NativeQuery {
  value.query
}
