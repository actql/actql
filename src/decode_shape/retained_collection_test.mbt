///|
test "shared retained collection inventory follows original buffer capacity and does not keep retired growth backing" {
  for n in [0, 1, 7, 8, 9, 33, 64] {
    let original : Array[String] = []
    let map : Map[String, String] = Map([])
    for i in 0..<n {
      let value = "k" + i.to_string()
      original.push(value)
      map[value] = value
    }
    let array = reference_array_retained_extent(
      1L,
      original.capacity().to_int64(),
    ).unwrap()
    assert_eq(array.record_headers, 2L)
    assert_eq(array.reference_slots, 1L + original.capacity().to_int64())
    let held = map_retained_extent(
      1L,
      map.capacity().to_int64(),
      map.length().to_int64(),
    ).unwrap()
    let growing = map_construction_extent(1L, n.to_int64()).unwrap()
    assert_true(growing.record_headers >= held.record_headers)
    assert_true(growing.reference_slots >= held.reference_slots)
    assert_true(growing.scalar_words >= held.scalar_words)
  }
  assert_eq(reference_array_retained_extent(-1L, 0L), None)
  assert_eq(map_retained_extent(1L, -1L, 0L), None)
  assert_eq(
    scale_collection_construction_extent(
      { record_headers: 2L, reference_slots: 0L, scalar_words: 0L, },
      9223372036854775807L,
    ),
    None,
  )
}

///|
test "zero multiplicity keeps valid constructor inventory empty without admitting negative units" {
  assert_eq(
    scale_collection_construction_extent(
      { record_headers: 2L, reference_slots: 6L, scalar_words: 0L, },
      0L,
    ),
    Some({ record_headers: 0L, reference_slots: 0L, scalar_words: 0L, }),
  )
  assert_eq(
    scale_collection_construction_extent(
      { record_headers: -1L, reference_slots: 6L, scalar_words: 0L, },
      0L,
    ),
    None,
  )
}
