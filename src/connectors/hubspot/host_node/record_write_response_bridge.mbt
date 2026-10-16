///|
#export_name("hubspotProjectRecordWriteSuccess")
pub fn hubspot_project_record_write_success(
  request : @catalog.RecordBatchRequest,
  status : Int,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
) -> Result[@catalog.RecordWriteResponse, @catalog.RecordWriteResponseIssue] {
  @catalog.project_record_write_success(
    request, status, bytes, max_bytes, max_nodes, max_depth, max_rows,
  )
}

///|
#export_name("hubspotRecordWriteResponseRows")
pub fn hubspot_record_write_response_rows(
  response : @catalog.RecordWriteResponse,
) -> Array[Array[String]] {
  let rows = []
  for index in 0..<@catalog.record_write_response_count(response) {
    let row = @catalog.record_write_response_result(response, index).unwrap()
    rows.push([row.id, if row.created { "created" } else { "updated" }])
  }
  rows
}

///|
#export_name("hubspotRecordWriteResponseSha256")
pub fn hubspot_record_write_response_sha256(
  response : @catalog.RecordWriteResponse,
) -> String {
  response.response_sha256
}
