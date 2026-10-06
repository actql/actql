///|
test "Events projection row names consume cumulative output text capacity" {
  let mut clock = ""
  for _ in 0..<513 {
    clock += "a"
  }
  let owner = bound_pipeline(
    "[{\"values\":{\"schema\":{\"" +
    clock +
    "\":{\"type\":\"number\",\"nullable\":false}," +
    "\"event_id\":{\"type\":\"number\",\"nullable\":false}," +
    "\"payload\":{\"type\":\"string\",\"nullable\":false}," +
    "\"session_start_ms\":{\"type\":\"number\",\"nullable\":false}," +
    "\"session_end_ms\":{\"type\":\"number\",\"nullable\":false}," +
    "\"session_id\":{\"type\":\"string\",\"nullable\":false}}," +
    "\"rows\":[]},\"as\":\"session_rows\"}]",
  )
  // Names cost 513 + 8 + 7 + 16 + 14 + 10 = 568 bytes per row.
  // Payload costs one byte. The independent session identity is 22 bytes
  // for IDs 1..9 and 24 bytes for IDs 10..61. Total text is therefore
  // 9*591 + 52*593 = 36155; each row also has seven logical nodes.
  let limits : ValueLimits = {
    max_nodes: 427,
    max_text_bytes: 36155,
    max_depth: 2,
    max_work: 36582,
  }
  for (text_limit, accepted) in [(36155, 61), (36154, 60), (10000, 16)] {
    let output = prepare_admitted_output(owner, Step(0), 61, {
      ..limits,
      max_text_bytes: text_limit,
    }).unwrap()
    let schema = output.buffer.schema
    for row in 0..<61 {
      let id = (row + 1).to_string()
      let identity = "session:12:v:" +
        id.length().to_string() +
        ":" +
        id +
        ":v:" +
        id.length().to_string() +
        ":" +
        id
      let appended = append_admitted_output_cells(output, 6, column => {
        let field = @schema.field_at(schema, column).unwrap()
        let wire = match @schema.reference_name(field.name) {
          "event_id" => id
          "session_end_ms" => "22"
          "session_id" => "\"" + identity + "\""
          "payload" => "\"a\""
          _ => "12"
        }
        Some(
          @admitted.admit(field.contract, input_cursor(wire), {
            max_nodes: 1,
            max_text_bytes: 24,
            max_depth: 2,
          }).unwrap(),
        )
      })
      if row < accepted {
        assert_true(appended is Ok(_))
        assert_eq(output.buffer.rows.length(), row + 1)
      } else {
        assert_true(appended is Err(CaptureLimit))
        assert_true(output.buffer.rows.is_empty())
        assert_true(finish_admitted_output(output) is Err(ClosedCapture))
        assert_false(cancel_admitted_output(output))
        break
      }
    }
    if accepted == 61 {
      let material = finish_admitted_output(output).unwrap()
      assert_eq(admitted_output_row_count(material), 61)
      assert_eq(admitted_output_usage(material), {
        nodes: 427,
        text_bytes: 36155,
        work: 36582,
      })
    }
  }
}
