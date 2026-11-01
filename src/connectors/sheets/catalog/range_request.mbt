// The same provider-owned installation/request types are used by JS and
// Native. They issue no common approval, claim, send or retry permission.

///|
pub struct RangeBinding {
  origin : String
  spreadsheet_id : String
  range : GridRange
  columns : Array[Column]
  command_cid : String
  binding_cid : String
  target_wire : String
  limits : Limits
}

///|
pub struct RangeRequest {
  binding : RangeBinding
  body : String
  path : String
  value_wire : String
  cid : String
}

///|
/// The existing saved range-entry rejection bound. Constructor quotation
/// borrows this same guard; it is not a Run allowance or caller setting.
pub fn range_saved_recovery_wire_byte_limit() -> Int {
  100000
}

///|
fn range_integer(value : Json?) -> Int? {
  match value {
    Some(Number(value, ..)) if value >= 0 &&
      value <= 2147483647.0 &&
      value.trunc() == value => Some(value.to_int())
    _ => None
  }
}

///|
fn range_of_json(value : Json) -> GridRange? {
  guard value is Object(fields) &&
    fields.length() == 5 &&
    range_integer(fields.get("sheetId")) is Some(sheet_id) &&
    range_integer(fields.get("startRow")) is Some(start_row) &&
    range_integer(fields.get("endRow")) is Some(end_row) &&
    range_integer(fields.get("startColumn")) is Some(start_column) &&
    range_integer(fields.get("endColumn")) is Some(end_column) else {
    return None
  }
  Some({ sheet_id, start_row, end_row, start_column, end_column, })
}

///|
fn range_columns(value : Json) -> Array[Column]? {
  guard value is Array(items) else { return None }
  let columns = []
  for item in items {
    guard item is Object(fields) &&
      fields.length() == 3 &&
      fields.get("name") is Some(String(name)) &&
      fields.get("type") is Some(String(kind)) else {
      return None
    }
    let nullable = match fields.get("nullable") {
      Some(True) => true
      Some(False) => false
      _ => return None
    }
    let cell_type : CellType = match kind {
      "string" => Text
      "number" => Number
      "boolean" => Boolean
      _ => return None
    }
    columns.push({ name, cell_type, nullable, })
  }
  if check_columns(columns) {
    Some(columns)
  } else {
    None
  }
}

///|
fn range_columns_json(columns : Array[Column]) -> Json {
  Json::array(
    columns.map(column => {
      "name": column.name.to_json(),
      "type": match column.cell_type {
        Text => "string".to_json()
        Number => "number".to_json()
        Boolean => "boolean".to_json()
      },
      "nullable": column.nullable.to_json(),
    }),
  )
}

///|
pub fn admit_range_binding(
  configuration_wire : String,
  command_cid : String,
  binding_cid : String,
  target_wire : String,
  limits : Limits,
) -> Result[RangeBinding, RangeFailure] {
  let configuration = match
    range_parse(configuration_wire, limits, "InvalidSheetsRangeInput") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard configuration is Object(configuration) &&
    configuration.length() == 4 &&
    configuration.get("origin") is Some(String(origin)) &&
    configuration.get("spreadsheetId") is Some(String(spreadsheet_id)) &&
    configuration.get("range") is Some(range) &&
    range_of_json(range) is Some(range) &&
    configuration.get("columns") is Some(columns) &&
    range_columns(columns) is Some(columns) else {
    return Err(range_contract_failure(InvalidSchema))
  }
  match check_range(range, columns, limits) {
    Ok(_) => ()
    Err(issue) => return Err(range_contract_failure(issue))
  }
  if spreadsheet_id.is_empty() ||
    spreadsheet_id.length() > 128 ||
    !spreadsheet_id
    .iter()
    .all(character => {
      (character >= 'A' && character <= 'Z') ||
      (character >= 'a' && character <= 'z') ||
      (character >= '0' && character <= '9') ||
      character == '_' ||
      character == '-'
    }) {
    return Err(range_failure("InvalidSheetsSpreadsheetId"))
  }
  let target = match
    range_parse(target_wire, limits, "SheetsRangeReferenceUnavailable") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let target_wire = match range_canonical(target, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    origin,
    spreadsheet_id,
    range,
    columns,
    command_cid,
    binding_cid,
    target_wire,
    limits,
  })
}

///|
/// Immutable constructor metadata from this SAME admitted binding. These are
/// representation inputs, not a new target admission or physical authority.
pub(all) struct RangeConstructionMetadata {
  columns : Int
  rows : Int
  name_units : Int64
  schema_bytes : Int64
  identity_units : Int64
  origin_units : Int
  spreadsheet_units : Int
  target_units : Int
  range : GridRange
  limits : Limits
}

///|
pub fn range_construction_metadata(
  binding : RangeBinding,
) -> RangeConstructionMetadata {
  let mut name_units = 0L
  for column in binding.columns {
    name_units += column.name.length().to_int64()
  }
  {
    columns: binding.columns.length(),
    rows: binding.range.end_row - binding.range.start_row,
    name_units,
    // The actual Column document owns the fixed spelling. Boolean is the
    // longest existing type label; a quoted name needs <=6 units per UTF16.
    schema_bytes: 2L +
    binding.columns.length().to_int64() *
    (
      range_columns_json([{ name: "", cell_type: Boolean, nullable: false, }])
      .stringify()
      .length()
      .to_int64() +
      1L
    ) +
    6L * name_units,
    identity_units: binding.command_cid.length().to_int64() +
    binding.binding_cid.length().to_int64(),
    origin_units: binding.origin.length(),
    spreadsheet_units: binding.spreadsheet_id.length(),
    target_units: binding.target_wire.length(),
    range: binding.range,
    limits: binding.limits,
  }
}

///|
pub fn range_target_matches(
  binding : RangeBinding,
  target_wire : String,
) -> Bool {
  // The original binding admitted and canonicalized this immutable DATA.
  // Exact spelling reuses that completed fact; changed/noncanonical inputs
  // retain their full old admission path. Permission/current and original
  // request ownership are separate boundaries and are not reused here.
  if target_wire == binding.target_wire {
    return true
  }
  guard range_parse(
      target_wire,
      binding.limits,
      "SheetsRangeReferenceUnavailable",
    )
    is Ok(target) &&
    range_canonical(target, binding.limits) is Ok(wire) else {
    return false
  }
  wire == binding.target_wire
}

///|
pub fn prepare_range_request(
  binding : RangeBinding,
  value_wire : String,
  target_wire : String,
) -> Result[RangeRequest, RangeFailure] {
  if !range_target_matches(binding, target_wire) {
    return Err(range_failure("SheetsRangeReferenceUnavailable"))
  }
  let value = match
    range_parse(value_wire, binding.limits, "InvalidSheetsRangeInput") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard value is Object(input) && input.length() == 1 && input.contains("rows") else {
    return Err(range_failure("InvalidSheetsRangeInput"))
  }
  guard input.get("rows") is Some(Array(items)) else {
    return Err(range_contract_failure(InvalidSchema))
  }
  let rows = []
  for item in items {
    guard item is Object(fields) && fields.length() == binding.columns.length() else {
      return Err(range_contract_failure(InvalidSchema))
    }
    let row = []
    for column in binding.columns {
      guard fields.get(column.name) is Some(value) else {
        return Err(range_contract_failure(InvalidSchema))
      }
      match value {
        Null | String(_) | Number(_, ..) | True | False => row.push(value)
        _ =>
          return Err(range_contract_failure(UnrepresentableWrite(column.name)))
      }
    }
    rows.push(row)
  }
  let body = match
    update_request(binding.range, binding.columns, rows, binding.limits) {
    Ok(body) => body
    Err(issue) => return Err(range_contract_failure(issue))
  }
  let path = "/v4/spreadsheets/" + binding.spreadsheet_id + ":batchUpdate"
  let cid = match
    range_request_cid(binding.origin, path, body, binding.target_wire) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let value_wire = match range_canonical(value, binding.limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({ binding, body, path, value_wire, cid, })
}

///|
pub fn admit_range_request(
  binding : RangeBinding,
  request : RangeRequest,
) -> Result[Unit, RangeFailure] {
  if binding.target_wire != request.binding.target_wire {
    Err(range_failure("SheetsRangeReferenceUnavailable"))
  } else if !physical_equal(binding, request.binding) {
    Err(range_failure("ForeignSheetsRangeRequest"))
  } else {
    Ok(())
  }
}

///|
pub fn range_request_json(
  binding : RangeBinding,
  request : RangeRequest,
) -> Result[String, RangeFailure] {
  match admit_range_request(binding, request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let value = match
    range_parse(request.value_wire, binding.limits, "InvalidSheetsRangeInput") {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let target = match
    range_parse(
      binding.target_wire,
      binding.limits,
      "SheetsRangeReferenceUnavailable",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  range_canonical(
    {
      "origin": binding.origin.to_json(),
      "path": request.path.to_json(),
      "spreadsheetId": binding.spreadsheet_id.to_json(),
      "sheetId": binding.range.sheet_id.to_json(),
      "acknowledgedRows": (binding.range.end_row - binding.range.start_row).to_json(),
      "value": value,
      "target": target,
      "requestCid": request.cid.to_json(),
    },
    binding.limits,
  )
}

///|
pub fn range_request_identity(request : RangeRequest) -> String {
  request.cid
}

///|
pub fn range_request_body(request : RangeRequest) -> String {
  request.body
}

///|
pub fn range_request_body_for(
  binding : RangeBinding,
  request : RangeRequest,
) -> Result[String, RangeFailure] {
  admit_range_request(binding, request).map(_ => request.body)
}

///|
fn range_recovery_value(
  binding : RangeBinding,
  effect_id : String,
) -> Result[Json, RangeFailure] {
  let target = match
    range_parse(
      binding.target_wire,
      binding.limits,
      "SheetsRangeRecoveryMismatch",
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  Ok({
    "version": "actql-sheets-range-recovery/0.1",
    "bindingCid": binding.binding_cid.to_json(),
    "commandCid": binding.command_cid.to_json(),
    "origin": binding.origin.to_json(),
    "spreadsheetId": binding.spreadsheet_id.to_json(),
    "range": range_json_value(binding.range),
    "columns": range_columns_json(binding.columns),
    "target": target,
    "effectId": effect_id.to_json(),
  })
}

///|
pub fn range_recovery_entry(
  binding : RangeBinding,
  effect_id : String,
) -> Result[String, RangeFailure] {
  let value = match range_recovery_value(binding, effect_id) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire = match range_canonical(value, binding.limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let cid = match range_content_cid(value, binding.limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  range_canonical(
    {
      "kind": "sheets-range-request",
      "wire": wire.to_json(),
      "observationCid": cid.to_json(),
    },
    binding.limits,
  )
}

///|
pub fn recover_range_requests(
  binding : RangeBinding,
  effects_wire : String,
  recovery_wire : String,
  limits : Limits,
) -> Result[Array[Array[RangeRequest]], RangeFailure] {
  guard range_parse(effects_wire, limits, "SheetsRangeRecoveryMismatch")
    is Ok(Array(effects)) &&
    range_parse(recovery_wire, limits, "SheetsRangeRecoveryMismatch")
    is Ok(Array(saved)) &&
    saved.length() == effects.length() else {
    return Err(range_failure("SheetsRangeRecoveryMismatch"))
  }
  let output = []
  for index, effect in effects {
    guard effect is Object(effect_fields) &&
      effect_fields.get("effect_id") is Some(String(effect_id)) &&
      effect_fields.get("effect_kind") == Some("command".to_json()) &&
      effect_fields.get("resolved_command_contract_cid") ==
      Some(binding.command_cid.to_json()) &&
      effect_fields.get("changes") is Some(Array(changes)) else {
      return Err(range_failure("SheetsRangeRecoveryMismatch"))
    }
    let entries = saved.filter(entry => {
      guard entry is Object(entry) else { return false }
      range_integer(entry.get("memberIndex")) == Some(index) &&
      entry.get("kind") == Some("sheets-range-request".to_json())
    })
    guard entries.length() == 1 &&
      entries[0] is Object(entry) &&
      entry.get("wire") is Some(String(wire)) &&
      @utf8.encode(wire).length() <= range_saved_recovery_wire_byte_limit() &&
      entry.get("observationCid") is Some(String(cid)) &&
      // Exact equality with the original constructor's canonical metadata
      // establishes the supplied wire as that SAME complete document. Do not
      // parse/canonicalize/hash an unrelated supplied tree before rejecting it.
      range_recovery_value(binding, effect_id) is Ok(expected) &&
      range_canonical(expected, limits) == Ok(wire) &&
      range_content_cid(expected, limits) == Ok(cid) else {
      return Err(range_failure("SheetsRangeRecoveryMismatch"))
    }
    let requests = []
    for change in changes {
      guard change is Object(change) &&
        change.get("intended_changes") is Some(Object(intended)) &&
        intended.get("value") is Some(value) &&
        change.get("target_row_identity") is Some(target) &&
        range_canonical(value, binding.limits) is Ok(value_wire) &&
        range_canonical(target, binding.limits) is Ok(target_wire) else {
        return Err(range_failure("SheetsRangeRecoveryMismatch"))
      }
      match prepare_range_request(binding, value_wire, target_wire) {
        Ok(request) => requests.push(request)
        Err(issue) => return Err(issue)
      }
    }
    output.push(requests)
  }
  Ok(output)
}
