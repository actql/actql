///|
test "HTTP Chat original request preserves typed input and explicit one-choice profile" {
  let (provider, request, calls) = openai_projection_fixture()
  let projected = project_http_chat_request(
    provider, request, "fixture-http", 10000, 1000, 40, 100, 20000,
  ).unwrap()
  assert_eq(projected.0, http_chat_expected_wire)
  assert_eq(
    (projected.1, projected.2, projected.3, projected.4),
    (
      "sha256:35db189b1ef0b8e41d799f6aa6420dc1acaf572afc290a2e28873e191ed01d4f",
      "sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba",
      "sha256:773858f1a0187020cb634048b5062e82163816ebf568902ff7c89d78ebacd317",
      "fixture-chat",
    ),
  )
  assert_eq(calls(), 0)
}

///|
test "HTTP Chat projection refuses foreign provider and missing physical model" {
  let (provider, request, calls) = openai_projection_fixture()
  let (foreign, _, foreign_calls) = openai_projection_fixture()
  assert_true(
    project_http_chat_request(
      foreign, request, "fixture-http", 10000, 1000, 40, 100, 20000,
    )
    is Err(ForeignRequest),
  )
  assert_true(
    project_http_chat_request(
      provider, request, "", 10000, 1000, 40, 100, 20000,
    )
    is Err(Unsupported),
  )
  assert_eq(calls(), 0)
  assert_eq(foreign_calls(), 0)
}

///|
test "HTTP Chat projection enforces cumulative preparation and outbound ceilings" {
  let (provider, request, calls) = openai_projection_fixture()
  assert_true(
    project_http_chat_request(
      provider, request, "fixture-http", 10, 1000, 40, 100, 20000,
    )
    is Err(Limit),
  )
  assert_true(
    project_http_chat_request(
      provider, request, "fixture-http", 10000, 1000, 40, 100, 0,
    )
    is Err(Limit),
  )
  assert_eq(calls(), 0)
}

///|
fn sdk_v4_completed_fixture(
  provider : AdmittedModelProvider,
  request : ModelRequest,
  max_work : Int,
) -> OpenAIChatProjection {
  let cursor = start_openai_chat_projection(
    provider, request, 10000, 1000, 40, 100, max_work,
  ).unwrap()
  while advance_openai_chat_projection(cursor).unwrap() is None {

  }
  cursor
}

///|
test "SDK v4 profile shares original materials and preserves omitted n and stream" {
  let (provider, request, calls) = openai_projection_fixture()
  let cursor = sdk_v4_completed_fixture(provider, request, 20000)
  let value = finish_openai_chat_sdk_v4_projection(
    cursor, "fixture-http", 10000,
  ).unwrap()
  assert_eq(value.7, sdk_v4_expected_wire)
  assert_eq(
    (value.3, value.4, value.5, value.6),
    (
      "sha256:35db189b1ef0b8e41d799f6aa6420dc1acaf572afc290a2e28873e191ed01d4f",
      "sha256:4dafcb774d376060c511f323e7a55cd2d2eeb634691f4431b0dd977c3ae7abba",
      "sha256:773858f1a0187020cb634048b5062e82163816ebf568902ff7c89d78ebacd317",
      "fixture-chat",
    ),
  )
  assert_true(advance_openai_chat_projection(cursor) is Err(ForeignRequest))
  assert_true(
    finish_openai_chat_sdk_v4_projection(cursor, "fixture-http", 10000)
    is Err(ForeignRequest),
  )
  assert_eq(calls(), 0)
}

///|
test "SDK v4 finish refuses unready retired and bounded terminal children without dispatch" {
  let (provider, request, calls) = openai_projection_fixture()
  let unready = start_openai_chat_projection(
    provider, request, 10000, 1000, 40, 100, 20000,
  ).unwrap()
  assert_true(
    finish_openai_chat_sdk_v4_projection(unready, "fixture-http", 10000)
    is Err(ForeignRequest),
  )
  retire_openai_chat_projection(unready)
  for
    (model, bytes) in [
      ("", 10000),
      ("fixture-http", 1),
      ("fixture-http", 357913942),
    ] {
    let cursor = sdk_v4_completed_fixture(provider, request, 20000)
    assert_true(
      finish_openai_chat_sdk_v4_projection(cursor, model, bytes) is Err(_),
    )
    assert_true(advance_openai_chat_projection(cursor) is Err(ForeignRequest))
  }
  let completed = sdk_v4_completed_fixture(provider, request, 20000)
  let used = openai_chat_projection_work(completed)
  retire_openai_chat_projection(completed)
  let cursor = sdk_v4_completed_fixture(provider, request, used)
  assert_true(
    finish_openai_chat_sdk_v4_projection(cursor, "fixture-http", 10000)
    is Err(Limit),
  )
  assert_true(advance_openai_chat_projection(cursor) is Err(ForeignRequest))
  assert_eq(calls(), 0)
}

///|
let sdk_v4_expected_wire : String = "{\"max_tokens\":16,\"messages\":[{\"content\":\"é\\r\\né\\n😀\",\"role\":\"system\"},{\"content\":\"{\\\"absent\\\":null,\\\"amount\\\":\\\"9007199254740993.00\\\",\\\"text\\\":\\\"é\\\\r\\\\n😀\\\"}\",\"role\":\"user\"}],\"model\":\"fixture-http\",\"response_format\":{\"json_schema\":{\"name\":\"actql_output\",\"schema\":{\"additionalProperties\":false,\"properties\":{\"answer\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"null\"}]}},\"required\":[\"answer\"],\"type\":\"object\"},\"strict\":true},\"type\":\"json_schema\"},\"seed\":-7,\"temperature\":0.25,\"top_p\":0.875}"

///|
test "SDK v4 convenience preserves exact body and refuses a foreign original before SDK driving" {
  let (provider, request, calls) = openai_projection_fixture()
  let (foreign, _, foreign_calls) = openai_projection_fixture()
  let value = project_openai_chat_sdk_v4_request(
    provider, request, "fixture-http", 10000, 10000, 1000, 40, 100, 20000,
  ).unwrap()
  assert_eq(value.7, sdk_v4_expected_wire)
  assert_eq(value.6, "fixture-chat")
  assert_true(
    project_openai_chat_sdk_v4_request(
      foreign, request, "fixture-http", 10000, 10000, 1000, 40, 100, 20000,
    )
    is Err(ForeignRequest),
  )
  assert_eq(calls(), 0)
  assert_eq(foreign_calls(), 0)
}

///|
let http_chat_expected_wire : String = "{\"max_tokens\":16,\"messages\":[{\"content\":\"é\\r\\né\\n😀\",\"role\":\"system\"},{\"content\":\"{\\\"absent\\\":null,\\\"amount\\\":\\\"9007199254740993.00\\\",\\\"text\\\":\\\"é\\\\r\\\\n😀\\\"}\",\"role\":\"user\"}],\"model\":\"fixture-http\",\"n\":1,\"response_format\":{\"json_schema\":{\"name\":\"actql_output\",\"schema\":{\"additionalProperties\":false,\"properties\":{\"answer\":{\"anyOf\":[{\"type\":\"string\"},{\"type\":\"null\"}]}},\"required\":[\"answer\"],\"type\":\"object\"},\"strict\":true},\"type\":\"json_schema\"},\"seed\":-7,\"stream\":false,\"temperature\":0.25,\"top_p\":0.875}"

///|
test "portable HTTP borrows only the paid codec result of the exact request and installation" {
  let (basis, request, calls) = openai_projection_fixture()
  let foreign_request = { ..request, slot_cid: request.slot_cid, }
  let installation = structured_capability_fixture_installation()
  let configuration =
    #|{"adapter_kind":"portable-http","api_mode":"chat-completions","credential_ref":"file:original.secret","endpoint":"https://models.example/v1/structured","model_id":"fixture-http","provider_id":"models/fixture","selector":"fixture-chat"}
  let binding = @publication_host.issue_client_model_provider_binding(
    "models/fixture", "{}", "{}", configuration,
  ).unwrap()
  let profile_wire =
    #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"1","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":null},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":20000,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://models.example/v1/structured","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:e3e456f4e1d5246eaf227870f1031185241d2d004922efc2d2e3934068868409","task":{"contract_cid":"sha256:35db189b1ef0b8e41d799f6aa6420dc1acaf572afc290a2e28873e191ed01d4f","input_schema_cid":"sha256:72b560b69347d1b6e7b74fa3ebca73f808d0be12a7cd6b53b3a53da4a3954b2a","kind":"structured_generate","output_schema_cid":"sha256:773858f1a0187020cb634048b5062e82163816ebf568902ff7c89d78ebacd317"},"version":"actql-model-response-profile/0.1"}
  let profile = @environment.read_model_response_profile(
    @utf8.encode(profile_wire),
    "sha256:e3e456f4e1d5246eaf227870f1031185241d2d004922efc2d2e3934068868409",
    { max_bytes: 10000, max_nodes: 1000, max_depth: 30, max_members: 1000, },
    100000,
  ).unwrap()
  let physical = install_async_model_provider("models/fixture").unwrap()
  let selected : ResolvedStructuredModel = {
    selector: "fixture-chat",
    model_id: "fixture-http",
    adapter_kind: "portable-http",
    api_mode: "chat-completions",
    endpoint: installation.endpoint,
  }
  let declared = register_structured_model_capability(
    physical, binding, configuration, selected, profile, true, true,
  ).unwrap()
  let admit = () => {
    admit_structured_model_provider(
      declared,
      selected,
      basis.execution,
      basis.dependencies,
      installation,
      (_, prompt) => {
        @environment.model_openai_chat_instructions(prompt) is Some(_)
      },
    ).unwrap()
  }
  let admitted = admit()
  assert_true(
    model_http_original_credential_reference(admitted, configuration)
    is Some("file:original.secret"),
  )
  let substituted =
    #|{"adapter_kind":"portable-http","api_mode":"chat-completions","credential_ref":"file:replaced.secret","endpoint":"https://models.example/v1/structured","model_id":"fixture-http","provider_id":"models/fixture","selector":"fixture-chat"}
  assert_true(substituted.length() == configuration.length())
  assert_true(
    model_http_original_credential_reference(admitted, substituted) is None,
  )
  let original = prepare_model_http_chat_request(
    admitted, request, installation, 100,
  ).unwrap()
  guard prepared_model_http_chat_material(original, request, admitted)
    is Some((endpoint, actual_profile, body)) else {
    abort("the exact paid projection must be borrowable")
  }
  assert_eq(endpoint, installation.endpoint)
  assert_true(physical_equal(profile, actual_profile))
  assert_eq(body, @utf8.encode(http_chat_expected_wire))
  let foreign = prepare_model_http_chat_request(
    admitted, foreign_request, installation, 100,
  ).unwrap()
  let (_, _, foreign_body) = prepared_model_http_chat_material(
    foreign, foreign_request, admitted,
  ).unwrap()
  assert_eq(foreign_body, body)
  assert_true(
    prepared_model_http_chat_material(foreign, request, admitted) is None,
  )
  assert_true(
    prepared_model_http_chat_material(original, request, admit()) is None,
  )
  let other_endpoint = {
    ..installation,
    endpoint: "https://other.example/v1/structured",
  }
  assert_true(
    prepare_model_http_chat_request(admitted, request, other_endpoint, 100)
    is Err(ForeignRequest),
  )
  let invocations = Ref(0)
  let start = _ => {
    invocations.val += 1
    None
  }
  let quantities : @resources.QuantityAmounts = {
    tokens: 32L,
    cost_units: 0L,
    duration_ms: 1000L,
  }
  let plan = prepared_model_http_chat_plan(
    original, installation, quantities, start,
  ).unwrap()
  assert_true(physical_equal(plan.request, request))
  assert_eq(plan.wire_bytes, body.length().to_int64())
  assert_true(
    plan.invocation is AsynchronousHttpChat(retained, _) &&
    physical_equal(retained, original) &&
    !physical_equal(retained, foreign),
  )
  assert_true(
    prepared_model_http_chat_plan(original, other_endpoint, quantities, start)
    is Err(InvalidProvider),
  )
  assert_true(
    prepared_model_http_chat_plan(
      original,
      installation,
      { ..quantities, tokens: 15L, },
      start,
    )
    is Err(InvalidLimits),
  )
  assert_eq(invocations.val, 0)
  assert_eq(calls(), 0)
}
