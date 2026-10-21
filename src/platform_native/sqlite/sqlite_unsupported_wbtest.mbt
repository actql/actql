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

///|
test "non-native bounded readbacks cannot supply journal rows" {
  let database : Database = { unsupported: (), }
  assert_true(
    database.read_with_body_limit("original", "input", 8L)
    is Err(UnsupportedTarget),
  )
  assert_true(
    database.scan_after_with_body_limit("original", "", 8L)
    is Err(UnsupportedTarget),
  )
}

///|
test "non-native caller capacity release supplies no transaction or cleanup fact" {
  let database : Database = { unsupported: (), }
  assert_true(
    database.release_capacity_in_transaction("original", "one", 8L, 1L)
    is Err(UnsupportedTarget),
  )
}

///|
test "non-native metadata supplies neither original reservation nor database totals" {
  let database : Database = { unsupported: (), }
  assert_true(
    database.read_capacity("original", "one") is Err(UnsupportedTarget),
  )
  assert_true(database.database_usage() is Err(UnsupportedTarget))
  assert_true(database.client_read_evidence_schema() is Err(UnsupportedTarget))
  assert_true(
    database.install_client_read_evidence_schema(1L) is Err(UnsupportedTarget),
  )
  assert_true(
    database.client_read_evidence_usage("original", 64L, 65536L)
    is Err(UnsupportedTarget),
  )
}

///|
test "non-native snapshot cannot supply a row header or begin a transaction" {
  let database : Database = { unsupported: (), }
  assert_true(database.read_header("original", "one") is Err(UnsupportedTarget))
  assert_true(database.begin_deferred() is Err(UnsupportedTarget))
}

///|
test "fenced lookup snapshot refuses unsupported target without issuing a child" {
  let database : Database = { unsupported: (), }
  assert_true(database.prepare_lookup_read() is Err(UnsupportedTarget))
}
