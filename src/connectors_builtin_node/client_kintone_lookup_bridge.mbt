// Private original kintone lookup DATA, consumed in the same normal runtime.
// No wire/ID/scalar reconstructs its original request or issues authority.

///|
#export_name("clientProgramKintoneLookupLimits")
pub fn client_program_kintone_lookup_limits(
  max_key_bytes : Int,
  max_columns : Int,
  max_comparison_work : Int,
  max_request_bytes : Int,
  max_request_nodes : Int,
  max_request_depth : Int,
) -> @kintone_catalog.RecordLookupLimits {
  {
    max_key_bytes,
    max_columns,
    max_comparison_work,
    max_request_bytes,
    max_request_nodes,
    max_request_depth,
  }
}

///|
#export_name("clientProgramKintoneLookupRequest")
pub fn client_program_kintone_lookup_request(
  catalog : @kintone_catalog.FormFieldCatalog,
  key : String,
  value : String,
  names : Array[String],
  limits : @kintone_catalog.RecordLookupLimits,
) -> Result[
  @kintone_catalog.RecordLookupRequest,
  @kintone_catalog.RecordLookupIssue,
] {
  @kintone_catalog.prepare_record_text_key_lookup(
    catalog, key, value, names, limits,
  )
}

///|
#export_name("clientProgramKintoneLookupApp")
pub fn client_program_kintone_lookup_app(
  request : @kintone_catalog.RecordLookupRequest,
) -> String {
  @kintone_catalog.record_lookup_request_app_id(request)
}

///|
#export_name("clientProgramKintoneLookupBody")
pub fn client_program_kintone_lookup_body(
  request : @kintone_catalog.RecordLookupRequest,
) -> String {
  @kintone_catalog.record_lookup_request_body(request)
}

///|
#export_name("clientProgramKintoneLookupRecheckForm")
pub fn client_program_kintone_lookup_recheck_form(
  request : @kintone_catalog.RecordLookupRequest,
  bytes : Bytes,
  limits : @kintone_catalog.FormFieldLimits,
) -> Result[Unit, @kintone_catalog.RecordLookupIssue] {
  @kintone_catalog.recheck_record_lookup_form(request, bytes, limits)
}

///|
#export_name("clientProgramKintoneLookupResponse")
pub fn client_program_kintone_lookup_response(
  request : @kintone_catalog.RecordLookupRequest,
  status : Int,
  bytes : Bytes,
  limits : @kintone_catalog.RecordPageLimits,
) -> Result[
  @kintone_catalog.RecordLookupObservation,
  @kintone_catalog.RecordLookupIssue,
] {
  @kintone_catalog.project_record_key_lookup(request, status, bytes, limits)
}

///|
#export_name("clientProgramKintoneLookupPage")
pub fn client_program_kintone_lookup_page(
  observed : @kintone_catalog.RecordLookupObservation,
) -> @kintone_catalog.OriginalRecordPage {
  @kintone_catalog.record_key_lookup_page(observed)
}

///|
#export_name("clientProgramKintoneLookupUsesRequest")
pub fn client_program_kintone_lookup_uses_request(
  observed : @kintone_catalog.RecordLookupObservation,
  request : @kintone_catalog.RecordLookupRequest,
) -> Bool {
  @kintone_catalog.record_key_lookup_uses_request(observed, request)
}

///|
#export_name("clientProgramKintoneLookupMatch")
pub fn client_program_kintone_lookup_match(
  original : @kintone_catalog.RecordLookupObservation,
  observed : @kintone_catalog.RecordLookupObservation,
) -> Result[Unit, @kintone_catalog.RecordLookupIssue] {
  @kintone_catalog.match_record_key_lookup(original, observed)
}
