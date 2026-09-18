///|
/// Checked fixed-input SQL only. Completion still requires input admission,
/// null/cardinality validation, output guards and exactly owned transport.
struct NativeInnerJoin {
  owner : @lower.BoundPrepared
  profile : @lower.PreparedInnerJoin
  sql : String
  left_input : Int
  right_input : Int
  tables : Array[String]
  output_limit : Int64?
}

///|
fn join_column(
  schema : @schema.Schema,
  field : @schema.FieldName,
  work : Ref[Int],
) -> Int? {
  for index in 0..<@schema.field_count(schema) {
    if work.val <= 0 {
      return None
    }
    work.val -= 1
    if @schema.field_at(schema, index).unwrap().name == field {
      return Some(index)
    }
  }
  None
}

///|
fn join_sql_column(
  sql : SqlText,
  left : Bool,
  column : Int,
) -> Unit raise SqlFailure {
  sql_text(sql, if left { "l." } else { "r." })
  sql_identifier(sql, "c" + column.to_string())
}

///|
fn join_sql_key(
  sql : SqlText,
  left : Bool,
  column : Int,
  kind : String,
  scale : Int,
) -> Unit raise SqlFailure {
  if kind == "VARCHAR" {
    // Byte equality, independent of connection collation or normalization.
    sql_text(sql, "encode(")
    join_sql_column(sql, left, column)
    sql_text(sql, ")")
  } else if kind == "DECIMAL" {
    // Avoid a common DECIMAL(38,s) cast that cannot represent both operands.
    // Imported decimals have exact fixed-scale textual rendering; remove only
    // fractional zeroes, never integer zeroes, then compare canonical numbers.
    if scale > 0 {
      sql_text(sql, "rtrim(rtrim(")
    }
    sql_text(sql, "CAST(")
    join_sql_column(sql, left, column)
    sql_text(sql, " AS VARCHAR)")
    if scale > 0 {
      sql_text(sql, ", '0'), '.')")
    }
  } else {
    join_sql_column(sql, left, column)
  }
}

///|
pub fn compile_fixed_inner_join(
  owner : @lower.BoundPrepared,
  database_schema : String,
  tables : Array[String],
  limits : NativeQueryLimits,
) -> Result[NativeInnerJoin, NativeQueryIssue] {
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let prepared = @lower.bound_preparation(owner)
  let count = @lower.preparation_input_count(prepared)
  if count < 1 ||
    count > 2 ||
    tables.length() != count ||
    @lower.node_count(prepared) != 1 {
    return Err(UnsupportedShape)
  }
  let node = @lower.node_at(prepared, 0).unwrap()
  guard @lower.node_input_target(node, 0) is Some(@pipeline.Input(left_input)) &&
    @lower.node_input_target(node, 1) is Some(@pipeline.Input(right_input)) else {
    return Err(UnsupportedShape)
  }
  let kernel = match
    @lower.prepare_join_kernel(
      owner,
      0,
      limits.max_entries,
      limits.max_sql_bytes,
    ) {
    Ok(kernel) => kernel
    Err(PreparationLimit) => return Err(Limit)
    Err(_) => return Err(UnsupportedShape)
  }
  let profile = @lower.join_kernel_profile(kernel)
  if @lower.inner_join_kind(profile) != @join.Inner {
    return Err(UnsupportedShape)
  }
  let schemas = [
    @lower.preparation_input_schema(prepared, left_input).unwrap(),
    @lower.preparation_input_schema(prepared, right_input).unwrap(),
  ]
  let width = @lower.inner_join_field_count(profile)
  if width == 0 {
    return Err(UnsupportedShape)
  }
  let work = Ref(limits.max_entries)
  let sql = SqlText::{
    builder: StringBuilder(),
    remaining: limits.max_sql_bytes,
  }
  try {
    sql_text(sql, "SELECT ")
    for index in 0..<width {
      let field = @lower.inner_join_field_at(profile, index).unwrap()
      guard field.input is @schema.Qualified(side, name) else {
        return Err(UnsupportedField)
      }
      let left = side == @schema.Left
      guard join_column(
          schemas[if left { 0 } else { 1 }],
          @schema.Unqualified(name),
          work,
        )
        is Some(column) else {
        return Err(Limit)
      }
      if index > 0 {
        sql_text(sql, ", ")
      }
      join_sql_column(sql, left, column)
      sql_text(sql, " AS ")
      sql_identifier(sql, @schema.reference_name(field.output))
    }
    for side in 0..<2 {
      sql_text(
        sql,
        if side == 0 {
          " FROM (SELECT "
        } else {
          " INNER JOIN (SELECT "
        },
      )
      let schema = schemas[side]
      for column in 0..<@schema.field_count(schema) {
        if work.val <= 0 {
          return Err(Limit)
        }
        work.val -= 1
        let field = @schema.field_at(schema, column).unwrap()
        match parameter_type(field.contract) {
          Err(issue) => return Err(Parameter(issue))
          Ok(_) => ()
        }
        if column > 0 {
          sql_text(sql, ", ")
        }
        sql_identifier(sql, @schema.reference_name(field.name))
        sql_text(sql, " AS ")
        sql_identifier(sql, "c" + column.to_string())
      }
      if @schema.field_count(schema) > 0 {
        sql_text(sql, ", ")
      }
      sql_text(sql, "row_number() OVER () AS \"__ordinal\" FROM ")
      sql_identifier(sql, database_schema)
      sql_text(sql, ".")
      sql_identifier(
        sql,
        tables[if side == 0 { left_input } else { right_input }],
      )
      sql_text(sql, if side == 0 { ") AS l" } else { ") AS r ON " })
    }
    for key in 0..<@lower.inner_join_key_count(profile) {
      let (left, right) = @lower.inner_join_key_at(profile, key).unwrap()
      guard join_column(schemas[0], left, work) is Some(l) &&
        join_column(schemas[1], right, work) is Some(r) else {
        return Err(Limit)
      }
      let lt = match
        parameter_type(@schema.field_at(schemas[0], l).unwrap().contract) {
        Ok(t) => t
        Err(issue) => return Err(Parameter(issue))
      }
      let rt = match
        parameter_type(@schema.field_at(schemas[1], r).unwrap().contract) {
        Ok(t) => t
        Err(issue) => return Err(Parameter(issue))
      }
      if lt.0 != rt.0 {
        return Err(UnsupportedField)
      }
      if key > 0 {
        sql_text(sql, " AND ")
      }
      join_sql_key(sql, true, l, lt.0, lt.1.map(pair => pair.1).unwrap_or(0))
      sql_text(sql, " = ")
      join_sql_key(sql, false, r, rt.0, rt.1.map(pair => pair.1).unwrap_or(0))
    }
    sql_text(sql, " ORDER BY l.\"__ordinal\" ASC, r.\"__ordinal\" ASC")
  } catch {
    TextLimit => return Err(Limit)
    BadIdentifier => return Err(InvalidIdentifier)
  }
  Ok({
    owner,
    profile,
    sql: sql.builder.to_string(),
    left_input,
    right_input,
    tables: tables.copy(),
    output_limit: @lower.join_kernel_output_limit(kernel),
  })
}

///|
pub fn native_inner_join_sql(query : NativeInnerJoin) -> String {
  query.sql
}

///|
pub fn native_inner_join_owner(query : NativeInnerJoin) -> @lower.BoundPrepared {
  query.owner
}

///|
pub fn native_inner_join_profile(
  query : NativeInnerJoin,
) -> @lower.PreparedInnerJoin {
  query.profile
}

///|
pub fn native_inner_join_input(query : NativeInnerJoin, left : Bool) -> Int {
  if left {
    query.left_input
  } else {
    query.right_input
  }
}

///|
pub fn native_inner_join_output_limit(query : NativeInnerJoin) -> Int64? {
  query.output_limit
}
