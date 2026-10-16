///|
/// SQL API response limits supplied by the existing acquisition caller. Provider
/// sizes are observations, never permission to increase these bounds.
pub(all) struct ResponseLimits {
  max_bytes : Int
  max_nodes : Int
  max_depth : Int
  max_columns : Int
  max_name_units : Int
  max_handle_units : Int
  max_partitions : Int
  max_rows : Int
  max_total_rows : Int64
}

///|
pub(all) enum ResponseIssue {
  InvalidLimits
  BudgetExceeded
  InvalidResponse
  InvalidHandle
  DuplicateColumn(String)
  InvalidColumn(String)
  ContractMismatch(String)
  UnsupportedColumn(String, String)
  InvalidPartition
  WrongRowWidth
  InvalidCell(String)
  ValueOutOfRange(String)
  ValueBeyondScale(String)
  ValueAdmission(String, @admitted.Issue)
} derive(Eq, Debug)

///|
pub struct Column {
  priv name : String
  priv native_type : String
  priv precision : Int?
  priv scale : Int?
  priv contract : @contract.Contract
}

///|
/// Immutable vendor observation material, not a Source grant or an Acquisition
/// completion. A future Site caller must retain the original request/use/body.
pub struct ResultSet {
  priv handle : String
  priv columns : Array[Column]
  priv partitions : Array[Int64]
  priv total_rows : Int64
  priv rows : Array[Array[@admitted.CheckedValue]]
  priv response_sha256 : String
}

///|
pub struct Partition {
  priv original : ResultSet
  priv ordinal : Int
  priv rows : Array[Array[@admitted.CheckedValue]]
  priv response_sha256 : String
}

///|
fn valid_limits(limits : ResponseLimits) -> Bool {
  limits.max_bytes > 0 &&
  limits.max_nodes > 0 &&
  limits.max_depth > 0 &&
  limits.max_columns > 0 &&
  limits.max_name_units > 0 &&
  limits.max_handle_units > 0 &&
  limits.max_partitions > 0 &&
  limits.max_rows >= 0 &&
  limits.max_total_rows >= 0L
}

///|
fn response_root(
  bytes : Bytes,
  limits : ResponseLimits,
) -> Result[@decode.Cursor, ResponseIssue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  if bytes.length() > limits.max_bytes {
    return Err(BudgetExceeded)
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
          InputLimit | NodeLimit | DepthLimit => BudgetExceeded
          _ => InvalidResponse
        },
      )
  }
  match
    @decode.admit(parsed, {
      max_nodes: limits.max_nodes,
      max_depth: limits.max_depth,
      max_string_bytes: limits.max_bytes,
      max_total_string_bytes: limits.max_bytes,
    }) {
    Ok(value) => Ok(value)
    Err(_) => Err(InvalidResponse)
  }
}

///|
fn required_text(object : @decode.ObjectView, key : String) -> String? {
  guard @decode.lookup(object, key) is Some(value) else { return None }
  match @decode.text(value) {
    Ok(text) => Some(text)
    Err(_) => None
  }
}

///|
fn nonnegative(object : @decode.ObjectView, key : String) -> Int64? {
  guard @decode.lookup(object, key) is Some(value) &&
    @decode.safe_integer(value) is Ok(number) &&
    number >= 0L else {
    return None
  }
  Some(number)
}

///|
fn valid_handle(value : String, limits : ResponseLimits) -> Bool {
  // Handles are opaque provider identities, not UUIDs inferred from examples.
  // A later physical caller must encode this exact value as one URL segment.
  value.length() > 0 && value.length() <= limits.max_handle_units
}

///|
fn project_column(
  cursor : @decode.Cursor,
  limits : ResponseLimits,
) -> Result[Column, ResponseIssue] {
  guard @decode.open_object(cursor) is Ok(object) &&
    required_text(object, "name") is Some(name) &&
    name.length() > 0 &&
    name.length() <= limits.max_name_units &&
    required_text(object, "type") is Some(native_type) &&
    @decode.lookup(object, "nullable") is Some(nullable_cursor) &&
    @decode.boolean(nullable_cursor) is Ok(nullable) else {
    return Err(InvalidResponse)
  }
  let mut precision = None
  let mut scale = None
  let contract = match native_type {
    "FIXED" | "fixed" => {
      guard nonnegative(object, "precision") is Some(p) &&
        p > 0L &&
        p <= 38L &&
        nonnegative(object, "scale") is Some(s) &&
        s <= p &&
        @contract.decimal_contract(p.to_int(), s.to_int(), nullable~)
        is Some(value) else {
        return Err(InvalidColumn(name))
      }
      precision = Some(p.to_int())
      scale = Some(s.to_int())
      value
    }
    "TEXT" | "text" => @contract.primitive(@contract.StringType, nullable~)
    "REAL" | "real" | "FLOAT" | "float" =>
      @contract.primitive(@contract.NumberType, nullable~)
    "BOOLEAN" | "boolean" =>
      @contract.primitive(@contract.BooleanType, nullable~)
    "VARIANT" | "variant" | "OBJECT" | "object" | "ARRAY" | "array" =>
      @contract.primitive(@contract.JsonType, nullable~)
    _ => return Err(UnsupportedColumn(name, native_type))
  }
  Ok({ name, native_type, precision, scale, contract, })
}

///|
pub fn project_result_set(
  bytes : Bytes,
  limits : ResponseLimits,
) -> Result[ResultSet, ResponseIssue] {
  project_result_set_original(bytes, limits, None)
}

///|
/// Metadata equality is checked before admitting raw provider cells against
/// the exact original input contracts supplied by the existing Row Owner.
/// This never re-labels an already checked value or issues Source authority.
pub fn project_result_set_with_contracts(
  bytes : Bytes,
  limits : ResponseLimits,
  contracts : Array[(String, @contract.Contract)],
  max_contract_pairs : Int,
) -> Result[ResultSet, ResponseIssue] {
  if max_contract_pairs <= 0 ||
    contracts.is_empty() ||
    contracts.length() > limits.max_columns {
    return Err(InvalidLimits)
  }
  project_result_set_original(
    bytes,
    limits,
    Some((contracts, max_contract_pairs)),
  )
}

///|
fn project_result_set_original(
  bytes : Bytes,
  limits : ResponseLimits,
  expected : (Array[(String, @contract.Contract)], Int)?,
) -> Result[ResultSet, ResponseIssue] {
  let root = match response_root(bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard @decode.open_object(root) is Ok(object) &&
    required_text(object, "statementHandle") is Some(handle) else {
    return Err(InvalidResponse)
  }
  if !valid_handle(handle, limits) {
    return Err(InvalidHandle)
  }
  guard required_text(object, "sqlState") is Some("00000") &&
    @decode.lookup(object, "resultSetMetaData") is Some(metadata_cursor) &&
    @decode.open_object(metadata_cursor) is Ok(metadata) &&
    required_text(metadata, "format") is Some("jsonv2") &&
    nonnegative(metadata, "numRows") is Some(total_rows) &&
    @decode.lookup(metadata, "rowType") is Some(columns_cursor) &&
    @decode.array_length(columns_cursor) is Some(count) &&
    count > 0 &&
    @decode.lookup(metadata, "partitionInfo") is Some(partitions_cursor) &&
    @decode.array_length(partitions_cursor) is Some(partition_count) &&
    partition_count > 0 else {
    return Err(InvalidResponse)
  }
  if count > limits.max_columns ||
    partition_count > limits.max_partitions ||
    total_rows > limits.max_total_rows {
    return Err(BudgetExceeded)
  }
  let columns : Array[Column] = []
  for index in 0..<count {
    let column = match
      project_column(@decode.element_at(columns_cursor, index).unwrap(), limits) {
      Ok(value) => value
      Err(issue) => return Err(issue)
    }
    if columns.any(existing => existing.name == column.name) {
      return Err(DuplicateColumn(column.name))
    }
    columns.push(column)
  }
  if expected is Some((contracts, max_pairs)) {
    if contracts.length() != columns.length() {
      return Err(ContractMismatch("column_count"))
    }
    for index, (name, contract) in contracts {
      let observed = columns[index]
      if observed.name != name {
        return Err(ContractMismatch(name))
      }
      let same = @contract.type_equal(observed.contract, contract, max_pairs) catch {
        _ => return Err(BudgetExceeded)
      }
      if !same {
        return Err(ContractMismatch(name))
      }
      // Only raw provider cells are admitted below, using this nominal input
      // contract. The metadata-created contract is never copied into it.
      columns[index] = { ..observed, contract, }
    }
  }
  let partitions = []
  let mut observed_rows = 0L
  for index in 0..<partition_count {
    guard @decode.open_object(
        @decode.element_at(partitions_cursor, index).unwrap(),
      )
      is Ok(part) &&
      nonnegative(part, "rowCount") is Some(rows) else {
      return Err(InvalidPartition)
    }
    if rows > total_rows - observed_rows {
      return Err(InvalidPartition)
    }
    observed_rows += rows
    partitions.push(rows)
  }
  if observed_rows != total_rows {
    return Err(InvalidPartition)
  }
  let rows = match project_rows(object, columns, partitions[0], limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    handle,
    columns,
    partitions,
    total_rows,
    rows,
    response_sha256: @sha.hex(bytes),
  })
}

///|
pub fn project_partition(
  bytes : Bytes,
  original : ResultSet,
  ordinal : Int,
  limits : ResponseLimits,
) -> Result[Partition, ResponseIssue] {
  if !valid_limits(limits) {
    return Err(InvalidLimits)
  }
  // Reusing the same immutable metadata does not bypass a later caller's
  // tighter ceiling. These limits remain observations, not a Source grant.
  if original.total_rows > limits.max_total_rows ||
    original.columns.length() > limits.max_columns ||
    original.partitions.length() > limits.max_partitions ||
    original.handle.length() > limits.max_handle_units ||
    original.columns.any(column => column.name.length() > limits.max_name_units) {
    return Err(BudgetExceeded)
  }
  if ordinal <= 0 || ordinal >= original.partitions.length() {
    return Err(InvalidPartition)
  }
  let root = match response_root(bytes, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  // Additional partitions contain data only. Never accept a replacement schema,
  // handle or success marker from a different statement through this seam.
  guard @decode.closed_object(root, ["data"]) is Ok(object) else {
    return Err(InvalidResponse)
  }
  let rows = match
    project_rows(object, original.columns, original.partitions[ordinal], limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ original, ordinal, rows, response_sha256: @sha.hex(bytes), })
}

///|
pub fn result_set_row_count(result : ResultSet) -> Int {
  result.rows.length()
}

///|
pub fn result_set_total_rows(result : ResultSet) -> Int64 {
  result.total_rows
}

///|
pub fn result_set_handle(result : ResultSet) -> String {
  result.handle
}

///|
pub fn result_set_column_count(result : ResultSet) -> Int {
  result.columns.length()
}

///|
pub fn result_set_column_name(result : ResultSet, index : Int) -> String? {
  result.columns.get(index).map(column => column.name)
}

///|
pub fn result_set_column_contract(
  result : ResultSet,
  index : Int,
) -> @contract.Contract? {
  result.columns.get(index).map(column => column.contract)
}

///|
pub fn result_set_response_sha256(result : ResultSet) -> String {
  result.response_sha256
}

///|
pub fn partition_matches_original(
  partition : Partition,
  original : ResultSet,
) -> Bool {
  physical_equal(partition.original, original)
}

///|
pub fn partition_row_count(partition : Partition) -> Int {
  partition.rows.length()
}

///|
pub fn result_set_cell(
  result : ResultSet,
  row : Int,
  column : Int,
) -> @admitted.CheckedValue? {
  match result.rows.get(row) {
    Some(cells) => cells.get(column)
    None => None
  }
}

///|
pub fn partition_cell(
  partition : Partition,
  row : Int,
  column : Int,
) -> @admitted.CheckedValue? {
  match partition.rows.get(row) {
    Some(cells) => cells.get(column)
    None => None
  }
}

///|
pub fn result_set_partition_count(result : ResultSet) -> Int {
  result.partitions.length()
}

///|
pub fn result_set_partition_rows(result : ResultSet, ordinal : Int) -> Int64? {
  result.partitions.get(ordinal)
}

///|
pub fn partition_ordinal(partition : Partition) -> Int {
  partition.ordinal
}

///|
pub fn partition_response_sha256(partition : Partition) -> String {
  partition.response_sha256
}
