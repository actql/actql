///|
pub(all) struct DescriptionLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_fields : Int
  max_name_bytes : Int
  max_schema_bytes : Int
}

///|
pub(all) enum DescriptionIssue {
  InvalidLimits
  DescriptionLimit
  InvalidTarget
  InvalidResponse
  ForeignTarget
  InvalidColumn(String)
  DuplicateColumn(String)
  InvalidDeclaredKey
  InvalidSelection
  UnknownColumn(String)
  UnsupportedColumn(String, String)
  InvalidContract(String)
} derive(Eq, Debug)

///|
/// Configured names are routing DATA, never an adopted installation or grant.
pub struct TableTarget {
  priv project : String
  priv dataset : String
  priv table : String
}

///|
pub struct ColumnDescription {
  priv name : String
  priv native_type : String
  priv mode : String
  priv precision : Int64?
  priv scale : Int64?
  priv max_length : Int64?
  priv collation : String?
  priv children : Array[ColumnDescription]
  priv contract : @contract.Contract?
}

///|
/// One bounded tables.get observation. The physical caller retains its actual
/// request/body loan and authority separately; a digest or etag grants nothing.
pub struct TableDescription {
  priv target : TableTarget
  priv etag : String
  priv native_type : String
  priv columns : Array[ColumnDescription]
  priv declared_key : Array[String]
  priv response_sha256 : String
}

///|
priv struct DescriptionBudget {
  mut fields : Int
  mut names : Int
}

///|
fn valid_limits(limits : DescriptionLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_fields > 0 &&
  limits.max_name_bytes > 0 &&
  limits.max_schema_bytes > 0
}

///|
fn name_size(value : String, maximum : Int) -> Int? {
  if value.is_empty() || value.contains("\u0000") {
    return None
  }
  match @scalar.admit_utf8_length(value, maximum) {
    Ok(size) => Some(size)
    Err(_) => None
  }
}

///|
pub fn table_target(
  project : String,
  dataset : String,
  table : String,
  max_name_bytes : Int,
) -> Result[TableTarget, DescriptionIssue] {
  if max_name_bytes <= 0 {
    return Err(InvalidLimits)
  }
  let mut remaining = max_name_bytes
  for value in [project, dataset, table] {
    guard name_size(value, remaining) is Some(size) else {
      return Err(InvalidTarget)
    }
    remaining -= size
  }
  Ok({ project, dataset, table, })
}

///|
fn required_text(object : @decode.ObjectView, key : String) -> String? {
  guard @decode.lookup(object, key) is Some(cursor) else { return None }
  match @decode.text(cursor) {
    Ok(value) => Some(value)
    Err(_) => None
  }
}

///|
fn optional_decimal(
  object : @decode.ObjectView,
  key : String,
  column : String,
) -> Result[Int64?, DescriptionIssue] {
  match @decode.lookup(object, key) {
    None => Ok(None)
    Some(cursor) =>
      match @decode.text(cursor) {
        Ok(text) =>
          match @scalar.read_decimal_int64(text) {
            Ok(number) if number >= 0L => Ok(Some(number))
            _ => Err(InvalidColumn(column))
          }
        Err(_) => Err(InvalidColumn(column))
      }
  }
}

///|
fn numeric_contract(
  native_type : String,
  precision : Int64?,
  scale : Int64?,
  nullable : Bool,
  column : String,
) -> Result[@contract.Contract?, DescriptionIssue] {
  let big = native_type == "BIGNUMERIC" || native_type == "BIGDECIMAL"
  let max_scale = if big { 38L } else { 9L }
  let integer_digits = if big { 38L } else { 29L }
  match (precision, scale) {
    (None, None) =>
      // Unparameterized BIGNUMERIC exceeds the existing Common decimal law.
      // Do not advertise a rounded float, string or decimal(38,38) substitute.
      Ok(if big { None } else { @contract.decimal_contract(38, 9, nullable~) })
    (Some(p), s) => {
      let s = s.unwrap_or(0L)
      if s > max_scale || p < s + 1L || p - s > integer_digits {
        return Err(InvalidColumn(column))
      }
      Ok(
        if p <= 38L {
          @contract.decimal_contract(p.to_int(), s.to_int(), nullable~)
        } else {
          None
        },
      )
    }
    (None, Some(_)) => Err(InvalidColumn(column))
  }
}

///|
fn describe_fields(
  cursor : @decode.Cursor,
  budget : DescriptionBudget,
  limits : DescriptionLimits,
  depth : Int,
) -> Result[Array[ColumnDescription], DescriptionIssue] {
  guard @decode.array_length(cursor) is Some(count) else {
    return Err(InvalidResponse)
  }
  if depth > limits.max_depth || count > budget.fields {
    return Err(DescriptionLimit)
  }
  let columns : Array[ColumnDescription] = []
  for index in 0..<count {
    let child = @decode.element_at(cursor, index).unwrap()
    let column = match describe_column(child, budget, limits, depth) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if columns.any(prior => prior.name == column.name) {
      return Err(DuplicateColumn(column.name))
    }
    columns.push(column)
  }
  Ok(columns)
}

///|
fn describe_column(
  cursor : @decode.Cursor,
  budget : DescriptionBudget,
  limits : DescriptionLimits,
  depth : Int,
) -> Result[ColumnDescription, DescriptionIssue] {
  if budget.fields == 0 {
    return Err(DescriptionLimit)
  }
  budget.fields -= 1
  guard @decode.open_object(cursor) is Ok(object) &&
    required_text(object, "name") is Some(name) &&
    required_text(object, "type") is Some(native_type) else {
    return Err(InvalidResponse)
  }
  for value in [name, native_type] {
    guard name_size(value, budget.names) is Some(size) else {
      return Err(DescriptionLimit)
    }
    budget.names -= size
  }
  let mode = match @decode.lookup(object, "mode") {
    None => "NULLABLE"
    Some(cursor) =>
      match @decode.text(cursor) {
        Ok(value) => value
        Err(_) => return Err(InvalidColumn(name))
      }
  }
  if !["NULLABLE", "REQUIRED", "REPEATED"].contains(mode) {
    return Err(InvalidColumn(name))
  }
  let numbers = []
  for key in ["precision", "scale", "maxLength"] {
    match optional_decimal(object, key, name) {
      Ok(value) => numbers.push(value)
      Err(issue) => return Err(issue)
    }
  }
  let precision = numbers[0]
  let scale = numbers[1]
  let max_length = numbers[2]
  let numeric = ["NUMERIC", "DECIMAL", "BIGNUMERIC", "BIGDECIMAL"].contains(
    native_type,
  )
  if (!numeric && (precision is Some(_) || scale is Some(_))) ||
    (
      max_length is Some(_) &&
      (max_length == Some(0L) || !["STRING", "BYTES"].contains(native_type))
    ) {
    return Err(InvalidColumn(name))
  }
  let collation = match @decode.lookup(object, "collation") {
    None => None
    Some(cursor) =>
      match @decode.text(cursor) {
        Ok(value) => {
          match @scalar.admit_utf8_length(value, budget.names) {
            Ok(size) => budget.names -= size
            Err(_) => return Err(DescriptionLimit)
          }
          if native_type != "STRING" {
            return Err(InvalidColumn(name))
          }
          Some(value)
        }
        Err(_) => return Err(InvalidColumn(name))
      }
  }
  let record = native_type == "RECORD" || native_type == "STRUCT"
  let children = match @decode.lookup(object, "fields") {
    Some(fields) if record =>
      match describe_fields(fields, budget, limits, depth + 1) {
        Ok(value) => value
        Err(issue) => return Err(issue)
      }
    None if !record => []
    _ => return Err(InvalidColumn(name))
  }
  let nullable = mode == "NULLABLE"
  let base = if numeric {
    match numeric_contract(native_type, precision, scale, nullable, name) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
  } else {
    match native_type {
      "STRING" => Some(@contract.primitive(@contract.StringType, nullable~))
      "FLOAT" | "FLOAT64" =>
        Some(@contract.primitive(@contract.NumberType, nullable~))
      "BOOLEAN" | "BOOL" =>
        Some(@contract.primitive(@contract.BooleanType, nullable~))
      "DATE" => Some(@contract.primitive(@contract.DateType, nullable~))
      "JSON" => Some(@contract.primitive(@contract.JsonType, nullable~))
      "RECORD" | "STRUCT" => {
        let fields : Array[(String, @contract.Contract)] = []
        for child in children {
          if child.contract is Some(contract) {
            fields.push((child.name, contract))
          }
        }
        if fields.length() != children.length() {
          None
        } else {
          match
            @contract.object_contract(
              fields,
              nullable~,
              max_fields=limits.max_fields,
              max_name_bytes=limits.max_name_bytes,
            ) {
            Ok(value) => Some(value)
            Err(_) => return Err(InvalidContract(name))
          }
        }
      }
      // Missing lossless Common carriers remain visible, including full
      // INT64, BYTES, TIME, DATETIME and microsecond TIMESTAMP. Read-only WKT
      // GEOGRAPHY/INTERVAL/RANGE need their real provider spelling first.
      _ => None
    }
  }
  let contract = if mode == "REPEATED" {
    match base {
      Some(value) =>
        @contract.array_contract(
          @contract.with_nullability(value, false),
          nullable=false,
        )
      None => None
    }
  } else {
    base
  }
  Ok({
    name,
    native_type,
    mode,
    precision,
    scale,
    max_length,
    collation,
    children,
    contract,
  })
}

///|
fn declared_key(
  object : @decode.ObjectView,
  columns : Array[ColumnDescription],
  limits : DescriptionLimits,
) -> Result[Array[String], DescriptionIssue] {
  guard @decode.lookup(object, "tableConstraints") is Some(cursor) else {
    return Ok([])
  }
  guard @decode.open_object(cursor) is Ok(constraints) else {
    return Err(InvalidDeclaredKey)
  }
  guard @decode.lookup(constraints, "primaryKey") is Some(cursor) else {
    return Ok([])
  }
  guard @decode.open_object(cursor) is Ok(key) &&
    @decode.lookup(key, "columns") is Some(cursor) &&
    @decode.array_length(cursor) is Some(count) &&
    count > 0 &&
    count <= limits.max_fields else {
    return Err(InvalidDeclaredKey)
  }
  let values : Array[String] = []
  for index in 0..<count {
    guard @decode.text(@decode.element_at(cursor, index).unwrap()) is Ok(name) &&
      columns.any(column => column.name == name) &&
      !values.contains(name) else {
      return Err(InvalidDeclaredKey)
    }
    values.push(name)
  }
  Ok(values)
}

///|
pub fn project_table_description(
  target : TableTarget,
  bytes : Bytes,
  limits : DescriptionLimits,
) -> Result[TableDescription, DescriptionIssue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(DescriptionLimit)
  }
  let parsed = match
    @source.parse_json_bytes_preserving(bytes, {
      max_input_bytes: limits.max_bytes,
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
    }) {
    Ok(value) => value
    Err(issue) =>
      return Err(
        match issue.issue {
          InputLimit | NodeLimit | DepthLimit => DescriptionLimit
          _ => InvalidResponse
        },
      )
  }
  let root = match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => value
    Err(_) => return Err(InvalidResponse)
  }
  guard @decode.open_object(root) is Ok(object) &&
    required_text(object, "kind") == Some("bigquery#table") &&
    @decode.lookup(object, "tableReference") is Some(reference) &&
    @decode.open_object(reference) is Ok(reference) else {
    return Err(InvalidResponse)
  }
  if required_text(reference, "projectId") != Some(target.project) ||
    required_text(reference, "datasetId") != Some(target.dataset) ||
    required_text(reference, "tableId") != Some(target.table) {
    return Err(ForeignTarget)
  }
  guard required_text(object, "etag") is Some(etag) &&
    required_text(object, "type") is Some(native_type) &&
    @decode.lookup(object, "schema") is Some(schema) &&
    @decode.open_object(schema) is Ok(schema) &&
    @decode.lookup(schema, "fields") is Some(fields) else {
    return Err(InvalidResponse)
  }
  let budget = { fields: limits.max_fields, names: limits.max_name_bytes, }
  for name in [target.project, target.dataset, target.table, etag, native_type] {
    guard name_size(name, budget.names) is Some(size) else {
      return Err(DescriptionLimit)
    }
    budget.names -= size
  }
  let columns = match describe_fields(fields, budget, limits, 1) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let declared_key = match declared_key(object, columns, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    target,
    etag,
    native_type,
    columns,
    declared_key,
    response_sha256: @sha.hex(bytes),
  })
}

///|
pub fn description_matches_target(
  value : TableDescription,
  target : TableTarget,
) -> Bool {
  physical_equal(value.target, target)
}

///|
pub fn description_column_count(value : TableDescription) -> Int {
  value.columns.length()
}

///|
pub fn description_column(
  value : TableDescription,
  index : Int,
) -> ColumnDescription? {
  value.columns.get(index)
}

///|
pub fn description_declared_key(value : TableDescription) -> Array[String] {
  value.declared_key.copy()
}

///|
pub fn description_original(
  value : TableDescription,
) -> (String, String, String) {
  (value.etag, value.native_type, value.response_sha256)
}

///|
pub fn column_name(value : ColumnDescription) -> String {
  value.name
}

///|
pub fn column_type(value : ColumnDescription) -> String {
  value.native_type
}

///|
pub fn column_mode(value : ColumnDescription) -> String {
  value.mode
}

///|
pub fn column_constraints(
  value : ColumnDescription,
) -> (Int64?, Int64?, Int64?, String?) {
  (value.precision, value.scale, value.max_length, value.collation)
}

///|
pub fn column_children(value : ColumnDescription) -> Array[ColumnDescription] {
  value.children.copy()
}

///|
pub fn column_contract(value : ColumnDescription) -> @contract.Contract? {
  value.contract
}
