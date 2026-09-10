///|
test "hash sink shares text emission embedding and exact admission" {
  let text = writer(10000, 100, 8)
  measurement_fixture(text)
  let document = finish_document(text)
  let baseline = @sha256.text_hex(document_text(document)).unwrap()
  let size = document_bytes(document)
  for cap in [size - 1, size, size + 1] {
    for nodes in [1, 5, 6, 100] {
      for depth in [0, 1, 2, 8] {
        let expected = try {
          let w = writer(cap, nodes, depth)
          measurement_fixture(w)
          Some(@sha256.text_hex(finish(w)).unwrap())
        } catch {
          _ => None
        }
        let w = hashing_writer(cap, nodes, depth)
        let actual = try {
          measurement_fixture(w)
          Some(finish_hash(w))
        } catch {
          _ => None
        }
        assert_eq(actual, expected)
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
  }
  let embedded = hashing_writer(size, 100, 8)
  emit_document(embedded, document)
  assert_eq(finish_hash(embedded), baseline)
  assert_true(embedded.output is HashOutput(_))
}

///|
test "hash sink never exposes incomplete or failed output" {
  for case_ in [0, 1, 2, 3, 4] {
    let w = hashing_writer(100, 10, 4)
    let result = try {
      match case_ {
        0 => begin_array(w)
        1 => string_value(w, "😀".unsafe_substring(start=0, end=1))
        2 => number_value(w, -0.0)
        3 => {
          null_value(w)
          null_value(w)
        }
        _ => {
          begin_object(w)
          key(w, "a")
          null_value(w)
          key(w, "a")
        }
      }
      ignore(finish_hash(w))
      false
    } catch {
      _ => true
    }
    assert_true(result)
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
  let h = hashing_writer(4, 1, 0)
  null_value(h)
  assert_true(
    try {
      ignore(finish(h))
      false
    } catch {
      InvalidStructure => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(finish_hash(h))
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
  let t = writer(4, 1, 0)
  null_value(t)
  assert_true(
    try {
      ignore(finish_hash(t))
      false
    } catch {
      InvalidStructure => true
      _ => false
    },
  )
  assert_true(
    try {
      ignore(finish(t))
      false
    } catch {
      ClosedWriter => true
      _ => false
    },
  )
}
