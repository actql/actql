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

///|
#export_name("clientProgramKintoneCreatePreviewOutcome")
pub fn client_program_kintone_create_preview_outcome(
  mapping : @kintone_host.RecordCreateMapping,
  request : @kintone_catalog.RecordCreateRequest,
  response : @kintone_catalog.RecordCreateAcknowledgement,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
  max_value_bytes : Int,
  write_limits : @kintone_catalog.RecordWriteLimits,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_host.RecordCreatePreviewOutcome,
  @kintone_host.RecordCreateOutcomeIssue,
] {
  @kintone_host.project_record_create_preview_outcome(
    mapping, request, response, preview, member_index, row_index, max_value_bytes,
    write_limits, limits,
  )
}

///|
#export_name("clientProgramKintoneCreatePreviewOutcomeWire")
pub fn client_program_kintone_create_preview_outcome_wire(
  value : @kintone_host.RecordCreatePreviewOutcome,
) -> String {
  @kintone_host.record_create_preview_outcome_wire(value)
}

///|
#export_name("clientProgramKintoneCreatePreviewOutcomeRowCid")
pub fn client_program_kintone_create_preview_outcome_row_cid(
  value : @kintone_host.RecordCreatePreviewOutcome,
) -> String {
  @kintone_host.record_create_preview_outcome_row_cid(value)
}

///|
#export_name("clientProgramKintoneCreatePreviewOutcomeResponseSha256")
pub fn client_program_kintone_create_preview_outcome_response_sha256(
  value : @kintone_host.RecordCreatePreviewOutcome,
) -> String {
  @kintone_host.record_create_preview_outcome_response_sha256(value)
}

///|
#export_name("clientProgramKintoneCreatePreviewOutcomeMatches")
pub fn client_program_kintone_create_preview_outcome_matches(
  value : @kintone_host.RecordCreatePreviewOutcome,
  mapping : @kintone_host.RecordCreateMapping,
  request : @kintone_catalog.RecordCreateRequest,
  preview : @publication.EffectPreviewIdentity,
  member_index : Int,
  row_index : Int,
) -> Bool {
  @kintone_host.record_create_preview_outcome_matches(
    value, mapping, request, preview, member_index, row_index,
  )
}

///|
// Standard Row Effect already binds its original mapped row, Preview and claim.
// These are the existing Catalog's same-request provider DATA projections;
// no Preview/authority object is passed into the standard classify callback.
#export_name("clientProgramKintoneCreateEffectOutcome")
pub fn client_program_kintone_create_effect_outcome(
  request : @kintone_catalog.RecordCreateRequest,
  response : @kintone_catalog.RecordCreateAcknowledgement,
  limits : @kintone_catalog.RecordMutationLimits,
) -> Result[
  @kintone_catalog.RecordCreateEffectOutcome,
  @kintone_catalog.RecordMutationIssue,
] {
  @kintone_catalog.project_record_create_effect_outcome(
    request, response, limits,
  )
}

///|
#export_name("clientProgramKintoneCreateEffectOutcomeWire")
pub fn client_program_kintone_create_effect_outcome_wire(
  value : @kintone_catalog.RecordCreateEffectOutcome,
) -> String {
  @kintone_catalog.record_create_effect_outcome_wire(value)
}

///|
#export_name("clientProgramKintoneCreateEffectOutcomeResponseSha256")
pub fn client_program_kintone_create_effect_outcome_response_sha256(
  value : @kintone_catalog.RecordCreateEffectOutcome,
) -> String {
  @kintone_catalog.record_create_effect_outcome_response_sha256(value)
}

///|
#export_name("clientProgramKintoneCreateEffectOutcomeMatchesRequest")
pub fn client_program_kintone_create_effect_outcome_matches_request(
  value : @kintone_catalog.RecordCreateEffectOutcome,
  request : @kintone_catalog.RecordCreateRequest,
) -> Bool {
  @kintone_catalog.record_create_effect_outcome_matches_request(value, request)
}

///|
#export_name("clientProgramKintoneCreateRequestConstructionCapacity")
pub fn client_program_kintone_create_request_construction_capacity(
  mapping : @kintone_host.RecordCreateMapping,
  max_input_bytes : Int,
  write : @kintone_catalog.RecordWriteLimits,
  request : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_create_mapped_request_construction_capacity(
    mapping, max_input_bytes, write, request,
  )
}

///|
#export_name("clientProgramKintoneCreateFormRecheckConstructionCapacity")
pub fn client_program_kintone_create_form_recheck_construction_capacity(
  mapping : @kintone_host.RecordCreateMapping,
  limits : @kintone_catalog.FormFieldLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_create_mapped_form_recheck_construction_capacity(
    mapping, limits,
  )
}

///|
#export_name("clientProgramKintoneCreateResponseConstructionCapacity")
pub fn client_program_kintone_create_response_construction_capacity(
  mapping : @kintone_host.RecordCreateMapping,
  limits : @kintone_catalog.RecordMutationLimits,
) -> @execution.ExecutionCapacity? {
  @kintone_host.record_create_mapped_response_construction_capacity(
    mapping, limits,
  )
}
