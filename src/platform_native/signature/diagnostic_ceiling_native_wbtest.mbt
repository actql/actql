///|
test "Signature explicit diagnostic limit refuses before physical loading" {
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(0)) is Err(InvalidInput),
  )
  assert_true(
    load_library("unused", diagnostic_ceiling=Some(-1)) is Err(InvalidInput),
  )
}

///|
test "Signature original diagnostic ceiling belongs to the same Library" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap()
  let original = load_library(path, diagnostic_ceiling=Some(73)).unwrap()
  let legacy = load_library(path).unwrap()
  let other = load_library(path, diagnostic_ceiling=Some(91)).unwrap()
  assert_eq(original.diagnostic_ceiling(), Some(73))
  assert_eq(legacy.diagnostic_ceiling(), None)
  assert_eq(other.diagnostic_ceiling(), Some(91))
  assert_eq(original.diagnostic_ceiling(), Some(73))
}

///|
test "Signature original diagnostic ceiling is unavailable after failed loading" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_MISSING_LIBRARY").unwrap()
  let encoded = @utf8.encode(path)
  let original = load_library_ffi(encoded, encoded.length(), 73)
  assert_false(library_ready_ffi(original))
  let primary = library_message(original)
  assert_eq(original.diagnostic_ceiling(), None)
  assert_eq(library_message(original), primary)
}
