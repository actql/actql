///|
test "signature verification is explicitly unsupported off native" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_CRYPTO_LIBRARY"))
  guard load_library("libcrypto") is Err(UnsupportedTarget) else {
    fail("unsupported signature target loaded a crypto library")
  }
}
