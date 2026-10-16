// Only typed boundary projections. The portable provider catalog owns every
// request/ref/recovery interpretation; this package performs no physical I/O.

///|
#export_name("sheetsRangeFailureJson")
pub fn sheets_range_failure_json(issue : @catalog.RangeFailure) -> String {
  let code = @catalog.range_failure_code(issue)
  let value : Json = match @catalog.range_failure_refusal(issue) {
    Some(issue) => { "code": code.to_json(), "refused": issue_json(issue) }
    None => { "code": code.to_json() }
  }
  value.stringify()
}

///|
#export_name("sheetsRangeCommandJson")
pub fn sheets_range_command_json(
  connector_id : String,
  columns : String,
  rows : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.range_command_json(connector_id, columns, rows, {
    max_bytes,
    max_nodes,
    max_depth,
    max_cells,
  })
}

///|
#export_name("sheetsRangeCatalogJson")
pub fn sheets_range_catalog_json(
  declaration : String,
  command : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.range_catalog_json(declaration, command, {
    max_bytes,
    max_nodes,
    max_depth,
    max_cells,
  })
}

///|
#export_name("sheetsRangeReferenceJson")
pub fn sheets_range_reference_json(
  origin : String,
  spreadsheet_id : String,
  sheet_id : Int,
  start_row : Int,
  end_row : Int,
  start_column : Int,
  end_column : Int,
  catalog_cid : String,
  binding_cid : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.range_reference(
    origin,
    spreadsheet_id,
    { sheet_id, start_row, end_row, start_column, end_column, },
    catalog_cid,
    binding_cid,
    { max_bytes, max_nodes, max_depth, max_cells, },
  ).map(value => value.stringify())
}

///|
#export_name("sheetsRangeBinding")
pub fn sheets_range_binding(
  configuration : String,
  command_cid : String,
  binding_cid : String,
  target : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> Result[@catalog.RangeBinding, @catalog.RangeFailure] {
  @catalog.admit_range_binding(
    configuration,
    command_cid,
    binding_cid,
    target,
    { max_bytes, max_nodes, max_depth, max_cells, },
  )
}

///|
#export_name("sheetsRangePrepare")
pub fn sheets_range_prepare(
  binding : @catalog.RangeBinding,
  value : String,
  target : String,
) -> Result[@catalog.RangeRequest, @catalog.RangeFailure] {
  @catalog.prepare_range_request(binding, value, target)
}

///|
#export_name("sheetsRangeTargetMatches")
pub fn sheets_range_target_matches(
  binding : @catalog.RangeBinding,
  target : String,
) -> Bool {
  @catalog.range_target_matches(binding, target)
}

///|
#export_name("sheetsRangeRequestJson")
pub fn sheets_range_request_json(
  binding : @catalog.RangeBinding,
  request : @catalog.RangeRequest,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.range_request_json(binding, request)
}

///|
#export_name("sheetsRangeRequestCid")
pub fn sheets_range_request_cid(
  binding : @catalog.RangeBinding,
  request : @catalog.RangeRequest,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.admit_range_request(binding, request).map(_ => {
    @catalog.range_request_identity(request)
  })
}

///|
#export_name("sheetsRangeRecoveryEntryJson")
pub fn sheets_range_recovery_entry_json(
  binding : @catalog.RangeBinding,
  effect_id : String,
) -> Result[String, @catalog.RangeFailure] {
  @catalog.range_recovery_entry(binding, effect_id)
}

///|
#export_name("sheetsRangeRecover")
pub fn sheets_range_recover(
  binding : @catalog.RangeBinding,
  effects : String,
  recovery : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_cells : Int,
) -> Result[Array[Array[@catalog.RangeRequest]], @catalog.RangeFailure] {
  @catalog.recover_range_requests(binding, effects, recovery, {
    max_bytes,
    max_nodes,
    max_depth,
    max_cells,
  })
}
