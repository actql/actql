///|
/// Native result materialization uses the very same checked query and bound
/// parameter as fresh execution. It is not completion or resident provenance.
struct ResidentQuery {
  query : NativeQuery
  create_sql : String
  read_sql : String
  drop_sql : String
}

///|
pub fn prepare_resident_query(
  query : NativeQuery,
  output_table : String,
  max_sql_bytes : Int,
) -> Result[ResidentQuery, NativeQueryIssue] {
  if max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  if output_table == query.table {
    return Err(InvalidIdentifier)
  }
  let create = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(create, "CREATE TABLE ")
    sql_identifier(create, output_table)
    sql_text(create, " AS ")
    sql_text(create, query.sql)
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
pub fn resident_query_parameter(value : ResidentQuery) -> PhysicalParameter {
  value.query.parameter
}

///|
pub fn resident_query_owner(value : ResidentQuery) -> @lower.BoundPrepared {
  value.query.owner
}
