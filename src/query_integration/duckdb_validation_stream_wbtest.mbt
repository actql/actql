///|
test "streamed validation discards scan rows while preserving exact demand and both receipt identities" {
  for split in [false, true] {
    let streamed = received_identity_fixture(split~, streamed=true)
    let retained = received_identity_fixture(split~)
    assert_eq(@duckdb.native_validation_retained_rows(streamed), 0)
    assert_eq(@duckdb.native_validation_retained_rows(retained), 3)
    let demand = @duckdb.native_demand_usage(
      @duckdb.measure_native_demand(streamed, native_demand_physical()).unwrap(),
    )
    let prior = @duckdb.native_demand_usage(
      @duckdb.measure_native_demand(retained, native_demand_physical()).unwrap(),
    )
    assert_eq(demand.rows, prior.rows)
    assert_eq(demand.field_bytes, prior.field_bytes)
    assert_eq(demand.rhs_bytes, prior.rhs_bytes)
    assert_eq(
      (demand.true_rows, demand.false_rows, demand.null_rows),
      (2, 1, 0),
    )
    assert_eq(
      (demand.physical_work, demand.physical_bytes, demand.physical_nodes),
      (prior.physical_work, prior.physical_bytes, prior.physical_nodes),
    )
    let ids = @duckdb.identify_native_receipts(
      streamed,
      receipt_wire_limits(),
      5,
      89,
    ).unwrap()
    assert_eq(
      @duckdb.native_receipt_digest(ids, @duckdb.ValidationScan),
      (
        "sha256:723a49c09f83a9e64b8376fd9bda47b3196554fe8aa30e279516fbed4763327d",
        70, 10, 3,
      ),
    )
    assert_eq(
      @duckdb.native_receipt_digest(ids, @duckdb.NativeResult),
      (
        "sha256:b578d4eb7cd3e1c8e66fd5758a9c5a98dc05739e4c6fa282fc372aec70930e18",
        19, 5, 2,
      ),
    )
    @duckdb.abort_native_receiving(streamed)
    assert_false(@duckdb.native_receipts_match(ids, streamed))
  }
}

///|
test "streamed validation cannot reset demand or hashing allowances after discarding source values" {
  let value = received_identity_fixture(streamed=true)
  assert_true(
    @duckdb.measure_native_demand(value, {
      ..native_demand_physical(),
      max_work: 10001,
    })
    is Err(InvalidLimits),
  )
  assert_false(@duckdb.native_receiving_has_both(value))
  let value = received_identity_fixture(streamed=true)
  assert_true(
    @duckdb.identify_native_receipts(
      value,
      { ..receipt_wire_limits(), max_bytes: 90, },
      5,
      90,
    )
    is Err(_),
  )
  assert_false(@duckdb.native_receiving_has_both(value))
  let limits = { ..receipt_wire_limits(), max_bytes: 69, }
  let value = received_identity_fixture(streamed=true, wire=limits)
  assert_true(
    @duckdb.identify_native_receipts(value, limits, 5, 89)
    is Err(Wire(ValidationScan, _)),
  )
  let value = received_identity_fixture(streamed=true)
  assert_true(
    @duckdb.identify_native_receipts(value, receipt_wire_limits(), 4, 89)
    is Err(ReceiptRows),
  )
}

///|
test "streamed validation bounds chunk admission and still rejects excluded invalid source cells" {
  for too_large in [false, true] {
    let value = native_receiving_fixture()
    @duckdb.stream_native_validation(
      value,
      receipt_wire_limits(),
      native_demand_physical(),
      1,
    ).unwrap()
    receiving_metadata(value)
    let port = receiving_validation(value)
    @duckdb.accept_native_receipt_chunk(value, port, 1, [
      input_cursor("[null]"),
      input_cursor("[\"4008000000000000\"]"),
    ]).unwrap()
    assert_eq(@duckdb.native_validation_retained_rows(value), 0)
    let result = if too_large {
      @duckdb.accept_native_receipt_chunk(value, port, 2, [
        input_cursor("[null,null]"),
        input_cursor("[\"3ff0000000000000\",\"4000000000000000\"]"),
      ])
    } else {
      @duckdb.accept_native_receipt_chunk(value, port, 1, [
        input_cursor("[\"not-a-number\"]"),
        input_cursor("[\"3ff0000000000000\"]"),
      ])
    }
    assert_true(result is Err(Values(_)))
    assert_true(@duckdb.finish_native_receipt(value, port) is Err(InvalidState))
    assert_false(@duckdb.native_receiving_has_both(value))
  }
}

///|
test "streamed scan defers guard failure until physical admission has finished" {
  for invalid_later in [false, true] {
    let value = native_receiving_fixture(value_bytes=1)
    @duckdb.stream_native_validation(
      value,
      receipt_wire_limits(),
      native_demand_physical(),
      1,
    ).unwrap()
    receiving_metadata(value)
    let port = receiving_validation(value)
    @duckdb.accept_native_receipt_chunk(value, port, 1, [
      input_cursor("[null]"),
      input_cursor("[\"4000000000000000\"]"),
    ]).unwrap()
    assert_eq(@duckdb.native_validation_retained_rows(value), 0)
    if invalid_later {
      assert_true(
        @duckdb.accept_native_receipt_chunk(value, port, 1, [
          input_cursor("[\"invalid\"]"),
          input_cursor("[\"4000000000000000\"]"),
        ])
        is Err(Values(_)),
      )
    } else {
      assert_true(
        @duckdb.finish_native_receipt(value, port)
        is Err(Guard(ValidationScan, 0, -1, ValueBytes)),
      )
    }
  }
}

///|
test "empty streamed validation retains array identity without demanding RHS or materializing rows" {
  let value = native_receiving_fixture(value_bytes=0)
  let wire = {
    ..receipt_wire_limits(),
    max_bytes: 4,
    max_nodes: 2,
    max_depth: 1,
  }
  let demand : @execution.FixedInputGuardMeasureLimits = {
    max_work: 0,
    max_bytes: 0,
    max_nodes: 0,
    max_depth: 0,
  }
  @duckdb.stream_native_validation(value, wire, demand, 0).unwrap()
  receiving_metadata(value)
  let port = receiving_validation(value)
  @duckdb.finish_native_receipt(value, port).unwrap()
  let output = @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
    ("id", @duckdb.Float64),
  ]).unwrap()
  @duckdb.finish_native_receipt(value, output).unwrap()
  let usage = @duckdb.native_demand_usage(
    @duckdb.measure_native_demand(value, demand).unwrap(),
  )
  assert_eq(usage.rows, 0)
  assert_eq(usage.rhs_bytes, None)
  let ids = @duckdb.identify_native_receipts(value, wire, 0, 4).unwrap()
  for role in [@duckdb.ValidationScan, @duckdb.NativeResult] {
    assert_eq(
      @duckdb.native_receipt_digest(ids, role),
      (
        "sha256:4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e11ba873c2f11161202b945",
        2, 1, 0,
      ),
    )
  }
}
