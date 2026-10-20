///|
// Independently authored literal, not product output.
let finite_read_selection_fixture = "{\"native\":{\"result_read\":{\"connection\":\"local\",\"data_policy_cids\":[\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"],\"enabled\":true,\"formats\":[\"csv\",\"json\",\"jsonl\"],\"max_bytes\":65536,\"max_uses\":1,\"principal\":\"local-cli\",\"purpose\":\"cli-read\",\"result_names\":[\"answer\"],\"retention_file\":\"retention.json\",\"run_file\":\"run.json\",\"run_policy_profile_cid\":\"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243\",\"sink\":\"stdout\",\"store_file\":\"store.json\"}},\"version\":\"actql-config/0.1\"}"

///|
let finite_material_selection_fixture = "{\"native\":{\"result_read\":{\"connection\":\"local\",\"data_policy_cids\":[\"sha256:470e10d347bfe887c4a91d9f616b01b3e1aba211a2fd2ba20ebf63d136543563\"],\"enabled\":true,\"formats\":[\"json\"],\"max_bytes\":65536,\"max_uses\":1,\"principal\":\"local-cli\",\"purpose\":\"cli-table\",\"result_names\":[\"answer\"],\"retention_file\":\"retention.json\",\"run_file\":\"run.json\",\"run_policy_profile_cid\":\"sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243\",\"sink\":\"material\",\"store_file\":\"store.json\"}},\"version\":\"actql-config/0.1\"}"

///|
test "explicit finite install adds profile within existing selected limits" {
  let originals = client_local_product_finite_originals(
    "/Users/operator/.actql-local",
    "/product/lib/sqlite.dylib",
    "/product/lib/crypto.dylib",
    "2026-10-12T00:00:00.000Z",
    product_test_assets(),
  ).unwrap()
  assert_eq(originals.length(), 9)
  assert_eq(
    product_test_original(originals, "read.json"),
    finite_read_selection_fixture,
  )
  assert_eq(
    product_test_original(originals, "profile.json"),
    run_profile_fixture,
  )
  assert_eq(
    product_test_original(originals, "material-read.json"),
    finite_material_selection_fixture,
  )
  let read = product_asset_value(product_test_original(originals, "read.json")).unwrap()
  let fields = product_test_field(read, ["native", "result_read"])
  assert_eq(
    product_test_text(product_test_field(fields, ["run_policy_profile_cid"])),
    "sha256:1f4fe66d15e3cb0b6e2515d6f3734202d404fabf980c4939e0b41faef5be2243",
  )
  assert_true(@canonical.object_field(fields, "expires_at") is None)
  for
    (role, original) in [
      ("run_file", "run.json"),
      ("retention_file", "retention.json"),
      ("store_file", "store.json"),
    ] {
    assert_eq(product_test_text(product_test_field(fields, [role])), original)
  }
  for
    (key, literal) in [
      ("principal", "local-cli"),
      ("connection", "local"),
      ("purpose", "cli-read"),
      ("sink", "stdout"),
    ] {
    assert_eq(product_test_text(product_test_field(fields, [key])), literal)
  }
  let config = product_asset_value(
    product_test_original(originals, "config.json"),
  ).unwrap()
  assert_eq(
    product_test_text(
      product_test_field(config, ["native", "local", "run_policy_profile_file"]),
    ),
    "profile.json",
  )
  let selected = product_test_field(config, [
    "native", "local", "installation_files",
  ])
  guard selected is @canonical.Array(values) else {
    fail("selected originals missing")
  }
  assert_eq(@canonical.array_count(values), 6)
  let legacy = product_test_originals()
  for
    name in [
      "account.json", "environment.json", "run.json", "retention.json", "store.json",
    ] {
    assert_eq(
      product_test_original(originals, name),
      product_test_original(legacy, name),
    )
  }
  assert_eq(legacy.length(), 7)
  assert_false(legacy.any(value => value.0 == "profile.json"))
  assert_true(
    product_test_original(legacy, "read.json").contains(
      "\"expires_at\":\"2026-10-13T00:00:00.000Z\"",
    ),
  )
}

///|
test "finite install profile is stable across adoption time without renewing originals" {
  let first = client_local_product_finite_originals(
    "/Users/operator/.actql-local",
    "/product/lib/sqlite.dylib",
    "/product/lib/crypto.dylib",
    "2026-10-12T00:00:00.000Z",
    product_test_assets(),
  ).unwrap()
  let second = client_local_product_finite_originals(
    "/Users/operator/.actql-local",
    "/product/lib/sqlite.dylib",
    "/product/lib/crypto.dylib",
    "2026-10-13T00:00:00.001Z",
    product_test_assets(),
  ).unwrap()
  assert_eq(product_test_original(first, "profile.json"), run_profile_fixture)
  assert_eq(product_test_original(second, "profile.json"), run_profile_fixture)
  assert_eq(
    product_test_original(first, "read.json"),
    product_test_original(second, "read.json"),
  )
  assert_true(
    product_test_original(first, "run.json") !=
    product_test_original(second, "run.json"),
  )
  assert_true(
    product_test_original(first, "run.json").contains(
      "2026-10-13T00:00:00.000Z",
    ),
  )
}
