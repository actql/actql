///|
/// The full validation scan and native projection address the same owned query
/// and physical table. This handle grants neither source permission nor a read
/// view: the Host must execute both commands on one authorized transaction.
struct NativeScan {
  query : NativeQuery
  sql : String
  input_schema : @schema.Schema
  output_schema : @schema.Schema
}

///|
pub fn prepare_native_scan(
  query : NativeQuery,
  max_columns : Int,
  max_sql_bytes : Int,
) -> Result[NativeScan, NativeQueryIssue] {
  if max_columns < 0 || max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let pipeline = @lower.pipeline(@lower.bound_preparation(query.owner))
  guard @pipeline.schema_at(pipeline, Input(0)) is Some(input_schema) else {
    return Err(UnsupportedShape)
  }
  guard @pipeline.schema_at(pipeline, Step(1)) is Some(output_schema) else {
    return Err(UnsupportedShape)
  }
  let count = @schema.field_count(input_schema)
  if count > max_columns {
    return Err(Limit)
  }
  if count == 0 {
    return Err(UnsupportedShape)
  }
  let output = { builder: StringBuilder(), remaining: max_sql_bytes, }
  try {
    sql_text(output, "SELECT ")
    for i in 0..<count {
      let field = @schema.field_at(input_schema, i).unwrap()
      guard field.name is @schema.Unqualified(name) else {
        return Err(UnsupportedField)
      }
      if i > 0 {
        sql_text(output, ", ")
      }
      sql_identifier(output, name)
    }
    sql_text(output, " FROM ")
    sql_identifier(output, query.database_schema)
    sql_text(output, ".")
    sql_identifier(output, query.table)
    Ok({ query, sql: output.builder.to_string(), input_schema, output_schema, })
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
pub fn native_scan_query(scan : NativeScan) -> NativeQuery {
  scan.query
}

///|
pub fn native_scan_sql(scan : NativeScan) -> String {
  scan.sql
}

///|
/// Catalog-only verification command; it does not export source rows.
pub fn native_scan_metadata_sql(_scan : NativeScan) -> String {
  "SELECT table_type FROM information_schema.tables WHERE table_schema = ? AND table_name = ?"
}

///|
pub fn native_scan_metadata_parameter(
  scan : NativeScan,
  index : Int,
) -> PhysicalParameter? {
  let value = match index {
    0 => scan.query.database_schema
    1 => scan.query.table
    _ => return None
  }
  // Physical catalog names are Host identifiers, not ActQL scalar literals.
  Some({ id: "VARCHAR", decimal: None, value: ScalarText(value), })
}

///|
pub fn prepare_scan_validation_receiver(
  scan : NativeScan,
  fields : Array[(String, PhysicalType)],
  limits : PhysicalResultLimits,
  max_metadata_work : Int,
) -> Result[PhysicalResult, PhysicalResultIssue] {
  prepare_physical_result(scan.input_schema, fields, limits, max_metadata_work)
}

///|
pub fn prepare_scan_output_receiver(
  scan : NativeScan,
  fields : Array[(String, PhysicalType)],
  limits : PhysicalResultLimits,
  max_metadata_work : Int,
) -> Result[PhysicalResult, PhysicalResultIssue] {
  prepare_physical_result(scan.output_schema, fields, limits, max_metadata_work)
}
