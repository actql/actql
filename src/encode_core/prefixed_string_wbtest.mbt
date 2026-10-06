///|
test "prefixed string borrows segments and preserves independent sink bytes" {
  let prefix = "left."
  let text = String::make(58, 'a') + "😀\n\"\\\u0001"
  let expected = "\"left." + String::make(58, 'a') + "😀\\n\\\"\\\\\\u0001\""
  // 63 ASCII, four emoji bytes, 2+2+2+6 escaped bytes and two quotes.
  for sink in 0..<4 {
    let w = match sink {
      0 => writer(81, 1, 0)
      1 => measuring_writer(81, 1, 0)
      2 => hashing_writer(81, 1, 0)
      _ => buffered_hashing_writer(81, 1, 0, 70)
    }
    let cursor = start_prefixed_string_value(w, prefix, text)
    assert_eq(cursor.prefix, prefix)
    assert_eq(cursor.text, text)
    assert_eq(cursor.position, 0)
    let fragments : Array[String] = []
    if sink == 3 {
      fragments.push(drain_hash_output(w))
    }
    assert_false(advance_string_value(cursor))
    assert_eq(cursor.position, 65)
    assert_eq(writer_progress(w), (68, 1, 0))
    if sink == 3 {
      fragments.push(drain_hash_output(w))
    }
    assert_true(advance_string_value(cursor))
    if sink == 3 {
      fragments.push(drain_hash_output(w))
      assert_eq(fragments.join(""), expected)
    }
    cancel_string_value(cursor)
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
test "prefixed string treats segment and poll boundaries as one scalar stream" {
  let high = String::from_array([(0xd83d).unsafe_to_char()])
  let low = String::from_array([(0xde00).unsafe_to_char()])
  for
    (prefix, text, expected, bytes, polls) in [
      (high, low, "\"😀\"", 6, 1),
      (
        String::make(63, 'a') + high,
        low,
        "\"" + String::make(63, 'a') + "😀\"",
        69,
        1,
      ),
      (
        String::make(64, 'a') + high,
        low,
        "\"" + String::make(64, 'a') + "😀\"",
        70,
        2,
      ),
      ("", "", "\"\"", 2, 1),
      ("left.", "", "\"left.\"", 7, 1),
    ] {
    let w = writer(bytes, 1, 0)
    let cursor = start_prefixed_string_value(w, prefix, text)
    for poll in 1..<=polls {
      assert_eq(advance_string_value(cursor), poll == polls)
    }
    assert_eq(finish_text_usage(w), (expected, bytes, 1, 0))
  }
}

///|
test "prefixed string keeps exact limits and Unicode refusal precedence" {
  let high = String::from_array([(0xd800).unsafe_to_char()])
  let low = String::from_array([(0xdc00).unsafe_to_char()])
  for
    (prefix, text, bytes, unicode) in [
      ("left.", String::make(65, 'a'), 71, false),
      (String::make(64, 'a'), high, 65, true),
      (String::make(65, 'a'), high, 65, false),
      (high, "a", 100, true),
      ("left.", low, 100, true),
    ] {
    let w = measuring_writer(bytes, 1, 0)
    let cursor = start_prefixed_string_value(w, prefix, text)
    let failed = try {
      for _ in 0..<4 {
        if advance_string_value(cursor) {
          break
        }
      }
      false
    } catch {
      InvalidUnicode => unicode
      OutputLimit => !unicode
      _ => false
    }
    assert_true(failed)
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
  let exact = measuring_writer(72, 1, 0)
  let cursor = start_prefixed_string_value(
    exact,
    "left.",
    String::make(65, 'a'),
  )
  assert_false(advance_string_value(cursor))
  assert_true(advance_string_value(cursor))
  assert_eq(finish_measurement_usage(exact), (72, 1, 0))
}

///|
test "prefixed string cancellation retains exclusive writer custody" {
  let text = String::make(1000, 'x')
  let w = measuring_writer(2000, 3, 1)
  begin_array(w)
  let cursor = start_prefixed_string_value(w, "right.", text)
  assert_eq(cursor.text.length(), 1000)
  assert_eq(cursor.prefix, "right.")
  assert_false(advance_string_value(cursor))
  assert_eq(cursor.position, 64)
  assert_true(
    try {
      end_array(w)
      false
    } catch {
      InvalidStructure => true
      _ => false
    },
  )
  cancel_string_value(cursor)
  cancel_string_value(cursor)
  assert_true(w.closed)
  assert_true(w.frames.is_empty())
  assert_true(
    try {
      advance_string_value(cursor) |> ignore
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
}
