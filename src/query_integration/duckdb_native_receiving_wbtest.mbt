///|
fn native_receiving_fixture(
  max_rows? : Int = 10,
  value_bytes? : Int = 1000,
  output_rows? : Int = 100,
  work? : Int = 1000,
  bytes? : Int = 10000,
  nodes? : Int = 1000,
) -> @duckdb.NativeReceiving {
  let (_, owner) = query_sequence_fixture(
    catalog=Some(query_amount_nullable_catalog()),
  )
  let query = @duckdb.compile_native_filter_select(
    owner,
    "main",
    "records",
    native_compile_limits(),
  ).unwrap()
  let scan = @duckdb.prepare_native_scan(query, 2, 1000).unwrap()
  @duckdb.prepare_native_receiving(
    scan,
    { max_rows, max_cells: 100, max_nodes: 100, max_text_bytes: 1000, },
    1000,
    { max_value_bytes: value_bytes, max_output_rows: output_rows, },
    { max_work: work, max_bytes: bytes, max_nodes: nodes, max_depth: 10, },
  ).unwrap()
}

///|
fn receiving_metadata(value : @duckdb.NativeReceiving) -> Unit {
  @duckdb.admit_native_table_metadata(
    value,
    1,
    [("table_type", @duckdb.Varchar)],
    [input_cursor("[\"BASE TABLE\"]")],
  ).unwrap()
}

///|
fn receiving_validation(
  value : @duckdb.NativeReceiving,
) -> @duckdb.NativeReceiptPort {
  @duckdb.begin_native_receipt(value, @duckdb.ValidationScan, [
    ("amount", @duckdb.Float64),
    ("id", @duckdb.Float64),
  ]).unwrap()
}

///|
test "native receiving owns both roles and preserves aggregate receipt ceilings" {
  for (limit, succeeds) in [(5, true), (4, false)] {
    let value = native_receiving_fixture(max_rows=limit)
    receiving_metadata(value)
    let validation = receiving_validation(value)
    @duckdb.accept_native_receipt_chunk(value, validation, 3, [
      input_cursor("[null,null,null]"),
      input_cursor(
        "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
      ),
    ]).unwrap()
    assert_false(@duckdb.native_receiving_has_both(value))
    @duckdb.finish_native_receipt(value, validation).unwrap()
    let native = @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    let accepted = @duckdb.accept_native_receipt_chunk(value, native, 2, [
      input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
    ])
    if succeeds {
      assert_true(accepted is Ok(_))
      @duckdb.finish_native_receipt(value, native).unwrap()
      assert_true(@duckdb.native_receiving_has_both(value))
      @duckdb.abort_native_receiving(value)
      assert_false(@duckdb.native_receiving_has_both(value))
    } else {
      assert_true(accepted is Err(Values(RowLimit)))
      assert_true(
        @duckdb.finish_native_receipt(value, native) is Err(InvalidState),
      )
      assert_false(@duckdb.native_receiving_has_both(value))
    }
  }
}

///|
test "native receiving rejects views missing metadata early native and foreign receipts" {
  for kind in ["VIEW", "LOCAL TEMPORARY", "base table"] {
    let value = native_receiving_fixture()
    assert_true(
      @duckdb.admit_native_table_metadata(
        value,
        1,
        [("table_type", @duckdb.Varchar)],
        [input_cursor("[\"" + kind + "\"]")],
      )
      is Err(NotBaseTable),
    )
    assert_true(
      @duckdb.begin_native_receipt(value, @duckdb.ValidationScan, [])
      is Err(InvalidState),
    )
  }
  let early = native_receiving_fixture()
  assert_true(
    @duckdb.begin_native_receipt(early, @duckdb.NativeResult, [])
    is Err(InvalidState),
  )
  let left = native_receiving_fixture()
  let right = native_receiving_fixture()
  receiving_metadata(left)
  receiving_metadata(right)
  let foreign = receiving_validation(left)
  let own = receiving_validation(right)
  assert_true(
    @duckdb.accept_native_receipt_chunk(right, foreign, 0, [
      input_cursor("[]"),
      input_cursor("[]"),
    ])
    is Err(ForeignReceipt),
  )
  assert_true(@duckdb.finish_native_receipt(right, own) is Err(InvalidState))
  // Misuse of the other receiver must not consume the foreign upstream state.
  assert_true(@duckdb.finish_native_receipt(left, foreign) is Ok(_))
}

///|
test "invalid unused scan values abort before native and empty receipts still finish separately" {
  let value = native_receiving_fixture()
  receiving_metadata(value)
  let validation = receiving_validation(value)
  assert_true(
    @duckdb.accept_native_receipt_chunk(value, validation, 1, [
      input_cursor("[false]"),
      input_cursor("[\"3ff0000000000000\"]"),
    ])
    is Err(Values(Cell(0, 0, _))),
  )
  assert_true(
    @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
      ("id", @duckdb.Float64),
    ])
    is Err(InvalidState),
  )
  let empty = native_receiving_fixture(max_rows=0)
  receiving_metadata(empty)
  let scan = receiving_validation(empty)
  @duckdb.accept_native_receipt_chunk(empty, scan, 0, [
    input_cursor("[]"),
    input_cursor("[]"),
  ]).unwrap()
  @duckdb.finish_native_receipt(empty, scan).unwrap()
  let output = @duckdb.begin_native_receipt(empty, @duckdb.NativeResult, [
    ("id", @duckdb.Float64),
  ]).unwrap()
  @duckdb.finish_native_receipt(empty, output).unwrap()
  assert_true(@duckdb.native_receiving_has_both(empty))
}
