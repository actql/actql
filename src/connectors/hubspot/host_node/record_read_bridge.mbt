///|
#export_name("hubspotPrepareRecordRead")
pub fn hubspot_prepare_record_read(
  catalog : @catalog.PropertyCatalog,
  targets : Array[@catalog.RecordTarget],
  names : Array[String],
  max_rows : Int,
  max_properties : Int,
  max_columns : Int,
  max_request_bytes : Int,
  max_request_nodes : Int,
  max_request_depth : Int,
) -> Result[@catalog.RecordReadRequest, @catalog.RecordReadIssue] {
  @catalog.prepare_record_read_request(catalog, targets, names, {
    max_rows,
    max_properties,
    max_columns,
    max_request_bytes,
    max_request_nodes,
    max_request_depth,
  })
}

///|
#export_name("hubspotRecordReadBody")
pub fn hubspot_record_read_body(request : @catalog.RecordReadRequest) -> String {
  @catalog.record_read_request_body(request)
}

///|
#export_name("hubspotRecordReadObjectType")
pub fn hubspot_record_read_object_type(
  request : @catalog.RecordReadRequest,
) -> String {
  @catalog.record_read_request_object_type(request)
}

///|
#export_name("hubspotRecheckRecordReadRequest")
pub fn hubspot_recheck_record_read_request(
  request : @catalog.RecordReadRequest,
  current : @catalog.PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, @catalog.PropertyIssue] {
  @catalog.recheck_record_read_request(request, current, max_properties)
}

///|
#export_name("hubspotProjectRecordRead")
pub fn hubspot_project_record_read(
  request : @catalog.RecordReadRequest,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_rows : Int,
  max_columns : Int,
  max_cursor_units : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_output_bytes : Int,
  max_output_nodes : Int,
  max_output_depth : Int,
) -> Result[@catalog.RecordReadObservation, @catalog.RecordReadIssue] {
  @catalog.project_record_read_observation(
    request,
    bytes,
    {
      max_bytes,
      max_nodes,
      max_depth,
      max_rows,
      max_columns,
      max_cursor_units,
      max_value_nodes,
      max_value_text_bytes,
    },
    max_output_bytes,
    max_output_nodes,
    max_output_depth,
  )
}

///|
#export_name("hubspotRecordReadWire")
pub fn hubspot_record_read_wire(
  observation : @catalog.RecordReadObservation,
) -> String {
  @catalog.record_read_observation_wire(observation)
}

///|
#export_name("hubspotRecheckRecordRead")
pub fn hubspot_recheck_record_read(
  original : @catalog.RecordReadObservation,
  current : @catalog.RecordReadObservation,
  max_properties : Int,
  max_comparison_work : Int,
) -> Result[Unit, @catalog.RecordReadIssue] {
  @catalog.recheck_record_read_observation(
    original, current, max_properties, max_comparison_work,
  )
}
