///|
// Independent exact metadata bytes; epoch/adoption/read placeholders do not
// assert physical authentication, current authorization or acceptance.
let local_run_policy_packet_fixture = "{\"host_adoption_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"issued_at\":\"2026-10-13T00:00:00.001Z\",\"profile_wire\":\"{\\\"available_for_ms\\\":86400000,\\\"clock_contract_cid\\\":\\\"sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356\\\",\\\"delete_after_ms\\\":172800000,\\\"effective_data_policy_cid\\\":\\\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\\\",\\\"metadata_after_ms\\\":604800000,\\\"metadata_retention_policy_cid\\\":\\\"sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095\\\",\\\"read_for_ms\\\":86400000,\\\"retention_contract_cid\\\":\\\"sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a\\\",\\\"version\\\":\\\"actql-local-run-policy-profile/0.1\\\"}\",\"read_selection_cid\":\"sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff\",\"request_wire\":\"{\\\"authority_scope_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"caller_input_intent_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"caller_request_id\\\":\\\"sha256:60829347a8a67a0290d02e6fc991daaec4bb8097d27c611bd9f6c572ba293267\\\",\\\"intent_fingerprint_cid\\\":\\\"sha256:585c858537f5e7ec79a326a54e2891d2c3fc83c2dac4047e1b63f648d9d8f010\\\",\\\"logical_request_scope_cid\\\":\\\"sha256:47ab54e0ad7e0cd507d36d08e498278f40061b8cb9bdfc49ffa8e4d5f23c1918\\\",\\\"parameter_values_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"program_definition_cid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\"}\",\"retention_policy_wire\":\"{\\\"available_until\\\":\\\"2026-10-14T00:00:00.001Z\\\",\\\"clock_contract_cid\\\":\\\"sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356\\\",\\\"delete_by\\\":\\\"2026-10-15T00:00:00.001Z\\\",\\\"effective_data_policy_cid\\\":\\\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\\\",\\\"effective_retention_policy_cid\\\":\\\"sha256:3f5d2c8229efd0e4f5b5c641a1d4f0218edfc16b773efb5adab76fd89616420c\\\",\\\"extension_ceiling_at\\\":\\\"2026-10-15T00:00:00.001Z\\\",\\\"metadata_delete_by\\\":\\\"2026-10-20T00:00:00.001Z\\\",\\\"metadata_retention_policy_cid\\\":\\\"sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095\\\",\\\"retention_contract_cid\\\":\\\"sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a\\\",\\\"version\\\":\\\"actql-result-retention-policy/0.1\\\"}\",\"run_definition_cid\":\"sha256:2e7a5d58eeb58ee7b8a68e5858883f03f702e9a0632828cdb81e00010c582bad\",\"submission_reference_wire\":\"{\\\"epoch\\\":{\\\"authenticator\\\":\\\"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"authorityScopeCid\\\":\\\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"epochNonce\\\":\\\"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\\\",\\\"expiresAt\\\":2000,\\\"notBefore\\\":1000,\\\"version\\\":\\\"actql-submission-epoch/0.1\\\"},\\\"nonce\\\":\\\"original-submit\\\"}\",\"version\":\"actql-local-run-policy-original/0.1\"}"

///|
fn local_run_policy_packet_definition() -> @publication.PublicationContract {
  @publication.admit_publication_contract(
    "run_definition", "{\"authorization_context_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"compiled_plan_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"created_at\":\"2026-10-13T00:00:00.001Z\",\"input_artifact_set_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"invocation_template_cid\":\"sha256:6666666666666666666666666666666666666666666666666666666666666666\",\"run_definition_cid\":\"sha256:2e7a5d58eeb58ee7b8a68e5858883f03f702e9a0632828cdb81e00010c582bad\",\"run_id\":\"run\",\"scope_id\":\"scope\",\"valid_until\":\"2026-10-14T00:00:00.001Z\",\"version\":\"actql-run-definition/0.1\"}",
    8192, 512, 8,
  ).unwrap()
}

///|
fn local_run_policy_packet_request() -> ClientRequestIdentity {
  decode_client_submitted_journal_row(@utf8.encode(saved_submission_ready)).unwrap().run_admission.unwrap().0
}

///|
fn local_run_policy_packet_reference() -> ClientSubmissionReferenceRecord {
  decode_client_submitted_journal_row(@utf8.encode(saved_submission_ready)).unwrap().reference
}

///|
test "original finite policy packet binds exact Submission Run adoption and read original" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  let definition = local_run_policy_packet_definition()
  let original = bind_client_local_run_policy_original(
    profile,
    local_run_policy_packet_reference(),
    local_run_policy_packet_request(),
    definition,
    issue_client_local_run_retention_policy(profile, "2026-10-13T00:00:00.001Z").unwrap(),
    "2026-10-13T00:00:00.001Z",
    "sha256:" + "a".repeat(64),
    "sha256:" + "f".repeat(64),
  ).unwrap()
  assert_eq(
    client_local_run_policy_original_body(original),
    @utf8.encode(local_run_policy_packet_fixture),
  )
  assert_eq(
    product_cid(local_run_policy_packet_fixture),
    "sha256:24d9f490b5dbb2a3db3cf499badfb521fa7d4f0ce6806ef84e97b21e38639014",
  )
  let restored = admit_client_local_run_policy_original(
    client_local_run_policy_original_body(original),
    profile,
    local_run_policy_packet_reference(),
    local_run_policy_packet_request(),
    definition,
    "sha256:" + "a".repeat(64),
    "sha256:" + "f".repeat(64),
  ).unwrap()
  assert_eq(
    client_local_run_policy_original_read_expires_at(restored),
    "2026-10-14T00:00:00.001Z",
  )
  assert_eq(
    client_local_run_policy_original_body(restored),
    client_local_run_policy_original_body(original),
  )
  assert_eq(
    @publication.publication_contract_json(
      client_local_run_policy_original_retention(restored),
    ),
    @publication.publication_contract_json(
      client_local_run_policy_original_retention(original),
    ),
  )
}

///|
test "saved policy packet rejects changed issuance identity and missing originals" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  for
    wire in [
      local_run_policy_packet_fixture + " ",
      local_run_policy_packet_fixture.replace(old="{", new="{\"extra\":true,"),
      local_run_policy_packet_fixture.replace(
        old="{",
        new="{\"issued_at\":\"other\",",
      ),
      local_run_policy_packet_fixture.replace(
        old="2026-10-13T00:00:00.001Z",
        new="2026-10-14T00:00:00.001Z",
      ),
      local_run_policy_packet_fixture.replace(
        old="sha256:" + "a".repeat(64),
        new="sha256:" + "0".repeat(64),
      ),
      local_run_policy_packet_fixture.replace(
        old="sha256:" + "f".repeat(64),
        new="sha256:" + "0".repeat(64),
      ),
      local_run_policy_packet_fixture.replace(
        old="original-submit",
        new="foreign-submit",
      ),
      "{}",
      " ".repeat(8193),
    ] {
    assert_true(
      admit_client_local_run_policy_original(
        @utf8.encode(wire),
        profile,
        local_run_policy_packet_reference(),
        local_run_policy_packet_request(),
        local_run_policy_packet_definition(),
        "sha256:" + "a".repeat(64),
        "sha256:" + "f".repeat(64),
      )
      is Err(_),
    )
  }
}

///|
test "packet cannot substitute a foreign request Run or finite policy window" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  for
    request in [
      admit_client_request_identity_record_wire(saved_submission_other_request).unwrap(),
      admit_client_request_identity_record_wire(saved_submission_scope_request).unwrap(),
    ] {
    assert_true(
      bind_client_local_run_policy_original(
        profile,
        local_run_policy_packet_reference(),
        request,
        local_run_policy_packet_definition(),
        issue_client_local_run_retention_policy(
          profile, "2026-10-13T00:00:00.001Z",
        ).unwrap(),
        "2026-10-13T00:00:00.001Z",
        "sha256:" + "a".repeat(64),
        "sha256:" + "f".repeat(64),
      )
      is Err(_),
    )
  }
  assert_true(
    bind_client_local_run_policy_original(
      profile,
      local_run_policy_packet_reference(),
      local_run_policy_packet_request(),
      saved_submission_definition(),
      issue_client_local_run_retention_policy(
        profile, "2026-10-13T00:00:00.001Z",
      ).unwrap(),
      "2026-10-13T00:00:00.001Z",
      "sha256:" + "a".repeat(64),
      "sha256:" + "f".repeat(64),
    )
    is Err(_),
  )
  assert_true(
    bind_client_local_run_policy_original(
      profile,
      local_run_policy_packet_reference(),
      local_run_policy_packet_request(),
      local_run_policy_packet_definition(),
      issue_client_local_run_retention_policy(
        profile, "2026-10-14T00:00:00.001Z",
      ).unwrap(),
      "2026-10-13T00:00:00.001Z",
      "sha256:" + "a".repeat(64),
      "sha256:" + "f".repeat(64),
    )
    is Err(_),
  )
}

///|
test "journal packet shape checks Run correspondence without authenticating selection" {
  let request = local_run_policy_packet_request()
  let definition = local_run_policy_packet_definition()
  assert_eq(
    validate_client_local_run_policy_original_run(
      @utf8.encode(local_run_policy_packet_fixture),
      request,
      definition,
    ),
    Ok(()),
  )
  let foreign_adoption = local_run_policy_packet_fixture.replace(
    old="sha256:" + "a".repeat(64),
    new="sha256:" + "0".repeat(64),
  )
  // Inventory shape admission returns Unit, not authenticated original custody.
  assert_eq(
    validate_client_local_run_policy_original_run(
      @utf8.encode(foreign_adoption),
      request,
      definition,
    ),
    Ok(()),
  )
  assert_true(
    admit_client_local_run_policy_original(
      @utf8.encode(foreign_adoption),
      client_local_run_policy_profile(product_common_test_originals()).unwrap(),
      local_run_policy_packet_reference(),
      request,
      definition,
      "sha256:" + "a".repeat(64),
      "sha256:" + "f".repeat(64),
    )
    is Err(_),
  )
  for
    wire in [
      local_run_policy_packet_fixture.replace(
        old="original-submit",
        new="other-submit",
      ),
      local_run_policy_packet_fixture.replace(
        old="2026-10-13T00:00:00.001Z",
        new="2026-10-14T00:00:00.001Z",
      ),
      local_run_policy_packet_fixture.replace(old="86400000", new="86400001"),
      local_run_policy_packet_fixture + " ",
      "{}",
    ] {
    assert_true(
      validate_client_local_run_policy_original_run(
        @utf8.encode(wire),
        request,
        definition,
      )
      is Err(_),
    )
  }
  assert_true(
    validate_client_local_run_policy_original_run(
      @utf8.encode(local_run_policy_packet_fixture),
      admit_client_request_identity_record_wire(saved_submission_scope_request).unwrap(),
      definition,
    )
    is Err(_),
  )
  assert_true(
    validate_client_local_run_policy_original_run(
      @utf8.encode(local_run_policy_packet_fixture),
      request,
      saved_submission_definition(),
    )
    is Err(_),
  )
}
