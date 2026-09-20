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
  assert_true(row_limit.close())
  let byte_limit = database
    .stream_query("SELECT repeat('x', 1024)::VARCHAR AS value", 1, 1L, 1, 64)
    .unwrap()
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
