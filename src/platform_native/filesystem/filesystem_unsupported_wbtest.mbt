///|
test "non-native targets reject the native filesystem capability" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_STORE_ROOT"))
  guard open_root("") is Err(UnsupportedTarget) else {
    fail("non-native target accepted the native filesystem capability")
  }
}
