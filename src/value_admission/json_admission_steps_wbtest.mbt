///|
fn json_steps_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json(text, {
      max_input_bytes: 10000,
      max_nodes: 1000,
      max_depth: 100,
    }).unwrap(),
    {
      max_nodes: 1000,
      max_depth: 100,
      max_string_bytes: 10000,
      max_total_string_bytes: 10000,
    },
  ).unwrap()
}

///|
fn finish_json_steps(
  admission : JsonAdmission,
) -> Result[(CheckedValue, Int, Int), Issue] {
  for _ in 0..<10000 {
    match advance_json_admission(admission) {
      JsonAdmissionContinue => ()
      JsonAdmissionComplete(value, nodes, text) =>
        return Ok((value, nodes, text))
      JsonAdmissionFailed(issue) => return Err(issue)
      JsonAdmissionTerminal => abort("premature terminal")
    }
  }
  cancel_json_admission(admission)
  abort("JSON admission did not terminate")
}

///|
test "resumable JSON admission canonicalizes objects without losing NULL or wire identities" {
  let cursor = json_steps_cursor(
    "{\"z\":[null,2],\"a\":{\"key\":[1],\"definition\":\"N\"}}",
  )
  let limits : Limits = { max_nodes: 9, max_depth: 3, max_text_bytes: 17, }
  let admission = start_json_admission(cursor, limits).unwrap()
  let (checked, nodes, text) = finish_json_steps(admission).unwrap()
  assert_eq((nodes, text), (8, 16))
  let writer = @encode.writer(10000, 1000, 100)
  emit_checked_wire_value(checked, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"a\":{\"definition\":\"N\",\"key\":[1]},\"z\":[null,2]}",
  )
  assert_eq(
    (nodes, text),
    {
      let (_, n, t) = admit_usage(
        @contract.primitive(JsonType, nullable=false),
        cursor,
        limits,
      ).unwrap()
      (n, t)
    },
  )
  cancel_json_admission(admission)
  assert_true(advance_json_admission(admission) is JsonAdmissionTerminal)
  let writer = @encode.writer(10000, 1000, 100)
  emit_checked_wire_value(checked, writer)
  assert_eq(
    @encode.finish(writer),
    "{\"a\":{\"definition\":\"N\",\"key\":[1]},\"z\":[null,2]}",
  )
}

///|
test "resumable JSON admission preserves bound failures and cancellation" {
  let cursor = json_steps_cursor(
    "{\"z\":[null,2],\"a\":{\"key\":[1],\"definition\":\"N\"}}",
  )
  for
    limits in [
      { max_nodes: 0, max_depth: 100, max_text_bytes: 10000, },
      { max_nodes: 7, max_depth: 100, max_text_bytes: 10000, },
      { max_nodes: 1000, max_depth: 2, max_text_bytes: 10000, },
      { max_nodes: 1000, max_depth: 100, max_text_bytes: 15, },
    ] {
    let admission = start_json_admission(cursor, limits).unwrap()
    assert_true(finish_json_steps(admission) is Err(_))
    assert_true(admission.frames.is_empty())
    assert_true(admission.value is None)
  }
  let admission = start_json_admission(cursor, {
    max_nodes: 1000,
    max_depth: 100,
    max_text_bytes: 10000,
  }).unwrap()
  assert_true(advance_json_admission(admission) is JsonAdmissionContinue)
  assert_true(advance_json_admission(admission) is JsonAdmissionContinue)
  cancel_json_admission(admission)
  cancel_json_admission(admission)
  assert_true(advance_json_admission(admission) is JsonAdmissionTerminal)
  assert_true(admission.frames.is_empty())
  assert_true(admission.root is None)
}
