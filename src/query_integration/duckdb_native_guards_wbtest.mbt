///|
test "native value measurement spans receipts with exact physical and logical bounds" {
  // Scan: two (null, 2) rows = 10 canonical value bytes, four nodes,
  // six row/cell work units. Native: two 2 rows = 2 bytes, two nodes,
  // four work units. These are value sums, not receipt JSON byte lengths.
  for
    (work, bytes, nodes, output_rows, expected) in [
      (10, 12, 6, 2, "success"),
      (9, 12, 6, 2, "work"),
      (10, 11, 6, 2, "bytes"),
      (10, 12, 5, 2, "nodes"),
      (10, 12, 4, 2, "zero remaining nodes"),
      (10, 12, 6, 1, "rows"),
    ] {
    let value = native_receiving_fixture(
      work~,
      bytes~,
      nodes~,
      output_rows~,
      value_bytes=4,
    )
    receiving_metadata(value)
    let scan = receiving_validation(value)
    @duckdb.accept_native_receipt_chunk(value, scan, 2, [
      input_cursor("[null,null]"),
      input_cursor("[\"4000000000000000\",\"4000000000000000\"]"),
    ]).unwrap()
    @duckdb.finish_native_receipt(value, scan).unwrap()
    let native = @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    @duckdb.accept_native_receipt_chunk(value, native, 2, [
      input_cursor("[\"4000000000000000\",\"4000000000000000\"]"),
    ]).unwrap()
    let result = @duckdb.finish_native_receipt(value, native)
    match expected {
      "success" => {
        result.unwrap()
        assert_true(@duckdb.native_receiving_has_both(value))
      }
      "work" =>
        assert_true(result is Err(Guard(NativeResult, 1, 0, MeasurementWork)))
      "rows" =>
        assert_true(result is Err(Guard(NativeResult, 1, -1, OutputRows)))
      "zero remaining nodes" =>
        assert_true(
          result
          is Err(Guard(NativeResult, 0, 0, Measurement(@encode.OutputLimit))),
        )
      _ =>
        assert_true(
          result
          is Err(Guard(NativeResult, 1, 0, Measurement(@encode.OutputLimit))),
        )
    }
    if expected != "success" {
      assert_false(@duckdb.native_receiving_has_both(value))
      assert_true(
        @duckdb.finish_native_receipt(value, native) is Err(InvalidState),
      )
    }
  }
}

///|
test "native scan value guard includes unused nullable column before native SQL" {
  let value = native_receiving_fixture(value_bytes=3)
  receiving_metadata(value)
  let scan = receiving_validation(value)
  @duckdb.accept_native_receipt_chunk(value, scan, 1, [
    input_cursor("[null]"),
    input_cursor("[\"3ff0000000000000\"]"),
  ]).unwrap()
  assert_true(
    @duckdb.finish_native_receipt(value, scan)
    is Err(Guard(ValidationScan, 0, 0, ValueBytes)),
  )
  assert_true(@duckdb.finish_native_receipt(value, scan) is Err(InvalidState))
  assert_true(
    @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
      ("id", @duckdb.Float64),
    ])
    is Err(InvalidState),
  )
}

///|
test "native scan guard failure is independent of transport chunk width" {
  for width in [1, 7, 1000] {
    let value = native_receiving_fixture(value_bytes=3)
    receiving_metadata(value)
    let scan = receiving_validation(value)
    let mut start = 0
    while start < 9 {
      let end = (start + width).min(9)
      let mut amounts = "["
      let mut ids = "["
      for row in start..<end {
        if row != start {
          amounts += ","
          ids += ","
        }
        amounts += if row == 7 { "null" } else { "\"3ff0000000000000\"" }
        ids += "\"3ff0000000000000\""
      }
      let result = @duckdb.accept_native_receipt_chunk(
        value,
        scan,
        end - start,
        [input_cursor(amounts + "]"), input_cursor(ids + "]")],
      )
      result.unwrap()
      start = end
    }
    assert_true(
      @duckdb.finish_native_receipt(value, scan)
      is Err(Guard(ValidationScan, 7, 0, ValueBytes)),
    )
    assert_false(@duckdb.native_receiving_has_both(value))
  }
}

///|
test "native guard preparation rejects negative limits but zero is exhaustion not bad configuration" {
  let scan = @duckdb.native_receiving_scan(native_receiving_fixture())
  assert_true(
    @duckdb.prepare_native_receiving(
      scan,
      { max_rows: 10, max_cells: 100, max_nodes: 100, max_text_bytes: 1000, },
      1000,
      { max_value_bytes: 4, max_output_rows: 10, },
      { max_work: 10, max_bytes: 100, max_nodes: -1, max_depth: 0, },
    )
    is Err(InvalidLimits),
  )
  let value = native_receiving_fixture(nodes=0)
  receiving_metadata(value)
  let port = receiving_validation(value)
  @duckdb.accept_native_receipt_chunk(value, port, 1, [
    input_cursor("[null]"),
    input_cursor("[\"3ff0000000000000\"]"),
  ]).unwrap()
  assert_true(
    @duckdb.finish_native_receipt(value, port)
    is Err(Guard(ValidationScan, 0, 0, Measurement(@encode.OutputLimit))),
  )
  let empty = native_receiving_fixture(
    work=0,
    bytes=0,
    nodes=0,
    output_rows=0,
    value_bytes=0,
  )
  receiving_metadata(empty)
  let scan_port = receiving_validation(empty)
  @duckdb.finish_native_receipt(empty, scan_port).unwrap()
  let output_port = @duckdb.begin_native_receipt(empty, @duckdb.NativeResult, [
    ("id", @duckdb.Float64),
  ]).unwrap()
  @duckdb.finish_native_receipt(empty, output_port).unwrap()
  assert_true(@duckdb.native_receiving_has_both(empty))
}

///|
test "full scan admission precedes guard measurement as in the Local fixed input path" {
  for split in [false, true] {
    let value = native_receiving_fixture(value_bytes=3)
    receiving_metadata(value)
    let port = receiving_validation(value)
    let result = if split {
      @duckdb.accept_native_receipt_chunk(value, port, 1, [
        input_cursor("[null]"),
        input_cursor("[\"3ff0000000000000\"]"),
      ]).unwrap()
      @duckdb.accept_native_receipt_chunk(value, port, 1, [
        input_cursor("[null]"),
        input_cursor("[\"7ff0000000000000\"]"),
      ])
    } else {
      @duckdb.accept_native_receipt_chunk(value, port, 2, [
        input_cursor("[null,null]"),
        input_cursor("[\"3ff0000000000000\",\"7ff0000000000000\"]"),
      ])
    }
    assert_true(result is Err(Values(Cell(1, 1, _))))
    assert_true(@duckdb.finish_native_receipt(value, port) is Err(InvalidState))
  }
}
