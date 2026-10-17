// Typed projections of the same portable Sheets provider's original handles.

///|
#export_name("sheetsClearCommandJson")
pub fn sheets_clear_command_json(
  connector_id : String,
  columns : String,
  range : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.clear_command_json(connector_id, columns, range, {
    max_bytes,
    max_nodes,
    max_depth,
    max_cells,
  })
}

///|
#export_name("sheetsClearBinding")
pub fn sheets_clear_binding(
  configuration : String,
  command_cid : String,
  binding_cid : String,
  target : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> Result[@catalog.ClearRangeBinding, @catalog.RangeFailure] {
  @catalog.admit_clear_range_binding(
    configuration,
    command_cid,
    binding_cid,
    target,
    { max_bytes, max_nodes, max_depth, max_cells, },
  )
}

///|
#export_name("sheetsClearPrepare")
pub fn sheets_clear_prepare(
  binding : @catalog.ClearRangeBinding,
  value : String,
  target : String,
  marker : String,
) -> Result[@catalog.ClearRangeRequest, @catalog.RangeFailure] {
  @catalog.prepare_clear_range_request(binding, value, target, marker)
}

///|
#export_name("sheetsClearTargetMatches")
pub fn sheets_clear_target_matches(
  binding : @catalog.ClearRangeBinding,
  target : String,
) -> Bool {
  @catalog.clear_range_target_matches(binding, target)
}

///|
#export_name("sheetsClearRequestJson")
pub fn sheets_clear_request_json(
  binding : @catalog.ClearRangeBinding,
  request : @catalog.ClearRangeRequest,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.clear_range_request_json(binding, request)
}

///|
#export_name("sheetsClearRequestCid")
pub fn sheets_clear_request_cid(
  binding : @catalog.ClearRangeBinding,
  request : @catalog.ClearRangeRequest,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.clear_range_request_identity(binding, request)
}

///|
#export_name("sheetsClearRequestBody")
pub fn sheets_clear_request_body(
  binding : @catalog.ClearRangeBinding,
  request : @catalog.ClearRangeRequest,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.clear_range_request_body(binding, request)
}

///|
#export_name("sheetsClearOutcomeJson")
pub fn sheets_clear_outcome_json(
  binding : @catalog.ClearRangeBinding,
  request : @catalog.ClearRangeRequest,
  status : Int,
  body : Bytes,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.clear_range_request_outcome(binding, request, status, body).map(outcome => {
    let value : Json = match outcome {
      Applied => { "outcome": "Applied" }
      Unknown => { "outcome": "Unknown" }
    }
    value.stringify()
  })
}

///|
#export_name("sheetsClearRecoveryEntryJson")
pub fn sheets_clear_recovery_entry_json(
  binding : @catalog.ClearRangeBinding,
  effect_id : String,
  requests : Array[@catalog.ClearRangeRequest],
) -> Result[String, @catalog.RangeFailure] {
  @catalog.clear_range_recovery_entry(binding, effect_id, requests)
}

///|
#export_name("sheetsClearRecover")
pub fn sheets_clear_recover(
  binding : @catalog.ClearRangeBinding,
  effects : String,
  recovery : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> Result[Array[Array[@catalog.ClearRangeRequest]], @catalog.RangeFailure] {
  @catalog.recover_clear_range_requests(binding, effects, recovery, {
    max_bytes,
    max_nodes,
    max_depth,
    max_cells,
  })
}
