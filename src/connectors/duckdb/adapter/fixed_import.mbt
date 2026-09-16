///|
/// SQL and an immutable, exactly owned fixed input. No source connection or
/// source address is part of this handle. Execution still requires an isolated
/// Host-owned Compute database and its receiving admission/resource checks.
struct FixedImport {
  input : @execution.ProducerRead
  table : String
  create_sql : String
  insert_sql : String
  columns : Int
}

///|
pub fn prepare_fixed_import(
  input : @execution.ProducerRead,
  table : String,
  max_columns : Int,
  max_sql_bytes : Int,
) -> Result[FixedImport, NativeQueryIssue] {
  if !@execution.producer_read_available(input) {
    return Err(InputUnavailable)
  }
  if max_columns < 0 || max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let schema = @execution.producer_read_schema(input)
  match compile_fixed_import_schema(schema, table, max_columns, max_sql_bytes) {
    Err(issue) => Err(issue)
    Ok((create_sql, insert_sql, columns)) =>
      Ok({ input, table, create_sql, insert_sql, columns, })
  }
}

///|
fn compile_fixed_import_schema(
  schema : @schema.Schema,
  table : String,
  max_columns : Int,
  max_sql_bytes : Int,
  temporary? : Bool = true,
) -> Result[(String, String, Int), NativeQueryIssue] {
  let count = @schema.field_count(schema)
  if count > max_columns {
    return Err(Limit)
  }
  // DuckDB cannot represent a zero-column table. This is adapter eligibility,
  // not a restriction on an empty-schema Relation or its logical row count.
  if count == 0 {
    return Err(UnsupportedShape)
  }
  if !physical_column_names_unique(schema) {
    return Err(UnsupportedField)
  }
  let create = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(
      create,
      if temporary {
        "CREATE TEMP TABLE "
      } else {
        "CREATE TABLE "
      },
    )
    sql_identifier(create, table)
    sql_text(create, " (")
    for i in 0..<count {
      let field = @schema.field_at(schema, i).unwrap()
      if i > 0 {
        sql_text(create, ", ")
      }
      sql_identifier(create, @schema.reference_name(field.name))
      sql_text(create, " ")
      let (id, decimal) = match parameter_type(field.contract) {
        Ok(value) => value
        Err(issue) => return Err(Parameter(issue))
      }
      if decimal is Some((precision, scale)) {
        sql_text(create, "DECIMAL(")
        sql_text(create, precision.to_string())
        sql_text(create, ",")
        sql_text(create, scale.to_string())
        sql_text(create, ")")
      } else {
        sql_text(create, if id == "TIMESTAMP_TZ" { "TIMESTAMPTZ" } else { id })
      }
      if !field.contract.nullable {
        sql_text(create, " NOT NULL")
      }
    }
    sql_text(create, ")")
    let insert = { builder: StringBuilder(), remaining: create.remaining, }
    sql_text(insert, "INSERT INTO ")
    sql_identifier(insert, table)
    sql_text(insert, " VALUES (")
    for i in 0..<count {
      if i > 0 {
        sql_text(insert, ", ")
      }
      sql_text(insert, "?")
    }
    sql_text(insert, ")")
    Ok((create.builder.to_string(), insert.builder.to_string(), count))
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
// DuckDB identifiers fold ASCII case even when quoted. Logical ActQL names do
// not. Do not let CREATE TABLE reject or CTAS silently rename these fields.
fn physical_column_names_unique(schema : @schema.Schema) -> Bool {
  let names : Map[String, Bool] = Map([])
  for i in 0..<@schema.field_count(schema) {
    let name = @schema.reference_name(@schema.field_at(schema, i).unwrap().name)
    let folded = StringBuilder()
    for char in name {
      if char >= 'A' && char <= 'Z' {
        folded.write_string(char.to_string().to_lower())
      } else {
        folded.write_char(char)
      }
    }
    let key = folded.to_string()
    if names.contains(key) {
      return false
    }
    names[key] = true
  }
  true
}

///|
pub fn fixed_import_create_sql(value : FixedImport) -> String {
  value.create_sql
}

///|
pub fn fixed_import_insert_sql(value : FixedImport) -> String {
  value.insert_sql
}

///|
/// Bounded physical batching of the same exactly owned input. This changes
/// neither its row order nor logical admission. Returned rows may be smaller
/// than requested to fit the statement/parameter envelope, never larger.
pub fn fixed_import_batch_insert_sql(
  value : FixedImport,
  requested_rows : Int,
  max_parameters : Int,
  max_sql_bytes : Int,
) -> Result[(Int, String), NativeQueryIssue] {
  if requested_rows < 1 || max_parameters < 0 || max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !@execution.producer_read_available(value.input) {
    return Err(InputUnavailable)
  }
  compile_import_batch_sql(
    value.insert_sql,
    value.columns,
    requested_rows,
    max_parameters,
    max_sql_bytes,
  )
}

///|
fn compile_import_batch_sql(
  insert_sql : String,
  columns : Int,
  requested_rows : Int,
  max_parameters : Int,
  max_sql_bytes : Int,
) -> Result[(Int, String), NativeQueryIssue] {
  if requested_rows < 1 ||
    columns < 1 ||
    max_parameters < 0 ||
    max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  if columns > max_parameters {
    return Err(Limit)
  }
  let output = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(output, insert_sql)
    let mut rows = 1
    let parameter_rows = max_parameters / columns
    let maximum = if requested_rows < parameter_rows {
      requested_rows
    } else {
      parameter_rows
    }
    // Every extra tuple has exactly 3 * columns + 2 ASCII bytes. Divide
    // before multiplying to avoid overflow even with hostile limit values.
    if maximum > 1 &&
      output.remaining >= 2 &&
      columns <= (output.remaining - 2) / 3 {
      let tuple_bytes = 3 * columns + 2
      let sql_rows = output.remaining / tuple_bytes
      let count = if maximum - 1 < sql_rows { maximum - 1 } else { sql_rows }
      for _ in 0..<count {
        sql_text(output, ", (")
        for column in 0..<columns {
          if column > 0 {
            sql_text(output, ", ")
          }
          sql_text(output, "?")
        }
        sql_text(output, ")")
        rows += 1
      }
    }
    Ok((rows, output.builder.to_string()))
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
pub fn fixed_import_input(value : FixedImport) -> @execution.ProducerRead {
  value.input
}

///|
pub fn fixed_import_column_count(value : FixedImport) -> Int {
  value.columns
}

///|
pub fn fixed_import_parameter(
  value : FixedImport,
  row : Int,
  column : Int,
) -> Result[PhysicalParameter, ValueIssue] {
  prepare_producer_parameter(value.input, row, column)
}
