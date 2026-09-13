///|
fn received_identity_fixture(split? : Bool = false) -> @duckdb.NativeReceiving {
  let value = native_receiving_fixture()
  receiving_metadata(value)
  let scan = receiving_validation(value)
  if split {
    for id in ["4008000000000000", "3ff0000000000000", "4000000000000000"] {
      @duckdb.accept_native_receipt_chunk(value, scan, 1, [
        input_cursor("[null]"),
        input_cursor("[\"" + id + "\"]"),
      ]).unwrap()
    }
  } else {
    @duckdb.accept_native_receipt_chunk(value, scan, 3, [
      input_cursor("[null,null,null]"),
      input_cursor(
        "[\"4008000000000000\",\"3ff0000000000000\",\"4000000000000000\"]",
      ),
    ]).unwrap()
  }
  @duckdb.finish_native_receipt(value, scan).unwrap()
  let native = @duckdb.begin_native_receipt(value, @duckdb.NativeResult, [
    ("id", @duckdb.Float64),
  ]).unwrap()
  @duckdb.accept_native_receipt_chunk(value, native, 2, [
    input_cursor("[\"4008000000000000\",\"4000000000000000\"]"),
  ]).unwrap()
  @duckdb.finish_native_receipt(value, native).unwrap()
  value
}

///|
fn receipt_wire_limits() -> @execution.RowWireLimits {
  {
    max_columns: 2,
    max_order_work: 15,
    max_bytes: 89,
    max_nodes: 15,
    max_depth: 2,
  }
}

///|
test "empty receipts each consume their own array root and cannot be identified early" {
  let early = native_receiving_fixture()
  assert_true(
    @duckdb.identify_native_receipts(early, receipt_wire_limits(), 5, 89)
    is Err(InvalidState),
  )
  assert_true(
    @duckdb.admit_native_table_metadata(
      early,
      1,
      [("table_type", @duckdb.Varchar)],
      [input_cursor("[\"BASE TABLE\"]")],
    )
    is Err(InvalidState),
  )
  for nodes in [1, 2] {
    let owner = native_receiving_fixture()
    receiving_metadata(owner)
    let scan = receiving_validation(owner)
    @duckdb.finish_native_receipt(owner, scan).unwrap()
    let native = @duckdb.begin_native_receipt(owner, @duckdb.NativeResult, [
      ("id", @duckdb.Float64),
    ]).unwrap()
    @duckdb.finish_native_receipt(owner, native).unwrap()
    let result = @duckdb.identify_native_receipts(
      owner,
      { ..receipt_wire_limits(), max_bytes: 4, max_nodes: nodes, max_depth: 1, },
      0,
      4,
    )
    if nodes == 1 {
      assert_true(
        result is Err(Wire(NativeResult, Encoding(@encode.OutputLimit))),
      )
      assert_false(@duckdb.native_receiving_has_both(owner))
    } else {
      let ids = result.unwrap()
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
  }
}

///|
test "native receipts hash independent fixed typed-row preimages without combining receipts" {
  // Independent canonical preimages, hashed with Node crypto, not product output:
  // [{"amount":null,"id":3},{"amount":null,"id":1},{"amount":null,"id":2}]
  // [{"id":3},{"id":2}]
  for split in [false, true] {
    let owner = received_identity_fixture(split~)
    let ids = @duckdb.identify_native_receipts(
      owner,
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
    assert_eq(
      @duckdb.native_receipt_field(ids, @duckdb.ValidationScan, 0),
      Some("amount"),
    )
    assert_eq(
      @duckdb.native_receipt_field(ids, @duckdb.ValidationScan, 1),
      Some("id"),
    )
    assert_eq(
      @duckdb.native_receipt_field(ids, @duckdb.NativeResult, 0),
      Some("id"),
    )
    assert_eq(@duckdb.native_receipt_field(ids, @duckdb.NativeResult, 1), None)
    assert_true(@duckdb.native_receipts_match(ids, owner))
    assert_false(
      @duckdb.native_receipts_match(ids, received_identity_fixture()),
    )
    @duckdb.abort_native_receiving(owner)
    assert_false(@duckdb.native_receipts_match(ids, owner))
  }
}

///|
test "canonical receipt and physical hashing ceilings are separate cumulative limits" {
  let limits = receipt_wire_limits()
  for
    (case, wire, rows, bytes) in [
      (0, limits, 4, 89),
      (1, limits, 5, 88),
      (2, { ..limits, max_bytes: 88, }, 5, 89),
      (3, { ..limits, max_nodes: 14, }, 5, 89),
      (4, { ..limits, max_nodes: 10, }, 5, 89),
      (5, { ..limits, max_order_work: 14, }, 5, 89),
      (6, { ..limits, max_nodes: 0, }, 5, 89),
    ] {
    let owner = received_identity_fixture()
    let result = @duckdb.identify_native_receipts(owner, wire, rows, bytes)
    match case {
      0 => assert_true(result is Err(ReceiptRows))
      1 => assert_true(result is Err(ReceiptBytes))
      5 => assert_true(result is Err(Wire(NativeResult, OrderLimit)))
      6 => assert_true(result is Err(InvalidLimits))
      _ =>
        assert_true(
          result is Err(Wire(NativeResult, Encoding(@encode.OutputLimit))),
        )
    }
    assert_false(@duckdb.native_receiving_has_both(owner))
    assert_true(
      @duckdb.identify_native_receipts(owner, limits, 5, 89)
      is Err(InvalidState),
    )
  }
}
