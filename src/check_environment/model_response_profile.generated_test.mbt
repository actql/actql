// Generated from independently authored physical profile bodies.

///|
test "Response profile: non-SDK generation" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(model_response_profile_identity(admitted), cid)
  assert_eq(model_response_profile_usage(admitted), (1761, 64, 6778))
  let exact : Limits = { ..limits, max_bytes: 1761, max_nodes: 64, }
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 6778) is Ok(_),
  )
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 6777)
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_bytes: exact.max_bytes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_nodes: exact.max_nodes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Response profile: SDK native Decision" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"native\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(model_response_profile_identity(admitted), cid)
  assert_eq(model_response_profile_usage(admitted), (2017, 70, 7778))
  let exact : Limits = { ..limits, max_bytes: 2017, max_nodes: 70, }
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 7778) is Ok(_),
  )
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 7777)
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_bytes: exact.max_bytes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_nodes: exact.max_nodes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Response profile: no raw fields promised" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:d236befc79294ec339eb84c4c789973205cb9b6275b7a1e61a4a670522051a21\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:d236befc79294ec339eb84c4c789973205cb9b6275b7a1e61a4a670522051a21"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(model_response_profile_identity(admitted), cid)
  assert_eq(model_response_profile_usage(admitted), (1644, 58, 6273))
  let exact : Limits = { ..limits, max_bytes: 1644, max_nodes: 58, }
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 6273) is Ok(_),
  )
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 6272)
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_bytes: exact.max_bytes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_nodes: exact.max_nodes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Response profile: estimated declaration is not native Task support" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"estimated\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:168437f82993c17ba1430df085b9a2c5b1ced63b720b92527c79714ebf0d8919\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:168437f82993c17ba1430df085b9a2c5b1ced63b720b92527c79714ebf0d8919"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(model_response_profile_identity(admitted), cid)
  assert_eq(model_response_profile_usage(admitted), (2022, 70, 7798))
  let exact : Limits = { ..limits, max_bytes: 2022, max_nodes: 70, }
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 7798) is Ok(_),
  )
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 7797)
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_bytes: exact.max_bytes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_nodes: exact.max_nodes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Response profile: original revision strings" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"é\\r\\ncodec\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:af772cb1730918938df3764049352058f8cf6e2ef14c6b3e4b854474b3da2e48\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:af772cb1730918938df3764049352058f8cf6e2ef14c6b3e4b854474b3da2e48"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(model_response_profile_identity(admitted), cid)
  assert_eq(model_response_profile_usage(admitted), (1772, 64, 6819))
  let exact : Limits = { ..limits, max_bytes: 1772, max_nodes: 64, }
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 6819) is Ok(_),
  )
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 6818)
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_bytes: exact.max_bytes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_nodes: exact.max_nodes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Response profile: unknown root member" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"extra\":null,\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:9c370e5be93eba5c97df178bec6d24a0e0aced66fe73e0c8537af6ee57281a39\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:9c370e5be93eba5c97df178bec6d24a0e0aced66fe73e0c8537af6ee57281a39"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: unknown version" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:e62974477e4c42fd383571ea266f745c2472c7e4745db170e64cb246f86f5121\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/invalid\"}"
  let cid = "sha256:e62974477e4c42fd383571ea266f745c2472c7e4745db170e64cb246f86f5121"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: missing SDK discriminator" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\"},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:cc7bb3846da7390356aca900b69347214be5e4c7ff0a4d780a3a6e99452ba664\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:cc7bb3846da7390356aca900b69347214be5e4c7ff0a4d780a3a6e99452ba664"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: SDK lock absent" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"native\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:f3f9aa133dbf0f3d759c1eccb50adfa7f4bd9cf2313d7448e94a70d455a70fba\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:f3f9aa133dbf0f3d759c1eccb50adfa7f4bd9cf2313d7448e94a70d455a70fba"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: SDK interface mismatch" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v3\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"native\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:452f75831948038339bec87cc9d320a07c79377cdeeb90d6546358f1487e2a08\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:452f75831948038339bec87cc9d320a07c79377cdeeb90d6546358f1487e2a08"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: unknown adapter field" {
  let wire = "{\"adapter\":{\"authorized\":true,\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:d14810dc231007ab4923b773459cbdc9b28903d0c1b0be9a5d548dda13aceafb\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:d14810dc231007ab4923b773459cbdc9b28903d0c1b0be9a5d548dda13aceafb"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: ABI mismatch" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/invalid\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:37214d34d62996a18f50a66d16f5027300c318dd7a4c8ca7f42a729540ac269f\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:37214d34d62996a18f50a66d16f5027300c318dd7a4c8ca7f42a729540ac269f"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: streaming not supported" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":true},\"probability\":null,\"self_cid\":\"sha256:786412f454fab5505f6f4fbec7642a56bfe522b53411ca5976a69ec74ba7b90e\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:786412f454fab5505f6f4fbec7642a56bfe522b53411ca5976a69ec74ba7b90e"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: operation mismatch" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"GET\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:73abe29a04823727d4a1f2d173c70107ae50116f4adc882654657b0717a7c69e\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:73abe29a04823727d4a1f2d173c70107ae50116f4adc882654657b0717a7c69e"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: missing completion basis" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:0c4b420170b8cfbde332bfa3abb2ae6c9e7329e2f1edf7b961911fab8c272f74\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:0c4b420170b8cfbde332bfa3abb2ae6c9e7329e2f1edf7b961911fab8c272f74"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: metadata cannot replace endpoint validation" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":false,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:0d7b24974dc27a79b805f4359180198cb906b7a4b76b6d3a52a346514ad2ad1b\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:0d7b24974dc27a79b805f4359180198cb906b7a4b76b6d3a52a346514ad2ad1b"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: incomplete transport" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":false,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:48b2d43b782623a1ebfaaf9a102be0541cb1ede3fb638d21d152e1b2df5e2078\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:48b2d43b782623a1ebfaaf9a102be0541cb1ede3fb638d21d152e1b2df5e2078"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: unchecked output" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":false,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:03174d473f2a244d4093de2252d0269ea4c05bad081755f379c1a9f606b5c976\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:03174d473f2a244d4093de2252d0269ea4c05bad081755f379c1a9f606b5c976"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: generation with probabilities" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"native\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:9f62d0868364caeb7b33e2a85abc922630e3bb9f7a3e51912dc5fca63d8d2922\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:9f62d0868364caeb7b33e2a85abc922630e3bb9f7a3e51912dc5fca63d8d2922"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: Decision with missing probabilities" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:1df7f60605f2bea8a6023e22af84e2cc469619ff8563451321117453cadc5f3e\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:1df7f60605f2bea8a6023e22af84e2cc469619ff8563451321117453cadc5f3e"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: native codec with estimated probabilities" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"estimated\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:2cfa7f1f5c422613781a2a462ce8d9c9697603c7011c0386e8186bbd1a6f8c97\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:2cfa7f1f5c422613781a2a462ce8d9c9697603c7011c0386e8186bbd1a6f8c97"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: generation using native completion" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:123e3175777fd9cb5948497008bfffc292332324ddd4f7dd7198ddd3e8295076\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:123e3175777fd9cb5948497008bfffc292332324ddd4f7dd7198ddd3e8295076"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: observations duplicated" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:559de805fd6d1f05c3834d48049e652d87b37e8d9403ea11fb99df70fdbaeb42\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:559de805fd6d1f05c3834d48049e652d87b37e8d9403ea11fb99df70fdbaeb42"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: observations order changed" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_metadata\",\"output_tokens\",\"input_tokens\",\"finish_reason\",\"provider_reported_model_id\",\"provider_request_id\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:2f4b5c79a71abb548be34ef28b800ff6dbc57131783bc422639a6415203fbbbe\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:2f4b5c79a71abb548be34ef28b800ff6dbc57131783bc422639a6415203fbbbe"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: unknown observation" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"sdk_model_default\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:b0492b9b5f74967127e94aa83847993245fc50f7c6246af65af51c9128617f7f\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:b0492b9b5f74967127e94aa83847993245fc50f7c6246af65af51c9128617f7f"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: zero body bound" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":0,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:ad23a213ee3a56d793b14bcbb4af9483bc6fc4af1d86299f7ff51e669feac687\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:ad23a213ee3a56d793b14bcbb4af9483bc6fc4af1d86299f7ff51e669feac687"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: fractional parse bound" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":0.5,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:742d8e8100e7500010d2bae6af4efb246536936b8f2ef7a48f8d6ae71f3b4f53\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:742d8e8100e7500010d2bae6af4efb246536936b8f2ef7a48f8d6ae71f3b4f53"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: unbounded parse" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":2147483648,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:b48e1a78ab80abc7e31150a9ce712bd7599e5a30525b193ee64c48f94fcd9fbb\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:b48e1a78ab80abc7e31150a9ce712bd7599e5a30525b193ee64c48f94fcd9fbb"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: overflowing holding minimum" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":2147483647,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":2147483647,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2147483647,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:bcb0579c81715c9eeae5c987f49a917f5a66a7bc783c6192996bd9daf20df33d\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:bcb0579c81715c9eeae5c987f49a917f5a66a7bc783c6192996bd9daf20df33d"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: unfunded backing minimum" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":2815,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:f2b1737ba234b0685434ab3e7e86a44881819551b79e4c2046e0543ef0bcb523\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:f2b1737ba234b0685434ab3e7e86a44881819551b79e4c2046e0543ef0bcb523"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: exact backing minimum" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":2816,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:6ea1abf6763c4495412a163e04424e68ad130dd203bf1dccc1922b022aa0aad4\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:6ea1abf6763c4495412a163e04424e68ad130dd203bf1dccc1922b022aa0aad4"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  let admitted = value.unwrap()
  assert_eq(model_response_profile_identity(admitted), cid)
  assert_eq(model_response_profile_usage(admitted), (1761, 64, 6778))
  let exact : Limits = { ..limits, max_bytes: 1761, max_nodes: 64, }
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 6778) is Ok(_),
  )
  assert_true(
    read_model_response_profile(@utf8.encode(wire), cid, exact, 6777)
    is Err({ kind: WorkLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_bytes: exact.max_bytes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..exact, max_nodes: exact.max_nodes - 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}

///|
test "Response profile: fifth active slot" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":5,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:0449b6762cb9546a5df67b5008b67e06c06ac421958b441342db89d09dfeac26\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:0449b6762cb9546a5df67b5008b67e06c06ac421958b441342db89d09dfeac26"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: fifth unsettled slot" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":5},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:79f4c1eca6bbc5bec4f1a0a56812fdb7e89a5c54b2b1fb34ced8c88e564e495d\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:79f4c1eca6bbc5bec4f1a0a56812fdb7e89a5c54b2b1fb34ced8c88e564e495d"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: second model request" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":2,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:d94f834ba7348a0142e9559589804ffe200c8a6b29364feb59a899316ce31f13\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:d94f834ba7348a0142e9559589804ffe200c8a6b29364feb59a899316ce31f13"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden retry" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":true,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:7f573eb3d4782594cd717ad37c77ebfe60a2073d758fc7a74ef72f2fcdd9a320\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:7f573eb3d4782594cd717ad37c77ebfe60a2073d758fc7a74ef72f2fcdd9a320"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden fallback" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":true,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:e236a260244ff5ea58b1b8e870474ca80f1e53f1acc419ee54a74fdde6b4dd5a\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:e236a260244ff5ea58b1b8e870474ca80f1e53f1acc419ee54a74fdde6b4dd5a"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden hedging" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":true,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:f6b27f17091e4701f0133a86432b075f137cd1d11504e519b84962daff17c252\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:f6b27f17091e4701f0133a86432b075f137cd1d11504e519b84962daff17c252"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden tools" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":true,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:159e86d0aaf0d5dcf4587930dfea9a749073959d0e0ba6937497461d16e3777e\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:159e86d0aaf0d5dcf4587930dfea9a749073959d0e0ba6937497461d16e3777e"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden repair" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":true,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:f7d9cf7993abc2bea780066ee2067e6f7460a08ebd5a4adedb998a8b7de1aefe\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:f7d9cf7993abc2bea780066ee2067e6f7460a08ebd5a4adedb998a8b7de1aefe"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden cache" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":true,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:dfeefa9b0ec9aa95a3336f8132ec65a778744d26e7ee78ca4d4b4abbd98bf6b6\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:dfeefa9b0ec9aa95a3336f8132ec65a778744d26e7ee78ca4d4b4abbd98bf6b6"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden media_fetch" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":true,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:9b06932b1c52d97f469beb2bef7bd7439716d750529d25a34573815d5568ceb4\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:9b06932b1c52d97f469beb2bef7bd7439716d750529d25a34573815d5568ceb4"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden workflow_restore" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":true},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:4b04c4a4cd30f0daa55e7b1620f2fa555c531981762b8d37ec6577d32d064fc5\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:4b04c4a4cd30f0daa55e7b1620f2fa555c531981762b8d37ec6577d32d064fc5"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden sdk_telemetry" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":true,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:764ffb11c72b78cffd2c361ab5a0ee4b16e7a772469b8f79ae60ae2076a06f39\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:764ffb11c72b78cffd2c361ab5a0ee4b16e7a772469b8f79ae60ae2076a06f39"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
test "Response profile: hidden redirect" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":true,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:26190048bbd3f9b1992d19c10bc120870e7e6ac7041efad299babd7e951d6a61\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:26190048bbd3f9b1992d19c10bc120870e7e6ac7041efad299babd7e951d6a61"
  let limits : Limits = {
    max_bytes: 16384,
    max_nodes: 1024,
    max_depth: 20,
    max_members: 10,
  }
  let value = read_model_response_profile(
    @utf8.encode(wire),
    cid,
    limits,
    100000,
  )
  assert_true(value is Err(_))
}

///|
fn response_profile_fixture(
  wire : String,
  cid : String,
) -> ModelResponseProfile {
  read_model_response_profile(
    @utf8.encode(wire),
    cid,
    model_limits().bodies,
    100000,
  ).unwrap()
}

///|
fn response_profile_generation_installation() -> ModelResponseProfileInstallation {
  {
    builder_id: "fixture/http-builder",
    builder_revision: "1",
    codec_id: "fixture/chat-one",
    codec_revision: "1",
    build_artifact_cid: "sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2",
    endpoint: "https://fixture.invalid/v1/chat/completions",
    validator_id: "fixture/chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: "sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd",
    completion_basis: "generation_finish",
    sdk: None,
    http_method: "POST",
    streaming: false,
  }
}

///|
fn response_profile_native_installation() -> ModelResponseProfileInstallation {
  {
    builder_id: "fixture/sdk-builder",
    builder_revision: "1",
    codec_id: "fixture/native-decision",
    codec_revision: "1",
    build_artifact_cid: "sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2",
    endpoint: "https://fixture.invalid/systemone",
    validator_id: "fixture/chat-envelope",
    validator_revision: "1",
    validator_artifact_cid: "sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd",
    completion_basis: "native_decision",
    sdk: Some({
      version: "3.0.13",
      interface: "v4",
      lock_artifact_cid: "sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367",
      package_name: "@ai-sdk/typesafe-ai",
    }),
    http_method: "POST",
    streaming: false,
  }
}

///|
test "Response profile binds checked Task and exact installation facts without execution" {
  let generation = response_profile_fixture(
    "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}",
    "sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86",
  )
  let tasks = check_model_tasks(
    model_wire([sealed_fixture(model_core(), "contract_cid")]),
    model_limits(),
  ).unwrap()
  let task = resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()
  let installation = response_profile_generation_installation()
  assert_eq(
    check_model_response_profile_binding(generation, task, installation, None),
    Ok(()),
  )
  assert_eq(
    check_model_response_profile_binding(
      generation,
      decision_fixture_task(),
      installation,
      None,
    ),
    Err(ReferenceMismatch),
  )
  assert_eq(
    check_model_response_profile_binding(
      generation,
      task,
      { ..installation, endpoint: "https://foreign.invalid/", },
      None,
    ),
    Err(ReferenceMismatch),
  )
  assert_eq(
    check_model_response_profile_binding(
      generation,
      task,
      { ..installation, http_method: "GET", },
      None,
    ),
    Err(ReferenceMismatch),
  )
  assert_eq(
    check_model_response_profile_binding(
      generation,
      task,
      { ..installation, streaming: true, },
      None,
    ),
    Err(ReferenceMismatch),
  )
  assert_eq(
    check_model_response_profile_binding(
      generation,
      task,
      { ..installation, build_artifact_cid: "sha256:" + "f".repeat(64), },
      None,
    ),
    Err(ReferenceMismatch),
  )
  for
    changed in [
      { ..installation, builder_id: "foreign", },
      { ..installation, builder_revision: "foreign", },
      { ..installation, codec_id: "foreign", },
      { ..installation, codec_revision: "foreign", },
      { ..installation, validator_id: "foreign", },
      { ..installation, validator_revision: "foreign", },
      { ..installation, validator_artifact_cid: "sha256:" + "f".repeat(64), },
      { ..installation, completion_basis: "native_decision", },
    ] {
    assert_eq(
      check_model_response_profile_binding(generation, task, changed, None),
      Err(ReferenceMismatch),
    )
  }
  let native = response_profile_fixture(
    "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"native\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}",
    "sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b",
  )
  let native_installation = response_profile_native_installation()
  let task = decision_fixture_task()
  assert_eq(
    check_model_response_profile_binding(
      native,
      task,
      native_installation,
      Some(initial_jev_decision_profile()),
    ),
    Ok(()),
  )
  assert_eq(
    check_model_response_profile_binding(
      native,
      task,
      native_installation,
      None,
    ),
    Err(ReferenceMismatch),
  )
  let sdk = native_installation.sdk.unwrap()
  assert_eq(
    check_model_response_profile_binding(
      native,
      task,
      {
        ..native_installation,
        sdk: Some({ ..sdk, lock_artifact_cid: "sha256:" + "f".repeat(64), }),
      },
      Some(initial_jev_decision_profile()),
    ),
    Err(ReferenceMismatch),
  )
  for
    changed in [
      None,
      Some({ ..sdk, package_name: "foreign", }),
      Some({ ..sdk, version: "foreign", }),
      Some({ ..sdk, interface: "foreign", }),
    ] {
    assert_eq(
      check_model_response_profile_binding(
        native,
        task,
        { ..native_installation, sdk: changed, },
        Some(initial_jev_decision_profile()),
      ),
      Err(ReferenceMismatch),
    )
  }
  let estimated = response_profile_fixture(
    "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"estimated\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:168437f82993c17ba1430df085b9a2c5b1ced63b720b92527c79714ebf0d8919\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}",
    "sha256:168437f82993c17ba1430df085b9a2c5b1ced63b720b92527c79714ebf0d8919",
  )
  assert_eq(
    check_model_response_profile_binding(
      estimated,
      task,
      { ..native_installation, completion_basis: "generation_finish", },
      Some(initial_jev_decision_profile()),
    ),
    Err(ReferenceMismatch),
  )
  assert_eq(model_response_profile_observation_count(generation), 6)
  assert_eq(
    model_response_profile_observation_at(generation, 5),
    Some("provider_metadata"),
  )
  assert_eq(model_response_profile_observation_at(generation, 6), None)
}

///|
test "Response profile binding: foreign Task CID" {
  let profile = response_profile_fixture(
    "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:7c28c2a0f1897fc6e012430e62ff29de180faba303740193cb95da02ef8edc91\",\"task\":{\"contract_cid\":\"sha256:09b9462be780b51bb33b3cd7199aedb237b148b085f3eaa3aa1377a860873e7b\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}",
    "sha256:7c28c2a0f1897fc6e012430e62ff29de180faba303740193cb95da02ef8edc91",
  )
  let tasks = check_model_tasks(
    model_wire([sealed_fixture(model_core(), "contract_cid")]),
    model_limits(),
  ).unwrap()
  let task = resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()
  assert_eq(
    check_model_response_profile_binding(
      profile,
      task,
      response_profile_generation_installation(),
      None,
    ),
    Err(ReferenceMismatch),
  )
}

///|
test "Response profile binding: foreign input schema" {
  let profile = response_profile_fixture(
    "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:5b4f1a09f079f47252b1f43d82454dac86417d308bb2024b0cff1c107ccdebf6\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:eeac5bf36ed8f26ac4033361c7292476fa3248f1018a5e3ee7185fe674b69ce3\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}",
    "sha256:5b4f1a09f079f47252b1f43d82454dac86417d308bb2024b0cff1c107ccdebf6",
  )
  let tasks = check_model_tasks(
    model_wire([sealed_fixture(model_core(), "contract_cid")]),
    model_limits(),
  ).unwrap()
  let task = resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()
  assert_eq(
    check_model_response_profile_binding(
      profile,
      task,
      response_profile_generation_installation(),
      None,
    ),
    Err(InputSchemaMismatch),
  )
}

///|
test "Response profile binding: foreign output schema" {
  let profile = response_profile_fixture(
    "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:b1cf718a752699709a5af19eef8e08612b4d365a4522cdc576a5fe02f05325da\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:e8f6a51e4a8d79cf2c59638f8c3ac867b9711436d5a4e6c89538ea6e033c64e3\"},\"version\":\"actql-model-response-profile/0.1\"}",
    "sha256:b1cf718a752699709a5af19eef8e08612b4d365a4522cdc576a5fe02f05325da",
  )
  let tasks = check_model_tasks(
    model_wire([sealed_fixture(model_core(), "contract_cid")]),
    model_limits(),
  ).unwrap()
  let task = resolve_model_task(tasks, "model-task:risk-score.v1").unwrap()
  assert_eq(
    check_model_response_profile_binding(
      profile,
      task,
      response_profile_generation_installation(),
      None,
    ),
    Err(OutputSchemaMismatch),
  )
}

///|
test "Response profile rejects changed reference, self, body and noncanonical bytes" {
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86"
  let limits = model_limits().bodies
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      "sha256:" + "f".repeat(64),
      limits,
      100000,
    )
    is Err({ kind: IdentityMismatch, .. }),
  )
  let foreign = "sha256:" + "f".repeat(64)
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire.replace(old=cid, new=foreign)),
      foreign,
      limits,
      100000,
    )
    is Err({ kind: IdentityMismatch, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire.replace(old="chat-one", new="chat-two")),
      cid,
      limits,
      100000,
    )
    is Err({ kind: IdentityMismatch, .. }),
  )
  assert_true(
    read_model_response_profile(@utf8.encode(" " + wire), cid, limits, 100000)
    is Err({ kind: InvalidBody, .. }),
  )
  assert_true(
    read_model_response_profile(
      @utf8.encode(wire),
      cid,
      { ..limits, max_depth: 1, },
      100000,
    )
    is Err({ kind: BodyLimit, .. }),
  )
}
