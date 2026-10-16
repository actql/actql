///|
#export_name("hubspotPrepareRecordRequestMarker")
pub fn hubspot_prepare_record_request_marker(
  catalog : @catalog.PropertyCatalog,
  property : String,
  request_id : String,
  max_input_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_fields : Int,
  max_name_bytes : Int,
  max_value_nodes : Int,
  max_value_text_bytes : Int,
  max_comparison_work : Int,
  max_output_bytes : Int,
  max_output_nodes : Int,
  max_output_depth : Int,
) -> Result[@catalog.RecordRequestMarker, @catalog.RecordRequestIssue] {
  @catalog.prepare_record_request_marker(catalog, property, request_id, {
    max_input_bytes,
    max_nodes,
    max_depth,
    max_fields,
    max_name_bytes,
    max_value_nodes,
    max_value_text_bytes,
    max_comparison_work,
    max_output_bytes,
    max_output_nodes,
    max_output_depth,
  })
}

///|
#export_name("hubspotPrepareMarkedRecordBatch")
pub fn hubspot_prepare_marked_record_batch(
  catalog : @catalog.PropertyCatalog,
  kind : Int,
  key : String,
  inputs : Array[@catalog.RecordWriteInput],
  marker : @catalog.RecordRequestMarker,
  max_rows : Int,
  max_properties : Int,
  max_trace_bytes : Int,
  max_body_bytes : Int,
  max_body_nodes : Int,
  max_body_depth : Int,
) -> Result[@catalog.RecordBatchRequest, @catalog.RecordRequestIssue] {
  let operation = match (kind, key) {
    (0, "") => @catalog.Create
    (1, "id") => @catalog.Update
    (2, key) if !key.is_empty() && key != "id" => @catalog.Upsert(key)
    _ => return Err(@catalog.ForeignTargetKey)
  }
  @catalog.prepare_marked_record_batch_request(
    catalog,
    operation,
    inputs,
    marker,
    {
      max_rows,
      max_properties,
      max_trace_bytes,
      max_body_bytes,
      max_body_nodes,
      max_body_depth,
    },
  )
}

///|
#export_name("hubspotRecordBatchMarkerFields")
pub fn hubspot_record_batch_marker_fields(
  request : @catalog.RecordBatchRequest,
) -> Array[String]? {
  match @catalog.record_batch_request_marker(request) {
    Some(marker) => Some([marker.property, marker.request_id])
    None => None
  }
}

///|
#export_name("hubspotRecordBatchInputValueJson")
pub fn hubspot_record_batch_input_value_json(
  request : @catalog.RecordBatchRequest,
  index : Int,
) -> String? {
  match @catalog.record_batch_request_input(request, index) {
    Some(input) => Some(@catalog.write_body_value_json(input.body))
    None => None
  }
}

///|
#export_name("hubspotRecordBatchInputTargetJson")
pub fn hubspot_record_batch_input_target_json(
  request : @catalog.RecordBatchRequest,
  index : Int,
) -> String? {
  match @catalog.record_batch_request_input(request, index) {
    Some(input) => input.target.map(target => target.value_wire)
    None => None
  }
}
