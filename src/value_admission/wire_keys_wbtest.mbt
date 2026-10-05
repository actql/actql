///|
test "typed wire yields inside a long object key" {
  let name = String::make(4096, 'k')
  let builder = prepare_object_value(1).unwrap()
  assert_true(append_object_field(builder, name, null_value()))
  let value = finish_object_value(builder).unwrap()
  let expected = "{\"" + name + "\":null}"
  let writer = @encode.writer(4105, 2, 1)
  let cursor = start_wire_emit(value, writer)
  let mut complete = false
  let mut polls = 0
  for _ in 0..<1000 {
    let before = @encode.writer_progress(writer).0
    complete = advance_wire_emit(cursor)
    assert_true(@encode.writer_progress(writer).0 - before <= 68)
    polls += 1
    if complete {
      break
    }
  }
  assert_true(complete && polls > 60)
  assert_eq(@encode.finish_text_usage(writer), (expected, 4105, 2, 1))
}

///|
test "typed long key wire preserves byte bounds and cancellation custody" {
  let name = String::make(256, 'k')
  let builder = prepare_object_value(1).unwrap()
  assert_true(append_object_field(builder, name, null_value()))
  let value = finish_object_value(builder).unwrap()
  for bytes in [265, 264] {
    let w = @encode.measuring_writer(bytes, 2, 1)
    let result = try {
      emit_wire_value(value, w)
      @encode.finish_measurement_usage(w)
    } catch {
      @encode.OutputLimit => (-1, -1, -1)
      _ => abort("unexpected wire failure")
    }
    assert_eq(result, if bytes == 265 { (265, 2, 1) } else { (-1, -1, -1) })
  }
  let w = @encode.writer(265, 2, 1)
  let cursor = start_wire_emit(value, w)
  for _ in 0..<5 {
    assert_false(advance_wire_emit(cursor))
  }
  assert_true(@encode.writer_progress(w).0 > 1)
  cancel_wire_emit(cursor)
  assert_eq(wire_emit_pending_frames(cursor), 0)
  assert_true(
    try {
      @encode.finish(w) |> ignore
      false
    } catch {
      @encode.ClosedWriter => true
      _ => false
    },
  )
}

///|
test "reference wire yields through the retained canonical metadata envelope" {
  let name = String::make(256, 'k')
  let text = String::make(4096, 'g')
  let expected = artifact_reference_wire().replace(
    old="\"issuer_evidence\":{}",
    new="\"issuer_evidence\":{\"" + name + "\":[\"" + text + "\",null]}",
  )
  let checked = issue_reference(
    bind_reference_issuer((_, wire) => wire == expected, _ => true),
    reference_contract("{\"type\":\"artifact_ref\",\"nullable\":false}"),
    expected,
    { max_bytes: 10000, max_nodes: 64, max_depth: 5, max_text_units: 10000, },
  ).unwrap()
  // The fixed envelope has 18 nodes; evidence adds an array, Text and NULL.
  // It is ASCII, so the authored fixture length is its independent byte count.
  let w = @encode.writer(expected.length(), 21, 4)
  let cursor = start_wire_emit(checked.value, w)
  let mut polls = 0
  let mut done = false
  for _ in 0..<1000 {
    let before = @encode.writer_progress(w).0
    done = advance_wire_emit(cursor)
    assert_true(@encode.writer_progress(w).0 - before <= 68)
    polls += 1
    if done {
      break
    }
  }
  assert_true(done && polls > 100)
  assert_eq(@encode.finish_text_usage(w), (expected, expected.length(), 21, 4))
  let w = @encode.measuring_writer(expected.length(), 21, 4)
  let cursor = start_wire_emit(checked.value, w)
  for _ in 0..<30 {
    assert_false(advance_wire_emit(cursor))
  }
  assert_true(wire_emit_pending_frames(cursor) > 0)
  cancel_wire_emit(cursor)
  @encode.cancel_writer(w)
  assert_eq(wire_emit_pending_frames(cursor), 0)
  assert_true(
    try {
      @encode.finish_measurement(w) |> ignore
      false
    } catch {
      @encode.ClosedWriter => true
      _ => false
    },
  )
}
