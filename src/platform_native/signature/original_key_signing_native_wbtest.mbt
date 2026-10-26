///|
test "Native original private-key signing keeps its same physical child and spent attempt" {
  let path = @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap_or_else(() => {
      fail("selected actual Crypto Library is required")
    },
  )
  let directory = @env.get_env_var("ACTQL_TEST_ORIGINAL_SIGNING_ROOT").unwrap_or_else(() => {
      fail("fresh original private-key fixture root is required")
    },
  )
  let root = @filesystem.open_private_root(
    directory,
    diagnostic_ceiling=Some(64),
  ).unwrap()
  let key = root.adopt_private_file_projection("key.pem").unwrap()
  let library = load_library(path, diagnostic_ceiling=Some(64)).unwrap()
  let public_key = @base64.decode(
    "11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo=",
  )
  let original = library
    .prepare_original_key_signing_attempt(key, public_key, b"")
    .unwrap()
  assert_true(original.original_signature() is Err(_))
  assert_eq(original.primary_issue(), None)
  // Independent RFC 8032 test 1, not an expectation emitted by this signer.
  let expected = "5VZDAMNgrHKQhuLMgG6CioSHfx645dl02HPgZSJJAVVfuIIVkKM7rMYeOXAc-bRr0lv18FlbviRlUUFDjnoQCw"
  assert_eq(original.sign_once(), Ok(expected))
  assert_true(original.sign_once() is Err(Signing(_)))
  assert_eq(original.original_signature(), Ok(expected))
  assert_eq(original.primary_issue(), None)
  assert_eq(library.close_checked(), Err(CleanupPending))
  assert_eq(original.close_checked(), Ok(()))
  assert_true(original.original_signature() is Err(_))
  assert_eq(library.close_checked(), Ok(()))
  assert_true(root.close() is Ok(_))
}
