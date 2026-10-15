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

///|
test "non-native caller transaction claim cannot allocate or supply a retained use" {
  let database : Database = { unsupported: (), }
  assert_true(
    database.claim_ordinal_action_in_transaction("grant", "use", 2L)
    is Err(UnsupportedTarget),
  )
}
