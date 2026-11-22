///|
fn structured_capability_fixture_profile() -> @environment.ModelResponseProfile {
  let wire =
    #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"1","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":null},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://models.example/v1/structured","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:1df96033c675c1466c1ee765dbecc48799d57ba40fe9b9eaad22c76539ad2b75","task":{"contract_cid":"sha256:1338eb4818d71fb229fa020a1c98f518a51a8d9c1c204356ac9108855a60d524","input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","kind":"structured_generate","output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3"},"version":"actql-model-response-profile/0.1"}
  @environment.read_model_response_profile(
    @utf8.encode(wire),
    "sha256:1df96033c675c1466c1ee765dbecc48799d57ba40fe9b9eaad22c76539ad2b75",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
}

///|
fn structured_capability_fixture_installation() -> @environment.ModelResponseProfileInstallation {
  {
    builder_id: "fixture/http-builder",
    builder_revision: "1",
    codec_id: "fixture/chat-one",
    codec_revision: "1",
    build_artifact_cid: "sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2",
    sdk: None,
    endpoint: "https://models.example/v1/structured",
    http_method: "POST",
    streaming: false,
    validator_id: "fixture/chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: "sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd",
    completion_basis: "generation_finish",
  }
}

///|
test "structured Provider admission requires support on the resolved model and mode" {
  let (execution, dependencies) = provider_admission_fixture()
  let (foreign_execution, foreign_dependencies) = provider_admission_fixture()
  let provider = install_async_model_provider("models/fixture").unwrap()
  let selected : ResolvedStructuredModel = {
    selector: "fixture-risk-model",
    model_id: "physical-model-a",
    adapter_kind: "fixture-sdk",
    api_mode: "structured-http",
    endpoint: "https://models.example/v1/structured",
  }
  let configuration =
    #|{"adapter_kind":"fixture-sdk","api_mode":"structured-http","endpoint":"https://models.example/v1/structured","model_id":"physical-model-a","provider_id":"models/fixture","selector":"fixture-risk-model"}
  let foreign_configuration =
    #|{"adapter_kind":"fixture-sdk","api_mode":"structured-http","endpoint":"https://models.example/v1/structured","model_id":"physical-model-b","provider_id":"models/fixture","selector":"fixture-risk-model"}
  let issue = wire => {
    @publication_host.issue_client_model_provider_binding(
      "models/fixture", "{}", "{}", wire,
    ).unwrap()
  }
  let binding = issue(configuration)
  let profile = structured_capability_fixture_profile()
  let installation = structured_capability_fixture_installation()
  let foreign_binding = issue(foreign_configuration)
  // Same connector, selector and declared route. The installed original
  // actually resolves a different model. A substituted wire fails too.
  assert_true(
    register_structured_model_capability(
      provider, foreign_binding, foreign_configuration, selected, profile, true,
      true,
    )
    is Err(ForeignConfiguration),
  )
  assert_true(
    register_structured_model_capability(
      provider, foreign_binding, configuration, selected, profile, true, true,
    )
    is Err(ForeignConfiguration),
  )
  let supported = register_structured_model_capability(
    provider, binding, configuration, selected, profile, true, true,
  ).unwrap()
  let unsupported = register_structured_model_capability(
    provider, binding, configuration, selected, profile, true, false,
  ).unwrap()
  let unsupported_adapter = register_structured_model_capability(
    provider, binding, configuration, selected, profile, false, true,
  ).unwrap()
  let mut validations = 0
  let validate = (_, _) => {
    validations += 1
    true
  }
  let foreign_installation = { ..installation, codec_revision: "replacement", }
  assert_true(
    admit_structured_model_provider(
      supported, selected, execution, dependencies, foreign_installation, validate,
    )
    is Err(ForeignProfile),
  )
  assert_true(
    admit_structured_model_provider(
      unsupported, selected, execution, dependencies, installation, validate,
    )
    is Err(UnsupportedModel),
  )
  assert_true(
    admit_structured_model_provider(
      unsupported_adapter, selected, execution, dependencies, installation, validate,
    )
    is Err(UnsupportedAdapter),
  )
  let changed_model = { ..selected, model_id: "physical-model-b", }
  let changed_mode = { ..selected, api_mode: "streaming-http", }
  for changed in [changed_model, changed_mode] {
    assert_true(
      admit_structured_model_provider(
        supported, changed, execution, dependencies, installation, validate,
      )
      is Err(ChangedSelection),
    )
  }
  assert_true(
    admit_structured_model_provider(
      supported, selected, execution, foreign_dependencies, installation, validate,
    )
    is Err(ProviderAdmission(ForeignDependencies)),
  )
  assert_eq(validations, 0)
  let admitted = admit_structured_model_provider(
    supported, selected, execution, dependencies, installation, validate,
  ).unwrap()
  assert_eq(validations, 1)
  let replacement = register_structured_model_capability(
    provider, binding, configuration, selected, profile, true, true,
  ).unwrap()
  assert_true(
    admitted_structured_model_provider_for(
      admitted, replacement, binding, selected, execution,
    )
    is None,
  )
  assert_true(
    admitted_structured_model_provider_for(
      admitted, supported, binding, changed_model, execution,
    )
    is None,
  )
  assert_true(
    admitted_structured_model_provider_for(
      admitted, supported, binding, selected, foreign_execution,
    )
    is None,
  )
  assert_true(
    admitted_structured_model_provider_for(
      admitted,
      supported,
      issue(configuration),
      selected,
      execution,
    )
    is None,
  )
  assert_true(
    admitted_structured_model_provider_for(
      admitted, supported, binding, selected, execution,
    )
    is Some(actual) &&
    physical_equal(actual, provider),
  )
  let request : ModelRequest = {
    task: @environment.model_execution_task(execution),
    slot: 0,
    slot_cid: "fixture-slot",
    fixed_request_cid: "fixture-request",
    key: [],
    inputs: [],
  }
  let amounts : @resources.QuantityAmounts = {
    tokens: 128L,
    cost_units: 0L,
    duration_ms: 1000L,
  }
  let mut starts = 0
  let start = _ => {
    starts += 1
    None
  }
  let plan = (actual, response_profile, physical) => {
    structured_model_async_request_plan(
      admitted,
      supported,
      binding,
      actual,
      request,
      128L,
      amounts,
      response_profile,
      physical,
      start,
      (_, _, _) => None,
    )
  }
  assert_true(
    plan(selected, profile, foreign_installation) is Err(InvalidProvider),
  )
  assert_true(
    plan(selected, structured_capability_fixture_profile(), installation)
    is Err(InvalidProvider),
  )
  assert_true(
    plan(changed_model, profile, installation) is Err(InvalidProvider),
  )
  assert_true(plan(selected, profile, installation) is Ok(_))
  assert_eq(starts, 0)
}
