///|
/// Concrete receiver view preparation. A view plan does not grant a table lease
/// or discharge the common driver checks on exact input ownership and liveness.
struct DuckDBResidentRead {
  sql : String
  imported : @duckdb.ResidentImport
  input : @execution.ProducerRead
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
  ).map(sql => { sql, imported, input, })
}

///|
pub fn duckdb_resident_read_matches(
  read : DuckDBResidentRead,
  imported : @duckdb.ResidentImport,
  input : @execution.ProducerRead,
) -> Bool {
  physical_equal(read.imported, imported) &&
  physical_equal(read.input, input) &&
  @duckdb.resident_import_available(imported) &&
  @execution.producer_read_available(input)
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

///|
pub fn duckdb_resident_scan_sql(
  read : DuckDBResidentRead,
  max_bytes : Int,
) -> Result[String, @duckdb.NativeQueryIssue] {
  if !@execution.producer_read_available(read.input) {
    return Err(InputUnavailable)
  }
  @duckdb.resident_import_scan_sql(read.imported, max_bytes)
}

///|
pub fn duckdb_resident_demand_scan_sql(
  read : DuckDBResidentRead,
  column : Int,
  max_bytes : Int,
) -> Result[String, @duckdb.NativeQueryIssue] {
  if !@execution.producer_read_available(read.input) {
    return Err(InputUnavailable)
  }
  @duckdb.resident_import_demand_scan_sql(
    read.imported,
    read.input,
    column,
    max_bytes,
  )
}
