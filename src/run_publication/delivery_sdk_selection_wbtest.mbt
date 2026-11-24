///|
// Independent literal normative bytes and hashlib identity. No product output
// generates this oracle; selected metadata remains distinct from permission.
let sdk_read_fixture : String =
  #|{"connection":"local","data_policy_cids":["sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"],"formats":["jsonl"],"max_bytes":65536,"max_uses":1,"principal":"local-cli","purpose":"python-local-read","result_selection":{"authority":"original_result_read","kind":"requested_original_result"},"run_policy_profile_cid":"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243","sink":"sdk-rows","version":"actql-local-sdk-result-read-selection/0.1"}

///|
let sdk_worker_read_fixture : String =
  #|{"connection":"local","data_policy_cids":["sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"],"formats":["jsonl"],"max_bytes":65536,"max_uses":1,"principal":"local-cli","purpose":"python-local-read","result_selection":{"authority":"named_result_read","kind":"finite_result_names","names":["answer"]},"run_policy_profile_cid":"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243","sink":"sdk-rows","version":"actql-local-sdk-result-read-selection/0.1"}

///|
test "current SDK scopes preserve their independent canonical bodies and identities" {
  let profile = "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243"
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  for
    (scope, wire, cid, fixed) in [
      (
        RequestedOriginal,
        sdk_read_fixture,
        "sha256:8e336e72421b0dcf0a561bdad1b880cf5f209176a6c3ab121a96858333025291",
        None,
      ),
      (
        WorkerAnswer,
        sdk_worker_read_fixture,
        "sha256:789827ac92735d7d4a21bb287708695dc7d7e2e9ff8bb0b599c35ebb2c797974",
        Some("answer"),
      ),
    ] {
    let selected = issue_local_sdk_result_read_selection(
      profile,
      policy,
      scope~,
    ).unwrap()
    assert_eq(local_sdk_result_read_selection_wire(selected), wire)
    assert_eq(local_sdk_result_read_selection_cid(selected), cid)
    assert_eq(
      local_sdk_result_read_selection_parameters(selected),
      ("local-cli", "local", "python-local-read", fixed, "jsonl", 65536, 1),
    )
    assert_eq(
      admit_local_sdk_result_read_selection(wire, profile, policy),
      Ok(selected),
    )
    assert_true(
      local_sdk_result_read_selection_accepts_name(selected, "answer"),
    )
    assert_eq(
      local_sdk_result_read_selection_accepts_name(selected, "before_change"),
      scope is RequestedOriginal,
    )
    assert_false(local_sdk_result_read_selection_accepts_name(selected, ""))
  }
}

///|
test "SDK selection refuses the retired unmarked form and other scope substitutions" {
  let profile = "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243"
  let policy = "sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"
  let retired =
    #|{"connection":"local","data_policy_cids":["sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563"],"formats":["jsonl"],"max_bytes":65536,"max_uses":1,"principal":"local-cli","purpose":"python-local-read","result_names":["answer"],"run_policy_profile_cid":"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243","sink":"sdk-rows","version":"actql-local-sdk-result-read-selection/0.1"}
  for
    wire in [
      retired,
      sdk_read_fixture + " ",
      sdk_read_fixture.replace(old="requested_original_result", new="all"),
      sdk_read_fixture.replace(
        old="original_result_read",
        new="named_result_read",
      ),
      sdk_worker_read_fixture.replace(old="answer", new="other"),
      sdk_worker_read_fixture.replace(
        old="named_result_read",
        new="original_result_read",
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
