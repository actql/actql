///|
// Independent vector: fixed adopted durations and Python hashlib over the
// existing literal dependency bodies. Never produced by the profile writer.
let run_profile_fixture = "{\"available_for_ms\":86400000,\"clock_contract_cid\":\"sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356\",\"delete_after_ms\":172800000,\"effective_data_policy_cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\",\"metadata_after_ms\":604800000,\"metadata_retention_policy_cid\":\"sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095\",\"read_for_ms\":86400000,\"retention_contract_cid\":\"sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a\",\"version\":\"actql-local-run-policy-profile/0.1\"}"

///|
test "finite profile retains adopted durations and exact dependency identity" {
  let common = product_common_test_originals()
  let profile = client_local_run_policy_profile(common).unwrap()
  assert_eq(client_local_run_policy_profile_wire(profile), run_profile_fixture)
  assert_eq(
    client_local_run_policy_profile_cid(profile),
    "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
  )
  assert_eq(
    client_local_run_policy_profile_wire(
      admit_client_local_run_policy_profile(run_profile_fixture, common).unwrap(),
    ),
    run_profile_fixture,
  )
}

///|
test "closed profile refuses implicit renewal extended durations and noncanonical bytes" {
  let common = product_common_test_originals()
  for
    wire in [
      run_profile_fixture + " ",
      run_profile_fixture.replace(old="86400000", new="86400001"),
      run_profile_fixture.replace(old="172800000", new="172800001"),
      run_profile_fixture.replace(old="604800000", new="604800001"),
      run_profile_fixture.replace(old="86400000", new="null"),
      run_profile_fixture.replace(old="{", new="{\"extra\":true,"),
      run_profile_fixture.replace(old="{", new="{\"read_for_ms\":86400000,"),
      " ".repeat(8193),
    ] {
    assert_eq(
      admit_client_local_run_policy_profile(wire, common),
      Err(ForeignProfile),
    )
  }
}

///|
test "profile admission requires real matching Policy and dependency originals" {
  let common = product_common_test_originals()
  for
    changed in [
      { ..common, result_policy: b"{}", },
      { ..common, retention_dependencies: b"[]", },
      { ..common, retention_policy: b"{}", },
      {
        ..common,
        retention_dependencies: @utf8.encode(
          product_common_test_bytes(common.retention_dependencies).replace(
            old="local-clock",
            new="foreign-clock",
          ),
        ),
      },
    ] {
    assert_eq(client_local_run_policy_profile(changed), Err(InvalidOriginal))
  }
}

///|
test "new finite policy uses first acceptance time without extending the old original" {
  let common = product_common_test_originals()
  let original_bytes = common.retention_policy
  let old = @publication.admit_publication_contract(
    "result_retention_policy",
    product_common_test_bytes(original_bytes),
    8192,
    512,
    8,
  ).unwrap()
  let profile = client_local_run_policy_profile(common).unwrap()
  let fresh = issue_client_local_run_retention_policy(
    profile, "2026-10-13T00:00:00.001Z",
  ).unwrap()
  assert_eq(
    @publication.publication_contract_identity(fresh),
    "sha256:3f5d2c8229efd0e4f5b5c641a1d4f0218edfc16b773efb5adab76fd89616420c",
  )
  assert_eq(
    @publication.publication_contract_json(fresh),
    "{\"available_until\":\"2026-10-14T00:00:00.001Z\",\"clock_contract_cid\":\"sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356\",\"delete_by\":\"2026-10-15T00:00:00.001Z\",\"effective_data_policy_cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\",\"effective_retention_policy_cid\":\"sha256:3f5d2c8229efd0e4f5b5c641a1d4f0218edfc16b773efb5adab76fd89616420c\",\"extension_ceiling_at\":\"2026-10-15T00:00:00.001Z\",\"metadata_delete_by\":\"2026-10-20T00:00:00.001Z\",\"metadata_retention_policy_cid\":\"sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095\",\"retention_contract_cid\":\"sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a\",\"version\":\"actql-result-retention-policy/0.1\"}",
  )
  let body = product_asset_value(@publication.publication_contract_json(fresh)).unwrap()
  for
    (field, expected) in [
      ("available_until", "2026-10-14T00:00:00.001Z"),
      ("delete_by", "2026-10-15T00:00:00.001Z"),
      ("extension_ceiling_at", "2026-10-15T00:00:00.001Z"),
      ("metadata_delete_by", "2026-10-20T00:00:00.001Z"),
    ] {
    assert_eq(product_test_text(product_test_field(body, [field])), expected)
  }
  assert_eq(common.retention_policy, original_bytes)
  assert_eq(
    @publication.result_retention_interval_state(
      old, "2026-10-13T00:00:00.001Z",
    ),
    Ok("retention_expired"),
  )
  assert_eq(
    @publication.result_retention_interval_state(
      fresh, "2026-10-14T00:00:00.000Z",
    ),
    Ok("available"),
  )
  assert_eq(
    @publication.result_retention_interval_state(
      fresh, "2026-10-14T00:00:00.001Z",
    ),
    Ok("available"),
  )
  assert_eq(
    @publication.result_retention_interval_state(
      fresh, "2026-10-14T00:00:00.002Z",
    ),
    Ok("retention_expired"),
  )
  assert_eq(
    @publication.result_retention_interval_state(
      fresh, "2026-10-15T00:00:00.001Z",
    ),
    Ok("delete_due"),
  )
  // Native read still uses its separate exclusive deadline. This pure
  // constructor does not establish acceptance, a read grant or restart proof.
}

///|
test "invalid acceptance clocks refuse finite policy construction" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  for
    at in [
      "", "invalid", "2026-02-30T00:00:00.000Z", "9999-12-31T23:59:59.999Z",
    ] {
    assert_true(
      issue_client_local_run_retention_policy(profile, at)
      is Err(InvalidObservationTime),
    )
  }
}

///|
test "retention projection preserves all three selected original bodies and refuses substitutions" {
  let common = product_common_test_originals()
  let profile = client_local_run_policy_profile(common).unwrap()
  let bodies = client_local_run_policy_retention_bodies(
    profile,
    common.retention_dependencies,
  ).unwrap()
  let expected = [
    (
      "retention_contract", "sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a",
    ),
    (
      "metadata_retention_policy", "sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095",
    ),
    (
      "clock_contract", "sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356",
    ),
  ]
  assert_eq(bodies.length(), 3)
  for index, (kind, cid) in expected {
    assert_eq(
      @publication.captured_effect_dependency_body_kind(bodies[index]),
      kind,
    )
    assert_eq(
      @publication.captured_effect_dependency_body_cid(bodies[index]),
      cid,
    )
    let names = [
      "local-result-retention", "local-result-metadata", "local-clock",
    ]
    assert_eq(
      @publication.captured_effect_dependency_body_json(bodies[index]),
      "{\"name\":\"" +
      names[index] +
      "\",\"version\":\"actql-installed-local-policy/0.1\"}",
    )
  }
  for
    changed in [
      b"[]",
      b"{}",
      b"[null,null,null]",
      @utf8.encode(
        product_common_test_bytes(common.retention_dependencies).replace(
          old="local-clock",
          new="foreign-clock",
        ),
      ),
      @utf8.encode(
        product_common_test_bytes(common.retention_dependencies).replace(
          old="clock_contract",
          new="retention_contract",
        ),
      ),
    ] {
    assert_true(
      client_local_run_policy_retention_bodies(profile, changed)
      is Err(InvalidOriginal),
    )
  }
}
