///|
fn diagnostic_origin_store(
  name : String,
  database_ceiling : Int?,
  signature_ceiling : Int?,
) -> NativeRuntimeBundleStore {
  let parent = @env.get_env_var("ACTQL_TEST_NATIVE_RUNTIME_BUNDLE_ROOT").unwrap()
  let root = @filesystem.open_root(parent).unwrap()
  root.create_directory(name).unwrap() |> ignore
  root.close().unwrap()
  let sqlite = @sqlite.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY").unwrap(),
    diagnostic_ceiling=database_ceiling,
  ).unwrap()
  let crypto = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=signature_ceiling,
  ).unwrap()
  open_runtime_bundle_store_with_custody(
    sqlite,
    crypto,
    parent + "/" + name,
    native_bundle_authorities(),
    "aarch64-apple-darwin",
    22L,
    8,
    8,
    1048576L,
  ).unwrap()
}

///|
test "Store diagnostic budget follows the original Database and Signature Library" {
  let store = diagnostic_origin_store("bounded-diagnostics", Some(73), Some(91))
  let original = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_true(store.diagnostics_bounded_by(91))
  assert_true(store.diagnostics_bounded_by(92))
  assert_false(store.diagnostics_bounded_by(90))
  assert_false(store.diagnostics_bounded_by(73))
  assert_false(store.diagnostics_bounded_by(0))
  assert_false(store.diagnostics_bounded_by(-1))
  // A separate Library choice cannot reconfigure the Store's original pair.
  let other = @signature.load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(1),
  ).unwrap()
  assert_true(other.diagnostic_ceiling() is Some(1))
  assert_false(store.diagnostics_bounded_by(73))
  assert_true(store.diagnostics_bounded_by(91))
  store.retiring = true
  assert_false(store.diagnostics_bounded_by(91))
  store.retiring = false
  let after = store.database.read("runtime_bundle", "catalog").unwrap()
  assert_eq(after.revision, original.revision)
  assert_eq(after.body, original.body)
  store.close_checked().unwrap()
  assert_false(store.diagnostics_bounded_by(91))
  assert_true(store.database.diagnostic_ceiling() is Some(73))
}

///|
test "Store legacy diagnostic omission is not repaired by a later positive budget" {
  let legacy_database = diagnostic_origin_store(
    "legacy-database-diagnostics",
    None,
    Some(91),
  )
  assert_false(legacy_database.diagnostics_bounded_by(91))
  assert_false(legacy_database.diagnostics_bounded_by(2147483647))
  assert_true(legacy_database.database.diagnostic_ceiling() is None)
  legacy_database.close_checked().unwrap()
  let legacy_signature = diagnostic_origin_store(
    "legacy-signature-diagnostics",
    Some(73),
    None,
  )
  assert_false(legacy_signature.diagnostics_bounded_by(91))
  assert_false(legacy_signature.diagnostics_bounded_by(2147483647))
  assert_true(legacy_signature.signature_library.diagnostic_ceiling() is None)
  legacy_signature.close_checked().unwrap()
}
