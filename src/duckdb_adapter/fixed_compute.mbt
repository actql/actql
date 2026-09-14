///|
/// An owned import and native query agree on the exact receiving preparation.
/// This is a physical realization, not proof of execution or input admission.
struct FixedCompute {
  imported : FixedImport
  query : NativeQuery
}

///|
/// Static eligibility only: compile the same import schema and native expression
/// without inventing a future ProducerRead. Runtime binding remains mandatory.
pub fn check_fixed_compute_static(
  owner : @lower.BoundPrepared,
  table : String,
  limits : NativeQueryLimits,
) -> Result[Unit, NativeQueryIssue] {
  let query = match compile_native_filter_select(owner, "main", table, limits) {
    Ok(query) => query
    Err(issue) => return Err(issue)
  }
  let pipeline = @lower.pipeline(@lower.bound_preparation(query.owner))
  guard @pipeline.schema_at(pipeline, Input(0)) is Some(schema) else {
    return Err(UnsupportedShape)
  }
  compile_fixed_import_schema(
    schema,
    table,
    limits.max_entries,
    limits.max_sql_bytes,
  ).map(_ => ())
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
