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
test "independent model attempt evidence 6" {
  let value = seal_run_evidence_value(
    "model_attempt_accounting", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"cost_units\":null,\"cumulative_work\":23,\"duration_ms\":null,\"input_tokens\":null,\"output_tokens\":null,\"reservation\":{\"cost_units\":7,\"duration_ms\":19,\"tokens\":33},\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"uncertain_wire_bytes\":66536,\"version\":\"actql-model-attempt-accounting/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:5a6d1eaeb0cfd8578eb425fd4a4706b4c472d658f8e48288c3d108073b9dd887",
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
    "sha256:5a6d1eaeb0cfd8578eb425fd4a4706b4c472d658f8e48288c3d108073b9dd887",
  )
}

///|
test "independent model attempt evidence 7" {
  let value = seal_run_evidence_value(
    "model_attempt_accounting", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"cost_units\":null,\"cumulative_work\":23,\"duration_ms\":null,\"input_tokens\":1,\"output_tokens\":2,\"reservation\":{\"cost_units\":7,\"duration_ms\":19,\"tokens\":33},\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"uncertain_wire_bytes\":66536,\"version\":\"actql-model-attempt-accounting/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:2b21c2aa6d74db1db05d7bd7ddcc56a84c46f1ae1115356ed0fd47c6848d0951",
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
    "sha256:2b21c2aa6d74db1db05d7bd7ddcc56a84c46f1ae1115356ed0fd47c6848d0951",
  )
}

///|
test "independent model attempt evidence 8" {
  let value = seal_run_evidence_value(
    "model_attempt_outcome", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"category\":\"contract_violation\",\"failure\":\"budget_exceeded\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attempt-outcome/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:b5738bbd95eaaec73222e004087888fc3231d799410687d031745d6683d13a2d",
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
    "sha256:b5738bbd95eaaec73222e004087888fc3231d799410687d031745d6683d13a2d",
  )
}

///|
test "independent model attempt evidence 9" {
  let value = seal_run_evidence_value(
    "model_attachment_admission", "{\"attachments\":[{\"classification\":\"internal\",\"complete\":true,\"content_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"content_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"egress_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"frames\":null,\"item\":-1,\"media_input_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"media_type\":\"application/pdf\",\"pages\":1,\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"region\":\"fixture-region\",\"role\":\"document\",\"size_bytes\":3,\"transfer_method\":\"inline_bytes\"}],\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attachment-admission/0.1\"}",
    16384, 256, 8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(value),
    "sha256:e24637b4a3c2e152ce2f9af8efff0679856870c5e4f2d4a4239ecae5e963667a",
  )
  let restored = admit_run_evidence_value(
    "model_attachment_admission",
    run_evidence_value_json(value),
    16384,
    256,
    8,
  ).unwrap()
  assert_eq(
    run_evidence_value_identity(restored),
    "sha256:e24637b4a3c2e152ce2f9af8efff0679856870c5e4f2d4a4239ecae5e963667a",
  )
}

///|
test "invalid model attempt evidence model_attempt_accounting 688a91b3" {
  assert_true(
    seal_run_evidence_value(
      "model_attempt_accounting", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"cost_units\":null,\"cumulative_work\":23,\"duration_ms\":null,\"input_tokens\":-1,\"output_tokens\":null,\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"uncertain_wire_bytes\":66536,\"version\":\"actql-model-attempt-accounting/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_call_attempt c5c95c9e" {
  assert_true(
    seal_run_evidence_value(
      "model_call_attempt", "{\"attempt\":0,\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"provider_id\":\"models/fixture\",\"run_definition_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-call-attempt/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attempt_outcome 7127dfab" {
  assert_true(
    seal_run_evidence_value(
      "model_attempt_outcome", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"category\":\"provider_failure\",\"failure\":\"invented\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attempt-outcome/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attempt_accounting 6d30933a" {
  assert_true(
    seal_run_evidence_value(
      "model_attempt_accounting", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"cost_units\":null,\"cumulative_work\":23,\"duration_ms\":null,\"input_tokens\":null,\"output_tokens\":null,\"reservation\":{\"cost_units\":7,\"duration_ms\":19,\"tokens\":-1},\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"uncertain_wire_bytes\":66536,\"version\":\"actql-model-attempt-accounting/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attempt_accounting 7f408008" {
  assert_true(
    seal_run_evidence_value(
      "model_attempt_accounting", "{\"attempt_cid\":\"sha256:3dcf62f77c94893b9a28ab0d955989d8338d92ca74ec193c56b58b597864160c\",\"cost_units\":null,\"cumulative_work\":23,\"duration_ms\":null,\"input_tokens\":null,\"output_tokens\":null,\"reservation\":{\"cost_units\":7,\"tokens\":33},\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"uncertain_wire_bytes\":66536,\"version\":\"actql-model-attempt-accounting/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attachment_admission 772679c4" {
  assert_true(
    seal_run_evidence_value(
      "model_attachment_admission", "{\"attachments\":[],\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attachment-admission/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attachment_admission 556832a1" {
  assert_true(
    seal_run_evidence_value(
      "model_attachment_admission", "{\"attachments\":[{\"classification\":\"internal\",\"complete\":true,\"content_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"content_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"egress_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"frames\":null,\"item\":-2,\"media_input_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"media_type\":\"application/pdf\",\"pages\":1,\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"region\":\"fixture-region\",\"role\":\"document\",\"size_bytes\":3,\"transfer_method\":\"inline_bytes\"}],\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attachment-admission/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attachment_admission 2c616f9c" {
  assert_true(
    seal_run_evidence_value(
      "model_attachment_admission", "{\"attachments\":[{\"classification\":\"internal\",\"complete\":true,\"content_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"content_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"egress_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"frames\":null,\"item\":-1,\"media_input_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"media_type\":\"application/pdf\",\"pages\":1,\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"region\":\"fixture-region\",\"role\":\"document\",\"size_bytes\":-1,\"transfer_method\":\"inline_bytes\"}],\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attachment-admission/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attachment_admission e3f9020d" {
  assert_true(
    seal_run_evidence_value(
      "model_attachment_admission", "{\"attachments\":[{\"classification\":\"internal\",\"complete\":false,\"content_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"content_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"egress_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"frames\":null,\"item\":-1,\"media_input_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"media_type\":\"application/pdf\",\"pages\":1,\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"region\":\"fixture-region\",\"role\":\"document\",\"size_bytes\":3,\"transfer_method\":\"inline_bytes\"}],\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attachment-admission/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attachment_admission c7997fdd" {
  assert_true(
    seal_run_evidence_value(
      "model_attachment_admission", "{\"attachments\":[{\"classification\":\"internal\",\"complete\":true,\"content_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"content_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"egress_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"frames\":null,\"item\":-1,\"media_input_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"media_type\":\"application/pdf\",\"pages\":0,\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"region\":\"fixture-region\",\"role\":\"document\",\"size_bytes\":3,\"transfer_method\":\"inline_bytes\"}],\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attachment-admission/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attachment_admission 8b872333" {
  assert_true(
    seal_run_evidence_value(
      "model_attachment_admission", "{\"attachments\":[{\"classification\":\"internal\",\"complete\":true,\"content_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"content_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"egress_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"frames\":null,\"item\":-1,\"media_input_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"media_type\":\"application/pdf\",\"pages\":1,\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"region\":\"fixture-region\",\"role\":\"document\",\"size_bytes\":3,\"transfer_method\":\"uri\"}],\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attachment-admission/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}

///|
test "invalid model attempt evidence model_attachment_admission b3bbb0dc" {
  assert_true(
    seal_run_evidence_value(
      "model_attachment_admission", "{\"attachments\":[{\"classification\":\"internal\",\"complete\":true,\"content_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"content_ref_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"egress_scope_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"frames\":null,\"item\":-1,\"media_input_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"media_type\":\"application/pdf\",\"pages\":1,\"policy_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"region\":\"fixture-region\",\"role\":\"document\",\"size_bytes\":3,\"transfer_method\":\"inline_bytes\",\"unknown\":true}],\"authority_evidence_cid\":\"sha256:f1c9ce8f0fbef3942dfaa59025898a8843aeecb8e8d3a7d85181f1b399159c6a\",\"fixed_request_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"model_task_cid\":\"sha256:5555555555555555555555555555555555555555555555555555555555555555\",\"slot_cid\":\"sha256:9999999999999999999999999999999999999999999999999999999999999999\",\"version\":\"actql-model-attachment-admission/0.1\"}",
      16384, 256, 8,
    )
    is Err(RunEvidenceInvalidShape),
  )
}
