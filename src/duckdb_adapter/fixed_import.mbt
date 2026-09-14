///|
/// SQL and an immutable, exactly owned fixed input. No source connection or
/// source address is part of this handle. Execution still requires an isolated
/// Host-owned Compute database and its receiving admission/resource checks.
struct FixedImport {
  input : @execution.ProducerRead
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
      Ok({ input, create_sql, insert_sql, columns, })
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
pub fn fixed_import_create_sql(value : FixedImport) -> String {
  value.create_sql
}

///|
pub fn fixed_import_insert_sql(value : FixedImport) -> String {
  value.insert_sql
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
