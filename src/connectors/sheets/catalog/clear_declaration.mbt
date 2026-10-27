// Ordinary Command declaration data; the existing Common owner admits it.

///|
pub fn clear_command_json(
  connector_id : String,
  columns_wire : String,
  range_wire : String,
  limits : Limits,
) -> Result[String, RangeFailure] {
  guard range_parse(columns_wire, limits, "InvalidSheetsClearInput")
    is Ok(columns) &&
    range_columns(columns) is Some(columns) &&
    range_parse(range_wire, limits, "InvalidSheetsClearInput") is Ok(range) &&
    range_of_json(range) is Some(range) else {
    return Err(range_contract_failure(InvalidSchema))
  }
  match check_range(range, columns, limits) {
    Ok(_) => ()
    Err(issue) => return Err(range_contract_failure(issue))
  }
  let input_fields : Json = Json::object(Map([]))
  let input = match
    range_contract(connector_id, "command_input", input_fields, limits) {
    Ok(input) => input
    Err(issue) => return Err(issue)
  }
  let output = match
    range_contract(
      connector_id,
      "command_output",
      {
        "spreadsheet_id": { "type": "string", "nullable": false },
        "sheet_id": { "type": "number", "nullable": false },
        "cleared_rows": { "type": "number", "nullable": false },
      },
      limits,
    ) {
    Ok(output) => output
    Err(issue) => return Err(issue)
  }
  let command_id = "command:" + connector_id + ".sheets.clear_range.v1"
  let body : Json = {
    "schema": "actql.command_contract/0.1",
    "command_id": command_id.to_json(),
    "connector_id": connector_id.to_json(),
    "version": "sheets/0.1",
    "target": { "resource_kind": "sheet_range", "cardinality": "single" },
    "input_schema": range_contract_ref(input),
    "output_schema": range_contract_ref(output),
    "input_contract": { "additional_properties": false, "fields": input_fields },
    "permissions": ["sheets:cells:clear"],
    "preview": { "strength": "exact" },
    "outcome": "synchronous",
    "idempotency": { "support": "unsupported" },
    "reversibility": "unknown",
    "atomicity": "single_target",
  }
  let cid = match range_content_cid(body, limits) {
    Ok(cid) => cid
    Err(issue) => return Err(issue)
  }
  guard body is Object(fields) else {
    return Err(range_failure("InvalidSheetsClearInput"))
  }
  fields["contract_cid"] = cid.to_json()
  let command = Json::object(fields)
  let body = match range_canonical(command, limits) {
    Ok(body) => body
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
