// Same-runtime original Form/Mapping and mapped-value/native-request seam.
// These DATA projections issue no provider use, Preview, claim or authority.

///|
#export_name("clientProgramKintonePrepareCreateMapping")
pub fn client_program_kintone_prepare_create_mapping(
  original : @kintone_host.RecordDeclaration,
  resource : String,
  sources : Array[@client_row_source_host.RowMappingSource],
  approval : String,
  limits : @client_row_source_host.RowDeclarationLimits,
) -> Result[
  @kintone_host.RecordCreateMapping,
  @client_row_source_host.RowMappingIssue,
] {
  @kintone_host.prepare_record_create_mapping(
    original, resource, sources, approval, limits,
  )
}

///|
#export_name("clientProgramKintoneCreateMappingBody")
pub fn client_program_kintone_create_mapping_body(
  mapping : @kintone_host.RecordCreateMapping,
) -> Result[String, @kintone_host.RecordCreateExecutionIssue] {
  if !@kintone_host.record_create_mapping_is_original(mapping) {
    return Err(MappingMismatch)
  }
  Ok(@kintone_host.record_create_mapping(mapping).body)
}

///|
#export_name("clientProgramKintoneCreateMappingMatchesDeclaration")
pub fn client_program_kintone_create_mapping_matches_declaration(
  mapping : @kintone_host.RecordCreateMapping,
  original : @kintone_host.RecordDeclaration,
) -> Bool {
  @kintone_host.record_create_mapping_matches_declaration(mapping, original)
}

///|
#export_name("clientProgramKintoneCreateMappingMatchesRequest")
pub fn client_program_kintone_create_mapping_matches_request(
  mapping : @kintone_host.RecordCreateMapping,
  request : @kintone_catalog.RecordCreateRequest,
) -> Bool {
  @kintone_host.record_create_mapping_matches_request(mapping, request)
}

///|
#export_name("clientProgramKintoneCreateExecutionRequest")
pub fn client_program_kintone_create_execution_request(
  mapping : @kintone_host.RecordCreateMapping,
  bytes : Bytes,
  max_input_bytes : Int,
  write_limits : @kintone_catalog.RecordWriteLimits,
  request_limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordCreateRequest,
  @kintone_host.RecordCreateExecutionIssue,
] {
  @kintone_host.prepare_record_create_execution_request(
    mapping, bytes, max_input_bytes, write_limits, request_limits,
  )
}

///|
#export_name("clientProgramKintoneCreateValuesJson")
pub fn client_program_kintone_create_values_json(
  request : @kintone_catalog.RecordCreateRequest,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[String, @kintone_catalog.RecordCreateJsonIssue] {
  @kintone_catalog.record_create_request_values_json(
    request, max_bytes, max_nodes, max_depth,
  )
}
