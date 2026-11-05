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
    installed_contracts: None,
    roots: [],
    directories: [],
    witnesses: [],
    reader: None,
    reader_open_failure: None,
    root_open_failure: None,
    original_read: None,
    original_resources: None,
    command_preparation: false,
    selection: None,
    product: None,
    read_scope_entered: false,
    sqlite: "",
    crypto: "",
    command_sqlite_member: None,
    command_crypto_member: None,
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

///|
// The diagnostic adapter supplies private roots and the authored invalid
// manifests before syscall injection. These are real Reader Owner calls with
// injected errors, not observed kernel EIO faults.
fn runtime_binding_constructor_fixture(name : String) -> String {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_CUSTODY_ROOT").unwrap()
  parent + "/" + name
}

///|
test "Native runtime constructor retains rejected Reader cleanup and the original issue" {
  let path = runtime_binding_constructor_fixture("runtime-constructor-pending")
  let opened = open_native_local_packaged_runtime(
    path,
    "a".repeat(40),
    "darwin-arm64",
    "b".repeat(64),
  )
  guard opened is Err(Pending(runtime, Physical(Read(original)))) else {
    fail("rejected Reader cleanup was discarded or acknowledged")
  }
  assert_true(original.has_prefix("inspect committed file"))
  let failure = runtime.reader_open_failure.unwrap()
  assert_true(failure.issue() is Read(message) && message == original)
  assert_true(runtime.reader is None)
  assert_eq(runtime.roots.length(), 1)
  assert_true(runtime.check_current() is Err(Changed))
  assert_true(runtime.assets() is Err(Changed))
  assert_true(runtime.close() is Err(CleanupPending))
  assert_true(physical_equal(runtime.reader_open_failure.unwrap(), failure))
  assert_false(runtime.closed)
  // The injected close retired the descriptor before reporting EIO. Reusing
  // a descriptor for a new Writer must not let repeated cleanup close it.
  let writer = runtime.roots[0].create_writer("reuse.stage", 3L).unwrap()
  assert_true(runtime.close() is Err(CleanupPending))
  assert_true(physical_equal(runtime.reader_open_failure.unwrap(), failure))
  writer.append(b"abc").unwrap()
  writer.seal("reuse.object").unwrap() |> ignore
  writer.cancel().unwrap()
  assert_true(failure.issue() is Read(message) && message == original)
  assert_eq(runtime.roots.length(), 1)
  assert_false(runtime.closed)
}

///|
test "Native runtime constructor acknowledges successful rejected Reader cleanup" {
  let path = runtime_binding_constructor_fixture("runtime-constructor-acked")
  let opened = open_native_local_packaged_runtime(
    path,
    "a".repeat(40),
    "darwin-arm64",
    "b".repeat(64),
  )
  guard opened is Err(Refused(Physical(Read(original)))) else {
    fail("successful cleanup did not preserve the original constructor refusal")
  }
  assert_true(original.has_prefix("inspect committed file"))
}

///|
test "frozen scalar metadata cannot enable historical operational use in this implementation" {
  assert_true(
    require_local_historical_runtime_implementation()
    is Err(UnsupportedPreparation),
  )
}

///|
// This empty projection owns no Root, Read, Library or capacity. Exercise only
// the failure latch: restoring a cheap entry condition cannot revive metadata.
test "failed Runtime observation spends its metadata snapshot" {
  let runtime = local_runtime_empty(None)
  runtime.ready = true
  runtime.read_scope_entered = true
  assert_true(runtime.check_current() is Err(CleanupPending))
  assert_false(runtime.ready)
  runtime.read_scope_entered = false
  assert_true(runtime.library_paths() is Err(Changed))
  assert_true(runtime.assets() is Err(Changed))
  runtime.close().unwrap()
}
