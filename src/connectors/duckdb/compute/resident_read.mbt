///|
/// Concrete receiver view preparation. A view plan does not grant a table lease
/// or discharge the common driver checks on exact input ownership and liveness.
struct DuckDBResidentRead {
  sql : String
}

///|
pub fn prepare_duckdb_resident_read(
  imported : @duckdb.ResidentImport,
  input : @execution.ProducerRead,
  view_name : String,
  max_entries : Int,
  max_sql_bytes : Int,
) -> Result[DuckDBResidentRead, @duckdb.NativeQueryIssue] {
  @duckdb.resident_import_receiver_sql(
    imported, input, view_name, max_entries, max_sql_bytes,
  ).map(sql => { sql, })
}

///|
/// Bounded measurement of the actual representation, not a cost estimate.
pub fn duckdb_resident_read_bytes(
  read : DuckDBResidentRead,
  limit : Int,
) -> Int? {
  match @scalar.admit_utf8_length(read.sql, limit) {
    Ok(bytes) => Some(bytes)
    Err(_) => None
  }
}

///|
/// Only concrete transport wiring needs the SQL representation.
pub fn duckdb_resident_read_sql(read : DuckDBResidentRead) -> String {
  read.sql
}
