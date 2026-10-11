///|
fn raw_policy_test_body() -> String {
  "{\"available_until\":\"2026-10-12T01:00:00.000Z\",\"clock_contract_cid\":\"sha256:d67d8062754216896c89195ae0552d2f80a725455e6d5da88e3211dff0c06479\",\"delete_by\":\"2026-10-12T02:00:00.000Z\",\"effective_data_policy_cid\":\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\",\"extension_ceiling_at\":\"2026-10-12T02:00:00.000Z\",\"metadata_delete_by\":\"2026-10-12T03:00:00.000Z\",\"metadata_retention_policy_cid\":\"sha256:7a8f73a0a50704a2826e26b5a2d7179dcf9d29acb6d354abbc1885f558c7e895\",\"model_task_cid\":\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\",\"purpose\":\"model_raw_capture\",\"response_profile_cid\":\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\",\"retention_contract_cid\":\"sha256:52b5203f74728093e67d207b2a3c33d0b4b9bc7c10753df1d052eca825cdbc32\",\"run_definition_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"selected_at\":\"2026-10-12T00:00:00.000Z\",\"store_authority_cid\":\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\",\"version\":\"actql-model-raw-capture-policy/0.1\"}"
}

///|
fn raw_policy_test_originals() -> Array[CapturedEffectDependencyBody] {
  let originals = [
    (
      "retention_contract", "raw-retention-fixture", "sha256:52b5203f74728093e67d207b2a3c33d0b4b9bc7c10753df1d052eca825cdbc32",
    ),
    (
      "metadata_retention_policy", "raw-metadata-fixture", "sha256:7a8f73a0a50704a2826e26b5a2d7179dcf9d29acb6d354abbc1885f558c7e895",
    ),
    (
      "clock_contract", "raw-clock-fixture", "sha256:d67d8062754216896c89195ae0552d2f80a725455e6d5da88e3211dff0c06479",
    ),
  ].map(entry => {
    let (kind, name, cid) = entry
    admit_hashed_effect_dependency_body(
      kind,
      cid,
      "{\"name\":\"" +
      name +
      "\",\"version\":\"actql-installed-local-policy/0.1\"}",
      8192,
      128,
      8,
    ).unwrap()
  })
  originals.push(
    admit_captured_effect_dependency_body(
      "data_policy",
      Some(
        "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
      ),
      "{\"classification\":\"unknown\",\"source_data_policy_cids\":[],\"source_response_policy_cids\":[],\"unknown_provenance\":true,\"version\":\"actql-effective-data-policy/0.1\"}",
      8192,
      128,
      8,
    ).unwrap(),
  )
  originals
}

///|
test "raw selection resolves four actual originals without granting capture" {
  let originals = raw_policy_test_originals()
  let policy = seal_run_evidence_value(
    "model_raw_capture_policy",
    raw_policy_test_body(),
    8192,
    128,
    8,
  ).unwrap()
  let bound = bind_model_raw_capture_policy(
    policy,
    originals[0],
    originals[1],
    originals[2],
    originals[3],
  ).unwrap()
  assert_eq(
    model_raw_capture_policy_value(bound).identity,
    "sha256:8c05837fcdaa1233dd221da49e351ab244d929b219a75ff5ed2dc5f1d4f0408c",
  )
  // The typed view retains originals; these names are integrity fixtures,
  // not a Host installation, actual permission or tariff/capture inference.
  assert_eq(bound.retention.node.identity, originals[0].node.identity)
  assert_eq(bound.metadata.node.identity, originals[1].node.identity)
  assert_eq(bound.clock.node.identity, originals[2].node.identity)
  assert_eq(bound.data.node.identity, originals[3].node.identity)
  for changed in 0..<4 {
    let replaced = originals.copy()
    replaced[changed] = originals[(changed + 1) % 4]
    assert_true(
      bind_model_raw_capture_policy(
        policy,
        replaced[0],
        replaced[1],
        replaced[2],
        replaced[3],
      )
      is Err(_),
    )
  }
}

///|
test "raw retention selection refuses rehashed invalid intervals" {
  let originals = raw_policy_test_originals()
  for
    invalid in [
      raw_policy_test_body().replace(
        old="\"selected_at\":\"2026-10-12T00:00",
        new="\"selected_at\":\"2026-10-12T04:00",
      ),
      raw_policy_test_body().replace(
        old="\"extension_ceiling_at\":\"2026-10-12T02:00",
        new="\"extension_ceiling_at\":\"2026-10-12T01:00",
      ),
      raw_policy_test_body().replace(
        old="\"metadata_delete_by\":\"2026-10-12T03:00",
        new="\"metadata_delete_by\":\"2026-10-12T00:00",
      ),
      raw_policy_test_body().replace(
        old="2026-10-12T01:00",
        new="2026-99-12T01:00",
      ),
    ] {
    let policy = seal_run_evidence_value(
      "model_raw_capture_policy", invalid, 8192, 128, 8,
    ).unwrap()
    assert_true(
      bind_model_raw_capture_policy(
        policy,
        originals[0],
        originals[1],
        originals[2],
        originals[3],
      )
      is Err(_),
    )
  }
}
