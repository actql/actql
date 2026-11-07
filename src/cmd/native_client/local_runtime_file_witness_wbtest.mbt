///|
#borrow(root, name)
extern "C" fn runtime_file_witness_mutate(
  root : @local_filesystem.Root,
  name : Bytes,
  length : Int,
  kind : Int,
) -> Bool = "actql_native_filesystem_test_observation_mutation"

///|
// Existing Filesystem test mutation is deliberately confined to a three-byte
// synthetic regular file. No library body is loaded or used as authority.
fn runtime_file_witness_refuses_mutation(
  fixture : String,
  directory : String,
  filename : String,
  kind : Int,
) -> Unit raise {
  let runtime = runtime_namespace_open(fixture)
  let root = @local_filesystem.open_root(
    runtime_namespace_fixture(fixture) + "/" + directory,
  ).unwrap()
  let before = root.inspect_generation(filename).unwrap().unwrap()
  assert_eq(before.size, 3L)
  let encoded = @utf8.encode(filename)
  assert_true(
    runtime_file_witness_mutate(root, encoded, encoded.length(), kind),
  )
  let after = root.inspect_generation(filename).unwrap().unwrap()
  // The older opened-fd device/inode/size check still matches. It is not an
  // adequate replacement for the original full stat and same Reader checks.
  let old_generation_matches = root.verify_generation(filename, before)
  let current = runtime.check_current()
  let assets = runtime.assets()
  let libraries = runtime.library_paths()
  root.close().unwrap()
  runtime.close().unwrap()
  assert_eq(after, before)
  assert_true(old_generation_matches)
  assert_true(current is Err(Physical(@local_filesystem.GenerationMismatch)))
  // The explicit failed current observation spends this snapshot. Later
  // getters cannot revive it or repeat a new physical observation as authority.
  assert_true(assets is Err(Changed))
  assert_true(libraries is Err(Changed))
}

///|
test "runtime file witnesses retain unchanged full originals through real Reader finish" {
  let runtime = runtime_namespace_open("files-unchanged")
  assert_true(runtime.check_current() is Ok(_))
  assert_eq(runtime.assets().unwrap().environment, "abc")
  assert_eq(runtime.assets().unwrap().result_policy, "abc")
  assert_true(runtime.manifest() is Ok(_))
  runtime.close().unwrap()
  runtime.close().unwrap()
  assert_true(runtime.check_current() is Err(_))
}

///|
test "runtime file witnesses refuse same inode same size sqlite body overwrite" {
  runtime_file_witness_refuses_mutation(
    "files-sqlite-overwrite", "lib", "sqlite.bin", 2,
  )
}

///|
test "runtime file witnesses refuse crypto mode change without changing generation" {
  runtime_file_witness_refuses_mutation(
    "files-crypto-mode", "lib", "crypto.bin", 1,
  )
}

///|
test "runtime file witnesses refuse same size original environment overwrite" {
  runtime_file_witness_refuses_mutation(
    "files-environment-overwrite", "data", "environment.json", 2,
  )
}

///|
test "runtime file witnesses refuse original Result Policy mode change" {
  runtime_file_witness_refuses_mutation(
    "files-policy-mode", "data", "result-policy.json", 1,
  )
}
