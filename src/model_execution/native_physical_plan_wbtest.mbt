///|
// Reuse the existing independent native profile bytes/CID verbatim. These
// fixture declarations prove binding only, never complete physical funding.
fn native_plan_profile() -> @environment.ModelResponseProfile {
  let wire =
    #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/sdk-builder","builder_revision":"1","codec_id":"fixture/native-decision","codec_revision":"1","port_abi":"model-physical-port/1","sdk":{"interface":"v4","lock_artifact_cid":"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367","package":"@ai-sdk/typesafe-ai","version":"3.0.13"}},"completion":{"basis":"native_decision","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/systemone","method":"POST","streaming":false},"probability":{"source":"native","validation_profile_cid":"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f"},"self_cid":"sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b","task":{"contract_cid":"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e","input_schema_cid":"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466","kind":"decision","output_schema_cid":"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9"},"version":"actql-model-response-profile/0.1"}
  @environment.read_model_response_profile(
    @utf8.encode(wire),
    "sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 100, },
    100000,
  ).unwrap()
}

///|
fn native_plan_installation() -> @environment.ModelResponseProfileInstallation {
  {
    builder_id: "fixture/sdk-builder",
    builder_revision: "1",
    codec_id: "fixture/native-decision",
    codec_revision: "1",
    build_artifact_cid: "sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2",
    sdk: Some({
      package_name: "@ai-sdk/typesafe-ai",
      version: "3.0.13",
      interface: "v4",
      lock_artifact_cid: "sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367",
    }),
    endpoint: "https://fixture.invalid/systemone",
    http_method: "POST",
    streaming: false,
    validator_id: "fixture/chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: "sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd",
    completion_basis: "native_decision",
  }
}

///|
fn native_plan_original() -> (
  AdmittedModelProvider,
  ModelRequest,
  NativeDecisionRequest,
  () -> Int,
) raise {
  let (fixture, request, calls) = native_decision_projection_fixture("null")
  let provider = admit_model_provider(
    install_async_model_provider("models/fixture").unwrap(),
    fixture.execution,
    fixture.dependencies,
    (_, _) => true,
  ).unwrap()
  let cursor = start_native_decision_projection(
    provider, request, 10000, 1000, 40, 100, 10000,
  ).unwrap()
  let original = native_projection_run(cursor, 1)
  retire_native_decision_projection(cursor)
  (provider, request, original, calls)
}

///|
test "native physical plan accepts original Decision without dummy generation or dispatch" {
  let (provider, request, original, calls) = native_plan_original()
  assert_true(@environment.model_task_generation_config(request.task) is None)
  let quantities : @resources.QuantityAmounts = {
    tokens: 128L,
    cost_units: 0L,
    duration_ms: 1000L,
  }
  let plan = model_async_native_decision_request_plan(
    request,
    original,
    provider,
    1024L,
    quantities,
    native_plan_profile(),
    native_plan_installation(),
    @environment.initial_jev_decision_profile(),
    _ => None,
  ).unwrap()
  assert_true(plan.invocation is Asynchronous(_))
  assert_true(physical_equal(plan.request, request))
  assert_eq(plan.wire_bytes, 1024L)
  assert_eq(plan.quantities, quantities)
  assert_eq(plan.attachments.length(), 0)
  assert_true(plan.evidence is None)
  assert_eq(calls(), 0)
  retire_native_decision_request(original)
}

///|
test "native physical plan refuses foreign retired and synchronous original providers" {
  let (provider, request, original, calls) = native_plan_original()
  let (foreign, foreign_request, foreign_original, foreign_calls) = native_plan_original()
  let amounts : @resources.QuantityAmounts = {
    tokens: 128L,
    cost_units: 0L,
    duration_ms: 1000L,
  }
  let profile = native_plan_profile()
  let installation = native_plan_installation()
  let probability = @environment.initial_jev_decision_profile()
  for
    (p, r, view) in [
      (foreign, request, original),
      (provider, foreign_request, original),
      (provider, request, foreign_original),
    ] {
    assert_true(
      model_async_native_decision_request_plan(
        r,
        view,
        p,
        100L,
        amounts,
        profile,
        installation,
        probability,
        _ => None,
      )
      is Err(InvalidProvider),
    )
  }
  let (sync, sync_request, sync_calls) = native_decision_projection_fixture(
    "null",
  )
  let emitter = start_native_decision_projection(
    sync, sync_request, 10000, 1000, 40, 100, 10000,
  ).unwrap()
  let sync_original = native_projection_run(emitter, 1)
  assert_true(
    model_async_native_decision_request_plan(
      sync_request,
      sync_original,
      sync,
      100L,
      amounts,
      profile,
      installation,
      probability,
      _ => None,
    )
    is Err(InvalidProvider),
  )
  assert_true(
    model_physical_request_plan(request, 100L, amounts, () => Err(ProviderError))
    is Err(InvalidProvider),
  )
  assert_true(
    model_async_physical_request_plan(
      request,
      100L,
      amounts,
      profile,
      installation,
      _ => None,
    )
    is Err(InvalidProvider),
  )
  retire_native_decision_request(original)
  assert_true(
    model_async_native_decision_request_plan(
      request,
      original,
      provider,
      100L,
      amounts,
      profile,
      installation,
      probability,
      _ => None,
    )
    is Err(InvalidProvider),
  )
  retire_native_decision_request(foreign_original)
  retire_native_decision_request(sync_original)
  retire_native_decision_projection(emitter)
  assert_eq(calls(), 0)
  assert_eq(foreign_calls(), 0)
  assert_eq(sync_calls(), 0)
}

///|
test "native physical plan keeps exact profile installation and request quantity limits" {
  let (provider, request, original, calls) = native_plan_original()
  let amounts : @resources.QuantityAmounts = {
    tokens: 128L,
    cost_units: 0L,
    duration_ms: 1000L,
  }
  let profile = native_plan_profile()
  let installation = native_plan_installation()
  let probability = @environment.initial_jev_decision_profile()
  for
    wrong in [
      { ..installation, builder_revision: "foreign", },
      { ..installation, codec_revision: "foreign", },
      { ..installation, endpoint: "https://foreign.invalid/systemone", },
      { ..installation, completion_basis: "generation_finish", },
      { ..installation, sdk: None, },
    ] {
    assert_true(
      model_async_native_decision_request_plan(
        request,
        original,
        provider,
        100L,
        amounts,
        profile,
        wrong,
        probability,
        _ => None,
      )
      is Err(InvalidProvider),
    )
  }
  assert_true(
    model_async_native_decision_request_plan(
      request,
      original,
      provider,
      1025L,
      amounts,
      profile,
      installation,
      probability,
      _ => None,
    )
    is Err(RequestLimit),
  )
  for
    invalid in [
      { ..amounts, tokens: -1L, },
      { ..amounts, cost_units: -1L, },
      { ..amounts, duration_ms: -1L, },
      { ..amounts, tokens: 9007199254740992L, },
    ] {
    assert_true(
      model_async_native_decision_request_plan(
        request,
        original,
        provider,
        100L,
        invalid,
        profile,
        installation,
        probability,
        _ => None,
      )
      is Err(InvalidLimits),
    )
  }
  assert_true(
    model_async_native_decision_request_plan(
      request,
      original,
      provider,
      -1L,
      amounts,
      profile,
      installation,
      probability,
      _ => None,
    )
    is Err(InvalidLimits),
  )
  retire_native_decision_request(original)
  assert_eq(calls(), 0)
}

///|
test "native physical plan leaves generation token floor and synchronous branch unchanged" {
  let (_, request, original, calls) = native_plan_original()
  let task = @environment.resolve_model_task(
    model_execution_test_tasks(),
    "model-task:risk-score.v1",
  ).unwrap()
  let generation_request : ModelRequest = { ..request, task, inputs: [], }
  let exact : @resources.QuantityAmounts = {
    tokens: 32L,
    cost_units: 0L,
    duration_ms: 1000L,
  }
  assert_true(
    model_physical_request_plan(
      generation_request,
      100L,
      { ..exact, tokens: 31L, },
      () => Err(ProviderError),
    )
    is Err(InvalidLimits),
  )
  let plan = model_physical_request_plan(generation_request, 100L, exact, () => {
    Err(ProviderError)
  }).unwrap()
  assert_true(plan.invocation is Synchronous(_))
  assert_eq(calls(), 0)
  retire_native_decision_request(original)
}
