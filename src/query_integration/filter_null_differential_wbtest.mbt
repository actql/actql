///|
fn assert_filter_amounts(
  output : @execution.CompletedOutput,
  expected : Array[Double],
) -> Unit raise {
  assert_eq(@execution.completed_row_count(output), expected.length())
  for row, value in expected {
    assert_true(
      @execution.completed_cell(output, row, 0) is Some(Number(actual)) &&
      actual == value,
    )
  }
}

///|
test "nullable comparisons and NULL parameters agree with Local and export SQL" {
  for
    (operator, expected) in [
      ("=", [0.0]),
      ("<>", [-1.0, 1.0]),
      ("<=", [-1.0, 0.0]),
      (">=", [0.0, 1.0]),
    ] {
    for null_parameter in [false, true] {
      let (query, owner) = query_sequence_fixture(
        filter="amount " + operator + " $minimum",
        parameters="{\"minimum\":{\"type\":\"number\",\"nullable\":true}}",
        supplied=if null_parameter {
          "{\"minimum\":null}"
        } else {
          "{\"minimum\":0}"
        },
        catalog=Some(query_amount_nullable_catalog()),
        field="amount",
      )
      let prepared = @query.prepare_query_sequence(
        query,
        query_generated(owner),
        10000,
      ).unwrap()
      let receipt = @query.admit_query_receipt(
        prepared,
        [
          input_cursor("{\"id\":0,\"amount\":null}"),
          input_cursor("{\"id\":1,\"amount\":-1}"),
          input_cursor("{\"id\":2,\"amount\":0}"),
          input_cursor("{\"id\":3,\"amount\":1}"),
        ],
        4,
        run_limits().input_values,
      ).unwrap()
      let completed = @query.execute_query_receipt(
        prepared,
        receipt,
        compute_test_limits(),
      ).unwrap()
      assert_filter_amounts(
        @execution.completed_output(completed, Step(1)).unwrap(),
        if null_parameter {
          []
        } else {
          expected
        },
      )
      let compiled = @duckdb.compile_native_filter_select(
        owner,
        "main",
        "records",
        native_compile_limits(),
      ).unwrap()
      let writer = @encode.writer(10000, 100, 10)
      @encode.begin_object(writer)
      @encode.key(writer, "operator")
      @encode.string_value(writer, operator)
      @encode.key(writer, "nullParameter")
      @encode.bool_value(writer, null_parameter)
      @encode.key(writer, "sql")
      @encode.string_value(writer, @duckdb.native_query_sql(compiled))
      @encode.end_object(writer)
      println("ACTQL_FILTER_NULL " + @encode.finish(writer))
    }
  }
}
