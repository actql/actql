// Private same-runtime projections of the original vendor Catalog. These
// prepare DATA; no opaque grant, current authority or Effect is reconstructed.

///|
#export_name("clientProgramKintoneProjectRecordPage")
pub fn client_program_kintone_project_record_page(
  bytes : Bytes,
  catalog : @kintone_catalog.FormFieldCatalog,
  names : Array[String],
  limits : @kintone_catalog.RecordPageLimits,
) -> Result[
  @kintone_catalog.OriginalRecordPage,
  @kintone_catalog.RecordPageIssue,
] {
  @kintone_catalog.project_record_page(bytes, catalog, names, limits)
}

///|
#export_name("clientProgramKintoneMutationLimits")
pub fn client_program_kintone_mutation_limits(
  max_records : Int,
  max_identity_bytes : Int,
  max_comparison_work : Int,
  max_output_bytes : Int,
  max_output_nodes : Int,
  max_output_depth : Int,
) -> @kintone_catalog.RecordMutationLimits {
  {
    max_records,
    max_identity_bytes,
    max_comparison_work,
    max_output_bytes,
    max_output_nodes,
    max_output_depth,
  }
}

///|
#export_name("clientProgramKintoneOriginalRecordTarget")
pub fn client_program_kintone_original_record_target(
  page : @kintone_catalog.OriginalRecordPage,
  index : Int,
  max_identity_bytes : Int,
) -> Result[
  @kintone_catalog.OriginalRecordTarget,
  @kintone_catalog.RecordMutationIssue,
] {
  @kintone_catalog.prepare_original_record_target(
    page, index, max_identity_bytes,
  )
}

///|
#export_name("clientProgramKintoneDeleteRequest")
pub fn client_program_kintone_delete_request(
  targets : Array[@kintone_catalog.OriginalRecordTarget],
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordDeleteRequest,
  @kintone_catalog.RecordMutationIssue,
] {
  @kintone_catalog.prepare_record_delete_request(targets, limits)
}

///|
#export_name("clientProgramKintoneDeleteApp")
pub fn client_program_kintone_delete_app(
  request : @kintone_catalog.RecordDeleteRequest,
) -> String {
  @kintone_catalog.record_delete_request_app_id(request)
}

///|
#export_name("clientProgramKintoneDeleteCount")
pub fn client_program_kintone_delete_count(
  request : @kintone_catalog.RecordDeleteRequest,
) -> Int {
  @kintone_catalog.record_delete_request_count(request)
}

///|
#export_name("clientProgramKintoneDeleteBody")
pub fn client_program_kintone_delete_body(
  request : @kintone_catalog.RecordDeleteRequest,
) -> String {
  @kintone_catalog.record_delete_request_body(request)
}

///|
#export_name("clientProgramKintoneDeleteObservationBody")
pub fn client_program_kintone_delete_observation_body(
  request : @kintone_catalog.RecordDeleteRequest,
  max_fields : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @kintone_catalog.RecordMutationIssue] {
  @kintone_catalog.record_delete_observation_body(
    request, max_fields, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramKintoneDeleteRecheckForm")
pub fn client_program_kintone_delete_recheck_form(
  request : @kintone_catalog.RecordDeleteRequest,
  bytes : Bytes,
  limits : @kintone_catalog.FormFieldLimits,
) -> Result[Unit, @kintone_catalog.RecordMutationIssue] {
  @kintone_catalog.recheck_record_delete_form(request, bytes, limits)
}

///|
#export_name("clientProgramKintoneDeleteRecheckRecords")
pub fn client_program_kintone_delete_recheck_records(
  request : @kintone_catalog.RecordDeleteRequest,
  bytes : Bytes,
  limits : @kintone_catalog.RecordPageLimits,
  max_fields : Int,
  max_comparison_work : Int,
) -> Result[Unit, @kintone_catalog.RecordMutationIssue] {
  @kintone_catalog.recheck_record_delete_records(
    request, bytes, limits, max_fields, max_comparison_work,
  )
}

///|
#export_name("clientProgramKintoneDeleteResponse")
pub fn client_program_kintone_delete_response(
  request : @kintone_catalog.RecordDeleteRequest,
  status : Int,
  bytes : Bytes,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @kintone_catalog.RecordDeleteAcknowledgement,
  @kintone_catalog.RecordMutationIssue,
] {
  @kintone_catalog.project_record_delete_acknowledgement(
    request, status, bytes, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramKintoneDeleteResponseRequest")
pub fn client_program_kintone_delete_response_request(
  response : @kintone_catalog.RecordDeleteAcknowledgement,
) -> @kintone_catalog.RecordDeleteRequest {
  @kintone_catalog.record_delete_acknowledgement_request(response)
}
