///|
/// Borrow the original completed prefix under the caller's already selected
/// typed export limits; this issues no Source, Request or physical receipt.
#export_name("clientProgramKeyedLookupPrepareLeftIdentity")
pub fn client_program_keyed_lookup_prepare_left_identity(
  lookup : @publication_host.ClientKeyedLookupInput,
  limits : @publication_host.PublicationOutputExportLimits,
  max_work : Int,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.prepare_client_keyed_captured_left_identity(
    lookup, limits, max_work,
  ).map(_ => ())
}

///|
#export_name("clientProgramKeyedLookupBindQuerySourceMetadata")
pub fn client_program_keyed_lookup_bind_query_source_metadata(
  lookup : @publication_host.ClientKeyedLookupInput,
  index : Int,
  requirement : @planning.QueryRequirement,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  request : @publication_host.ClientRequestIdentity,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.bind_client_keyed_query_source_metadata(
    lookup, index, requirement, identity, logical, observation, request, retention,
    max_bytes, max_nodes, max_depth,
  ).map(_ => ())
}

///|
#export_name("clientProgramKeyedLookupBindWholeSourceMetadata")
pub fn client_program_keyed_lookup_bind_whole_source_metadata(
  lookup : @publication_host.ClientKeyedLookupInput,
  index : Int,
  identity : @query.CapturedSourceRelationIdentity,
  logical : @publication.RunEvidenceValue,
  observation : @publication.RunEvidenceValue,
  request : @publication_host.ClientRequestIdentity,
  retention : @publication.PublicationContract,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.bind_client_keyed_whole_source_metadata(
    lookup, index, identity, logical, observation, request, retention, max_bytes,
    max_nodes, max_depth,
  ).map(_ => ())
}

///|
#export_name("clientProgramKeyedLookupPrepareLeftRelation")
pub fn client_program_keyed_lookup_prepare_left_relation(
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientRequestIdentity,
  retention : @publication.PublicationContract,
  issuer : String,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.prepare_client_keyed_native_left_relation(
    lookup, request, retention, issuer, max_bytes, max_nodes, max_depth,
  ).map(_ => ())
}

///|
#export_name("clientProgramKeyedLookupPrepareActivation")
pub fn client_program_keyed_lookup_prepare_activation(
  lookup : @publication_host.ClientKeyedLookupInput,
  keyed_request : @publication_host.ClientKeyedRequest,
  request : @publication_host.ClientRequestIdentity,
  issuer : String,
  recorded_at : String,
  now_ms : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientKeyedNativeActivation,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.prepare_client_keyed_native_activation(
    lookup, keyed_request, request, issuer, recorded_at, now_ms, max_bytes, max_nodes,
    max_depth,
  )
}

///|
#export_name("clientProgramKeyedLookupDeclaredFileActivationRecord")
pub fn client_program_keyed_lookup_declared_file_activation_record(
  original : @publication_host.ClientKeyedNativeActivation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
  max_bytes : Int,
) -> Result[String, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.prepare_client_keyed_declared_file_activation_record(
    original, request, compiled, definition, graph, max_bytes,
  )
}

///|
/// Original typed fields for the existing Journal's key and ordered CAS.
/// This projection is DATA; only the checked record constructor can match it.
#export_name("clientProgramKeyedLookupActivationFields")
pub fn client_program_keyed_lookup_activation_fields(
  original : @publication_host.ClientKeyedNativeActivation,
) -> (String, String, Int, Int) {
  (
    @publication.publication_contract_identity(original.batch),
    @publication.publication_contract_identity(original.slot),
    original.batch_index,
    original.batch_count,
  )
}

///|
#export_name("clientProgramKeyedLookupActivationMatches")
pub fn client_program_keyed_lookup_activation_matches(
  original : @publication_host.ClientKeyedNativeActivation,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
) -> Bool {
  @publication_host.client_keyed_native_activation_matches(
    original, request, compiled, definition, graph,
  )
}

///|
#export_name("clientProgramKeyedLookupPrepareRetention")
pub fn client_program_keyed_lookup_prepare_retention(
  lookup : @publication_host.ClientKeyedLookupInput,
  request : @publication_host.ClientRequestIdentity,
  retention_contract : String,
  available_until : String,
  delete_by : String,
  metadata_delete_by : String,
  metadata_policy : String,
  clock_contract : String,
  max_bytes : Int,
) -> Result[
  @publication.PublicationContract,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.prepare_client_keyed_declared_file_retention(
    lookup, request, retention_contract, available_until, delete_by, metadata_delete_by,
    metadata_policy, clock_contract, max_bytes,
  )
}

///|
#export_name("clientProgramKeyedLookupStartDeclaredFileRequestPlan")
pub fn client_program_keyed_lookup_start_declared_file_request_plan(
  lookup : @publication_host.ClientKeyedLookupInput,
  at : String,
  now_ms : Int64,
  issuer : String,
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.start_client_keyed_declared_file_request_plan(
    lookup, at, now_ms, issuer,
  )
}

///|
#export_name("clientProgramKeyedLookupDeclaredFilePageRecord")
pub fn client_program_keyed_lookup_declared_file_page_record(
  page : @publication_host.ClientKeyedNativeCapturedPage,
  keyed_request : @publication_host.ClientKeyedRequest,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
  max_bytes : Int,
) -> Result[String, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.prepare_client_keyed_declared_file_page_record(
    page, keyed_request, request, compiled, definition, graph, max_bytes,
  )
}

///|
#export_name("clientProgramKeyedLookupCapturedPageMatches")
pub fn client_program_keyed_lookup_captured_page_matches(
  page : @publication_host.ClientKeyedNativeCapturedPage,
  keyed_request : @publication_host.ClientKeyedRequest,
  request : @publication_host.ClientRequestIdentity,
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  graph : @publication_host.ClientInferPlanGraph,
) -> Bool {
  @publication_host.client_keyed_native_captured_page_matches(
    page, keyed_request, request, compiled, definition, graph,
  )
}

///|
#export_name("clientProgramKeyedLookupCapturedPageFields")
pub fn client_program_keyed_lookup_captured_page_fields(
  page : @publication_host.ClientKeyedNativeCapturedPage,
) -> (String, String, String, Int) {
  (
    page.batch_plan_cid,
    page.call_slot_cid,
    page.activation_cid,
    page.batch_index,
  )
}

///|
#export_name("clientProgramKeyedLookupRawStoreBinding")
pub fn client_program_keyed_lookup_raw_store_binding(
  raw : @publication_host.ClientKeyedNativeRawResponse,
) -> Result[
  (String, String, String, String, Int64),
  @publication_host.ClientKeyedRequestIssue,
] {
  guard @publication.lookup_raw_response_content(raw.metadata)
    is Some((cid, count)) else {
    return Err(@publication_host.Assembly("foreign_lookup_raw_response"))
  }
  Ok(
    (
      @publication.publication_contract_identity(raw.metadata),
      raw.holding,
      @publication.publication_contract_json(raw.metadata),
      cid,
      count,
    ),
  )
}

///|
#export_name("clientProgramKeyedLookupPrepareDeclaredFileRawCapture")
pub fn client_program_keyed_lookup_prepare_declared_file_raw_capture(
  compiled : @publication_host.ClientCompiledRun,
  definition : @publication.PublicationContract,
  request : @publication_host.ClientKeyedRequest,
  retention : @publication.PublicationContract,
  store_id : String,
  store_cid : String,
  availability_cid : String,
  issuer_cid : String,
  content_cid : String,
  size_bytes : Int,
  captured_at : String,
  now_ms : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
  max_text_units : Int,
) -> Result[
  @publication_host.ClientKeyedNativeRawResponse,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.prepare_client_keyed_declared_file_raw_capture(
    compiled,
    definition,
    request,
    retention,
    store_id,
    store_cid,
    availability_cid,
    issuer_cid,
    content_cid,
    size_bytes,
    captured_at,
    now_ms,
    { max_bytes, max_nodes, max_depth, max_text_units, },
  )
}

///|
#export_name("clientProgramKeyedLookupPrepareCapturedPage")
pub fn client_program_keyed_lookup_prepare_captured_page(
  request : @publication_host.ClientKeyedRequest,
  capture : @client_row_source_host.RowKeyedSourceCapture,
  raw : @publication_host.ClientKeyedNativeRawResponse,
  recorded_at : String,
  limits : @publication_host.PublicationOutputExportLimits,
  max_work : Int,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @publication_host.ClientKeyedNativeCapturedPage,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.prepare_client_keyed_captured_page(
    request, capture, raw, recorded_at, limits, max_work, max_bytes, max_nodes, max_depth,
  )
}

///|
#export_name("clientProgramKeyedLookupDeclaredFilePublicationInput")
pub fn client_program_keyed_lookup_declared_file_publication_input(
  lookup : @publication_host.ClientKeyedLookupInput,
  recorded_at : String,
  now_ms : Int64,
  max_bytes : Int,
  max_nodes : Int,
  max_depth : Int,
) -> Result[
  @execution.SuppliedRelationRead,
  @publication_host.ClientKeyedRequestIssue,
] {
  @publication_host.finish_client_keyed_lookup_publication_input(
    lookup,
    max_bytes,
    max_nodes,
    max_depth,
    retain_body=true,
    native_completion=Some((recorded_at, now_ms)),
  )
}

///|
#export_name("clientProgramKeyedLookupBindDeclaredFilePhysicalSource")
pub fn client_program_keyed_lookup_bind_declared_file_physical_source(
  lookup : @publication_host.ClientKeyedLookupInput,
  declarations : Array[@client_row_source_host.RowDeclaration],
) -> Result[Unit, @publication_host.ClientKeyedRequestIssue] {
  @publication_host.bind_client_keyed_declared_file_physical_source(
    lookup, declarations,
  )
}
