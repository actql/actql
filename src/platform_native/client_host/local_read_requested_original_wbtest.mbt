///|
fn requested_original_test_wire() -> String {
  local_read_original_wire
  .replace(
    old="\"result_names\":[\"answer\"]",
    new="\"result_selection\":{\"kind\":\"requested_original_result\"}",
  )
  .replace(
    old="\"expires_at\":\"2026-10-12T00:00:00.000Z\"",
    new="\"run_policy_profile_cid\":\"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243\",\"run_file\":\"run.json\",\"retention_file\":\"retention.json\",\"store_file\":\"store.json\"",
  )
}

///|
test "requested original purpose cannot be used as an unnarrowed finite read selection" {
  let wire = requested_original_test_wire()
  let purpose = admit_native_local_read_purpose(wire).unwrap()
  assert_true(purpose.names is RequestedOriginalResult)
  assert_eq(purpose.max_bytes, 65536)
  assert_eq(purpose.max_uses, 1)
  assert_eq(purpose.purpose, "inspection")
  assert_true(admit_native_local_read_selection(wire) is Err(InvalidOriginal))
  for
    changed in [
      wire.replace(
        old="\"result_selection\":",
        new="\"result_names\":[\"file\"],\"result_selection\":",
      ),
      wire.replace(old="requested_original_result", new="all"),
      wire.replace(
        old="\"kind\":\"requested_original_result\"",
        new="\"kind\":\"requested_original_result\",\"names\":[\"file\"]",
      ),
      local_read_original_wire.replace(
        old="\"result_names\":[\"answer\"]",
        new="\"result_selection\":{\"kind\":\"requested_original_result\"}",
      ),
    ] {
    assert_true(admit_native_local_read_purpose(changed) is Err(_))
  }
}

///|
test "installed original Result authority is a closed selected purpose" {
  let legacy = requested_original_test_wire()
  let marked = legacy.replace(
    old="\"kind\":\"requested_original_result\"",
    new="\"authority\":\"original_result_read\",\"kind\":\"requested_original_result\"",
  )
  let purpose = admit_native_local_read_purpose(marked).unwrap()
  assert_true(purpose.names is RequestedOriginalResultWithAuthority)
  assert_true(admit_native_local_read_selection(marked) is Err(InvalidOriginal))
  assert_true(
    admit_native_local_read_purpose(
      marked.replace(old="original_result_read", new="read_any_result"),
    )
    is Err(InvalidOriginal),
  )
  assert_true(
    purpose.narrow_original("before_change", () => false, (_, _) => true)
    is Err(SelectionMismatch),
  )
  assert_eq(
    purpose
    .narrow_original("before_change", () => true, (_, _) => true)
    .unwrap().result_names,
    ["before_change"],
  )
}

///|
test "requested original narrows to one existing name and preserves finite operator names" {
  let purpose = admit_native_local_read_purpose(requested_original_test_wire()).unwrap()
  let checks = Ref(0)
  let selected = purpose
    .narrow_original(
      "file",
      () => {
        checks.val += 1
        true
      },
      (_, _) => true,
    )
    .unwrap()
  assert_eq(checks.val, 1)
  assert_eq(selected.result_names, ["file"])
  assert_eq(selected.formats, ["jsonl"])
  assert_eq(selected.max_bytes, 65536)
  assert_eq(selected.max_uses, 1)
  assert_eq(selected.principal, "operator")
  assert_eq(selected.connection, "cli")
  assert_eq(selected.purpose, "inspection")
  assert_true(
    purpose.narrow_original("foreign", () => false, (_, _) => true)
    is Err(SelectionMismatch),
  )
  let finite = admit_native_local_read_purpose(local_read_original_wire).unwrap()
  assert_true(
    finite.narrow_original("file", () => true, (_, _) => true)
    is Err(SelectionMismatch),
  )
  assert_eq(
    finite.narrow_original("answer", () => true, (_, _) => true).unwrap().result_names,
    ["answer"],
  )
  for name in ["", "x".repeat(129), "bad\u{0000}name"] {
    assert_true(
      purpose.narrow_original(name, () => true, (_, _) => true)
      is Err(SelectionMismatch),
    )
  }
}

///|
test "requested original finite controls are admitted before the original lookup" {
  let purpose = admit_native_local_read_purpose(requested_original_test_wire()).unwrap()
  let observations = Ref(0)
  // Independent pinned wrapper/backing and tariff:4H*16+10R*8+7W*8=200B.
  assert_eq(
    @execution.preparation_representation_cost({
      record_headers: 4L,
      reference_slots: 10L,
      scalar_words: 7L,
      owned_utf16_units: 0L,
      owned_wire_bytes: 0L,
    }),
    Some(200L),
  )
  assert_true(
    purpose.narrow_original(
      "file",
      () => {
        observations.val += 1
        true
      },
      (r, e) => r <= 199L && e <= 200L,
    )
    is Err(_),
  )
  assert_eq(observations.val, 0)
  let selected = purpose
    .narrow_original(
      "file",
      () => {
        observations.val += 1
        true
      },
      (r, e) => r == 200L && e == 200L,
    )
    .unwrap()
  assert_eq(observations.val, 1)
  assert_eq(selected.result_names, ["file"])
}

///|
test "requested original purpose independent canonical body preserves its complete identity" {
  let wire =
    #|{"native":{"result_read":{"connection":"cli","data_policy_cids":["sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"],"enabled":true,"formats":["jsonl"],"max_bytes":65536,"max_uses":1,"principal":"operator","purpose":"inspection","result_selection":{"kind":"requested_original_result"},"retention_file":"retention.json","run_file":"run.json","run_policy_profile_cid":"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243","sink":"stdout","store_file":"store.json"}},"version":"actql-config/0.1"}
  assert_eq(
    "sha256:" + @sha.hex(@utf8.encode(wire)),
    "sha256:9c2deeb0bce96f7adedf721c204ae410597abf5b68686192dfe3cc2a35ff6148",
  )
  assert_true(
    admit_native_local_read_purpose(wire).unwrap().names
    is RequestedOriginalResult,
  )
  assert_true(admit_native_local_read_selection(wire) is Err(InvalidOriginal))
}
