///|
test "JSON values keep their domain in the canonical typed wire" {
  let value = accept(simple("json"), "1")
  let output = @encode.writer(100, 10, 10)
  @value_admission.emit_checked_wire_value(value, output)
  assert_eq(@encode.finish(output), "{\"$json\":1}")
  let scalar = accept(simple("number"), "1")
  let output = @encode.writer(100, 10, 10)
  @value_admission.emit_checked_wire_value(scalar, output)
  assert_eq(@encode.finish(output), "1")
}

///|
test "typed JSON roots remain nonnullable and wire round trip without scalar coercion" {
  for
    (source, wire) in [
      ("null", "{\"$json\":null}"),
      ("true", "{\"$json\":true}"),
      ("1.00e2", "{\"$json\":100}"),
      ("\"text\"", "{\"$json\":\"text\"}"),
      ("[null,true,1]", "{\"$json\":[null,true,1]}"),
      ("{\"$json\":null}", "{\"$json\":{\"$json\":null}}"),
    ] {
    let (value, _, _) = @value_admission.admit_json_literal(source, limits()).unwrap()
    assert_true(value.contract.shape is @contract.Json)
    assert_eq(value.contract.nullable, false)
    assert_true(@value_admission.json_payload(value.value) is Some(_))
    let output = @encode.writer(1000, 100, 10)
    @value_admission.emit_checked_wire_value(value, output)
    assert_eq(@encode.finish(output), wire)
    let reread = @value_admission.admit_wire(
      value.contract,
      owned(parsed(wire)),
      limits(),
    ).unwrap()
    let output = @encode.writer(1000, 100, 10)
    @value_admission.emit_checked_wire_value(reread, output)
    assert_eq(@encode.finish(output), wire)
    assert_true(
      @value_admission.recheck_runtime_value(
        reread.value,
        value.contract,
        limits(),
      )
      is Some(_),
    )
    assert_true(
      @value_admission.recheck_runtime_value(
        reread.value,
        simple("number"),
        limits(),
      )
      is None,
    )
  }
  let sql_null = accept(simple("json", nullable=true), "null")
  assert_true(sql_null.value is @value_admission.Null)
  let json_null = @value_admission.admit_json_literal("null", limits()).unwrap().0
  assert_true(!(json_null.value is @value_admission.Null))
  assert_true(
    @value_admission.admit_wire(simple("json"), owned(parsed("null")), limits())
    is Err(_),
  )
}

///|
test "JSON data keys and strings survive typed admission and identity spelling" {
  let (value, nodes, bytes) = @value_admission.admit_json_literal(
    "{\"e\\u0301\":\"e\\u0301\\r\\n\",\"é\":1}",
    limits(),
  ).unwrap()
  assert_eq(nodes, 3)
  assert_eq(bytes, 10)
  let output = @encode.writer(1000, 100, 10)
  @value_admission.emit_checked_wire_value(value, output)
  assert_eq(
    @encode.finish(output),
    "{\"$json\":{\"e\u{0301}\":\"e\u{0301}\\r\\n\",\"é\":1}}",
  )
}

///|
test "JSON precision and duplicate payload budgets cannot be bypassed by typed literal" {
  assert_true(
    @value_admission.admit_json_literal("9007199254740993", limits())
    is Err(
      @value_admission.JsonLiteralParse(
        { issue: @source.NumberPrecisionLoss, .. }
      )
    ),
  )
  assert_true(
    @value_admission.admit_json_literal(
      "{\"a\":1,\"a\":[1,2]}",
      limits(nodes=4),
    )
    is Err(@value_admission.JsonLiteralParse({ issue: @source.NodeLimit, .. })),
  )
  let (value, nodes, _) = @value_admission.admit_json_literal(
    "{\"a\":1,\"a\":2}",
    limits(),
  ).unwrap()
  assert_eq(nodes, 3)
  let output = @encode.writer(100, 10, 10)
  @value_admission.emit_checked_wire_value(value, output)
  assert_eq(@encode.finish(output), "{\"$json\":{\"a\":1}}")
}
