///|
/// Physical preparation only. Execution must bind a live run-owned environment
/// and seal its table generation after successful import and transaction commit.
struct ResidentImport {
  storage : @execution.ProducerStorage
  table : String
  create_sql : String
  insert_sql : String
}

///|
/// Full immutable copy scan in insertion order, before receiver projection.
/// A shadowed rowid cannot stand in for the physical ordinal.
pub fn resident_import_scan_sql(
  imported : ResidentImport,
  max_sql_bytes : Int,
) -> Result[String, NativeQueryIssue] {
  if !resident_import_available(imported) {
    return Err(InputUnavailable)
  }
  if max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let schema = @execution.producer_storage_schema(imported.storage)
  for column in 0..<@schema.field_count(schema) {
    if @schema.reference_name(@schema.field_at(schema, column).unwrap().name).to_lower() ==
      "rowid" {
      return Err(UnsupportedField)
    }
  }
  let sql = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(sql, "SELECT * FROM main.")
    sql_identifier(sql, imported.table)
    sql_text(sql, " ORDER BY rowid")
    Ok(sql.builder.to_string())
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
pub fn resident_import_available(value : ResidentImport) -> Bool {
  @execution.producer_storage_available(value.storage)
}

///|
/// Exact immutable storage association; this is not a consumer binding.
pub fn resident_import_storage(
  value : ResidentImport,
) -> @execution.ProducerStorage {
  value.storage
}

///|
pub fn resident_import_matches_storage(
  value : ResidentImport,
  storage : @execution.ProducerStorage,
) -> Bool {
  physical_equal(value.storage, storage) && resident_import_available(value)
}

///|
pub fn resident_import_matches_output(
  value : ResidentImport,
  output : @execution.CompletedOutput,
) -> Bool {
  @execution.producer_storage_matches_output(value.storage, output)
}

///|
pub fn resident_import_drop_sql(
  value : ResidentImport,
  max_sql_bytes : Int,
) -> Result[String, NativeQueryIssue] {
  if max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let sql = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(sql, "DROP TABLE main.")
    sql_identifier(sql, value.table)
    Ok(sql.builder.to_string())
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
pub fn prepare_resident_import(
  storage : @execution.ProducerStorage,
  table : String,
  max_columns : Int,
  max_sql_bytes : Int,
) -> Result[ResidentImport, NativeQueryIssue] {
  if !@execution.producer_storage_available(storage) {
    return Err(InputUnavailable)
  }
  if max_columns < 0 || max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  match
    compile_fixed_import_schema(
      @execution.producer_storage_schema(storage),
      table,
      max_columns,
      max_sql_bytes,
      temporary=false,
    ) {
    Ok((create_sql, insert_sql, _)) =>
      Ok({ storage, table, create_sql, insert_sql, })
    Err(issue) => Err(issue)
  }
}

///|
pub fn resident_import_create_sql(value : ResidentImport) -> String {
  value.create_sql
}

///|
/// Native ingestion of an exact retained file after its full storage scan.
/// The caller must keep one thread, verify the file before use, and validate
/// the resulting table through the normal resident consumer boundary.
pub fn resident_import_file_sql(
  value : ResidentImport,
  max_row_bytes : Int,
  max_sql_bytes : Int,
) -> String? {
  let schema = @execution.producer_storage_schema(value.storage)
  if !resident_import_available(value) ||
    max_row_bytes <= 0 ||
    max_sql_bytes <= 0 ||
    @schema.field_count(schema) == 0 ||
    !physical_column_names_unique(schema) {
    return None
  }
  for index in 0..<@schema.field_count(schema) {
    let field = @schema.field_at(schema, index).unwrap()
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
    sql_text(output, "CREATE TABLE main.")
    sql_identifier(output, value.table)
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
    Some(output.builder.to_string())
  } catch {
    _ => None
  }
}

///|
pub fn resident_import_insert_sql(value : ResidentImport) -> String {
  value.insert_sql
}

///|
pub fn resident_import_batch_insert_sql(
  value : ResidentImport,
  requested_rows : Int,
  max_parameters : Int,
  max_sql_bytes : Int,
) -> Result[(Int, String), NativeQueryIssue] {
  if !resident_import_available(value) {
    return Err(InputUnavailable)
  }
  compile_import_batch_sql(
    value.insert_sql,
    resident_import_column_count(value),
    requested_rows,
    max_parameters,
    max_sql_bytes,
  )
}

///|
pub fn resident_import_row_count(value : ResidentImport) -> Int {
  @execution.producer_storage_row_count(value.storage)
}

///|
pub fn resident_import_column_count(value : ResidentImport) -> Int {
  @schema.field_count(@execution.producer_storage_schema(value.storage))
}

///|
pub fn resident_import_parameter(
  value : ResidentImport,
  row : Int,
  column : Int,
) -> Result[PhysicalParameter, ValueIssue] {
  if !@execution.producer_storage_available(value.storage) {
    return Err(InputUnavailable)
  }
  guard @schema.field_at(
      @execution.producer_storage_schema(value.storage),
      column,
    )
    is Some(field) else {
    return Err(OutOfRange)
  }
  guard @execution.producer_storage_cell(value.storage, row, column)
    is Some(cell) else {
    return Err(OutOfRange)
  }
  parameter_from_cell(field.contract, cell)
}

///|
/// A connection-local view maps a checked receiver onto the exact stored
/// producer. It never guesses by equal schema/content or rewrites query text.
pub fn resident_import_receiver_sql(
  imported : ResidentImport,
  input : @execution.ProducerRead,
  view : String,
  max_entries : Int,
  max_sql_bytes : Int,
) -> Result[String, NativeQueryIssue] {
  if max_entries < 0 || max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let mapping = match
    @execution.producer_storage_projection(imported.storage, input, max_entries) {
    Ok(value) => value
    Err(ProducerUnavailable) => return Err(InputUnavailable)
    Err(Limit) => return Err(Limit)
    Err(_) => return Err(UnsupportedShape)
  }
  if mapping.length() == 0 {
    return Err(UnsupportedShape)
  }
  let source = @execution.producer_storage_schema(imported.storage)
  let receiver = @execution.producer_read_schema(input)
  let sql = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(sql, "CREATE TEMP VIEW ")
    sql_identifier(sql, view)
    sql_text(sql, " AS SELECT ")
    for i, column in mapping {
      if i > 0 {
        sql_text(sql, ", ")
      }
      sql_identifier(
        sql,
        @schema.reference_name(@schema.field_at(source, column).unwrap().name),
      )
      sql_text(sql, " AS ")
      sql_identifier(
        sql,
        @schema.reference_name(@schema.field_at(receiver, i).unwrap().name),
      )
    }
    // The immutable resident table owns insertion order as its physical rowid.
    // Expose that stored ordinal explicitly; downstream joins must not derive a
    // fresh row_number from an optimizer-dependent scan order.
    sql_text(sql, ", rowid AS ")
    sql_identifier(sql, fixed_import_ordinal_column())
    sql_text(sql, " FROM main.")
    sql_identifier(sql, imported.table)
    Ok(sql.builder.to_string())
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}
