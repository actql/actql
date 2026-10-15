///|
test "non-native targets reject the native SQLite capability" {
  ignore(@env.get_env_var("ACTQL_TEST_NATIVE_SQLITE_LIBRARY"))
  guard load_library("") is Err(UnsupportedTarget) else {
    fail("non-native target accepted the native SQLite capability")
  }
}

///|
test "non-native original claim lookup never supplies claim history" {
  let database : Database = { unsupported: (), }
  assert_true(
    database.lookup_claim_ordinal("grant", "original") is Err(UnsupportedTarget),
  )
}
