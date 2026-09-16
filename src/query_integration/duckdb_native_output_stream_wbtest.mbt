///|
fn native_stream_scan(value : @duckdb.NativeReceiving) -> Unit {
  receiving_metadata(value)
  let scan = receiving_validation(value)
  @duckdb.accept_native_receipt_chunk(value, scan, 3, [
    input_cursor("[null,null,null]"),
    input_cursor(
      "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
    ),
  ]).unwrap()
  @duckdb.finish_native_receipt(value, scan).unwrap()
}

///|
test "native output streams under backpressure without retaining completed row batches" {
  let value = native_receiving_fixture()
  @duckdb.stream_native_validation(
    value,
    receipt_wire_limits(),
    native_demand_physical(),
    3,
  ).unwrap()
  @duckdb.stream_native_output(
    value,
    100,
    native_retained_values(),
    receipt_wire_limits(),
    64,
    1,
  ).unwrap()
  native_stream_scan(value)
  let port = @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
    ("id", @duckdb.Float64),
  ]).unwrap()
  let text = StringBuilder()
  for bits in ["4008000000000000", "4000000000000000"] {
    @duckdb.accept_native_receipt_chunk(value, port, 1, [
      input_cursor("[\"" + bits + "\"]"),
    ]).unwrap()
    assert_eq(@duckdb.native_output_retained_rows(value), 1)
    while @duckdb.drain_native_output_row(value).unwrap() is Some(chunk) {
      text.write_string(chunk)
    }
    assert_eq(@duckdb.native_output_retained_rows(value), 0)
  }
  @duckdb.finish_native_receipt(value, port).unwrap()
  let (receipt, tail) = @duckdb.finish_native_output_stream(value)
    .unwrap()
    .unwrap()
  text.write_string(tail)
  assert_eq(text.to_string(), "[{\"id\":3},{\"id\":2}]")
  assert_true(@duckdb.native_output_stream_matches(value, receipt))
  assert_eq(@duckdb.native_validation_retained_rows(value), 0)
  let ids = @duckdb.identify_native_receipts(
    value,
    receipt_wire_limits(),
    5,
    89,
  ).unwrap()
  assert_eq(
    @duckdb.native_receipt_digest(ids, @duckdb.NativeResult),
    @execution.output_stream_identity(receipt),
  )
  @duckdb.abort_native_receiving(value)
  assert_false(@duckdb.native_output_stream_matches(value, receipt))
}

///|
test "native output stream refuses undrained overwrite and undrained receipt completion" {
  for overwrite in [false, true] {
    let value = native_receiving_fixture()
    @duckdb.stream_native_output(
      value,
      100,
      native_retained_values(),
      receipt_wire_limits(),
      64,
      1,
    ).unwrap()
    native_stream_scan(value)
    let port = @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    @duckdb.accept_native_receipt_chunk(value, port, 1, [
      input_cursor("[\"4008000000000000\"]"),
    ]).unwrap()
    let result = if overwrite {
      @duckdb.accept_native_receipt_chunk(value, port, 1, [
        input_cursor("[\"4000000000000000\"]"),
      ])
    } else {
      @duckdb.finish_native_receipt(value, port)
    }
    assert_true(result is Err(InvalidState))
    assert_eq(@duckdb.native_output_retained_rows(value), 0)
    assert_true(@duckdb.finish_native_output_stream(value) is Err(InvalidState))
  }
}

///|
test "native output encoding failure cannot precede required demand failure or publish partial material" {
  for demand_fails in [false, true] {
    let value = native_receiving_fixture()
    let demand = if demand_fails {
      { ..native_demand_physical(), max_work: 0, }
    } else {
      native_demand_physical()
    }
    @duckdb.stream_native_validation(value, receipt_wire_limits(), demand, 3).unwrap()
    @duckdb.stream_native_output(
      value,
      100,
      native_retained_values(),
      { ..receipt_wire_limits(), max_bytes: 1, },
      64,
      2,
    ).unwrap()
    native_stream_scan(value)
    let port = @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    @duckdb.accept_native_receipt_chunk(value, port, 2, [
      input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
    ]).unwrap()
    while @duckdb.drain_native_output_row(value).unwrap() is Some(_) {
      ()
    }
    @duckdb.finish_native_receipt(value, port).unwrap()
    assert_true(@duckdb.finish_native_output_stream(value) is Ok(None))
    let measured = @duckdb.measure_native_demand(value, demand)
    if demand_fails {
      assert_true(measured is Err(Operand(0, false, MeasurementWork)))
    } else {
      measured.unwrap() |> ignore
      assert_true(
        @duckdb.identify_native_receipts(value, receipt_wire_limits(), 5, 89)
        is Err(Stream(_)),
      )
    }
    assert_false(@duckdb.native_receiving_has_both(value))
  }
}
