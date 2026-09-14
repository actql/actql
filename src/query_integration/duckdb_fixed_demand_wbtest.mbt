///|
test "fixed native demand shares comparison laws without Local predicate replay" {
  let input = duckdb_captured_input(filter="id > 2")
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  for ceiling in [4, 5] {
    let receiving = @duckdb.prepare_fixed_compute_receiving(
      compute,
      [("id", @duckdb.Float64)],
      { max_rows: 2, max_cells: 2, max_nodes: 2, max_text_bytes: 0, },
      { max_nodes: 4, max_text_bytes: 4, max_depth: 2, max_work: 8, },
      100,
    ).unwrap()
    @duckdb.receive_fixed_compute_chunk(receiving, 1, [
      input_cursor("[\"4008000000000000\"]"),
    ]).unwrap()
    let receipt = @duckdb.finish_fixed_compute_receiving(receiving).unwrap()
    let measured = @duckdb.measure_fixed_compute_demand(
      compute,
      receipt,
      ceiling,
      { max_work: 7, max_bytes: 3, max_nodes: 3, max_depth: 10, },
    )
    if ceiling == 4 {
      assert_true(measured is Err(Predicate(ValueBytes)))
      assert_true(@duckdb.fixed_compute_receipt_rows(receipt) is None)
    } else {
      let measured = measured.unwrap()
      guard @duckdb.fixed_compute_demand_usage(measured)
        is @duckdb.Comparison(usage) else {
        fail("expected comparison demand")
      }
      assert_eq(usage.rows, 2)
      assert_eq(usage.field_bytes, 2L)
      assert_eq(usage.rhs_bytes, Some(1))
      assert_eq((usage.true_rows, usage.false_rows, usage.null_rows), (1, 1, 0))
      assert_eq(usage.predicate_bytes, 9L)
      assert_eq(
        (usage.physical_work, usage.physical_bytes, usage.physical_nodes),
        (7, 3, 3),
      )
      assert_true(
        @duckdb.fixed_compute_demand_matches(measured, compute, receipt, 5),
      )
      assert_false(
        @duckdb.fixed_compute_demand_matches(measured, compute, receipt, 6),
      )
      let foreign = @duckdb.prepare_fixed_compute(
        input,
        "held",
        native_compile_limits(),
      ).unwrap()
      assert_false(
        @duckdb.fixed_compute_demand_matches(measured, foreign, receipt, 5),
      )
      assert_true(
        @duckdb.measure_fixed_compute_demand(foreign, receipt, 5, {
          max_work: 100,
          max_bytes: 100,
          max_nodes: 100,
          max_depth: 10,
        })
        is Err(InvalidState),
      )
      assert_true(
        @duckdb.fixed_compute_demand_matches(measured, compute, receipt, 5),
      )
      @duckdb.abort_fixed_compute_receiving(receiving)
      assert_false(
        @duckdb.fixed_compute_demand_matches(measured, compute, receipt, 5),
      )
    }
    assert_true(@execution.producer_read_available(input))
  }
}

///|
test "fixed native comparison demand preserves empty and nullable inputs" {
  for
    (source, output, input_count, null_count, true_count, ceiling) in [
      ("[]", "[]", 0, 0, 0, 0),
      ("[{\"x\":null}]", "[]", 1, 1, 0, 4),
      ("[{\"x\":null},{\"x\":3}]", "[\"4008000000000000\"]", 2, 1, 1, 4),
    ] {
    let input = duckdb_fixed_values(
      "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":true}},\"rows\":" +
      source +
      "},\"as\":\"seed\"}]",
      steps="[{\"filter\":\"x > 2\"},{\"select\":[\"x\"]}]",
    )
    let compute = @duckdb.prepare_fixed_compute(
      input,
      "held",
      native_compile_limits(),
    ).unwrap()
    let receiving = @duckdb.prepare_fixed_compute_receiving(
      compute,
      [("x", @duckdb.Float64)],
      { max_rows: 2, max_cells: 2, max_nodes: 2, max_text_bytes: 0, },
      { max_nodes: 4, max_text_bytes: 4, max_depth: 2, max_work: 8, },
      100,
    ).unwrap()
    @duckdb.receive_fixed_compute_chunk(receiving, true_count, [
      input_cursor(output),
    ]).unwrap()
    let receipt = @duckdb.finish_fixed_compute_receiving(receiving).unwrap()
    let measured = @duckdb.measure_fixed_compute_demand(
      compute,
      receipt,
      ceiling,
      { max_work: 100, max_bytes: 100, max_nodes: 100, max_depth: 10, },
    ).unwrap()
    guard @duckdb.fixed_compute_demand_usage(measured)
      is @duckdb.Comparison(usage) else {
      fail("expected comparison demand")
    }
    assert_eq(usage.rows, input_count)
    assert_eq(
      (usage.true_rows, usage.false_rows, usage.null_rows),
      (true_count, 0, null_count),
    )
    assert_eq(usage.predicate_bytes, (true_count + null_count).to_int64() * 4L)
    if input_count == 0 {
      assert_eq(usage.rhs_bytes, None)
      assert_eq((usage.physical_bytes, usage.physical_nodes), (0, 0))
    } else {
      assert_eq(usage.rhs_bytes, Some(1))
    }
  }
}
