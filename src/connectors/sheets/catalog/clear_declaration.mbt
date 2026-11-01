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
  let (input_id, output_id, command_id, operation) = range_declaration_names(
    connector_id, true,
  )
  let input = match
    range_named_contract(input_id, "command_input", input_fields, limits) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let output = match
    range_named_contract(
      output_id,
      "command_output",
      range_output_fields_document(true),
      limits,
    ) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let body = range_command_document(
    connector_id, command_id, input, output, input_fields, operation,
  )
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
    range_command_bundle_document(command, input, output, command_id, cid, body),
    limits,
  )
}
