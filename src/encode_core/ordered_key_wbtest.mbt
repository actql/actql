///|
test "ordered key cursor uses existing sinks escaping and exact output limits" {
  let name = String::make(63, 'a') + "😀\n\"\\\u0001"
  let expected = "{\"" +
    String::make(63, 'a') +
    "😀\\n\\\"\\\\\\u0001\":null}"
  // The quoted key is 81 bytes, colon/null and braces add seven: 88.
  for sink in 0..<4 {
    let writer = match sink {
      0 => writer(88, 2, 1)
      1 => measuring_writer(88, 2, 1)
      2 => hashing_writer(88, 2, 1)
      _ => buffered_hashing_writer(88, 2, 1, 70)
    }
    begin_ordered_object(writer)
    let key = start_ordered_key(writer, name)
    let pieces : Array[String] = []
    if sink == 3 {
      pieces.push(drain_hash_output(writer))
    }
    let mut done = false
    for _ in 0..<20 {
      done = advance_ordered_key(key)
      if sink == 3 {
        pieces.push(drain_hash_output(writer))
      }
      if done {
        break
      }
    }
    assert_true(done)
    cancel_ordered_key(key)
    null_value(writer)
    end_object(writer)
    if sink == 3 {
      pieces.push(drain_hash_output(writer))
      assert_eq(pieces.join(""), expected)
    }
    match sink {
      0 => assert_eq(finish_text_usage(writer), (expected, 88, 2, 1))
      1 => assert_eq(finish_measurement_usage(writer), (88, 2, 1))
      _ =>
        assert_eq(
          finish_hash_metrics(writer),
          (@sha256.text_hex(expected).unwrap(), 88, 2, 1),
        )
    }
  }
  let short = measuring_writer(87, 2, 1)
  assert_true(
    try {
      begin_ordered_object(short)
      ordered_key(short, name)
      null_value(short)
      end_object(short)
      false
    } catch {
      OutputLimit => true
      _ => false
    },
  )
  assert_true(short.closed)
}

///|
test "ordered keys reject duplicate reversed and prefix keys across resumes" {
  let prefix = String::make(4096, 'k')
  for
    (first, second, accepted) in [
      (prefix, prefix, false),
      (prefix + "b", prefix + "a", false),
      (prefix + "a", prefix, false),
      (prefix, prefix + "a", true),
      (prefix + "😀", prefix + "\u{e000}", true),
      (prefix + "\u{e000}", prefix + "😀", false),
    ] {
    let w = writer(20000, 3, 1)
    begin_ordered_object(w)
    ordered_key(w, first)
    null_value(w)
    let progress = writer_progress(w).0
    let cursor = start_ordered_key(w, second)
    assert_false(advance_ordered_key(cursor))
    assert_eq(writer_progress(w).0, progress)
    assert_eq(cursor.position, 64)
    let mut polls = 1
    let result = try {
      while !advance_ordered_key(cursor) {
        polls += 1
        if polls > 200 {
          abort("ordered key did not terminate")
        }
      }
      true
    } catch {
      InvalidStructure => false
      _ => abort("unexpected key failure")
    }
    assert_eq(result, accepted)
    assert_true(polls >= 64)
    if accepted {
      null_value(w)
      end_object(w)
      assert_eq(finish(w), "{\"" + first + "\":null,\"" + second + "\":null}")
    } else {
      assert_true(w.closed)
    }
  }
}

///|
test "unfinished ordered key forbids interleaving and cancels the writer" {
  for misuse in 0..<5 {
    let w = writer(1000, 10, 3)
    begin_ordered_object(w)
    let cursor = start_ordered_key(w, String::make(256, 'k'))
    assert_false(advance_ordered_key(cursor))
    assert_false(advance_ordered_key(cursor))
    assert_false(advance_ordered_key(cursor))
    assert_true(
      try {
        match misuse {
          0 => null_value(w)
          1 => end_object(w)
          2 => finish(w) |> ignore
          3 => start_ordered_key(w, "other") |> ignore
          _ => key(w, "other")
        }
        false
      } catch {
        InvalidStructure => true
        _ => false
      },
    )
    cancel_ordered_key(cursor)
    cancel_ordered_key(cursor)
    assert_eq(w.frames.length(), 0)
    assert_true(
      try {
        finish(w) |> ignore
        false
      } catch {
        ClosedWriter => true
        _ => false
      },
    )
  }
  let w = writer(1000, 10, 3)
  begin_ordered_object(w)
  let cursor = start_ordered_key(w, String::make(256, 'k'))
  assert_false(advance_ordered_key(cursor))
  cancel_ordered_key(cursor)
  assert_true(
    try {
      advance_ordered_key(cursor) |> ignore
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
  let generic = writer(100, 10, 1)
  begin_object(generic)
  assert_true(
    try {
      start_ordered_key(generic, "a") |> ignore
      false
    } catch {
      InvalidStructure => true
      _ => false
    },
  )
}

///|
test "ordered key keeps malformed Unicode and output failure priority" {
  let malformed = String::make(65, 'a') +
    String::from_array([(0xd800).unsafe_to_char()])
  for (bytes, expected) in [(100, 0), (65, 1)] {
    let w = writer(bytes, 2, 1)
    begin_ordered_object(w)
    let result = try {
      ordered_key(w, malformed)
      -1
    } catch {
      InvalidUnicode => 0
      OutputLimit => 1
      _ => 2
    }
    assert_eq(result, expected)
    assert_true(w.closed)
  }
}
