///|
test "original Contract body inventory retains native text date timestamp and array admission" {
  let cases = [
    (@contract.StringType, false, "\"original\""),
    (@contract.StringType, true, "null"),
    (@contract.DateType, true, "\"2024-02-29\""),
    (@contract.TimestampType, true, "\"2024-02-29T12:34:56.123456789Z\""),
  ]
  for (kind, nullable, wire) in cases {
    let original = @contract.primitive(kind, nullable~)
    let cursor = json_steps_cursor(wire)
    let geometry = @decode.observe_subtree_construction_geometry(cursor)
    let body = contract_value_body_construction_inventory(original, geometry).unwrap()
    assert_eq(body.values.records, 1L)
    assert_eq(body.owned_value_utf16_units, 0L)
    assert_eq(body.owned_decimal_scratch_utf16_units, 0L)
    let admitted = admit_usage(original, cursor, {
        max_nodes: 1,
        max_depth: 0,
        max_text_bytes: 100,
      }).unwrap().0
    assert_true(physical_equal(admitted.contract, original))
    assert_eq(typed_steps_wire(admitted), wire)
  }
  let item = @contract.primitive(@contract.StringType, nullable=false)
  let original = @contract.array_contract(item, nullable=false).unwrap()
  let cursor = json_steps_cursor("[\"a\",\"b\"]")
  let geometry = @decode.observe_subtree_construction_geometry(cursor)
  let body = contract_value_body_construction_inventory(original, geometry).unwrap()
  assert_eq((body.values.records, body.values.reference_items), (4L, 2L))
  assert_eq(body.owned_value_utf16_units, 0L)
  let admitted = admit_usage(original, cursor, {
      max_nodes: 3,
      max_depth: 1,
      max_text_bytes: 2,
    }).unwrap().0
  assert_true(physical_equal(admitted.contract, original))
  assert_eq(typed_steps_wire(admitted), "[\"a\",\"b\"]")
  let short = start_typed_admission(original, cursor, {
    max_nodes: 2,
    max_depth: 1,
    max_text_bytes: 2,
  }).unwrap()
  assert_true(
    advance_typed_admission(short)
    is TypedAdmissionFailed(ValueIssue(BudgetExceeded, ..)),
  )
  assert_true(short.frames.is_empty() && short.root is None)
  cancel_typed_admission(short)
  assert_eq(@decode.array_length(cursor), Some(2))
}

///|
test "original Contract body inventory refuses unsupported constructors and malformed geometry" {
  let geometry = @decode.observe_subtree_construction_geometry(
    json_steps_cursor("\"borrowed\""),
  )
  let json = @contract.primitive(@contract.JsonType, nullable=false)
  let vector = @contract.vector_contract(2.0, nullable=false).unwrap()
  let content = @contract.content_reference_contract(
    Some("text/plain"),
    nullable=false,
    max_name_bytes=100,
  ).unwrap()
  for
    original in [
      json,
      vector,
      content,
      @contract.array_contract(json, nullable=false).unwrap(),
    ] {
    assert_true(
      contract_value_body_construction_inventory(original, geometry) is None,
    )
  }
  let original = @contract.primitive(@contract.StringType, nullable=false)
  assert_true(
    contract_value_body_construction_inventory(original, {
      ..geometry,
      nodes: geometry.nodes + 1,
    })
    is None,
  )
}

///|
test "Decimal row text upper bound follows original coefficient and canonical wire owners" {
  for
    (precision, scale, text) in [
      (1, 0, "-9"),
      (8, 2, "-999999.99"),
      (38, 0, "-" + "9".repeat(38)),
      (38, 38, "-0." + "9".repeat(38)),
    ] {
    let original = @contract.decimal_contract(precision, scale, nullable=false).unwrap()
    let wire = "\"" + text + "\""
    let cursor = json_steps_cursor(wire)
    let geometry = @decode.observe_subtree_construction_geometry(cursor)
    let (value, nodes, bytes) = admit_usage(original, cursor, {
      max_nodes: 1,
      max_depth: 0,
      max_text_bytes: 100,
    }).unwrap()
    assert_eq(nodes, 1)
    assert_eq(canonical_scalar_text(value, 100), Some(text))
    assert_eq(typed_steps_wire(value), wire)
    // Sign, point and leading zero are codec syntax, not Number conversion.
    // Precision remains the original admitted Contract's actual precision.
    assert_true(bytes <= precision + 3)
    assert_true(wire.length() <= precision + 5)
    let body = contract_value_body_construction_inventory(original, geometry).unwrap()
    assert_eq(body.owned_value_utf16_units, precision.to_int64() + 1L)
    assert_eq(
      body.owned_decimal_scratch_utf16_units,
      2L + 3L * Int::min(geometry.max_text_utf16, precision).to_int64(),
    )
  }
  let original = @contract.decimal_contract(38, 38, nullable=true).unwrap()
  let (absent, nodes, text) = admit_usage(original, json_steps_cursor("null"), {
    max_nodes: 1,
    max_depth: 0,
    max_text_bytes: 0,
  }).unwrap()
  assert_eq((nodes, text), (1, 0))
  assert_eq(typed_steps_wire(absent), "null")
}
