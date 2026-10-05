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
