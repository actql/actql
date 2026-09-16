///|
test "managed DuckDB output uses selected attempt guards and exact retained receipt" {
  for mode in 0..<5 {
    let (input, close_input) = duckdb_captured_input_lifetime(filter="id > 2")
    let transport : FixedComputeTestTransport = { settled: None, }
    let (attempt, _) = fixed_compute_attempt_fixture(
      transport,
      fixed_compute_attempt_limits(),
      supplied_input=Some(input),
      ceiling=if mode == 1 { 4 } else { 5 },
    )
    let output = @duckdb_compute.begin_managed_duckdb_compute_output(attempt, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    // Output mode is exclusive even before any values are received.
    assert_true(
      @duckdb_compute.begin_duckdb_compute_result(attempt, [
        ("id", @duckdb.Float64),
      ])
      is Err(InvalidState),
    )
    assert_true(
      @duckdb_compute.begin_managed_duckdb_compute_output(attempt, [
        ("id", @duckdb.Float64),
      ])
      is Err(InvalidState),
    )
    let live = Ref(true)
    let port = @execution.prepare_managed_output_retention_port(
      @duckdb_compute.managed_duckdb_compute_output_values(output),
      (receipt : @execution.ManagedOutputValueReceipt) => {
        Some((receipt, 7, 8L, fn() { live.val }))
      },
    ).unwrap()
    @duckdb_compute.receive_managed_duckdb_compute_output(output, 1, [
      input_cursor("[\"4008000000000000\"]"),
    ]).unwrap()
    let receipt = @duckdb_compute.finish_managed_duckdb_compute_output(output).unwrap()
    let material = @execution.retain_managed_output(port, receipt).unwrap()
    assert_true(
      @duckdb_compute.verified_managed_duckdb_compute_material(output, material)
      is None,
    )
    if mode != 0 {
      transport.settled = Some(attempt)
    }
    if mode == 2 {
      close_input()
    }
    let verified = @duckdb_compute.verify_managed_duckdb_compute_output(output)
    if mode == 0 {
      assert_true(verified is Err(UnverifiedTransport))
    } else if mode == 1 {
      assert_true(verified is Err(Demand(Predicate(ValueBytes))))
    } else if mode == 2 {
      assert_true(verified is Err(Guard(ForeignInput)))
    } else {
      verified.unwrap()
      assert_true(
        @duckdb_compute.verified_managed_duckdb_compute_material(
          output, material,
        )
        is Some(_),
      )
      assert_eq(
        @execution.managed_output_value_fixed_measurement_usage(receipt),
        Some((6, 3, 3)),
      )
      if mode == 3 {
        live.val = false
      } else {
        close_input()
      }
      assert_true(
        @duckdb_compute.verified_managed_duckdb_compute_material(
          output, material,
        )
        is None,
      )
    }
    assert_true(
      @duckdb_compute.complete_duckdb_compute_attempt(attempt)
      is Err(InvalidState),
    )
    @duckdb_compute.cancel_managed_duckdb_compute_output(output)
    assert_true(
      @duckdb_compute.verified_managed_duckdb_compute_material(output, material)
      is None,
    )
    assert_true(
      @duckdb_compute.verify_managed_duckdb_compute_output(output)
      is Err(InvalidState),
    )
  }
}

///|
test "managed DuckDB output rejects malformed values and preserves input plus output budget" {
  for malformed in [true, false] {
    let transport : FixedComputeTestTransport = { settled: None, }
    let limits = fixed_compute_attempt_limits()
    let (attempt, _) = fixed_compute_attempt_fixture(transport, {
      ..limits,
      values: { ..limits.values, max_work: if malformed { 100 } else { 5 }, },
    })
    let output = @duckdb_compute.begin_managed_duckdb_compute_output(attempt, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    let received = @duckdb_compute.receive_managed_duckdb_compute_output(
      output,
      1,
      [
        input_cursor(
          if malformed {
            "[\"7ff0000000000000\"]"
          } else {
            "[\"4008000000000000\"]"
          },
        ),
      ],
    )
    if malformed {
      assert_true(received is Err(ManagedValues(_)))
      assert_true(
        @duckdb_compute.finish_managed_duckdb_compute_output(output)
        is Err(InvalidState),
      )
    } else {
      received.unwrap()
      assert_true(
        @duckdb_compute.finish_managed_duckdb_compute_output(output)
        is Err(ManagedValues(Values(Guard(_)))),
      )
    }
    transport.settled = Some(attempt)
    assert_true(
      @duckdb_compute.verify_managed_duckdb_compute_output(output)
      is Err(InvalidState),
    )
  }
}
