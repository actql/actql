///|
test "private ciphertext construction follows exact AEAD envelope geometry without funding a quota" {
  // Independent fixed ASCII envelope (version, nonce16, tag24, empty cipher)
  // is128 bytes. RFC4648 groups three plaintext bytes into four cipher chars.
  for
    (plain, expected) in [
      (1, 132),
      (2, 132),
      (3, 132),
      (4, 136),
      (1048576, 1398232),
    ] {
    let quote = private_evidence_custody_construction(plain).unwrap()
    assert_eq(quote.envelope_bytes, expected)
    assert_true(quote.retained.owned_wire_bytes >= expected.to_int64() + 32L)
    assert_true(quote.workspace.owned_wire_bytes >= plain.to_int64())
  }
  assert_true(private_evidence_custody_construction(0) is None)
  assert_true(private_evidence_custody_construction(-1) is None)
  assert_true(private_evidence_custody_construction(1048577) is None)
  assert_eq(
    private_evidence_custody_wire_construction("日").unwrap().envelope_bytes,
    132,
  )
  assert_eq(
    private_evidence_custody_wire_construction("日日").unwrap().envelope_bytes,
    136,
  )
}

///|
test "observed ciphertext above the plaintext limit uses the existing envelope law" {
  // Independent existing AES-GCM/Base64 boundary: 128 + 4*ceil(1MiB/3).
  let largest = private_evidence_envelope_construction(1398232L).unwrap()
  assert_eq(largest.envelope_bytes, 1398232)
  assert_true(largest.workspace.owned_wire_bytes >= 1398232L)
  assert_true(private_evidence_envelope_construction(1048577L) is Some(_))
  assert_true(private_evidence_envelope_construction(1398233L) is None)
  assert_true(private_evidence_envelope_construction(0L) is None)
  assert_true(private_evidence_envelope_construction(-1L) is None)
  // This read quote does not change the original plaintext admission limit.
  assert_true(private_evidence_custody_construction(1048577) is None)
}

///|
test "private envelope mixed JSON construction covers scalar container field and malformed prefix families" {
  // Independent grammar families under the unchanged pinned JSON parser.
  // Tuple: input bytes, values, arrays, maps, fields, array items.
  let families = [
    (1L, 1L, 0L, 0L, 0L, 0L), // 0
    (2L, 1L, 1L, 0L, 0L, 0L), // []
    (2L, 1L, 0L, 1L, 0L, 0L), // {}
    (11L, 4L, 2L, 1L, 1L, 2L), // [{"": [0]}]
    (2049L, 1025L, 1024L, 0L, 0L, 1024L), // nested arrays
    (1024L, 1024L, 1024L, 0L, 0L, 1023L), // unclosed depth frontier
    (2001L, 1001L, 1L, 0L, 0L, 1000L), // dense scalar Array
    (3001L, 1001L, 1L, 1000L, 0L, 1000L), // Array of empty Maps
    (5001L, 1001L, 0L, 1L, 1000L, 0L), // repeated shortest object key
    (5001L, 1001L, 0L, 1000L, 1000L, 0L), // nested object fields
  ]
  for (bytes, values, arrays, maps, fields, items) in families {
    let actual = @shape.collection_construction_extent({
      records: 4L * values + 2L * fields + 16L,
      record_references: 6L * values + 2L * fields + 32L,
      record_words: 4L * values + fields + 16L,
      reference_arrays: arrays,
      reference_items: items,
      scalar_arrays: 0L,
      scalar_items: 0L,
      maps,
      map_entries: fields,
    }).unwrap()
    let bound = private_evidence_json_construction_extent(bytes).unwrap()
    assert_true(bound.record_headers >= actual.record_headers)
    assert_true(bound.reference_slots >= actual.reference_slots)
    assert_true(bound.scalar_words >= actual.scalar_words)
  }
  assert_true(private_evidence_json_construction_extent(0L) is None)
  assert_true(private_evidence_json_construction_extent(1398273L) is None)
}

///|
test "private envelope mixed containers use one grammar constrained construction peak" {
  // An Array of 1000 empty Maps is 3001 bytes, not 1501 independent
  // Map/value pairs. The independent shared constructor expansion for every
  // grammar mixture fits 11H/33R/25W per three syntax bytes, plus at most
  // 1024 unfinished containers and the final token/key frontier.
  let bound = private_evidence_json_construction_extent(3001L).unwrap()
  assert_true(bound.record_headers <= 14800L)
  assert_true(bound.reference_slots <= 44384L)
  assert_true(bound.scalar_words <= 33616L)
  // Enumerate independent tree inventories, including nonempty Arrays,
  // object fields, duplicate keys, and mixed-container branching. Every
  // nonempty Map needs a field, every nonempty Array an item.
  for values in 1L..<33L {
    for maps in 0L..<=values {
      for arrays in 0L..<=(values - maps) {
        for fields in 0L..<values {
          let items = values - fields - 1L
          if (fields > 0L && maps == 0L) || (items > 0L && arrays == 0L) {
            continue
          }
          let nonempty = Int64::min(maps, fields) + Int64::min(arrays, items)
          let bytes = 2L * values + arrays + maps + 3L * fields - nonempty - 1L
          if bytes < 1L {
            continue
          }
          let actual = @shape.collection_construction_extent({
            records: 4L * values + 2L * fields + 16L,
            record_references: 6L * values + 2L * fields + 32L,
            record_words: 4L * values + fields + 16L,
            reference_arrays: arrays,
            reference_items: items,
            scalar_arrays: 0L,
            scalar_items: 0L,
            maps,
            map_entries: fields,
          }).unwrap()
          let quoted = private_evidence_json_construction_extent(bytes).unwrap()
          assert_true(quoted.record_headers >= actual.record_headers)
          assert_true(quoted.reference_slots >= actual.reference_slots)
          assert_true(quoted.scalar_words >= actual.scalar_words)
        }
      }
    }
  }
}
