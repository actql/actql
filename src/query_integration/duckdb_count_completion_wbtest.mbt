///|
test "fixed global count completion uses its own target and preserves common guards" {
  for
    (rows, expected_wire, expected) in [
      ("[]", "[\"0000000000000000\"]", 0.0),
      ("[{\"x\":null},{\"x\":2}]", "[\"4000000000000000\"]", 2.0),
    ] {
    let input = duckdb_fixed_values(
      "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":true}},\"rows\":" +
      rows +
      "},\"as\":\"seed\"}]",
      steps="[{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
    )
    let owner = @execution.producer_read_receiver(input)
    let transport : FixedComputeTestTransport = { settled: None, }
    let (attempt, _) = fixed_compute_attempt_fixture(
      transport,
      fixed_compute_attempt_limits(),
      supplied_input=Some(input),
      generated=Some(compute_test_sequence(owner)),
    )
    @duckdb_compute.begin_duckdb_compute_result(attempt, [
      ("__actql_output_0", @duckdb.Float64),
    ]).unwrap()
    @duckdb_compute.receive_duckdb_compute_chunk(attempt, 1, [
      input_cursor(expected_wire),
    ]).unwrap()
    @duckdb_compute.finish_duckdb_compute_result(attempt).unwrap()
    transport.settled = Some(attempt)
    let output = @duckdb_compute.complete_duckdb_compute_attempt(attempt).unwrap()
    assert_eq(@execution.completed_row_count(output), 1)
    assert_true(
      @execution.completed_cell(output, 0, 0) is Some(Number(n)) &&
      n == expected,
    )
    let receiver = typed_receiver(
      owner,
      "[{\"select\":[\"n\"]}]",
      target=Step(0),
    )
    let binding = @execution.bind_completed_input(receiver, 0, owner, output).unwrap()
    let completed = @execution.execute_generated_sequence(
      compute_test_sequence(receiver),
      [],
      compute_test_limits(),
      produced=[binding],
    ).unwrap()
    let downstream = @execution.completed_output(completed, Step(0)).unwrap()
    @duckdb_compute.close_duckdb_compute_attempt(attempt)
    assert_true(
      @execution.bind_completed_input(receiver, 0, owner, output)
      is Err(ProducerUnavailable),
    )
    assert_true(
      @execution.completed_cell(downstream, 0, 0) is Some(Number(n)) &&
      n == expected,
    )
  }
}

///|
test "global count cannot seal an empty receipt even when its fixed input is empty" {
  let input = duckdb_fixed_values(
    "[{\"values\":{\"schema\":{\"x\":{\"type\":\"number\",\"nullable\":true}},\"rows\":[]},\"as\":\"seed\"}]",
    steps="[{\"group\":{\"by\":[],\"aggregates\":{\"n\":{\"fn\":\"count\"}}}}]",
  )
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "fixed",
    native_compile_limits(),
  ).unwrap()
  let limits = fixed_compute_attempt_limits()
  let receiving = @duckdb.prepare_fixed_compute_receiving(
    compute,
    [("__actql_output_0", @duckdb.Float64)],
    limits.physical,
    limits.retention,
    limits.metadata_work,
  ).unwrap()
  assert_true(
    @duckdb.finish_fixed_compute_receiving(receiving) is Err(InvalidShape),
  )
  assert_true(
    @duckdb.finish_fixed_compute_receiving(receiving) is Err(InvalidState),
  )
  assert_true(@execution.producer_read_available(input))
}
