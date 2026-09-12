///|
fn assert_wire(
  value : @value_admission.CheckedValue,
  expected : String,
  bytes : Int,
  nodes : Int,
  depth : Int,
) -> Unit raise {
  let out = @encode.writer(bytes, nodes, depth)
  @value_admission.emit_wire_value(value.value, out)
  assert_eq(@encode.finish(out), expected)
  let measurement = @encode.measuring_writer(bytes, nodes, depth)
  @value_admission.emit_wire_value(value.value, measurement)
  assert_eq(
    @encode.finish_measurement_usage(measurement),
    (bytes, nodes, depth),
  )
  for caps in [(bytes - 1, nodes, depth), (bytes, nodes - 1, depth)] {
    try {
      let short = @encode.measuring_writer(caps.0, caps.1, caps.2)
      @value_admission.emit_wire_value(value.value, short)
      ignore(@encode.finish_measurement_usage(short))
    } catch {
      @encode.OutputLimit => ()
      _ => assert_true(false)
    } noraise {
      _ => assert_true(false)
    }
  }
  if depth > 0 {
    try {
      let short = @encode.measuring_writer(bytes, nodes, depth - 1)
      @value_admission.emit_wire_value(value.value, short)
      ignore(@encode.finish_measurement_usage(short))
    } catch {
      @encode.OutputLimit => ()
      _ => assert_true(false)
    } noraise {
      _ => assert_true(false)
    }
  }
}

///|
test "typed wire fixed scalar and opaque object vectors" {
  // Expected text and UTF-8 counts are independently fixed, not product output.
  for
    (text, bytes, nodes, depth) in [
      ("null", 4, 1, 0),
      ("true", 4, 1, 0),
      ("1e+21", 5, 1, 0),
      ("\"é😀\\u0000\\n\\\"\\\\\"", 20, 1, 0),
      (
        "{\"$param\":\"literal\",\"literal\":[1,null],\"é\":\"😀\"}", 51, 6, 2,
      ),
      ("[]", 2, 1, 1),
      ("{}", 2, 1, 1),
    ] {
    assert_wire(
      accept(simple("json", nullable=true), text),
      text,
      bytes,
      nodes,
      depth,
    )
  }
  assert_wire(
    accept(simple("date"), "\"0000-02-29\""),
    "\"0000-02-29\"",
    12,
    1,
    0,
  )
  assert_wire(
    accept(simple("timestamp"), "\"2024-01-01T00:00:00.000Z\""),
    "\"2024-01-01T00:00:00.000Z\"",
    26,
    1,
    0,
  )
  assert_wire(
    accept(
      contract("{\"type\":\"vector\",\"nullable\":false,\"dimensions\":3}"),
      "[1,2.5,-3]",
    ),
    "[1,2.5,-3]",
    10,
    4,
    1,
  )
}

///|
test "decimal wire measures fixed scale rather than the coefficient or identity tag" {
  for
    (precision, scale, text, bytes) in [
      (3, 3, "\"0.001\"", 7),
      (4, 2, "\"-19.90\"", 8),
      (38, 38, "\"0.00000000000000000000000000000000000000\"", 42),
      (38, 0, "\"99999999999999999999999999999999999999\"", 40),
    ] {
    let type_ = contract(
      "{\"type\":\"decimal\",\"nullable\":false,\"precision\":" +
      precision.to_string() +
      ",\"scale\":" +
      scale.to_string() +
      "}",
    )
    assert_wire(accept(type_, text), text, bytes, 1, 0)
  }
}

///|
test "typed wire embedding charges repeated values and closes a failed prefix" {
  let value = accept(simple("string"), "\"é\"")
  let out = @encode.measuring_writer(11, 3, 1)
  @encode.begin_array(out)
  @value_admission.emit_wire_value(value.value, out)
  @value_admission.emit_wire_value(value.value, out)
  @encode.end_array(out)
  assert_eq(@encode.finish_measurement_usage(out), (11, 3, 1))
  let short = @encode.measuring_writer(6, 3, 1)
  @encode.begin_array(short)
  @value_admission.emit_wire_value(value.value, short)
  try @value_admission.emit_wire_value(value.value, short) catch {
    @encode.OutputLimit => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
  try @encode.finish_measurement_usage(short) catch {
    @encode.ClosedWriter => ()
    _ => assert_true(false)
  } noraise {
    _ => assert_true(false)
  }
}

///|
test "typed wire traverses deep values without recursion or whole output allocation" {
  let depth = 10000
  let text = "[".repeat(depth) + "null" + "]".repeat(depth)
  let value = accept(simple("json"), text)
  assert_wire(value, text, depth * 2 + 4, depth + 1, depth)
}
