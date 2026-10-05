///|
test "stepped string preserves independent escaped text and sink budgets" {
  let prefix = String::make(63, 'a')
  let text = prefix + "😀\n\"\\\u0001"
  let expected = "\"" + prefix + "😀\\n\\\"\\\\\\u0001\""
  // 63 ASCII + 4 emoji + 2 newline + 2 quote + 2 backslash + 6 control
  // bytes, plus two quotes: 81 bytes and one scalar node, depth zero.
  for sink in 0..<4 {
    let w = match sink {
      0 => writer(81, 1, 0)
      1 => measuring_writer(81, 1, 0)
      2 => hashing_writer(81, 1, 0)
      _ => buffered_hashing_writer(81, 1, 0, 70)
    }
    let cursor = start_string_value(w, text)
    let pieces : Array[String] = []
    if sink == 3 {
      pieces.push(drain_hash_output(w))
    }
    assert_false(advance_string_value(cursor))
    assert_eq(cursor.position, 65) // Do not split the crossing pair.
    assert_eq(writer_progress(w), (68, 1, 0))
    if sink == 3 {
      pieces.push(drain_hash_output(w))
    }
    assert_true(advance_string_value(cursor))
    if sink == 3 {
      pieces.push(drain_hash_output(w))
      assert_eq(pieces.join(""), expected)
    }
    cancel_string_value(cursor) // Completed custody is already transferred.
    match sink {
      0 => assert_eq(finish_text_usage(w), (expected, 81, 1, 0))
      1 => assert_eq(finish_measurement_usage(w), (81, 1, 0))
      _ =>
        assert_eq(
          finish_hash_metrics(w),
          (@sha256.text_hex(expected).unwrap(), 81, 1, 0),
        )
    }
  }
}

///|
test "stepped string keeps exact one-short and Unicode failure priority" {
  for
    (text, cap, error) in [
      (String::make(65, 'a'), 66, OutputLimit),
      (
        String::make(64, 'a') + String::from_array([(0xd800).unsafe_to_char()]),
        65,
        InvalidUnicode,
      ),
      (
        String::make(65, 'a') + String::from_array([(0xd800).unsafe_to_char()]),
        65,
        OutputLimit,
      ),
    ] {
    let w = writer(cap, 1, 0)
    let cursor = start_string_value(w, text)
    let failure = try {
      while !advance_string_value(cursor) {
        ()
      }
      None
    } catch {
      issue => Some(issue)
    }
    assert_true(
      match (failure, error) {
        (Some(OutputLimit), OutputLimit)
        | (Some(InvalidUnicode), InvalidUnicode) => true
        _ => false
      },
    )
    assert_true(
      try {
        finish(w) |> ignore
        false
      } catch {
        ClosedWriter => true
        _ => false
      },
    )
    cancel_string_value(cursor)
  }
  let exact = measuring_writer(67, 1, 0)
  let cursor = start_string_value(exact, String::make(65, 'a'))
  assert_false(advance_string_value(cursor))
  assert_true(advance_string_value(cursor))
  assert_eq(finish_measurement(exact), 67)
}

///|
test "unfinished string rejects interleaving and finalization" {
  for misuse in 0..<4 {
    let w = writer(1000, 10, 2)
    begin_array(w)
    let cursor = start_string_value(w, String::make(100, 'a'))
    assert_false(advance_string_value(cursor))
    assert_true(
      try {
        match misuse {
          0 => null_value(w)
          1 => end_array(w)
          2 => finish(w) |> ignore
          _ => start_string_value(w, "other") |> ignore
        }
        false
      } catch {
        InvalidStructure => true
        _ => false
      },
    )
    cancel_string_value(cursor)
  }
}

///|
test "cancelled string cannot publish and completed cursor cannot replay" {
  let w = writer(1000, 10, 2)
  begin_array(w)
  let cursor = start_string_value(w, String::make(100, 'a'))
  assert_false(advance_string_value(cursor))
  cancel_string_value(cursor)
  cancel_string_value(cursor)
  assert_true(w.closed)
  assert_true(w.frames.is_empty())
  let done = writer(100, 3, 1)
  begin_array(done)
  let cursor = start_string_value(done, "x")
  assert_true(advance_string_value(cursor))
  assert_true(
    try {
      advance_string_value(cursor) |> ignore
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
  number_value(done, 2.0)
  end_array(done)
  assert_eq(finish(done), "[\"x\",2]")
}
