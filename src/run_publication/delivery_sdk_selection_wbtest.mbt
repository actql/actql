///|
// Independent literal normative bytes and hashlib identity. No product output
// generates this oracle; selected metadata remains distinct from permission.
let sdk_read_fixture : String = "{\"connection\":\"local\",\"data_policy_cids\":[\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"],\"formats\":[\"jsonl\"],\"max_bytes\":65536,\"max_uses\":1,\"principal\":\"local-cli\",\"purpose\":\"python-local-read\",\"result_names\":[\"answer\"],\"run_policy_profile_cid\":\"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243\",\"sink\":\"sdk-rows\",\"version\":\"actql-local-sdk-result-read-selection/0.1\"}"

///|
test "SDK read selection preserves independent canonical body and identity" {
  let selected = issue_local_sdk_result_read_selection(
    "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243", "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
  ).unwrap()
  assert_eq(local_sdk_result_read_selection_wire(selected), sdk_read_fixture)
  assert_eq(
    local_sdk_result_read_selection_cid(selected),
    "sha256:13906dcd43b46a467520bf3ea87a8889fd9d04701106b814e85142703e751f27",
  )
  assert_eq(
    local_sdk_result_read_selection_parameters(selected),
    (
      "local-cli",
      "local",
      "python-local-read",
      Some("answer"),
      "jsonl",
      65536,
      1,
    ),
  )
  assert_eq(
    admit_local_sdk_result_read_selection(
      sdk_read_fixture, "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
      "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    ),
    Ok(selected),
  )
}

///|
test "SDK read selection admits only the exact requested original mode" {
  let profile = "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243"
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let named_wire = sdk_read_fixture.replace(
    old="\"result_names\":[\"answer\"]",
    new="\"result_selection\":{\"authority\":\"original_result_read\",\"kind\":\"requested_original_result\"}",
  )
  let named = admit_local_sdk_result_read_selection(named_wire, profile, policy).unwrap()
  let legacy = admit_local_sdk_result_read_selection(
    sdk_read_fixture, profile, policy,
  ).unwrap()
  assert_eq(
    local_sdk_result_read_selection_cid(named),
    "sha256:8e336e72421b0dcf0a561bdad1b880cf5f209176a6c3ab121a96858333025291",
  )
  assert_true(local_sdk_result_read_selection_accepts_name(legacy, "answer"))
  assert_false(
    local_sdk_result_read_selection_accepts_name(legacy, "before_change"),
  )
  assert_true(
    local_sdk_result_read_selection_accepts_name(named, "before_change"),
  )
  assert_false(local_sdk_result_read_selection_accepts_name(named, ""))
  for
    wire in [
      named_wire + " ",
      named_wire.replace(old="requested_original_result", new="all"),
      named_wire.replace(
        old="\"result_selection\"",
        new="\"result_names\":[\"answer\"],\"result_selection\"",
      ),
    ] {
    assert_eq(
      admit_local_sdk_result_read_selection(wire, profile, policy),
      Err(ForeignOriginal),
    )
  }
}

///|
test "SDK read metadata rejects aliases expanded limits expired fields and noncanonical copies" {
  for
    wire in [
      sdk_read_fixture + " ",
      sdk_read_fixture.replace(old="65536", new="65537"),
      sdk_read_fixture.replace(old="\"max_uses\":1", new="\"max_uses\":2"),
      sdk_read_fixture.replace(old="python-local-read", new="cli-read"),
      sdk_read_fixture.replace(old="sdk-rows", new="stdout"),
      sdk_read_fixture.replace(old="jsonl", new="sdk-rows"),
      sdk_read_fixture.replace(old="answer", new="other"),
      sdk_read_fixture.replace(
        old="{",
        new="{\"expires_at\":\"2099-01-01T00:00:00.000Z\",",
      ),
      sdk_read_fixture.replace(old="{", new="{\"principal\":\"local-cli\","),
      "{}",
    ] {
    assert_eq(
      admit_local_sdk_result_read_selection(
        wire, "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
        "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
      ),
      Err(ForeignOriginal),
    )
  }
}

///|
test "SDK read metadata requires exact selected profile and data Policy bindings" {
  assert_eq(
    issue_local_sdk_result_read_selection(
      "public", "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    ),
    Err(InvalidBinding),
  )
  assert_eq(
    issue_local_sdk_result_read_selection(
      "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
      "sha256:" + "A".repeat(64),
    ),
    Err(InvalidBinding),
  )
  assert_eq(
    admit_local_sdk_result_read_selection(
      sdk_read_fixture,
      "sha256:" + "a".repeat(64),
      "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563",
    ),
    Err(ForeignOriginal),
  )
  assert_eq(
    admit_local_sdk_result_read_selection(
      sdk_read_fixture,
      "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
      "sha256:" + "b".repeat(64),
    ),
    Err(ForeignOriginal),
  )
}
