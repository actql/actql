///|
/// Static SQL realization of one checked, fixed-input group/count. This is
/// neither an acquisition query nor execution evidence. Runtime binding must
/// still establish the exact input, limits, transport and successful retention.
struct NativeCountGroup {
  owner : @lower.BoundPrepared
  group : @lower.PreparedCountGroup
  sql : String
  table : String
}

///|
pub fn compile_fixed_count_group(
  owner : @lower.BoundPrepared,
  database_schema : String,
  table : String,
  limits : NativeQueryLimits,
) -> Result[NativeCountGroup, NativeQueryIssue] {
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let prepared = @lower.bound_preparation(owner)
  let pipeline = @lower.pipeline(prepared)
  if @pipeline.input_count(pipeline) != 1 || @pipeline.step_count(pipeline) != 1 {
    return Err(UnsupportedShape)
  }
  let kernel = match
    @lower.prepare_kernel(
      owner,
      0,
      max_bindings=limits.max_entries,
      max_name_bytes=limits.max_sql_bytes,
      limits.expressions,
    ) {
    Ok(kernel) => kernel
    Err(e) => return Err(Lowering(e))
  }
  guard @lower.kernel_count_group(kernel) is Some(group) else {
    return Err(UnsupportedShape)
  }
  if Some(@lower.kernel_input(kernel)) != @lower.input_id(prepared, 0) {
    return Err(UnsupportedShape)
  }
  let checked = @lower.count_group_checked(group)
  let input = @relation.input_schema(checked)
  let output = @relation.output_schema(checked)
  let width = @schema.field_count(output)
  if width > limits.max_entries {
    return Err(Limit)
  }
  // A zero-column output needs a hidden transport column, not an invented
  // user-visible aggregate. The ordinary Local realization remains eligible.
  if width == 0 {
    return Err(UnsupportedShape)
  }
  let counts : Map[String, @lower.PreparedCount] = Map([])
  for i in 0..<@lower.count_group_aggregate_count(group) {
    let count = @lower.count_group_aggregate_at(group, i).unwrap()
    counts[count.name] = count
  }
  let sql = { builder: StringBuilder(), remaining: limits.max_sql_bytes, }
  try {
    sql_text(sql, "SELECT ")
    for i in 0..<width {
      if i > 0 {
        sql_text(sql, ", ")
      }
      let field = @schema.field_at(output, i).unwrap().name
      let name = @schema.reference_name(field)
      match counts.get(name) {
        Some(count) => {
          // Imported row counts are Int-bounded. Exact counts therefore fit
          // binary64; this cast does not define a general language count cap.
          sql_text(sql, "CAST(COUNT(")
          match count.field {
            None => sql_text(sql, "*")
            Some(field) => sql_identifier(sql, @schema.reference_name(field))
          }
          sql_text(sql, ") AS DOUBLE)")
        }
        None => sql_identifier(sql, name)
      }
      sql_text(sql, " AS ")
      sql_identifier(sql, name)
    }
    sql_text(sql, " FROM ")
    sql_identifier(sql, database_schema)
    sql_text(sql, ".")
    sql_identifier(sql, table)
    let keys = @lower.count_group_key_count(group)
    if keys > 0 {
      sql_text(sql, " GROUP BY ")
      for i in 0..<keys {
        if i > 0 {
          sql_text(sql, ", ")
        }
        sql_identifier(
          sql,
          @schema.reference_name(@lower.count_group_key_at(group, i).unwrap()),
        )
      }
      sql_text(sql, " ORDER BY ")
      for i in 0..<keys {
        if i > 0 {
          sql_text(sql, ", ")
        }
        let field = @lower.count_group_key_at(group, i).unwrap()
        guard @schema.lookup(input, field) is Some(contract) else {
          return Err(UnsupportedField)
        }
        match parameter_type(contract) {
          Err(e) => return Err(Parameter(e))
          Ok(_) => ()
        }
        if contract.shape is @contract.Text(_) {
          emit_utf16_order_key(sql, @schema.reference_name(field))
        } else {
          sql_identifier(sql, @schema.reference_name(field))
        }
        sql_text(sql, " ASC NULLS FIRST")
      }
    }
    Ok({ owner, group, table, sql: sql.builder.to_string(), })
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
/// DuckDB's default VARCHAR byte order differs from ActQL's UTF16 order.
/// Generate a lexicographic list of UTF16 code units entirely inside SQL.
/// The helper list is physical scratch, never an output field or logical key.
fn emit_utf16_order_key(sql : SqlText, field : String) -> Unit raise SqlFailure {
  sql_text(sql, "flatten(list_transform(list_transform(range(1, length(")
  sql_identifier(sql, field)
  sql_text(sql, ") + 1), lambda __actql_i: unicode(substr(")
  sql_identifier(sql, field)
  sql_text(
    sql, ", __actql_i, 1))), lambda __actql_cp: CASE WHEN __actql_cp > 65535 THEN [55296 + ((__actql_cp - 65536) // 1024), 56320 + ((__actql_cp - 65536) % 1024)] ELSE [__actql_cp] END))",
  )
}

///|
pub fn fixed_count_group_owner(
  query : NativeCountGroup,
) -> @lower.BoundPrepared {
  query.owner
}

///|
pub fn fixed_count_group_sql(query : NativeCountGroup) -> String {
  query.sql
}

///|
pub fn fixed_count_group_profile(
  query : NativeCountGroup,
) -> @lower.PreparedCountGroup {
  query.group
}
