///|
test "non-native targets reject the native DuckDB capability" {
  ignore(@env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY"))
  guard load_library("") is Err(UnsupportedTarget) else {
    fail("non-native target accepted the native DuckDB capability")
  }
}
