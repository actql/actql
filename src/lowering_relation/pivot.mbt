///|
/// Owner-bound pivot profile. The checker remains authoritative for schema,
/// aggregate applicability, stable-order obligations, and fill typing.
struct PreparedPivot {
  input_schema : @schema.Schema
  output_schema : @schema.Schema
  result_contract : @contract.Contract
  index : Array[@schema.FieldName]
  column : @schema.FieldName
  value : @schema.FieldName
  values : Array[String]
  function : @relation.AggregateFunction
  fill : PreparedPivotFill?
}

///|
pub enum PreparedPivotFill {
  Null
  Value(@value.CheckedValue)
}

///|
pub(all) enum PivotIssue {
  NotPivot
  InvalidLimits
  PreparationLimit
  MissingFillParameter(String)
} derive(Eq, Debug)

///|
fn prepare_pivot(
  owner : BoundPrepared,
  checked : @relation.CheckedOperation,
  max_entries : Int,
  max_name_bytes : Int,
) -> Result[(PreparedPivot, Int, Int), PivotIssue] {
  if max_entries < 0 || max_name_bytes < 0 {
    return Err(InvalidLimits)
  }
  guard @relation.pivot(checked) is Some(pivot) else { return Err(NotPivot) }
  let index_count = @relation.pivot_index_count(pivot)
  let value_count = @relation.pivot_value_count(pivot)
  if index_count > max_entries || value_count > max_entries - index_count - 2 {
    return Err(PreparationLimit)
  }
  let mut remaining = max_name_bytes
  let spend_name = fn(name : String) -> Bool {
    if name.length() > remaining {
      return false
    }
    let bytes = @utf8.encode(name).length()
    if bytes > remaining {
      return false
    }
    remaining -= bytes
    true
  }
  let index : Array[@schema.FieldName] = []
  for i = 0; i < index_count; i = i + 1 {
    let field = @relation.pivot_index_at(pivot, i).unwrap().field
    if !spend_name(@schema.reference_name(field)) {
      return Err(PreparationLimit)
    }
    index.push(field)
  }
  let column = @relation.pivot_column(pivot).field
  let value = @relation.pivot_value(pivot).field
  if !spend_name(@schema.reference_name(column)) ||
    !spend_name(@schema.reference_name(value)) {
    return Err(PreparationLimit)
  }
  let values : Array[String] = []
  for i = 0; i < value_count; i = i + 1 {
    let name = @relation.pivot_value_at(pivot, i).unwrap()
    if !spend_name(name) {
      return Err(PreparationLimit)
    }
    values.push(name)
  }
  let fill = match @relation.pivot_fill(pivot) {
    None => None
    Some(@relation.Null(..)) => Some(Null)
    Some(@relation.Literal(value, ..)) => Some(Value(value))
    Some(@relation.Parameter(name, ..)) =>
      match parameter_value(owner, name) {
        Some(value) => Some(Value(value))
        None => return Err(MissingFillParameter(name))
      }
  }
  Ok(
    (
      {
        input_schema: @relation.input_schema(checked),
        output_schema: @relation.output_schema(checked),
        result_contract: @relation.pivot_result(pivot),
        index,
        column,
        value,
        values,
        function: @relation.pivot_function(pivot),
        fill,
      },
      max_name_bytes - remaining,
      index_count + value_count + 2,
    ),
  )
}

///|
pub fn pivot_index_count(value : PreparedPivot) -> Int {
  value.index.length()
}

///|
pub fn pivot_index_at(value : PreparedPivot, index : Int) -> @schema.FieldName? {
  value.index.get(index)
}

///|
pub fn pivot_column(value : PreparedPivot) -> @schema.FieldName {
  value.column
}

///|
pub fn pivot_value(value : PreparedPivot) -> @schema.FieldName {
  value.value
}

///|
pub fn pivot_axis_count(value : PreparedPivot) -> Int {
  value.values.length()
}

///|
pub fn pivot_axis_at(value : PreparedPivot, index : Int) -> String? {
  value.values.get(index)
}

///|
pub fn pivot_function(value : PreparedPivot) -> @relation.AggregateFunction {
  value.function
}

///|
pub fn pivot_fill(value : PreparedPivot) -> PreparedPivotFill? {
  value.fill
}

///|
pub fn pivot_input_schema(value : PreparedPivot) -> @schema.Schema {
  value.input_schema
}

///|
pub fn pivot_output_schema(value : PreparedPivot) -> @schema.Schema {
  value.output_schema
}

///|
/// Checked aggregate result contract projected at the common lowering boundary.
/// Backends use this readonly view without reopening frontend operations.
pub fn pivot_result_contract(value : PreparedPivot) -> @contract.Contract {
  value.result_contract
}
