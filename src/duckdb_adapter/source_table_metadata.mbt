///|
pub(all) enum SourceTableIssue {
  InvalidMetadata
  NotBaseTable
}

///|
fn source_table_metadata_sql() -> String {
  "SELECT table_type FROM information_schema.tables WHERE table_schema = ? AND table_name = ?"
}

///|
fn validate_source_table_metadata(
  rows : Int,
  fields : Array[(String, PhysicalType)],
  columns : Array[@decode.Cursor],
) -> Result[Unit, SourceTableIssue] {
  if rows != 1 ||
    fields.length() != 1 ||
    columns.length() != 1 ||
    fields[0] != ("table_type", Varchar) ||
    @decode.array_length(columns[0]) != Some(1) {
    return Err(InvalidMetadata)
  }
  guard @decode.text(@decode.element_at(columns[0], 0).unwrap())
    is Ok("BASE TABLE") else {
    return Err(NotBaseTable)
  }
  Ok(())
}
