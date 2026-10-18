///|
pub(all) struct DescriptionLimits {
  max_columns : Int
  max_name_bytes : Int
  max_schema_bytes : Int
  max_nodes : Int
  max_depth : Int
}

///|
pub(all) enum DescriptionIssue {
  InvalidLimits
  InvalidTarget
  DescriptionLimit
  WrongDescriptionShape
  IncompleteDescription
  ForeignPartition
  ForeignTarget
  InvalidColumn(String)
  DuplicateColumn(String)
  UnknownColumn(String)
  UnsupportedType(String, String)
  InvalidSelection
  InvalidSchema
} derive(Eq, Debug)

///|
/// Configured physical names, not a credential, Source grant or authority CID.
pub struct TableTarget {
  priv database : String
  priv schema : String
  priv table : String
}

///|
priv struct DescriptionColumn {
  name : String
  ordinal : Int64
  native_type : String
  nullable : Bool
  precision : Int64?
  scale : Int64?
  max_characters : Int64?
  contract : @contract.Contract?
}

///|
/// Retains the actual metadata responses. Current read authority and the
/// request/credential binding remain with the existing Host/Site Owner.
pub struct TableDescription {
  priv target : TableTarget
  priv original : @response.ResultSet
  priv partitions : Array[@response.Partition]
  priv columns : Array[DescriptionColumn]
}

///|
fn valid_description_limits(limits : DescriptionLimits) -> Bool {
  limits.max_columns > 0 &&
  limits.max_name_bytes > 0 &&
  limits.max_schema_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0
}

///|
fn valid_target_name(value : String, maximum : Int) -> Bool {
  !value.is_empty() &&
  !value.contains("\u0000") &&
  @scalar.admit_utf8_length(value, maximum) is Ok(_)
}

///|
pub fn table_target(
  database : String,
  schema : String,
  table : String,
  max_name_bytes : Int,
) -> Result[TableTarget, DescriptionIssue] {
  if max_name_bytes <= 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_name_bytes
  for name in [database, schema, table] {
    if !valid_target_name(name, remaining) {
      return Err(InvalidTarget)
    }
    remaining -= @scalar.admit_utf8_length(name, remaining).unwrap()
  }
  Ok({ database, schema, table, })
}

///|
fn text_cell(value : @admitted.CheckedValue) -> String? {
  match value.value {
    @admitted.Text(text) => Some(text)
    _ => None
  }
}

///|
fn integer_cell(value : @admitted.CheckedValue) -> Int64? {
  guard value.value is @admitted.Decimal(decimal) && decimal.scale == 0 else {
    return None
  }
  match @scalar.read_decimal_int64(decimal.coefficient) {
    Ok(number) if number >= 0L => Some(number)
    _ => None
  }
}

///|
fn optional_integer_cell(
  value : @admitted.CheckedValue,
) -> Result[Int64?, DescriptionIssue] {
  if value.value is @admitted.Null {
    Ok(None)
  } else {
    match integer_cell(value) {
      Some(value) => Ok(Some(value))
      None => Err(WrongDescriptionShape)
    }
  }
}

///|
fn description_contract(
  native_type : String,
  nullable : Bool,
  precision : Int64?,
  scale : Int64?,
) -> @contract.Contract? {
  match native_type {
    "NUMBER" | "DECIMAL" | "NUMERIC" =>
      match (precision, scale) {
        (Some(p), Some(s)) if p > 0L && p <= 38L && s <= p =>
          @contract.decimal_contract(p.to_int(), s.to_int(), nullable~)
        _ => None
      }
    "TEXT" | "VARCHAR" | "STRING" =>
      Some(@contract.primitive(@contract.StringType, nullable~))
    "FLOAT" | "REAL" | "DOUBLE" =>
      Some(@contract.primitive(@contract.NumberType, nullable~))
    "BOOLEAN" => Some(@contract.primitive(@contract.BooleanType, nullable~))
    "DATE" => Some(@contract.primitive(@contract.DateType, nullable~))
    "TIMESTAMP_LTZ" =>
      Some(@contract.primitive(@contract.TimestampType, nullable~))
    "VARIANT" | "OBJECT" | "ARRAY" =>
      Some(@contract.primitive(@contract.JsonType, nullable~))
    _ => None
  }
}

///|
fn description_column(
  cells : Array[@admitted.CheckedValue],
  target : TableTarget,
  remaining_names : Int,
) -> Result[(DescriptionColumn, Int), DescriptionIssue] {
  guard text_cell(cells[0]) == Some(target.database) &&
    text_cell(cells[1]) == Some(target.schema) &&
    text_cell(cells[2]) == Some(target.table) else {
    return Err(ForeignTarget)
  }
  guard text_cell(cells[3]) is Some(name) &&
    valid_target_name(name, remaining_names) &&
    integer_cell(cells[4]) is Some(ordinal) &&
    ordinal > 0L &&
    text_cell(cells[5]) is Some(nullability) &&
    (nullability == "YES" || nullability == "NO") &&
    text_cell(cells[6]) is Some(native_type) &&
    !native_type.is_empty() else {
    return Err(WrongDescriptionShape)
  }
  let names = @scalar.admit_utf8_length(name, remaining_names).unwrap()
  let type_bytes = match
    @scalar.admit_utf8_length(native_type, remaining_names - names) {
    Ok(size) => size
    Err(_) => return Err(DescriptionLimit)
  }
  let numbers = []
  for value in [cells[7], cells[8], cells[9]] {
    match optional_integer_cell(value) {
      Ok(value) => numbers.push(value)
      Err(issue) => return Err(issue)
    }
  }
  let nullable = nullability == "YES"
  let precision = numbers[0]
  let scale = numbers[1]
  let contract = description_contract(native_type, nullable, precision, scale)
  if ["NUMBER", "DECIMAL", "NUMERIC"].contains(native_type) && contract is None {
    return Err(InvalidColumn(name))
  }
  Ok(
    (
      {
        name,
        ordinal,
        native_type,
        nullable,
        precision,
        scale,
        max_characters: numbers[2],
        contract,
      },
      names + type_bytes,
    ),
  )
}

///|
pub fn project_table_description(
  target : TableTarget,
  original : @response.ResultSet,
  partitions : Array[@response.Partition],
  limits : DescriptionLimits,
) -> Result[TableDescription, DescriptionIssue] {
  if !valid_description_limits(limits) {
    return Err(InvalidLimits)
  }
  let headers = [
    "TABLE_CATALOG", "TABLE_SCHEMA", "TABLE_NAME", "COLUMN_NAME", "ORDINAL_POSITION",
    "IS_NULLABLE", "DATA_TYPE", "NUMERIC_PRECISION", "NUMERIC_SCALE", "CHARACTER_MAXIMUM_LENGTH",
  ]
  if @response.result_set_column_count(original) != headers.length() {
    return Err(WrongDescriptionShape)
  }
  for index, header in headers {
    if @response.result_set_column_name(original, index) != Some(header) {
      return Err(WrongDescriptionShape)
    }
  }
  if @response.result_set_total_rows(original) > limits.max_columns.to_int64() {
    return Err(DescriptionLimit)
  }
  if partitions.length() != @response.result_set_partition_count(original) - 1 {
    return Err(IncompleteDescription)
  }
  for index, part in partitions {
    if !@response.partition_matches_original(part, original) ||
      @response.partition_ordinal(part) != index + 1 {
      return Err(ForeignPartition)
    }
  }
  let mut names = limits.max_name_bytes
  for name in [target.database, target.schema, target.table] {
    match @scalar.admit_utf8_length(name, names) {
      Ok(size) => names -= size
      Err(_) => return Err(DescriptionLimit)
    }
  }
  let columns : Array[DescriptionColumn] = []
  for page in 0..<(partitions.length() + 1) {
    let count = if page == 0 {
      @response.result_set_row_count(original)
    } else {
      @response.partition_row_count(partitions[page - 1])
    }
    for row in 0..<count {
      let cells = []
      for column in 0..<headers.length() {
        let value = if page == 0 {
          @response.result_set_cell(original, row, column)
        } else {
          @response.partition_cell(partitions[page - 1], row, column)
        }
        guard value is Some(value) else { return Err(WrongDescriptionShape) }
        cells.push(value)
      }
      let (column, used) = match description_column(cells, target, names) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
      names -= used
      if columns.any(prior => prior.name == column.name) {
        return Err(DuplicateColumn(column.name))
      }
      if columns.last() is Some(prior) && prior.ordinal >= column.ordinal {
        return Err(InvalidColumn(column.name))
      }
      columns.push(column)
    }
  }
  if columns.is_empty() ||
    columns.length().to_int64() != @response.result_set_total_rows(original) {
    return Err(IncompleteDescription)
  }
  Ok({ target, original, partitions: partitions.copy(), columns, })
}

///|
pub fn description_matches_target(
  description : TableDescription,
  target : TableTarget,
) -> Bool {
  physical_equal(description.target, target)
}

///|
pub fn description_column_count(description : TableDescription) -> Int {
  description.columns.length()
}

///|
pub fn description_column_name(
  description : TableDescription,
  ordinal : Int,
) -> String? {
  description.columns.get(ordinal).map(column => column.name)
}

///|
pub fn description_column_type(
  description : TableDescription,
  ordinal : Int,
) -> String? {
  description.columns.get(ordinal).map(column => column.native_type)
}

///|
pub fn description_column_contract(
  description : TableDescription,
  ordinal : Int,
) -> @contract.Contract? {
  match description.columns.get(ordinal) {
    Some(column) => column.contract
    None => None
  }
}

///|
pub fn description_matches_response(
  description : TableDescription,
  original : @response.ResultSet,
) -> Bool {
  physical_equal(description.original, original)
}

///|
pub fn description_response_count(description : TableDescription) -> Int {
  description.partitions.length() + 1
}

///|
pub fn description_column_nullable(
  description : TableDescription,
  index : Int,
) -> Bool? {
  description.columns.get(index).map(column => column.nullable)
}

///|
pub fn description_column_numeric_properties(
  description : TableDescription,
  index : Int,
) -> (Int64?, Int64?)? {
  description.columns.get(index).map(column => (column.precision, column.scale))
}

///|
pub fn description_column_max_characters(
  description : TableDescription,
  index : Int,
) -> Int64? {
  match description.columns.get(index) {
    Some(column) => column.max_characters
    None => None
  }
}
