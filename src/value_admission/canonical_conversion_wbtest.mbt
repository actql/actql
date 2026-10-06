///|
test "canonical conversion builds nested data in finite individual frames" {
  let value = @identity.from_json({ "a": [1, null], "b": "x" }, 100, 8, 100)
  // Five JSON nodes and three ASCII bytes (two field names and one value).
  for (nodes, bytes, accepted) in [(5, 3, true), (4, 3, false), (5, 2, false)] {
    let cursor = start_canonical_conversion(value, {
      max_nodes: nodes,
      max_depth: 8,
      max_text_bytes: bytes,
    }).unwrap()
    let mut terminal = false
    for _ in 0..<32 {
      match advance_canonical_conversion(cursor) {
        CanonicalConversionContinue => ()
        CanonicalConversionFailed => {
          assert_false(accepted)
          terminal = true
          break
        }
        CanonicalConversionComplete(value) => {
          assert_true(accepted)
          let writer = @encode.writer(100, 100, 8)
          emit_wire_value(value, writer)
          assert_eq(@encode.finish(writer), "{\"a\":[1,null],\"b\":\"x\"}")
          terminal = true
          break
        }
      }
    }
    assert_true(terminal)
    cancel_canonical_conversion(cursor)
    cancel_canonical_conversion(cursor)
    assert_true(cursor.pending.is_empty())
    assert_true(cursor.value is None)
    assert_true(
      advance_canonical_conversion(cursor) is CanonicalConversionFailed,
    )
  }
}

///|
test "canonical capture restores JSON null and scalar domains without key normalization" {
  let contract = @contract.primitive(@contract.JsonType, nullable=true)
  for
    wire in [
      "{\"$json\":null}", "{\"$json\":true}", "{\"$json\":1}", "{\"$json\":\"x\"}",
      "{\"$json\":{\"e\u{301}\":null,\"é\":1}}", "null",
    ] {
    let source = @source.parse_json_bytes_preserving(@utf8.encode(wire), {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap()
    let canonical = @identity.from_source(source, 100, 10, 1000, data_keys=true)
    let limits = { max_nodes: 100, max_depth: 10, max_text_bytes: 1000, }
    let cursor = start_canonical_conversion(
      canonical,
      limits,
      contract=Some(contract),
      wire=true,
    ).unwrap()
    let mut complete = false
    for _ in 0..<100 {
      match advance_canonical_conversion(cursor) {
        CanonicalConversionContinue => ()
        CanonicalConversionFailed => abort("canonical JSON restore failed")
        CanonicalConversionComplete(value) => {
          assert_true(recheck_runtime_value(value, contract, limits) is Some(_))
          let writer = @encode.writer(1000, 100, 10)
          emit_wire_value(value, writer)
          assert_eq(@encode.finish(writer), wire)
          assert_eq(value is Null, wire == "null")
          complete = true
          break
        }
      }
    }
    assert_true(complete)
  }
}

///|
test "canonical conversion can stop while a large array is still private" {
  let value = @identity.from_json(
    Json::array(Array::make(2048, Json::number(1))),
    2049,
    2,
    0,
  )
  let cursor = start_canonical_conversion(value, {
    max_nodes: 2049,
    max_depth: 2,
    max_text_bytes: 0,
  }).unwrap()
  for _ in 0..<64 {
    assert_true(
      advance_canonical_conversion(cursor) is CanonicalConversionContinue,
    )
  }
  assert_true(cursor.nodes < 2049)
  assert_true(cursor.value is None || !cursor.pending.is_empty())
  cancel_canonical_conversion(cursor)
  assert_true(cursor.pending.is_empty())
  assert_true(cursor.value is None)
}

///|
test "canonical conversion restores typed decimal timestamp and vector leaves" {
  let contract = @contract.object_contract(
    [
      ("decimal", @contract.decimal_contract(38, 2, nullable=false).unwrap()),
      (
        "timestamp",
        @contract.primitive(@contract.TimestampType, nullable=false),
      ),
      ("vector", @contract.vector_contract(2, nullable=false).unwrap()),
    ],
    nullable=false,
    max_fields=3,
    max_name_bytes=100,
  ).unwrap()
  let value = @identity.from_json(
    {
      "decimal": "123456789012345678901234567890123456.78",
      "timestamp": "2026-10-01T00:00:00.000Z",
      "vector": [1, 2],
    },
    100,
    8,
    1000,
  )
  let limits = { max_nodes: 100, max_depth: 8, max_text_bytes: 1000, }
  let cursor = start_canonical_conversion(
    value,
    limits,
    contract=Some(contract),
  ).unwrap()
  let mut terminal = false
  for _ in 0..<100 {
    match advance_canonical_conversion(cursor) {
      CanonicalConversionContinue => ()
      CanonicalConversionFailed => {
        assert_true(false)
        return
      }
      CanonicalConversionComplete(value) => {
        assert_true(recheck_runtime_value(value, contract, limits) is Some(_))
        let writer = @encode.writer(1000, 100, 8)
        emit_wire_value(value, writer)
        assert_eq(
          @encode.finish(writer),
          "{\"decimal\":\"123456789012345678901234567890123456.78\",\"timestamp\":\"2026-10-01T00:00:00.000Z\",\"vector\":[1,2]}",
        )
        terminal = true
        break
      }
    }
  }
  assert_true(terminal)
  cancel_canonical_conversion(cursor)
}
