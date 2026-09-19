///|
test "non-native targets reject native publication storage" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"))
  guard @sqlite.load_library("") is Err(@sqlite.UnsupportedTarget) else {
    fail("non-native target accepted the native publication dependency")
  }
}
