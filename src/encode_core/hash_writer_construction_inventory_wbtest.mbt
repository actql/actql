///|
test "hash writer construction inventory is finite monotone and refuses negative bounds" {
  assert_true(hash_writer_construction_inventory(-1, 0) is None)
  assert_true(hash_writer_construction_inventory(0, -1) is None)
  let empty = hash_writer_construction_inventory(0, 0).unwrap()
  let one = hash_writer_construction_inventory(1, 1).unwrap()
  assert_true(one.record_headers > empty.record_headers)
  assert_true(one.reference_slots > empty.reference_slots)
  assert_true(one.scalar_words > empty.scalar_words)
  assert_eq(one.owned_wire_bytes, empty.owned_wire_bytes)
  assert_eq(one.owned_utf16_units, empty.owned_utf16_units)
  assert_true(
    hash_writer_construction_inventory(2147483647, 2147483647) is Some(_),
  )
}

///|
test "hash writer explicit live key inventory preserves general fallback and depth backing" {
  assert_eq(
    hash_writer_live_key_inventory(140, 10),
    hash_writer_construction_inventory(140, 10),
  )
  let narrow = hash_writer_live_key_inventory(140, 10).unwrap()
  let general = hash_writer_construction_inventory(500308, 10).unwrap()
  assert_eq(
    general.record_headers - narrow.record_headers,
    4L * (500308L - 140L),
  )
  assert_eq(
    general.reference_slots - narrow.reference_slots,
    11L * (500308L - 140L),
  )
  assert_eq(general.scalar_words - narrow.scalar_words, 13L * (500308L - 140L))
  assert_true(
    hash_writer_live_key_inventory(0, 10).unwrap().record_headers >
    hash_writer_live_key_inventory(0, 0).unwrap().record_headers,
  )
  assert_true(hash_writer_live_key_inventory(-1, 10) is None)
}

///|
test "actual hashing object keys use the shared linked Map construction owner" {
  // Fourteen keys cross the pinned Map's initial and next growth thresholds.
  // Inspect the original writer's own live Map, not a second input traversal.
  let output = hashing_writer(4096, 32, 2)
  begin_object(output)
  for i in 0..<14 {
    key(output, "key-" + i.to_string())
    null_value(output)
  }
  let keys = match output.frames[0] {
    ObjectKey(false, keys) => keys.length()
    _ => abort("original object key frame required")
  }
  assert_eq(keys, 14)
  let empty = hash_writer_live_key_inventory(0, 1).unwrap()
  let populated = hash_writer_live_key_inventory(keys, 1).unwrap()
  let map_empty = @shape.map_construction_extent(1L, 0L).unwrap()
  let map_populated = @shape.map_construction_extent(1L, keys.to_int64()).unwrap()
  assert_eq(
    populated.record_headers - empty.record_headers,
    map_populated.record_headers - map_empty.record_headers,
  )
  assert_eq(
    populated.reference_slots - empty.reference_slots,
    map_populated.reference_slots - map_empty.reference_slots,
  )
  assert_eq(
    populated.scalar_words - empty.scalar_words,
    map_populated.scalar_words - map_empty.scalar_words,
  )
  end_object(output)
  let (_, _, nodes, depth) = finish_hash_metrics(output)
  assert_eq(nodes, keys + 1)
  assert_eq(depth, 1)
}

///|
test "nested hashing writer Maps preserve depth growth and borrowed original keys" {
  let output = hashing_writer(4096, 32, 3)
  begin_object(output)
  key(output, "outer")
  begin_object(output)
  key(output, "inner")
  null_value(output)
  assert_eq(output.frames.length(), 2)
  let mut entries = 0
  for frame in output.frames {
    match frame {
      ObjectKey(_, keys) | ObjectValue(keys) => entries += keys.length()
      _ => abort("original nested object frame required")
    }
  }
  assert_eq(entries, 2)
  let one = hash_writer_live_key_inventory(entries, 1).unwrap()
  let two = hash_writer_live_key_inventory(entries, 2).unwrap()
  let one_map = @shape.map_construction_extent(1L, 2L).unwrap()
  let two_maps = @shape.map_construction_extent(2L, 2L).unwrap()
  // An additional depth also retains Frame/Some2H2R2W and three growing
  // frame-array reference slots. Input key strings remain borrowed.
  assert_eq(
    two.record_headers - one.record_headers,
    two_maps.record_headers - one_map.record_headers + 2L,
  )
  assert_eq(
    two.reference_slots - one.reference_slots,
    two_maps.reference_slots - one_map.reference_slots + 5L,
  )
  assert_eq(
    two.scalar_words - one.scalar_words,
    two_maps.scalar_words - one_map.scalar_words + 2L,
  )
  assert_eq(two.owned_utf16_units, one.owned_utf16_units)
  assert_eq(two.owned_wire_bytes, one.owned_wire_bytes)
  end_object(output)
  end_object(output)
  let (_, _, nodes, depth) = finish_hash_metrics(output)
  assert_eq(nodes, 3)
  assert_eq(depth, 2)
}
