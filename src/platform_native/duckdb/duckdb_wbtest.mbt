///|
test "native DuckDB loader rejects a missing library" {
  guard load_library("/actql/missing/libduckdb") is Err(LibraryLoad(_)) else {
    fail("missing native DuckDB library was accepted")
  }
}

///|
test "native DuckDB executes through the selected C API library" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let library = load_library(path).unwrap()
  assert_true(library.version().has_prefix("v"))
  let database = library.open_database().unwrap()
  guard database.query_i64("select 42::bigint") is Ok(42L) else {
    fail("native DuckDB scalar result did not match")
  }
  guard database.query_i64("select 1, 2") is Err(Query(_)) else {
    fail("non-scalar result was accepted")
  }
  database.close()
  database.close()
  guard database.query_i64("select 1") is Err(Query(_)) else {
    fail("closed database accepted a query")
  }
}

///|
test "native DuckDB exposes an exact transaction boundary" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let database = load_library(path).unwrap().open_database().unwrap()
  database.begin_transaction().unwrap()
  assert_true(database.begin_transaction() is Err(Query(_)))
  assert_eq(database.query_i64("SELECT 42::BIGINT"), Ok(42L))
  database.commit_transaction().unwrap()
  assert_true(database.commit_transaction() is Err(Query(_)))
  database.begin_transaction().unwrap()
  database.rollback_transaction().unwrap()
  assert_true(database.rollback_transaction() is Err(Query(_)))
  database.close()
}

///|
test "native DuckDB streams bounded physical column batches" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let database = load_library(path).unwrap().open_database().unwrap()
  let query = database
    .stream_query(
      "SELECT * FROM (VALUES " +
      "(1::INTEGER, 'a'::VARCHAR, 1.5::DOUBLE, true, " +
      "12.34::DECIMAL(4,2)), " +
      "(2::INTEGER, '日本語'::VARCHAR, NULL::DOUBLE, false, " +
      "-0.01::DECIMAL(4,2))) " +
      "AS t(i, s, d, b, amount)",
      5,
      2L,
      1,
      256,
    )
    .unwrap()
  assert_eq(
    query.fields_json().unwrap(),
    "[[\"i\",\"INTEGER\",null,null]," +
    "[\"s\",\"VARCHAR\",null,null]," +
    "[\"d\",\"DOUBLE\",null,null]," +
    "[\"b\",\"BOOLEAN\",null,null]," +
    "[\"amount\",\"DECIMAL\",\"4\",\"2\"]]",
  )
  assert_eq(
    query.next().unwrap(),
    Some({
      row_count: 1,
      columns_json: "[[\"1\"],[\"a\"],[\"3ff8000000000000\"],[true],[\"1234\"]]",
    }),
  )
  assert_eq(
    query.next().unwrap(),
    Some({
      row_count: 1,
      columns_json: "[[\"2\"],[\"日本語\"],[null],[false],[\"-1\"]]",
    }),
  )
  assert_eq(query.next().unwrap(), None)
  assert_true(query.close())
  assert_false(query.close())
  database.close()
}

///|
test "native DuckDB binds exact admitted physical parameters" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let database = load_library(path).unwrap().open_database().unwrap()
  let query = database
    .prepare_stream_query(
      "SELECT ?::BOOLEAN AS b, ?::DOUBLE AS d, ?::VARCHAR AS s, " +
      "?::DECIMAL(38,18) AS amount, ?::DATE AS day, " +
      "?::TIMESTAMPTZ AS instant, ?::INTEGER AS absent",
      7,
      1L,
      1,
      1024,
    )
    .unwrap()
  assert_eq(query.parameter_count(), 7)
  assert_true(query.fields_json() is Err(Query(_)))
  for
    (index, parameter) in [
      (0, BooleanValue(true)),
      (1, DoubleValue(1.5)),
      (2, TextValue("日本語")),
      (3, DecimalValue("99999999999999999999999999999999999999", 38, 18)),
      (4, DateValue(11016)),
      (5, TimestampValue(-1000L)),
      (6, NullValue),
    ] {
    query.bind_parameter(index, parameter).unwrap()
  }
  query.execute().unwrap()
  assert_eq(
    query.fields_json().unwrap(),
    "[[\"b\",\"BOOLEAN\",null,null]," +
    "[\"d\",\"DOUBLE\",null,null]," +
    "[\"s\",\"VARCHAR\",null,null]," +
    "[\"amount\",\"DECIMAL\",\"38\",\"18\"]," +
    "[\"day\",\"DATE\",null,null]," +
    "[\"instant\",\"TIMESTAMP_TZ\",null,null]," +
    "[\"absent\",\"INTEGER\",null,null]]",
  )
  assert_eq(
    query.next().unwrap(),
    Some({
      row_count: 1,
      columns_json: "[[true],[\"3ff8000000000000\"],[\"日本語\"]," +
      "[\"99999999999999999999999999999999999999\"]," +
      "[\"11016\"],[\"-1000\"],[null]]",
    }),
  )
  assert_eq(query.next().unwrap(), None)
  assert_true(query.close())
  database.close()
}

///|
test "native DuckDB rejects incomplete and contradictory parameter binding" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let database = load_library(path).unwrap().open_database().unwrap()
  let incomplete = database
    .prepare_stream_query("SELECT ?::INTEGER", 1, 1L, 1, 128)
    .unwrap()
  assert_true(incomplete.execute() is Err(Query(_)))
  assert_true(incomplete.close())
  let out_of_order = database
    .prepare_stream_query("SELECT ?::INTEGER, ?::INTEGER", 2, 1L, 1, 128)
    .unwrap()
  assert_true(out_of_order.bind_parameter(1, NullValue) is Err(Query(_)))
  assert_true(out_of_order.close())
  let invalid_decimal = database
    .prepare_stream_query("SELECT ?::DECIMAL(4,2)", 1, 1L, 1, 128)
    .unwrap()
  assert_true(
    invalid_decimal.bind_parameter(0, DecimalValue("10000", 4, 2))
    is Err(Query(_)),
  )
  assert_true(invalid_decimal.close())
  database.close()
}

///|
test "native DuckDB rejects physical results before crossing hard bounds" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let database = load_library(path).unwrap().open_database().unwrap()
  assert_true(
    database.stream_query("SELECT 1, 2", 1, 1L, 1, 256) is Err(CapacityExceeded),
  )
  assert_true(database.stream_query("SELECT ?", 1, 1L, 1, 256) is Err(Query(_)))
  assert_true(
    database.stream_query("SELECT [1, 2]", 1, 1L, 1, 256) is Err(Query(_)),
  )
  let row_limit = database
    .stream_query("SELECT * FROM (VALUES (1), (2)) t(i)", 1, 1L, 2, 256)
    .unwrap()
  assert_true(row_limit.next() is Err(CapacityExceeded))
  assert_true(row_limit.next() is Err(CapacityExceeded))
  assert_true(row_limit.close())
  let byte_limit = database
    .stream_query("SELECT repeat('x', 1024)::VARCHAR AS value", 1, 1L, 1, 64)
    .unwrap()
  assert_true(byte_limit.next() is Err(CapacityExceeded))
  assert_true(byte_limit.next() is Err(CapacityExceeded))
  assert_true(byte_limit.close())
  let closing = database
    .stream_query("SELECT 1::INTEGER", 1, 1L, 1, 64)
    .unwrap()
  database.close()
  assert_true(closing.next() is Err(Closed))
  assert_true(closing.close())
  assert_true(database.stream_query("SELECT 1", 1, 1L, 1, 64) is Err(Closed))
}
