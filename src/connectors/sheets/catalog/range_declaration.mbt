// Command declaration data stays ordinary Catalog data. Its interpretation,
// dependency references and canonical identities belong to the provider.

///|
fn range_contract_ref(value : Json) -> Json {
  guard value is Object(fields) else { return Json::null() }
  { "id": fields["id"], "version": fields["version"], "cid": fields["cid"] }
}

///|
fn range_contract(
  connector_id : String,
  kind : String,
  fields : Json,
  limits : Limits,
) -> Result[Json, RangeFailure] {
  range_named_contract(connector_id + ".sheets." + kind, kind, fields, limits)
}

///|
fn range_named_contract(
  id : String,
  kind : String,
  fields : Json,
  limits : Limits,
) -> Result[Json, RangeFailure] {
  let body : Json = {
    "schema": "actql.contract/0.1",
    "id": id.to_json(),
    "version": "sheets/0.1",
    "kind": kind.to_json(),
    "body": {
      "type": "object",
      "nullable": false,
      "additional_properties": false,
      "fields": fields,
    },
  }
  let cid = match range_content_cid(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard body is Object(fields) else {
    return Err(range_failure("InvalidSheetsRangeInput"))
  }
  fields["cid"] = cid.to_json()
  Ok(Json::object(fields))
}

///|
pub fn range_command_json(
  connector_id : String,
  columns_wire : String,
  range_wire : String,
  limits : Limits,
) -> Result[String, RangeFailure] {
  guard range_parse(columns_wire, limits, "InvalidSheetsRangeInput")
    is Ok(columns) &&
    range_columns(columns) is Some(columns) else {
    return Err(range_contract_failure(InvalidSchema))
  }
  guard range_parse(range_wire, limits, "InvalidSheetsRangeInput") is Ok(range) &&
    range_of_json(range) is Some(range) else {
    return Err(range_contract_failure(InvalidRange))
  }
  let row_count = range.end_row - range.start_row
  let fields : Map[String, Json] = Map([])
  for column in columns {
    fields[column.name] = {
      "type": match column.cell_type {
        Text => "string".to_json()
        Number => "number".to_json()
        Boolean => "boolean".to_json()
      },
      "nullable": false,
    }
  }
  let input_fields : Json = {
    "rows": {
      "type": "array",
      "nullable": false,
      "max_items": row_count.to_json(),
      "items": {
        "type": "object",
        "nullable": false,
        "additional_properties": false,
        "fields": Json::object(fields),
      },
    },
  }
  let input = match
    range_contract(connector_id, "command_input", input_fields, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output = match
    range_contract(
      connector_id,
      "command_output",
      {
        "spreadsheet_id": { "type": "string", "nullable": false },
        "sheet_id": { "type": "number", "nullable": false },
        "acknowledged_rows": { "type": "number", "nullable": false },
      },
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let command_id = "command:" + connector_id + ".sheets.update_range.v0"
  let body : Json = {
    "schema": "actql.command_contract/0.1",
    "command_id": command_id.to_json(),
    "connector_id": connector_id.to_json(),
    "version": "sheets/0.1",
    "target": { "resource_kind": "sheet_range", "cardinality": "single" },
    "input_schema": range_contract_ref(input),
    "output_schema": range_contract_ref(output),
    "input_contract": { "additional_properties": false, "fields": input_fields },
    "permissions": ["sheets:cells:update"],
    "preview": { "strength": "exact" },
    "outcome": "synchronous",
    "idempotency": { "support": "unsupported" },
    "reversibility": "unknown",
    "atomicity": "single_target",
  }
  let cid = match range_content_cid(body, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  guard body is Object(fields) else {
    return Err(range_failure("InvalidSheetsRangeInput"))
  }
  fields["contract_cid"] = cid.to_json()
  let command = Json::object(fields)
  let body = match range_canonical(command, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  range_canonical(
    {
      "command": command,
      "contracts": [input, output],
      "installed": {
        "resource": "range_target",
        "commandRef": command_id.to_json(),
        "commandCid": cid.to_json(),
        "body": body.to_json(),
      },
    },
    limits,
  )
}

///|
fn range_contract_cid(value : Json) -> String {
  match value {
    Object(fields) =>
      match fields.get("cid") {
        Some(String(value)) => value
        _ => ""
      }
    _ => ""
  }
}

///|
pub fn range_catalog_json(
  declared_wire : String,
  range_command_wire : String,
  limits : Limits,
) -> Result[String, RangeFailure] {
  guard range_parse(declared_wire, limits, "InvalidSheetsRangeInput")
    is Ok(Object(declared)) &&
    range_parse(range_command_wire, limits, "InvalidSheetsRangeInput")
    is Ok(Object(range_command)) &&
    declared.get("catalog") is Some(String(catalog_wire)) &&
    range_parse(catalog_wire, limits, "InvalidSheetsRangeInput")
    is Ok(Object(catalog)) &&
    declared.get("contracts") is Some(Array(original_contracts)) &&
    range_command.get("contracts") is Some(Array(additional)) &&
    range_command.get("command") is Some(command) else {
    return Err(range_failure("InvalidSheetsRangeInput"))
  }
  let contracts = []
  for original in original_contracts {
    guard original is String(wire) &&
      range_parse(wire, limits, "InvalidSheetsRangeInput") is Ok(value) else {
      return Err(range_failure("InvalidSheetsRangeInput"))
    }
    contracts.push(value)
  }
  for contract in additional {
    contracts.push(contract)
  }
  contracts.sort_by((left, right) => {
    @text.compare_utf16(range_contract_cid(left), range_contract_cid(right))
  })
  catalog.remove("catalog_cid") |> ignore
  catalog["commands"] = Json::array([command])
  catalog["contracts"] = Json::array(contracts)
  let cid = match range_content_cid(Json::object(catalog), limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  catalog["catalog_cid"] = cid.to_json()
  let catalog_wire = match range_canonical(Json::object(catalog), limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let contract_wires = []
  for contract in contracts {
    match range_canonical(contract, limits) {
      Ok(value) => contract_wires.push(value.to_json())
      Err(issue) => return Err(issue)
    }
  }
  declared["catalog_cid"] = cid.to_json()
  declared["catalog"] = catalog_wire.to_json()
  declared["contracts"] = Json::array(contract_wires)
  // Keep the complete SAME Command beside the Catalog for the existing
  // common Environment constructor. No Host-specific second recipe adds it.
  let command_wire = match range_canonical(command, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  declared["command_bodies"] = Json::array([command_wire.to_json()])
  range_canonical(Json::object(declared), limits)
}
