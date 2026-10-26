///|
test "original signing owner observation is not an attempt or a returned signature" {
  let library = load_library(
    @env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY").unwrap(),
    diagnostic_ceiling=Some(64),
  ).unwrap()
  let root = @filesystem.open_private_root(
    @env.get_env_var("ACTQL_TEST_ORIGINAL_SIGNING_ROOT").unwrap(),
    diagnostic_ceiling=Some(64),
  ).unwrap()
  let key = root.adopt_private_file_projection("key.pem").unwrap()
  let original = library
    .prepare_original_key_signing_attempt(
      key,
      @base64.decode("11qYAYKxCrfVS/7TyWQHOg7hcvPapiMlrwIaaPcHURo="),
      b"",
    )
    .unwrap()
  original.require_original_owner().unwrap()
  original.require_original_owner().unwrap()
  assert_eq(original.primary_issue(), None)
  assert_true(original.original_signature() is Err(_))
  original.close_checked().unwrap()
  assert_true(original.require_original_owner() is Err(Signing(_)))
  library.close_checked().unwrap()
  assert_true(root.close() is Ok(_))
}
