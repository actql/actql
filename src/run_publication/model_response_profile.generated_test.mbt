// Generated independent profile artifact caller fixtures.

///|
test "Profile artifact: non-SDK generation" {
  let body = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86"
  let issued = seal_run_evidence_value(
    "model_response_profile", body, 16384, 1024, 20,
  ).unwrap()
  assert_eq(run_evidence_value_identity(issued), cid)
  assert_eq(run_evidence_value_json(issued), wire)
  let restored = admit_run_evidence_value(
    "model_response_profile", wire, 16384, 1024, 20,
  ).unwrap()
  assert_eq(run_evidence_value_json(restored), wire)
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      " " + wire,
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceInvalidWire),
  )
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      wire.replace(old="codec_revision", new="unregistered_revision"),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceInvalidShape),
  )
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      wire.replace(old="fixture", new="foreign"),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}

///|
test "Profile artifact: SDK native Decision" {
  let body = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"native\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/sdk-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/native-decision\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":{\"interface\":\"v4\",\"lock_artifact_cid\":\"sha256:edc7462f3e63c2e7e6bc4187122b8b23f9de9596dfd348d9e4b302f3bfeb2367\",\"package\":\"@ai-sdk/typesafe-ai\",\"version\":\"3.0.13\"}},\"completion\":{\"basis\":\"native_decision\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/systemone\",\"method\":\"POST\",\"streaming\":false},\"probability\":{\"source\":\"native\",\"validation_profile_cid\":\"sha256:55dae6c0400f1d8da79714cd232f94c2fa05334078f86278244e1c6935ff3e7f\"},\"self_cid\":\"sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b\",\"task\":{\"contract_cid\":\"sha256:def45fa15b898ea3ae17c7920d24ea8c11af6cfc7dee7b5a39ef7566d5e96d4e\",\"input_schema_cid\":\"sha256:3b945d01674c1d9006497d459e110bfde9e836e5686fcca3b6dd1fc7b82f9466\",\"kind\":\"decision\",\"output_schema_cid\":\"sha256:4ce8bfaf60dd4fe01d0f7df2cc73fb8303c9daef9c06adb09e72385be34ff3f9\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:486ad7544b0ada0ed4ae785247956cb8ede31b36281b1c8ee21551b598c5074b"
  let issued = seal_run_evidence_value(
    "model_response_profile", body, 16384, 1024, 20,
  ).unwrap()
  assert_eq(run_evidence_value_identity(issued), cid)
  assert_eq(run_evidence_value_json(issued), wire)
  let restored = admit_run_evidence_value(
    "model_response_profile", wire, 16384, 1024, 20,
  ).unwrap()
  assert_eq(run_evidence_value_json(restored), wire)
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      " " + wire,
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceInvalidWire),
  )
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      wire.replace(old="codec_revision", new="unregistered_revision"),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceInvalidShape),
  )
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      wire.replace(old="fixture", new="foreign"),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}

///|
test "Profile artifact: no raw fields promised" {
  let body = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"1\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:d236befc79294ec339eb84c4c789973205cb9b6275b7a1e61a4a670522051a21\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:d236befc79294ec339eb84c4c789973205cb9b6275b7a1e61a4a670522051a21"
  let issued = seal_run_evidence_value(
    "model_response_profile", body, 16384, 1024, 20,
  ).unwrap()
  assert_eq(run_evidence_value_identity(issued), cid)
  assert_eq(run_evidence_value_json(issued), wire)
  let restored = admit_run_evidence_value(
    "model_response_profile", wire, 16384, 1024, 20,
  ).unwrap()
  assert_eq(run_evidence_value_json(restored), wire)
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      " " + wire,
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceInvalidWire),
  )
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      wire.replace(old="codec_revision", new="unregistered_revision"),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceInvalidShape),
  )
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      wire.replace(old="fixture", new="foreign"),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}

///|
test "Profile artifact: original revision strings" {
  let body = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"é\\r\\ncodec\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let wire = "{\"adapter\":{\"build_artifact_cid\":\"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2\",\"builder_id\":\"fixture/http-builder\",\"builder_revision\":\"1\",\"codec_id\":\"fixture/chat-one\",\"codec_revision\":\"é\\r\\ncodec\",\"port_abi\":\"model-physical-port/1\",\"sdk\":null},\"completion\":{\"basis\":\"generation_finish\",\"endpoint_envelope\":true,\"output_contract\":true,\"transport_eof\":true,\"validator_artifact_cid\":\"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd\",\"validator_id\":\"fixture/chat-envelope\",\"validator_revision\":\"1\"},\"controls\":{\"cache\":false,\"fallback\":false,\"hedging\":false,\"media_fetch\":false,\"model_requests\":1,\"redirect\":false,\"repair\":false,\"retry\":false,\"sdk_telemetry\":false,\"tools\":false,\"workflow_restore\":false},\"limits\":{\"active_slots\":4,\"adapter_holding_bytes\":4096,\"adapter_workspace_bytes\":2048,\"chunk_bytes\":512,\"chunks\":16,\"header_bytes\":256,\"metadata_bytes\":128,\"metadata_depth\":4,\"metadata_nodes\":16,\"parse_depth\":16,\"parse_nodes\":256,\"parse_work\":8192,\"request_bytes\":1024,\"response_bytes\":2048,\"unsettled_slots\":4},\"observations\":[\"provider_request_id\",\"provider_reported_model_id\",\"finish_reason\",\"input_tokens\",\"output_tokens\",\"provider_metadata\"],\"operation\":{\"endpoint\":\"https://fixture.invalid/v1/chat/completions\",\"method\":\"POST\",\"streaming\":false},\"probability\":null,\"self_cid\":\"sha256:af772cb1730918938df3764049352058f8cf6e2ef14c6b3e4b854474b3da2e48\",\"task\":{\"contract_cid\":\"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560\",\"input_schema_cid\":\"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7\",\"kind\":\"structured_generate\",\"output_schema_cid\":\"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3\"},\"version\":\"actql-model-response-profile/0.1\"}"
  let cid = "sha256:af772cb1730918938df3764049352058f8cf6e2ef14c6b3e4b854474b3da2e48"
  let issued = seal_run_evidence_value(
    "model_response_profile", body, 16384, 1024, 20,
  ).unwrap()
  assert_eq(run_evidence_value_identity(issued), cid)
  assert_eq(run_evidence_value_json(issued), wire)
  let restored = admit_run_evidence_value(
    "model_response_profile", wire, 16384, 1024, 20,
  ).unwrap()
  assert_eq(run_evidence_value_json(restored), wire)
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      " " + wire,
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceInvalidWire),
  )
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      wire.replace(old="codec_revision", new="unregistered_revision"),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceInvalidShape),
  )
  assert_true(
    admit_run_evidence_value(
      "model_response_profile",
      wire.replace(old="fixture", new="foreign"),
      16384,
      1024,
      20,
    )
    is Err(RunEvidenceIdentityMismatch),
  )
}
