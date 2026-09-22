///|
fn admitted_payload(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 1000,
      max_nodes: 4,
      max_depth: 1,
    }).unwrap(),
    {
      max_nodes: 4,
      max_depth: 1,
      max_string_bytes: 1000,
      max_total_string_bytes: 1000,
    },
  ).unwrap()
}

///|
test "native bridge binds Connector-admitted parameters without reinterpretation" {
  guard @env.get_env_var("ACTQL_TEST_DUCKDB_LIBRARY") is Some(path) else {
    return
  }
  let database = @native_duckdb.load_library(path)
    .unwrap()
    .open_database(@native_duckdb.restricted_open_limits(134217728L))
    .unwrap()
  let query = database
    .prepare_stream_query(
      "SELECT ?::DOUBLE AS number, ?::VARCHAR AS text", 2, 1L, 1, 256,
    )
    .unwrap()
  let number = @admitted.admit(
    @contract.primitive(@contract.NumberType, nullable=false),
    admitted_payload("1.5"),
    { max_nodes: 1, max_depth: 0, max_text_bytes: 32, },
  ).unwrap()
  let text = @admitted.admit(
    @contract.primitive(@contract.StringType, nullable=false),
    admitted_payload("\"日本語\""),
    { max_nodes: 1, max_depth: 0, max_text_bytes: 32, },
  ).unwrap()
  bind_native_parameter(
    query,
    0,
    @duckdb.prepare_physical_parameter(number).unwrap(),
  ).unwrap()
  bind_native_parameter(
    query,
    1,
    @duckdb.prepare_physical_parameter(text).unwrap(),
  ).unwrap()
  query.execute().unwrap()
  assert_eq(
    query.next().unwrap(),
    Some({
      row_count: 1,
      columns_json: "[[\"3ff8000000000000\"],[\"日本語\"]]",
    }),
  )
  assert_eq(query.next().unwrap(), None)
  assert_true(query.close())
  database.close()
}
