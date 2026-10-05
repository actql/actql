///|
test "embedded verified documents retain buffered hash bytes and depth" {
  let source = writer(100, 10, 4)
  begin_array(source)
  string_value(source, "é😀")
  end_array(source)
  let document = finish_document(source)
  let target = buffered_hashing_writer(100, 10, 4, 32)
  begin_array(target)
  assert_eq(drain_hash_output(target), "[")
  emit_document(target, document)
  assert_eq(drain_hash_output(target), "[\"é😀\"]")
  end_array(target)
  assert_eq(drain_hash_output(target), "]")
  let (hex, bytes, nodes, depth) = finish_hash_metrics(target)
  assert_eq(hex, @sha256.text_hex("[[\"é😀\"]]").unwrap())
  assert_eq((bytes, nodes, depth), (12, 3, 2))
}

///|
test "drained canonical batches preserve exact text hash and cumulative usage" {
  let w = buffered_hashing_writer(100, 10, 4, 16)
  begin_array(w)
  assert_eq(drain_hash_output(w), "[")
  begin_object(w)
  key(w, "K")
  string_value(w, "é😀")
  end_object(w)
  assert_eq(drain_hash_output(w), "{\"K\":\"é😀\"}")
  null_value(w)
  end_array(w)
  assert_eq(drain_hash_output(w), ",null]")
  assert_eq(drain_hash_output(w), "")
  let (hex, bytes, nodes) = finish_hash_usage(w)
  assert_eq(hex, @sha256.text_hex("[{\"K\":\"é😀\"},null]").unwrap())
  assert_eq(bytes, 21)
  assert_eq(nodes, 4)
  assert_true(
    try {
      ignore(drain_hash_output(w))
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
}

///|
test "draining does not reset total bytes nodes depth or duplicate key checks" {
  for case_ in 0..<4 {
    let w = buffered_hashing_writer(
      if case_ == 0 {
        5
      } else {
        100
      },
      if case_ == 1 {
        1
      } else {
        10
      },
      if case_ == 2 {
        1
      } else {
        4
      },
      32,
    )
    if case_ == 3 {
      begin_object(w)
    } else {
      begin_array(w)
    }
    ignore(drain_hash_output(w))
    assert_true(
      try {
        match case_ {
          0 => {
            null_value(w)
            ignore(drain_hash_output(w))
            end_array(w)
          }
          1 => null_value(w)
          2 => begin_array(w)
          _ => {
            key(w, "x")
            null_value(w)
            ignore(drain_hash_output(w))
            key(w, "x")
          }
        }
        false
      } catch {
        OutputLimit | InvalidStructure => true
        _ => false
      },
    )
    assert_true(
      try {
        ignore(finish_hash(w))
        false
      } catch {
        ClosedWriter => true
        _ => false
      },
    )
  }
}

///|
test "buffer overflow and undrained finalization cannot publish a digest" {
  for size in [0, 1, 5] {
    let w = buffered_hashing_writer(100, 10, 4, size)
    assert_true(
      try {
        string_value(w, "😀")
        false
      } catch {
        OutputLimit => true
        _ => false
      },
    )
    assert_true(
      try {
        ignore(drain_hash_output(w))
        false
      } catch {
        ClosedWriter => true
        _ => false
      },
    )
  }
  let w = buffered_hashing_writer(100, 10, 4, 6)
  string_value(w, "😀")
  assert_true(
    try {
      ignore(finish_hash_usage(w))
      false
    } catch {
      InvalidStructure => true
      _ => false
    },
  )
  let exact = buffered_hashing_writer(6, 1, 0, 6)
  string_value(exact, "😀")
  assert_eq(drain_hash_output(exact), "\"😀\"")
  let (hex, bytes, nodes) = finish_hash_usage(exact)
  assert_eq(hex, @sha256.text_hex("\"😀\"").unwrap())
  assert_eq((bytes, nodes), (6, 1))
}

///|
test "buffered writer cannot complete a previously drained partial document" {
  let w = buffered_hashing_writer(100, 10, 4, 8)
  begin_array(w)
  ignore(drain_hash_output(w))
  assert_true(
    try {
      ignore(finish_hash(w))
      false
    } catch {
      InvalidStructure => true
      _ => false
    },
  )
  assert_true(
    try {
      end_array(w)
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
}

///|
test "discarded batches preserve independent raw Unicode identity and exact encoded batch cap" {
  for cap in [16, 17, 18] {
    let w = buffered_hashing_writer(100, 10, 4, cap, retain_text=false)
    assert_true(w.output is BufferedHashOutput(buffer) && buffer.text is None)
    if cap < 17 {
      assert_true(
        try {
          string_value(w, "é\r\n😀\"\\")
          false
        } catch {
          OutputLimit => true
          _ => false
        },
      )
      assert_true(
        try {
          ignore(finish_hash(w))
          false
        } catch {
          ClosedWriter => true
          _ => false
        },
      )
    } else {
      string_value(w, "é\r\n😀\"\\")
      assert_eq(drain_hash_output(w), "")
      assert_eq(writer_progress(w), (17, 1, 0))
      let (hash, bytes, nodes) = finish_hash_usage(w)
      assert_eq(
        hash, "0049092db04fc092a03b5d747c0d3651adacfa4136c83e2d16c2c2d58d1451e0",
      )
      assert_eq((bytes, nodes), (17, 1))
      let original = writer(100, 10, 4)
      string_value(original, "é\r\n😀\"\\")
      let document = finish_document(original)
      let embedded = buffered_hashing_writer(100, 10, 4, cap, retain_text=false)
      emit_document(embedded, document)
      assert_eq(drain_hash_output(embedded), "")
      assert_eq(finish_hash_usage(embedded), (hash, 17, 1))
    }
  }
}

///|
test "discarded batches still require drain and preserve cumulative limits and cancellation" {
  let pending = buffered_hashing_writer(6, 1, 0, 6, retain_text=false)
  string_value(pending, "😀")
  assert_true(
    try {
      ignore(finish_hash(pending))
      false
    } catch {
      InvalidStructure => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(drain_hash_output(pending))
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
  let limited = buffered_hashing_writer(6, 3, 1, 5, retain_text=false)
  begin_array(limited)
  null_value(limited)
  assert_eq(drain_hash_output(limited), "")
  end_array(limited)
  assert_eq(drain_hash_output(limited), "")
  assert_eq(finish_hash_usage(limited).1, 6)
  let overflow = buffered_hashing_writer(5, 3, 1, 5, retain_text=false)
  begin_array(overflow)
  null_value(overflow)
  assert_eq(drain_hash_output(overflow), "")
  assert_true(
    try {
      end_array(overflow)
      false
    } catch {
      OutputLimit => true
      _ => false
    },
  )
  cancel_writer(overflow)
  cancel_writer(overflow)
  assert_true(
    try {
      ignore(finish_hash(overflow))
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
}
