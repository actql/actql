///|
test "native HTTPS client is explicit on unsupported targets" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_HTTP_LIBRARY"))
  guard load_library("libcurl") is Err(UnsupportedTarget) else {
    fail("unsupported HTTPS client was accepted")
  }
}

///|
test "HTTP custody loader keeps unsupported and explicit invalid-ceiling refusal before acquisition" {
  assert_true(
    load_library_with_custody("libcurl")
    is Err(RefusedBeforeAcquisition(UnsupportedTarget)),
  )
  assert_true(
    load_library_with_custody("libcurl", diagnostic_ceiling=Some(0))
    is Err(RefusedBeforeAcquisition(InvalidConfiguration)),
  )
}
