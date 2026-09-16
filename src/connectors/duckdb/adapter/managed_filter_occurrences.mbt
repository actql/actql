///|
/// Ordered physical occurrence output for the existing checked filter/select.
/// Host must bind ordinal to the exact input's unique zero-based logical row
/// order. Returned integers are not execution proof or authority to read rows.
/// The query's existing parameter and demand/completion obligations still apply.
pub fn[T] managed_fixed_selection_sql(
  query : ManagedFixedQuery[T],
  ordinal : String,
  occurrence_alias : String,
  limits : NativeQueryLimits,
) -> Result[String, NativeQueryIssue] {
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  if !managed_fixed_query_matches(query, query.input) {
    return Err(InputUnavailable)
  }
  guard query.query is FilterSelect(native) else {
    return Err(UnsupportedShape)
  }
  let input = @execution.managed_producer_read_schema(query.input)
  let output = @lower.preparation_schema_at(
    @lower.bound_preparation(native.owner),
    Step(1),
  ).unwrap()
  let mut work = limits.max_entries
  let mut bytes = limits.max_sql_bytes
  for name in [ordinal, occurrence_alias] {
    match @scalar.admit_utf8_length(name, bytes) {
      Ok(size) => bytes -= size
      Err(_) => return Err(Limit)
    }
  }
  for side, schema in [input, output] {
    let width = @schema.field_count(schema)
    if width > work {
      return Err(Limit)
    }
    work -= width
    for column in 0..<width {
      let name = @schema.reference_name(
        @schema.field_at(schema, column).unwrap().name,
      )
      match @scalar.admit_utf8_length(name, bytes) {
        Ok(size) => bytes -= size
        Err(_) => return Err(Limit)
      }
      let forbidden = if side == 0 { ordinal } else { occurrence_alias }
      if physical_column_name_key(name) == physical_column_name_key(forbidden) {
        return Err(UnsupportedField)
      }
    }
    if !physical_column_names_unique(schema) {
      return Err(UnsupportedField)
    }
  }
  let compiled = match
    compile_native_filter_select_base(
      native.owner,
      native.database_schema,
      native.table,
      limits,
      Some((ordinal, occurrence_alias)),
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  if !managed_fixed_query_matches(query, query.input) {
    return Err(InputUnavailable)
  }
  Ok(compiled.sql)
}
