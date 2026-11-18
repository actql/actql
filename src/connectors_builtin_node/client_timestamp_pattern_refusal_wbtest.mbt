///|
// Independently hashed DATA profile; the existing original Request fixture owns
// its actual resource admission. This profile supplies no operational funding.
fn request_timestamp_pattern_environment() -> @program_check.CheckEnvironment {
  let wire =
    #|{"command_contracts":[],"connector_capabilities":[],"connector_catalogs":[],"contract_registry":[],"evidence_bundle_cid":"sha256:cb359594d618dc1c5e5a77f83aa7a4f85cfd30550bd376efa2add397cee3bf0c","host_policy_profile":{"capacity":{"max_aggregate_array_items":1000,"max_artifact_bytes":1000,"max_artifact_rows":1000,"max_effect_items":1000,"max_graph_input_edges":1000,"max_graph_input_nodes":1000,"max_graph_output_rows":1000,"max_graph_paths":1000,"max_infer_items":1000,"max_model_input_tokens_per_item":1000,"max_model_request_bytes_per_item":1000,"max_model_total_duration_ms":1000,"max_nested_value_bytes":1000,"max_nested_value_depth":1000,"max_relation_output_rows":1000,"max_temporal_matches_per_key":1000,"max_temporal_output_rows":1000,"version":"actql-capacity-host-policy/0.1"},"text_time_evaluation":{"max_input_codepoints":64,"max_input_utf8_bytes":256,"max_output_bytes":64,"max_pattern_bytes":100,"max_replacements":1,"version":"actql-text-time-host-policy/0.1"}},"mapping_contracts":[],"model_task_contracts":[],"schema_snapshots":[],"source_views":[],"version":"actql-check-environment/0.1"}
  client_program_check_environment(
    wire, "sha256:cb359594d618dc1c5e5a77f83aa7a4f85cfd30550bd376efa2add397cee3bf0c",
    true, false, true, false, false, false, false,
  ).unwrap()
}

///|
test "Request timestamp pattern refusal preserves the exact authored parser cause" {
  let environment = request_timestamp_pattern_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  for
    sql in [
      "SELECT FORMAT_TIMESTAMP('%Y', CAST('2026-01-02T00:00:00.000Z' AS TIMESTAMP)) AS x",
      "SELECT PARSE_TIMESTAMP('%Y-%m-%d', '2026-01-02') AS x", "SELECT PARSE_TIMESTAMP('', '2026') AS x",
      "SELECT PARSE_TIMESTAMP('yyyyyyyy', '2026') AS x", "SELECT PARSE_TIMESTAMP('MM-dd', '01-02') AS x",
      "SELECT PARSE_TIMESTAMP('yyyy-MM-dd ss', '2026-01-02 00') AS x",
    ] {
    let (parent, receipt) = request_diagnostic_test_parent()
    let result = client_program_prepare_request_source_computation(
      parent,
      receipt,
      request_diagnostic_test_json(
        "{\"format\":\"sql\",\"text\":\"" + sql + "\"}",
      ),
      request_diagnostic_test_json("null"),
      environment,
      publication,
      None,
    )
    assert_true(result is Err(_))
    assert_eq(
      request_diagnostic_checked_issue_code(result),
      Some("ClientProgramTimestampPatternInvalid"),
    )
    @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  }
}

///|
test "Request timestamp projection keeps missing profile foreign and retired originals uncertain" {
  let environment = request_timestamp_pattern_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let source = request_diagnostic_test_json(
    "{\"format\":\"sql\",\"text\":\"SELECT PARSE_TIMESTAMP('%Y', '2026') AS x\"}",
  )
  let (parent, receipt) = request_diagnostic_test_parent()
  let foreign = client_program_prepare_request_source_computation(
    parent,
    request_diagnostic_test_receipt(),
    source,
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  assert_true(foreign is Err(_))
  assert_eq(request_diagnostic_checked_issue_code(foreign), None)
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
  let retired = client_program_prepare_request_source_computation(
    parent,
    receipt,
    source,
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  assert_true(retired is Err(_))
  assert_eq(request_diagnostic_checked_issue_code(retired), None)
  let missing = original_lookup_diagnostic_environment(false)
  let missing_publication = @source_publication.prepare_published_query_environment(
    missing,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(missing) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (next, input) = request_diagnostic_test_parent()
  let unavailable = client_program_prepare_request_source_computation(
    next,
    input,
    source,
    request_diagnostic_test_json("null"),
    missing,
    missing_publication,
    None,
  )
  assert_true(unavailable is Err(_))
  assert_true(
    request_diagnostic_checked_issue_code(unavailable) !=
    Some("ClientProgramTimestampPatternInvalid"),
  )
  @client_local_host.abort_request_preparation_after_cleanup(next).unwrap()
}

///|
// Consume the actual Core Result and its existing Option callback ABI through
// the imported Node adapter; no result layout or public-looking code is forged.
extern "js" fn request_timestamp_pattern_public_refusal(
  loader : RequestDiagnosticTestLoader,
  result : Result[Unit, @client_local_host.ClientRequestTerminalIssue],
  project : (Result[Unit, @client_local_host.ClientRequestTerminalIssue]) -> String?,
) -> Bool =
  #|(loader,result,project)=>{const {checkedRequestProgramPreparation,requestProgramPreparationProblemCode,requestProgramPreparationRefusalCode}=loader('../../../../../adapters/host-node/client-program-preparation.mjs');const {runtimeField}=loader('../../../../../adapters/host-common/compiler-binding.generated.mjs');let calls=0;try{checkedRequestProgramPreparation({clientProgramRequestPreparationIssueCode(actual){if(actual!==result)throw Error('SubstitutedResult');calls++;return project(actual);}},result);return false;}catch(error){return calls===1&&error.code==='ClientProgramInvalidInput'&&error.cause===runtimeField(result,0)&&requestProgramPreparationProblemCode(error)==='ClientProgramTimestampPatternInvalid'&&requestProgramPreparationRefusalCode(error)==='ClientProgramInvalidInput'&&requestProgramPreparationProblemCode({...error})===undefined;}}

///|
test "original Core timestamp failure enters the same Node nominal refusal association" {
  let environment = request_timestamp_pattern_environment()
  let publication = @source_publication.prepare_published_query_environment(
    environment,
    "{\"environmentCid\":\"" +
    @program_check.checking_environment_cid(environment) +
    "\",\"aliases\":[]}",
  ).unwrap()
  let (parent, receipt) = request_diagnostic_test_parent()
  let result = client_program_prepare_request_source_computation(
    parent,
    receipt,
    request_diagnostic_test_json(
      "{\"format\":\"sql\",\"text\":\"SELECT PARSE_TIMESTAMP('%Y-%m-%d', '2026-01-02') AS x\"}",
    ),
    request_diagnostic_test_json("null"),
    environment,
    publication,
    None,
  )
  assert_true(result is Err(_))
  assert_true(
    request_timestamp_pattern_public_refusal(
      request_diagnostic_test_loader(request_diagnostic_test_url()),
      result,
      original => request_diagnostic_checked_issue_code(original),
    ),
  )
  @client_local_host.abort_request_preparation_after_cleanup(parent).unwrap()
}
