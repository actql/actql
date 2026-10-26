///|
fn close_test_library() -> Library {
  load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(256),
  ).unwrap()
}

///|
test "Signature explicit close stops every original Library alias and is idempotent" {
  let original = close_test_library()
  let same_original = original
  assert_true(library_ready_ffi(original))
  original.require_current().unwrap()
  same_original.require_current().unwrap()
  original.close_checked().unwrap()
  assert_false(library_ready_ffi(same_original))
  assert_eq(same_original.require_current(), Err(InvalidInput))
  assert_eq(same_original.diagnostic_ceiling(), None)
  assert_true(same_original.random_bytes(32) is Err(_))
  assert_true(same_original.hmac_sha256(b"key", b"message") is Err(_))
  assert_true(same_original.sha256_hasher() is Err(_))
  assert_true(same_original.generate_ed25519_key_pair() is Err(_))
  same_original.close_checked().unwrap()
  original.close_checked().unwrap()
}

///|
test "Signature close retains the original dynamic handle until every EVP context acknowledges" {
  let original = close_test_library()
  let first = original.sha256_hasher().unwrap()
  let second = original.sha256_hasher().unwrap()
  first.update(b"first").unwrap()
  second.update(b"second").unwrap()
  original.require_current().unwrap()
  assert_eq(original.close_checked(), Err(CleanupPending))
  assert_false(library_ready_ffi(original))
  assert_eq(original.require_current(), Err(InvalidInput))
  assert_true(original.sha256_hasher() is Err(_))
  assert_true(first.update(b"more") is Err(_))
  assert_true(first.finish_hex() is Err(_))
  assert_eq(original.close_checked(), Err(CleanupPending))
  first.close_checked().unwrap()
  first.close_checked().unwrap()
  assert_eq(original.close_checked(), Err(CleanupPending))
  second.close_checked().unwrap()
  original.close_checked().unwrap()
  assert_eq(original.require_current(), Err(InvalidInput))
  second.close_checked().unwrap()
  original.close_checked().unwrap()
}

///|
test "Signature digest completion retires its EVP context while escaped hash aliases remain inert" {
  let original = close_test_library()
  let hash = original.sha256_hasher().unwrap()
  let same_original = hash
  hash.update(b"abc").unwrap()
  assert_eq(
    hash.finish_hex().unwrap(),
    "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
  )
  original.close_checked().unwrap()
  assert_true(same_original.update(b"later") is Err(_))
  assert_true(same_original.finish_hex() is Err(_))
  same_original.close_checked().unwrap()
  original.close_checked().unwrap()
}

///|
test "Signature failed initialization keeps its original diagnostic through empty-context cleanup" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_MISSING_LIBRARY").unwrap()
  let encoded = @utf8.encode(path)
  let original = load_library_ffi(encoded, encoded.length(), 256)
  assert_false(library_ready_ffi(original))
  let primary = library_message(original)
  let hash = sha256_new_ffi(original)
  assert_false(sha256_ready_ffi(hash))
  assert_true(sha256_close_ffi(hash))
  original.close_checked().unwrap()
  assert_eq(library_message(original), primary)
}
