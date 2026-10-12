///|
// Matching-target definitions only until the physical diagnostic runs. These
// do not establish installed-109 custody, current package or migration success.
fn runtime_binding_test_originals() -> Array[(String, Bytes)] {
  @host.client_local_product_originals(
    "/fixture",
    "/fixture/sqlite",
    "/fixture/crypto",
    "2026-10-12T00:00:00.000Z",
    @host.client_local_product_assets(),
  ).unwrap()
}

///|
test "Native runtime assets use the complete retained original not the 8K Policy view" {
  let originals = runtime_binding_test_originals()
  let run = originals.iter().find_first(pair => pair.0 == "run.json").unwrap().1
  let environment = originals
    .iter()
    .find_first(pair => pair.0 == "environment.json")
    .unwrap().1
  let assets = local_runtime_original_assets(environment, run).unwrap()
  let expected = @host.client_local_product_assets()
  assert_eq(assets.environment, expected.environment)
  assert_eq(assets.registry, expected.registry)
  assert_eq(assets.values, expected.values)
  assert_eq(assets.fragment, expected.fragment)
  assert_eq(assets.ordered, expected.ordered)
  assert_eq(assets.result_policy, expected.result_policy)
}

///|
test "Native runtime asset projection refuses duplicate unknown and missing members" {
  let originals = runtime_binding_test_originals()
  let run = originals.iter().find_first(pair => pair.0 == "run.json").unwrap().1
  let wire = @utf8.decode(run)
  for
    changed in [
      wire.replace(old="\"version\":", new="\"unknown\":0,\"version\":"),
      wire.replace(
        old="\"version\":",
        new="\"version\":\"actql-config/0.1\",\"version\":",
      ),
      wire.replace(old="\"registry\":", new="\"missing_registry\":"),
    ] {
    assert_true(
      local_runtime_original_assets(b"{}", @utf8.encode(changed))
      is Err(CustodyLost),
    )
  }
  assert_true(
    local_runtime_original_assets(b"{}", b"{}").map(_ => 0) is Err(CustodyLost),
  )
}

///|
test "Native runtime package refuses missing observations and closes an empty projection once" {
  let missing : NativeLocalPackagedRuntime = {
    manifest: None,
    assets: None,
    roots: [],
    witnesses: [],
    reader: None,
    sqlite: "",
    crypto: "",
    ready: false,
    closed: false,
  }
  assert_true(missing.check_current() is Err(Changed))
  assert_true(missing.assets() is Err(Changed))
  assert_true(missing.library_paths() is Err(Changed))
  missing.close().unwrap()
  missing.close().unwrap()
  assert_true(missing.closed)
  assert_true(missing.manifest() is Err(Changed))
}

///|
test "Native runtime context rejects noncanonical paths before filesystem open" {
  for
    path in [
      "relative", "/root/", "/root//child", "/root/../child", "/root/./child", "/root\u{0000}",
    ] {
    assert_true(
      open_native_local_packaged_runtime(
        path,
        "a".repeat(40),
        "darwin-arm64",
        "b".repeat(64),
      )
      is Err(Refused(InvalidInput)),
    )
  }
}
