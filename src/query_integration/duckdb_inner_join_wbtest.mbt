///|
fn native_join_fixture(left : String, right : String) -> @lower.BoundPrepared {
  let value = fn(kind : String, name : String) -> String {
    "{\"values\":{\"schema\":{\"__ordinal\":{\"type\":\"number\",\"nullable\":false},\"k\":" +
    kind +
    ",\"tag\":{\"type\":\"number\",\"nullable\":false}},\"rows\":[]},\"as\":\"" +
    name +
    "\"}"
  }
  let upstream = @pipeline.check(
    input_cursor("[" + value(left, "a") + "," + value(right, "b") + "]"),
    [],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  let receiver = @pipeline.check_with_evidence(
    input_cursor(
      "[{\"join\":{\"with\":\"b\",\"kind\":\"inner\",\"on\":[{\"left\":\"k\",\"right\":\"k\"},{\"left\":\"__ordinal\",\"right\":\"__ordinal\"}],\"select\":{\"l\":\"left.tag\",\"r\":\"right.tag\"}},\"from\":\"a\"}]",
    ),
    [
      (
        "a",
        @pipeline.ProducedInput(
          @pipeline.produced_input(upstream, Step(0)).unwrap(),
        ),
      ),
      (
        "b",
        @pipeline.ProducedInput(
          @pipeline.produced_input(upstream, Step(1)).unwrap(),
        ),
      ),
    ],
    None,
    None,
    {
      max_steps: 10,
      max_work: 100000,
      max_text_bytes: 10000,
      max_nodes: 1000,
      max_tokens: 1000,
      max_depth: 100,
    },
  ).unwrap()
  @lower.bind_parameters(
    @lower.prepare(receiver, {
      max_nodes: 100,
      max_references: 100,
      max_work: 10000,
      max_identifier_bytes: 1000,
    }).unwrap(),
    None,
    max_parameters=0,
    max_name_bytes=0,
  ).unwrap()
}

///|
test "native inner join compiles exact owner ports and bounded collision free SQL" {
  let number = "{\"type\":\"number\",\"nullable\":true}"
  let owner = native_join_fixture(number, number)
  let limits = native_compile_limits()
  let compiled = @duckdb.compile_fixed_inner_join(
    owner,
    "main",
    ["left_rows", "right_rows"],
    limits,
  ).unwrap()
  assert_true(physical_equal(@duckdb.native_inner_join_owner(compiled), owner))
  assert_eq(@duckdb.native_inner_join_input(compiled, true), 0)
  assert_eq(@duckdb.native_inner_join_input(compiled, false), 1)
  assert_eq(
    @lower.inner_join_key_count(@duckdb.native_inner_join_profile(compiled)),
    2,
  )
  let expected = "SELECT l.\"c2\" AS \"l\", r.\"c2\" AS \"r\" FROM (SELECT \"__ordinal\" AS \"c0\", \"k\" AS \"c1\", \"tag\" AS \"c2\", \"__actql_input_ordinal\" AS \"__ordinal\" FROM \"main\".\"left_rows\") AS l INNER JOIN (SELECT \"__ordinal\" AS \"c0\", \"k\" AS \"c1\", \"tag\" AS \"c2\", \"__actql_input_ordinal\" AS \"__ordinal\" FROM \"main\".\"right_rows\") AS r ON l.\"c1\" = r.\"c1\" AND l.\"c0\" = r.\"c0\" ORDER BY l.\"__ordinal\" ASC, r.\"__ordinal\" ASC"
  assert_eq(@duckdb.native_inner_join_sql(compiled), expected)
  assert_true(
    @duckdb.compile_fixed_inner_join(
      owner,
      "main",
      ["left_rows", "right_rows"],
      { ..limits, max_sql_bytes: expected.length(), },
    )
    is Ok(_),
  )
  assert_true(
    @duckdb.compile_fixed_inner_join(
      owner,
      "main",
      ["left_rows", "right_rows"],
      { ..limits, max_sql_bytes: expected.length() - 1, },
    )
    is Err(Limit),
  )
  assert_true(
    @duckdb.compile_fixed_inner_join(owner, "main", ["left_rows"], limits)
    is Err(UnsupportedShape),
  )
  assert_true(
    @duckdb.compile_fixed_inner_join(
      owner,
      "main",
      ["left\u0000", "right_rows"],
      limits,
    )
    is Err(InvalidIdentifier),
  )
}

///|
test "emit real DuckDB composite join SQL fixtures for mapped scalar types" {
  for
    (name, left, right) in [
      (
        "number", "{\"type\":\"number\",\"nullable\":true}", "{\"type\":\"number\",\"nullable\":true}",
      ),
      (
        "text", "{\"type\":\"string\",\"nullable\":true}", "{\"type\":\"string\",\"nullable\":true}",
      ),
      (
        "boolean", "{\"type\":\"boolean\",\"nullable\":true}", "{\"type\":\"boolean\",\"nullable\":true}",
      ),
      (
        "date", "{\"type\":\"date\",\"nullable\":true}", "{\"type\":\"date\",\"nullable\":true}",
      ),
      (
        "timestamp", "{\"type\":\"timestamp\",\"nullable\":true}", "{\"type\":\"timestamp\",\"nullable\":true}",
      ),
      (
        "decimal", "{\"type\":\"decimal\",\"precision\":38,\"scale\":0,\"nullable\":true}",
        "{\"type\":\"decimal\",\"precision\":38,\"scale\":2,\"nullable\":true}",
      ),
    ] {
    let owner = native_join_fixture(left, right)
    let query = @duckdb.compile_fixed_inner_join(
      owner,
      "main",
      ["left_rows", "right_rows"],
      native_compile_limits(),
    ).unwrap()
    let writer = @encode.writer(10000, 100, 10)
    @encode.begin_object(writer)
    @encode.key(writer, "name")
    @encode.string_value(writer, name)
    @encode.key(writer, "sql")
    @encode.string_value(writer, @duckdb.native_inner_join_sql(query))
    @encode.end_object(writer)
    println("ACTQL_INNER_JOIN " + @encode.finish(writer))
  }
}
