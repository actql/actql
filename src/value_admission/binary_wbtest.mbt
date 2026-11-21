///|
test "BYTES admits only canonical padded base64 and preserves original octets" {
  let contract = typed_steps_contract("{\"type\":\"bytes\",\"nullable\":false}")
  let limits = { max_nodes: 1, max_depth: 0, max_text_bytes: 4, }
  for
    (wire, expected) in [
      ("", []),
      ("Zg==", [102]),
      ("Zm8=", [102, 111]),
      ("Zm9v", [102, 111, 111]),
      ("AP+A", [0, 255, 128]),
    ] {
    let source = Json::string(wire).stringify()
    let (checked, nodes, text) = admit_usage(
      contract,
      json_steps_cursor(source),
      limits,
    ).unwrap()
    guard checked.value is Binary(bytes) else { abort("expected BYTES") }
    assert_eq((nodes, text), (1, wire.length()))
    assert_eq(bytes_count(bytes), expected.length())
    assert_eq(bytes_wire_text(bytes), wire)
    assert_eq(
      Array::makei(expected.length(), index => {
        bytes_at(bytes, index).unwrap().to_int()
      }),
      expected,
    )
    assert_true(bytes_at(bytes, expected.length()) is None)
    assert_eq(typed_steps_wire(checked), source)
    assert_true(
      recheck_runtime_value(checked.value, contract, limits) is Some(_),
    )
  }

  for
    wire in [
      "Zg", "Zh==", "Zm9=", "Zm8_", "Zg==AAAA", "AA=\n", "====", "雪aaa",
    ] {
    let source = Json::string(wire).stringify()
    assert_true(
      admit_wire(contract, json_steps_cursor(source), {
        ..limits,
        max_text_bytes: 32,
      })
      is Err(ValueIssue(InvalidBytes, ..)),
      msg=wire,
    )
  }
  assert_true(
    admit_wire(contract, json_steps_cursor("\"Zg==\""), {
      ..limits,
      max_text_bytes: 3,
    })
    is Err(ValueIssue(BudgetExceeded, ..)),
  )
  assert_true(
    admit_wire(contract, json_steps_cursor("null"), limits)
    is Err(ValueIssue(UnexpectedNull, ..)),
  )
  assert_true(
    admit_wire(
      @contract.with_nullability(contract, true),
      json_steps_cursor("null"),
      limits,
    ).unwrap().value
    is Null,
  )
}

///|
test "BYTES retains distinct typed identity and bounds wire construction" {
  let bytes = b"\x00\xFF\x80"
  assert_true(bytes_value(bytes, 3) is None)
  let value = bytes_value(bytes, 4).unwrap()
  let limits = { max_nodes: 1, max_depth: 1, max_text_bytes: 4, }
  let contract = @contract.primitive(@contract.BytesType, nullable=false)
  let text = @contract.primitive(@contract.StringType, nullable=false)
  assert_true(recheck_runtime_value(value, text, limits) is None)
  let checked = recheck_runtime_value(value, contract, limits).unwrap()
  assert_eq(typed_steps_wire(checked), "\"AP+A\"")
  assert_eq(
    complete_order_key(checked, limits).unwrap(),
    "[\"bytes\",\"AP+A\"]",
  )
  assert_false(@contract.key_comparable(contract, text))
}
