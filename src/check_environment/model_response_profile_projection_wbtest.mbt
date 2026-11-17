///|
// Independent wire/CID vectors: original portability template with only the
// three pinned public Task/schema identities substituted using Python hashlib.

///|
fn projection_template_0() -> ModelResponseProfile {
  read_model_response_profile(
    @utf8.encode(
      (
        #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"1","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":null},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/v1/chat/completions","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86","task":{"contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","kind":"structured_generate","output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3"},"version":"actql-model-response-profile/0.1"}
      ),
    ),
    "sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86",
    declaration_limits().bodies,
    100000,
  ).unwrap()
}

///|
fn projection_template_1() -> ModelResponseProfile {
  read_model_response_profile(
    @utf8.encode(
      (
        #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"Exact é\r\n","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":{"interface":"v4","lock_artifact_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","package":"@ai-sdk/openai","version":"4.0.91"}},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"\"quoted\"\\revision"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/v1/chat/completions","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:60fb40b49f3d0bea86e58b4dc816d49686db79f054234469394d69728ff8d233","task":{"contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","kind":"structured_generate","output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3"},"version":"actql-model-response-profile/0.1"}
      ),
    ),
    "sha256:60fb40b49f3d0bea86e58b4dc816d49686db79f054234469394d69728ff8d233",
    declaration_limits().bodies,
    100000,
  ).unwrap()
}

///|
fn profile_projection_original() -> NormalizedPublicModelTask {
  let declaration = normalization_declaration(
    ",\"limits\":{\"max_output_tokens\":200}",
  )
  let defaults = default_profile_read(
    handling_configuration(handling_policy_original()),
  )
  let resolved = resolve_model_provider_defaults(
    defaults,
    None,
    Some(200L),
    1000,
  ).unwrap()
  normalize_public_model_task(
    declaration,
    defaults,
    resolved,
    "operator",
    declaration_limits(),
  ).unwrap()
}

///|
test "normalized response profile preserves physical non-SDK fields and independent canonical identity" {
  let original = profile_projection_original()
  let template = projection_template_0()
  let before = normalized_public_model_task_materials(original)
  let (wire, cid) = normalized_public_model_task_response_profile(
    original, template, 10000, 1000, 32, 22000,
  ).unwrap()
  assert_eq(
    cid, "sha256:fad6cfa53e9d26282fdf0402c5c630af6af59c3fe6e9a50b5d09ff2e1525c12a",
  )
  assert_eq(
    wire,
    (
      #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"1","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":null},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/v1/chat/completions","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:fad6cfa53e9d26282fdf0402c5c630af6af59c3fe6e9a50b5d09ff2e1525c12a","task":{"contract_cid":"sha256:e672bc4e7bc042bf5fd95712095c32d902065a876e8bf775bf1741f795bba1bd","input_schema_cid":"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb","kind":"structured_generate","output_schema_cid":"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb"},"version":"actql-model-response-profile/0.1"}
    ),
  )
  let actual = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    declaration_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(actual.installation.endpoint, template.installation.endpoint)
  assert_eq(actual.installation.sdk, template.installation.sdk)
  assert_eq(actual.limits, template.limits)
  assert_eq(actual.observations, template.observations)
  assert_eq(actual.task_cid, original.task_cid)
  assert_eq(actual.input_schema_cid, original.declaration.input.cid)
  assert_eq(actual.output_schema_cid, original.declaration.output.cid)
  assert_eq(normalized_public_model_task_materials(original), before)
}

///|
test "normalized response profile preserves physical SDK fields and independent canonical identity" {
  let original = profile_projection_original()
  let template = projection_template_1()
  let before = normalized_public_model_task_materials(original)
  let (wire, cid) = normalized_public_model_task_response_profile(
    original, template, 10000, 1000, 32, 22000,
  ).unwrap()
  assert_eq(
    cid, "sha256:ebea2b76400bcda070dd394a06a31bfda72d8e50796bb82aca6cdb8d5076de71",
  )
  assert_eq(
    wire,
    (
      #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"Exact é\r\n","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":{"interface":"v4","lock_artifact_cid":"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa","package":"@ai-sdk/openai","version":"4.0.91"}},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"\"quoted\"\\revision"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/v1/chat/completions","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:ebea2b76400bcda070dd394a06a31bfda72d8e50796bb82aca6cdb8d5076de71","task":{"contract_cid":"sha256:e672bc4e7bc042bf5fd95712095c32d902065a876e8bf775bf1741f795bba1bd","input_schema_cid":"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb","kind":"structured_generate","output_schema_cid":"sha256:f89257995d800e6fda8e5c4ea89ec10e01702a86253b6ef701930d4be9aac7fb"},"version":"actql-model-response-profile/0.1"}
    ),
  )
  let actual = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    declaration_limits().bodies,
    100000,
  ).unwrap()
  assert_eq(actual.installation.endpoint, template.installation.endpoint)
  assert_eq(actual.installation.sdk, template.installation.sdk)
  assert_eq(actual.limits, template.limits)
  assert_eq(actual.observations, template.observations)
  assert_eq(actual.task_cid, original.task_cid)
  assert_eq(actual.input_schema_cid, original.declaration.input.cid)
  assert_eq(actual.output_schema_cid, original.declaration.output.cid)
  assert_eq(normalized_public_model_task_materials(original), before)
}

///|
test "normalized response profile refuses limits and incompatible Decision without changing originals" {
  let original = profile_projection_original()
  let template = projection_template_0()
  let before = normalized_public_model_task_materials(original)
  for (bytes, nodes, depth) in [(1, 1000, 32), (10000, 1, 32), (10000, 1000, 0)] {
    assert_true(
      normalized_public_model_task_response_profile(
        original, template, bytes, nodes, depth, 22000,
      )
      is Err({ kind: BodyLimit, .. }),
    )
  }
  assert_true(
    normalized_public_model_task_response_profile(
      original, template, 10000, 1000, 32, 21999,
    )
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    normalized_public_model_task_response_profile(
      original, template, -1, 1000, 32, 22000,
    )
    is Err({ kind: InvalidLimits, .. }),
  )
  let decision = read_model_response_profile(
    @utf8.encode(
      (
        #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/sdk-builder","builder_revision":"1","codec_id":"fixture/native-decision","codec_revision":"1","port_abi":"model-physical-port/1","sdk":{"interface":"v4","lock_artifact_cid":"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367","package":"@ai-sdk/typesafe-ai","version":"3.0.13"}},"completion":{"basis":"native_decision","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/systemone","method":"POST","streaming":false},"probability":{"source":"native","validation_profile_cid":"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f"},"self_cid":"sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b","task":{"contract_cid":"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e","input_schema_cid":"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466","kind":"decision","output_schema_cid":"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9"},"version":"actql-model-response-profile/0.1"}
      ),
    ),
    "sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b",
    declaration_limits().bodies,
    100000,
  ).unwrap()
  assert_true(
    normalized_public_model_task_response_profile(
      original, decision, 10000, 1000, 32, 22000,
    )
    is Err({ kind: ReferenceMismatch, .. }),
  )
  assert_eq(normalized_public_model_task_materials(original), before)
  assert_true(
    normalized_public_model_task_response_profile(
      original, template, 10000, 1000, 32, 22000,
    )
    is Ok(_),
  )
}

///|
test "normalized response profile enters the existing full Task and installation binding checker" {
  let original = profile_projection_original()
  let (task_wire, _, _, _) = normalized_public_model_task_materials(original)
  // The existing Environment/Task reader independently admits the emitted
  // Task. No hand-assembled Task token substitutes for that consuming owner.
  let prefix = "{\"command_contracts\":[],\"connector_capabilities\":[],\"connector_catalogs\":[],\"contract_registry\":[],"
  let suffix = "\"host_policy_profile\":{},\"mapping_contracts\":[],\"model_task_contracts\":[" +
    task_wire +
    "],\"schema_snapshots\":[],\"source_views\":[],\"version\":\"actql-check-environment/0.1\"}"
  let environment_cid = "sha256:" + @sha.hex(@utf8.encode(prefix + suffix))
  let environment = read(
    @utf8.encode(
      prefix + "\"evidence_bundle_cid\":\"" + environment_cid + "\"," + suffix,
    ),
    environment_cid,
    declaration_limits().bodies,
  ).unwrap()
  let task = resolve_model_task(
    check_model_tasks(environment, declaration_limits()).unwrap(),
    "model-task:public.opaque",
  ).unwrap()
  let template = projection_template_1()
  let (wire, cid) = normalized_public_model_task_response_profile(
    original, template, 10000, 1000, 32, 22000,
  ).unwrap()
  let profile = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    declaration_limits().bodies,
    100000,
  ).unwrap()
  assert_true(
    check_model_response_profile_binding(
      profile,
      task,
      template.installation,
      None,
    )
    is Ok(_),
  )
  assert_true(
    check_model_response_profile_binding(
      template,
      task,
      template.installation,
      None,
    )
    is Err(ReferenceMismatch),
  )
  let changed = {
    ..template.installation,
    endpoint: "https://other.invalid/v1/chat/completions",
  }
  assert_true(
    check_model_response_profile_binding(profile, task, changed, None)
    is Err(ReferenceMismatch),
  )
}
