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
