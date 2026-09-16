///|
fn managed_fixed_demand_receipt(
  input : @execution.ProducerRead,
  compute : @duckdb.FixedCompute,
) -> @execution.ManagedOutputValueReceipt {
  let values = @execution.prepare_managed_output_values(
    @execution.producer_read_receiver(input),
    @duckdb.fixed_query_target(@duckdb.fixed_compute_query(compute)),
    2,
    { max_nodes: 10, max_text_bytes: 100, max_depth: 10, max_work: 100, },
    100,
    { max_work: 100, max_bytes: 100, max_nodes: 100, max_depth: 10, },
  ).unwrap()
  let receiving = @duckdb.prepare_managed_physical_output(
    values,
    [("id", @duckdb.Float64)],
    { max_rows: 2, max_cells: 2, max_nodes: 2, max_text_bytes: 0, },
    100,
  ).unwrap()
  @duckdb.append_managed_physical_output(receiving, 1, [
    input_cursor("[\"4008000000000000\"]"),
  ]).unwrap()
  @duckdb.finish_managed_physical_output(receiving).unwrap()
}

///|
test "managed fixed demand consumes the existing import measurement exactly once" {
  let f = native_issuer_fixture()
  let attempt = native_issued_attempt(f)
  let source_receipt = native_retained_receive(attempt)
  let handle = @execution.retain_admitted_output_stream(source_receipt, (), fn() {
    true
  })
  @duckdb_query.stage_duckdb_native_output_material(
    attempt,
    @execution.retained_output_material(handle),
  ).unwrap()
  f.transport.push(attempt)
  let observation = @duckdb_query.complete_duckdb_native_capture(
    f.issuer,
    attempt,
    native_completion_limits(),
  ).unwrap()
  let output = @duckdb_query.complete_duckdb_native_retained_output(
    f.issuer,
    attempt,
    observation,
    100,
    10000,
  ).unwrap()
  let owner = @duckdb.native_query_owner(
    @duckdb.native_scan_query(
      @duckdb_query.duckdb_native_preparation_scan(
        @duckdb_query.duckdb_native_attempt_preparation(attempt),
      ),
    ),
  )
  let receiver = typed_receiver(
    owner, "[{\"filter\":\"id > 2\"},{\"select\":[\"id\"]}]",
  )
  let input = @execution.prepare_producer_read(
    receiver,
    @execution.bind_completed_input(receiver, 0, owner, output).unwrap(),
    100,
    10000,
  ).unwrap()
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let receipt = managed_fixed_demand_receipt(input, compute)
  let limits : @execution.FixedInputGuardMeasureLimits = {
    max_work: 7,
    max_bytes: 3,
    max_nodes: 3,
    max_depth: 10,
  }
  let stream = @duckdb.prepare_fixed_import_stream(
    @duckdb.fixed_compute_import(compute, 0).unwrap(),
    100,
    native_retained_values(),
    native_completion_limits().receipts,
    1000,
  ).unwrap()
  @duckdb.attach_fixed_import_demand(stream, compute, 5, limits).unwrap()
  for row in ["{\"id\":3}", "{\"id\":2}"] {
    @duckdb.append_fixed_import_stream(
      stream,
      row,
      { max_bytes: 1000, max_nodes: 100, max_depth: 10, max_text_bytes: 1000, },
      materialize_parameters=false,
    ).unwrap()
    |> ignore
  }
  @duckdb.finish_fixed_import_stream(stream).unwrap() |> ignore
  let input_demand = @duckdb.fixed_import_verified_demand(stream).unwrap()
  let measured = @duckdb.measure_managed_fixed_compute_demand(
    compute,
    receipt,
    5,
    limits,
    input_demand~,
  ).unwrap()
  assert_true(
    @duckdb.managed_fixed_compute_demand_matches(measured, compute, receipt, 5),
  )
  assert_true(
    @duckdb.measure_managed_fixed_compute_demand(
      compute,
      receipt,
      5,
      limits,
      input_demand~,
    )
    is Err(InvalidState),
  )
}

///|
test "managed fixed demand preserves comparison limits without a logical CID receipt" {
  let (input, close_input) = duckdb_captured_input_lifetime(filter="id > 2")
  let compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  let receipt = managed_fixed_demand_receipt(input, compute)
  let limits : @execution.FixedInputGuardMeasureLimits = {
    max_work: 7,
    max_bytes: 3,
    max_nodes: 3,
    max_depth: 10,
  }
  assert_true(
    @duckdb.measure_managed_fixed_compute_demand(compute, receipt, 4, limits)
    is Err(Predicate(ValueBytes)),
  )
  let measured = @duckdb.measure_managed_fixed_compute_demand(
    compute, receipt, 5, limits,
  ).unwrap()
  guard @duckdb.managed_fixed_compute_demand_usage(measured)
    is @duckdb.Comparison(usage) else {
    fail("expected comparison demand")
  }
  assert_eq(
    (usage.rows, usage.true_rows, usage.false_rows, usage.null_rows),
    (2, 1, 1, 0),
  )
  assert_eq(
    (usage.physical_work, usage.physical_bytes, usage.physical_nodes),
    (7, 3, 3),
  )
  assert_eq(usage.predicate_bytes, 9L)
  assert_true(
    @duckdb.managed_fixed_compute_demand_matches(measured, compute, receipt, 5),
  )
  assert_false(
    @duckdb.managed_fixed_compute_demand_matches(measured, compute, receipt, 6),
  )
  let other_receipt = managed_fixed_demand_receipt(input, compute)
  assert_false(
    @duckdb.managed_fixed_compute_demand_matches(
      measured, compute, other_receipt, 5,
    ),
  )
  let other_compute = @duckdb.prepare_fixed_compute(
    input,
    "held",
    native_compile_limits(),
  ).unwrap()
  assert_false(
    @duckdb.managed_fixed_compute_demand_matches(
      measured, other_compute, receipt, 5,
    ),
  )
  let foreign = duckdb_captured_input(filter="id > 2")
  let foreign_compute = @duckdb.prepare_fixed_compute(
    foreign,
    "held",
    native_compile_limits(),
  ).unwrap()
  assert_true(
    @duckdb.measure_managed_fixed_compute_demand(
      foreign_compute, receipt, 5, limits,
    )
    is Err(InvalidState),
  )
  close_input()
  assert_false(
    @duckdb.managed_fixed_compute_demand_matches(measured, compute, receipt, 5),
  )
  assert_true(
    @duckdb.measure_managed_fixed_compute_demand(compute, receipt, 5, limits)
    is Err(InvalidState),
  )
}
