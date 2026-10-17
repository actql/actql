///|
/// Keep typed selectors and body documents in this provider runtime. These
/// exports prepare DATA only; the Host's original nominal claim authorizes I/O.
#export_name("hubspotPrepareRecordTarget")
pub fn hubspot_prepare_record_target(
  catalog : @catalog.PropertyCatalog,
  key : String,
  bytes : Bytes,
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
) -> Result[@catalog.RecordTarget, @catalog.RecordRequestIssue] {
  @catalog.prepare_record_target(catalog, key, bytes, {
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
#export_name("hubspotCreateRecordWriteInput")
pub fn hubspot_create_record_write_input(
  body : @catalog.WriteBody,
  trace_id : String,
) -> @catalog.RecordWriteInput {
  { body, target: None, trace_id, }
}

///|
#export_name("hubspotTargetedRecordWriteInput")
pub fn hubspot_targeted_record_write_input(
  body : @catalog.WriteBody,
  target : @catalog.RecordTarget,
  trace_id : String,
) -> @catalog.RecordWriteInput {
  { body, target: Some(target), trace_id, }
}

///|
#export_name("hubspotPrepareRecordBatch")
pub fn hubspot_prepare_record_batch(
  catalog : @catalog.PropertyCatalog,
  kind : Int,
  key : String,
  inputs : Array[@catalog.RecordWriteInput],
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
  @catalog.prepare_record_batch_request(catalog, operation, inputs, {
    max_rows,
    max_properties,
    max_trace_bytes,
    max_body_bytes,
    max_body_nodes,
    max_body_depth,
  })
}

///|
#export_name("hubspotRecordBatchBody")
pub fn hubspot_record_batch_body(
  request : @catalog.RecordBatchRequest,
) -> String {
  @catalog.record_batch_request_body(request)
}

///|
#export_name("hubspotRecordBatchObjectType")
pub fn hubspot_record_batch_object_type(
  request : @catalog.RecordBatchRequest,
) -> String {
  @catalog.record_batch_request_object_type(request)
}

///|
#export_name("hubspotRecordBatchEndpoint")
pub fn hubspot_record_batch_endpoint(
  request : @catalog.RecordBatchRequest,
) -> String {
  match request.operation {
    Create => "create"
    Update => "update"
    Upsert(_) => "upsert"
  }
}

///|
#export_name("hubspotRecordBatchCount")
pub fn hubspot_record_batch_count(request : @catalog.RecordBatchRequest) -> Int {
  @catalog.record_batch_request_count(request)
}

///|
#export_name("hubspotRecheckRecordBatch")
pub fn hubspot_recheck_record_batch(
  request : @catalog.RecordBatchRequest,
  current : @catalog.PropertyCatalog,
  max_properties : Int,
) -> Result[Unit, @catalog.PropertyIssue] {
  @catalog.recheck_record_batch_request(request, current, max_properties)
}
