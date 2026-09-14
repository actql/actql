///|
// Input vectors and expected values transcribed from the independently authored
// portability/corpus/group-canonical-order.json, not an evaluator's output.
test "canonical group corpus agrees with Local execution and exports checked SQL" {
  let cases : Array[(String, String, String, Array[Array[Double?]])] = [
    (
      "single-key-null-first-and-null-group-equality",
      "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"k\":2},{\"k\":null},{\"k\":-1},{\"k\":null},{\"k\":0}]},\"as\":\"seed\"}]",
      "[{\"group\":{\"by\":[\"k\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
      [
        [None, Some(2.0)],
        [Some(-1.0), Some(1.0)],
        [Some(0.0), Some(1.0)],
        [Some(2.0), Some(1.0)],
      ],
    ),
    (
      "compound-null-placement-at-each-component",
      "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"a\":1,\"b\":null},{\"a\":null,\"b\":2},{\"a\":0,\"b\":9},{\"a\":null,\"b\":null},{\"a\":0,\"b\":null},{\"a\":null,\"b\":-1},{\"a\":0,\"b\":-2},{\"a\":null,\"b\":null}]},\"as\":\"seed\"}]",
      "[{\"group\":{\"by\":[\"a\",\"b\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
      [
        [None, None, Some(2.0)],
        [None, Some(-1.0), Some(1.0)],
        [None, Some(2.0), Some(1.0)],
        [Some(0.0), None, Some(1.0)],
        [Some(0.0), Some(-2.0), Some(1.0)],
        [Some(0.0), Some(9.0), Some(1.0)],
        [Some(1.0), None, Some(1.0)],
      ],
    ),
    (
      "authored-key-order-not-object-name-order",
      "[{\"values\":{\"schema\":{\"a\":{\"type\":\"number\",\"nullable\":true},\"b\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[{\"a\":null,\"b\":2},{\"a\":1,\"b\":null},{\"a\":null,\"b\":null},{\"a\":0,\"b\":2}]},\"as\":\"seed\"}]",
      "[{\"group\":{\"by\":[\"b\",\"a\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
      [
        [None, None, Some(1.0)],
        [Some(1.0), None, Some(1.0)],
        [None, Some(2.0), Some(1.0)],
        [Some(0.0), Some(2.0), Some(1.0)],
      ],
    ),
    (
      "empty-keyed-input",
      "[{\"values\":{\"schema\":{\"k\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"}]",
      "[{\"group\":{\"by\":[\"k\"],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
      [],
    ),
    (
      "empty-global-input",
      "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"}]",
      "[{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
      [[Some(0.0)]],
    ),
  ]
  for (id, seed, steps, expected) in cases {
    let input = duckdb_fixed_values(seed, steps~)
    let owner = @execution.producer_read_receiver(input)
    let completed = @execution.execute_fixed_producers_guarded(
      compute_test_sequence(owner),
      [input],
      Step(0),
      compute_test_limits(),
      max_rows=100,
      max_value_bytes=1000,
      { max_nodes: 10000, max_bytes: 100000, max_depth: 100, max_work: 100000, },
    ).unwrap()
    let output = @execution.completed_output(completed, Step(0)).unwrap()
    assert_eq(@execution.completed_row_count(output), expected.length())
    for row, values in expected {
      for column, expected in values {
        match expected {
          None =>
            assert_true(
              @execution.completed_cell(output, row, column) is Some(Null),
            )
          Some(n) =>
            assert_true(
              @execution.completed_cell(output, row, column)
              is Some(Number(actual)) &&
              actual == n,
            )
        }
      }
    }
    let query = @duckdb.compile_fixed_query(
      owner,
      "main",
      "fixed",
      native_compile_limits(),
    ).unwrap()
    let writer = @encode.writer(10000, 100, 10)
    @encode.begin_object(writer)
    @encode.key(writer, "id")
    @encode.string_value(writer, id)
    @encode.key(writer, "sql")
    @encode.string_value(writer, @duckdb.fixed_query_sql(query))
    @encode.end_object(writer)
    println("ACTQL_GROUP_CORPUS " + @encode.finish(writer))
  }
}
