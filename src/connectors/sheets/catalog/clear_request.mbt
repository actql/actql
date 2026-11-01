// The same Sheets provider Owner retains the original clear request and marker.

///|
pub struct ClearRangeBinding {
  original : RangeBinding
}

///|
pub struct ClearRangeRequest {
  binding : ClearRangeBinding
  body : String
  marker : String
  cid : String
}

///|
pub fn admit_clear_range_binding(
  configuration_wire : String,
  command_cid : String,
  binding_cid : String,
  target_wire : String,
  limits : Limits,
) -> Result[ClearRangeBinding, RangeFailure] {
  admit_range_binding(
    configuration_wire, command_cid, binding_cid, target_wire, limits,
  ).map(original => { original, })
}

///|
pub fn clear_range_construction_metadata(
  binding : ClearRangeBinding,
) -> RangeConstructionMetadata {
  range_construction_metadata(binding.original)
}

///|
pub fn clear_range_target_matches(
  binding : ClearRangeBinding,
  target_wire : String,
) -> Bool {
  range_target_matches(binding.original, target_wire)
}

///|
pub fn prepare_clear_range_request(
  binding : ClearRangeBinding,
  value_wire : String,
  target_wire : String,
  marker : String,
) -> Result[ClearRangeRequest, RangeFailure] {
  let original = binding.original
  if !clear_range_target_matches(binding, target_wire) {
    return Err(range_failure("SheetsRangeReferenceUnavailable"))
  }
  guard range_parse(value_wire, original.limits, "InvalidSheetsClearInput")
    is Ok(Object(input)) &&
    input.is_empty() else {
    return Err(range_failure("InvalidSheetsClearInput"))
  }
  let body = match
    clear_request(original.range, original.columns, marker, original.limits) {
    Ok(body) => body
    Err(issue) => return Err(range_contract_failure(issue))
  }
  let path = "/v4/spreadsheets/" + original.spreadsheet_id + ":batchUpdate"
  let cid = match
    clear_request_identity(original.origin, path, body, original.target_wire) {
    Ok(cid) => cid
    Err(issue) => return Err(issue)
  }
  Ok({ binding, body, marker, cid, })
}

///|
pub fn admit_clear_range_request(
  binding : ClearRangeBinding,
  request : ClearRangeRequest,
) -> Result[Unit, RangeFailure] {
  if binding.original.target_wire != request.binding.original.target_wire {
    Err(range_failure("SheetsRangeReferenceUnavailable"))
  } else if !physical_equal(binding, request.binding) {
    Err(range_failure("ForeignSheetsClearRequest"))
  } else {
    Ok(())
  }
}

///|
pub fn clear_range_request_identity(
  binding : ClearRangeBinding,
  request : ClearRangeRequest,
) -> Result[String, RangeFailure] {
  admit_clear_range_request(binding, request).map(_ => request.cid)
}

///|
pub fn clear_range_request_body(
  binding : ClearRangeBinding,
  request : ClearRangeRequest,
) -> Result[String, RangeFailure] {
  admit_clear_range_request(binding, request).map(_ => request.body)
}

///|
pub fn clear_range_request_json(
  binding : ClearRangeBinding,
  request : ClearRangeRequest,
) -> Result[String, RangeFailure] {
  match admit_clear_range_request(binding, request) {
    Ok(_) => ()
    Err(issue) => return Err(issue)
  }
  let original = binding.original
  range_canonical(
    {
      "origin": original.origin.to_json(),
      "path": ("/v4/spreadsheets/" + original.spreadsheet_id + ":batchUpdate").to_json(),
      "spreadsheetId": original.spreadsheet_id.to_json(),
      "sheetId": original.range.sheet_id.to_json(),
      "clearedRows": (original.range.end_row - original.range.start_row).to_json(),
      "value": {},
      "target": original.target,
      "marker": request.marker.to_json(),
      "requestCid": request.cid.to_json(),
    },
    original.limits,
  )
}

///|
pub fn clear_range_request_outcome(
  binding : ClearRangeBinding,
  request : ClearRangeRequest,
  status : Int,
  body : Bytes,
) -> Result[AppendOutcome, RangeFailure] {
  admit_clear_range_request(binding, request).map(_ => {
    let original = binding.original
    classify_clear(
      status,
      body,
      original.spreadsheet_id,
      original.range,
      request.marker,
      original.limits,
    )
  })
}

///|
fn clear_recovery_value(
  binding : ClearRangeBinding,
  effect_id : String,
  markers : Array[String],
) -> Result[Json, RangeFailure] {
  let original = binding.original
  if markers.length() > original.limits.max_cells {
    return Err(range_contract_failure(BudgetExceeded))
  }
  let seen : Map[String, Bool] = Map([])
  for marker in markers {
    if !check_clear_marker(marker) || seen.contains(marker) {
      return Err(range_failure("SheetsClearRecoveryMismatch"))
    }
    seen[marker] = true
  }
  let target = match
    range_parse(
      original.target_wire,
      original.limits,
      "SheetsClearRecoveryMismatch",
    ) {
    Ok(target) => target
    Err(issue) => return Err(issue)
  }
  Ok({
    "version": "actql-sheets-clear-recovery/0.1",
    "bindingCid": original.binding_cid.to_json(),
    "commandCid": original.command_cid.to_json(),
    "origin": original.origin.to_json(),
    "spreadsheetId": original.spreadsheet_id.to_json(),
    "range": range_json_value(original.range),
    "columns": range_columns_json(original.columns),
    "target": target,
    "effectId": effect_id.to_json(),
    "markers": Json::array(markers.map(marker => marker.to_json())),
  })
}

///|
pub fn clear_range_recovery_entry(
  binding : ClearRangeBinding,
  effect_id : String,
  requests : Array[ClearRangeRequest],
) -> Result[String, RangeFailure] {
  if requests.length() > binding.original.limits.max_cells {
    return Err(range_contract_failure(BudgetExceeded))
  }
  let markers = []
  for request in requests {
    match admit_clear_range_request(binding, request) {
      Ok(_) => markers.push(request.marker)
      Err(issue) => return Err(issue)
    }
  }
  let value = match clear_recovery_value(binding, effect_id, markers) {
    Ok(value) => value
    Err(issue) => return Err(issue)
  }
  let wire = match range_canonical(value, binding.original.limits) {
    Ok(wire) => wire
    Err(issue) => return Err(issue)
  }
  let cid = match range_content_cid(value, binding.original.limits) {
    Ok(cid) => cid
    Err(issue) => return Err(issue)
  }
  range_canonical(
    {
      "kind": "sheets-clear-request",
      "wire": wire.to_json(),
      "observationCid": cid.to_json(),
    },
    binding.original.limits,
  )
}

///|
pub fn recover_clear_range_requests(
  binding : ClearRangeBinding,
  effects_wire : String,
  recovery_wire : String,
  limits : Limits,
) -> Result[Array[Array[ClearRangeRequest]], RangeFailure] {
  guard range_parse(effects_wire, limits, "SheetsClearRecoveryMismatch")
    is Ok(Array(effects)) &&
    range_parse(recovery_wire, limits, "SheetsClearRecoveryMismatch")
    is Ok(Array(saved)) &&
    saved.length() == effects.length() &&
    effects.length() <= limits.max_cells else {
    return Err(range_failure("SheetsClearRecoveryMismatch"))
  }
  let by_index : Map[Int, Map[String, Json]] = Map([])
  for value in saved {
    guard value is Object(entry) &&
      range_integer(entry.get("memberIndex")) is Some(index) &&
      index < effects.length() &&
      !by_index.contains(index) &&
      entry.get("kind") == Some("sheets-clear-request".to_json()) else {
      return Err(range_failure("SheetsClearRecoveryMismatch"))
    }
    by_index[index] = entry
  }
  let output = []
  let mut total = 0
  for index, effect in effects {
    guard effect is Object(effect) &&
      effect.get("effect_id") is Some(String(effect_id)) &&
      effect.get("effect_kind") == Some("command".to_json()) &&
      effect.get("resolved_command_contract_cid") ==
      Some(binding.original.command_cid.to_json()) &&
      effect.get("changes") is Some(Array(changes)) &&
      by_index.get(index) is Some(entry) &&
      entry.get("wire") is Some(String(wire)) &&
      entry.get("observationCid") is Some(String(cid)) &&
      range_parse(wire, limits, "SheetsClearRecoveryMismatch")
      is Ok(Object(value)) &&
      value.get("markers") is Some(Array(marker_values)) &&
      marker_values.length() == changes.length() else {
      return Err(range_failure("SheetsClearRecoveryMismatch"))
    }
    if changes.length() > limits.max_cells - total {
      return Err(range_contract_failure(BudgetExceeded))
    }
    total = total + changes.length()
    let markers = []
    for value in marker_values {
      guard value is String(marker) else {
        return Err(range_failure("SheetsClearRecoveryMismatch"))
      }
      markers.push(marker)
    }
    guard clear_recovery_value(binding, effect_id, markers) is Ok(expected) &&
      range_canonical(expected, limits) == Ok(wire) &&
      range_content_cid(expected, limits) == Ok(cid) else {
      return Err(range_failure("SheetsClearRecoveryMismatch"))
    }
    let requests = []
    for row_index, change in changes {
      guard change is Object(change) &&
        change.get("intended_changes") is Some(Object(intended)) &&
        intended.get("value") is Some(value) &&
        change.get("target_row_identity") is Some(target) &&
        range_canonical(value, binding.original.limits) is Ok(value_wire) &&
        range_canonical(target, binding.original.limits) is Ok(target_wire) else {
        return Err(range_failure("SheetsClearRecoveryMismatch"))
      }
      match
        prepare_clear_range_request(
          binding,
          value_wire,
          target_wire,
          markers[row_index],
        ) {
        Ok(request) => requests.push(request)
        Err(issue) => return Err(issue)
      }
    }
    output.push(requests)
  }
  Ok(output)
}
