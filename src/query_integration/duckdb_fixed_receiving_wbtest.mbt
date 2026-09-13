///|
test "fixed Compute receiving seals exact owned output without granting execution success" {
  let input = duckdb_captured_input()
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let physical : @duckdb.PhysicalResultLimits = {
    max_rows: 2,
    max_cells: 2,
    max_nodes: 2,
    max_text_bytes: 0,
  }
  let retained : @execution.ValueLimits = {
    max_nodes: 4,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 8,
  }
  let receiving = @duckdb.prepare_fixed_compute_receiving(
    compute,
    [("id", @duckdb.Float64)],
    physical,
    retained,
    100,
  ).unwrap()
  for payload in ["[\"4008000000000000\"]", "[\"4000000000000000\"]"] {
    @duckdb.receive_fixed_compute_chunk(receiving, 1, [input_cursor(payload)]).unwrap()
  }
  let receipt = @duckdb.finish_fixed_compute_receiving(receiving).unwrap()
  assert_true(@duckdb.fixed_compute_receipt_matches(receipt, receiving))
  let rows = @duckdb.fixed_compute_receipt_rows(receipt).unwrap()
  let measure_limits : @execution.FixedInputGuardMeasureLimits = {
    max_work: 8,
    max_bytes: 4,
    max_nodes: 4,
    max_depth: 10,
  }
  let measuring = @execution.prepare_fixed_producer_measurement(
    input,
    @pipeline.Step(1),
    max_rows=2,
    max_value_bytes=1,
    measure_limits,
  ).unwrap()
  let measured = @execution.finish_fixed_producer_measurement(measuring, rows).unwrap()
  assert_eq(@execution.fixed_producer_measurement_usage(measured), (8, 4, 4))
  assert_true(
    @execution.fixed_producer_measurement_matches(measured, input, rows, 2, 1),
  )
  assert_false(
    @execution.fixed_producer_measurement_matches(measured, input, rows, 2, 2),
  )
  assert_false(
    @execution.fixed_producer_measurement_matches(
      measured,
      duckdb_captured_input(),
      rows,
      2,
      1,
    ),
  )
  assert_true(
    @execution.finish_fixed_producer_measurement(measuring, rows)
    is Err(ForeignInput),
  )
  for
    physical_measurement in [
      { ..measure_limits, max_work: 7, },
      { ..measure_limits, max_bytes: 3, },
      { ..measure_limits, max_nodes: 3, },
    ] {
    let short = @execution.prepare_fixed_producer_measurement(
      input,
      @pipeline.Step(1),
      max_rows=2,
      max_value_bytes=1,
      physical_measurement,
    ).unwrap()
    assert_true(
      @execution.finish_fixed_producer_measurement(short, rows) is Err(_),
    )
    assert_true(
      @execution.finish_fixed_producer_measurement(short, rows)
      is Err(ForeignInput),
    )
  }
  let foreign_measurement = @execution.prepare_fixed_producer_measurement(
    duckdb_captured_input(),
    @pipeline.Step(1),
    max_rows=2,
    max_value_bytes=1,
    measure_limits,
  ).unwrap()
  assert_true(
    @execution.finish_fixed_producer_measurement(foreign_measurement, rows)
    is Err(ForeignInput),
  )
  assert_true(
    physical_equal(
      @execution.admitted_output_owner(rows),
      @execution.producer_read_receiver(input),
    ),
  )
  assert_eq(@execution.admitted_output_target(rows), @pipeline.Step(1))
  assert_eq(@execution.admitted_output_usage(rows), {
    nodes: 4,
    text_bytes: 4,
    work: 8,
  })
  assert_true(
    @execution.admitted_output_cell(rows, 0, 0) is Some(@admitted.Number(3)),
  )
  assert_true(
    @execution.admitted_output_cell(rows, 1, 0) is Some(@admitted.Number(2)),
  )
  assert_true(
    @duckdb.finish_fixed_compute_receiving(receiving) is Err(InvalidState),
  )
  assert_true(
    @duckdb.receive_fixed_compute_chunk(receiving, 0, [input_cursor("[]")])
    is Err(InvalidState),
  )
  let other = @duckdb.prepare_fixed_compute_receiving(
    compute,
    [("id", @duckdb.Float64)],
    physical,
    retained,
    100,
  ).unwrap()
  assert_false(@duckdb.fixed_compute_receipt_matches(receipt, other))
  @duckdb.abort_fixed_compute_receiving(receiving)
  assert_true(@duckdb.fixed_compute_receipt_rows(receipt) is None)
  assert_true(@execution.producer_read_available(input))
  let empty = @duckdb.finish_fixed_compute_receiving(other).unwrap()
  assert_eq(
    @execution.admitted_output_row_count(
      @duckdb.fixed_compute_receipt_rows(empty).unwrap(),
    ),
    0,
  )
}

///|
test "fixed Compute receiving failures are terminal and preserve reusable upstream input" {
  let input = duckdb_captured_input()
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let physical : @duckdb.PhysicalResultLimits = {
    max_rows: 2,
    max_cells: 2,
    max_nodes: 2,
    max_text_bytes: 0,
  }
  let exact : @execution.ValueLimits = {
    max_nodes: 4,
    max_text_bytes: 4,
    max_depth: 2,
    max_work: 8,
  }
  for
    retained in [
      { ..exact, max_nodes: 3, },
      { ..exact, max_text_bytes: 3, },
      { ..exact, max_work: 7, },
    ] {
    let receiver = @duckdb.prepare_fixed_compute_receiving(
      compute,
      [("id", @duckdb.Float64)],
      physical,
      retained,
      100,
    ).unwrap()
    assert_true(
      @duckdb.receive_fixed_compute_chunk(receiver, 2, [
        input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
      ])
      is Err(Retention(CaptureLimit)),
    )
    assert_true(
      @duckdb.finish_fixed_compute_receiving(receiver) is Err(InvalidState),
    )
  }
  for payload in ["[null]", "[\"7ff0000000000000\"]", "[\"invalid\"]"] {
    let receiver = @duckdb.prepare_fixed_compute_receiving(
      compute,
      [("id", @duckdb.Float64)],
      physical,
      exact,
      100,
    ).unwrap()
    assert_true(
      @duckdb.receive_fixed_compute_chunk(receiver, 1, [input_cursor(payload)])
      is Err(Physical(_)),
    )
    assert_true(
      @duckdb.finish_fixed_compute_receiving(receiver) is Err(InvalidState),
    )
  }
  let oversized = @duckdb.prepare_fixed_compute_receiving(
    compute,
    [("id", @duckdb.Float64)],
    { ..physical, max_rows: 3, max_cells: 3, max_nodes: 3, },
    exact,
    100,
  ).unwrap()
  assert_true(
    @duckdb.receive_fixed_compute_chunk(oversized, 3, []) is Err(InvalidShape),
  )
  assert_true(
    @duckdb.finish_fixed_compute_receiving(oversized) is Err(InvalidState),
  )
  assert_true(
    @duckdb.prepare_fixed_compute_receiving(
      compute,
      [("wrong", @duckdb.Float64)],
      physical,
      exact,
      100,
    )
    is Err(Physical(SchemaMismatch)),
  )
  assert_true(@execution.producer_read_available(input))
}
