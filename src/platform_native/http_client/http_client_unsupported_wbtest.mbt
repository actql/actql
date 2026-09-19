///|
test "native HTTPS client is explicit on unsupported targets" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY"))
  guard load_library("libcurl") is Err(UnsupportedTarget) else {
    fail("unsupported HTTPS client was accepted")
  }
}
