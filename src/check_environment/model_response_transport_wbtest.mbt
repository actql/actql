///|
// Original independent corpus body/CID, not product-derived expected limits.
fn response_transport_test_profile() -> ModelResponseProfile {
  let wire =
    #|{"adapter":{"build_artifact_cid":"sha256:12b1a34ce23743c38303cc50fb4eb040689c50f37c1a594b1382d754a4c578a2","builder_id":"fixture/http-builder","builder_revision":"1","codec_id":"fixture/chat-one","codec_revision":"1","port_abi":"model-physical-port/1","sdk":null},"completion":{"basis":"generation_finish","endpoint_envelope":true,"output_contract":true,"transport_eof":true,"validator_artifact_cid":"sha256:9dde7d7e6c108739d709824371c425f8d26afd8451d470d7477ef2ac8ecffacd","validator_id":"fixture/chat-envelope","validator_revision":"1"},"controls":{"cache":false,"fallback":false,"hedging":false,"media_fetch":false,"model_requests":1,"redirect":false,"repair":false,"retry":false,"sdk_telemetry":false,"tools":false,"workflow_restore":false},"limits":{"active_slots":4,"adapter_holding_bytes":4096,"adapter_workspace_bytes":2048,"chunk_bytes":512,"chunks":16,"header_bytes":256,"metadata_bytes":128,"metadata_depth":4,"metadata_nodes":16,"parse_depth":16,"parse_nodes":256,"parse_work":8192,"request_bytes":1024,"response_bytes":2048,"unsettled_slots":4},"observations":["provider_request_id","provider_reported_model_id","finish_reason","input_tokens","output_tokens","provider_metadata"],"operation":{"endpoint":"https://fixture.invalid/v1/chat/completions","method":"POST","streaming":false},"probability":null,"self_cid":"sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86","task":{"contract_cid":"sha256:cfb4c49389dd5ecbcd97d4b60276549dcf6fd2ce62584707b5c661d94dce4560","input_schema_cid":"sha256:57887e29c270383ae1e005ba3476a81c8b0012a8b566db860c75abba9c786dd7","kind":"structured_generate","output_schema_cid":"sha256:d67003c78c0eb8b7ab0499bbed57bc8d5895c43ed0b3ce27755b656a65fd49f3"},"version":"actql-model-response-profile/0.1"}
  read_model_response_profile(
    @utf8.encode(wire),
    "sha256:e5d56780055a27fdfc4c522d9afb38403887afeae671fb93c4ebee8a872f7d86",
    { max_bytes: 16384, max_nodes: 1024, max_depth: 20, max_members: 10, },
    100000,
  ).unwrap()
}

///|
test "admitted response transport accepts exact and tighter positive acquisition ceilings" {
  let profile = response_transport_test_profile()
  assert_true(
    model_response_profile_transport_matches(profile, 1024, 2048, 512, 16, 256),
  )
  assert_true(
    model_response_profile_transport_matches(profile, 1023, 2047, 511, 15, 255),
  )
  assert_true(model_response_profile_transport_matches(profile, 1, 1, 1, 1, 1))
  assert_eq(model_response_profile_limits(profile).response_bytes, 2048)
}

///|
test "each response transport mismatch refuses without rewriting original profile limits" {
  let profile = response_transport_test_profile()
  let original = [1024, 2048, 512, 16, 256]
  for index in 0..<5 {
    for wrong in [-1, 0, original[index] + 1, 2147483647] {
      let values = original.copy()
      values[index] = wrong
      assert_false(
        model_response_profile_transport_matches(
          profile,
          values[0],
          values[1],
          values[2],
          values[3],
          values[4],
        ),
      )
      assert_true(
        model_response_profile_transport_matches(
          profile,
          original[0],
          original[1],
          original[2],
          original[3],
          original[4],
        ),
      )
    }
  }
}
