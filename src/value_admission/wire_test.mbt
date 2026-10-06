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
test "resumable typed wire yields inside a long nested Text and cancels" {
  let text = String::make(130, 'a') + "😀"
  let payload = "[\"" + text + "\",[1,2]]"
  let expected = "{\"$json\":" + payload + "}"
  let value = accept(simple("json"), payload)
  // Payload: outer array, Text, inner array and two numbers = five nodes,
  // depth two. Its quoted Text is 136 bytes; array punctuation adds eight.
  // The typed JSON envelope adds ten bytes, one node and one depth level.
  let writer = @encode.writer(154, 6, 3)
  let cursor = @value_admission.start_wire_emit(value.value, writer)
  let mut polls = 0
  let mut largest = 0
  let mut done = false
  while !done && polls < 100 {
    let before = @encode.writer_progress(writer).0
    done = @value_admission.advance_wire_emit(cursor)
    largest = Int::max(largest, @encode.writer_progress(writer).0 - before)
    polls += 1
  }
  assert_true(done && polls > 3)
  assert_true(largest <= 68)
  assert_eq(@value_admission.wire_emit_pending_frames(cursor), 0)
  assert_eq(@encode.finish_text_usage(writer), (expected, 154, 6, 3))

  let writer = @encode.writer(154, 6, 3)
  let cursor = @value_admission.start_wire_emit(value.value, writer)
  for _ in 0..<5 {
    assert_false(@value_admission.advance_wire_emit(cursor))
  }
  // Polls open the JSON envelope (9 bytes), open its array (10), select
  // the Text (10), open its quote (11), then emit 64 ASCII bytes (75).
  // JsonEnd, the array continuation and the progressed Text remain owned.
  assert_eq(@encode.writer_progress(writer).0, 75)
  @value_admission.cancel_wire_emit(cursor)
  assert_eq(@value_admission.wire_emit_pending_frames(cursor), 0)
  assert_true(
    try {
      @encode.finish(writer) |> ignore
      false
    } catch {
      @encode.ClosedWriter => true
      _ => false
    },
  )
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
    if text == "null" {
      assert_wire(
        accept(simple("json", nullable=true), text),
        text,
        bytes,
        nodes,
        depth,
      )
    } else {
      assert_wire(
        accept(simple("json", nullable=true), text),
        "{\"$json\":" + text + "}",
        bytes + 10,
        nodes + 1,
        depth + 1,
      )
    }
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
  assert_wire(
    value,
    "{\"$json\":" + text + "}",
    depth * 2 + 14,
    depth + 2,
    depth + 1,
  )
}
