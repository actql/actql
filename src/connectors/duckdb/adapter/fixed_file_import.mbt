///|
/// Native parsing of the admitted stored wire. This is a physical conversion,
/// not validation evidence on its own: the complete resulting table still needs
/// the typed input scan, consumer demand and guards. Ordered content identity
/// is checked by hashing or the installed Host's exact native-copy proof.
pub fn fixed_import_file_sql(
  stream : FixedImportStream,
  max_row_bytes : Int,
  max_sql_bytes : Int,
) -> (String, String)? {
  let schema = @execution.retained_producer_scan_schema(stream.scan)
  if max_row_bytes <= 0 ||
    max_sql_bytes <= 0 ||
    @schema.field_count(schema) == 0 ||
    !physical_column_names_unique(schema) {
    return None
  }
  for index in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, index).unwrap()
    // Typed wire wrappers for dates/decimals/etc need a separate conversion.
    // rowid must remain the native insertion-order ordinal, not a user column.
    if @schema.reference_name(field.name).to_lower() == "rowid" {
      return None
    }
    match field.contract.shape {
      @contract.Number | @contract.Boolean | @contract.Text(_) => ()
      _ => return None
    }
  }
  let output = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(output, "CREATE TEMP TABLE ")
    sql_identifier(output, stream.owner.table)
    sql_text(
      output, " AS SELECT * FROM read_json(?, format='array', records=true, auto_detect=false, columns={",
    )
    for index in 0..<@schema.field_count(schema) {
      let field = @schema.field_at(schema, index).unwrap()
      if index > 0 {
        sql_text(output, ", ")
      }
      sql_identifier(output, @schema.reference_name(field.name))
      sql_text(output, ": '")
      let kind = match field.contract.shape {
        @contract.Number => "DOUBLE"
        @contract.Boolean => "BOOLEAN"
        _ => "VARCHAR"
      }
      sql_text(output, kind)
      sql_text(output, "'")
    }
    sql_text(output, "}, maximum_object_size=")
    sql_text(output, max_row_bytes.to_string())
    sql_text(output, ", ignore_errors=false)")
    let scan = { builder: StringBuilder(), remaining: output.remaining, }
    sql_text(scan, "SELECT * FROM ")
    sql_identifier(scan, stream.owner.table)
    sql_text(scan, " ORDER BY rowid")
    Some((output.builder.to_string(), scan.builder.to_string()))
  } catch {
    _ => None
  }
}
