///|
test "Native Model HTTP keeps the resolved route from the adopted provider" {
  let revision = "sha256:" + "1".repeat(64)
  let contract = "sha256:" + "2".repeat(64)
  let profile = "sha256:" + "3".repeat(64)
  let wire = "{\"adapter_kind\":\"portable-http\",\"api_mode\":\"chat-completions\",\"configuration_contract_cid\":\"" +
    contract +
    "\",\"credential_ref\":\"file:provider.key\",\"endpoint\":\"https://models.example/v1/chat/completions\",\"installation_revision_cid\":\"" +
    revision +
    "\",\"model_id\":\"deployed-model\",\"provider_id\":\"models/http\",\"response_profile_cid\":\"" +
    profile +
    "\",\"selector\":\"authored-alias\"}"
  let body = @utf8.encode(wire)
  let limits : @environment.Limits = {
    max_bytes: 1024,
    max_nodes: 16,
    max_depth: 4,
    max_members: 8,
  }
  let route = @model.read_portable_model_http_chat_file_route(
    body, "models/http", revision, contract, profile, "provider.key", limits,
  ).unwrap()
  assert_eq(route.selector, "authored-alias")
  assert_eq(route.model_id, "deployed-model")
  assert_eq(route.endpoint, "https://models.example/v1/chat/completions")
  let manifest = "a".repeat(64)
  let installed = native_model_http_installation_profile(
    manifest,
    route.endpoint,
  )
  assert_eq(installed.endpoint, "https://models.example/v1/chat/completions")
  assert_eq(installed.build_artifact_cid, "sha256:" + manifest)
  assert_eq(installed.validator_artifact_cid, "sha256:" + manifest)
  assert_true(installed.sdk is None)
  assert_eq(installed.http_method, "POST")
  assert_false(installed.streaming)
  assert_eq(installed.completion_basis, "generation_finish")
  let replaced = native_model_http_installation_profile(
    "b".repeat(64),
    route.endpoint,
  )
  assert_true(replaced.build_artifact_cid != installed.build_artifact_cid)
  assert_true(
    replaced.validator_artifact_cid != installed.validator_artifact_cid,
  )
}

///|
test "Native Model HTTP policy requires bounded transport and explicit evidence locators" {
  let wire =
    #|{"ca_path":"/etc/ssl/fixture.pem","connect_timeout_ms":500,"operation_timeout_ms":1250,"credential_expires_at_ms":1798761600000,"max_projection_frames":100,"attempt_tokens":500,"attempt_cost_units":0,"input_classification":"internal","provider_region":"fixture","provider_retention":false,"provider_training_use":false,"retention_contract_file":"retention.json","metadata_retention_file":"metadata.json","clock_contract_file":"clock.json","data_policy_file":"data.json","available_until":"2027-01-01T00:00:00.000Z","delete_by":"2027-01-02T00:00:00.000Z","extension_ceiling_at":"2027-01-02T00:00:00.000Z","metadata_delete_by":"2027-01-03T00:00:00.000Z"}
  let limits : @environment.Limits = {
    max_bytes: 8192,
    max_nodes: 128,
    max_depth: 8,
    max_members: 64,
  }
  let selected = native_model_http_run_policy_selection(
    @utf8.encode(wire),
    limits,
  ).unwrap()
  assert_eq(selected.transport.connect_timeout_ms, 500)
  assert_eq(selected.transport.operation_timeout_ms, 1250)
  assert_eq(selected.transport.credential_expires_at, 1798761600000L)
  assert_eq(
    selected.transport.observation.classification,
    @environment.Internal,
  )
  assert_eq(selected.transport.attempt_tokens, 500L)
  assert_eq(selected.retention, "retention.json")
  assert_eq(selected.data, "data.json")
  assert_true(selected.output_policy is None)
  let cid = "sha256:" + "a".repeat(64)
  let declared = "{\"upstream_model_outputs\":{\"version\":\"actql-local-model-output-policy/0.1\",\"inputs\":[{\"classification\":\"internal\",\"input_index\":0,\"producer_stage\":1,\"producer_step\":2,\"producer_task_cid\":\"" +
    cid +
    "\",\"producer_binding_cid\":\"" +
    cid +
    "\",\"producer_profile_cid\":\"" +
    cid +
    "\",\"producer_schema_cid\":\"" +
    cid +
    "\",\"receiving_binding_cid\":\"" +
    cid +
    "\"}],\"receiving_task_cid\":\"" +
    cid +
    "\",\"receiving_profile_cid\":\"" +
    cid +
    "\"},"
  fn parse_output_use(value : String) -> NativeModelOutputDeclaration? {
    let parsed = native_model_http_run_policy_selection(
      @utf8.encode(wire.replace(old="{", new=value)),
      limits,
    )
    guard parsed.bind(value => value.output_policy) is Some(cursor) &&
      @decode.closed_object(cursor, [
        "inputs", "receiving_profile_cid", "receiving_task_cid", "version",
      ])
      is Ok(fields) else {
      return None
    }
    @decode.lookup(fields, "inputs")
    .bind(values => @decode.element_at(values, 0))
    .bind(native_model_output_declaration)
  }
  let dependency = parse_output_use(declared).unwrap()
  assert_eq((dependency.input, dependency.stage, dependency.step), (0, 1, 2))
  assert_eq(dependency.classification, @environment.Internal)
  assert_eq(dependency.receiving_binding, cid)
  for
    changed in [
      declared.replace(old=cid, new="sha256:" + "A".repeat(64)),
      declared.replace(old="\"internal\"", new="\"unknown\""),
      declared.replace(old="\"input_index\":0", new="\"input_index\":-1"),
      declared.replace(
        old="\"input_index\":0",
        new="\"input_index\":0,\"extra\":true",
      ),
    ] {
    assert_true(parse_output_use(changed) is None)
  }
  for
    (old, new) in [
      ("\"/etc/ssl/fixture.pem\"", "\"relative.pem\""),
      ("\"operation_timeout_ms\":1250", "\"operation_timeout_ms\":499"),
      ("\"attempt_tokens\":500", "\"attempt_tokens\":0"),
      ("\"internal\"", "\"unknown\""),
      ("\"clock_contract_file\":\"clock.json\",", ""),
      ("\"data_policy_file\"", "\"unexpected_file\""),
    ] {
    assert_true(
      native_model_http_run_policy_selection(
        @utf8.encode(wire.replace(old~, new~)),
        limits,
      )
      is None,
    )
  }
}

///|
test "Native Model HTTP execution bundle quote covers the original wires" {
  let wire =
    #|{"contract_cid":"original-cid","contract":"{\"c\":1}","prompt":"{\"p\":\"日本語\"}","retry_policy":"{\"r\":[]}","backoff":"{\"b\":[]}"}
  let bytes = @utf8.encode(wire)
  let limits : @environment.Limits = {
    max_bytes: bytes.length(),
    max_nodes: 32,
    max_depth: 8,
    max_members: 16,
  }
  let original = (
    "original-cid", "{\"c\":1}", "{\"p\":\"日本語\"}", "{\"r\":[]}", "{\"b\":[]}",
  )
  assert_eq(
    @model.read_portable_model_http_execution_wires(bytes, limits),
    Some(original),
  )
  let documents = [original.1, original.2, original.3, original.4]
  let (retained, working) = native_model_http_execution_construction(
    documents,
    bytes.length(),
    limits,
  ).unwrap()
  assert_true(working.owned_wire_bytes >= bytes.length().to_int64())
  assert_eq(retained.owned_wire_bytes, 0L)
  assert_true(
    @execution.preparation_representation_cost(working).unwrap() >
    @execution.preparation_representation_cost(retained).unwrap(),
  )
}
