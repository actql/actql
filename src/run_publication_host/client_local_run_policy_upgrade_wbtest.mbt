///|
// Independent literal metadata bytes and SHA256, not an adopted Host or grant.
let policy_upgrade_old_read = "{\"native\":{\"result_read\":{\"connection\":\"local\",\"data_policy_cids\":[\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"],\"enabled\":true,\"expires_at\":\"2026-10-13T00:00:00.000Z\",\"formats\":[\"csv\",\"json\",\"jsonl\"],\"max_bytes\":65536,\"max_uses\":1,\"principal\":\"local-cli\",\"purpose\":\"cli-read\",\"result_names\":[\"answer\"],\"sink\":\"stdout\"}},\"version\":\"actql-config/0.1\"}"

///|
let policy_upgrade_read = "{\"native\":{\"result_read\":{\"connection\":\"local\",\"data_policy_cids\":[\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"],\"enabled\":true,\"formats\":[\"csv\",\"json\",\"jsonl\"],\"max_bytes\":65536,\"max_uses\":1,\"principal\":\"local-cli\",\"purpose\":\"cli-read\",\"result_names\":[\"answer\"],\"retention_file\":\"keep.json\",\"run_file\":\"work.json\",\"run_policy_profile_cid\":\"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243\",\"sink\":\"stdout\",\"store_file\":\"payload.json\"}},\"version\":\"actql-config/0.1\"}"

///|
let policy_upgrade_fixture = "{\"adoption_cid\":\"sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa\",\"authority_scope_cid\":\"sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb\",\"legacy_admissions_wire\":\"[{\\\"admitted_revision\\\":\\\"3\\\",\\\"request_scope_cid\\\":\\\"sha256:cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc\\\",\\\"run_definition_cid\\\":\\\"sha256:dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd\\\",\\\"submission_reference_cid\\\":\\\"sha256:eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee\\\"}]\",\"operation_id\":\"explicit-upgrade-1\",\"profile_wire\":\"{\\\"available_for_ms\\\":86400000,\\\"clock_contract_cid\\\":\\\"sha256:c2f7278baa9548283e904d1e8b9048efc0a206ecaca397527ec970776a2f2356\\\",\\\"delete_after_ms\\\":172800000,\\\"effective_data_policy_cid\\\":\\\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\\\",\\\"metadata_after_ms\\\":604800000,\\\"metadata_retention_policy_cid\\\":\\\"sha256:dbf36e9f6f9b35881ac625290a1c93dbbe485ee8d954cdac3c55e345df4c3095\\\",\\\"read_for_ms\\\":86400000,\\\"retention_contract_cid\\\":\\\"sha256:a8fb82bdb39b1eb3e6871a55d63f3cb554dcc1953e06501bb686fd8ca8f9646a\\\",\\\"version\\\":\\\"actql-local-run-policy-profile/0.1\\\"}\",\"read_configuration_name\":\"read.json\",\"read_original_cid\":\"sha256:9c9fe45e41f29c9ebaf4ca2a9e518e4f1ea3342c177b7d6522ea5af17cc8c95a\",\"read_selection_wire\":\"{\\\"native\\\":{\\\"result_read\\\":{\\\"connection\\\":\\\"local\\\",\\\"data_policy_cids\\\":[\\\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\\\"],\\\"enabled\\\":true,\\\"formats\\\":[\\\"csv\\\",\\\"json\\\",\\\"jsonl\\\"],\\\"max_bytes\\\":65536,\\\"max_uses\\\":1,\\\"principal\\\":\\\"local-cli\\\",\\\"purpose\\\":\\\"cli-read\\\",\\\"result_names\\\":[\\\"answer\\\"],\\\"retention_file\\\":\\\"keep.json\\\",\\\"run_file\\\":\\\"work.json\\\",\\\"run_policy_profile_cid\\\":\\\"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243\\\",\\\"sink\\\":\\\"stdout\\\",\\\"store_file\\\":\\\"payload.json\\\"}},\\\"version\\\":\\\"actql-config/0.1\\\"}\",\"retention_configuration_cid\":\"sha256:2222222222222222222222222222222222222222222222222222222222222222\",\"retention_configuration_name\":\"keep.json\",\"run_configuration_cid\":\"sha256:1111111111111111111111111111111111111111111111111111111111111111\",\"run_configuration_name\":\"work.json\",\"store_configuration_cid\":\"sha256:3333333333333333333333333333333333333333333333333333333333333333\",\"store_configuration_name\":\"payload.json\",\"version\":\"actql-local-run-policy-upgrade/0.1\"}"

///|
fn policy_upgrade_files() -> Array[(String, String)] {
  [
    (
      "read.json", "sha256:9c9fe45e41f29c9ebaf4ca2a9e518e4f1ea3342c177b7d6522ea5af17cc8c95a",
    ),
    ("work.json", "sha256:" + "1".repeat(64)),
    ("keep.json", "sha256:" + "2".repeat(64)),
    ("payload.json", "sha256:" + "3".repeat(64)),
  ]
}

///|
fn policy_upgrade_legacy() -> Array[ClientLocalLegacyPolicyRun] {
  [
    {
      request_scope_cid: "sha256:" + "c".repeat(64),
      run_definition_cid: "sha256:" + "d".repeat(64),
      submission_reference_cid: "sha256:" + "e".repeat(64),
      admitted_revision: 3L,
    },
  ]
}

///|
fn policy_upgrade_restore(
  body : String,
) -> Result[ClientLocalRunPolicyUpgrade, ClientLocalRunPolicyProfileIssue] {
  admit_client_local_run_policy_upgrade(
    @utf8.encode(body),
    client_local_run_policy_profile(product_common_test_originals()).unwrap(),
    policy_upgrade_old_read,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "explicit-upgrade-1",
    policy_upgrade_files(),
  )
}

///|
test "explicit upgrade binds exact original roles and legacy facts without renewing old read" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  let original = bind_client_local_run_policy_upgrade(
    profile,
    policy_upgrade_old_read,
    "sha256:" + "a".repeat(64),
    "sha256:" + "b".repeat(64),
    "explicit-upgrade-1",
    policy_upgrade_files(),
    policy_upgrade_legacy(),
  ).unwrap()
  assert_eq(
    client_local_run_policy_upgrade_body(original),
    @utf8.encode(policy_upgrade_fixture),
  )
  assert_eq(
    product_cid(policy_upgrade_fixture),
    "sha256:50ea4cfc8971b947f7e988bf525f637606bc19a92b88078c8e368374085df4e1",
  )
  assert_eq(
    client_local_run_policy_upgrade_read_wire(original),
    policy_upgrade_read,
  )
  assert_eq(
    product_cid(policy_upgrade_read),
    "sha256:c03a2f30d887f6d5797b4e005bf4c4ad8e962c937cae28bde377a23647c05bb9",
  )
  let restored = policy_upgrade_restore(policy_upgrade_fixture).unwrap()
  assert_eq(
    client_local_run_policy_upgrade_body(restored),
    client_local_run_policy_upgrade_body(original),
  )
  assert_eq(
    client_local_run_policy_upgrade_legacy_runs(restored),
    policy_upgrade_legacy(),
  )
  // Mutating a returned collection cannot change the opaque saved original.
  let exposed = client_local_run_policy_upgrade_legacy_runs(restored)
  exposed.clear()
  assert_eq(
    client_local_run_policy_upgrade_legacy_runs(restored),
    policy_upgrade_legacy(),
  )
  assert_true(policy_upgrade_old_read.contains("2026-10-13T00:00:00.000Z"))
  assert_false(policy_upgrade_read.contains("expires_at"))
}

///|
test "upgrade restore rejects wrong original identity role operation and noncanonical body" {
  for
    (old, replacement) in [
      ("sha256:" + "a".repeat(64), "sha256:" + "0".repeat(64)),
      ("sha256:" + "b".repeat(64), "sha256:" + "0".repeat(64)),
      ("explicit-upgrade-1", "explicit-upgrade-2"),
      ("work.json", "foreign.json"),
      ("86400000", "86400001"),
      ("actql-local-run-policy-upgrade/0.1", "foreign"),
    ] {
    assert_true(
      policy_upgrade_restore(
        policy_upgrade_fixture.replace(old~, new=replacement),
      )
      is Err(_),
    )
  }
  for
    wire in [
      policy_upgrade_fixture + " ",
      "{}",
      " ".repeat(8193),
      policy_upgrade_fixture.replace(old="{", new="{\"extra\":\"x\","),
      policy_upgrade_fixture.replace(
        old="{",
        new="{\"operation_id\":\"other\",",
      ),
    ] {
    assert_true(policy_upgrade_restore(wire) is Err(_))
  }
}

///|
test "upgrade construction rejects duplicate facts invalid roles and original read substitution" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  let bind = (files, legacy) => {
    bind_client_local_run_policy_upgrade(
      profile,
      policy_upgrade_old_read,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "explicit-upgrade-1",
      files,
      legacy,
    )
  }
  let files = policy_upgrade_files()
  files[1] = files[0]
  assert_true(bind(files, policy_upgrade_legacy()) is Err(_))
  let files = policy_upgrade_files()
  files[0] = ("read.json", "sha256:" + "0".repeat(64))
  assert_true(bind(files, policy_upgrade_legacy()) is Err(_))
  let legacy = policy_upgrade_legacy()
  legacy.push(legacy[0])
  assert_true(bind(policy_upgrade_files(), legacy) is Err(_))
  let legacy = policy_upgrade_legacy()
  legacy[0] = { ..legacy[0], admitted_revision: -1L, }
  assert_true(bind(policy_upgrade_files(), legacy) is Err(_))
  for name in ["", "../work.json", "work/name", "n".repeat(129)] {
    let files = policy_upgrade_files()
    files[1] = (name, files[1].1)
    assert_true(bind(files, policy_upgrade_legacy()) is Err(_))
  }
  let legacy = policy_upgrade_legacy()
  for _ in 0..<8 {
    legacy.push(legacy[0])
  }
  assert_true(bind(policy_upgrade_files(), legacy) is Err(_))
}

///|
test "read lifetime alternative preserves exact Unicode CR LF and string values" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  for value in ["e\u{0301}", "é", "a\r\nb\rc\n", "item"] {
    let wire = policy_upgrade_old_read.replace(old="cli-read", new=value)
    // Control characters are encoded using the value codec, not normalized.
    let writer = @encode.writer(128, 4, 2) catch { _ => abort("writer") }
    @encode.string_value(writer, value) catch {
      _ => abort("string")
    }
    let literal = @encode.finish(writer) catch { _ => abort("finish") }
    let wire = if value.contains("\r") || value.contains("\n") {
      policy_upgrade_old_read.replace(old="\"cli-read\"", new=literal)
    } else {
      wire
    }
    let finite = client_local_finite_read_selection_wire(
      wire, profile, "work.json", "keep.json", "payload.json",
    ).unwrap()
    let root = product_asset_value(finite).unwrap()
    assert_eq(
      product_test_text(
        product_test_field(root, ["native", "result_read", "purpose"]),
      ),
      value,
    )
  }
  assert_true(
    client_local_finite_read_selection_wire(
      policy_upgrade_read, profile, "work.json", "keep.json", "payload.json",
    )
    is Err(_),
  )
}

///|
test "legacy facts have one canonical correspondence independent of input order" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  let first = policy_upgrade_legacy()[0]
  let second = {
    ..first,
    request_scope_cid: "sha256:" + "f".repeat(64),
    admitted_revision: 4L,
  }
  let bind = records => {
    bind_client_local_run_policy_upgrade(
      profile,
      policy_upgrade_old_read,
      "sha256:" + "a".repeat(64),
      "sha256:" + "b".repeat(64),
      "explicit-upgrade-1",
      policy_upgrade_files(),
      records,
    )
  }
  let forward = bind([first, second]).unwrap()
  let reversed = bind([second, first]).unwrap()
  assert_eq(
    client_local_run_policy_upgrade_body(forward),
    client_local_run_policy_upgrade_body(reversed),
  )
  assert_eq(client_local_run_policy_upgrade_legacy_runs(reversed), [
    first, second,
  ])
  let restored = policy_upgrade_restore(
    @utf8.decode(client_local_run_policy_upgrade_body(reversed)),
  ).unwrap()
  assert_eq(client_local_run_policy_upgrade_legacy_runs(restored), [
    first, second,
  ])
}

///|
test "finite read conversion preserves the explicit accepted Run selector and rejects mixed alternatives" {
  let profile = client_local_run_policy_profile(product_common_test_originals()).unwrap()
  let literal = "\"data_policy_cids\":[\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"]"
  let selected = policy_upgrade_old_read.replace(
    old=literal,
    new="\"accepted_run_policy\":true",
  )
  let finite = client_local_finite_read_selection_wire(
    selected, profile, "work.json", "keep.json", "payload.json",
  ).unwrap()
  assert_eq(
    finite,
    policy_upgrade_read
    .replace(old=literal + ",", new="")
    .replace(
      old="{\"connection\":",
      new="{\"accepted_run_policy\":true,\"connection\":",
    ),
  )
  for
    replacement in [
      "\"accepted_run_policy\":false",
      "\"accepted_run_policy\":null",
      "\"accepted_run_policy\":true," + literal,
      "\"unknown_policy\":true",
    ] {
    assert_true(
      client_local_finite_read_selection_wire(
        policy_upgrade_old_read.replace(old=literal, new=replacement),
        profile,
        "work.json",
        "keep.json",
        "payload.json",
      )
      is Err(InvalidOriginal),
    )
  }
}
