///|
#borrow(root)
extern "C" fn runtime_namespace_replace(root : @local_filesystem.Root) -> Bool = "actql_native_filesystem_test_directory_replacement"

///|
#borrow(root)
extern "C" fn runtime_namespace_mode(
  root : @local_filesystem.Root,
  mode : Int,
) -> Bool = "actql_native_filesystem_test_private_mode"

///|
// Synthetic package files exercise the real Root/Reader and runtime reader.
// No library is loaded, config adopted, resource funded or Run admitted.
fn runtime_namespace_fixture(name : String) -> String raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_NAMESPACE_ROOT")
    is Some(root) else {
    fail("runtime namespace tests require their own original fixture")
  }
  root + "/" + name
}

///|
fn runtime_namespace_open(
  name : String,
) -> @local_host.NativeLocalPackagedRuntime raise {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_NAMESPACE_MANIFEST_SHA256")
    is Some(hash) else {
    fail("runtime namespace tests require the exact input manifest digest")
  }
  @local_host.open_native_local_packaged_runtime(
    runtime_namespace_fixture(name),
    "a".repeat(40),
    "darwin-arm64",
    hash,
  ).unwrap()
}

///|
test "runtime original namespace keeps unchanged directory and file witnesses current" {
  let runtime = runtime_namespace_open("unchanged")
  assert_true(runtime.check_current() is Ok(_))
  assert_true(runtime.manifest() is Ok(_))
  assert_true(runtime.assets() is Ok(_))
  assert_eq(
    runtime.library_paths().unwrap(),
    (
      runtime_namespace_fixture("unchanged") + "/lib/sqlite.bin",
      runtime_namespace_fixture("unchanged") + "/lib/crypto.bin",
    ),
  )
  runtime.close().unwrap()
  runtime.close().unwrap()
  assert_true(runtime.check_current() is Err(_))
}

///|
test "runtime original namespace refuses renamed package while original files remain open" {
  let runtime = runtime_namespace_open("root-replaced")
  let root = @local_filesystem.open_root(
    runtime_namespace_fixture("root-replaced"),
  ).unwrap()
  assert_true(runtime_namespace_replace(root))
  let current = runtime.library_paths()
  root.close().unwrap()
  runtime.close().unwrap()
  assert_true(current is Err(Physical(@local_filesystem.GenerationMismatch)))
}

///|
test "runtime original namespace refuses renamed member directory with unchanged opened files" {
  let runtime = runtime_namespace_open("child-replaced")
  let root = @local_filesystem.open_root(
    runtime_namespace_fixture("child-replaced") + "/data",
  ).unwrap()
  assert_true(runtime_namespace_replace(root))
  // Metadata getters retain immutable DATA; observe the actual original
  // namespace before consuming it, then preserve the spent-snapshot refusal.
  let current = runtime.check_current()
  let assets = runtime.assets()
  root.close().unwrap()
  runtime.close().unwrap()
  assert_true(current is Err(Physical(@local_filesystem.GenerationMismatch)))
  assert_true(assets is Err(Changed))
}

///|
test "runtime original namespace refuses symlink before manifest or member admission" {
  guard @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_NAMESPACE_MANIFEST_SHA256")
    is Some(hash) else {
    fail("runtime namespace tests require the exact input manifest digest")
  }
  let opened = @local_host.open_native_local_packaged_runtime(
    runtime_namespace_fixture("alias"),
    "a".repeat(40),
    "darwin-arm64",
    hash,
  )
  assert_true(
    opened is Err(Refused(Physical(@local_filesystem.GenerationMismatch))),
  )
}

///|
test "runtime original namespace refuses changed original directory mode" {
  let runtime = runtime_namespace_open("mode-changed")
  let root = @local_filesystem.open_root(
    runtime_namespace_fixture("mode-changed") + "/lib",
  ).unwrap()
  assert_true(runtime_namespace_mode(root, 0o750))
  let current = runtime.check_current()
  let manifest = runtime.manifest()
  root.close().unwrap()
  runtime.close().unwrap()
  assert_true(current is Err(Physical(@local_filesystem.GenerationMismatch)))
  assert_true(manifest is Err(Changed))
}
