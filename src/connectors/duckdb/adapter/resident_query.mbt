///|
/// Native result materialization uses the very same checked query and bound
/// parameter as fresh execution. It is not completion or resident provenance.
struct ResidentQuery {
  query : FixedQuery
  create_sql : String
  read_sql : String
  drop_sql : String
}

///|
pub fn prepare_resident_query(
  query : FixedQuery,
  output_table : String,
  max_sql_bytes : Int,
) -> Result[ResidentQuery, NativeQueryIssue] {
  if max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  match
    check_resident_output_static(
      fixed_query_owner(query),
      fixed_query_target(query),
    ) {
    Err(issue) => return Err(issue)
    Ok(_) => ()
  }
  let input_tables = match query {
    FilterSelect(query) => [query.table]
    CountGroup(query) => [query.table]
    InnerJoin(query) => query.tables
  }
  for input_table in input_tables {
    if output_table == input_table {
      return Err(InvalidIdentifier)
    }
  }
  let create = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(create, "CREATE TABLE ")
    sql_identifier(create, output_table)
    sql_text(create, " AS ")
    sql_text(create, fixed_query_sql(query))
    let read = { builder: StringBuilder(), remaining: create.remaining, }
    sql_text(read, "SELECT * FROM main.")
    sql_identifier(read, output_table)
    let drop = { builder: StringBuilder(), remaining: read.remaining, }
    sql_text(drop, "DROP TABLE main.")
    sql_identifier(drop, output_table)
    Ok({
      query,
      create_sql: create.builder.to_string(),
      read_sql: read.builder.to_string(),
      drop_sql: drop.builder.to_string(),
    })
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
/// Resident tables use logical column names. Reject lossy CTAS name folding
/// before selection; fresh result transport does not materialize these names.
pub fn check_resident_output_static(
  owner : @lower.BoundPrepared,
  target : @pipeline.Target,
) -> Result[Unit, NativeQueryIssue] {
  let prepared = @lower.bound_preparation(owner)
  guard @lower.preparation_schema_at(prepared, target) is Some(schema) else {
    return Err(UnsupportedShape)
  }
  if !physical_column_names_unique(schema) {
    return Err(UnsupportedField)
  }
  Ok(())
}

///|
pub fn resident_query_create_sql(value : ResidentQuery) -> String {
  value.create_sql
}

///|
pub fn resident_query_read_sql(value : ResidentQuery) -> String {
  value.read_sql
}

///|
pub fn resident_query_drop_sql(value : ResidentQuery) -> String {
  value.drop_sql
}

///|
pub fn resident_query_parameter(
  value : ResidentQuery,
  index : Int,
) -> PhysicalParameter? {
  fixed_query_parameter(value.query, index)
}

///|
pub fn resident_query_owner(value : ResidentQuery) -> @lower.BoundPrepared {
  fixed_query_owner(value.query)
}
