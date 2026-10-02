// Generated independent model attempt evidence vectors.

///|
test "independent model attempt evidence 0" {
  let value = seal_run_evidence_value(
    "model_dispatch_authority", "{\"account_configuration_cid\":\"sha256:4444444444444444444444444444444444444444444444444444444444444444\",\"answering_authority\":null,\"basis\":\"account_allow\",\"connection\":\"models/fixture\",\"entry_id\":\"model-policy\",\"execution_context_cid\":\"sha256:7777777777777777777777777777777777777777777777777777777777777777\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"host_policy_cid\":\"sha256:8888888888888888888888888888888888888888888888888888888888888888\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"operation\":\"infer\",\"principal\":\"fixture-principal\",\"program_definition_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"resource\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"run_authorization_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"run_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"satisfied_claims\":[],\"version\":\"actql-model-dispatch-authority/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a",
  )
  let restored = admit_run_evidence_value(
    "model_dispatch_authority",
    run_evidence_value_json(value),
    16384,
    256,
    8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a",
  )
}

///|
test "independent model attempt evidence 1" {
  let value = seal_run_evidence_value(
    "model_call_attempt", "{\"attempt\":1,\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"provider_id\":\"models/fixture\",\"run_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-call-attempt/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c",
  )
  let restored = admit_run_evidence_value(
    "model_call_attempt",
    run_evidence_value_json(value),
    16384,
    256,
    8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c",
  )
}

///|
test "independent model attempt evidence 2" {
  let value = seal_run_evidence_value(
    "model_attempt_accounting", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"cost_units\":null,\"cumulative_work\":23,\"duration_ms\":null,\"input_tokens\":null,\"output_tokens\":null,\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"uncertain_wire_bytes\":66536,\"version\":\"actql-model-attempt-accounting/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:ccabd20a0bc525e511c6f022da4e05a054b64e68c64ea7e4789364e9f2987875",
  )
  let restored = admit_run_evidence_value(
    "model_attempt_accounting",
    run_evidence_value_json(value),
    16384,
    256,
    8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:ccabd20a0bc525e511c6f022da4e05a054b64e68c64ea7e4789364e9f2987875",
  )
}

///|
test "independent model attempt evidence 3" {
  let value = seal_run_evidence_value(
    "model_attempt_outcome", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"category\":\"provider_failure\",\"failure\":\"timeout\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attempt-outcome/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:252250c410302b88f632283cdb7de42c8afbcedb84105a0b01c1b3ddc86666d1",
  )
  let restored = admit_run_evidence_value(
    "model_attempt_outcome",
    run_evidence_value_json(value),
    16384,
    256,
    8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:252250c410302b88f632283cdb7de42c8afbcedb84105a0b01c1b3ddc86666d1",
  )
}

///|
test "independent model attempt evidence 4" {
  let value = seal_run_evidence_value(
    "model_attempt_outcome", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"category\":\"cancelled\",\"failure\":\"cancelled\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attempt-outcome/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:e5fca8b0f42cc39cc3bb09f7e8bbb13be343eaed92424a7e9baa895def392148",
  )
  let restored = admit_run_evidence_value(
    "model_attempt_outcome",
    run_evidence_value_json(value),
    16384,
    256,
    8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:e5fca8b0f42cc39cc3bb09f7e8bbb13be343eaed92424a7e9baa895def392148",
  )
}

///|
test "independent model attempt evidence 5" {
  let value = seal_run_evidence_value(
    "model_attempt_accounting", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"cost_units\":null,\"cumulative_work\":23,\"duration_ms\":null,\"input_tokens\":1,\"output_tokens\":2,\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"uncertain_wire_bytes\":66536,\"version\":\"actql-model-attempt-accounting/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:5780758d79752eb86fd36c7ff11f96e7832bb4f91e17aa04c9bacdec7a517ce3",
  )
  let restored = admit_run_evidence_value(
    "model_attempt_accounting",
    run_evidence_value_json(value),
    16384,
    256,
    8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:5780758d79752eb86fd36c7ff11f96e7832bb4f91e17aa04c9bacdec7a517ce3",
  )
}

///|
test "invalid model attempt evidence model_attempt_accounting" {
  assert_true(
    seal_run_evidence_value(
      "model_attempt_accounting", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"cost_units\":null,\"cumulative_work\":23,\"duration_ms\":null,\"input_tokens\":-1,\"output_tokens\":null,\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"uncertain_wire_bytes\":66536,\"version\":\"actql-model-attempt-accounting/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_call_attempt" {
  assert_true(
    seal_run_evidence_value(
      "model_call_attempt", "{\"attempt\":0,\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"provider_id\":\"models/fixture\",\"run_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-call-attempt/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attempt_outcome" {
  assert_true(
    seal_run_evidence_value(
      "model_attempt_outcome", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"category\":\"provider_failure\",\"failure\":\"invented\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attempt-outcome/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}
