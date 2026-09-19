///|
test "non-native targets reject the native SQLite capability" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"))
  guard load_library("") is Err(UnsupportedTarget) else {
    fail("non-native target accepted the native SQLite capability")
  }
}
