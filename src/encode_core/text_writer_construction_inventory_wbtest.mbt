///|
test "common constructor controls cover both original closed protocol String exports" {
  // The superseded per-provider fixed-control vectors at6ff5d8b5 cover the
  // complete co-held subject/mutation literal forests. Keep them only as
  // regression minima here, not another production header/reference table.
  // Two actual stringify calls share this existing conservative envelope;
  // operation/row multiplicity and their String backing remain with callers.
  for (nodes, h, r, w) in [(6, 107L, 253L, 162L), (7, 117L, 274L, 179L)] {
    let original = text_writer_construction_inventory(0, nodes, 2).unwrap()
    assert_true(2L * original.record_headers >= h)
    assert_true(2L * original.reference_slots >= r)
    assert_true(2L * original.scalar_words >= w)
  }
}

///|
test "shared frame construction preserves original hash inventory vectors" {
  for
    (keys, depth, h, r, words) in [
      (0, 0, 40L, 43L, 507L),
      (14, 2, 114L, 243L, 735L),
      (100, 7, 503L, 1304L, 1968L),
    ] {
    let original = hash_writer_live_key_inventory(keys, depth).unwrap()
    assert_eq(original.record_headers, h)
    assert_eq(original.reference_slots, r)
    assert_eq(original.scalar_words, words)
    assert_eq(original.owned_utf16_units, 359L)
    assert_eq(original.owned_wire_bytes, 148L)
  }
}

///|
test "text writer inventory binds zero initial storage and finite boundary quantities" {
  let empty = text_writer_construction_inventory(0, 1, 0).unwrap()
  assert_eq(empty, {
    record_headers: 26L,
    reference_slots: 35L,
    scalar_words: 37L,
    owned_utf16_units: 30L,
  })
  for (bytes, utf16) in [(256, 1054L), (257, 1058L), (258, 1061L)] {
    let q = text_writer_construction_inventory(bytes, 14, 2).unwrap()
    assert_eq(q.record_headers, 96L)
    assert_eq(q.reference_slots, 224L)
    assert_eq(q.scalar_words, 252L)
    assert_eq(q.owned_utf16_units, utf16)
  }
  assert_true(text_writer_construction_inventory(-1, 1, 0) is None)
  assert_true(text_writer_construction_inventory(1, 0, 0) is None)
  assert_true(text_writer_construction_inventory(1, 1, -1) is None)
  assert_true(
    text_writer_construction_inventory(2147483647, 2147483647, 2147483647)
    is Some(_),
  )
  let output = writer(0, 1, 0)
  assert_true(
    try {
      null_value(output)
      false
    } catch {
      OutputLimit => true
      _ => false
    },
  )
  assert_true(output.closed)
}

///|
test "original text writer Unicode spans finish and one short retain their own sink" {
  for length in [0, 257, 258] {
    let text = "x".repeat(length) + "é😀\n"
    let expected = "\"" + "x".repeat(length) + "é😀\\n\""
    let bytes = length + 10
    let quantity = text_writer_construction_inventory(bytes, 1, 0).unwrap()
    for cap in [bytes - 1, bytes] {
      let output = writer(cap, 1, 0)
      assert_true(output.output is TextOutput(_))
      let value = try {
        string_value(output, text)
        Some(finish_text_usage(output))
      } catch {
        OutputLimit => None
        _ => abort("original text writer failure changed")
      }
      if cap == bytes {
        let (actual, charged, nodes, depth) = value.unwrap()
        assert_eq(actual, expected)
        assert_eq((charged, nodes, depth), (bytes, 1, 0))
        assert_true(actual.length().to_int64() <= quantity.owned_utf16_units)
      } else {
        assert_true(value is None)
      }
      assert_true(output.closed)
    }
  }
}
