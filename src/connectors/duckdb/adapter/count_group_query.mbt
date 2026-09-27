///|
/// Static SQL realization of one checked, fixed-input group/count. This is
/// neither an acquisition query nor execution evidence. Runtime binding must
/// still establish the exact input, limits, transport and successful retention.
struct NativeCountGroup {
  owner : @lower.BoundPrepared
  group : @lower.PreparedCountGroup
  sql : String
  table : String
  output_names : Array[String]
}

///|
fn count_group_output_name(index : Int) -> String {
  "__actql_output_" + index.to_string()
}

///|
fn count_group_output_index(
  schema : @schema.Schema,
  name : @schema.FieldName,
) -> Int? {
  for index in 0..<@schema.field_count(schema) {
    if @schema.field_at(schema, index).unwrap().name == name {
      return Some(index)
    }
  }
  None
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
  if @lower.preparation_input_count(prepared) != 1 ||
    @lower.node_count(prepared) != 1 {
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
  let input = @lower.preparation_input_schema(prepared, 0).unwrap()
  let output = @lower.node_output_schema(@lower.node_at(prepared, 0).unwrap())
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
  let keys = @lower.count_group_key_count(group)
  let output_names = Array::makei(width, count_group_output_name)
  try {
    sql_text(sql, if keys > 0 { "SELECT * FROM (SELECT " } else { "SELECT " })
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
          if count.count_if {
            guard count.field is Some(field) else {
              return Err(UnsupportedField)
            }
            sql_text(sql, "CASE WHEN ")
            group_input_identifier(sql, @schema.reference_name(field))
            sql_text(sql, " THEN 1 END")
          } else {
            match count.field {
              None => sql_text(sql, "*")
              Some(field) =>
                group_input_identifier(sql, @schema.reference_name(field))
            }
          }
          sql_text(sql, ") AS DOUBLE)")
        }
        None => {
          guard @schema.lookup(input, field) is Some(contract) else {
            return Err(UnsupportedField)
          }
          if contract.shape is @contract.Text(_) {
            sql_text(sql, "first(")
            group_input_identifier(sql, name)
            sql_text(sql, ")")
          } else {
            group_input_identifier(sql, name)
          }
        }
      }
      sql_text(sql, " AS ")
      sql_identifier(sql, output_names[i])
    }
    sql_text(sql, " FROM ")
    sql_identifier(sql, database_schema)
    sql_text(sql, ".")
    sql_identifier(sql, table)
    sql_text(sql, " AS __actql_source")
    if keys > 0 {
      sql_text(sql, " GROUP BY ")
      for i in 0..<keys {
        if i > 0 {
          sql_text(sql, ", ")
        }
        let field = @lower.count_group_key_at(group, i).unwrap()
        guard @schema.lookup(input, field) is Some(contract) else {
          return Err(UnsupportedField)
        }
        if contract.shape is @contract.Text(_) {
          sql_text(sql, "encode(")
          group_input_identifier(sql, @schema.reference_name(field))
          sql_text(sql, ")")
        } else {
          group_input_identifier(sql, @schema.reference_name(field))
        }
      }
      sql_text(sql, ") AS __actql_grouped ORDER BY ")
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
          emit_utf16_order_key_from(
            sql,
            "__actql_grouped",
            count_group_output_name(
              count_group_output_index(output, field).unwrap(),
            ),
          )
        } else {
          physical_input_identifier(
            sql,
            "__actql_grouped",
            count_group_output_name(
              count_group_output_index(output, field).unwrap(),
            ),
          )
        }
        sql_text(sql, " ASC NULLS FIRST")
      }
    }
    Ok({ owner, group, table, sql: sql.builder.to_string(), output_names, })
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
/// Physical UTF-16 order key for a trusted SQL alias and checked text field.
/// This is an implementation of the existing logical text order, not a new
/// collation contract.
fn emit_utf16_order_key_from(
  sql : SqlText,
  source_alias : String,
  field : String,
) -> Unit raise SqlFailure {
  sql_text(sql, "flatten(list_transform(list_transform(range(1, length(")
  physical_input_identifier(sql, source_alias, field)
  sql_text(sql, ") + 1), lambda __actql_i: unicode(substr(")
  physical_input_identifier(sql, source_alias, field)
  sql_text(
    sql, ", __actql_i, 1))), lambda __actql_cp: CASE WHEN __actql_cp > 65535 THEN [55296 + ((__actql_cp - 65536) // 1024), 56320 + ((__actql_cp - 65536) % 1024)] ELSE [__actql_cp] END))",
  )
}

///|
fn group_input_identifier(
  sql : SqlText,
  field : String,
) -> Unit raise SqlFailure {
  sql_text(sql, "__actql_source.")
  sql_identifier(sql, field)
}

///|
fn physical_input_identifier(
  sql : SqlText,
  source_alias : String,
  field : String,
) -> Unit raise SqlFailure {
  sql_identifier(sql, source_alias)
  sql_text(sql, ".")
  sql_identifier(sql, field)
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

///|
pub fn fixed_count_group_output_names(
  query : NativeCountGroup,
) -> Array[String] {
  query.output_names.copy()
}
