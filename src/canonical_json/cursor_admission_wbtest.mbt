///|
fn canonical_cursor(text : String) -> @decode.Cursor {
  @decode.admit(
    @source.parse_json_bytes_preserving(@utf8.encode(text), {
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
fn complete_cursor(
  admission : CursorAdmission,
) -> Result[(CanonicalValue, Int, Int), CanonicalFailure] {
  for _ in 0..<10000 {
    match advance_cursor_admission(admission) {
      CursorAdmissionContinue => ()
      CursorAdmissionComplete(value, nodes, text) =>
        return Ok((value, nodes, text))
      CursorAdmissionFailed(issue) => return Err(issue)
      CursorAdmissionTerminal => abort("premature canonical admission terminal")
    }
  }
  abort("canonical admission did not terminate")
}

///|
test "indexed canonical admission shares normalization and immutable identity" {
  let source = @source.parse_json_bytes_preserving(
    @utf8.encode(
      (
        #|{"z":[null,2],"e\u0301":{"\ue000":false,"😀":"e\u0301\r\n"}}
      ),
    ),
    { max_input_bytes: 10000, max_nodes: 1000, max_depth: 100, },
  ).unwrap()
  let decoded = @decode.admit(source, {
    max_nodes: 1000,
    max_depth: 100,
    max_string_bytes: 10000,
    max_total_string_bytes: 10000,
  }).unwrap()
  let admission = start_cursor_admission(decoded, 8, 3, 100, 100).unwrap()
  let (value, nodes, text) = complete_cursor(admission).unwrap()
  let expected = "{\"z\":[null,2],\"é\":{\"😀\":\"e\u0301\\r\\n\",\"\ue000\":false}}"
  assert_eq(stringify_value(value, 1000, 100, 10), expected)
  assert_eq((nodes, text), (7, 16))
  assert_eq(
    stringify_value(from_source(source, 8, 3, 100), 1000, 100, 10),
    expected,
  )
  cancel_cursor_admission(admission)
  cancel_cursor_admission(admission)
  assert_true(advance_cursor_admission(admission) is CursorAdmissionTerminal)
  assert_eq(stringify_value(value, 1000, 100, 10), expected)
  assert_eq(@decode.object_length(decoded), Some(2))
}

///|
test "indexed canonical admission refuses collisions and every input budget" {
  let collision = canonical_cursor("{\"é\":1,\"e\\u0301\":2}")
  assert_true(
    complete_cursor(
      start_cursor_admission(collision, 10, 10, 100, 100).unwrap(),
    )
    is Err(DuplicateKey("é")),
  )
  let cursor = canonical_cursor("{\"z\":[null,2],\"a\":\"é\"}")
  for
    (nodes, depth, units, bytes) in [
      (4, 10, 100, 100),
      (100, 1, 100, 100),
      (100, 10, 2, 100),
      (100, 10, 100, 3),
    ] {
    let admission = start_cursor_admission(cursor, nodes, depth, units, bytes).unwrap()
    assert_true(complete_cursor(admission) is Err(InputLimit))
    assert_true(
      admission.pending.is_empty() &&
      admission.root is None &&
      admission.value is None,
    )
  }
  for
    (nodes, depth, units, bytes) in [
      (0, 0, 0, 0),
      (1, -1, 0, 0),
      (1, 0, -1, 0),
      (1, 0, 0, -1),
    ] {
    assert_true(
      start_cursor_admission(cursor, nodes, depth, units, bytes) is None,
    )
  }
}

///|
test "canonical cursor cancellation releases child state not source data" {
  let cursor = canonical_cursor("{\"z\":[null,2],\"a\":{\"d\":[true]}}")
  let saw_sort = Ref(false)
  for stop in 0..<80 {
    let admission = start_cursor_admission(cursor, 100, 10, 100, 100).unwrap()
    for _ in 0..<stop {
      match advance_cursor_admission(admission) {
        CursorAdmissionContinue => ()
        CursorAdmissionComplete(_, _, _) => break
        _ => abort("cancellation fixture refused")
      }
    }
    let saved = admission.pending.copy()
    cancel_cursor_admission(admission)
    cancel_cursor_admission(admission)
    for frame in saved {
      match frame {
        CursorArrayNext(_, values, _, _) | CursorArrayAppend(values) =>
          assert_eq(values.length(), 0)
        CursorObjectSort(_, keys, sort, _) => {
          saw_sort.val = true
          assert_eq(keys.length(), 0)
          assert_true(@sort.index_at(sort, 0) is None)
        }
        CursorObjectNext(_, keys, sort, output, _, _) => {
          saw_sort.val = true
          assert_eq(keys.length(), 0)
          assert_eq(output.length(), 0)
          assert_true(@sort.index_at(sort, 0) is None)
        }
        _ => ()
      }
    }
    assert_eq(@decode.object_length(cursor), Some(2))
  }
  assert_true(saw_sort.val)
}

///|
test "resumed canonical emission writes at most one value node per advance" {
  let value = from_source(
    @source.parse_json("{\"z\":[null,2],\"a\":{\"d\":[true]}}", {
      max_input_bytes: 1000,
      max_nodes: 100,
      max_depth: 10,
    }).unwrap(),
    100,
    10,
    100,
  )
  let writer = @encode.writer(1000, 100, 10)
  let cursor = start_emit(value, writer)
  let mut previous = 0
  let mut steps = 0
  while true {
    let complete = advance_emit(cursor)
    let (_, nodes, _) = @encode.writer_progress(writer)
    assert_true(nodes >= previous && nodes - previous <= 1)
    previous = nodes
    steps += 1
    if complete {
      break
    }
    if steps > 100 {
      abort("canonical emission did not terminate")
    }
  }
  assert_eq(previous, 7)
  assert_true(steps > previous)
  assert_eq(@encode.finish(writer), "{\"a\":{\"d\":[true]},\"z\":[null,2]}")
  cancel_emit(cursor)
  assert_true(advance_emit(cursor))
  let writer = @encode.writer(1000, 100, 10)
  let cursor = start_emit(value, writer)
  assert_false(advance_emit(cursor))
  cancel_emit(cursor)
  assert_true(cursor.pending.is_empty())
  try @encode.finish(writer) catch {
    _ => ()
  } noraise {
    _ => abort("cancelled partial writer finished")
  }
  @encode.cancel_writer(writer)
}

///|
test "canonical emission resumes long keys and Text with visible custody" {
  let key = String::make(256, 'k')
  let text = String::make(4096, 'g')
  let expected = "{\"" + key + "\":[\"" + text + "\",null]}"
  let value = from_source(
    @source.parse_json(expected, {
      max_input_bytes: 10000,
      max_nodes: 10,
      max_depth: 4,
    }).unwrap(),
    10,
    4,
    10000,
  )
  let writer = @encode.writer(expected.length(), 4, 2)
  let cursor = start_emit(value, writer)
  let mut complete = false
  let mut polls = 0
  for _ in 0..<200 {
    let frames = emit_pending_frames(cursor)
    let bytes = @encode.writer_progress(writer).0
    complete = advance_emit(cursor)
    assert_true(emit_pending_frames(cursor) <= frames + 1)
    assert_true(@encode.writer_progress(writer).0 - bytes <= 68)
    polls += 1
    if complete {
      break
    }
  }
  assert_true(complete && polls > 60)
  assert_eq(emit_pending_frames(cursor), 0)
  assert_eq(@encode.finish(writer), expected)
  for cancel_key in [true, false] {
    let writer = @encode.writer(expected.length(), 4, 2)
    let cursor = start_emit(value, writer)
    let mut reached = false
    for _ in 0..<200 {
      assert_false(advance_emit(cursor))
      if (cursor.pending.last() is Some(KeyNext(_)) && cancel_key) ||
        (cursor.pending.last() is Some(TextNext(_)) && !cancel_key) {
        reached = true
        break
      }
    }
    assert_true(reached)
    cancel_emit(cursor)
    assert_eq(emit_pending_frames(cursor), 0)
    cancel_emit(cursor)
    assert_true(advance_emit(cursor))
    try @encode.finish(writer) catch {
      @encode.ClosedWriter => ()
      _ => abort("unexpected cancelled canonical writer issue")
    } noraise {
      _ => abort("unfinished canonical emission finished")
    }
  }
}
