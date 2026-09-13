///|
pub(all) enum NativeQueryIssue {
  InvalidLimits
  Limit
  UnsupportedShape
  UnsupportedPredicate
  UnsupportedField
  InvalidIdentifier
  Lowering(@lower.KernelIssue)
  Parameter(ValueIssue)
}

///|
pub(all) struct NativeQueryLimits {
  max_entries : Int
  max_sql_bytes : Int
  expressions : @lower.ExpressionLimits
}

///|
/// Compilation is not authority or completion. The exact checked owner stays
/// attached for runtime eligibility and completion validation by the Host.
struct NativeQuery {
  owner : @lower.BoundPrepared
  sql : String
  parameter : PhysicalParameter
}

///|
priv struct SqlText {
  builder : StringBuilder
  mut remaining : Int
}

///|
priv suberror SqlFailure {
  TextLimit
  BadIdentifier
}

///|
fn sql_text(output : SqlText, text : String) -> Unit raise SqlFailure {
  match @scalar.admit_utf8_length(text, output.remaining) {
    Err(_) => raise TextLimit
    Ok(bytes) => {
      output.remaining -= bytes
      output.builder.write_string(text)
    }
  }
}

///|
fn sql_identifier(output : SqlText, name : String) -> Unit raise SqlFailure {
  if name == "" {
    raise BadIdentifier
  }
  // Validate Unicode and charge all bytes before building the quoted spelling.
  let bytes = match @scalar.admit_utf8_length(name, output.remaining) {
    Ok(bytes) => bytes
    Err(_) => raise TextLimit
  }
  output.remaining -= bytes
  sql_text(output, "\"")
  for char in name.iter() {
    if char == '\u0000' {
      raise BadIdentifier
    }
    if char == '"' {
      sql_text(output, "\"")
    }
    output.builder.write_char(char)
  }
  sql_text(output, "\"")
}

///|
/// A physical table address supplied by trusted Host binding, not user SQL.
/// Only direct InputField comparisons against an already bound scalar compile.
/// Full-scan type/value validation and logical guards remain runtime obligations.
pub fn compile_native_filter_select(
  owner : @lower.BoundPrepared,
  database_schema : String,
  table : String,
  limits : NativeQueryLimits,
) -> Result[NativeQuery, NativeQueryIssue] {
  if limits.max_entries < 0 || limits.max_sql_bytes < 0 {
    return Err(InvalidLimits)
  }
  let preparation = @lower.bound_preparation(owner)
  let pipeline = @lower.pipeline(preparation)
  if @pipeline.input_count(pipeline) != 1 || @pipeline.step_count(pipeline) != 2 {
    return Err(UnsupportedShape)
  }
  let filter = match
    @lower.prepare_kernel(
      owner,
      0,
      max_bindings=limits.max_entries,
      max_name_bytes=limits.max_sql_bytes,
      limits.expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lowering(issue))
  }
  let projection = match
    @lower.prepare_kernel(
      owner,
      1,
      max_bindings=limits.max_entries,
      max_name_bytes=limits.max_sql_bytes,
      limits.expressions,
    ) {
    Ok(value) => value
    Err(issue) => return Err(Lowering(issue))
  }
  if @lower.kernel_view_entries(filter) > limits.max_entries ||
    @lower.kernel_view_entries(projection) >
    limits.max_entries - @lower.kernel_view_entries(filter) {
    return Err(Limit)
  }
  guard @lower.kernel_body(filter) is @lower.Filter(expression) else {
    return Err(UnsupportedShape)
  }
  guard @lower.kernel_body(projection) is @lower.Select(fields) else {
    return Err(UnsupportedShape)
  }
  guard @lower.node_at(preparation, 0) is Some(filter_node) else {
    return Err(UnsupportedShape)
  }
  if @lower.kernel_input(projection) != @lower.node_id(filter_node) ||
    Some(@lower.kernel_input(filter)) != @lower.input_id(preparation, 0) {
    return Err(UnsupportedShape)
  }
  guard @lower.expression_body(expression)
    is @lower.Binary(operator, left, right) else {
    return Err(UnsupportedPredicate)
  }
  guard @lower.expression_body(left)
    is @lower.Field(_, @relation.InputField(@schema.Unqualified(name))) else {
    return Err(UnsupportedPredicate)
  }
  let number = @lower.expression_contract(left).shape is @contract.Number
  let boolean = @lower.expression_contract(left).shape is @contract.Boolean
  let symbol = match operator {
    Equal if number || boolean => " = "
    NotEqual if number => " <> "
    Less if number => " < "
    LessEqual if number => " <= "
    Greater if number => " > "
    GreaterEqual if number => " >= "
    _ => return Err(UnsupportedPredicate)
  }
  let parameter = match @lower.expression_body(right) {
    Literal(value) => {
      let valid = match value.value {
        @admitted.Null => true
        @admitted.Number(_) => number
        @admitted.Boolean(_) => boolean
        _ => false
      }
      if !valid {
        return Err(UnsupportedPredicate)
      }
      if value.value is @admitted.Null {
        {
          id: if number {
            "DOUBLE"
          } else {
            "BOOLEAN"
          },
          decimal: None,
          value: Some(value.value),
        }
      } else {
        match prepare_physical_parameter(value) {
          Ok(value) => value
          Err(issue) => return Err(Parameter(issue))
        }
      }
    }
    TypedNull =>
      {
        id: if number {
          "DOUBLE"
        } else {
          "BOOLEAN"
        },
        decimal: None,
        value: None,
      }
    _ => return Err(UnsupportedPredicate)
  }
  let output = { builder: StringBuilder(), remaining: limits.max_sql_bytes, }
  try {
    sql_text(output, "SELECT ")
    for i, field in fields {
      guard field.input is @schema.Unqualified(input) else {
        return Err(UnsupportedField)
      }
      guard field.output is @schema.Unqualified(result) else {
        return Err(UnsupportedField)
      }
      if i > 0 {
        sql_text(output, ", ")
      }
      sql_identifier(output, input)
      sql_text(output, " AS ")
      sql_identifier(output, result)
    }
    sql_text(output, " FROM ")
    sql_identifier(output, database_schema)
    sql_text(output, ".")
    sql_identifier(output, table)
    sql_text(output, " WHERE ")
    // Validated physical integers/floats must compare in the checked binary64
    // domain, not DuckDB's parameter-dependent integer comparison coercions.
    if number {
      sql_text(output, "CAST(")
    }
    sql_identifier(output, name)
    if number {
      sql_text(output, " AS DOUBLE)")
    }
    sql_text(output, symbol)
    sql_text(output, "?")
    Ok({ owner, sql: output.builder.to_string(), parameter, })
  } catch {
    TextLimit => Err(Limit)
    BadIdentifier => Err(InvalidIdentifier)
  }
}

///|
pub fn native_query_owner(query : NativeQuery) -> @lower.BoundPrepared {
  query.owner
}

///|
pub fn native_query_sql(query : NativeQuery) -> String {
  query.sql
}

///|
pub fn native_query_parameter(query : NativeQuery) -> PhysicalParameter {
  query.parameter
}
